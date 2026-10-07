\set ON_ERROR_STOP on
-- Atualiza uma instalação local existente sem reinstalar nem apagar dados.
-- Executar: psql -v ON_ERROR_STOP=1 -d mottainai_operational
--           -f database/operational/update_existing_jpa.sql
BEGIN;
\ir 24_jpa_compatibility.sql
\ir 25_jpa_compatibility_tests.sql
COMMIT;
