# Contrato dos eventos operacionais para BI

O banco físico `MOTTAINAI` é a origem. A RPA `analytics/load.py` lê uma
fotografia consistente, reconcilia o histórico em uma única transação no
`MOTTAINAI_ANALITICO` e só então publica o lote em `job_log`. A carga diária
permanece às 02:00, fuso `America/Sao_Paulo`. A migração SQL deve ser aplicada
no analítico antes de executar a versão nova da RPA.

| Fonte operacional | Destino analítico | Grão e uso |
|---|---|---|
| `inventory_count` + `inventory_count_item` + `inventory` + `batch` | `fact_inventory_count_line` | Item contado; acuracidade e divergência apenas em contagens concluídas |
| `inventory_movement` | `fact_inventory_movement` existente | Movimento por data; saídas, entradas e suporte ao giro após histórico suficiente |
| `transfer` + `transfer_item` + `batch` | `fact_transfer_line` | Linha de transferência; conclusão e tempo, sem inferir venda no destino |
| `replenishment_pre_list` + itens | `fact_replenishment_plan_line` | Item sugerido por produto/loja |
| `replenishment_execution` + itens + `batch` | `fact_replenishment_execution_line` | Item executado; só `end_date` preenchido conta como concluído |
| `donation` + itens + `batch` | `fact_donation_line` | Item doado com status; sem copiar instituição ou observação |
| `disposal` + itens + `batch` | `fact_disposal_line` | Item descartado; motivo textual fica na origem até existir código controlado |
| `alert` | `fact_alert_lifecycle` | Estado atual do alerta, origem e resolução |
| `suggested_action` + `alert` | `fact_action_lifecycle` | Estado atual da ação e chave de correlação com recomendação |

Os IDs de origem são preservados. CPF, email, telefone, nome de cliente,
instituição da doação, observações e textos livres não são copiados por esses
datasets. O custo vem de `batch.unit_cost` e serve para **valor a custo**;
não é margem nem economia atribuível. Alteração posterior nesse custo pode
reexpressar o histórico, portanto margem financeira exige custo congelado no
momento da venda ou um livro de custos imutável.

## Validação após o data load e a RPA

Execute no `MOTTAINAI_ANALITICO`:

```sql
SELECT 'contagens' AS fato, count(*) AS linhas FROM mottainai_analytics.fact_inventory_count_line
UNION ALL SELECT 'transferencias', count(*) FROM mottainai_analytics.fact_transfer_line
UNION ALL SELECT 'pre_listas', count(*) FROM mottainai_analytics.fact_replenishment_plan_line
UNION ALL SELECT 'reposicoes', count(*) FROM mottainai_analytics.fact_replenishment_execution_line
UNION ALL SELECT 'doacoes', count(*) FROM mottainai_analytics.fact_donation_line
UNION ALL SELECT 'descartes', count(*) FROM mottainai_analytics.fact_disposal_line
UNION ALL SELECT 'alertas', count(*) FROM mottainai_analytics.fact_alert_lifecycle
UNION ALL SELECT 'acoes', count(*) FROM mottainai_analytics.fact_action_lifecycle;

SELECT job_id, status, cutoff_at, finished_at, metadata -> 'dataset_counts' AS dataset_counts
FROM mottainai_analytics.job_log
WHERE job_name = 'operational_to_analytics_daily'
ORDER BY job_id DESC LIMIT 1;

SELECT * FROM mottainai_analytics.vw_inventory_count_accuracy LIMIT 10;
SELECT * FROM mottainai_analytics.vw_replenishment_fulfillment LIMIT 10;
SELECT * FROM mottainai_analytics.vw_alert_action_funnel LIMIT 10;
```

Se o data load inserir registros hoje e a atualização for necessária antes
das próximas 02:00, acione manualmente o workflow
`Operational to analytics daily load` **depois** da migração e do data load.
O job Databricks das 02:30 consome apenas o lote analítico publicado. As novas
views PostgreSQL ficam prontas imediatamente; levar estes novos fatos às
camadas Bronze/Silver/Gold do Databricks requer uma versão do contrato BI e
testes de qualidade próprios antes de exibir novos cartões no dashboard.
