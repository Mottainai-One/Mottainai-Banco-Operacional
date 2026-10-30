-- Idempotency receipts for POS writes and safe outbox replay.
BEGIN;

CREATE TABLE IF NOT EXISTS mottainai.pos_api_idempotency (
    store_id INTEGER NOT NULL
        REFERENCES mottainai.retail_store(store_id) ON DELETE RESTRICT,
    terminal_id INTEGER NOT NULL
        REFERENCES mottainai.pos_terminal(terminal_id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL,
    payload_hash TEXT NOT NULL CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
    entity_type VARCHAR(30) NOT NULL,
    entity_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (terminal_id, idempotency_key)
);

ALTER TABLE mottainai.pos_api_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.pos_api_idempotency FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pos_api_idempotency_store_scope
    ON mottainai.pos_api_idempotency;
CREATE POLICY pos_api_idempotency_store_scope
    ON mottainai.pos_api_idempotency
    FOR ALL TO mottainai_api
    USING (store_id = mottainai.fn_get_current_store_id())
    WITH CHECK (store_id = mottainai.fn_get_current_store_id());

REVOKE ALL ON mottainai.pos_api_idempotency FROM PUBLIC;
GRANT SELECT, INSERT ON mottainai.pos_api_idempotency TO mottainai_api;

COMMIT;
