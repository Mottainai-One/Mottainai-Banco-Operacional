\set ON_ERROR_STOP on
\echo 'Finalizing reversible employee PII storage'

BEGIN;
\ir 29_finalize_reversible_employee_pii.sql
COMMIT;

\echo 'Finalization completed; legacy employee/app_user contact columns removed'
