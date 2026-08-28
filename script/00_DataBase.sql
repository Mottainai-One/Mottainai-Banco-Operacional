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

-- Nao usamos DROP SCHEMA ... CASCADE: em ambiente compartilhado isso
-- apagaria objetos de dependentcias nao relacionados. O install roda em
-- um database limpo e o reset/carga usa exclusivamente script de seed/teste.
CREATE SCHEMA IF NOT EXISTS mottainai;
CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
SET search_path TO mottainai, public;
