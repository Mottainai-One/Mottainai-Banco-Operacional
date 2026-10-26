-- Encrypted customer payload expected by the Spring API model.
SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS customer_private_data (
    customer_id INTEGER PRIMARY KEY REFERENCES customer(customer_id) ON DELETE CASCADE,
    payload_ciphertext BYTEA NOT NULL,
    payload_nonce BYTEA NOT NULL,
    key_version SMALLINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_customer_private_nonce_size CHECK (octet_length(payload_nonce) = 12),
    CONSTRAINT ck_customer_private_ciphertext_size CHECK (octet_length(payload_ciphertext) >= 17),
    CONSTRAINT ck_customer_private_key_version CHECK (key_version > 0)
);

ALTER TABLE customer_private_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_private_data FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_private_data_self_policy ON customer_private_data;
CREATE POLICY customer_private_data_self_policy ON customer_private_data
    FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

REVOKE ALL ON customer_private_data FROM PUBLIC;
-- The staff API role can inspect the schema for Hibernate validation, but RLS
-- grants it no access to customer payload rows.
GRANT SELECT ON customer_private_data TO mottainai_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON customer_private_data TO mottainai_customer_api;

COMMENT ON TABLE customer_private_data IS
    'AES-256-GCM customer payload; key material remains outside PostgreSQL.';
