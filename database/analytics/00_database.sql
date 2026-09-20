-- Execute conectado ao banco mottainai_analytics.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
COMMENT ON SCHEMA mottainai_analytics IS
    'Banco analitico: historico, indicadores, recomendacoes de IA e controle de ingestao.';

SET search_path TO mottainai_analytics, public;
