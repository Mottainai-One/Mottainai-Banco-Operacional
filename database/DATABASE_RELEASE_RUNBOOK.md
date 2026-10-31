# Mottainai database release runbook

This runbook coordinates the operational database, the physical analytics
database, and the scheduled RPA. The two databases are separate Aiven PostgreSQL
databases. SQL must be run against the named database in each step; a three-part
cross-database name does not work in PostgreSQL.

## Release order

1. Confirm that `MOTTAINAI` is at operational schema version 38 or later.
2. Merge and deploy the RPA change that uses each partitioned fact's composite
   key in its `ON CONFLICT` clause.
3. Connect directly to `MOTTAINAI_ANALITICO` and apply analytics migrations 15
   and 16, or use the complete analytics installer for a fresh database.
4. Run the RPA workflow once manually and verify the published batch and table
   reconciliation.
5. Leave the scheduled run at 02:00 in `America/Sao_Paulo`; monitor the next
   scheduled execution before treating the automation as operationally proven.

The RPA code and analytics schema must use the same composite keys. Do not apply
partition migration 16 to an environment whose RPA still uses the pre-migration
single-column conflict targets.

## Operational database check

Connect to `MOTTAINAI` and verify the installed version and the fields consumed
by the daily RPA:

```sql
SELECT version, description
FROM mottainai.schema_version
ORDER BY version DESC
LIMIT 1;
```

The operational database does not need synthetic rows to pass this check. The
read-only regression script `database/operational/39_analytics_source_contract_tests.sql`
checks that the source tables and columns needed for KPI extraction are present.

## Analytics database migration

For an existing database that already has the base mart and migration 15, run
the partition migration while connected directly to `MOTTAINAI_ANALITICO`:

```bash
psql -v ON_ERROR_STOP=1 -d MOTTAINAI_ANALITICO \
  -f database/analytics/16_partition_operational_kpi_facts.sql
```

The migration converts the eight operational KPI facts to monthly range
partitions, copies existing records transactionally, retains a `DEFAULT`
partition for dates outside the current monthly window, rebuilds the five
dependent views, restores loader and reader grants, and records schema versions
15 and 16. It does not delete or fabricate fact data.

For a new analytics database, run
`database/analytics/install.sql` with `psql`, or
`database/analytics/install_pgadmin.sql` in pgAdmin. Both installers include
migrations 15 and 16.

## Validation after deployment

On `MOTTAINAI_ANALITICO`, confirm that versions 15 and 16 are recorded and all
eight KPI facts are partitioned:

```sql
SELECT version, description
FROM mottainai_analytics.schema_version
WHERE version IN (15, 16)
ORDER BY version;

SELECT c.relname AS fact_table, pg_get_partkeydef(c.oid) AS partition_key
FROM pg_partitioned_table p
JOIN pg_class c ON c.oid = p.partrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'mottainai_analytics'
  AND c.relname IN (
    'fact_inventory_count_line', 'fact_transfer_line',
    'fact_replenishment_plan_line', 'fact_replenishment_execution_line',
    'fact_donation_line', 'fact_disposal_line',
    'fact_alert_lifecycle', 'fact_action_lifecycle'
  )
ORDER BY c.relname;
```

Check the latest load and published batch:

```sql
SELECT job_name, status, started_at, finished_at,
       rows_read, rows_written, error_message, batch_id
FROM mottainai_analytics.job_log
WHERE job_name = 'operational_to_analytics_daily'
ORDER BY job_id DESC
LIMIT 5;

SELECT batch_id, source_cutoff_at, published_at
FROM mottainai_analytics.vw_published_batch
ORDER BY published_at DESC
LIMIT 5;
```

Compare each analytical fact count with its operational source count before
diagnosing an empty KPI as a pipeline failure. A zero-row operational source
should produce a zero-row analytical fact; successful ETL is not expected to
invent sales, inventory movements, counts, transfers, donations, or alerts.

`mv_dashboard_metrics` is refreshed inside the successful RPA transaction. A
published batch proves the database mart was refreshed; the Databricks SQL
dashboard's own refresh/cache schedule remains a separate workspace setting and
must be checked in Databricks.

## Failure handling

- The RPA writes all reconciled datasets and the successful `job_log` record in
  one analytics transaction. On error, that transaction rolls back.
- If the RPA fails after migration 16, verify it is running the composite-key
  release before rerunning it.
- Do not truncate or drop analytics facts as a troubleshooting step. Capture
  the failed `job_log` row and compare source and target counts first.
- Keep `MOTTAINAI_ANALITICO` separate from the operational transaction database;
  the 02:00 schedule is the boundary for publishing analytical changes.
