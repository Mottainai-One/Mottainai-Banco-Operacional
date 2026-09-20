# Documentação concreta do banco analítico Mottainai

**Versão:** 2026-09-20
**Database:** `mottainai_analytics`
**Schema:** `mottainai_analytics`
**Finalidade:** sustentar BI, histórico, indicadores, previsões e recomendações sem disputar recursos com o banco operacional.

## Decisão de arquitetura

O banco analítico recebe somente transações confirmadas. Ele organiza atributos em dimensões e medidas em fatos, registra a ingestão idempotente e mantém objetos de IA. Não existem FKs, `dblink` ou escrita SQL direta entre databases; IDs operacionais são chaves de correlação.

Os scripts instaláveis ficam exclusivamente em `database/analytics`. Esta documentação fica fora da pasta de scripts e serve como contrato para pipelines, dashboards e APIs de consulta.

## Aderência aos requisitos das disciplinas

| Disciplina | Evidência implementada | Situação |
|---|---|---|
| Business Intelligence | Modelo estrela, dimensão calendário, fatos, snapshots, KPIs, views e cargas incrementais | Atende |
| Modelagem de dados | Grão documentado, chaves de negócio, dimensões conformadas e separação entre fatos e dimensões | Atende |
| Desenvolvimento operacional | Inbox idempotente, checkpoint, dead letter, logs de job e contratos de recomendação | Atende a integração |
| RF01-RF03 | Views de vendas, produtos, perdas, ticket e dashboard executivo | Atende a camada de dados |
| RF06-RF11 | Histórico de estoque/venda, modelos, previsões, recomendações, feedback e métricas | Atende |
| RF13 | Dados de fluxo por loja para recomendação de transferência | Atende |
| RF16 | Histórico de custo, venda e preço para análises de margem/precificação | Atende como insumo |
| ODS 12.3, 12.5 e 12.6 | Fato de perdas, destino, perda evitada e métricas executivas | Atende a mensuração |

O arquivo local chamado “Atividade de BI” não contém a rubrica do projeto Mottainai. A avaliação acima usa os requisitos funcionais fornecidos e critérios gerais de BI; deve ser reconciliada com a rubrica oficial quando ela for disponibilizada.

## Grão do modelo

- `fact_sales`: uma venda por data.
- `fact_sale_item`: um item de venda por data.
- `fact_inventory_movement`: um movimento de estoque por data.
- `fact_inventory_snapshot`: uma posição diária por loja, produto, lote e tipo de estoque.
- `fact_purchase_order`: um pedido por data.
- `fact_receiving`: um recebimento.
- `fact_promotion_result`: uma promoção por loja, produto e dia.
- `fact_loss_destination`: uma destinação de perda.
- `fact_transfer`: uma transferência.
- `fact_replenishment`: uma reposição.
- `fact_loyalty`: um evento de pontos.

Dimensões usam atualização tipo 1 nesta primeira versão. Quando o histórico de atributo for necessário, deve ser criada uma chave substituta e vigência tipo 2, sem mudar silenciosamente o grão atual.

## Particionamento mensal

As quatro tabelas com maior crescimento recebem partições mensais: `fact_sales`, `fact_sale_item`, `fact_inventory_movement` e `fact_inventory_snapshot`. São criados 12 meses anteriores, o mês atual e 6 futuros, além de uma partição default para impedir perda de carga.

Tabelas de menor volume não são particionadas nesta fase. Essa escolha reduz planejamento, manutenção e partições vazias. A decisão deve ser revista por métricas de volume e tempo de consulta, não apenas pelo tamanho do calendário.

Queries de dashboard precisam filtrar a chave de partição diretamente. Evitar funções sobre a coluna no predicado, como `date_trunc('month', sale_date)`, quando um intervalo puder ser usado.

## Fluxo de integração

```text
event_queue operacional
        |
        v
ingestion_event -> validação da versão -> dimensões -> fatos -> checkpoint
        |                                      |
        +-> etl_dead_letter                    +-> views e KPIs
                                                       |
                                                       v
                                               modelos e recomendações
                                                       |
                                                       v
                                      API -> suggested_action operacional
```

`event_uuid` garante deduplicação. O checkpoint só avança depois do commit das dimensões e fatos. Replay usa o mesmo UUID. Payload inválido ou versão incompatível segue para dead letter com erro explícito.

## Rotas sugeridas para API e BI

| Recurso | Rotas principais | Objetos |
|---|---|---|
| Dashboard | `GET /analytics/dashboard?companyId=&from=&to=` | `vw_executive_dashboard` |
| Vendas | `GET /analytics/sales/daily`, `GET /analytics/products/top` | `vw_sales_daily_kpis`, `vw_top_selling_products` |
| Estoque | `GET /analytics/inventory/current`, `GET /analytics/inventory/stockout-risk` | `vw_inventory_snapshot_current`, `vw_stockout_analysis` |
| Sustentabilidade | `GET /analytics/losses`, `GET /analytics/avoided-losses` | `fact_loss_destination`, `fact_promotion_result` |
| IA | `GET /analytics/models/performance`, `GET /recommendations`, `POST /recommendations/{id}/feedback` | `vw_ai_performance`, `ai_*` |
| Motor | `GET /engine/suggestions`, `POST /engine/scans` | `engine_scan_log`, `engine_suggestion` |
| Fidelidade | `GET /analytics/customers/{anonymousKey}/loyalty` | `vw_customer_loyalty_analysis` |

Dashboards usam usuário somente leitura e consultam views. Payloads de ingestão e features de modelos não devem ser expostos diretamente.

## Privacidade e qualidade

- `dim_customer` não contém CPF, nome, e-mail ou telefone.
- `anonymous_key` é o identificador de exposição analítica.
- `dim_employee` não replica CPF.
- Cada fato tem grão explícito para impedir duplicidade de medidas.
- Reconciliação diária compara quantidade e valor de vendas por loja/data com o operacional.
- Snapshots devem fechar com o saldo do estoque operacional.
- Modelos registram versão, parâmetros, execução, confiança e feedback.

## Instalação e manutenção

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_analytics \
  -f database/analytics/install.sql
```

Mensalmente, antes da virada:

```sql
SELECT mottainai_analytics.sp_create_monthly_fact_partitions(12, 6);
```

Monitorar linhas nas partições `*_default`; presença de dados indica atraso na criação mensal ou data fora da janela esperada.

## Dicionário de dados

O catálogo abaixo é gerado a partir dos scripts desta versão. As relações entre dimensões e fatos usam IDs de correlação e são deliberadamente sem FK para não acoplar a disponibilidade da carga.

### `ai_execution`

**Por que existe:** Registra execução e falha do modelo.

**Relacionamentos:** ai_model(model_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `execution_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `model_id` | `BIGINT NOT NULL REFERENCES ai_model(model_id)` | Identificador ou chave de correlação. |
| `started_at` | `TIMESTAMPTZ NOT NULL` | Data e hora usada para auditoria ou processamento. |
| `finished_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `status` | `job_status NOT NULL DEFAULT 'RUNNING'` | Estado atual do ciclo de vida. |
| `input_rows` | `BIGINT` | Atributo do domínio desta entidade. |
| `output_rows` | `BIGINT` | Atributo do domínio desta entidade. |
| `error_message` | `TEXT` | Atributo do domínio desta entidade. |
| `metadata` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |

### `ai_feedback`

**Por que existe:** Registra decisão humana e resultado.

**Relacionamentos:** ai_recommendation(recommendation_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `feedback_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `recommendation_id` | `BIGINT NOT NULL REFERENCES ai_recommendation(recommendation_id)` | Identificador ou chave de correlação. |
| `source_user_id` | `BIGINT` | Identificador ou chave de correlação. |
| `decision` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `reason` | `TEXT` | Atributo do domínio desta entidade. |
| `outcome` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `ai_model`

**Por que existe:** Versiona modelos e parâmetros.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `model_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `model_type` | `ai_model_type NOT NULL` | Atributo do domínio desta entidade. |
| `version` | `VARCHAR(50) NOT NULL` | Versão para evolução ou concorrência otimista. |
| `parameters` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `metrics` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `trained_at` | `TIMESTAMPTZ` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `ai_prediction`

**Por que existe:** Registra previsão e explicação.

**Relacionamentos:** ai_model(model_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `prediction_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `prediction_uuid` | `UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE` | Atributo do domínio desta entidade. |
| `model_id` | `BIGINT NOT NULL REFERENCES ai_model(model_id)` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `prediction_type` | `VARCHAR(80) NOT NULL` | Atributo do domínio desta entidade. |
| `prediction_value` | `NUMERIC(18,6)` | Valor monetário ou medida financeira. |
| `confidence` | `NUMERIC(6,5) CHECK (confidence BETWEEN 0 AND 1)` | Atributo do domínio desta entidade. |
| `horizon_date` | `DATE` | Data de negócio e possível filtro temporal. |
| `input_features` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `explanation` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `predicted_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `ai_recommendation`

**Por que existe:** Registra recomendação acionável.

**Relacionamentos:** ai_prediction(prediction_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `recommendation_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `recommendation_uuid` | `UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE` | Atributo do domínio desta entidade. |
| `prediction_id` | `BIGINT REFERENCES ai_prediction(prediction_id)` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `action_type` | `suggested_action_type NOT NULL` | Atributo do domínio desta entidade. |
| `priority` | `priority_level NOT NULL DEFAULT 'MEDIUM'` | Atributo do domínio desta entidade. |
| `status` | `suggested_action_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `title` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `rationale` | `TEXT` | Atributo do domínio desta entidade. |
| `proposed_values` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Valor monetário ou medida financeira. |
| `estimated_impact` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `operational_action_id` | `BIGINT` | Identificador ou chave de correlação. |
| `valid_until` | `TIMESTAMPTZ` | Atributo do domínio desta entidade. |
| `accepted_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `executed_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_category`

**Por que existe:** Descreve a categoria do produto.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `category_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `parent_category_id` | `BIGINT` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_company`

**Por que existe:** Descreve a empresa sem depender do OLTP.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `company_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `plan_id` | `BIGINT` | Identificador ou chave de correlação. |
| `legal_name` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `trade_name` | `VARCHAR(255)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_customer`

**Por que existe:** Pseudonimiza o cliente para análises.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `customer_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `anonymous_key` | `UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE` | Atributo do domínio desta entidade. |
| `birth_year` | `SMALLINT` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `marketing_consent` | `BOOLEAN NOT NULL DEFAULT false` | Atributo do domínio desta entidade. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_date`

**Por que existe:** Fornece calendário conformado.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `date_key` | `DATE PRIMARY KEY` | Data de negócio e possível filtro temporal. |
| `year_number` | `SMALLINT NOT NULL` | Atributo do domínio desta entidade. |
| `quarter_number` | `SMALLINT NOT NULL CHECK (quarter_number BETWEEN 1 AND 4)` | Atributo do domínio desta entidade. |
| `month_number` | `SMALLINT NOT NULL CHECK (month_number BETWEEN 1 AND 12)` | Atributo do domínio desta entidade. |
| `month_name` | `VARCHAR(12) NOT NULL` | Atributo do domínio desta entidade. |
| `week_number` | `SMALLINT NOT NULL` | Atributo do domínio desta entidade. |
| `day_number` | `SMALLINT NOT NULL CHECK (day_number BETWEEN 1 AND 31)` | Atributo do domínio desta entidade. |
| `day_of_week_number` | `SMALLINT NOT NULL CHECK (day_of_week_number BETWEEN 1 AND 7)` | Atributo do domínio desta entidade. |
| `day_of_week_name` | `VARCHAR(12) NOT NULL` | Atributo do domínio desta entidade. |
| `is_weekend` | `BOOLEAN NOT NULL` | Atributo do domínio desta entidade. |

### `dim_employee`

**Por que existe:** Descreve papel e situação do funcionário sem CPF.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `employee_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `role_id` | `BIGINT` | Identificador ou chave de correlação. |
| `role_name` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_product`

**Por que existe:** Descreve o produto para análises.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `product_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `category_id` | `BIGINT` | Identificador ou chave de correlação. |
| `tax_profile_id` | `BIGINT` | Identificador ou chave de correlação. |
| `sku` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `barcode` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `name` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `brand` | `VARCHAR(120)` | Atributo do domínio desta entidade. |
| `unit_of_measure` | `VARCHAR(30)` | Atributo do domínio desta entidade. |
| `avg_cost` | `NUMERIC(15,4)` | Valor monetário ou medida financeira. |
| `suggested_price` | `NUMERIC(15,4)` | Valor monetário ou medida financeira. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_store`

**Por que existe:** Descreve a loja para filtros e agrupamentos.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `store_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `city` | `VARCHAR(120)` | Atributo do domínio desta entidade. |
| `state_code` | `CHAR(2)` | Atributo do domínio desta entidade. |
| `latitude` | `NUMERIC(10,7)` | Atributo do domínio desta entidade. |
| `longitude` | `NUMERIC(10,7)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `dim_supplier`

**Por que existe:** Descreve o fornecedor com dados minimizados.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `supplier_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `city` | `VARCHAR(120)` | Atributo do domínio desta entidade. |
| `state_code` | `CHAR(2)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT true` | Indica se o registro pode ser utilizado. |
| `source_updated_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `engine_scan_log`

**Por que existe:** Registra varreduras do motor.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `scan_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `scan_type` | `VARCHAR(60) NOT NULL` | Atributo do domínio desta entidade. |
| `started_at` | `TIMESTAMPTZ NOT NULL` | Data e hora usada para auditoria ou processamento. |
| `finished_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `status` | `job_status NOT NULL DEFAULT 'RUNNING'` | Estado atual do ciclo de vida. |
| `scanned_rows` | `BIGINT NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `suggestions_created` | `BIGINT NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `error_message` | `TEXT` | Atributo do domínio desta entidade. |
| `metadata` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |

### `engine_suggestion`

**Por que existe:** Registra sugestões produzidas pelo motor.

**Relacionamentos:** ai_recommendation(recommendation_id), engine_scan_log(scan_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `suggestion_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `suggestion_uuid` | `UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE` | Atributo do domínio desta entidade. |
| `scan_id` | `BIGINT REFERENCES engine_scan_log(scan_id)` | Identificador ou chave de correlação. |
| `recommendation_id` | `BIGINT REFERENCES ai_recommendation(recommendation_id)` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `action_type` | `suggested_action_type NOT NULL` | Atributo do domínio desta entidade. |
| `priority` | `priority_level NOT NULL DEFAULT 'MEDIUM'` | Atributo do domínio desta entidade. |
| `status` | `suggested_action_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `proposed_values` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Valor monetário ou medida financeira. |
| `operational_action_id` | `BIGINT` | Identificador ou chave de correlação. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `etl_checkpoint`

**Por que existe:** Controla a última posição confirmada do pipeline.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `pipeline_name` | `VARCHAR(150) PRIMARY KEY` | Atributo do domínio desta entidade. |
| `last_event_uuid` | `UUID` | Atributo do domínio desta entidade. |
| `last_source_id` | `BIGINT` | Identificador ou chave de correlação. |
| `last_occurred_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |
| `metadata` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |

### `etl_dead_letter`

**Por que existe:** Preserva eventos com falha para reprocessamento.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `dead_letter_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `event_uuid` | `UUID` | Atributo do domínio desta entidade. |
| `pipeline_name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `payload` | `JSONB NOT NULL` | Atributo do domínio desta entidade. |
| `error_message` | `TEXT NOT NULL` | Atributo do domínio desta entidade. |
| `retry_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `first_failed_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
| `last_failed_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
| `resolved_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |

### `fact_inventory_movement`

**Por que existe:** Mede movimentos de estoque.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `movement_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `movement_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `movement_timestamp` | `TIMESTAMPTZ NOT NULL` | Atributo do domínio desta entidade. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `inventory_id` | `BIGINT` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `employee_id` | `BIGINT` | Identificador ou chave de correlação. |
| `movement_type` | `VARCHAR(40) NOT NULL` | Atributo do domínio desta entidade. |
| `quantity` | `NUMERIC(15,3) NOT NULL` | Quantidade ou contagem mensurável. |
| `unit_cost` | `NUMERIC(15,4)` | Valor monetário ou medida financeira. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_inventory_movement_default`

**Por que existe:** Recebe movimentos cuja data ainda não possui partição mensal.

**Relacionamentos:** PARTITION OF fact_inventory_movement.

| Campo | Definição SQL | Uso |
|---|---|---|

### `fact_inventory_snapshot`

**Por que existe:** Registra a posição diária do estoque.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `snapshot_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `inventory_type` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `quantity` | `NUMERIC(15,3) NOT NULL` | Quantidade ou contagem mensurável. |
| `reserved_quantity` | `NUMERIC(15,3) NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `average_cost` | `NUMERIC(15,4)` | Valor monetário ou medida financeira. |
| `expiration_date` | `DATE` | Data de negócio e possível filtro temporal. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_inventory_snapshot_default`

**Por que existe:** Recebe snapshots cuja data ainda não possui partição mensal.

**Relacionamentos:** PARTITION OF fact_inventory_snapshot.

| Campo | Definição SQL | Uso |
|---|---|---|

### `fact_loss_destination`

**Por que existe:** Mede perdas por destinação.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `loss_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `loss_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `destination_type` | `VARCHAR(40) NOT NULL` | Atributo do domínio desta entidade. |
| `quantity` | `NUMERIC(15,3) NOT NULL` | Quantidade ou contagem mensurável. |
| `estimated_value` | `NUMERIC(15,2)` | Valor monetário ou medida financeira. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_loyalty`

**Por que existe:** Mede eventos de pontos.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `loyalty_event_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `event_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `customer_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `event_type` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `points_delta` | `INTEGER NOT NULL` | Atributo do domínio desta entidade. |
| `balance_after` | `INTEGER` | Atributo do domínio desta entidade. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_promotion_result`

**Por que existe:** Mede resultado de promoções e perda evitada.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `promotion_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `result_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `units_sold` | `NUMERIC(15,3) NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `gross_revenue` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Valor monetário ou medida financeira. |
| `discount_granted` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `avoided_loss` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_purchase_order`

**Por que existe:** Mede pedidos de compra.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `purchase_order_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `order_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `supplier_id` | `BIGINT` | Identificador ou chave de correlação. |
| `employee_id` | `BIGINT` | Identificador ou chave de correlação. |
| `status` | `VARCHAR(30) NOT NULL` | Estado atual do ciclo de vida. |
| `item_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `total_amount` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Valor monetário ou medida financeira. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_receiving`

**Por que existe:** Mede recebimentos.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `receiving_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `purchase_order_id` | `BIGINT` | Identificador ou chave de correlação. |
| `receiving_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `supplier_id` | `BIGINT` | Identificador ou chave de correlação. |
| `employee_id` | `BIGINT` | Identificador ou chave de correlação. |
| `status` | `VARCHAR(30) NOT NULL` | Estado atual do ciclo de vida. |
| `item_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_replenishment`

**Por que existe:** Mede reposição solicitada e atendida.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `replenishment_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `replenishment_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `requested_quantity` | `NUMERIC(15,3) NOT NULL` | Quantidade ou contagem mensurável. |
| `supplied_quantity` | `NUMERIC(15,3)` | Quantidade ou contagem mensurável. |
| `status` | `VARCHAR(30) NOT NULL` | Estado atual do ciclo de vida. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_sale_item`

**Por que existe:** Mede um item vendido por data.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `sale_item_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `sale_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `batch_id` | `BIGINT` | Identificador ou chave de correlação. |
| `quantity` | `NUMERIC(15,3) NOT NULL` | Quantidade ou contagem mensurável. |
| `unit_price` | `NUMERIC(15,4) NOT NULL` | Valor monetário ou medida financeira. |
| `discount_amount` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `subtotal` | `NUMERIC(15,2) NOT NULL` | Valor monetário ou medida financeira. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_sale_item_default`

**Por que existe:** Recebe itens cuja data ainda não possui partição mensal.

**Relacionamentos:** PARTITION OF fact_sale_item.

| Campo | Definição SQL | Uso |
|---|---|---|

### `fact_sale_payment`

**Por que existe:** Mede pagamentos por método.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `payment_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `sale_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `payment_method` | `VARCHAR(40) NOT NULL` | Atributo do domínio desta entidade. |
| `amount` | `NUMERIC(15,2) NOT NULL` | Valor monetário ou medida financeira. |
| `installments` | `SMALLINT` | Atributo do domínio desta entidade. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_sales`

**Por que existe:** Mede uma venda por data.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `sale_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `sale_timestamp` | `TIMESTAMPTZ NOT NULL` | Atributo do domínio desta entidade. |
| `company_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `employee_id` | `BIGINT` | Identificador ou chave de correlação. |
| `customer_id` | `BIGINT` | Identificador ou chave de correlação. |
| `item_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `gross_amount` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Valor monetário ou medida financeira. |
| `discount_amount` | `NUMERIC(15,2) NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `net_amount` | `NUMERIC(15,2) NOT NULL` | Valor monetário ou medida financeira. |
| `status` | `VARCHAR(30) NOT NULL` | Estado atual do ciclo de vida. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `fact_sales_default`

**Por que existe:** Recebe vendas cuja data ainda não possui partição mensal.

**Relacionamentos:** PARTITION OF fact_sales.

| Campo | Definição SQL | Uso |
|---|---|---|

### `fact_transfer`

**Por que existe:** Mede transferências entre lojas.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `transfer_id` | `BIGINT PRIMARY KEY` | Identificador ou chave de correlação. |
| `transfer_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `source_store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `destination_store_id` | `BIGINT NOT NULL` | Identificador ou chave de correlação. |
| `status` | `VARCHAR(30) NOT NULL` | Estado atual do ciclo de vida. |
| `item_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `total_cost` | `NUMERIC(15,2)` | Valor monetário ou medida financeira. |
| `loaded_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |

### `ingestion_event`

**Por que existe:** Implementa inbox idempotente.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `event_uuid` | `UUID PRIMARY KEY` | Atributo do domínio desta entidade. |
| `source_event_id` | `BIGINT UNIQUE` | Identificador ou chave de correlação. |
| `source_database` | `VARCHAR(80) NOT NULL DEFAULT 'mottainai_operational'` | Atributo do domínio desta entidade. |
| `event_type` | `VARCHAR(120) NOT NULL` | Atributo do domínio desta entidade. |
| `aggregate_type` | `VARCHAR(80)` | Atributo do domínio desta entidade. |
| `aggregate_id` | `VARCHAR(120)` | Identificador ou chave de correlação. |
| `company_id` | `BIGINT` | Identificador ou chave de correlação. |
| `store_id` | `BIGINT` | Identificador ou chave de correlação. |
| `schema_version` | `INTEGER NOT NULL DEFAULT 1` | Atributo do domínio desta entidade. |
| `payload` | `JSONB NOT NULL` | Atributo do domínio desta entidade. |
| `occurred_at` | `TIMESTAMPTZ NOT NULL` | Data e hora usada para auditoria ou processamento. |
| `ingested_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
| `processed_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `status` | `ingestion_status NOT NULL DEFAULT 'RECEIVED'` | Estado atual do ciclo de vida. |
| `retry_count` | `INTEGER NOT NULL DEFAULT 0` | Quantidade ou contagem mensurável. |
| `error_message` | `TEXT` | Atributo do domínio desta entidade. |

### `job_log`

**Por que existe:** Registra execução das cargas.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `job_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `job_name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `status` | `job_status NOT NULL DEFAULT 'RUNNING'` | Estado atual do ciclo de vida. |
| `started_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Data e hora usada para auditoria ou processamento. |
| `finished_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `rows_read` | `BIGINT NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `rows_written` | `BIGINT NOT NULL DEFAULT 0` | Atributo do domínio desta entidade. |
| `error_message` | `TEXT` | Atributo do domínio desta entidade. |
| `metadata` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |

### `kpi_cache`

**Por que existe:** Materializa indicador por escopo e data.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `kpi_key` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `scope_type` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `scope_id` | `BIGINT NOT NULL DEFAULT 0` | Identificador ou chave de correlação. |
| `reference_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `value` | `NUMERIC(20,6)` | Valor monetário ou medida financeira. |
| `payload` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |
| `calculated_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
| `expires_at` | `TIMESTAMPTZ` | Atributo do domínio desta entidade. |

### `query_performance`

**Por que existe:** Registra amostras de desempenho de consultas.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `sample_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `query_name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `duration_ms` | `NUMERIC(14,3) NOT NULL` | Atributo do domínio desta entidade. |
| `rows_returned` | `BIGINT` | Atributo do domínio desta entidade. |
| `sampled_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
| `metadata` | `JSONB NOT NULL DEFAULT '{}'::jsonb` | Atributo do domínio desta entidade. |

### `schema_version`

**Por que existe:** Controla a versão instalada do schema analítico.

**Relacionamentos:** sem FK externa; IDs preservam a correlação com a origem ou com objetos analíticos locais.

| Campo | Definição SQL | Uso |
|---|---|---|
| `version` | `INTEGER PRIMARY KEY` | Versão para evolução ou concorrência otimista. |
| `description` | `TEXT NOT NULL` | Atributo do domínio desta entidade. |
| `applied_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Atributo do domínio desta entidade. |
