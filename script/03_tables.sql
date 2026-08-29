-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
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
    latitude        DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude       DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180),
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
    latitude        DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude       DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180),
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

CREATE TABLE IF NOT EXISTS tax_profile (
    tax_profile_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                VARCHAR(30) NOT NULL UNIQUE,
    name                VARCHAR(120) NOT NULL,
    description         TEXT,
    cfop                VARCHAR(4),
    icms_cst            VARCHAR(3),
    icms_csosn          VARCHAR(4),
    icms_rate           DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (icms_rate BETWEEN 0 AND 100),
    ipi_cst             VARCHAR(2),
    ipi_rate             DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (ipi_rate BETWEEN 0 AND 100),
    pis_cst             VARCHAR(2),
    pis_rate             DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (pis_rate BETWEEN 0 AND 100),
    cofins_cst          VARCHAR(2),
    cofins_rate         DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (cofins_rate BETWEEN 0 AND 100),
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product (
    product_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id     INTEGER NOT NULL REFERENCES product_category(category_id) ON DELETE RESTRICT,
    tax_profile_id  INTEGER NOT NULL REFERENCES tax_profile(tax_profile_id) ON DELETE RESTRICT,
    sku             VARCHAR(50) NOT NULL UNIQUE,
    barcode         VARCHAR(30) NOT NULL UNIQUE,
    ncm             VARCHAR(8) NOT NULL CHECK (ncm ~ '^\d{8}$'),
    cest            VARCHAR(7) CHECK (cest IS NULL OR cest ~ '^\d{7}$'),
    name            VARCHAR(150) NOT NULL,
    description     TEXT,
    brand           VARCHAR(100),
    unit_measure    VARCHAR(20) NOT NULL,
    weight          DECIMAL(10,3) CHECK (weight >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER NOT NULL DEFAULT 1,
    avg_cost        DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (avg_cost >= 0),
    suggested_price DECIMAL(10,2) CHECK (suggested_price IS NULL OR suggested_price >= 0)
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

-- 11_SALES.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS customer (
    customer_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name            VARCHAR(150) NOT NULL,
    cpf                  CHAR(11) UNIQUE CHECK (cpf IS NULL OR fn_validate_cpf(cpf)),
    email                VARCHAR(150) CHECK (fn_validate_email(email)),
    phone                VARCHAR(20),
    address_id           INTEGER REFERENCES address(address_id) ON DELETE SET NULL,
    external_auth_uid    VARCHAR(150) UNIQUE,
    birth_date           DATE,
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_consent    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at           TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_auth (
    customer_auth_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id            INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    login_email            VARCHAR(150) NOT NULL UNIQUE CHECK (fn_validate_email(login_email)),
    password_hash          TEXT NOT NULL,
    password_changed_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    failed_attempts        INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until           TIMESTAMP,
    recovery_token_hash    TEXT,
    recovery_expires_at    TIMESTAMP,
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at          TIMESTAMP,
    created_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK ((recovery_token_hash IS NULL AND recovery_expires_at IS NULL)
        OR (recovery_token_hash IS NOT NULL AND recovery_expires_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS pos_terminal (
    terminal_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    terminal_code        VARCHAR(30) NOT NULL,
    name                 VARCHAR(80) NOT NULL,
    hostname             VARCHAR(120),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (store_id, terminal_code)
);

CREATE TABLE IF NOT EXISTS pos_shift (
    shift_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    terminal_id          INTEGER NOT NULL REFERENCES pos_terminal(terminal_id) ON DELETE RESTRICT,
    employee_id          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    opened_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    opening_amount       DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (opening_amount >= 0),
    closed_at             TIMESTAMP,
    closing_amount       DECIMAL(12,2) CHECK (closing_amount IS NULL OR closing_amount >= 0),
    expected_amount      DECIMAL(12,2),
    status               VARCHAR(20) NOT NULL DEFAULT 'OPEN'
                         CHECK (status IN ('OPEN','CLOSED','CANCELED')),
    observation          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE IF NOT EXISTS pos_cash_movement (
    cash_movement_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shift_id             INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT,
    employee_id          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    movement_type        VARCHAR(12) NOT NULL CHECK (movement_type IN ('SANGRIA','SUPRIMENTO')),
    amount               DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    movement_date        TIMESTAMP NOT NULL DEFAULT NOW(),
    reason               VARCHAR(200) NOT NULL,
    observation          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sales_transaction (
    sale_id         INTEGER GENERATED ALWAYS AS IDENTITY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    shift_id        INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT,
    customer_id     INTEGER REFERENCES customer(customer_id) ON DELETE SET NULL,
    customer_document VARCHAR(14) CHECK (customer_document IS NULL OR customer_document ~ '^\d{11}(\d{3})?$'),
    sale_date       TIMESTAMP NOT NULL DEFAULT NOW(),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
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
    status          sale_item_status NOT NULL DEFAULT 'SOLD',
    canceled_at     TIMESTAMP,
    subtotal        DECIMAL(12,2) GENERATED ALWAYS AS (quantity_sold * unit_price) STORED,
    sale_date       TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date) 
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sale_payment (
    sale_payment_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id              INTEGER NOT NULL,
    sale_date            TIMESTAMP NOT NULL,
    payment_method       payment_method NOT NULL,
    amount               DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    installments         INTEGER NOT NULL DEFAULT 1 CHECK (installments > 0),
    authorization_code   VARCHAR(100),
    nsu                  VARCHAR(100),
    transaction_id       VARCHAR(150),
    paid_at              TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS fiscal_document (
    fiscal_document_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id              INTEGER NOT NULL,
    sale_date            TIMESTAMP NOT NULL,
    document_type        VARCHAR(10) NOT NULL CHECK (document_type IN ('NFE','NFCE','SAT')),
    series               VARCHAR(10),
    document_number      VARCHAR(30),
    access_key           VARCHAR(44) UNIQUE CHECK (access_key IS NULL OR access_key ~ '^\d{44}$'),
    status               VARCHAR(20) NOT NULL DEFAULT 'AUTHORIZED'
                         CHECK (status IN ('PENDING','AUTHORIZED','CANCELED','REJECTED')),
    issued_at            TIMESTAMP,
    total_amount         DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    protocol_number      VARCHAR(100),
    xml_content          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE RESTRICT
);

-- 12_ALERTS_AND_ACTIONS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS pos_cancel_request (
    cancel_request_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id               INTEGER NOT NULL,
    sale_date             TIMESTAMP NOT NULL,
    sale_item_id          INTEGER REFERENCES sale_item(sale_item_id) ON DELETE RESTRICT,
    requested_by          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    approved_by           INTEGER REFERENCES employee(employee_id) ON DELETE RESTRICT,
    target_type           pos_cancel_target NOT NULL,
    reason                VARCHAR(250) NOT NULL,
    status                pos_cancel_status NOT NULL DEFAULT 'PENDING',
    requested_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    decided_at            TIMESTAMP,
    executed_at           TIMESTAMP,
    decision_observation  TEXT,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE RESTRICT,
    CHECK ((target_type = 'ITEM' AND sale_item_id IS NOT NULL)
        OR (target_type = 'SALE' AND sale_item_id IS NULL)),
    CHECK (decided_at IS NULL OR decided_at >= requested_at),
    CHECK (executed_at IS NULL OR decided_at IS NOT NULL)
);

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

CREATE TABLE IF NOT EXISTS promotion (
    promotion_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id  INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    name                 VARCHAR(150) NOT NULL,
    description          TEXT,
    promotion_type       VARCHAR(20) NOT NULL CHECK (promotion_type IN ('DISCOUNT_PERCENT','DISCOUNT_FIXED','SPECIAL_PRICE')),
    starts_at             TIMESTAMP NOT NULL,
    ends_at               TIMESTAMP NOT NULL,
    status                promotion_status NOT NULL DEFAULT 'PENDING_APPROVAL',
    active                BOOLEAN NOT NULL DEFAULT FALSE,
    created_by            INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    approved_by           INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    approved_at           TIMESTAMP,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMP,
    CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS promotion_item (
    promotion_item_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_id         INTEGER NOT NULL REFERENCES promotion(promotion_id) ON DELETE CASCADE,
    product_id           INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    original_price       DECIMAL(12,2) NOT NULL CHECK (original_price >= 0),
    promotional_price    DECIMAL(12,2) NOT NULL CHECK (promotional_price >= 0),
    discount_percent     DECIMAL(7,4) GENERATED ALWAYS AS (
        CASE WHEN original_price > 0
             THEN ((original_price - promotional_price) / original_price) * 100
             ELSE 0 END
    ) STORED,
    quantity_available  DECIMAL(12,3) CHECK (quantity_available IS NULL OR quantity_available >= 0),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (promotion_id, product_id),
    CHECK (promotional_price <= original_price)
);

CREATE TABLE IF NOT EXISTS customer_geofence (
    geofence_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE CASCADE,
    radius_meters        INTEGER NOT NULL DEFAULT 1000 CHECK (radius_meters BETWEEN 50 AND 10000),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (customer_id, store_id)
);

CREATE TABLE IF NOT EXISTS loyalty_account (
    loyalty_account_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    points_balance       INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    joined_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS loyalty_transaction (
    loyalty_transaction_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loyalty_account_id   INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE CASCADE,
    sale_id              INTEGER,
    sale_date            TIMESTAMP,
    transaction_type     VARCHAR(20) NOT NULL CHECK (transaction_type IN ('EARN','REDEEM','ADJUSTMENT','EXPIRE')),
    points               INTEGER NOT NULL CHECK (points <> 0),
    description          VARCHAR(255) NOT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS loyalty_reward (
    reward_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                   VARCHAR(120) NOT NULL,
    description            TEXT,
    points_cost            INTEGER NOT NULL CHECK (points_cost > 0),
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    valid_from             TIMESTAMP,
    valid_until            TIMESTAMP,
    created_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

CREATE TABLE IF NOT EXISTS loyalty_redemption (
    redemption_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loyalty_account_id  INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE RESTRICT,
    reward_id            INTEGER NOT NULL REFERENCES loyalty_reward(reward_id) ON DELETE RESTRICT,
    points_spent         INTEGER NOT NULL CHECK (points_spent > 0),
    redeemed_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    status               VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'
                         CHECK (status IN ('PENDING','CONFIRMED','CANCELED')),
    UNIQUE (loyalty_account_id, reward_id, redeemed_at)
);

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

-- 21_ARCHIVE_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS audit_log_archive (LIKE audit_log);
CREATE TABLE IF NOT EXISTS inventory_movement_archive (LIKE inventory_movement);
CREATE TABLE IF NOT EXISTS sales_transaction_archive (LIKE sales_transaction);

-- ====================================================================
-- 21B_ENGINE_DIAGNOSTICS.SQL
-- Registro do motor de inteligencia Mottainai: varreduras (scans),
-- sugestoes taticas e regras de configuracao.
-- ====================================================================

CREATE TABLE IF NOT EXISTS engine_scan_log (
    scan_id            BIGSERIAL PRIMARY KEY,
    store_id           INTEGER REFERENCES retail_store(store_id) ON DELETE CASCADE,
    scanned_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    skus_scanned       INTEGER NOT NULL DEFAULT 0 CHECK (skus_scanned >= 0),
    diagnostics_count  INTEGER NOT NULL DEFAULT 0 CHECK (diagnostics_count >= 0),
    assertiveness_rate DECIMAL(5,2) CHECK (assertiveness_rate IS NULL OR assertiveness_rate BETWEEN 0 AND 100),
    status             VARCHAR(20) NOT NULL DEFAULT 'COMPLETED'
);
CREATE INDEX IF NOT EXISTS idx_engine_scan_store_time ON engine_scan_log(store_id, scanned_at);

CREATE TABLE IF NOT EXISTS engine_suggestion (
    suggestion_id    BIGSERIAL PRIMARY KEY,
    scan_id          BIGINT REFERENCES engine_scan_log(scan_id) ON DELETE SET NULL,
    store_id         INTEGER REFERENCES retail_store(store_id) ON DELETE CASCADE,
    product_id       INTEGER REFERENCES product(product_id) ON DELETE CASCADE,
    tactic           VARCHAR(50) NOT NULL,
    suggested_action VARCHAR(200),
    status           VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','ACCEPTED','REJECTED','EDITED','EXECUTED')),
    proposal         JSONB,
    decision_at      TIMESTAMP,
    acted_by         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_engine_suggestion_store_status ON engine_suggestion(store_id, status);
CREATE INDEX IF NOT EXISTS idx_engine_suggestion_tactic ON engine_suggestion(tactic);

CREATE TABLE IF NOT EXISTS system_rule (
    rule_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_category  VARCHAR(30) NOT NULL
                   CHECK (rule_category IN ('ENGINE','FINANCIAL','EXPIRATION','PRICE','GENERAL')),
    rule_key       VARCHAR(60) NOT NULL,
    rule_name      VARCHAR(120),
    rule_value     TEXT,
    value_type     VARCHAR(20) NOT NULL DEFAULT 'TEXT'
                   CHECK (value_type IN ('TEXT','NUMBER','BOOLEAN','JSON')),
    description    TEXT,
    active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (rule_category, rule_key)
);
CREATE INDEX IF NOT EXISTS idx_system_rule_category ON system_rule(rule_category);
