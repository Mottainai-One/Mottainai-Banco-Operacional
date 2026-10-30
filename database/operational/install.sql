\set ON_ERROR_STOP on
-- This orchestrator intentionally requires psql because it uses \ir to load
-- modules relative to this file. Other clients must execute the listed files
-- in the same order or use a migration tool configured with that sequence.
\echo 'Installing mottainai_operational'

BEGIN;
\ir 00_database.sql
\ir 01_enums.sql
\ir 02_functions.sql
\ir 03_tables.sql
\ir 04_additional_tables.sql
\ir 04_security.sql
\ir 05_indexes.sql
\ir 06_triggers.sql
\ir 07_views.sql
\ir 08_procedures.sql
\ir 08_partition_maintenance_fix.sql
\ir 09_seed.sql
\ir 10_product_company.sql
\ir 20_security_hardening.sql
\ir 22_sensitive_data_contract.sql
\ir 24_jpa_compatibility.sql
\ir 25_api_rpa_compatibility.sql
\ir 28_reversible_employee_pii.sql
\ir 29_finalize_reversible_employee_pii.sql
\ir 30_customer_private_data.sql
COMMIT;

-- POS API support includes enum changes that must be committed before use.
-- Keep these incremental migrations outside the installation transaction.
\ir update_existing_pos_api.sql
\ir 36_api_soft_delete_promotion_items.sql

-- Final customer security and mobile API contract are applied only after the
-- POS compatibility migrations are committed.
BEGIN;
\ir 37_reversible_customer_pii.sql
COMMIT;

\echo 'mottainai_operational installed successfully'
