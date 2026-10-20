-- ============================================================================
-- REVERSIBLE CUSTOMER PRIVATE DATA
-- PostgreSQL 15+
--
-- The customer registry keeps deterministic tokens for equality lookups.
-- Original values may be recovered only from this AES-256-GCM envelope by an
-- authorized application holding the external KMS key. Key material and raw
-- personal values are never accepted by PostgreSQL functions or stored here.
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS customer_private_data (
    customer_id         INTEGER PRIMARY KEY
        REFERENCES customer(customer_id) ON DELETE CASCADE,
    payload_ciphertext  BYTEA NOT NULL,
    payload_nonce       BYTEA NOT NULL,
    key_version         SMALLINT NOT NULL,
    algorithm           VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    payload_format      VARCHAR(20) NOT NULL DEFAULT 'JSON_V1',
    encrypted_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Upgrade a table created from the preliminary ZIP migration without
-- rebuilding it or invalidating existing AES-GCM envelopes.
ALTER TABLE customer_private_data
    ADD COLUMN IF NOT EXISTS algorithm VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    ADD COLUMN IF NOT EXISTS payload_format VARCHAR(20) NOT NULL DEFAULT 'JSON_V1',
    ADD COLUMN IF NOT EXISTS encrypted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE customer_private_data
    DROP CONSTRAINT IF EXISTS customer_private_data_payload_ciphertext_check,
    DROP CONSTRAINT IF EXISTS customer_private_data_payload_nonce_check,
    DROP CONSTRAINT IF EXISTS customer_private_data_key_version_check,
    DROP CONSTRAINT IF EXISTS ck_customer_private_ciphertext_size,
    DROP CONSTRAINT IF EXISTS ck_customer_private_nonce_size,
    DROP CONSTRAINT IF EXISTS ck_customer_private_key_version,
    DROP CONSTRAINT IF EXISTS ck_customer_private_algorithm,
    DROP CONSTRAINT IF EXISTS ck_customer_private_payload_format;

ALTER TABLE customer_private_data
    ADD CONSTRAINT ck_customer_private_ciphertext_size
        CHECK (octet_length(payload_ciphertext) >= 17),
    ADD CONSTRAINT ck_customer_private_nonce_size
        CHECK (octet_length(payload_nonce) = 12),
    ADD CONSTRAINT ck_customer_private_key_version
        CHECK (key_version > 0),
    ADD CONSTRAINT ck_customer_private_algorithm
        CHECK (algorithm = 'AES-256-GCM'),
    ADD CONSTRAINT ck_customer_private_payload_format
        CHECK (payload_format = 'JSON_V1');

-- Keep encrypted envelopes and nonces out of audit and technical logs even
-- when this module is applied by itself to an existing installation.
CREATE OR REPLACE FUNCTION fn_sanitize_audit_json(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_data IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(p_data) = 'object' THEN
        SELECT jsonb_object_agg(entry.key,
            CASE
                WHEN lower(entry.key) = ANY (ARRAY[
                    'password', 'password_hash', 'token', 'token_hash',
                    'refresh_token', 'refresh_token_hash', 'recovery_token_hash',
                    'cpf', 'customer_document', 'email', 'login_email', 'phone',
                    'full_name', 'birth_date', 'external_auth_uid', 'address_token',
                    'payload_ciphertext', 'payload_nonce',
                    'name_ciphertext', 'name_nonce', 'cpf_ciphertext', 'cpf_nonce',
                    'email_ciphertext', 'email_nonce', 'phone_ciphertext', 'phone_nonce'
                ]) THEN '"[REDACTED]"'::JSONB
                ELSE fn_sanitize_audit_json(entry.value)
            END)
        INTO v_result
        FROM jsonb_each(p_data) AS entry;
        RETURN COALESCE(v_result, '{}'::JSONB);
    END IF;

    IF jsonb_typeof(p_data) = 'array' THEN
        SELECT jsonb_agg(fn_sanitize_audit_json(item.value))
        INTO v_result
        FROM jsonb_array_elements(p_data) AS item;
        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    RETURN p_data;
END;
$$;

REVOKE ALL ON FUNCTION fn_sanitize_audit_json(JSONB) FROM PUBLIC;

CREATE OR REPLACE FUNCTION fn_trg_touch_customer_private_data()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_trg_touch_customer_private_data() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_touch_customer_private_data
    ON customer_private_data;
CREATE TRIGGER trg_touch_customer_private_data
BEFORE UPDATE ON customer_private_data
FOR EACH ROW EXECUTE FUNCTION fn_trg_touch_customer_private_data();

DROP TRIGGER IF EXISTS trg_audit_customer_private_data
    ON customer_private_data;
CREATE TRIGGER trg_audit_customer_private_data
AFTER INSERT OR UPDATE OR DELETE ON customer_private_data
FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('customer_id');

ALTER TABLE customer_private_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_private_data FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_private_data_select_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_select_policy
    ON customer_private_data
    FOR SELECT TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id());

DROP POLICY IF EXISTS customer_private_data_insert_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_insert_policy
    ON customer_private_data
    FOR INSERT TO mottainai_customer_api
    WITH CHECK (customer_id = fn_get_current_customer_id());

DROP POLICY IF EXISTS customer_private_data_update_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_update_policy
    ON customer_private_data
    FOR UPDATE TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

-- Revoke permissions possibly granted by the preliminary ZIP migration.
REVOKE ALL ON customer_private_data FROM PUBLIC;
REVOKE ALL ON customer_private_data FROM mottainai_api;
REVOKE ALL ON customer_private_data FROM mottainai_customer_api;
GRANT SELECT, INSERT, UPDATE ON customer_private_data
    TO mottainai_customer_api;

COMMENT ON TABLE customer_private_data IS
    'Customer-scoped AES-256-GCM envelope. Tokens remain in customer/customer_auth for lookup; encryption keys remain in external KMS.';
COMMENT ON COLUMN customer_private_data.payload_ciphertext IS
    'AES-256-GCM ciphertext including authentication tag for the JSON_V1 customer identity payload.';
COMMENT ON COLUMN customer_private_data.payload_nonce IS
    'Unique 96-bit nonce generated by the authorized encrypting service.';
COMMENT ON COLUMN customer_private_data.key_version IS
    'External KMS key version required for decryption and key rotation.';

INSERT INTO schema_version (
    version, description, type, script, installed_by
) VALUES (
    '30',
    'Add tenant-isolated reversible customer private-data envelope',
    'SQL',
    '30_reversible_customer_pii.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
