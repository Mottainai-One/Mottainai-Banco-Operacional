\set ON_ERROR_STOP on
\echo 'Preparing reversible employee PII storage'

BEGIN;
\ir 28_reversible_employee_pii.sql
COMMIT;

\echo 'Preparation completed; backfill AES-GCM envelopes before finalization'
