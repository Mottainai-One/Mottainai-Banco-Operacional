\set ON_ERROR_STOP on

-- Additive upgrade for an existing MOTTAINAI database.
-- Execute from psql; paths are resolved relative to this file.
\echo 'Applying mobile product media and damage-report migrations'
\ir 40_mobile_product_image_url.sql
\ir 41_mobile_damage_reports.sql
\echo 'Mobile operational database update completed'
