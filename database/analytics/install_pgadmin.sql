-- MOTTAINAI ANALYTICS DATABASE - PGADMIN COMPLETE INSTALLER
-- Generated from database/analytics/install.sql and its modules.
-- PostgreSQL 15+. Connect to the physical analytics database before executing.


BEGIN;

-- ============================================================================
-- MODULE: 00_database.sql
-- ============================================================================
-- Execute conectado ao banco mottainai_analytics.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
COMMENT ON SCHEMA mottainai_analytics IS
    'Banco analitico: historico, indicadores, recomendacoes de IA e controle de ingestao.';

SET search_path TO mottainai_analytics, public;

-- ============================================================================
-- MODULE: 01_types.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

DO $$ BEGIN
    CREATE TYPE ai_model_type AS ENUM (
        'DEMAND_FORECAST', 'EXPIRY_RISK', 'PRICE_OPTIMIZATION',
        'REPLENISHMENT', 'CUSTOMER_SEGMENTATION', 'FRAUD_DETECTION'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE suggested_action_type AS ENUM (
        'DISCOUNT', 'REPLENISH', 'TRANSFER', 'DONATE',
        'DISCARD', 'ADJUST_PRICE', 'CONTACT_SUPPLIER'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE suggested_action_status AS ENUM (
        'PENDING', 'ACCEPTED', 'REJECTED', 'EXECUTED', 'EXPIRED', 'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE ingestion_status AS ENUM ('RECEIVED', 'PROCESSED', 'FAILED', 'IGNORED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE job_status AS ENUM ('RUNNING', 'SUCCEEDED', 'FAILED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- MODULE: 02_dimensions.sql
-- ============================================================================
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

-- ============================================================================
-- MODULE: 03_facts.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

-- IDs abaixo preservam as chaves de origem. Nao ha FKs entre bancos fisicos.
CREATE TABLE IF NOT EXISTS fact_sales (
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    sale_timestamp      TIMESTAMPTZ NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    employee_id         BIGINT,
    customer_id         BIGINT,
    item_count          INTEGER NOT NULL DEFAULT 0,
    gross_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    net_amount          NUMERIC(15,2) NOT NULL,
    status              VARCHAR(30) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sale_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS fact_sales_default
    PARTITION OF fact_sales DEFAULT;

CREATE TABLE IF NOT EXISTS fact_sale_item (
    sale_item_id        BIGINT NOT NULL,
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    quantity            NUMERIC(15,3) NOT NULL,
    unit_price          NUMERIC(15,4) NOT NULL,
    discount_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    subtotal            NUMERIC(15,2) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sale_item_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS fact_sale_item_default
    PARTITION OF fact_sale_item DEFAULT;

CREATE TABLE IF NOT EXISTS fact_sale_payment (
    payment_id          BIGINT PRIMARY KEY,
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    payment_method      VARCHAR(40) NOT NULL,
    amount              NUMERIC(15,2) NOT NULL,
    installments        SMALLINT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_inventory_movement (
    movement_id         BIGINT NOT NULL,
    movement_date       DATE NOT NULL,
    movement_timestamp  TIMESTAMPTZ NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    inventory_id        BIGINT,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    employee_id         BIGINT,
    movement_type       VARCHAR(40) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    unit_cost           NUMERIC(15,4),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (movement_id, movement_date)
) PARTITION BY RANGE (movement_date);

CREATE TABLE IF NOT EXISTS fact_inventory_movement_default
    PARTITION OF fact_inventory_movement DEFAULT;

CREATE TABLE IF NOT EXISTS fact_inventory_snapshot (
    snapshot_date       DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT NOT NULL,
    inventory_type      VARCHAR(30) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    reserved_quantity   NUMERIC(15,3) NOT NULL DEFAULT 0,
    average_cost        NUMERIC(15,4),
    expiration_date     DATE,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (snapshot_date, store_id, product_id, batch_id, inventory_type)
) PARTITION BY RANGE (snapshot_date);

CREATE TABLE IF NOT EXISTS fact_inventory_snapshot_default
    PARTITION OF fact_inventory_snapshot DEFAULT;

CREATE TABLE IF NOT EXISTS fact_purchase_order (
    purchase_order_id   BIGINT NOT NULL,
    order_date          DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    supplier_id         BIGINT,
    employee_id         BIGINT,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (purchase_order_id, order_date)
);

CREATE TABLE IF NOT EXISTS fact_receiving (
    receiving_id        BIGINT PRIMARY KEY,
    purchase_order_id   BIGINT,
    receiving_date      DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    supplier_id         BIGINT,
    employee_id         BIGINT,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_promotion_result (
    promotion_id        BIGINT NOT NULL,
    result_date         DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    units_sold          NUMERIC(15,3) NOT NULL DEFAULT 0,
    gross_revenue       NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_granted    NUMERIC(15,2) NOT NULL DEFAULT 0,
    avoided_loss        NUMERIC(15,2) NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (promotion_id, result_date, store_id, product_id)
);

CREATE TABLE IF NOT EXISTS fact_loss_destination (
    loss_id             BIGINT PRIMARY KEY,
    loss_date           DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    destination_type    VARCHAR(40) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    estimated_value     NUMERIC(15,2),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_transfer (
    transfer_id         BIGINT PRIMARY KEY,
    transfer_date       DATE NOT NULL,
    source_store_id     BIGINT NOT NULL,
    destination_store_id BIGINT NOT NULL,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    total_cost          NUMERIC(15,2),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE fact_transfer IS
    'Fato completo de transferencia entre lojas, no grao de uma transferencia.';

CREATE TABLE IF NOT EXISTS fact_replenishment (
    replenishment_id    BIGINT PRIMARY KEY,
    replenishment_date  DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    requested_quantity  NUMERIC(15,3) NOT NULL,
    supplied_quantity   NUMERIC(15,3),
    status              VARCHAR(30) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_loyalty (
    loyalty_event_id    BIGINT PRIMARY KEY,
    event_date          DATE NOT NULL,
    customer_id         BIGINT NOT NULL,
    store_id            BIGINT,
    event_type          VARCHAR(30) NOT NULL,
    points_delta        INTEGER NOT NULL,
    balance_after       INTEGER,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- MODULE: 03_monthly_partitions.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

-- Particionamento mensal somente para os fatos de maior volume. As tabelas de
-- menor volume permanecem simples para evitar centenas de particoes vazias no
-- inicio do projeto.
CREATE OR REPLACE FUNCTION sp_create_monthly_fact_partitions(
    p_months_back INTEGER DEFAULT 12,
    p_months_ahead INTEGER DEFAULT 6
)
RETURNS VOID AS $$
DECLARE
    v_month DATE;
    v_table TEXT;
    v_partition_column TEXT;
    v_partition_name TEXT;
    v_has_default_rows BOOLEAN;
    v_tables CONSTANT TEXT[] := ARRAY[
        'fact_sales',
        'fact_sale_item',
        'fact_inventory_movement',
        'fact_inventory_snapshot',
        'fact_inventory_count_line',
        'fact_transfer_line',
        'fact_replenishment_plan_line',
        'fact_replenishment_execution_line',
        'fact_donation_line',
        'fact_disposal_line',
        'fact_alert_lifecycle',
        'fact_action_lifecycle'
    ];
BEGIN
    IF p_months_back < 0 OR p_months_ahead < 0 THEN
        RAISE EXCEPTION 'Partition month ranges cannot be negative';
    END IF;

    FOREACH v_table IN ARRAY v_tables
    LOOP
        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_table)) IS NULL THEN
            CONTINUE;
        END IF;

        v_partition_column := CASE v_table
            WHEN 'fact_sales' THEN 'sale_date'
            WHEN 'fact_sale_item' THEN 'sale_date'
            WHEN 'fact_inventory_movement' THEN 'movement_date'
            WHEN 'fact_inventory_snapshot' THEN 'snapshot_date'
            WHEN 'fact_inventory_count_line' THEN 'count_date'
            WHEN 'fact_transfer_line' THEN 'request_date'
            WHEN 'fact_replenishment_plan_line' THEN 'generated_at'
            WHEN 'fact_replenishment_execution_line' THEN 'started_at'
            WHEN 'fact_donation_line' THEN 'donation_date'
            WHEN 'fact_disposal_line' THEN 'disposal_date'
            WHEN 'fact_alert_lifecycle' THEN 'generated_at'
            WHEN 'fact_action_lifecycle' THEN 'generated_at'
        END;

        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - make_interval(months => p_months_back),
                date_trunc('month', current_date) + make_interval(months => p_months_ahead),
                interval '1 month'
            )::date
        LOOP
            v_partition_name := v_table || '_' || to_char(v_month, 'YYYY_MM');

            -- Keep late/out-of-window rows in the default partition. PostgreSQL
            -- refuses a new range partition when its default already contains
            -- matching rows, so leave that month there until it can be moved
            -- during a maintenance window.
            IF to_regclass(format('%I.%I', 'mottainai_analytics', v_table || '_default')) IS NOT NULL THEN
                EXECUTE format(
                    'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I >= $1 AND %I < $2 LIMIT 1)',
                    'mottainai_analytics', v_table || '_default',
                    v_partition_column, v_partition_column
                ) INTO STRICT v_has_default_rows USING
                    v_month,
                    (v_month + interval '1 month')::date;
                IF v_has_default_rows THEN
                    CONTINUE;
                END IF;
            END IF;

            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I '
                || 'FOR VALUES FROM (%L) TO (%L)',
                'mottainai_analytics', v_partition_name,
                'mottainai_analytics', v_table,
                v_month, (v_month + interval '1 month')::date
            );
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql
SET timezone TO 'UTC';

SELECT sp_create_monthly_fact_partitions(12, 6);

-- ============================================================================
-- MODULE: 04_ai.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

CREATE TABLE IF NOT EXISTS ai_model (
    model_id            BIGSERIAL PRIMARY KEY,
    name                VARCHAR(150) NOT NULL,
    model_type          ai_model_type NOT NULL,
    version             VARCHAR(50) NOT NULL,
    parameters          JSONB NOT NULL DEFAULT '{}'::jsonb,
    metrics             JSONB NOT NULL DEFAULT '{}'::jsonb,
    active              BOOLEAN NOT NULL DEFAULT true,
    trained_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, version)
);

CREATE TABLE IF NOT EXISTS ai_prediction (
    prediction_id       BIGSERIAL PRIMARY KEY,
    prediction_uuid     UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    model_id            BIGINT NOT NULL REFERENCES ai_model(model_id),
    company_id          BIGINT,
    store_id            BIGINT,
    product_id          BIGINT,
    batch_id            BIGINT,
    prediction_type     VARCHAR(80) NOT NULL,
    prediction_value    NUMERIC(18,6),
    confidence          NUMERIC(6,5) CHECK (confidence BETWEEN 0 AND 1),
    horizon_date        DATE,
    input_features      JSONB NOT NULL DEFAULT '{}'::jsonb,
    explanation         JSONB NOT NULL DEFAULT '{}'::jsonb,
    predicted_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_recommendation (
    recommendation_id   BIGSERIAL PRIMARY KEY,
    recommendation_uuid UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    prediction_id       BIGINT REFERENCES ai_prediction(prediction_id),
    company_id          BIGINT,
    store_id            BIGINT,
    product_id          BIGINT,
    batch_id            BIGINT,
    action_type         suggested_action_type NOT NULL,
    priority            priority_level NOT NULL DEFAULT 'MEDIUM',
    status              suggested_action_status NOT NULL DEFAULT 'PENDING',
    title               VARCHAR(255) NOT NULL,
    rationale           TEXT,
    proposed_values     JSONB NOT NULL DEFAULT '{}'::jsonb,
    estimated_impact    JSONB NOT NULL DEFAULT '{}'::jsonb,
    operational_action_id BIGINT,
    valid_until         TIMESTAMPTZ,
    accepted_at         TIMESTAMPTZ,
    executed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN ai_recommendation.operational_action_id IS
    'ID devolvido pelo banco operacional; correlacao, nao chave estrangeira entre bancos.';

CREATE TABLE IF NOT EXISTS ai_feedback (
    feedback_id         BIGSERIAL PRIMARY KEY,
    recommendation_id   BIGINT NOT NULL REFERENCES ai_recommendation(recommendation_id),
    source_user_id      BIGINT,
    decision            VARCHAR(30) NOT NULL,
    reason              TEXT,
    outcome             JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_execution (
    execution_id        BIGSERIAL PRIMARY KEY,
    model_id            BIGINT NOT NULL REFERENCES ai_model(model_id),
    started_at          TIMESTAMPTZ NOT NULL,
    finished_at         TIMESTAMPTZ,
    status              job_status NOT NULL DEFAULT 'RUNNING',
    input_rows          BIGINT,
    output_rows         BIGINT,
    error_message       TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS engine_scan_log (
    scan_id             BIGSERIAL PRIMARY KEY,
    company_id          BIGINT,
    store_id            BIGINT,
    scan_type           VARCHAR(60) NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL,
    finished_at         TIMESTAMPTZ,
    status              job_status NOT NULL DEFAULT 'RUNNING',
    scanned_rows        BIGINT NOT NULL DEFAULT 0,
    suggestions_created BIGINT NOT NULL DEFAULT 0,
    error_message       TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS engine_suggestion (
    suggestion_id       BIGSERIAL PRIMARY KEY,
    suggestion_uuid     UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    scan_id             BIGINT REFERENCES engine_scan_log(scan_id),
    recommendation_id   BIGINT REFERENCES ai_recommendation(recommendation_id),
    store_id            BIGINT,
    product_id          BIGINT,
    batch_id            BIGINT,
    action_type         suggested_action_type NOT NULL,
    priority            priority_level NOT NULL DEFAULT 'MEDIUM',
    status              suggested_action_status NOT NULL DEFAULT 'PENDING',
    proposed_values     JSONB NOT NULL DEFAULT '{}'::jsonb,
    operational_action_id BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS kpi_cache (
    kpi_key             VARCHAR(150) NOT NULL,
    scope_type          VARCHAR(30) NOT NULL,
    scope_id            BIGINT NOT NULL DEFAULT 0,
    reference_date      DATE NOT NULL,
    value               NUMERIC(20,6),
    payload             JSONB NOT NULL DEFAULT '{}'::jsonb,
    calculated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ,
    PRIMARY KEY (kpi_key, scope_type, scope_id, reference_date)
);

-- ============================================================================
-- MODULE: 05_integration.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

CREATE TABLE IF NOT EXISTS ingestion_event (
    event_uuid          UUID PRIMARY KEY,
    source_event_id     BIGINT UNIQUE,
    source_database     VARCHAR(80) NOT NULL DEFAULT 'mottainai_operational',
    event_type          VARCHAR(120) NOT NULL,
    aggregate_type      VARCHAR(80),
    aggregate_id        VARCHAR(120),
    company_id          BIGINT,
    store_id            BIGINT,
    schema_version      INTEGER NOT NULL DEFAULT 1,
    payload             JSONB NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at        TIMESTAMPTZ,
    status              ingestion_status NOT NULL DEFAULT 'RECEIVED',
    retry_count         INTEGER NOT NULL DEFAULT 0,
    error_message       TEXT
);

CREATE TABLE IF NOT EXISTS etl_checkpoint (
    pipeline_name       VARCHAR(150) PRIMARY KEY,
    last_event_uuid     UUID,
    last_source_id      BIGINT,
    last_occurred_at    TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS etl_dead_letter (
    dead_letter_id      BIGSERIAL PRIMARY KEY,
    event_uuid          UUID,
    pipeline_name       VARCHAR(150) NOT NULL,
    payload             JSONB NOT NULL,
    error_message       TEXT NOT NULL,
    retry_count         INTEGER NOT NULL DEFAULT 0,
    first_failed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_failed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS job_log (
    job_id              BIGSERIAL PRIMARY KEY,
    job_name            VARCHAR(150) NOT NULL,
    status              job_status NOT NULL DEFAULT 'RUNNING',
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at         TIMESTAMPTZ,
    rows_read           BIGINT NOT NULL DEFAULT 0,
    rows_written        BIGINT NOT NULL DEFAULT 0,
    error_message       TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS query_performance (
    sample_id           BIGSERIAL PRIMARY KEY,
    query_name          VARCHAR(150) NOT NULL,
    duration_ms         NUMERIC(14,3) NOT NULL,
    rows_returned       BIGINT,
    sampled_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- ============================================================================
-- MODULE: 06_indexes.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

CREATE INDEX IF NOT EXISTS idx_dim_store_company ON dim_store(company_id);
CREATE INDEX IF NOT EXISTS idx_dim_product_category ON dim_product(category_id);
CREATE INDEX IF NOT EXISTS idx_fact_sales_store_date ON fact_sales(store_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer_date ON fact_sales(customer_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_sale_item_product_date ON fact_sale_item(product_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_movement_product_date
    ON fact_inventory_movement(product_id, movement_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_snapshot_store_date
    ON fact_inventory_snapshot(store_id, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_snapshot_expiration
    ON fact_inventory_snapshot(expiration_date) WHERE expiration_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_prediction_scope
    ON ai_prediction(store_id, product_id, predicted_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_pending
    ON ai_recommendation(priority, created_at DESC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_engine_suggestion_pending
    ON engine_suggestion(store_id, priority, created_at DESC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_ingestion_event_status
    ON ingestion_event(status, occurred_at);
CREATE INDEX IF NOT EXISTS idx_ingestion_event_aggregate
    ON ingestion_event(aggregate_type, aggregate_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_etl_dead_letter_unresolved
    ON etl_dead_letter(pipeline_name, last_failed_at) WHERE resolved_at IS NULL;

-- ============================================================================
-- MODULE: 07_views.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

-- Reference date remains fixed until the next successful publication.
CREATE OR REPLACE VIEW vw_published_batch AS
SELECT job_id, started_at AS source_cutoff_at,
       (started_at AT TIME ZONE 'America/Sao_Paulo')::date AS snapshot_date,
       NULL::UUID AS batch_id,
       finished_at AS published_at
FROM job_log
WHERE job_name = 'operational_to_analytics_daily'
  AND status::text = 'SUCCEEDED'
ORDER BY job_id DESC
LIMIT 1;

CREATE OR REPLACE VIEW vw_sales_daily_kpis AS
SELECT
    fs.sale_date,
    fs.company_id,
    fs.store_id,
    ds.name AS store_name,
    count(*) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS sale_count,
    sum(fs.item_count) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS item_count,
    sum(fs.gross_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS gross_revenue,
    sum(fs.discount_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS discount_amount,
    sum(fs.net_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS net_revenue,
    avg(fs.net_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS average_ticket
FROM fact_sales fs
LEFT JOIN dim_store ds ON ds.store_id = fs.store_id
GROUP BY fs.sale_date, fs.company_id, fs.store_id, ds.name;

CREATE OR REPLACE VIEW vw_top_selling_products AS
SELECT
    fsi.sale_date,
    fsi.store_id,
    fsi.product_id,
    dp.name AS product_name,
    dp.category_id,
    sum(fsi.quantity) AS units_sold,
    sum(fsi.subtotal) AS net_revenue,
    sum(fsi.discount_amount) AS discount_amount
FROM fact_sale_item fsi
LEFT JOIN dim_product dp ON dp.product_id = fsi.product_id
GROUP BY fsi.sale_date, fsi.store_id, fsi.product_id, dp.name, dp.category_id;

CREATE OR REPLACE VIEW vw_inventory_snapshot_current AS
SELECT DISTINCT ON (store_id, product_id, batch_id, inventory_type)
    snapshot_date,
    company_id,
    store_id,
    product_id,
    batch_id,
    inventory_type,
    quantity,
    reserved_quantity,
    quantity - reserved_quantity AS available_quantity,
    average_cost,
    expiration_date,
    NULL::BIGINT AS inventory_id,
    NULL::NUMERIC(15,3) AS minimum_quantity
FROM fact_inventory_snapshot
ORDER BY store_id, product_id, batch_id, inventory_type, snapshot_date DESC;

CREATE OR REPLACE VIEW vw_stockout_analysis AS
SELECT
    current_stock.store_id,
    current_stock.product_id,
    dp.name AS product_name,
    sum(current_stock.available_quantity) AS available_quantity,
    coalesce(sales.units_sold_30d, 0) AS units_sold_30d,
    CASE
        WHEN coalesce(sales.units_sold_30d, 0) = 0 THEN NULL
        ELSE sum(current_stock.available_quantity) / (sales.units_sold_30d / 30.0)
    END AS estimated_days_of_stock
FROM vw_inventory_snapshot_current current_stock
LEFT JOIN dim_product dp ON dp.product_id = current_stock.product_id
LEFT JOIN (
    SELECT store_id, product_id, sum(quantity) AS units_sold_30d
    FROM fact_sale_item
    CROSS JOIN vw_published_batch b
    WHERE sale_date BETWEEN b.snapshot_date - 29 AND b.snapshot_date
    GROUP BY store_id, product_id
) sales
    ON sales.store_id = current_stock.store_id
   AND sales.product_id = current_stock.product_id
GROUP BY current_stock.store_id, current_stock.product_id, dp.name, sales.units_sold_30d;

CREATE OR REPLACE VIEW vw_ai_performance AS
SELECT
    am.model_id,
    am.name AS model_name,
    am.model_type,
    count(DISTINCT ap.prediction_id) AS predictions,
    count(DISTINCT ar.recommendation_id) AS recommendations,
    count(DISTINCT ar.recommendation_id) FILTER (WHERE ar.status = 'ACCEPTED') AS accepted,
    count(DISTINCT ar.recommendation_id) FILTER (WHERE ar.status = 'EXECUTED') AS executed,
    avg(ap.confidence) AS average_confidence
FROM ai_model am
LEFT JOIN ai_prediction ap ON ap.model_id = am.model_id
LEFT JOIN ai_recommendation ar ON ar.prediction_id = ap.prediction_id
GROUP BY am.model_id, am.name, am.model_type;

CREATE OR REPLACE VIEW vw_engine_suggestion_metrics AS
SELECT
    created_at::date AS reference_date,
    store_id,
    action_type,
    count(*) AS suggestions,
    count(*) FILTER (WHERE status IN ('ACCEPTED', 'EXECUTED')) AS accepted_or_executed,
    count(*) FILTER (WHERE status = 'REJECTED') AS rejected
FROM engine_suggestion
GROUP BY created_at::date, store_id, action_type;

CREATE OR REPLACE VIEW vw_executive_dashboard AS
SELECT
    sales.reference_date,
    sales.company_id,
    sales.sale_count,
    sales.net_revenue,
    sales.discount_amount,
    sales.average_ticket,
    coalesce(loss.estimated_loss, 0) AS estimated_loss
FROM (
    SELECT
        sale_date AS reference_date,
        company_id,
        sum(sale_count) AS sale_count,
        sum(net_revenue) AS net_revenue,
        sum(discount_amount) AS discount_amount,
        CASE WHEN sum(sale_count) = 0 THEN NULL
             ELSE sum(net_revenue) / sum(sale_count) END AS average_ticket
    FROM vw_sales_daily_kpis
    GROUP BY sale_date, company_id
) sales
LEFT JOIN (
    SELECT loss_date, company_id, sum(estimated_value) AS estimated_loss
    FROM fact_loss_destination
    GROUP BY loss_date, company_id
) loss ON loss.loss_date = sales.reference_date AND loss.company_id = sales.company_id;

CREATE OR REPLACE VIEW vw_customer_loyalty_analysis AS
SELECT
    dc.anonymous_key,
    coalesce(sales.purchases, 0) AS purchases,
    sales.last_purchase_date,
    coalesce(sales.lifetime_value, 0) AS lifetime_value,
    coalesce(loyalty.points_delta, 0) AS points_delta
FROM dim_customer dc
LEFT JOIN (
    SELECT
        customer_id,
        count(DISTINCT sale_id) AS purchases,
        max(sale_date) AS last_purchase_date,
        sum(net_amount) AS lifetime_value
    FROM fact_sales
    WHERE status NOT IN ('CANCELED', 'RETURNED')
    GROUP BY customer_id
) sales ON sales.customer_id = dc.customer_id
LEFT JOIN (
    SELECT customer_id, sum(points_delta) AS points_delta
    FROM fact_loyalty
    GROUP BY customer_id
) loyalty ON loyalty.customer_id = dc.customer_id;

-- ============================================================================
-- MODULE: 08_seed.sql
-- ============================================================================
SET search_path TO mottainai_analytics, public;

INSERT INTO dim_date (
    date_key, year_number, quarter_number, month_number, month_name,
    week_number, day_number, day_of_week_number, day_of_week_name, is_weekend
)
SELECT
    day::date,
    extract(year FROM day)::smallint,
    extract(quarter FROM day)::smallint,
    extract(month FROM day)::smallint,
    to_char(day, 'TMMonth'),
    extract(week FROM day)::smallint,
    extract(day FROM day)::smallint,
    extract(isodow FROM day)::smallint,
    to_char(day, 'TMDay'),
    extract(isodow FROM day) IN (6, 7)
FROM generate_series(
    date_trunc('year', current_date) - interval '5 years',
    date_trunc('year', current_date) + interval '3 years' - interval '1 day',
    interval '1 day'
) AS calendar(day)
ON CONFLICT (date_key) DO NOTHING;

INSERT INTO ai_model (name, model_type, version, parameters)
VALUES
    ('Previsao de Demanda', 'DEMAND_FORECAST', '1.0.0', '{"horizon_days": 30}'),
    ('Risco de Validade', 'EXPIRY_RISK', '1.0.0', '{"warning_days": [30, 15, 7]}'),
    ('Otimizacao de Preco', 'PRICE_OPTIMIZATION', '1.0.0', '{"min_margin_percent": 5}')
ON CONFLICT (name, version) DO NOTHING;

INSERT INTO schema_version (version, description)
VALUES (10, 'Separacao fisica do banco analitico e de IA')
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- MODULE: 10_dashboard.sql
-- ============================================================================
-- Dados e views que sustentam o dashboard de empresas, lojas e funcionarios.
-- Execute conectado ao banco fisico analitico.
SET search_path TO mottainai_analytics, public;

ALTER TABLE dim_company ADD COLUMN IF NOT EXISTS plan_name VARCHAR(150);

CREATE TABLE IF NOT EXISTS fact_store_daily (
    snapshot_date DATE NOT NULL,
    company_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    employees_total INTEGER NOT NULL DEFAULT 0,
    employees_active INTEGER NOT NULL DEFAULT 0,
    users_total INTEGER NOT NULL DEFAULT 0,
    users_active INTEGER NOT NULL DEFAULT 0,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (snapshot_date, store_id)
);

CREATE INDEX IF NOT EXISTS idx_fact_store_daily_company_date
    ON fact_store_daily (company_id, snapshot_date DESC);

CREATE OR REPLACE VIEW vw_company_kpis AS
WITH latest_store AS (
    SELECT f.*,
           row_number() OVER (PARTITION BY store_id ORDER BY snapshot_date DESC) AS rn
    FROM fact_store_daily f
), totals AS (
    SELECT c.company_id,
           c.legal_name AS official_name,
           c.plan_name,
           coalesce(sum(f.employees_total), 0)::integer AS employees_total,
           coalesce(sum(f.employees_active), 0)::integer AS employees_active,
           coalesce(sum(f.users_total), 0)::integer AS users_total,
           coalesce(sum(f.users_active), 0)::integer AS users_active,
           count(f.store_id)::integer AS stores_total
    FROM dim_company c
    LEFT JOIN latest_store f ON f.company_id = c.company_id AND f.rn = 1
    GROUP BY c.company_id, c.legal_name, c.plan_name
)
SELECT totals.*,
       rank() OVER (ORDER BY employees_active DESC, users_active DESC) AS active_rank
FROM totals;

CREATE OR REPLACE VIEW vw_employee_distribution AS
WITH role_counts AS (
    SELECT coalesce(role_name, 'Sem funcao') AS role_name,
           count(*)::integer AS employees_total,
           count(*) FILTER (WHERE active)::integer AS employees_active
    FROM dim_employee
    GROUP BY coalesce(role_name, 'Sem funcao')
)
SELECT role_name, employees_total, employees_active,
       round(100.0 * employees_active / nullif(sum(employees_active) OVER (), 0), 2)
           AS active_share_percent
FROM role_counts;

CREATE OR REPLACE VIEW vw_store_daily_kpis AS
SELECT f.snapshot_date AS full_date,
       c.company_id, c.legal_name AS official_name,
       s.store_id, s.name AS store_name, s.city, s.state_code AS state,
       f.employees_total, f.employees_active, f.users_total, f.users_active,
       f.users_active - lag(f.users_active) OVER
           (PARTITION BY f.store_id ORDER BY f.snapshot_date) AS users_active_delta
FROM fact_store_daily f
JOIN dim_company c ON c.company_id = f.company_id
JOIN dim_store s ON s.store_id = f.store_id;

-- ============================================================================
-- MODULE: 11_priority_views.sql
-- ============================================================================
-- Views do dashboard derivadas apenas de dimensoes e fatos do banco fisico analitico.
SET search_path TO mottainai_analytics, public;

ALTER TABLE fact_inventory_snapshot
    ADD COLUMN IF NOT EXISTS inventory_id BIGINT,
    ADD COLUMN IF NOT EXISTS minimum_quantity NUMERIC(15,3);

CREATE TABLE IF NOT EXISTS fact_alert_snapshot (
    snapshot_date DATE NOT NULL,
    alert_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    PRIMARY KEY (snapshot_date, alert_id)
);

CREATE OR REPLACE VIEW vw_inventory_snapshot_current AS
SELECT DISTINCT ON (store_id, product_id, batch_id, inventory_type)
       snapshot_date, company_id, store_id, product_id, batch_id,
       inventory_type, quantity, reserved_quantity,
       quantity - reserved_quantity AS available_quantity,
       average_cost, expiration_date, inventory_id, minimum_quantity
FROM fact_inventory_snapshot
ORDER BY store_id, product_id, batch_id, inventory_type, snapshot_date DESC;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT i.inventory_id, i.product_id, p.name AS product,
       i.store_id, s.name AS store,
       i.quantity AS current_quantity, i.minimum_quantity
FROM vw_inventory_snapshot_current i
JOIN dim_product p ON p.product_id = i.product_id
JOIN dim_store s ON s.store_id = i.store_id
WHERE i.minimum_quantity IS NOT NULL
  AND i.quantity < i.minimum_quantity;

CREATE OR REPLACE VIEW vw_monthly_summary AS
WITH sales AS (
    SELECT date_trunc('month', sale_date)::date AS month_start, store_id,
           count(*) AS total_sales, sum(net_amount) AS total_revenue,
           avg(net_amount) AS avg_ticket,
           count(DISTINCT employee_id) AS active_sellers
    FROM fact_sales
    WHERE status = 'COMPLETED'
    GROUP BY 1, 2
), units AS (
    SELECT date_trunc('month', i.sale_date)::date AS month_start, i.store_id,
           sum(i.quantity) AS units_sold
    FROM fact_sale_item i
    JOIN fact_sales s ON s.sale_id = i.sale_id AND s.sale_date = i.sale_date
    WHERE s.status = 'COMPLETED'
    GROUP BY 1, 2
)
SELECT sales.month_start, sales.store_id, ds.name AS store_name,
       sales.total_sales, sales.total_revenue, sales.avg_ticket,
       sales.active_sellers, coalesce(units.units_sold, 0) AS units_sold
FROM sales
JOIN dim_store ds ON ds.store_id = sales.store_id
LEFT JOIN units ON units.month_start = sales.month_start AND units.store_id = sales.store_id;

CREATE OR REPLACE VIEW vw_product_risk_ranking AS
WITH expiration AS (
    SELECT i.store_id, i.product_id,
           sum(i.quantity) FILTER (WHERE i.expiration_date BETWEEN b.snapshot_date AND b.snapshot_date + 15)
               AS quantity_at_expiration_risk,
           sum(i.quantity * coalesce(i.average_cost, 0)) FILTER
               (WHERE i.expiration_date BETWEEN b.snapshot_date AND b.snapshot_date + 15)
               AS value_at_expiration_risk,
           min(i.expiration_date - b.snapshot_date) FILTER
               (WHERE i.expiration_date >= b.snapshot_date) AS nearest_expiration_days
    FROM vw_inventory_snapshot_current i
    CROSS JOIN vw_published_batch b
    GROUP BY i.store_id, i.product_id, b.snapshot_date
)
SELECT x.store_id, s.name AS store_name, x.product_id, x.product_name,
       CASE WHEN x.available_quantity <= 0 THEN 'CRITICAL'
            WHEN x.estimated_days_of_stock < 7 THEN 'HIGH'
            WHEN x.estimated_days_of_stock < 15 THEN 'MEDIUM'
            ELSE 'LOW' END AS stockout_risk,
       x.available_quantity AS current_stock,
       x.estimated_days_of_stock AS days_of_coverage,
       coalesce(e.quantity_at_expiration_risk, 0)::numeric(18,3) AS quantity_at_expiration_risk,
       coalesce(e.value_at_expiration_risk, 0)::numeric(18,2) AS value_at_expiration_risk,
       e.nearest_expiration_days,
       CASE WHEN x.available_quantity <= 0 OR coalesce(e.value_at_expiration_risk,0) >= 1000 THEN 'CRITICAL'
            WHEN x.estimated_days_of_stock < 7 OR coalesce(e.value_at_expiration_risk,0) > 0 THEN 'HIGH'
            WHEN x.estimated_days_of_stock < 15 THEN 'MEDIUM'
            ELSE 'LOW' END AS consolidated_risk
FROM vw_stockout_analysis x
JOIN dim_store s ON s.store_id = x.store_id
LEFT JOIN expiration e ON e.store_id = x.store_id AND e.product_id = x.product_id;

-- Uma linha por loja. Atualizada ao fim de cada carga diaria; nunca consulta o operacional.
DROP MATERIALIZED VIEW IF EXISTS mv_dashboard_metrics;
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_dashboard_metrics AS
WITH sales AS (
    SELECT store_id, count(*) AS transactions, sum(net_amount) AS revenue,
           avg(net_amount) AS avg_ticket
    FROM fact_sales
    CROSS JOIN vw_published_batch b
    WHERE sale_date BETWEEN b.snapshot_date - 1 AND b.snapshot_date
      AND status = 'COMPLETED'
    GROUP BY store_id
), products AS (
    SELECT i.store_id, count(DISTINCT i.product_id) AS products_sold
    FROM fact_sale_item i
    JOIN fact_sales s ON s.sale_id = i.sale_id AND s.sale_date = i.sale_date
    CROSS JOIN vw_published_batch b
    WHERE i.sale_date BETWEEN b.snapshot_date - 1 AND b.snapshot_date
      AND s.status = 'COMPLETED'
    GROUP BY i.store_id
), alerts AS (
    SELECT store_id, count(*) AS active_alerts
    FROM fact_alert_snapshot
    WHERE snapshot_date = (SELECT snapshot_date FROM vw_published_batch)
      AND status = 'ACTIVE'
    GROUP BY store_id
), ruptures AS (
    SELECT store_id, count(DISTINCT inventory_id) AS products_in_rupture
    FROM vw_critical_stock
    GROUP BY store_id
)
SELECT s.store_id, s.name AS store_name,
       coalesce(a.active_alerts,0) AS active_alerts,
       coalesce(r.products_in_rupture,0) AS products_in_rupture,
       coalesce(x.revenue,0) AS daily_revenue,
       coalesce(x.avg_ticket,0) AS avg_ticket,
       coalesce(x.transactions,0) AS daily_transactions,
       coalesce(p.products_sold,0) AS products_sold,
       NULL::numeric(18,2) AS monthly_economy
FROM dim_store s
LEFT JOIN sales x ON x.store_id = s.store_id
LEFT JOIN products p ON p.store_id = s.store_id
LEFT JOIN alerts a ON a.store_id = s.store_id
LEFT JOIN ruptures r ON r.store_id = s.store_id
WHERE s.active
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_dashboard_metrics_store
    ON mv_dashboard_metrics(store_id);

-- ============================================================================
-- MODULE: 12_daily_batch.sql
-- ============================================================================
-- ============================================================================
-- DAILY OPERATIONAL TO ANALYTICS BATCH CONTRACT
-- PostgreSQL 15+
--
-- The external scheduler starts this pipeline at 02:00 America/Sao_Paulo,
-- after the previous business day has closed. PostgreSQL stores the contract,
-- staging, reconciliation, checkpoints and publication state; it does not
-- connect directly to the separate operational database.
-- ============================================================================

SET search_path TO mottainai_analytics, public;

DO $$ BEGIN
    CREATE TYPE daily_batch_status AS ENUM (
        'EXTRACTING', 'STAGED', 'TRANSFORMING',
        'VALIDATED', 'PUBLISHED', 'FAILED'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE etl_extraction_mode AS ENUM ('INCREMENTAL', 'SNAPSHOT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE etl_payload_policy AS ENUM (
        'BUSINESS', 'MINIMIZED', 'EXCLUDED'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
DECLARE
    v_can_manage_roles BOOLEAN;
BEGIN
    SELECT rolsuper OR rolcreaterole
    INTO v_can_manage_roles
    FROM pg_roles
    WHERE rolname = current_user;

    IF NOT coalesce(v_can_manage_roles, FALSE) THEN
        RAISE EXCEPTION
            'The analytics installer requires CREATEROLE to create safe group roles';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_analytics_loader') THEN
        CREATE ROLE mottainai_analytics_loader
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_analytics_reader') THEN
        CREATE ROLE mottainai_analytics_reader
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname IN ('mottainai_analytics_loader', 'mottainai_analytics_reader')
          AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
               OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'An analytics group role has unsafe attributes';
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS etl_pipeline_config (
    pipeline_name       VARCHAR(150) PRIMARY KEY,
    source_database     VARCHAR(80) NOT NULL,
    timezone_name       VARCHAR(80) NOT NULL,
    schedule_local_time TIME NOT NULL,
    staging_retention_days INTEGER NOT NULL DEFAULT 35
        CHECK (staging_retention_days BETWEEN 7 AND 365),
    enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etl_source_contract (
    source_table        VARCHAR(120) PRIMARY KEY,
    load_order          INTEGER NOT NULL CHECK (load_order > 0),
    extraction_mode     etl_extraction_mode NOT NULL,
    watermark_column    VARCHAR(120),
    target_object       VARCHAR(150),
    payload_policy      etl_payload_policy NOT NULL DEFAULT 'BUSINESS',
    required            BOOLEAN NOT NULL DEFAULT TRUE,
    enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    description         TEXT NOT NULL,
    CHECK (
        extraction_mode = 'SNAPSHOT'
        OR watermark_column IS NOT NULL
    ),
    CHECK (payload_policy <> 'EXCLUDED' OR enabled = FALSE)
);

ALTER TABLE job_log
    ADD COLUMN IF NOT EXISTS batch_id UUID,
    ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cutoff_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS etl_daily_batch (
    batch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_name       VARCHAR(150) NOT NULL
        REFERENCES etl_pipeline_config(pipeline_name) ON DELETE RESTRICT,
    job_id              BIGINT UNIQUE
        REFERENCES job_log(job_id) ON DELETE RESTRICT,
    business_date       DATE NOT NULL,
    scheduled_at        TIMESTAMPTZ NOT NULL,
    cutoff_at           TIMESTAMPTZ NOT NULL,
    status              daily_batch_status NOT NULL DEFAULT 'EXTRACTING',
    attempt_count       INTEGER NOT NULL DEFAULT 1 CHECK (attempt_count > 0),
    source_transaction_id TEXT,
    expected_rows       BIGINT NOT NULL DEFAULT 0 CHECK (expected_rows >= 0),
    staged_rows         BIGINT NOT NULL DEFAULT 0 CHECK (staged_rows >= 0),
    rejected_rows       BIGINT NOT NULL DEFAULT 0 CHECK (rejected_rows >= 0),
    rows_written        BIGINT NOT NULL DEFAULT 0 CHECK (rows_written >= 0),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    staged_at           TIMESTAMPTZ,
    validated_at        TIMESTAMPTZ,
    published_at        TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    error_message       TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (pipeline_name, business_date),
    CHECK (cutoff_at <= scheduled_at),
    CHECK (
        (scheduled_at AT TIME ZONE 'America/Sao_Paulo')::TIME = TIME '02:00:00'
    ),
    CHECK (
        business_date =
            (scheduled_at AT TIME ZONE 'America/Sao_Paulo')::DATE - 1
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_etl_daily_batch_published_date
    ON etl_daily_batch(pipeline_name, business_date)
    WHERE status = 'PUBLISHED';

CREATE TABLE IF NOT EXISTS stg_operational_row (
    staging_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id            UUID NOT NULL
        REFERENCES etl_daily_batch(batch_id) ON DELETE CASCADE,
    source_table        VARCHAR(120) NOT NULL
        REFERENCES etl_source_contract(source_table) ON DELETE RESTRICT,
    source_key          TEXT NOT NULL,
    company_id          BIGINT,
    store_id            BIGINT,
    payload             JSONB NOT NULL,
    source_created_at   TIMESTAMPTZ,
    source_updated_at   TIMESTAMPTZ,
    source_deleted_at   TIMESTAMPTZ,
    extracted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload_sha256      TEXT GENERATED ALWAYS AS (
        encode(digest(payload::TEXT, 'sha256'), 'hex')
    ) STORED,
    UNIQUE (batch_id, source_table, source_key)
);

CREATE TABLE IF NOT EXISTS etl_rejected_row (
    rejection_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id            UUID NOT NULL
        REFERENCES etl_daily_batch(batch_id) ON DELETE CASCADE,
    source_table        VARCHAR(120) NOT NULL,
    source_key          TEXT NOT NULL,
    payload_sha256      TEXT NOT NULL,
    rejection_reason    TEXT NOT NULL,
    rejected_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (batch_id, source_table, source_key, payload_sha256)
);

CREATE TABLE IF NOT EXISTS etl_reconciliation (
    batch_id            UUID NOT NULL
        REFERENCES etl_daily_batch(batch_id) ON DELETE CASCADE,
    source_table        VARCHAR(120) NOT NULL
        REFERENCES etl_source_contract(source_table) ON DELETE RESTRICT,
    expected_rows       BIGINT NOT NULL CHECK (expected_rows >= 0),
    staged_rows         BIGINT NOT NULL CHECK (staged_rows >= 0),
    matched             BOOLEAN NOT NULL,
    checked_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (batch_id, source_table)
);

CREATE TABLE IF NOT EXISTS etl_table_checkpoint (
    pipeline_name       VARCHAR(150) NOT NULL
        REFERENCES etl_pipeline_config(pipeline_name) ON DELETE RESTRICT,
    source_table        VARCHAR(120) NOT NULL
        REFERENCES etl_source_contract(source_table) ON DELETE RESTRICT,
    last_batch_id       UUID NOT NULL,
    last_business_date  DATE NOT NULL,
    last_source_key     TEXT,
    last_source_updated_at TIMESTAMPTZ,
    rows_staged         BIGINT NOT NULL DEFAULT 0,
    published_at        TIMESTAMPTZ NOT NULL,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (pipeline_name, source_table)
);

CREATE INDEX IF NOT EXISTS idx_etl_daily_batch_status_schedule
    ON etl_daily_batch(status, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_stg_operational_batch_table
    ON stg_operational_row(batch_id, source_table);
CREATE INDEX IF NOT EXISTS idx_stg_operational_watermark
    ON stg_operational_row(source_table, source_updated_at, source_key);
CREATE INDEX IF NOT EXISTS idx_etl_rejected_batch
    ON etl_rejected_row(batch_id, rejected_at);

INSERT INTO etl_pipeline_config (
    pipeline_name, source_database, timezone_name,
    schedule_local_time, staging_retention_days
) VALUES (
    'operational_to_analytics_daily',
    'mottainai_operational',
    'America/Sao_Paulo',
    TIME '02:00:00',
    35
)
ON CONFLICT (pipeline_name) DO UPDATE
SET source_database = EXCLUDED.source_database,
    timezone_name = EXCLUDED.timezone_name,
    schedule_local_time = EXCLUDED.schedule_local_time,
    updated_at = now();

INSERT INTO etl_source_contract (
    source_table, load_order, extraction_mode, watermark_column,
    target_object, payload_policy, required, enabled, description
) VALUES
    ('subscription_plan', 10, 'INCREMENTAL', 'updated_at', 'dim_company', 'BUSINESS', TRUE, TRUE, 'Plan attributes used by the company dimension'),
    ('address', 20, 'INCREMENTAL', 'updated_at', 'dim_store/dim_supplier', 'MINIMIZED', TRUE, TRUE, 'Only city and state may leave the operational database'),
    ('company', 30, 'INCREMENTAL', 'updated_at', 'dim_company', 'BUSINESS', TRUE, TRUE, 'Company dimension source'),
    ('employee_role', 40, 'INCREMENTAL', 'updated_at', 'dim_employee', 'BUSINESS', TRUE, TRUE, 'Role name source'),
    ('retail_store', 50, 'INCREMENTAL', 'updated_at', 'dim_store', 'MINIMIZED', TRUE, TRUE, 'Store dimension without contacts'),
    ('employee', 60, 'INCREMENTAL', 'updated_at', 'dim_employee', 'MINIMIZED', TRUE, TRUE, 'Employee dimension without identity or contacts'),
    ('product_category', 70, 'INCREMENTAL', 'updated_at', 'dim_category', 'BUSINESS', TRUE, TRUE, 'Product category dimension'),
    ('tax_profile', 80, 'INCREMENTAL', 'updated_at', 'dim_product', 'BUSINESS', TRUE, TRUE, 'Tax attributes required by product analytics'),
    ('product', 90, 'INCREMENTAL', 'updated_at', 'dim_product', 'BUSINESS', TRUE, TRUE, 'Product dimension source'),
    ('supplier', 100, 'INCREMENTAL', 'updated_at', 'dim_supplier', 'MINIMIZED', TRUE, TRUE, 'Supplier dimension without contacts'),
    ('supplier_product', 110, 'INCREMENTAL', 'updated_at', 'fact_purchase_order', 'BUSINESS', TRUE, TRUE, 'Supplier and product commercial relation'),
    ('store_product_price', 120, 'INCREMENTAL', 'updated_at', 'product_price_history', 'BUSINESS', TRUE, TRUE, 'Current store price source'),
    ('purchase_order', 200, 'INCREMENTAL', 'order_date', 'fact_purchase_order', 'BUSINESS', TRUE, TRUE, 'Purchase order fact source'),
    ('purchase_order_item', 210, 'INCREMENTAL', 'order_date', 'fact_purchase_order', 'BUSINESS', TRUE, TRUE, 'Purchase order item source'),
    ('receiving', 220, 'INCREMENTAL', 'receiving_date', 'fact_receiving', 'BUSINESS', TRUE, TRUE, 'Receiving fact source'),
    ('receiving_item', 230, 'INCREMENTAL', 'created_at', 'fact_receiving', 'BUSINESS', TRUE, TRUE, 'Receiving item source'),
    ('batch', 240, 'INCREMENTAL', 'updated_at', 'fact_inventory_snapshot', 'BUSINESS', TRUE, TRUE, 'Product batch and expiration source'),
    ('inventory', 250, 'SNAPSHOT', NULL, 'fact_inventory_snapshot', 'BUSINESS', TRUE, TRUE, 'Complete end-of-shift inventory position'),
    ('inventory_movement', 260, 'INCREMENTAL', 'movement_date', 'fact_inventory_movement', 'BUSINESS', TRUE, TRUE, 'Inventory movement fact source'),
    ('inventory_count', 270, 'INCREMENTAL', 'updated_at', 'fact_inventory_snapshot', 'BUSINESS', TRUE, TRUE, 'Physical inventory header'),
    ('inventory_count_item', 280, 'INCREMENTAL', 'created_at', 'fact_inventory_snapshot', 'BUSINESS', TRUE, TRUE, 'Physical inventory item'),
    ('pos_terminal', 300, 'INCREMENTAL', 'updated_at', 'fact_store_daily', 'BUSINESS', TRUE, TRUE, 'Point-of-sale terminal state'),
    ('pos_shift', 310, 'INCREMENTAL', 'opened_at', 'fact_store_daily', 'BUSINESS', TRUE, TRUE, 'Shift lifecycle source'),
    ('pos_cash_movement', 320, 'INCREMENTAL', 'created_at', 'fact_store_daily', 'BUSINESS', TRUE, TRUE, 'Cash movement analytics source'),
    ('sales_transaction', 330, 'INCREMENTAL', 'sale_date', 'fact_sales', 'MINIMIZED', TRUE, TRUE, 'Sales fact without customer documents'),
    ('sale_item', 340, 'INCREMENTAL', 'sale_date', 'fact_sale_item', 'BUSINESS', TRUE, TRUE, 'Sale item fact source'),
    ('sale_payment', 350, 'INCREMENTAL', 'created_at', 'fact_sale_payment', 'BUSINESS', TRUE, TRUE, 'Payment method fact source'),
    ('fiscal_document', 360, 'INCREMENTAL', 'created_at', 'fact_sales', 'MINIMIZED', TRUE, TRUE, 'Fiscal status without document secrets'),
    ('pos_cancel_request', 370, 'INCREMENTAL', 'created_at', 'fact_sales', 'BUSINESS', TRUE, TRUE, 'Cancellation source'),
    ('alert', 400, 'INCREMENTAL', 'updated_at', 'fact_alert_snapshot', 'BUSINESS', TRUE, TRUE, 'Operational alert snapshot'),
    ('suggested_action', 410, 'INCREMENTAL', 'updated_at', 'engine_suggestion', 'BUSINESS', TRUE, TRUE, 'Operational action feedback'),
    ('promotion', 420, 'INCREMENTAL', 'updated_at', 'fact_promotion_result', 'BUSINESS', TRUE, TRUE, 'Promotion header source'),
    ('promotion_item', 430, 'INCREMENTAL', 'created_at', 'fact_promotion_result', 'BUSINESS', TRUE, TRUE, 'Promotion item source'),
    ('customer', 440, 'INCREMENTAL', 'updated_at', 'dim_customer', 'MINIMIZED', TRUE, TRUE, 'Only anonymous key, birth year, flags and consent may be staged'),
    ('customer_geofence', 450, 'INCREMENTAL', 'updated_at', 'dim_customer', 'MINIMIZED', TRUE, TRUE, 'Minimized customer engagement source'),
    ('customer_consent', 460, 'INCREMENTAL', 'recorded_at', 'dim_customer', 'MINIMIZED', TRUE, TRUE, 'Consent state without identity attributes'),
    ('loyalty_account', 470, 'INCREMENTAL', 'updated_at', 'fact_loyalty', 'MINIMIZED', TRUE, TRUE, 'Anonymous loyalty balance source'),
    ('loyalty_transaction', 480, 'INCREMENTAL', 'created_at', 'fact_loyalty', 'MINIMIZED', TRUE, TRUE, 'Anonymous loyalty movement source'),
    ('loyalty_reward', 490, 'INCREMENTAL', 'updated_at', 'fact_loyalty', 'BUSINESS', TRUE, TRUE, 'Reward catalog source'),
    ('loyalty_redemption', 500, 'INCREMENTAL', 'redeemed_at', 'fact_loyalty', 'MINIMIZED', TRUE, TRUE, 'Anonymous redemption source'),
    ('transfer', 510, 'INCREMENTAL', 'updated_at', 'fact_transfer', 'BUSINESS', TRUE, TRUE, 'Transfer header source'),
    ('transfer_item', 520, 'INCREMENTAL', 'created_at', 'fact_transfer', 'BUSINESS', TRUE, TRUE, 'Transfer item source'),
    ('donation', 530, 'INCREMENTAL', 'updated_at', 'fact_loss_destination', 'BUSINESS', TRUE, TRUE, 'Donation loss destination source'),
    ('donation_item', 540, 'INCREMENTAL', 'created_at', 'fact_loss_destination', 'BUSINESS', TRUE, TRUE, 'Donation item source'),
    ('disposal', 550, 'INCREMENTAL', 'updated_at', 'fact_loss_destination', 'BUSINESS', TRUE, TRUE, 'Disposal loss destination source'),
    ('disposal_item', 560, 'INCREMENTAL', 'created_at', 'fact_loss_destination', 'BUSINESS', TRUE, TRUE, 'Disposal item source'),
    ('replenishment_pre_list', 570, 'INCREMENTAL', 'updated_at', 'fact_replenishment', 'BUSINESS', TRUE, TRUE, 'Replenishment planning source'),
    ('replenishment_pre_list_item', 580, 'INCREMENTAL', 'created_at', 'fact_replenishment', 'BUSINESS', TRUE, TRUE, 'Replenishment planning item'),
    ('replenishment_execution', 590, 'INCREMENTAL', 'updated_at', 'fact_replenishment', 'BUSINESS', TRUE, TRUE, 'Replenishment execution source'),
    ('replenishment_execution_item', 600, 'INCREMENTAL', 'created_at', 'fact_replenishment', 'BUSINESS', TRUE, TRUE, 'Replenishment execution item'),
    ('product_history', 610, 'INCREMENTAL', 'changed_at', 'dim_product', 'BUSINESS', TRUE, TRUE, 'Product attribute history'),
    ('supplier_history', 620, 'INCREMENTAL', 'changed_at', 'dim_supplier', 'BUSINESS', TRUE, TRUE, 'Supplier attribute history without contacts'),
    ('product_price_history', 630, 'INCREMENTAL', 'changed_at', 'dim_product', 'BUSINESS', TRUE, TRUE, 'Product price history'),
    ('system_rule', 640, 'INCREMENTAL', 'updated_at', 'engine_suggestion', 'BUSINESS', TRUE, TRUE, 'Rules used to explain analytical recommendations'),
    ('customer_private_data', 898, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Encrypted customer identity envelopes never enter analytics'),
    ('employee_private_data', 899, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Encrypted identity envelopes and masks never enter analytics'),
    ('app_user', 900, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Authentication accounts never enter analytics'),
    ('customer_auth', 901, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Customer credentials never enter analytics'),
    ('staff_session', 902, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Session hashes never enter analytics'),
    ('password_reset_token', 903, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Recovery hashes never enter analytics'),
    ('audit_log', 904, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Operational audit remains in its source database'),
    ('system_log', 905, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Operational logs remain in their source database'),
    ('error_log', 906, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Error details and stack traces remain operational'),
    ('integration_log', 907, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Integration payloads are not copied'),
    ('event_queue', 908, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'The daily batch supersedes raw event payload replication'),
    ('legacy_sync_record', 909, 'SNAPSHOT', NULL, NULL, 'EXCLUDED', FALSE, FALSE, 'Legacy correlation metadata remains operational')
ON CONFLICT (source_table) DO UPDATE
SET load_order = EXCLUDED.load_order,
    extraction_mode = EXCLUDED.extraction_mode,
    watermark_column = EXCLUDED.watermark_column,
    target_object = EXCLUDED.target_object,
    payload_policy = EXCLUDED.payload_policy,
    required = EXCLUDED.required,
    enabled = EXCLUDED.enabled,
    description = EXCLUDED.description;

CREATE OR REPLACE FUNCTION fn_payload_has_forbidden_key(p_payload JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, mottainai_analytics
AS $$
DECLARE
    v_key TEXT;
    v_value JSONB;
BEGIN
    IF jsonb_typeof(p_payload) = 'object' THEN
        FOR v_key, v_value IN SELECT * FROM jsonb_each(p_payload)
        LOOP
            IF lower(v_key) = ANY (ARRAY[
                'cpf', 'email', 'phone', 'full_name', 'customer_document',
                'password', 'password_hash', 'refresh_token',
                'refresh_token_hash', 'token_hash', 'recovery_token_hash',
                'code_hash', 'firebase_uid', 'address_token', 'street',
                'number', 'neighborhood', 'zip_code', 'old_data', 'new_data',
                'stack_trace', 'parameters', 'payload', 'response',
                'payload_ciphertext', 'payload_nonce', 'payload_format',
                'name_ciphertext', 'name_nonce', 'name_token', 'name_masked',
                'cpf_ciphertext', 'cpf_nonce', 'cpf_masked',
                'email_ciphertext', 'email_nonce', 'email_token', 'email_masked',
                'phone_ciphertext', 'phone_nonce', 'phone_token', 'phone_masked',
                'key_version', 'encrypted_at'
            ]) THEN
                RETURN TRUE;
            END IF;

            IF jsonb_typeof(v_value) IN ('object', 'array')
               AND mottainai_analytics.fn_payload_has_forbidden_key(v_value) THEN
                RETURN TRUE;
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(p_payload) = 'array' THEN
        FOR v_value IN SELECT value FROM jsonb_array_elements(p_payload)
        LOOP
            IF jsonb_typeof(v_value) IN ('object', 'array')
               AND mottainai_analytics.fn_payload_has_forbidden_key(v_value) THEN
                RETURN TRUE;
            END IF;
        END LOOP;
    END IF;

    RETURN FALSE;
END;
$$;

ALTER TABLE stg_operational_row
    DROP CONSTRAINT IF EXISTS ck_stg_operational_payload_safe;
ALTER TABLE stg_operational_row
    ADD CONSTRAINT ck_stg_operational_payload_safe
    CHECK (NOT fn_payload_has_forbidden_key(payload));

CREATE OR REPLACE FUNCTION fn_begin_daily_batch(
    p_business_date DATE,
    p_cutoff_at TIMESTAMPTZ DEFAULT NULL,
    p_source_transaction_id TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_pipeline CONSTANT VARCHAR(150) := 'operational_to_analytics_daily';
    v_timezone VARCHAR(80);
    v_schedule TIME;
    v_scheduled_at TIMESTAMPTZ;
    v_cutoff_at TIMESTAMPTZ;
    v_batch etl_daily_batch%ROWTYPE;
    v_job_id BIGINT;
BEGIN
    IF p_business_date IS NULL THEN
        RAISE EXCEPTION 'business_date is required';
    END IF;

    SELECT timezone_name, schedule_local_time
    INTO v_timezone, v_schedule
    FROM etl_pipeline_config
    WHERE pipeline_name = v_pipeline
      AND enabled;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Daily analytics pipeline is disabled or missing';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_timezone) THEN
        RAISE EXCEPTION 'Invalid pipeline timezone: %', v_timezone;
    END IF;

    IF p_business_date >= (now() AT TIME ZONE v_timezone)::date THEN
        RAISE EXCEPTION 'business_date must identify a closed day before today in %',
            v_timezone;
    END IF;

    v_scheduled_at := ((p_business_date + 1)::TIMESTAMP + v_schedule)
        AT TIME ZONE v_timezone;
    v_cutoff_at := coalesce(p_cutoff_at, v_scheduled_at);

    IF v_cutoff_at > v_scheduled_at THEN
        RAISE EXCEPTION 'cutoff_at cannot be after the scheduled 02:00 execution';
    END IF;

    SELECT * INTO v_batch
    FROM etl_daily_batch
    WHERE pipeline_name = v_pipeline
      AND business_date = p_business_date
    FOR UPDATE;

    IF FOUND AND v_batch.status = 'PUBLISHED' THEN
        RETURN v_batch.batch_id;
    ELSIF FOUND AND v_batch.status <> 'FAILED' THEN
        RAISE EXCEPTION 'Batch % is currently in status %',
            v_batch.batch_id, v_batch.status;
    END IF;

    INSERT INTO job_log (
        job_name, status, scheduled_at, cutoff_at, metadata
    ) VALUES (
        v_pipeline, 'RUNNING', v_scheduled_at, v_cutoff_at,
        coalesce(p_metadata, '{}'::jsonb)
            || jsonb_build_object('business_date', p_business_date)
    )
    RETURNING job_id INTO v_job_id;

    IF v_batch.batch_id IS NULL THEN
        INSERT INTO etl_daily_batch (
            pipeline_name, job_id, business_date, scheduled_at, cutoff_at,
            source_transaction_id, metadata
        ) VALUES (
            v_pipeline, v_job_id, p_business_date, v_scheduled_at, v_cutoff_at,
            p_source_transaction_id, coalesce(p_metadata, '{}'::jsonb)
        )
        RETURNING batch_id INTO v_batch.batch_id;
    ELSE
        DELETE FROM stg_operational_row WHERE batch_id = v_batch.batch_id;
        DELETE FROM etl_rejected_row WHERE batch_id = v_batch.batch_id;
        DELETE FROM etl_reconciliation WHERE batch_id = v_batch.batch_id;

        UPDATE etl_daily_batch
        SET job_id = v_job_id,
            scheduled_at = v_scheduled_at,
            cutoff_at = v_cutoff_at,
            status = 'EXTRACTING',
            attempt_count = attempt_count + 1,
            source_transaction_id = p_source_transaction_id,
            expected_rows = 0,
            staged_rows = 0,
            rejected_rows = 0,
            rows_written = 0,
            started_at = now(),
            staged_at = NULL,
            validated_at = NULL,
            published_at = NULL,
            finished_at = NULL,
            error_message = NULL,
            metadata = coalesce(p_metadata, '{}'::jsonb)
        WHERE batch_id = v_batch.batch_id;
    END IF;

    RETURN v_batch.batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_stage_operational_row(
    p_batch_id UUID,
    p_source_table VARCHAR,
    p_source_key TEXT,
    p_payload JSONB,
    p_company_id BIGINT DEFAULT NULL,
    p_store_id BIGINT DEFAULT NULL,
    p_source_created_at TIMESTAMPTZ DEFAULT NULL,
    p_source_updated_at TIMESTAMPTZ DEFAULT NULL,
    p_source_deleted_at TIMESTAMPTZ DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_status daily_batch_status;
    v_contract etl_source_contract%ROWTYPE;
    v_payload_hash TEXT;
BEGIN
    SELECT status INTO v_status
    FROM etl_daily_batch
    WHERE batch_id = p_batch_id
    FOR UPDATE;

    IF v_status IS NULL OR v_status <> 'EXTRACTING' THEN
        RAISE EXCEPTION 'Batch % is not accepting staged rows', p_batch_id;
    END IF;

    SELECT * INTO v_contract
    FROM etl_source_contract
    WHERE source_table = p_source_table;

    IF NOT FOUND OR NOT v_contract.enabled
       OR v_contract.payload_policy = 'EXCLUDED' THEN
        RAISE EXCEPTION 'Source table % is not allowed in analytics', p_source_table;
    END IF;

    IF p_source_key IS NULL OR btrim(p_source_key) = '' OR p_payload IS NULL THEN
        RAISE EXCEPTION 'source_key and payload are required';
    END IF;

    IF fn_payload_has_forbidden_key(p_payload) THEN
        v_payload_hash := encode(public.digest(p_payload::TEXT, 'sha256'), 'hex');
        INSERT INTO etl_rejected_row (
            batch_id, source_table, source_key,
            payload_sha256, rejection_reason
        ) VALUES (
            p_batch_id, p_source_table, p_source_key,
            v_payload_hash, 'Payload contains a field forbidden in analytics'
        )
        ON CONFLICT DO NOTHING;

        UPDATE etl_daily_batch
        SET rejected_rows = (
            SELECT count(*) FROM etl_rejected_row
            WHERE batch_id = p_batch_id
        )
        WHERE batch_id = p_batch_id;
        RETURN FALSE;
    END IF;

    INSERT INTO stg_operational_row (
        batch_id, source_table, source_key, company_id, store_id, payload,
        source_created_at, source_updated_at, source_deleted_at
    ) VALUES (
        p_batch_id, p_source_table, p_source_key, p_company_id, p_store_id,
        p_payload, p_source_created_at, p_source_updated_at, p_source_deleted_at
    )
    ON CONFLICT (batch_id, source_table, source_key) DO UPDATE
    SET company_id = EXCLUDED.company_id,
        store_id = EXCLUDED.store_id,
        payload = EXCLUDED.payload,
        source_created_at = EXCLUDED.source_created_at,
        source_updated_at = EXCLUDED.source_updated_at,
        source_deleted_at = EXCLUDED.source_deleted_at,
        extracted_at = now();

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_reconcile_daily_batch(
    p_batch_id UUID,
    p_expected_counts JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_missing TEXT;
    v_expected_total BIGINT;
    v_staged_total BIGINT;
    v_rejected_total BIGINT;
    v_mismatch_count INTEGER;
    v_job_id BIGINT;
BEGIN
    IF coalesce(jsonb_typeof(p_expected_counts), '') <> 'object' THEN
        RAISE EXCEPTION 'expected_counts must be a JSON object';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM etl_daily_batch
        WHERE batch_id = p_batch_id AND status = 'EXTRACTING'
    ) THEN
        RAISE EXCEPTION 'Batch % is not ready for reconciliation', p_batch_id;
    END IF;

    SELECT string_agg(source_table, ', ' ORDER BY load_order)
    INTO v_missing
    FROM etl_source_contract
    WHERE enabled AND required
      AND NOT (p_expected_counts ? source_table);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Expected counts missing for: %', v_missing;
    END IF;

    DELETE FROM etl_reconciliation WHERE batch_id = p_batch_id;

    INSERT INTO etl_reconciliation (
        batch_id, source_table, expected_rows, staged_rows, matched
    )
    SELECT
        p_batch_id,
        contract.source_table,
        (p_expected_counts ->> contract.source_table)::BIGINT,
        coalesce(staged.row_count, 0),
        (p_expected_counts ->> contract.source_table)::BIGINT
            = coalesce(staged.row_count, 0)
    FROM etl_source_contract contract
    LEFT JOIN (
        SELECT source_table, count(*) AS row_count
        FROM stg_operational_row
        WHERE batch_id = p_batch_id
        GROUP BY source_table
    ) staged ON staged.source_table = contract.source_table
    WHERE contract.enabled AND contract.required;

    SELECT coalesce(sum(expected_rows), 0),
           coalesce(sum(staged_rows), 0),
           count(*) FILTER (WHERE NOT matched)
    INTO v_expected_total, v_staged_total, v_mismatch_count
    FROM etl_reconciliation
    WHERE batch_id = p_batch_id;

    SELECT count(*) INTO v_rejected_total
    FROM etl_rejected_row
    WHERE batch_id = p_batch_id;

    SELECT job_id INTO v_job_id
    FROM etl_daily_batch
    WHERE batch_id = p_batch_id;

    IF v_mismatch_count > 0 OR v_rejected_total > 0 THEN
        UPDATE etl_daily_batch
        SET status = 'FAILED',
            expected_rows = v_expected_total,
            staged_rows = v_staged_total,
            rejected_rows = v_rejected_total,
            finished_at = now(),
            error_message = format(
                'Reconciliation failed: %s mismatches and %s rejected rows',
                v_mismatch_count, v_rejected_total)
        WHERE batch_id = p_batch_id;

        UPDATE job_log
        SET status = 'FAILED',
            finished_at = now(),
            rows_read = v_staged_total,
            error_message = format(
                'Reconciliation failed: %s mismatches and %s rejected rows',
                v_mismatch_count, v_rejected_total)
        WHERE job_id = v_job_id;
        RETURN FALSE;
    END IF;

    UPDATE etl_daily_batch
    SET status = 'STAGED',
        expected_rows = v_expected_total,
        staged_rows = v_staged_total,
        rejected_rows = 0,
        staged_at = now()
    WHERE batch_id = p_batch_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_mark_daily_batch_transformed(
    p_batch_id UUID,
    p_rows_written BIGINT,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
BEGIN
    IF p_rows_written IS NULL OR p_rows_written < 0 THEN
        RAISE EXCEPTION 'rows_written must be zero or greater';
    END IF;

    UPDATE etl_daily_batch
    SET status = 'VALIDATED',
        rows_written = p_rows_written,
        validated_at = now(),
        metadata = metadata || coalesce(p_metadata, '{}'::jsonb)
    WHERE batch_id = p_batch_id
      AND status IN ('STAGED', 'TRANSFORMING');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Batch % is not ready to be validated', p_batch_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_publish_daily_batch(p_batch_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_batch etl_daily_batch%ROWTYPE;
    v_published_at TIMESTAMPTZ := now();
BEGIN
    SELECT * INTO v_batch
    FROM etl_daily_batch
    WHERE batch_id = p_batch_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Batch % does not exist', p_batch_id;
    ELSIF v_batch.status = 'PUBLISHED' THEN
        RETURN;
    ELSIF v_batch.status <> 'VALIDATED' THEN
        RAISE EXCEPTION 'Batch % must be VALIDATED before publication', p_batch_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM etl_reconciliation
        WHERE batch_id = p_batch_id AND NOT matched
    ) OR NOT EXISTS (
        SELECT 1 FROM etl_reconciliation WHERE batch_id = p_batch_id
    ) THEN
        RAISE EXCEPTION 'Batch % has no successful reconciliation', p_batch_id;
    END IF;

    INSERT INTO etl_table_checkpoint (
        pipeline_name, source_table, last_batch_id, last_business_date,
        last_source_key, last_source_updated_at, rows_staged, published_at
    )
    SELECT
        v_batch.pipeline_name,
        reconciliation.source_table,
        v_batch.batch_id,
        v_batch.business_date,
        max(staging.source_key),
        max(staging.source_updated_at),
        reconciliation.staged_rows,
        v_published_at
    FROM etl_reconciliation reconciliation
    LEFT JOIN stg_operational_row staging
      ON staging.batch_id = reconciliation.batch_id
     AND staging.source_table = reconciliation.source_table
    WHERE reconciliation.batch_id = p_batch_id
    GROUP BY reconciliation.source_table, reconciliation.staged_rows
    ON CONFLICT (pipeline_name, source_table) DO UPDATE
    SET last_batch_id = EXCLUDED.last_batch_id,
        last_business_date = EXCLUDED.last_business_date,
        last_source_key = EXCLUDED.last_source_key,
        last_source_updated_at = EXCLUDED.last_source_updated_at,
        rows_staged = EXCLUDED.rows_staged,
        published_at = EXCLUDED.published_at;

    UPDATE etl_checkpoint
    SET last_source_id = v_batch.job_id,
        last_occurred_at = v_batch.cutoff_at,
        updated_at = v_published_at,
        metadata = metadata || jsonb_build_object(
            'batch_id', v_batch.batch_id,
            'business_date', v_batch.business_date,
            'schedule', '02:00 America/Sao_Paulo'
        )
    WHERE pipeline_name = v_batch.pipeline_name;

    IF NOT FOUND THEN
        INSERT INTO etl_checkpoint (
            pipeline_name, last_source_id, last_occurred_at, metadata
        ) VALUES (
            v_batch.pipeline_name, v_batch.job_id, v_batch.cutoff_at,
            jsonb_build_object(
                'batch_id', v_batch.batch_id,
                'business_date', v_batch.business_date,
                'schedule', '02:00 America/Sao_Paulo'
            )
        );
    END IF;

    UPDATE etl_daily_batch
    SET status = 'PUBLISHED',
        published_at = v_published_at,
        finished_at = v_published_at
    WHERE batch_id = p_batch_id;

    UPDATE job_log
    SET status = 'SUCCEEDED',
        finished_at = v_published_at,
        rows_read = v_batch.staged_rows,
        rows_written = v_batch.rows_written,
        batch_id = v_batch.batch_id,
        metadata = metadata || jsonb_build_object(
            'business_date', v_batch.business_date,
            'published_at', v_published_at
        )
    WHERE job_id = v_batch.job_id;

    IF to_regclass('mottainai_analytics.mv_dashboard_metrics') IS NOT NULL THEN
        REFRESH MATERIALIZED VIEW mv_dashboard_metrics;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_fail_daily_batch(
    p_batch_id UUID,
    p_error_message TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_job_id BIGINT;
BEGIN
    UPDATE etl_daily_batch
    SET status = 'FAILED',
        error_message = left(coalesce(p_error_message, 'Unspecified ETL failure'), 4000),
        finished_at = now()
    WHERE batch_id = p_batch_id
      AND status <> 'PUBLISHED'
    RETURNING job_id INTO v_job_id;

    IF v_job_id IS NOT NULL THEN
        UPDATE job_log
        SET status = 'FAILED',
            finished_at = now(),
            error_message = left(coalesce(p_error_message, 'Unspecified ETL failure'), 4000)
        WHERE job_id = v_job_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_purge_daily_batch_staging()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai_analytics, pg_temp
AS $$
DECLARE
    v_retention_days INTEGER;
BEGIN
    SELECT staging_retention_days INTO v_retention_days
    FROM etl_pipeline_config
    WHERE pipeline_name = 'operational_to_analytics_daily';

    DELETE FROM etl_daily_batch
    WHERE status IN ('PUBLISHED', 'FAILED')
      AND finished_at < now() - make_interval(days => v_retention_days);
END;
$$;

CREATE OR REPLACE VIEW vw_published_batch AS
SELECT
    job_id,
    cutoff_at AS source_cutoff_at,
    (cutoff_at AT TIME ZONE 'America/Sao_Paulo')::DATE AS snapshot_date,
    batch_id,
    finished_at AS published_at
FROM job_log
WHERE job_name = 'operational_to_analytics_daily'
  AND status = 'SUCCEEDED'
  AND batch_id IS NOT NULL
  AND cutoff_at IS NOT NULL
  AND metadata ->> 'publication_contract' = 'analytics_mart_v1'
ORDER BY finished_at DESC, job_id DESC
LIMIT 1;

COMMENT ON VIEW vw_published_batch IS 'publication_contract=analytics_mart_v1';

CREATE OR REPLACE VIEW vw_etl_daily_batch_health AS
SELECT
    batch.batch_id,
    batch.business_date,
    batch.scheduled_at,
    batch.cutoff_at,
    batch.status,
    batch.attempt_count,
    batch.expected_rows,
    batch.staged_rows,
    batch.rejected_rows,
    batch.rows_written,
    batch.started_at,
    batch.finished_at,
    batch.published_at,
    batch.error_message,
    extract(epoch FROM (coalesce(batch.finished_at, now()) - batch.started_at))
        AS duration_seconds,
    batch.started_at > batch.scheduled_at + interval '15 minutes' AS started_late
FROM etl_daily_batch batch
ORDER BY batch.business_date DESC;

COMMENT ON TABLE stg_operational_row IS
    'Idempotent staging for the 02:00 daily batch. Raw credentials and personal contact fields are forbidden.';
COMMENT ON TABLE etl_daily_batch IS
    'One restartable and publish-once analytical batch per closed business day.';
COMMENT ON VIEW vw_etl_daily_batch_health IS
    'Operational monitoring of the daily 02:00 analytics publication.';

REVOKE ALL ON FUNCTION fn_payload_has_forbidden_key(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_begin_daily_batch(DATE, TIMESTAMPTZ, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_stage_operational_row(
    UUID, VARCHAR, TEXT, JSONB, BIGINT, BIGINT,
    TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_reconcile_daily_batch(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mark_daily_batch_transformed(UUID, BIGINT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_publish_daily_batch(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_fail_daily_batch(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_purge_daily_batch_staging() FROM PUBLIC;

GRANT USAGE ON SCHEMA mottainai_analytics
    TO mottainai_analytics_loader, mottainai_analytics_reader;
GRANT EXECUTE ON FUNCTION fn_begin_daily_batch(DATE, TIMESTAMPTZ, TEXT, JSONB),
    fn_stage_operational_row(
        UUID, VARCHAR, TEXT, JSONB, BIGINT, BIGINT,
        TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
    ),
    fn_reconcile_daily_batch(UUID, JSONB),
    fn_mark_daily_batch_transformed(UUID, BIGINT, JSONB),
    fn_publish_daily_batch(UUID),
    fn_fail_daily_batch(UUID, TEXT)
    TO mottainai_analytics_loader;
GRANT EXECUTE ON PROCEDURE sp_purge_daily_batch_staging()
    TO mottainai_analytics_loader;
GRANT SELECT ON etl_pipeline_config, etl_source_contract,
    etl_daily_batch, etl_reconciliation, etl_table_checkpoint,
    vw_etl_daily_batch_health, vw_published_batch
    TO mottainai_analytics_loader;
GRANT SELECT ON vw_etl_daily_batch_health, vw_published_batch
    TO mottainai_analytics_reader;

GRANT SELECT, INSERT, UPDATE ON
    dim_date, dim_company, dim_store, dim_category, dim_product,
    dim_supplier, dim_employee, dim_customer,
    fact_sales, fact_sale_item, fact_sale_payment,
    fact_inventory_movement, fact_inventory_snapshot,
    fact_purchase_order, fact_receiving, fact_promotion_result,
    fact_loss_destination, fact_transfer, fact_replenishment,
    fact_loyalty, fact_store_daily, fact_alert_snapshot
    TO mottainai_analytics_loader;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mottainai_analytics
    TO mottainai_analytics_loader;

GRANT SELECT ON
    dim_date, dim_company, dim_store, dim_category, dim_product,
    dim_supplier, dim_employee, dim_customer,
    fact_sales, fact_sale_item, fact_sale_payment,
    fact_inventory_movement, fact_inventory_snapshot,
    fact_purchase_order, fact_receiving, fact_promotion_result,
    fact_loss_destination, fact_transfer, fact_replenishment,
    fact_loyalty, fact_store_daily, fact_alert_snapshot,
    vw_sales_daily_kpis, vw_top_selling_products,
    vw_inventory_snapshot_current, vw_stockout_analysis,
    vw_ai_performance, vw_engine_suggestion_metrics,
    vw_executive_dashboard, vw_customer_loyalty_analysis,
    vw_company_kpis, vw_employee_distribution, vw_store_daily_kpis,
    vw_critical_stock, vw_monthly_summary, vw_product_risk_ranking,
    mv_dashboard_metrics
    TO mottainai_analytics_reader;

INSERT INTO schema_version (version, description)
VALUES (12, 'Daily 02:00 operational-to-analytics batch contract')
ON CONFLICT (version) DO UPDATE
SET description = EXCLUDED.description,
    applied_at = now();

-- ============================================================================
-- MODULE: 09_tests.sql
-- ============================================================================
DO $$
DECLARE
    required_table TEXT;
    partitioned_table TEXT;
    current_partition_bound TEXT;
    current_month DATE := date_trunc('month', current_date)::date;
    next_month DATE := (date_trunc('month', current_date) + interval '1 month')::date;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'dim_date', 'dim_product', 'fact_sales', 'fact_inventory_snapshot',
        'fact_transfer', 'ai_model', 'ai_recommendation',
        'ingestion_event', 'etl_checkpoint'
    ]
    LOOP
        IF to_regclass('mottainai_analytics.' || required_table) IS NULL THEN
            RAISE EXCEPTION 'Tabela analitica obrigatoria ausente: %', required_table;
        END IF;
    END LOOP;

    IF to_regclass('mottainai_analytics.inventory') IS NOT NULL
       OR to_regclass('mottainai_analytics.sales_transaction') IS NOT NULL THEN
        RAISE EXCEPTION 'Tabelas transacionais nao devem existir no banco analitico';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai_analytics'
          AND table_name = 'dim_customer'
          AND column_name IN ('cpf', 'email', 'phone', 'full_name')
    ) THEN
        RAISE EXCEPTION 'A dimensao de cliente contem dados pessoais desnecessarios';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        WHERE namespace.nspname = 'mottainai_analytics'
          AND parent.relname IN (
              'fact_sales', 'fact_sale_item',
              'fact_inventory_movement', 'fact_inventory_snapshot'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM pg_class child
              WHERE child.oid = inheritance.inhrelid
                AND child.relname LIKE '%_default'
          )
    ) < 76 THEN
        RAISE EXCEPTION 'Monthly analytical partitions were not created';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai_analytics'
          AND table_name = 'fact_transfer'
          AND column_name = 'destination_store_id'
    ) THEN
        RAISE EXCEPTION 'fact_transfer definition is incomplete';
    END IF;

    FOREACH partitioned_table IN ARRAY ARRAY[
        'fact_sales', 'fact_sale_item',
        'fact_inventory_movement', 'fact_inventory_snapshot'
    ]
    LOOP
        SELECT pg_get_expr(child.relpartbound, child.oid)
        INTO current_partition_bound
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        WHERE namespace.nspname = 'mottainai_analytics'
          AND parent.relname = partitioned_table
          AND child.relname = partitioned_table || '_' || to_char(current_month, 'YYYY_MM');

        IF current_partition_bound IS NULL
           OR position(current_month::text IN current_partition_bound) = 0
           OR position(next_month::text IN current_partition_bound) = 0 THEN
            RAISE EXCEPTION 'Invalid current-month partition bound for %: %',
                partitioned_table, current_partition_bound;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- MODULE: 13_daily_batch_tests.sql
-- ============================================================================
-- ============================================================================
-- DAILY ANALYTICS BATCH CONTRACT TESTS
-- Test-only module.
-- ============================================================================

SET search_path TO mottainai_analytics, public;

DO $$
DECLARE
    v_required TEXT[];
BEGIN
    SELECT array_agg(required.object_name ORDER BY required.object_name)
    INTO v_required
    FROM (VALUES
        ('etl_pipeline_config'),
        ('etl_source_contract'),
        ('etl_daily_batch'),
        ('stg_operational_row'),
        ('etl_reconciliation'),
        ('etl_table_checkpoint'),
        ('etl_rejected_row')
    ) required(object_name)
    WHERE to_regclass('mottainai_analytics.' || required.object_name) IS NULL;

    IF v_required IS NOT NULL THEN
        RAISE EXCEPTION 'Missing daily batch objects: %', v_required;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM etl_pipeline_config
        WHERE pipeline_name = 'operational_to_analytics_daily'
          AND timezone_name = 'America/Sao_Paulo'
          AND schedule_local_time = TIME '02:00:00'
          AND enabled
    ) THEN
        RAISE EXCEPTION 'The daily 02:00 schedule contract is missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM etl_source_contract
        WHERE source_table IN (
            'customer_private_data', 'employee_private_data', 'app_user', 'customer_auth', 'staff_session',
            'password_reset_token', 'integration_log'
        )
          AND (enabled OR payload_policy <> 'EXCLUDED')
    ) THEN
        RAISE EXCEPTION 'Credential-bearing sources are enabled for analytics';
    END IF;

    IF NOT fn_payload_has_forbidden_key(
        '{"employee_id":1,"name_ciphertext":"secret"}'::jsonb
    ) OR NOT fn_payload_has_forbidden_key(
        '{"employee_id":1,"email_masked":"a***@example.com"}'::jsonb
    ) OR NOT fn_payload_has_forbidden_key(
        '{"employee_id":1,"cpf_ciphertext":"secret"}'::jsonb
    ) OR NOT fn_payload_has_forbidden_key(
        '{"customer_id":1,"payload_ciphertext":"secret"}'::jsonb
    ) THEN
        RAISE EXCEPTION 'Encrypted or masked identity fields are not blocked from analytics';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mottainai_analytics_loader'
          AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mottainai_analytics_reader'
          AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
    ) THEN
        RAISE EXCEPTION 'Safe analytics roles are missing';
    END IF;

    RAISE NOTICE 'Daily batch structural tests passed';
END;
$$;

DO $$
DECLARE
    v_batch_id UUID;
    v_expected JSONB;
    v_staged BOOLEAN;
BEGIN
    BEGIN
        v_batch_id := fn_begin_daily_batch(
            (now() AT TIME ZONE 'America/Sao_Paulo')::date - 1,
            NULL,
            'contract-test-transaction',
            '{"test":true}'::jsonb
        );

        IF (SELECT (scheduled_at AT TIME ZONE 'America/Sao_Paulo')::TIME
            FROM etl_daily_batch WHERE batch_id = v_batch_id)
            <> TIME '02:00:00' THEN
            RAISE EXCEPTION 'Batch was not scheduled at 02:00 Sao Paulo time';
        END IF;

        v_staged := fn_stage_operational_row(
            v_batch_id,
            'company',
            'company_id=1',
            '{"company_id":1,"legal_name":"Contract Test","active":true}'::jsonb,
            1,
            NULL,
            now() - interval '2 days',
            now() - interval '1 day',
            NULL
        );

        IF NOT v_staged THEN
            RAISE EXCEPTION 'Safe company row was rejected';
        END IF;

        SELECT jsonb_object_agg(
            source_table,
            CASE WHEN source_table = 'company' THEN 1 ELSE 0 END
        )
        INTO v_expected
        FROM etl_source_contract
        WHERE enabled AND required;

        IF NOT fn_reconcile_daily_batch(v_batch_id, v_expected) THEN
            RAISE EXCEPTION 'Valid batch reconciliation failed';
        END IF;

        PERFORM fn_mark_daily_batch_transformed(
            v_batch_id, 1, '{"transform":"contract-test"}'::jsonb);
        PERFORM fn_publish_daily_batch(v_batch_id);

        IF NOT EXISTS (
            SELECT 1 FROM etl_daily_batch
            WHERE batch_id = v_batch_id
              AND status = 'PUBLISHED'
              AND expected_rows = 1
              AND staged_rows = 1
              AND rows_written = 1
        ) THEN
            RAISE EXCEPTION 'Daily batch was not published correctly';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM etl_table_checkpoint
            WHERE last_batch_id = v_batch_id
              AND source_table = 'company'
        ) THEN
            RAISE EXCEPTION 'Table checkpoint was not advanced after publication';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001', MESSAGE = 'rollback-daily-batch-contract-test';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'rollback-daily-batch-contract-test' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Daily batch lifecycle test passed';
END;
$$;

DO $$
DECLARE
    v_batch_id UUID;
    v_result BOOLEAN;
BEGIN
    BEGIN
        v_batch_id := fn_begin_daily_batch(
            (now() AT TIME ZONE 'America/Sao_Paulo')::date - 2,
            NULL,
            'privacy-contract-test',
            '{"test":true}'::jsonb
        );

        v_result := fn_stage_operational_row(
            v_batch_id,
            'customer',
            'customer_id=1',
            '{"customer_id":1,"cpf":"12345678901"}'::jsonb
        );

        IF v_result OR NOT EXISTS (
            SELECT 1 FROM etl_rejected_row WHERE batch_id = v_batch_id
        ) THEN
            RAISE EXCEPTION 'Sensitive customer payload was not rejected';
        END IF;

        IF EXISTS (
            SELECT 1 FROM stg_operational_row WHERE batch_id = v_batch_id
        ) THEN
            RAISE EXCEPTION 'Sensitive payload reached analytics staging';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001', MESSAGE = 'rollback-daily-batch-privacy-test';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'rollback-daily-batch-privacy-test' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Daily batch privacy test passed';
END;
$$;
COMMIT;


-- ============================================================================
-- MODULE: 15_operational_kpi_facts.sql
-- ============================================================================
-- Run against MOTTAINAI_ANALITICO after the base analytics schema is installed.
-- This migration only creates analytical facts/views. It does not read MOTTAINAI,
-- start a load, change source tables, or synthesize KPI values.
BEGIN;
SET LOCAL search_path TO mottainai_analytics, public;
DO $$
BEGIN
    IF current_database() IN ('MOTTAINAI', 'mottainai_operational', 'mottainai') THEN
        RAISE EXCEPTION 'Connect to MOTTAINAI_ANALITICO before applying BI fact migration';
    END IF;
    IF to_regclass('mottainai_analytics.fact_sales') IS NULL THEN
        RAISE EXCEPTION 'Base analytical schema is missing; install it before migration 15';
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS fact_inventory_count_line (
    inventory_count_item_id BIGINT PRIMARY KEY,
    inventory_count_id BIGINT NOT NULL,
    count_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    inventory_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    system_quantity NUMERIC(15,3) NOT NULL,
    counted_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    finished_at TIMESTAMPTZ,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (system_quantity >= 0 AND counted_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS fact_transfer_line (
    transfer_item_id BIGINT PRIMARY KEY,
    transfer_id BIGINT NOT NULL,
    request_date DATE NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    source_store_id BIGINT NOT NULL,
    destination_store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    status VARCHAR(30) NOT NULL,
    transferred_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (transferred_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_replenishment_plan_line (
    pre_list_item_id BIGINT PRIMARY KEY,
    pre_list_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL,
    suggested_quantity NUMERIC(15,3) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (suggested_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_replenishment_execution_line (
    execution_item_id BIGINT PRIMARY KEY,
    execution_id BIGINT NOT NULL,
    pre_list_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    replenished_quantity NUMERIC(15,3) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (replenished_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_donation_line (
    donation_item_id BIGINT PRIMARY KEY,
    donation_id BIGINT NOT NULL,
    donation_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    status VARCHAR(30) NOT NULL,
    donated_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (donated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_disposal_line (
    disposal_item_id BIGINT PRIMARY KEY,
    disposal_id BIGINT NOT NULL,
    disposal_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    disposed_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (disposed_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_alert_lifecycle (
    alert_id BIGINT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    alert_type VARCHAR(40) NOT NULL,
    priority VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ,
    source_updated_at TIMESTAMPTZ NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_action_lifecycle (
    suggested_action_id BIGINT PRIMARY KEY,
    alert_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    action_type VARCHAR(40) NOT NULL,
    status VARCHAR(30) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    source_recommendation_uuid UUID,
    source_updated_at TIMESTAMPTZ NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bi_count_store_date ON fact_inventory_count_line(store_id, count_date);
CREATE INDEX IF NOT EXISTS idx_bi_transfer_store_date ON fact_transfer_line(source_store_id, request_date);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_plan ON fact_replenishment_plan_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_execution ON fact_replenishment_execution_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_donation_store_date ON fact_donation_line(store_id, donation_date);
CREATE INDEX IF NOT EXISTS idx_bi_disposal_store_date ON fact_disposal_line(store_id, disposal_date);
CREATE INDEX IF NOT EXISTS idx_bi_action_alert ON fact_action_lifecycle(alert_id);

CREATE OR REPLACE VIEW vw_inventory_count_accuracy AS
SELECT count_date, store_id,
       count(*) AS counted_positions,
       count(*) FILTER (WHERE counted_quantity = system_quantity) AS matching_positions,
       round(count(*) FILTER (WHERE counted_quantity = system_quantity)::numeric / nullif(count(*), 0), 4) AS accuracy_rate,
       sum(abs(counted_quantity - system_quantity)) AS absolute_quantity_difference,
       CASE WHEN count(*) FILTER (WHERE unit_cost IS NULL) > 0 THEN NULL
            ELSE sum(abs(counted_quantity - system_quantity) * unit_cost) END AS absolute_difference_value,
       count(*) FILTER (WHERE unit_cost IS NULL) AS positions_without_cost
FROM fact_inventory_count_line
WHERE status = 'COMPLETED'
GROUP BY count_date, store_id;

COMMENT ON VIEW vw_inventory_count_accuracy IS
    'Accuracy among completed counted positions only; not inventory coverage or system-wide accuracy.';

CREATE OR REPLACE VIEW vw_transfer_execution AS
SELECT request_date, source_store_id, destination_store_id,
       count(DISTINCT transfer_id) AS transfers_with_items,
       count(DISTINCT transfer_id) FILTER (WHERE status = 'COMPLETED') AS completed_transfers,
       sum(transferred_quantity) AS requested_item_quantity,
       sum(transferred_quantity) FILTER (WHERE status = 'COMPLETED') AS completed_item_quantity,
       avg(extract(epoch FROM (completed_at - requested_at))/3600)
           FILTER (WHERE status = 'COMPLETED' AND completed_at IS NOT NULL) AS mean_completion_hours
FROM fact_transfer_line
GROUP BY request_date, source_store_id, destination_store_id;

COMMENT ON VIEW vw_transfer_execution IS
    'Measures transfer completion, not subsequent sale or avoided waste at destination.';

CREATE OR REPLACE VIEW vw_replenishment_fulfillment AS
WITH plan AS (
    SELECT pre_list_id, store_id, product_id, generated_at::date AS plan_date,
           max(status) AS plan_status, sum(suggested_quantity) AS suggested_quantity
    FROM fact_replenishment_plan_line
    GROUP BY pre_list_id, store_id, product_id, generated_at::date
), execution AS (
    SELECT pre_list_id, store_id, product_id,
           sum(replenished_quantity) FILTER (WHERE completed_at IS NOT NULL) AS completed_quantity,
           count(*) FILTER (WHERE completed_at IS NOT NULL) AS completed_lines
    FROM fact_replenishment_execution_line
    GROUP BY pre_list_id, store_id, product_id
)
SELECT p.pre_list_id, p.store_id, p.product_id, p.plan_date, p.plan_status,
       p.suggested_quantity, e.completed_quantity,
       CASE WHEN e.completed_lines > 0 THEN e.completed_quantity / nullif(p.suggested_quantity, 0)
            ELSE NULL END AS fulfillment_rate
FROM plan p LEFT JOIN execution e
  ON e.pre_list_id = p.pre_list_id AND e.store_id = p.store_id AND e.product_id = p.product_id;

COMMENT ON VIEW vw_replenishment_fulfillment IS
    'Only completed executions count as supplied; no execution produces NULL rate, not zero.';

CREATE OR REPLACE VIEW vw_product_destinations AS
SELECT 'DONATION'::text AS destination_type, donation_date AS event_date,
       store_id, product_id, batch_id, status, donated_quantity AS quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE donated_quantity * unit_cost END AS value_at_cost,
       suggested_action_id
FROM fact_donation_line
UNION ALL
SELECT 'DISPOSAL', disposal_date, store_id, product_id, batch_id,
       'REGISTERED', disposed_quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE disposed_quantity * unit_cost END,
       suggested_action_id
FROM fact_disposal_line;

COMMENT ON VIEW vw_product_destinations IS
    'Recorded dispositions at cost; donation counts as completed only with status COMPLETED. No avoided-loss claim.';

CREATE OR REPLACE VIEW vw_alert_action_funnel AS
SELECT a.generated_at::date AS alert_date, a.store_id,
       count(DISTINCT a.alert_id) AS alerts,
       count(DISTINCT a.alert_id) FILTER (WHERE a.status = 'RESOLVED') AS resolved_alerts,
       count(s.suggested_action_id) AS suggested_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'APPROVED') AS approved_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'EXECUTED') AS executed_actions
FROM fact_alert_lifecycle a
LEFT JOIN fact_action_lifecycle s ON s.alert_id = a.alert_id
GROUP BY a.generated_at::date, a.store_id;

COMMENT ON VIEW vw_alert_action_funnel IS
    'Current statuses by alert cohort; approval is not a historical transition and execution is not proven effective.';

COMMIT;

-- ============================================================================
-- MODULE: 16_partition_operational_kpi_facts.sql
-- ============================================================================
-- Convert the event facts from migration 15 to monthly range-partitioned tables.
-- Existing rows are copied transactionally. Late or out-of-window dates use a
-- DEFAULT partition, so the daily RPA does not fail on old or future events.
BEGIN;
SET LOCAL search_path TO mottainai_analytics, public;
SET LOCAL TIME ZONE 'UTC';

DO $$
BEGIN
    IF current_database() IN ('MOTTAINAI', 'mottainai_operational', 'mottainai') THEN
        RAISE EXCEPTION 'Connect to MOTTAINAI_ANALITICO before migration 16';
    END IF;
    IF to_regclass('mottainai_analytics.schema_version') IS NULL
       OR to_regclass('mottainai_analytics.fact_inventory_count_line') IS NULL THEN
        RAISE EXCEPTION 'Apply analytics base schema and migration 15 before migration 16';
    END IF;
END;
$$;

DO $$
DECLARE
    v_table TEXT;
    v_id_column TEXT;
    v_partition_column TEXT;
    v_new_table TEXT;
    v_old_table TEXT;
    v_relkind "char";
    v_month DATE;
    v_columns TEXT;
BEGIN
    FOR v_table, v_id_column, v_partition_column IN
        SELECT * FROM (VALUES
            ('fact_inventory_count_line', 'inventory_count_item_id', 'count_date'),
            ('fact_transfer_line', 'transfer_item_id', 'request_date'),
            ('fact_replenishment_plan_line', 'pre_list_item_id', 'generated_at'),
            ('fact_replenishment_execution_line', 'execution_item_id', 'started_at'),
            ('fact_donation_line', 'donation_item_id', 'donation_date'),
            ('fact_disposal_line', 'disposal_item_id', 'disposal_date'),
            ('fact_alert_lifecycle', 'alert_id', 'generated_at'),
            ('fact_action_lifecycle', 'suggested_action_id', 'generated_at')
        ) AS facts(table_name, id_column, partition_column)
    LOOP
        SELECT c.relkind INTO v_relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mottainai_analytics' AND c.relname = v_table;

        IF v_relkind = 'p' THEN
            CONTINUE;
        END IF;
        IF v_relkind IS DISTINCT FROM 'r' THEN
            RAISE EXCEPTION 'Expected ordinary table mottainai_analytics.% from migration 15', v_table;
        END IF;

        v_new_table := v_table || '__partitioned_16';
        v_old_table := v_table || '__before_partition_16';
        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_new_table)) IS NOT NULL
           OR to_regclass(format('%I.%I', 'mottainai_analytics', v_old_table)) IS NOT NULL THEN
            RAISE EXCEPTION 'Unexpected partial migration artifacts for %', v_table;
        END IF;

        EXECUTE format(
            'CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS '
            || 'INCLUDING GENERATED INCLUDING STORAGE INCLUDING COMMENTS) PARTITION BY RANGE (%I)',
            'mottainai_analytics', v_new_table,
            'mottainai_analytics', v_table,
            v_partition_column
        );
        EXECUTE format(
            'ALTER TABLE %I.%I ADD CONSTRAINT %I PRIMARY KEY (%I, %I)',
            'mottainai_analytics', v_new_table,
            v_new_table || '_pkey', v_id_column, v_partition_column
        );

        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - interval '12 months',
                date_trunc('month', current_date) + interval '6 months',
                interval '1 month'
            )::date
        LOOP
            EXECUTE format(
                'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                'mottainai_analytics', v_table || '_' || to_char(v_month, 'YYYY_MM'),
                'mottainai_analytics', v_new_table,
                v_month, (v_month + interval '1 month')::date
            );
        END LOOP;

        EXECUTE format(
            'CREATE TABLE %I.%I PARTITION OF %I.%I DEFAULT',
            'mottainai_analytics', v_table || '_default',
            'mottainai_analytics', v_new_table
        );

        SELECT string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum)
        INTO v_columns
        FROM pg_attribute a
        WHERE a.attrelid = format('%I.%I', 'mottainai_analytics', v_table)::regclass
          AND a.attnum > 0 AND NOT a.attisdropped;

        EXECUTE format(
            'INSERT INTO %I.%I (%s) SELECT %s FROM %I.%I',
            'mottainai_analytics', v_new_table, v_columns, v_columns,
            'mottainai_analytics', v_table
        );

        EXECUTE format('ALTER TABLE %I.%I RENAME TO %I',
            'mottainai_analytics', v_table, v_old_table);
        EXECUTE format('ALTER TABLE %I.%I RENAME TO %I',
            'mottainai_analytics', v_new_table, v_table);
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW vw_inventory_count_accuracy AS
SELECT count_date, store_id,
       count(*) AS counted_positions,
       count(*) FILTER (WHERE counted_quantity = system_quantity) AS matching_positions,
       round(count(*) FILTER (WHERE counted_quantity = system_quantity)::numeric / nullif(count(*), 0), 4) AS accuracy_rate,
       sum(abs(counted_quantity - system_quantity)) AS absolute_quantity_difference,
       CASE WHEN count(*) FILTER (WHERE unit_cost IS NULL) > 0 THEN NULL
            ELSE sum(abs(counted_quantity - system_quantity) * unit_cost) END AS absolute_difference_value,
       count(*) FILTER (WHERE unit_cost IS NULL) AS positions_without_cost
FROM fact_inventory_count_line
WHERE status = 'COMPLETED'
GROUP BY count_date, store_id;

CREATE OR REPLACE VIEW vw_transfer_execution AS
SELECT request_date, source_store_id, destination_store_id,
       count(DISTINCT transfer_id) AS transfers_with_items,
       count(DISTINCT transfer_id) FILTER (WHERE status = 'COMPLETED') AS completed_transfers,
       sum(transferred_quantity) AS requested_item_quantity,
       sum(transferred_quantity) FILTER (WHERE status = 'COMPLETED') AS completed_item_quantity,
       avg(extract(epoch FROM (completed_at - requested_at))/3600)
           FILTER (WHERE status = 'COMPLETED' AND completed_at IS NOT NULL) AS mean_completion_hours
FROM fact_transfer_line
GROUP BY request_date, source_store_id, destination_store_id;

CREATE OR REPLACE VIEW vw_replenishment_fulfillment AS
WITH plan AS (
    SELECT pre_list_id, store_id, product_id, generated_at::date AS plan_date,
           max(status) AS plan_status, sum(suggested_quantity) AS suggested_quantity
    FROM fact_replenishment_plan_line
    GROUP BY pre_list_id, store_id, product_id, generated_at::date
), execution AS (
    SELECT pre_list_id, store_id, product_id,
           sum(replenished_quantity) FILTER (WHERE completed_at IS NOT NULL) AS completed_quantity,
           count(*) FILTER (WHERE completed_at IS NOT NULL) AS completed_lines
    FROM fact_replenishment_execution_line
    GROUP BY pre_list_id, store_id, product_id
)
SELECT p.pre_list_id, p.store_id, p.product_id, p.plan_date, p.plan_status,
       p.suggested_quantity, e.completed_quantity,
       CASE WHEN e.completed_lines > 0 THEN e.completed_quantity / nullif(p.suggested_quantity, 0)
            ELSE NULL END AS fulfillment_rate
FROM plan p LEFT JOIN execution e
  ON e.pre_list_id = p.pre_list_id AND e.store_id = p.store_id AND e.product_id = p.product_id;

CREATE OR REPLACE VIEW vw_product_destinations AS
SELECT 'DONATION'::text AS destination_type, donation_date AS event_date,
       store_id, product_id, batch_id, status, donated_quantity AS quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE donated_quantity * unit_cost END AS value_at_cost,
       suggested_action_id
FROM fact_donation_line
UNION ALL
SELECT 'DISPOSAL', disposal_date, store_id, product_id, batch_id,
       'REGISTERED', disposed_quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE disposed_quantity * unit_cost END,
       suggested_action_id
FROM fact_disposal_line;

CREATE OR REPLACE VIEW vw_alert_action_funnel AS
SELECT a.generated_at::date AS alert_date, a.store_id,
       count(DISTINCT a.alert_id) AS alerts,
       count(DISTINCT a.alert_id) FILTER (WHERE a.status = 'RESOLVED') AS resolved_alerts,
       count(s.suggested_action_id) AS suggested_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'APPROVED') AS approved_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'EXECUTED') AS executed_actions
FROM fact_alert_lifecycle a
LEFT JOIN fact_action_lifecycle s ON s.alert_id = a.alert_id
GROUP BY a.generated_at::date, a.store_id;

COMMENT ON VIEW vw_inventory_count_accuracy IS
    'Accuracy among completed counted positions only; not inventory coverage or system-wide accuracy.';
COMMENT ON VIEW vw_transfer_execution IS
    'Measures transfer completion, not subsequent sale or avoided waste at destination.';
COMMENT ON VIEW vw_replenishment_fulfillment IS
    'Only completed executions count as supplied; no execution produces NULL rate, not zero.';
COMMENT ON VIEW vw_product_destinations IS
    'Recorded dispositions at cost; donation counts as completed only with status COMPLETED. No avoided-loss claim.';
COMMENT ON VIEW vw_alert_action_funnel IS
    'Current statuses by alert cohort; approval is not a historical transition and execution is not proven effective.';

-- Rebind dependencies after table replacement before removing the old table OIDs.
DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'fact_inventory_count_line', 'fact_transfer_line',
        'fact_replenishment_plan_line', 'fact_replenishment_execution_line',
        'fact_donation_line', 'fact_disposal_line',
        'fact_alert_lifecycle', 'fact_action_lifecycle'
    ]
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I.%I',
            'mottainai_analytics', v_table || '__before_partition_16');
    END LOOP;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_bi_count_store_date
    ON fact_inventory_count_line(store_id, count_date);
CREATE INDEX IF NOT EXISTS idx_bi_transfer_store_date
    ON fact_transfer_line(source_store_id, request_date);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_plan
    ON fact_replenishment_plan_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_execution
    ON fact_replenishment_execution_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_donation_store_date
    ON fact_donation_line(store_id, donation_date);
CREATE INDEX IF NOT EXISTS idx_bi_disposal_store_date
    ON fact_disposal_line(store_id, disposal_date);
CREATE INDEX IF NOT EXISTS idx_bi_action_alert
    ON fact_action_lifecycle(alert_id);

GRANT SELECT, INSERT, UPDATE ON
    fact_inventory_count_line, fact_transfer_line,
    fact_replenishment_plan_line, fact_replenishment_execution_line,
    fact_donation_line, fact_disposal_line,
    fact_alert_lifecycle, fact_action_lifecycle
TO mottainai_analytics_loader;
GRANT SELECT ON
    fact_inventory_count_line, fact_transfer_line,
    fact_replenishment_plan_line, fact_replenishment_execution_line,
    fact_donation_line, fact_disposal_line,
    fact_alert_lifecycle, fact_action_lifecycle,
    vw_inventory_count_accuracy, vw_transfer_execution,
    vw_replenishment_fulfillment, vw_product_destinations,
    vw_alert_action_funnel
TO mottainai_analytics_reader;

SELECT sp_create_monthly_fact_partitions(12, 6);

INSERT INTO schema_version (version, description)
VALUES
    (15, 'Operational KPI event facts and semantic views'),
    (16, 'Monthly partitioning for operational KPI event facts')
ON CONFLICT (version) DO UPDATE
SET description = EXCLUDED.description,
    applied_at = now();

COMMIT;
