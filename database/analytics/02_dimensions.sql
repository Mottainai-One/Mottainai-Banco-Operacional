SET search_path TO mottainai_analytics, public;

CREATE TABLE IF NOT EXISTS schema_version (
    version             INTEGER PRIMARY KEY,
    description         TEXT NOT NULL,
    applied_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_date (
    date_key            DATE PRIMARY KEY,
    year_number         SMALLINT NOT NULL,
    quarter_number      SMALLINT NOT NULL CHECK (quarter_number BETWEEN 1 AND 4),
    month_number        SMALLINT NOT NULL CHECK (month_number BETWEEN 1 AND 12),
    month_name          VARCHAR(12) NOT NULL,
    week_number         SMALLINT NOT NULL,
    day_number          SMALLINT NOT NULL CHECK (day_number BETWEEN 1 AND 31),
    day_of_week_number  SMALLINT NOT NULL CHECK (day_of_week_number BETWEEN 1 AND 7),
    day_of_week_name    VARCHAR(12) NOT NULL,
    is_weekend          BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_company (
    company_id          BIGINT PRIMARY KEY,
    plan_id             BIGINT,
    legal_name          VARCHAR(255) NOT NULL,
    trade_name          VARCHAR(255),
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_store (
    store_id            BIGINT PRIMARY KEY,
    company_id          BIGINT NOT NULL,
    name                VARCHAR(255) NOT NULL,
    city                VARCHAR(120),
    state_code          CHAR(2),
    latitude            NUMERIC(10,7),
    longitude           NUMERIC(10,7),
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_category (
    category_id         BIGINT PRIMARY KEY,
    parent_category_id  BIGINT,
    name                VARCHAR(150) NOT NULL,
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_product (
    product_id          BIGINT PRIMARY KEY,
    category_id         BIGINT,
    tax_profile_id      BIGINT,
    sku                 VARCHAR(100),
    barcode             VARCHAR(100),
    name                VARCHAR(255) NOT NULL,
    brand               VARCHAR(120),
    unit_of_measure     VARCHAR(30),
    avg_cost            NUMERIC(15,4),
    suggested_price     NUMERIC(15,4),
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_supplier (
    supplier_id         BIGINT PRIMARY KEY,
    company_id          BIGINT NOT NULL,
    name                VARCHAR(255) NOT NULL,
    city                VARCHAR(120),
    state_code          CHAR(2),
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_employee (
    employee_id         BIGINT PRIMARY KEY,
    store_id            BIGINT,
    role_id             BIGINT,
    role_name           VARCHAR(100),
    active              BOOLEAN NOT NULL DEFAULT true,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id         BIGINT PRIMARY KEY,
    anonymous_key       UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    birth_year          SMALLINT,
    active              BOOLEAN NOT NULL DEFAULT true,
    marketing_consent   BOOLEAN NOT NULL DEFAULT false,
    source_updated_at   TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE dim_customer IS
    'Dimensao minimizada: nao replica CPF, nome, telefone ou e-mail do banco operacional.';
