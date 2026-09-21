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
\ir 10_tests.sql
COMMIT;

\echo 'mottainai_operational installed successfully'
