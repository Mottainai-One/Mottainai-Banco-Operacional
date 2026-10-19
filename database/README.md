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
