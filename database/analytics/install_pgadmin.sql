-- Instalador para pgAdmin Query Tool. Conecte-se ao banco MOTTAINAI_ANALITICO antes de executar.
-- Gerado a partir de install.sql; nao execute no banco MOTTAINAI.
BEGIN;

-- ===== 00_database.sql =====
-- Execute conectado ao banco mottainai_analytics.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
COMMENT ON SCHEMA mottainai_analytics IS
    'Banco analitico: historico, indicadores, recomendacoes de IA e controle de ingestao.';

SET search_path TO mottainai_analytics, public;


-- ===== 01_types.sql =====
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


-- ===== 02_dimensions.sql =====
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


-- ===== 03_facts.sql =====
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


-- ===== 03_monthly_partitions.sql =====
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
    v_partition_name TEXT;
    v_tables CONSTANT TEXT[] := ARRAY[
        'fact_sales',
        'fact_sale_item',
        'fact_inventory_movement',
        'fact_inventory_snapshot'
    ];
BEGIN
    IF p_months_back < 0 OR p_months_ahead < 0 THEN
        RAISE EXCEPTION 'Partition month ranges cannot be negative';
    END IF;

    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - make_interval(months => p_months_back),
                date_trunc('month', current_date) + make_interval(months => p_months_ahead),
                interval '1 month'
            )::date
        LOOP
            v_partition_name := v_table || '_' || to_char(v_month, 'YYYY_MM');

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
$$ LANGUAGE plpgsql;

SELECT sp_create_monthly_fact_partitions(12, 6);


-- ===== 04_ai.sql =====
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


-- ===== 05_integration.sql =====
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


-- ===== 06_indexes.sql =====
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


-- ===== 07_views.sql =====
SET search_path TO mottainai_analytics, public;

-- Reference date remains fixed until the next successful publication.
CREATE OR REPLACE VIEW vw_published_batch AS
SELECT job_id, started_at AS source_cutoff_at,
       (started_at AT TIME ZONE 'America/Sao_Paulo')::date AS snapshot_date
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
    expiration_date
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


-- ===== 08_seed.sql =====
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


-- ===== 10_dashboard.sql =====
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


-- ===== 11_priority_views.sql =====
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


-- ===== 09_tests.sql =====
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

COMMIT;