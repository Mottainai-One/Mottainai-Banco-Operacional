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
