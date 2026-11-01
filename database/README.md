# Bancos MOTTAINAI: instalação completa e contrato da RPA

Este diretório é a fonte versionada para recriar os dois bancos físicos usados pela solução:

- `operational/`: banco operacional `MOTTAINAI`, schema `mottainai`;
- `analytics/`: banco analítico, schema `mottainai_analytics`.

Os bancos são físicos e independentes. Portanto, não há foreign keys entre eles. A correlação entre registros é feita pelos IDs de origem e pelo contrato de ingestão diário.

## Instalação do zero

Conecte ao banco operacional e execute `database/operational/install.sql` com `psql`.

Depois, conecte ao banco analítico e execute `database/analytics/install.sql` com `psql`. Para pgAdmin, use `database/analytics/install_pgadmin.sql` conectado diretamente ao banco analítico.

Os instaladores carregam, na ordem correta, schemas, tipos, funções, tabelas, segurança, índices, triggers, views, procedimentos, dados iniciais e o contrato da carga diária.

## Contrato da carga diária

O banco analítico registra em `mottainai_analytics.etl_source_contract` como cada tabela do operacional será extraída:

- tabelas com `INCREMENTAL` precisam ter o `watermark_column` existente no operacional;
- `customer_consent` usa `recorded_at`;
- `loyalty_redemption` usa `redeemed_at`;
- `inventory` permanece `SNAPSHOT` quando não há timestamp de alteração;
- nenhuma tabela de credenciais ou PII reversível é habilitada para o analítico.

## Verificação após instalação

No operacional:

```sql
SELECT current_database(), to_regclass('mottainai.company'),
       to_regclass('mottainai.customer_consent'),
       to_regclass('mottainai.loyalty_redemption');
```

No analítico:

```sql
SELECT current_database(),
       to_regclass('mottainai_analytics.etl_source_contract'),
       to_regclass('mottainai_analytics.etl_daily_batch');

SELECT source_table, extraction_mode, watermark_column
FROM mottainai_analytics.etl_source_contract
WHERE enabled
ORDER BY load_order;
```

A RPA valida novamente as colunas do operacional antes de abrir cada batch. Assim, um banco instalado a partir destes scripts permanece coerente com o contrato versionado.

Para uma instalação existente que ainda tenha os watermarks antigos, execute no banco analítico `database/analytics/13_align_existing_watermarks.sql`.
Para uma instalação existente que já contenha o contrato `etl_daily_batch`,
aplique também `database/analytics/14_publish_mart_view.sql` conectado ao
banco físico `MOTTAINAI_ANALITICO`. Essa migração faz
`vw_published_batch` mostrar somente uma carga cujo `job_log` foi confirmado
na mesma transação que escreve os fatos e dimensões. Registros antigos em
`etl_daily_batch` permanecem para auditoria, mas não representam por si só
um data mart atualizado.

## Fatos operacionais para BI

Após instalar o esquema analítico existente, execute, nesta ordem,
`database/analytics/15_operational_kpi_facts.sql` e
`database/analytics/16_partition_operational_kpi_facts.sql`, **conectado ao
banco físico `MOTTAINAI_ANALITICO`**. Os arquivos são SQL PostgreSQL puro e
podem ser abertos no Query Tool do pgAdmin ou executados com `psql`; não iniciam
cargas. Em uma instalação nova, `install.sql` e `install_pgadmin.sql` incluem
as duas migrações.

Ela cria fatos por linha para contagens físicas, transferências, pré-listas,
execuções de reposição, doações e descartes, além de fatos de ciclo de vida
para alertas e ações. As views `vw_inventory_count_accuracy`,
`vw_transfer_execution`, `vw_replenishment_fulfillment`,
`vw_product_destinations` e `vw_alert_action_funnel` expõem indicadores
auditáveis. As tabelas são preenchidas pela RPA `analytics/load.py` **após**
o data load operacional; apenas executar as migrações deixa os fatos vazios.

A migração 16 converte esses oito fatos em tabelas particionadas mensalmente,
preservando os registros existentes em uma transação e mantendo uma partição
`DEFAULT` para datas fora da janela criada. A chave primária composta inclui o
ID de origem e a coluna de partição; por isso a RPA usa os mesmos campos no
`ON CONFLICT`. As versões 15 e 16 ficam registradas em `schema_version`.

Confira o banco selecionado e os objetos antes da primeira carga:

```sql
SELECT current_database(); -- MOTTAINAI_ANALITICO
SELECT to_regclass('mottainai_analytics.fact_inventory_count_line') AS inventory_count,
       to_regclass('mottainai_analytics.fact_transfer_line') AS transfer_line,
       to_regclass('mottainai_analytics.fact_alert_lifecycle') AS alert_lifecycle;
```

As quantidades e valores registrados não são previsões. Acuracidade só usa
contagens `COMPLETED`; a taxa de reposição fica nula sem execução concluída;
doação só conta como concluída quando seu status é `COMPLETED`. O número de
alertas resolvidos e ações executadas não comprova efetividade econômica.

## API do PDV

O suporte do PDV é instalado somente no banco operacional. Em uma instalação
existente, execute `database/operational/update_existing_pos_api.sql` conectado
ao banco `mottainai_operational`:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/update_existing_pos_api.sql
```

Não use `psql --single-transaction` para esse arquivo: as migrations 31 e 33
adicionam valores `ENUM`, que precisam estar confirmados antes de as migrations
posteriores usarem esses valores. A instalação limpa também executa esse
atualizador após confirmar a transação do schema operacional. As migrations
criam recibos idempotentes com RLS, habilitam o estado `DRAFT` para vendas e
itens, mantêm itens de rascunho sem reserva de lote/estoque e expõem uma busca
de cliente que retorna somente o ID a partir do token `AUTH_SHA256_...`.

O schema operacional já possui índices únicos parciais que permitem no máximo
um turno aberto por terminal e por funcionário; por isso não é necessário
adicionar outro índice para essa regra.

A instalação limpa também executa `36_api_soft_delete_promotion_items.sql`,
alinhada à Flyway V11 da API Spring. A migration de compatibilidade de promoção
é repetível e mantém o histórico de itens removidos, permitindo cadastrar
novamente o mesmo produto na promoção depois da exclusão lógica.

## API mobile do cliente

O contrato final do aplicativo de clientes é instalado pelos módulos
`37_reversible_customer_pii.sql` e `38_client_mobile_api.sql`. Em um banco
operacional existente, execute:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/update_existing_customer_private_data.sql
```

O módulo 37 mantém o envelope AES-256-GCM após a exclusão lógica, impede
`DELETE` físico e permite leitura administrativa somente para gerente ou
administrador da mesma empresa com venda válida do cliente. O módulo 38 cria a
role sem login `mottainai_client_api`, três roles proprietárias sem login,
views de catálogo filtradas e funções transacionais para cadastro Firebase,
perfil, login e recuperação. Credenciais, TLS e chaves AES permanecem no secret
manager/KMS e nunca são versionados no SQL.

## Finalização dos dados pessoais de funcionários

Em bancos existentes, o módulo `28_reversible_employee_pii.sql` cria a área
criptografada de transição, mas mantém temporariamente as colunas legadas. Após
o backend/RPA preencher e validar todos os envelopes AES-GCM e identificadores
de busca, execute `29_finalize_reversible_employee_pii.sql`.

Essa etapa falha antes de qualquer remoção quando encontra criptografia,
fingerprint ou `firebase_uid` obrigatório incompleto. Quando as validações
passam, remove `name`, `cpf`, `email` e `phone` de `employee`, além de `cpf` e
`email` de `app_user`. Os dados protegidos permanecem em
`employee_private_data`; `app_user` mantém `employee_id` e `firebase_uid`.

No Aiven, o provedor mantém o executor `avnadmin` como membro das roles que ele
cria e impede que esse grant administrativo seja revogado pelo próprio login.
O instalador aceita somente essa associação nominal e rejeita qualquer outro
membro. O login do backend recebe exclusivamente `mottainai_client_api`; nunca
recebe uma role proprietária ou administrativa.

O Aiven não permite ao `avnadmin` conceder ACL de parâmetro como um superusuário
real. Por isso, o contexto RLS do cliente fica em
`api_customer_transaction_context`, associado ao PID e à transação atual. A
tabela é inacessível aos logins das APIs e somente funções `SECURITY DEFINER`
das roles técnicas de perfil ou autenticação podem gravá-la. Bootstrap e
operação protegida devem ocorrer na mesma transação.

A atualização incremental do POS também executa
`37_pos_manager_approvals.sql`, que cria o registro durável de pedidos de
aprovação. Cancelamentos continuam usando `pos_cancel_request` e
`sp_decide_pos_cancellation`; os outros tipos ficam registrados em
`pos_manager_approval_request`.
