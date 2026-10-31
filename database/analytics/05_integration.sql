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
