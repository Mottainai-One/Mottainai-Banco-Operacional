-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 00_EXTENSIONS.SQL
-- ====================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- 01_SCHEMA.SQL
-- ====================================================================

DROP SCHEMA IF EXISTS mottainai CASCADE;
CREATE SCHEMA IF NOT EXISTS mottainai;
CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
SET search_path TO mottainai, public;
