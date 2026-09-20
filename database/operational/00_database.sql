CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS mottainai;
SET search_path TO mottainai, public;

COMMENT ON SCHEMA mottainai IS
    'Fonte oficial dos cadastros e processos transacionais do Mottainai.';
