\set ON_ERROR_STOP on
\echo 'Adding reversible customer private-data storage'

BEGIN;
\ir 30_reversible_customer_pii.sql
COMMIT;

\echo 'Customer private-data storage installed successfully'
