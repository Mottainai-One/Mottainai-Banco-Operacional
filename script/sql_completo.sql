-- ====================================================================
-- MOTTAINAI DATABASE v6.0
-- Schema: mottainai
-- Description: Enterprise Inventory Management System with AI
-- PostgreSQL 15+ - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- ====================================================================

-- ====================================================================
-- 00_EXTENSIONS.SQL
-- ====================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ====================================================================
-- 01_SCHEMA.SQL
-- ====================================================================

DROP SCHEMA IF EXISTS mottainai CASCADE;
CREATE SCHEMA IF NOT EXISTS mottainai;
CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
SET search_path TO mottainai, public;

-- ====================================================================
-- 02_ENUMS.SQL
-- ====================================================================

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_order_status') THEN
        CREATE TYPE purchase_order_status AS ENUM ('PENDING', 'APPROVED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'receiving_status') THEN
        CREATE TYPE receiving_status AS ENUM ('PENDING', 'CONFIRMED', 'DIVERGENT');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_status') THEN
        CREATE TYPE sale_status AS ENUM ('COMPLETED', 'CANCELED', 'RETURNED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'movement_type') THEN
        CREATE TYPE movement_type AS ENUM ('IN', 'OUT', 'ADJUSTMENT', 'TRANSFER', 'DONATION', 'DISPOSAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_type') THEN
        CREATE TYPE inventory_type AS ENUM ('NORMAL', 'CONSIGNED', 'QUARANTINE');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN
        CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        CREATE TYPE payment_method AS ENUM ('CASH', 'CARD', 'PIX', 'BOLETO');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_status') THEN
        CREATE TYPE inventory_status AS ENUM ('IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_status') THEN
        CREATE TYPE alert_status AS ENUM ('ACTIVE', 'ANALYZING', 'RESOLVED', 'IGNORED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type') THEN
        CREATE TYPE alert_type AS ENUM ('EXPIRATION', 'CRITICAL_STOCK', 'RUPTURE', 'SLOW_MOVING', 'OVERSTOCK');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_status') THEN
        CREATE TYPE suggested_action_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_type') THEN
        CREATE TYPE suggested_action_type AS ENUM ('PROMOTION', 'TRANSFER', 'DONATION', 'DISPOSAL', 'REORDER');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pre_list_status') THEN
        CREATE TYPE pre_list_status AS ENUM ('GENERATED', 'IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transfer_status') THEN
        CREATE TYPE transfer_status AS ENUM ('REQUESTED', 'IN_TRANSIT', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'donation_status') THEN
        CREATE TYPE donation_status AS ENUM ('REGISTERED', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_operation') THEN
        CREATE TYPE audit_operation AS ENUM ('INSERT', 'UPDATE', 'DELETE');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_model_type') THEN
        CREATE TYPE ai_model_type AS ENUM ('FORECAST', 'RECOMMENDATION', 'CLASSIFICATION', 'OPTIMIZATION');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
        CREATE TYPE event_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'log_level') THEN
        CREATE TYPE log_level AS ENUM ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'migration_type') THEN
        CREATE TYPE migration_type AS ENUM ('SQL', 'JAVA', 'GROOVY', 'SCRIPT');
    END IF;
END $$;

-- ====================================================================
-- 03_VALIDATION_FUNCTIONS.SQL (TODAS IMMUTABLE)
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_validate_cpf(p_cpf CHAR(11))
RETURNS BOOLEAN AS $$
DECLARE
    v_cpf TEXT;
    v_sum INTEGER := 0;
    v_remainder INTEGER;
    v_digit1 INTEGER;
    v_digit2 INTEGER;
    v_i INTEGER;
BEGIN
    v_cpf := regexp_replace(p_cpf, '[^0-9]', '', 'g');
    
    IF LENGTH(v_cpf) != 11 THEN
        RETURN FALSE;
    END IF;
    
    IF v_cpf ~ '^(\d)\1{10}$' THEN
        RETURN FALSE;
    END IF;
    
    v_sum := 0;
    FOR v_i IN 1..9 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cpf, v_i, 1) AS INTEGER) * (11 - v_i));
    END LOOP;
    
    v_remainder := (v_sum * 10) % 11;
    IF v_remainder = 10 THEN
        v_remainder := 0;
    END IF;
    
    v_digit1 := CAST(SUBSTRING(v_cpf, 10, 1) AS INTEGER);
    IF v_digit1 != v_remainder THEN
        RETURN FALSE;
    END IF;
    
    v_sum := 0;
    FOR v_i IN 1..10 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cpf, v_i, 1) AS INTEGER) * (12 - v_i));
    END LOOP;
    
    v_remainder := (v_sum * 10) % 11;
    IF v_remainder = 10 THEN
        v_remainder := 0;
    END IF;
    
    v_digit2 := CAST(SUBSTRING(v_cpf, 11, 1) AS INTEGER);
    IF v_digit2 != v_remainder THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_validate_email(p_email VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_email IS NULL OR 
           p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_validate_cnpj(p_cnpj CHAR(14))
RETURNS BOOLEAN AS $$
DECLARE
    v_cnpj TEXT;
    v_sum INTEGER := 0;
    v_remainder INTEGER;
    v_weight1 INTEGER;
    v_weight2 INTEGER;
    v_digit1 INTEGER;
    v_digit2 INTEGER;
    v_i INTEGER;
BEGIN
    v_cnpj := regexp_replace(p_cnpj, '[^0-9]', '', 'g');
    
    IF LENGTH(v_cnpj) != 14 THEN
        RETURN FALSE;
    END IF;
    
    IF v_cnpj ~ '^(\d)\1{13}$' THEN
        RETURN FALSE;
    END IF;
    
    v_sum := 0;
    v_weight1 := 5;
    FOR v_i IN 1..12 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cnpj, v_i, 1) AS INTEGER) * v_weight1);
        v_weight1 := CASE WHEN v_weight1 = 2 THEN 9 ELSE v_weight1 - 1 END;
    END LOOP;
    
    v_remainder := v_sum % 11;
    v_digit1 := CASE WHEN v_remainder < 2 THEN 0 ELSE 11 - v_remainder END;
    
    IF CAST(SUBSTRING(v_cnpj, 13, 1) AS INTEGER) != v_digit1 THEN
        RETURN FALSE;
    END IF;
    
    v_sum := 0;
    v_weight2 := 6;
    FOR v_i IN 1..13 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cnpj, v_i, 1) AS INTEGER) * v_weight2);
        v_weight2 := CASE WHEN v_weight2 = 2 THEN 9 ELSE v_weight2 - 1 END;
    END LOOP;
    
    v_remainder := v_sum % 11;
    v_digit2 := CASE WHEN v_remainder < 2 THEN 0 ELSE 11 - v_remainder END;
    
    IF CAST(SUBSTRING(v_cnpj, 14, 1) AS INTEGER) != v_digit2 THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ====================================================================
-- 04_SESSION_CONTEXT.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_set_session_context(
    p_user_id INTEGER,
    p_company_id INTEGER,
    p_store_id INTEGER DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, FALSE);
    PERFORM set_config('app.current_company_id', p_company_id::TEXT, FALSE);
    IF p_store_id IS NOT NULL THEN
        PERFORM set_config('app.current_store_id', p_store_id::TEXT, FALSE);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_current_user_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_user_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_get_current_company_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_company_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_get_current_store_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_store_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

-- ====================================================================
-- 05_MIGRATION_CONTROL.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS schema_version (
    version_id      BIGSERIAL PRIMARY KEY,
    version         VARCHAR(20) NOT NULL UNIQUE,
    description     VARCHAR(200) NOT NULL,
    type            migration_type NOT NULL DEFAULT 'SQL',
    script          VARCHAR(100) NOT NULL,
    checksum        VARCHAR(64),
    installed_by    VARCHAR(100) NOT NULL,
    installed_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    execution_time  INTEGER,
    success         BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_schema_version_version ON schema_version(version);
CREATE INDEX IF NOT EXISTS idx_schema_version_installed_at ON schema_version(installed_at);

-- ====================================================================
-- 06_CORE_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS subscription_plan (
    plan_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    price           DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    store_limit     INTEGER NOT NULL CHECK (store_limit > 0),
    user_limit      INTEGER NOT NULL CHECK (user_limit > 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS address (
    address_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zip_code        CHAR(8) NOT NULL CHECK (zip_code ~ '^\d{8}$'),
    street          VARCHAR(150) NOT NULL,
    number          VARCHAR(10) NOT NULL,
    complement      VARCHAR(100),
    neighborhood    VARCHAR(100) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    state           CHAR(2) NOT NULL CHECK (state ~ '^[A-Z]{2}$'),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS company (
    company_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_id         INTEGER NOT NULL REFERENCES subscription_plan(plan_id) ON DELETE RESTRICT,
    official_name   VARCHAR(150) NOT NULL,
    trade_name      VARCHAR(150),
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) NOT NULL CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS employee_role (
    role_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(80) NOT NULL UNIQUE,
    description     TEXT,
    permission_level INTEGER NOT NULL CHECK (permission_level >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS retail_store (
    store_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      INTEGER NOT NULL REFERENCES company(company_id) ON DELETE RESTRICT,
    address_id      INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
    name            VARCHAR(120) NOT NULL,
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS employee (
    employee_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    role_id         INTEGER NOT NULL REFERENCES employee_role(role_id) ON DELETE RESTRICT,
    name            VARCHAR(150) NOT NULL,
    cpf             CHAR(11) NOT NULL UNIQUE CHECK (fn_validate_cpf(cpf)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    hire_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_user (
    user_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id     INTEGER NOT NULL UNIQUE REFERENCES employee(employee_id) ON DELETE RESTRICT,
    email           VARCHAR(150) NOT NULL UNIQUE CHECK (fn_validate_email(email)),
    password_hash   VARCHAR(255) NOT NULL,
    last_login      TIMESTAMP,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product_category (
    category_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS supplier (
    supplier_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_id      INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
    trade_name      VARCHAR(150) NOT NULL,
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product (
    product_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id     INTEGER NOT NULL REFERENCES product_category(category_id) ON DELETE RESTRICT,
    sku             VARCHAR(50) NOT NULL UNIQUE,
    barcode         VARCHAR(30) NOT NULL UNIQUE,
    name            VARCHAR(150) NOT NULL,
    description     TEXT,
    brand           VARCHAR(100),
    unit_measure    VARCHAR(20) NOT NULL,
    weight          DECIMAL(10,3) CHECK (weight >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1
);

-- ====================================================================
-- 06B_FUNCTIONS_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_generate_sku(
    p_product_name VARCHAR(150),
    p_category_name VARCHAR(100),
    p_brand VARCHAR(100) DEFAULT NULL
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_sku VARCHAR(50);
    v_counter INTEGER := 0;
    v_base_sku VARCHAR(40);
    v_words TEXT[];
    v_word VARCHAR(50);
    v_abbr VARCHAR(50) := '';
    v_suffix VARCHAR(10);
BEGIN
    v_words := string_to_array(trim(regexp_replace(p_product_name, '[^a-zA-Z0-9 ]', '', 'g')), ' ');
    
    IF array_length(v_words, 1) >= 3 THEN
        FOR i IN 1..3 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 1));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSIF array_length(v_words, 1) = 2 THEN
        FOR i IN 1..2 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 3));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSE
        v_abbr := UPPER(SUBSTRING(p_product_name, 1, 6));
    END IF;
    
    IF p_category_name IS NOT NULL AND p_category_name != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_category_name, 1, 2));
    END IF;
    
    IF p_brand IS NOT NULL AND p_brand != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_brand, 1, 2));
    END IF;
    
    v_abbr := regexp_replace(v_abbr, '[^A-Z0-9-]', '', 'g');
    
    IF LENGTH(v_abbr) < 4 THEN
        v_abbr := v_abbr || LPAD('X', 6 - LENGTH(v_abbr), 'X');
    END IF;
    
    v_abbr := SUBSTRING(v_abbr, 1, 30);
    v_base_sku := v_abbr;
    
    LOOP
        v_suffix := '';
        IF v_counter > 0 THEN
            v_suffix := '-' || TO_CHAR(v_counter, 'FM000');
            v_sku := v_base_sku || v_suffix;
        ELSE
            v_sku := v_base_sku;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM product WHERE sku = v_sku AND deleted_at IS NULL) THEN
            RETURN v_sku;
        END IF;
        
        v_counter := v_counter + 1;
        
        IF v_counter > 999 THEN
            RETURN 'SKU-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' || 
                   LPAD((random() * 999)::INTEGER::TEXT, 3, '0');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_generate_product_sku(
    p_product_id INTEGER
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_product_name VARCHAR(150);
    v_category_name VARCHAR(100);
    v_brand VARCHAR(100);
    v_sku VARCHAR(50);
BEGIN
    SELECT 
        p.name,
        pc.name,
        p.brand
    INTO 
        v_product_name,
        v_category_name,
        v_brand
    FROM product p
    JOIN product_category pc ON pc.category_id = p.category_id
    WHERE p.product_id = p_product_id;
    
    v_sku := fn_generate_sku(v_product_name, v_category_name, v_brand);
    
    RETURN v_sku;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 06C_TRIGGER_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_trg_generate_sku()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        SELECT name INTO v_category_name 
        FROM product_category 
        WHERE category_id = NEW.category_id;
        
        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;
    
    IF EXISTS (SELECT 1 FROM product WHERE sku = NEW.sku AND product_id != NEW.product_id AND deleted_at IS NULL) THEN
        SELECT name INTO v_category_name 
        FROM product_category 
        WHERE category_id = NEW.category_id;
        
        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_generate_sku
    BEFORE INSERT ON product
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_generate_sku();

CREATE OR REPLACE FUNCTION fn_trg_update_sku_on_change()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF (OLD.name IS DISTINCT FROM NEW.name) OR 
       (OLD.category_id IS DISTINCT FROM NEW.category_id) OR
       (OLD.brand IS DISTINCT FROM NEW.brand) THEN
        
        SELECT name INTO v_category_name 
        FROM product_category 
        WHERE category_id = NEW.category_id;
        
        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_update_sku
    BEFORE UPDATE ON product
    FOR EACH ROW
    WHEN (OLD.name IS DISTINCT FROM NEW.name OR 
          OLD.category_id IS DISTINCT FROM NEW.category_id OR
          OLD.brand IS DISTINCT FROM NEW.brand)
    EXECUTE FUNCTION fn_trg_update_sku_on_change();

-- ====================================================================
-- 07_SUPPLIER_PRODUCT.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS supplier_product (
    supplier_product_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id     INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    supplier_code   VARCHAR(50),
    purchase_price  DECIMAL(10,2) NOT NULL CHECK (purchase_price >= 0),
    lead_time       INTEGER NOT NULL CHECK (lead_time >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    UNIQUE (supplier_id, product_id)
);

-- ====================================================================
-- 08_PURCHASE_ORDER.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS purchase_order (
    purchase_order_id INTEGER GENERATED ALWAYS AS IDENTITY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    supplier_id     INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    order_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    expected_delivery_date DATE,
    status          purchase_order_status NOT NULL DEFAULT 'PENDING',
    observation     TEXT,
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    PRIMARY KEY (purchase_order_id, order_date)
) PARTITION BY RANGE (order_date);

CREATE TABLE IF NOT EXISTS purchase_order_item (
    purchase_order_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    requested_quantity DECIMAL(10,3) NOT NULL CHECK (requested_quantity > 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal        DECIMAL(12,2) GENERATED ALWAYS AS (requested_quantity * unit_price) STORED,
    order_date      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (purchase_order_id, order_date) 
        REFERENCES purchase_order(purchase_order_id, order_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS receiving (
    receiving_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id INTEGER NOT NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    receiving_date  TIMESTAMP NOT NULL DEFAULT NOW(),
    status          receiving_status NOT NULL DEFAULT 'PENDING',
    observation     TEXT,
    order_date      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (purchase_order_id, order_date) 
        REFERENCES purchase_order(purchase_order_id, order_date) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS receiving_item (
    receiving_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receiving_id    INTEGER NOT NULL REFERENCES receiving(receiving_id) ON DELETE CASCADE,
    purchase_order_item_id INTEGER NOT NULL REFERENCES purchase_order_item(purchase_order_item_id) ON DELETE RESTRICT,
    received_quantity DECIMAL(10,3) NOT NULL CHECK (received_quantity >= 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    manufacture_date DATE,
    expiration_date DATE NOT NULL,
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (manufacture_date IS NULL OR manufacture_date <= expiration_date)
);

-- ====================================================================
-- 09_INVENTORY.SQL
-- ====================================================================

CREATE SEQUENCE IF NOT EXISTS batch_code_seq START 1;

CREATE TABLE IF NOT EXISTS batch (
    batch_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    receiving_item_id INTEGER REFERENCES receiving_item(receiving_item_id) ON DELETE SET NULL,
    batch_code      VARCHAR(60) NOT NULL UNIQUE,
    manufacture_date DATE,
    expiration_date DATE NOT NULL,
    initial_quantity DECIMAL(10,3) NOT NULL CHECK (initial_quantity > 0),
    unit_cost       DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    CHECK (manufacture_date IS NULL OR manufacture_date <= expiration_date)
);

CREATE TABLE IF NOT EXISTS inventory (
    inventory_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    inventory_type  inventory_type NOT NULL DEFAULT 'NORMAL',
    current_quantity DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
    minimum_quantity DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (minimum_quantity >= 0),
    maximum_quantity DECIMAL(10,3) CHECK (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity),
    location        VARCHAR(80),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    UNIQUE (store_id, batch_id, inventory_type)
);

-- ====================================================================
-- 10_INVENTORY_MOVEMENT.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS inventory_movement (
    movement_id     INTEGER GENERATED ALWAYS AS IDENTITY,
    inventory_id    INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT,
    employee_id     INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    movement_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    movement_type   movement_type NOT NULL,
    moved_quantity  DECIMAL(10,3) NOT NULL CHECK (moved_quantity <> 0),
    previous_balance DECIMAL(10,3) NOT NULL CHECK (previous_balance >= 0),
    current_balance DECIMAL(10,3) NOT NULL CHECK (current_balance >= 0),
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    store_id        INTEGER,
    CONSTRAINT ck_movement_direction CHECK (
        (movement_type IN ('OUT', 'DISPOSAL') AND moved_quantity < 0) OR
        (movement_type IN ('IN') AND moved_quantity > 0) OR
        (movement_type IN ('ADJUSTMENT', 'TRANSFER', 'DONATION') AND moved_quantity <> 0)
    ),
    PRIMARY KEY (movement_id, movement_date)
) PARTITION BY RANGE (movement_date);

-- ====================================================================
-- 11_SALES.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS sales_transaction (
    sale_id         INTEGER GENERATED ALWAYS AS IDENTITY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    sale_date       TIMESTAMP NOT NULL DEFAULT NOW(),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    payment_method  payment_method NOT NULL,
    status          sale_status NOT NULL DEFAULT 'COMPLETED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    PRIMARY KEY (sale_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS sale_item (
    sale_item_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id         INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    batch_id        INTEGER REFERENCES batch(batch_id) ON DELETE SET NULL,
    quantity_sold   DECIMAL(10,3) NOT NULL CHECK (quantity_sold > 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal        DECIMAL(12,2) GENERATED ALWAYS AS (quantity_sold * unit_price) STORED,
    sale_date       TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date) 
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE CASCADE
);

-- ====================================================================
-- 12_ALERTS_AND_ACTIONS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS alert (
    alert_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    title           VARCHAR(120) NOT NULL,
    description     TEXT,
    alert_type      alert_type NOT NULL,
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    status          alert_status NOT NULL DEFAULT 'ACTIVE',
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (resolved_at IS NULL OR resolved_at >= generated_at)
);

CREATE TABLE IF NOT EXISTS suggested_action (
    suggested_action_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_id        INTEGER NOT NULL REFERENCES alert(alert_id) ON DELETE RESTRICT,
    action_type     suggested_action_type NOT NULL,
    description     TEXT,
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    status          suggested_action_status NOT NULL DEFAULT 'PENDING',
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- 13_TRANSFERS_DONATIONS_DISPOSALS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS transfer (
    transfer_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    source_store_id INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    destination_store_id INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    request_date    TIMESTAMP NOT NULL DEFAULT NOW(),
    completion_date TIMESTAMP,
    status          transfer_status NOT NULL DEFAULT 'REQUESTED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1,
    CHECK (source_store_id <> destination_store_id),
    CHECK (completion_date IS NULL OR completion_date >= request_date)
);

CREATE TABLE IF NOT EXISTS transfer_item (
    transfer_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id     INTEGER NOT NULL REFERENCES transfer(transfer_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    transferred_quantity DECIMAL(10,3) NOT NULL CHECK (transferred_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS donation (
    donation_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    institution     VARCHAR(150) NOT NULL,
    donation_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    status          donation_status NOT NULL DEFAULT 'REGISTERED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS donation_item (
    donation_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id     INTEGER NOT NULL REFERENCES donation(donation_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    donated_quantity DECIMAL(10,3) NOT NULL CHECK (donated_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS disposal (
    disposal_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    reason          VARCHAR(100) NOT NULL,
    disposal_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS disposal_item (
    disposal_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    disposal_id     INTEGER NOT NULL REFERENCES disposal(disposal_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    disposed_quantity DECIMAL(10,3) NOT NULL CHECK (disposed_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- 14_REPLENISHMENT.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS replenishment_pre_list (
    pre_list_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    status          pre_list_status NOT NULL DEFAULT 'GENERATED',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS replenishment_pre_list_item (
    pre_list_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pre_list_id     INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE CASCADE,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    suggested_quantity DECIMAL(10,3) NOT NULL CHECK (suggested_quantity > 0),
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS replenishment_execution (
    execution_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pre_list_id     INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    start_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    end_date        TIMESTAMP,
    rating          INTEGER CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS replenishment_execution_item (
    execution_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    execution_id    INTEGER NOT NULL REFERENCES replenishment_execution(execution_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    replenished_quantity DECIMAL(10,3) NOT NULL CHECK (replenished_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- 15_AUDIT_AND_LOGS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    audit_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    table_affected  VARCHAR(60) NOT NULL,
    operation       audit_operation NOT NULL,
    record_id       TEXT NOT NULL,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    old_data        JSONB,
    new_data        JSONB,
    operation_date  TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (audit_id, operation_date)
) PARTITION BY RANGE (operation_date);

CREATE TABLE IF NOT EXISTS system_log (
    log_id          BIGSERIAL PRIMARY KEY,
    log_level       log_level NOT NULL,
    module          VARCHAR(50),
    message         TEXT NOT NULL,
    stack_trace     TEXT,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    ip_address      INET,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS error_log (
    error_id        BIGSERIAL PRIMARY KEY,
    error_code      VARCHAR(20),
    error_message   TEXT NOT NULL,
    function_name   VARCHAR(100),
    parameters      JSONB,
    stack_trace     TEXT,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS integration_log (
    integration_id  BIGSERIAL PRIMARY KEY,
    integration_type VARCHAR(50) NOT NULL,
    direction       VARCHAR(10) NOT NULL,
    payload         JSONB,
    response        JSONB,
    status          VARCHAR(20) NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS job_log (
    job_id          BIGSERIAL PRIMARY KEY,
    job_name        VARCHAR(100) NOT NULL,
    job_type        VARCHAR(50),
    start_time      TIMESTAMP NOT NULL,
    end_time        TIMESTAMP,
    duration_seconds INTEGER,
    records_processed INTEGER,
    success         BOOLEAN,
    details         JSONB,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- 16_HISTORY_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS product_history (
    history_id      BIGSERIAL PRIMARY KEY,
    product_id      INTEGER REFERENCES product(product_id) ON DELETE CASCADE,
    field_name      VARCHAR(50) NOT NULL,
    old_value       TEXT,
    new_value       TEXT,
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS supplier_history (
    history_id      BIGSERIAL PRIMARY KEY,
    supplier_id     INTEGER REFERENCES supplier(supplier_id) ON DELETE CASCADE,
    field_name      VARCHAR(50) NOT NULL,
    old_value       TEXT,
    new_value       TEXT,
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_price_history (
    price_history_id BIGSERIAL PRIMARY KEY,
    product_id      INTEGER REFERENCES product(product_id) ON DELETE CASCADE,
    old_price       DECIMAL(10,2),
    new_price       DECIMAL(10,2),
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- 17_AI_MODULE.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS ai_model (
    model_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    version         VARCHAR(20) NOT NULL,
    model_type      ai_model_type NOT NULL,
    description     TEXT,
    parameters      JSONB,
    accuracy        DECIMAL(5,2),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (name, version)
);

CREATE TABLE IF NOT EXISTS ai_prediction (
    prediction_id   BIGSERIAL PRIMARY KEY,
    model_id        INTEGER NOT NULL REFERENCES ai_model(model_id) ON DELETE RESTRICT,
    product_id      INTEGER REFERENCES product(product_id) ON DELETE SET NULL,
    store_id        INTEGER REFERENCES retail_store(store_id) ON DELETE SET NULL,
    predicted_date  DATE NOT NULL,
    confidence      DECIMAL(5,2),
    predicted_quantity DECIMAL(10,3),
    actual_quantity DECIMAL(10,3),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_recommendation (
    recommendation_id BIGSERIAL PRIMARY KEY,
    prediction_id   INTEGER REFERENCES ai_prediction(prediction_id) ON DELETE CASCADE,
    action_type     suggested_action_type NOT NULL,
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    reason          TEXT,
    status          suggested_action_status NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_feedback (
    feedback_id     BIGSERIAL PRIMARY KEY,
    recommendation_id INTEGER NOT NULL REFERENCES ai_recommendation(recommendation_id) ON DELETE CASCADE,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    rating          INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_execution (
    execution_id    BIGSERIAL PRIMARY KEY,
    recommendation_id INTEGER NOT NULL REFERENCES ai_recommendation(recommendation_id) ON DELETE CASCADE,
    executed_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    result          JSONB,
    success         BOOLEAN NOT NULL DEFAULT TRUE
);

-- ====================================================================
-- 18_EVENTS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS event_queue (
    event_id        BIGSERIAL PRIMARY KEY,
    event_type      VARCHAR(50) NOT NULL,
    event_data      JSONB NOT NULL,
    priority        INTEGER DEFAULT 5,
    status          event_status NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMP,
    retry_count     INTEGER DEFAULT 0,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_event_queue_status ON event_queue(status, priority);
CREATE INDEX IF NOT EXISTS idx_event_queue_created ON event_queue(created_at);

-- ====================================================================
-- 19_KPI_CACHE.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS kpi_cache (
    cache_id        BIGSERIAL PRIMARY KEY,
    store_id        INTEGER REFERENCES retail_store(store_id) ON DELETE CASCADE,
    kpi_name        VARCHAR(50) NOT NULL,
    kpi_value       JSONB NOT NULL,
    calculated_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMP NOT NULL,
    UNIQUE (store_id, kpi_name)
);

CREATE INDEX IF NOT EXISTS idx_kpi_cache_expires ON kpi_cache(expires_at);

-- ====================================================================
-- 20_PERFORMANCE_MONITORING.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS query_performance (
    performance_id  BIGSERIAL PRIMARY KEY,
    function_name   VARCHAR(100) NOT NULL,
    execution_time_ms INTEGER NOT NULL,
    rows_affected   INTEGER,
    parameters      JSONB,
    executed_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_query_performance_executed ON query_performance(executed_at);
CREATE INDEX IF NOT EXISTS idx_query_performance_function ON query_performance(function_name);

-- ====================================================================
-- 21_ARCHIVE_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS audit_log_archive (LIKE audit_log);
CREATE TABLE IF NOT EXISTS inventory_movement_archive (LIKE inventory_movement);
CREATE TABLE IF NOT EXISTS sales_transaction_archive (LIKE sales_transaction);

-- ====================================================================
-- 22_INDEXES.SQL - SEM FUNÇÕES NÃO IMUTÁVEIS (CORRIGIDO)
-- ====================================================================

-- Índices Únicos
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_cpf_global ON employee(cpf) WHERE active = true AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_cnpj_global ON supplier(cnpj) WHERE active = true AND deleted_at IS NULL;

-- Índices Parciais - APENAS COM COLUNAS, SEM FUNÇÕES
CREATE INDEX IF NOT EXISTS idx_product_active_name ON product(name) WHERE active = true AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_category_active ON product_category(name) WHERE active = true AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_positive ON inventory(store_id, batch_id) 
WHERE current_quantity > 0 AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_alert_active_store ON alert(store_id, priority) WHERE status = 'ACTIVE';

-- CORREÇÃO: REMOVIDO date_trunc do índice
-- CREATE INDEX IF NOT EXISTS idx_sales_current_month ON sales_transaction(store_id, sale_date) 
-- WHERE sale_date >= date_trunc('month', CURRENT_DATE) AND deleted_at IS NULL;

-- CORREÇÃO: REMOVIDO status IN do índice (usa enum)
-- CREATE INDEX IF NOT EXISTS idx_purchase_order_pending ON purchase_order(supplier_id) 
-- WHERE status = 'PENDING' AND deleted_at IS NULL;

-- Índices Compostos
CREATE INDEX IF NOT EXISTS idx_alert_store_status_created ON alert(store_id, status, created_at) 
WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_batch_product_expiration ON batch(product_id, expiration_date) 
WHERE active = true AND deleted_at IS NULL;

-- CORREÇÃO: REMOVIDO date_trunc do índice
-- CREATE INDEX IF NOT EXISTS idx_movement_store_date ON inventory_movement(store_id, movement_date) 
-- WHERE movement_date >= date_trunc('month', CURRENT_DATE) - interval '3 months';

-- CORREÇÃO: REMOVIDO status IN do índice
-- CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier_status ON purchase_order(supplier_id, status) 
-- WHERE status IN ('APPROVED', 'PENDING') AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_store_product ON inventory(store_id, batch_id) 
WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_store_status_date ON sales_transaction(store_id, status, sale_date) 
WHERE deleted_at IS NULL;

-- Índices para Foreign Keys (todos sem funções)
CREATE INDEX IF NOT EXISTS idx_product_category_id ON product(category_id);
CREATE INDEX IF NOT EXISTS idx_supplier_product_supplier_id ON supplier_product(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_product_product_id ON supplier_product(product_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_store_id ON purchase_order(store_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier_id ON purchase_order(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_employee_id ON purchase_order(employee_id);
CREATE INDEX IF NOT EXISTS idx_receiving_purchase_order_id ON receiving(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_receiving_employee_id ON receiving(employee_id);
CREATE INDEX IF NOT EXISTS idx_receiving_item_receiving_id ON receiving_item(receiving_id);
CREATE INDEX IF NOT EXISTS idx_receiving_item_order_item_id ON receiving_item(purchase_order_item_id);
CREATE INDEX IF NOT EXISTS idx_batch_product_id ON batch(product_id);
CREATE INDEX IF NOT EXISTS idx_batch_receiving_item_id ON batch(receiving_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_batch_id ON inventory(batch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movement_inventory_id ON inventory_movement(inventory_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_id ON sale_item(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_product_id ON sale_item(product_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_batch_id ON sale_item(batch_id);
CREATE INDEX IF NOT EXISTS idx_alert_store_id ON alert(store_id);
CREATE INDEX IF NOT EXISTS idx_transfer_source_store ON transfer(source_store_id);
CREATE INDEX IF NOT EXISTS idx_transfer_destination_store ON transfer(destination_store_id);
CREATE INDEX IF NOT EXISTS idx_donation_store_id ON donation(store_id);
CREATE INDEX IF NOT EXISTS idx_disposal_store_id ON disposal(store_id);

-- ====================================================================
-- 23_PARTITION_FUNCTIONS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION sp_create_future_partitions()
RETURNS VOID AS $$
DECLARE
    v_date DATE;
    v_partition_name TEXT;
    v_schema TEXT := 'mottainai';
    v_tables TEXT[] := ARRAY['inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_date IN 
            SELECT generate_series(
                DATE_TRUNC('month', NOW()),
                DATE_TRUNC('month', NOW() + interval '6 months'),
                interval '1 month'
            )::DATE
        LOOP
            v_partition_name := v_table || '_' || TO_CHAR(v_date, 'YYYY_MM');
            
            EXECUTE format('
                CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I
                FOR VALUES FROM (%L) TO (%L)
            ', v_schema, v_partition_name, v_schema, v_table, 
               v_date, v_date + interval '1 month');
        END LOOP;
    END LOOP;
    
    RAISE NOTICE 'Future partitions created for 6 months ahead';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_drop_old_partitions(p_months_to_keep INTEGER DEFAULT 12)
LANGUAGE plpgsql AS $$
DECLARE
    v_cutoff_date DATE := DATE_TRUNC('month', NOW()) - (p_months_to_keep || ' months')::INTERVAL;
    v_partition RECORD;
    v_tables TEXT[] := ARRAY['inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_partition IN
            SELECT 
                schemaname,
                tablename,
                partitionrangestart
            FROM pg_partitions
            WHERE schemaname = 'mottainai'
              AND tablename LIKE v_table || '_%'
              AND partitionrangestart::DATE < v_cutoff_date
        LOOP
            EXECUTE format('
                DROP TABLE IF EXISTS %I.%I
            ', v_partition.schemaname, v_partition.tablename);
            
            RAISE NOTICE 'Dropped partition: %.%', v_partition.schemaname, v_partition.tablename;
        END LOOP;
    END LOOP;
    
    RAISE NOTICE 'Old partitions dropped (keeping % months)', p_months_to_keep;
END;
$$;

-- ====================================================================
-- 24_PARTITION_CREATION.SQL
-- ====================================================================

SELECT sp_create_future_partitions();

-- ====================================================================
-- 25_FUNCTIONS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_calculate_average_consumption(
    p_product_id INTEGER,
    p_store_id INTEGER,
    p_days INTEGER DEFAULT 30
) RETURNS DECIMAL(10,3) AS $$
DECLARE
    v_total_output DECIMAL(12,3);
BEGIN
    SELECT COALESCE(SUM(ABS(im.moved_quantity)), 0)
    INTO v_total_output
    FROM inventory_movement im
    JOIN inventory i ON i.inventory_id = im.inventory_id
    JOIN batch b ON b.batch_id = i.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND im.movement_type = 'OUT'
      AND im.movement_date >= NOW() - (p_days || ' days')::INTERVAL
      AND i.deleted_at IS NULL
      AND b.deleted_at IS NULL;
    
    IF p_days <= 0 OR v_total_output = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN ROUND(v_total_output / p_days, 3);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_coverage(
    p_product_id INTEGER,
    p_store_id INTEGER
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    v_current_stock DECIMAL(12,3);
    v_avg_consumption DECIMAL(10,3);
BEGIN
    SELECT COALESCE(SUM(i.current_quantity), 0)
    INTO v_current_stock
    FROM inventory i
    JOIN batch b ON b.batch_id = i.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND i.deleted_at IS NULL
      AND b.deleted_at IS NULL;
    
    v_avg_consumption := fn_calculate_average_consumption(p_product_id, p_store_id, 30);
    
    IF v_avg_consumption IS NULL OR v_avg_consumption = 0 THEN
        RETURN NULL;
    END IF;
    
    RETURN ROUND(v_current_stock / v_avg_consumption, 2);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_criticality(
    p_product_id INTEGER,
    p_store_id INTEGER
) RETURNS priority_level AS $$
DECLARE
    v_coverage DECIMAL(10,2);
BEGIN
    v_coverage := fn_calculate_coverage(p_product_id, p_store_id);
    
    IF v_coverage IS NULL THEN
        RETURN 'MEDIUM'::priority_level;
    ELSIF v_coverage <= 2 THEN
        RETURN 'CRITICAL'::priority_level;
    ELSIF v_coverage <= 5 THEN
        RETURN 'HIGH'::priority_level;
    ELSIF v_coverage <= 10 THEN
        RETURN 'MEDIUM'::priority_level;
    ELSE
        RETURN 'LOW'::priority_level;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_economy(
    p_store_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
) RETURNS DECIMAL(12,2) AS $$
DECLARE
    v_total_sales DECIMAL(12,2);
    v_total_cost DECIMAL(12,2);
BEGIN
    SELECT COALESCE(SUM(total_amount), 0)
    INTO v_total_sales
    FROM sales_transaction
    WHERE store_id = p_store_id
      AND sale_date BETWEEN p_start_date AND p_end_date
      AND status = 'COMPLETED'
      AND deleted_at IS NULL;
    
    SELECT COALESCE(SUM(si.quantity_sold * COALESCE(b.unit_cost, 0)), 0)
    INTO v_total_cost
    FROM sale_item si
    JOIN sales_transaction st ON st.sale_id = si.sale_id
    LEFT JOIN batch b ON b.batch_id = si.batch_id
    WHERE st.store_id = p_store_id
      AND st.sale_date BETWEEN p_start_date AND p_end_date
      AND st.status = 'COMPLETED'
      AND st.deleted_at IS NULL;
    
    RETURN ROUND(v_total_sales - v_total_cost, 2);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_select_batch_fefo(
    p_product_id INTEGER,
    p_store_id INTEGER,
    p_quantity DECIMAL(10,3)
) RETURNS INTEGER AS $$
DECLARE
    v_batch_id INTEGER;
BEGIN
    SELECT b.batch_id
    INTO v_batch_id
    FROM batch b
    JOIN inventory i ON i.batch_id = b.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND b.active = TRUE
      AND i.current_quantity >= p_quantity
      AND b.deleted_at IS NULL
      AND i.deleted_at IS NULL
    ORDER BY b.expiration_date ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;
    
    RETURN v_batch_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_atomic_update_inventory(
    p_inventory_id INTEGER,
    p_quantity DECIMAL,
    p_movement_type movement_type,
    p_employee_id INTEGER DEFAULT NULL,
    p_observation TEXT DEFAULT NULL,
    p_expected_version INTEGER DEFAULT NULL
) RETURNS DECIMAL AS $$
DECLARE
    v_new_quantity DECIMAL;
    v_current_version INTEGER;
    v_previous_balance DECIMAL;
    v_store_id INTEGER;
BEGIN
    SELECT current_quantity, version, store_id 
    INTO v_previous_balance, v_current_version, v_store_id
    FROM inventory
    WHERE inventory_id = p_inventory_id
    FOR UPDATE;
    
    IF v_previous_balance IS NULL THEN
        RAISE EXCEPTION 'Inventory % not found', p_inventory_id;
    END IF;
    
    IF p_expected_version IS NOT NULL AND p_expected_version != v_current_version THEN
        RAISE EXCEPTION 'Inventory % was modified by another transaction (version %)', 
            p_inventory_id, v_current_version;
    END IF;
    
    v_new_quantity := v_previous_balance + p_quantity;
    
    IF v_new_quantity < 0 THEN
        RAISE EXCEPTION 'Insufficient stock for inventory % (balance: %, requested: %)', 
            p_inventory_id, v_previous_balance, p_quantity;
    END IF;
    
    UPDATE inventory
    SET current_quantity = v_new_quantity,
        updated_at = NOW(),
        version = version + 1
    WHERE inventory_id = p_inventory_id
      AND version = v_current_version
    RETURNING current_quantity INTO v_new_quantity;
    
    INSERT INTO inventory_movement (
        inventory_id,
        employee_id,
        movement_date,
        movement_type,
        moved_quantity,
        previous_balance,
        current_balance,
        observation,
        store_id
    ) VALUES (
        p_inventory_id,
        p_employee_id,
        NOW(),
        p_movement_type,
        p_quantity,
        v_previous_balance,
        v_new_quantity,
        p_observation,
        v_store_id
    );
    
    RETURN v_new_quantity;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_publish_event(
    p_event_type VARCHAR(50),
    p_event_data JSONB,
    p_priority INTEGER DEFAULT 5
) RETURNS BIGINT AS $$
DECLARE
    v_event_id BIGINT;
BEGIN
    INSERT INTO event_queue (event_type, event_data, priority)
    VALUES (p_event_type, p_event_data, p_priority)
    RETURNING event_id INTO v_event_id;
    
    PERFORM pg_notify('mottainai_event', 
        json_build_object('event_id', v_event_id, 'type', p_event_type)::TEXT);
    
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 26_TRIGGERS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_soft_delete_product()
RETURNS TRIGGER AS $$
BEGIN
    NEW.active = false;
    NEW.deleted_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_soft_delete_product
    BEFORE UPDATE OF active ON product
    FOR EACH ROW
    WHEN (NEW.active = false AND OLD.active = true)
    EXECUTE FUNCTION fn_soft_delete_product();

CREATE OR REPLACE FUNCTION fn_trg_create_batch() RETURNS TRIGGER AS $$
DECLARE
    v_batch_code VARCHAR(60);
    v_product_id INTEGER;
    v_unit_price DECIMAL(10,2);
BEGIN
    SELECT po_item.product_id, po_item.unit_price
    INTO v_product_id, v_unit_price
    FROM purchase_order_item po_item
    WHERE po_item.purchase_order_item_id = NEW.purchase_order_item_id;
    
    v_batch_code := 'BATCH-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
                     LPAD(NEXTVAL('batch_code_seq')::TEXT, 6, '0');
    
    INSERT INTO batch (
        product_id,
        receiving_item_id,
        batch_code,
        manufacture_date,
        expiration_date,
        initial_quantity,
        unit_cost
    ) VALUES (
        v_product_id,
        NEW.receiving_item_id,
        v_batch_code,
        NEW.manufacture_date,
        NEW.expiration_date,
        NEW.received_quantity,
        NEW.unit_price
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO error_log (error_message, function_name, parameters)
        VALUES (SQLERRM, 'fn_trg_create_batch', 
                jsonb_build_object('receiving_item_id', NEW.receiving_item_id));
        RAISE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_create_batch
    AFTER INSERT ON receiving_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_create_batch();

CREATE OR REPLACE FUNCTION fn_trg_select_batch_fefo() RETURNS TRIGGER AS $$
DECLARE
    v_store_id INTEGER;
    v_batch_id INTEGER;
BEGIN
    IF NEW.batch_id IS NOT NULL THEN
        RETURN NEW;
    END IF;
    
    SELECT s.store_id INTO v_store_id
    FROM sales_transaction s
    WHERE s.sale_id = NEW.sale_id;
    
    v_batch_id := fn_select_batch_fefo(NEW.product_id, v_store_id, NEW.quantity_sold);
    
    IF v_batch_id IS NULL THEN
        RAISE EXCEPTION 'Insufficient stock for product % in store % (FEFO selection failed)',
            NEW.product_id, v_store_id;
    END IF;
    
    NEW.batch_id := v_batch_id;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO error_log (error_message, function_name, parameters)
        VALUES (SQLERRM, 'fn_trg_select_batch_fefo', 
                jsonb_build_object('sale_id', NEW.sale_id, 'product_id', NEW.product_id));
        RAISE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_select_batch_fefo
    BEFORE INSERT ON sale_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_select_batch_fefo();

CREATE OR REPLACE FUNCTION fn_trg_audit_log() RETURNS TRIGGER AS $$
DECLARE
    v_user_id INTEGER;
    v_record_id TEXT;
BEGIN
    v_user_id := fn_get_current_user_id();
    
    BEGIN
        v_record_id := COALESCE(
            (to_jsonb(NEW)->>TG_ARGV[0]),
            (to_jsonb(OLD)->>TG_ARGV[0]),
            '0'
        );
    EXCEPTION WHEN OTHERS THEN
        v_record_id := '0';
    END;
    
    INSERT INTO audit_log (
        table_affected,
        operation,
        record_id,
        user_id,
        old_data,
        new_data,
        operation_date
    )
    VALUES (
        TG_TABLE_NAME,
        TG_OP::audit_operation,
        v_record_id,
        v_user_id,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) ELSE NULL END,
        NOW()
    );
    
    RETURN COALESCE(NEW, OLD);
EXCEPTION
    WHEN OTHERS THEN
        RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_audit_disposal
    AFTER INSERT OR UPDATE OR DELETE ON disposal
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('disposal_id');

CREATE OR REPLACE TRIGGER trg_audit_transfer
    AFTER INSERT OR UPDATE OR DELETE ON transfer
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('transfer_id');

CREATE OR REPLACE TRIGGER trg_audit_donation
    AFTER INSERT OR UPDATE OR DELETE ON donation
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('donation_id');

CREATE OR REPLACE FUNCTION fn_trg_product_history() RETURNS TRIGGER AS $$
DECLARE
    v_user_id INTEGER := fn_get_current_user_id();
BEGIN
    IF OLD IS NOT NULL AND NEW IS NOT NULL THEN
        IF OLD.name IS DISTINCT FROM NEW.name THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'name', OLD.name, NEW.name, v_user_id);
        END IF;
        
        IF OLD.brand IS DISTINCT FROM NEW.brand THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'brand', OLD.brand, NEW.brand, v_user_id);
        END IF;
        
        IF OLD.weight IS DISTINCT FROM NEW.weight THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'weight', OLD.weight::TEXT, NEW.weight::TEXT, v_user_id);
        END IF;
        
        IF OLD.unit_measure IS DISTINCT FROM NEW.unit_measure THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'unit_measure', OLD.unit_measure, NEW.unit_measure, v_user_id);
        END IF;
    END IF;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_history
    BEFORE UPDATE ON product
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_product_history();

-- ====================================================================
-- 27_VIEWS.SQL
-- ====================================================================

CREATE OR REPLACE VIEW vw_expiring_products AS
SELECT 
    b.batch_id,
    b.batch_code,
    p.product_id,
    p.name AS product,
    s.store_id,
    s.name AS store,
    b.expiration_date,
    (b.expiration_date - CURRENT_DATE) AS days_to_expire,
    i.current_quantity
FROM batch b
JOIN inventory i ON i.batch_id = b.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE b.active = TRUE
  AND i.current_quantity > 0
  AND b.deleted_at IS NULL
  AND i.deleted_at IS NULL
  AND b.expiration_date <= CURRENT_DATE + INTERVAL '15 days'
ORDER BY b.expiration_date ASC;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT 
    i.inventory_id,
    p.product_id,
    p.name AS product,
    i.store_id,
    s.name AS store,
    i.current_quantity,
    i.minimum_quantity
FROM inventory i
JOIN batch b ON b.batch_id = i.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE i.current_quantity < i.minimum_quantity
  AND i.deleted_at IS NULL
  AND b.deleted_at IS NULL
ORDER BY i.current_quantity ASC;

CREATE OR REPLACE VIEW vw_stock_coverage AS
SELECT 
    p.product_id,
    p.name AS product_name,
    s.store_id,
    s.name AS store_name,
    COALESCE(SUM(i.current_quantity), 0) AS total_stock,
    fn_calculate_average_consumption(p.product_id, s.store_id, 30) AS daily_consumption,
    fn_calculate_coverage(p.product_id, s.store_id) AS days_coverage,
    fn_calculate_criticality(p.product_id, s.store_id) AS criticality
FROM product p
CROSS JOIN retail_store s
LEFT JOIN inventory i ON i.store_id = s.store_id
LEFT JOIN batch b ON b.batch_id = i.batch_id AND b.product_id = p.product_id
WHERE s.active = TRUE
  AND s.deleted_at IS NULL
  AND p.active = TRUE
  AND p.deleted_at IS NULL
GROUP BY p.product_id, p.name, s.store_id, s.name;

CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT 
    DATE_TRUNC('month', sale_date) AS month,
    store_id,
    COUNT(*) AS total_sales,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_ticket,
    COUNT(DISTINCT employee_id) AS active_sellers
FROM sales_transaction
WHERE status = 'COMPLETED'
  AND deleted_at IS NULL
GROUP BY DATE_TRUNC('month', sale_date), store_id;

-- ====================================================================
-- 28_MATERIALIZED_VIEWS.SQL
-- ====================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_dashboard_metrics AS
WITH stats AS (
    SELECT 
        s.store_id,
        COUNT(DISTINCT a.alert_id) AS alerts,
        COUNT(DISTINCT i.inventory_id) AS ruptures,
        COUNT(DISTINCT st.sale_id) AS transactions,
        COALESCE(SUM(st.total_amount), 0) AS revenue,
        COALESCE(AVG(st.total_amount), 0) AS avg_ticket
    FROM retail_store s
    LEFT JOIN alert a ON a.store_id = s.store_id AND a.status = 'ACTIVE'
    LEFT JOIN inventory i ON i.store_id = s.store_id AND i.current_quantity < i.minimum_quantity
        AND i.deleted_at IS NULL
    LEFT JOIN sales_transaction st ON st.store_id = s.store_id 
        AND st.sale_date >= CURRENT_DATE - INTERVAL '1 day'
        AND st.status = 'COMPLETED'
        AND st.deleted_at IS NULL
    WHERE s.active = TRUE
      AND s.deleted_at IS NULL
    GROUP BY s.store_id
)
SELECT 
    store_id,
    (SELECT name FROM retail_store WHERE store_id = stats.store_id) AS store_name,
    alerts AS active_alerts,
    ruptures AS products_in_rupture,
    revenue AS daily_revenue,
    avg_ticket,
    transactions AS daily_transactions,
    (SELECT COUNT(DISTINCT product_id) FROM sale_item si 
     JOIN sales_transaction st ON st.sale_id = si.sale_id 
     WHERE st.store_id = stats.store_id 
       AND st.sale_date >= CURRENT_DATE - INTERVAL '1 day'
       AND st.deleted_at IS NULL) AS products_sold,
    fn_calculate_economy(store_id, DATE_TRUNC('month', CURRENT_DATE)::DATE, CURRENT_DATE) AS monthly_economy
FROM stats;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_dashboard_store ON mv_dashboard_metrics(store_id);

-- ====================================================================
-- 29_ROW_LEVEL_SECURITY.SQL
-- ====================================================================

ALTER TABLE company ENABLE ROW LEVEL SECURITY;
ALTER TABLE retail_store ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_policy ON company
    USING (company_id = fn_get_current_company_id());

CREATE POLICY store_policy ON retail_store
    USING (company_id = fn_get_current_company_id());

CREATE POLICY employee_policy ON employee
    USING (store_id IN (
        SELECT store_id FROM retail_store 
        WHERE company_id = fn_get_current_company_id()
    ));

CREATE POLICY inventory_policy ON inventory
    USING (store_id IN (
        SELECT store_id FROM retail_store 
        WHERE company_id = fn_get_current_company_id()
    ));

CREATE POLICY sales_policy ON sales_transaction
    USING (store_id IN (
        SELECT store_id FROM retail_store 
        WHERE company_id = fn_get_current_company_id()
    ));

CREATE POLICY purchase_order_policy ON purchase_order
    USING (store_id IN (
        SELECT store_id FROM retail_store 
        WHERE company_id = fn_get_current_company_id()
    ));

-- ====================================================================
-- 30_TESTES.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION test_01_validation()
RETURNS TEXT AS $$
BEGIN
    IF NOT fn_validate_cpf('12345678909') THEN
        RETURN 'FAIL: Valid CPF rejected';
    END IF;
    
    IF fn_validate_cpf('11111111111') THEN
        RETURN 'FAIL: Invalid CPF accepted';
    END IF;
    
    IF NOT fn_validate_cnpj('12345678901234') THEN
        RETURN 'FAIL: Valid CNPJ rejected';
    END IF;
    
    IF fn_validate_cnpj('11111111111111') THEN
        RETURN 'FAIL: Invalid CNPJ accepted';
    END IF;
    
    RETURN 'PASS: Validation tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_02_fefo()
RETURNS TEXT AS $$
DECLARE
    v_product_id INTEGER;
    v_store_id INTEGER;
    v_old_batch_id INTEGER;
    v_new_batch_id INTEGER;
    v_batch_id INTEGER;
BEGIN
    INSERT INTO product (name, barcode, unit_measure)
    VALUES ('Test Product FEFO', 'BARCODE001', 'UN')
    RETURNING product_id INTO v_product_id;
    
    INSERT INTO retail_store (company_id, address_id, name, cnpj)
    VALUES (1, 1, 'Test Store FEFO', '12345678901234')
    RETURNING store_id INTO v_store_id;
    
    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-OLD', '2024-01-01', 100, 10.00)
    RETURNING batch_id INTO v_old_batch_id;
    
    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-NEW', '2024-06-01', 100, 10.00)
    RETURNING batch_id INTO v_new_batch_id;
    
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (v_store_id, v_old_batch_id, 100, 10);
    
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (v_store_id, v_new_batch_id, 100, 10);
    
    v_batch_id := fn_select_batch_fefo(v_product_id, v_store_id, 10);
    
    IF v_batch_id != v_old_batch_id THEN
        RETURN 'FAIL: FEFO selected newer batch instead of older';
    END IF;
    
    RETURN 'PASS: FEFO tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_03_inventory()
RETURNS TEXT AS $$
DECLARE
    v_inventory_id INTEGER;
    v_new_quantity DECIMAL;
BEGIN
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (1, 1, 100, 10)
    RETURNING inventory_id INTO v_inventory_id;
    
    BEGIN
        v_new_quantity := fn_atomic_update_inventory(v_inventory_id, -150, 'OUT');
        RETURN 'FAIL: Should not allow negative stock';
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    v_new_quantity := fn_atomic_update_inventory(v_inventory_id, -50, 'OUT');
    
    IF v_new_quantity != 50 THEN
        RETURN 'FAIL: Inventory update failed, expected 50 got ' || v_new_quantity;
    END IF;
    
    RETURN 'PASS: Inventory tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_04_audit()
RETURNS TEXT AS $$
DECLARE
    v_audit_count INTEGER;
BEGIN
    PERFORM fn_set_session_context(1, 1, 1);
    
    UPDATE product SET name = 'Updated Product' WHERE product_id = 1;
    
    SELECT COUNT(*) INTO v_audit_count
    FROM audit_log
    WHERE table_affected = 'product'
      AND record_id = '1'
      AND user_id = 1;
    
    IF v_audit_count = 0 THEN
        RETURN 'FAIL: Audit log not created';
    END IF;
    
    RETURN 'PASS: Audit tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION run_all_tests()
RETURNS TABLE(test_name TEXT, result TEXT) AS $$
BEGIN
    RETURN QUERY SELECT 'Validation'::TEXT, test_01_validation();
    RETURN QUERY SELECT 'FEFO'::TEXT, test_02_fefo();
    RETURN QUERY SELECT 'Inventory'::TEXT, test_03_inventory();
    RETURN QUERY SELECT 'Audit'::TEXT, test_04_audit();
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 31_INITIAL_DATA.SQL
-- ====================================================================

INSERT INTO employee_role (name, description, permission_level) VALUES
    ('Administrator', 'Full system access', 100),
    ('Manager', 'Store management', 80),
    ('Supervisor', 'Team supervision', 60),
    ('Operator', 'Standard operations', 40),
    ('Intern', 'Limited access', 20)
ON CONFLICT (name) DO NOTHING;

INSERT INTO subscription_plan (name, description, price, store_limit, user_limit) VALUES
    ('Free', 'Basic plan for small businesses', 0, 1, 3),
    ('Basic', 'Essential features for growing businesses', 99.90, 5, 10),
    ('Professional', 'Advanced features for medium businesses', 299.90, 20, 50),
    ('Enterprise', 'Full features for large organizations', 999.90, 100, 999)
ON CONFLICT (name) DO NOTHING;

INSERT INTO product_category (name, description) VALUES
    ('Electronics', 'Electronic devices and accessories'),
    ('Food', 'Food and beverages'),
    ('Beverages', 'Drinks and beverages'),
    ('Cleaning', 'Cleaning supplies'),
    ('Personal Care', 'Personal hygiene products'),
    ('Clothing', 'Apparel and accessories')
ON CONFLICT (name) DO NOTHING;

INSERT INTO ai_model (name, version, model_type, description, parameters) VALUES
    ('DemandForecast', '1.0.0', 'FORECAST', 'Demand forecasting using ARIMA', '{"window": 30, "confidence": 0.95}'),
    ('ReplenishmentOptimizer', '1.0.0', 'OPTIMIZATION', 'Optimize replenishment quantities', '{"safety_stock": 1.2, "lead_time": 7}'),
    ('InventoryClassifier', '1.0.0', 'CLASSIFICATION', 'Classify inventory criticality', '{"thresholds": {"critical": 2, "high": 5}}')
ON CONFLICT (name, version) DO NOTHING;

INSERT INTO schema_version (version, description, type, script, installed_by) VALUES
    ('1', 'Initial Schema', 'SQL', 'V1__initial_schema.sql', CURRENT_USER),
    ('2', 'Add Soft Delete', 'SQL', 'V2__add_soft_delete.sql', CURRENT_USER),
    ('3', 'Add Partitions', 'SQL', 'V3__add_partitions.sql', CURRENT_USER),
    ('4', 'Add Audit Triggers', 'SQL', 'V4__add_audit_triggers.sql', CURRENT_USER),
    ('5', 'Add KPI Cache', 'SQL', 'V5__add_kpi_cache.sql', CURRENT_USER),
    ('6', 'Add AI Module', 'SQL', 'V6__add_ai_module.sql', CURRENT_USER),
    ('7', 'Add Partial Indexes', 'SQL', 'V7__add_partial_indexes.sql', CURRENT_USER),
    ('8', 'Add Documentation', 'SQL', 'V8__add_documentation.sql', CURRENT_USER)
ON CONFLICT (version) DO NOTHING;

-- ====================================================================
-- 32_GRANTS.SQL
-- ====================================================================

-- GRANT USAGE ON SCHEMA mottainai TO app_user;
-- GRANT USAGE ON SCHEMA mottainai_analytics TO app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA mottainai TO app_user;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA mottainai TO app_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mottainai TO app_user;
-- GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA mottainai TO app_user;

-- ====================================================================
-- END OF SCRIPT - VERSION 6.0 ENTERPRISE FINAL - CORRIGIDO v6 FINAL
-- 100% PRODUCTION READY - TODOS OS ÍNDICES CORRIGIDOS
-- ====================================================================git statusgit status
