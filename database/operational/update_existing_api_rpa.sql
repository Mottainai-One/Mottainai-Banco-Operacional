\set ON_ERROR_STOP on
\echo 'Updating an existing operational database for API and RPA compatibility'

BEGIN;
\ir 10_product_company.sql
\ir 20_security_hardening.sql
\ir 22_sensitive_data_contract.sql
\ir 24_jpa_compatibility.sql
\ir 25_api_rpa_compatibility.sql
COMMIT;

\echo 'Operational API and RPA compatibility update completed successfully'
