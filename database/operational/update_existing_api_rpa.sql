\set ON_ERROR_STOP on
\echo 'Updating an existing operational database for API and RPA compatibility'

BEGIN;
\ir 10_product_company.sql
\ir 20_security_hardening.sql
\ir 22_sensitive_data_contract.sql
\ir 24_jpa_compatibility.sql
\ir 25_api_rpa_compatibility.sql
\ir 37_reversible_customer_pii.sql
\ir 38_client_mobile_api.sql
COMMIT;

-- Keep the Spring API soft-delete contract aligned after the compatibility transaction.
\ir 36_api_soft_delete_promotion_items.sql

\echo 'Operational API and RPA compatibility update completed successfully'
