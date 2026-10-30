\set ON_ERROR_STOP on
\echo 'Applying the final customer private-data contract'

BEGIN;
\ir 37_reversible_customer_pii.sql
COMMIT;

\echo 'Final customer private-data contract installed successfully'
