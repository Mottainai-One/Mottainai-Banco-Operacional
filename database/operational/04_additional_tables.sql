SET search_path TO mottainai, public;

-- O funcionario ja possui CPF. A conta de acesso tambem recebe o campo por
-- requisito da API, mas ele e preenchido a partir de employee para evitar
-- divergencia entre as duas copias do dado pessoal.
ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS cpf CHAR(11);

UPDATE app_user app
SET cpf = employee.cpf
FROM employee
WHERE employee.employee_id = app.employee_id
  AND app.cpf IS DISTINCT FROM employee.cpf;

ALTER TABLE app_user
    ALTER COLUMN cpf SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_app_user_cpf'
          AND conrelid = 'app_user'::regclass
    ) THEN
        ALTER TABLE app_user ADD CONSTRAINT uq_app_user_cpf UNIQUE (cpf);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_app_user_cpf_valid'
          AND conrelid = 'app_user'::regclass
    ) THEN
        ALTER TABLE app_user ADD CONSTRAINT ck_app_user_cpf_valid
            CHECK (fn_validate_cpf(cpf));
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_sync_app_user_cpf()
RETURNS TRIGGER AS $$
DECLARE
    v_employee_cpf CHAR(11);
BEGIN
    SELECT cpf INTO v_employee_cpf
    FROM employee
    WHERE employee_id = NEW.employee_id;

    IF v_employee_cpf IS NULL THEN
        RAISE EXCEPTION 'Employee % does not exist or has no CPF', NEW.employee_id;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.cpf IS NULL THEN
        NEW.cpf := v_employee_cpf;
    ELSIF NEW.cpf IS DISTINCT FROM v_employee_cpf THEN
        RAISE EXCEPTION 'app_user.cpf must match employee.cpf';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_app_user_cpf ON app_user;
CREATE TRIGGER trg_sync_app_user_cpf
BEFORE INSERT OR UPDATE OF employee_id, cpf ON app_user
FOR EACH ROW EXECUTE FUNCTION fn_sync_app_user_cpf();

CREATE OR REPLACE FUNCTION fn_propagate_employee_cpf()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE app_user SET cpf = NEW.cpf WHERE employee_id = NEW.employee_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_propagate_employee_cpf ON employee;
CREATE TRIGGER trg_propagate_employee_cpf
AFTER UPDATE OF cpf ON employee
FOR EACH ROW
WHEN (OLD.cpf IS DISTINCT FROM NEW.cpf)
EXECUTE FUNCTION fn_propagate_employee_cpf();

-- Campo exigido pelo contrato atual da API. O preco efetivo por loja fica
-- versionado em store_product_price; base_price e o valor-base do cadastro.
ALTER TABLE product
    ADD COLUMN IF NOT EXISTS base_price DECIMAL(12,2) NOT NULL DEFAULT 0
        CHECK (base_price >= 0);

CREATE INDEX IF NOT EXISTS idx_product_ncm ON product (ncm);

-- Preço efetivo por loja. product.suggested_price continua sendo apenas sugestão.
CREATE TABLE IF NOT EXISTS store_product_price (
    store_product_price_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id               INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    product_id             INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    regular_price          DECIMAL(12,2) NOT NULL CHECK (regular_price > 0),
    valid_from             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until            TIMESTAMPTZ,
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    version                INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (valid_until IS NULL OR valid_until > valid_from),
    EXCLUDE USING gist (
        store_id WITH =,
        product_id WITH =,
        tstzrange(valid_from, COALESCE(valid_until, 'infinity'::timestamptz), '[)') WITH &&
    ) WHERE (active)
);

CREATE INDEX IF NOT EXISTS idx_store_product_price_lookup
    ON store_product_price (store_id, product_id, valid_from DESC)
    WHERE active;

-- Contagem física e reconciliação de estoque.
CREATE TABLE IF NOT EXISTS inventory_count (
    inventory_count_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id           INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id        INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    started_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at        TIMESTAMPTZ,
    status             inventory_status NOT NULL DEFAULT 'IN_PROGRESS',
    observation        TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE IF NOT EXISTS inventory_count_item (
    inventory_count_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_count_id      BIGINT NOT NULL REFERENCES inventory_count(inventory_count_id) ON DELETE CASCADE,
    inventory_id            INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT,
    system_quantity         DECIMAL(12,3) NOT NULL CHECK (system_quantity >= 0),
    counted_quantity        DECIMAL(12,3) NOT NULL CHECK (counted_quantity >= 0),
    difference              DECIMAL(12,3) GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,
    observation             TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (inventory_count_id, inventory_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_count_store_status
    ON inventory_count (store_id, status, started_at DESC);

-- Recuperação de acesso de funcionários. Apenas hash do token é persistido.
CREATE TABLE IF NOT EXISTS password_reset_token (
    recovery_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
    token_hash        TEXT NOT NULL UNIQUE,
    expires_at        TIMESTAMPTZ NOT NULL,
    used_at           TIMESTAMPTZ,
    requested_ip      INET,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (expires_at > created_at),
    CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_password_reset_token_active
    ON password_reset_token (user_id, expires_at)
    WHERE used_at IS NULL;

-- Correlação de recomendações analíticas com ações operacionais.
ALTER TABLE suggested_action
    ADD COLUMN IF NOT EXISTS source_recommendation_uuid UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_suggested_action_source_recommendation
    ON suggested_action (source_recommendation_uuid)
    WHERE source_recommendation_uuid IS NOT NULL;

-- Evolui event_queue para um outbox transacional idempotente.
ALTER TABLE event_queue
    ADD COLUMN IF NOT EXISTS event_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS aggregate_type VARCHAR(60),
    ADD COLUMN IF NOT EXISTS aggregate_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS company_id INTEGER,
    ADD COLUMN IF NOT EXISTS store_id INTEGER,
    ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(180);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_queue_event_uuid ON event_queue (event_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_queue_idempotency
    ON event_queue (idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_queue_dispatch
    ON event_queue (status, priority, occurred_at) WHERE published_at IS NULL;

CREATE OR REPLACE FUNCTION fn_publish_integration_event(
    p_event_type VARCHAR(50),
    p_aggregate_type VARCHAR(60),
    p_aggregate_id VARCHAR(120),
    p_event_data JSONB,
    p_company_id INTEGER DEFAULT NULL,
    p_store_id INTEGER DEFAULT NULL,
    p_idempotency_key VARCHAR(180) DEFAULT NULL,
    p_priority INTEGER DEFAULT 5
) RETURNS UUID AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    INSERT INTO event_queue (
        event_type, aggregate_type, aggregate_id, event_data,
        company_id, store_id, idempotency_key, priority
    ) VALUES (
        p_event_type, p_aggregate_type, p_aggregate_id, p_event_data,
        p_company_id, p_store_id, p_idempotency_key, p_priority
    )
    ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING event_uuid INTO v_event_uuid;

    PERFORM pg_notify('mottainai_event', v_event_uuid::TEXT);
    RETURN v_event_uuid;
END;
$$ LANGUAGE plpgsql;

-- End of additional table definitions. The password reset token table is complete above.
