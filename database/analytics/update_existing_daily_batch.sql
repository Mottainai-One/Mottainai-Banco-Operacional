\set ON_ERROR_STOP on

\echo 'Updating analytics database for the daily 02:00 batch contract'

BEGIN;
\ir 07_views.sql
\ir 10_dashboard.sql
\ir 11_priority_views.sql
\ir 12_daily_batch.sql
\ir 13_daily_batch_tests.sql
COMMIT;

\echo 'Daily analytics batch contract installed successfully'
