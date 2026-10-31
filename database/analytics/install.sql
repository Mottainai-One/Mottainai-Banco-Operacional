\set ON_ERROR_STOP on

BEGIN;
\ir 00_database.sql
\ir 01_types.sql
\ir 02_dimensions.sql
\ir 03_facts.sql
\ir 03_monthly_partitions.sql
\ir 04_ai.sql
\ir 05_integration.sql
\ir 06_indexes.sql
\ir 07_views.sql
\ir 08_seed.sql
\ir 10_dashboard.sql
\ir 11_priority_views.sql
\ir 12_daily_batch.sql
\ir 09_tests.sql
\ir 13_daily_batch_tests.sql
COMMIT;

\ir 15_operational_kpi_facts.sql
