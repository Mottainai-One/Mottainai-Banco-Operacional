-- ====================================================================
-- MOTTAINAI DATABASE v6.0
-- INSTALL - Complete installation script
-- ====================================================================

\echo '========================================'
\echo 'Installing Mottainai Database v6.0'
\echo '========================================'

\echo 'Step 1: Creating database and schemas...'
\i 00_DataBase.sql

\echo 'Step 2: Creating enums...'
\i 01_Enums.sql

\echo 'Step 3: Creating functions...'
\i 02_functions.sql

\echo 'Step 4: Creating tables...'
\i 03_tables.sql

\echo 'Step 5: Creating constraints and partitions...'
\i 04_constraints.sql

\echo 'Step 6: Creating indexes...'
\i 05_index.sql

\echo 'Step 7: Creating triggers...'
\i 06_triggers.sql

\echo 'Step 8: Creating views...'
\i 07_views.sql

\echo 'Step 9: Seeding data...'
\i 08_seed.sql

\echo 'Step 10: Creating procedures...'
\i 09_procedures.sql

\echo 'Step 11: Creating test suite functions...'
\i 10_tests.sql

\echo '========================================'
\echo 'Installation completed successfully!'
\echo '========================================'

-- The test suite (SELECT * FROM run_all_tests();) is intentionally not
-- auto-executed here: it requires seeded data (company, address, product).
-- Run it manually after executing dataLoad.sql.
