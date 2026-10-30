\set ON_ERROR_STOP on
\echo 'Applying the final customer private-data and mobile API contract'

BEGIN;
\ir 37_reversible_customer_pii.sql
\ir 38_client_mobile_api.sql
COMMIT;

\echo 'Final customer database contract installed successfully'
