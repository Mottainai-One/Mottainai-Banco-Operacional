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
