-- ============================================================================
-- REVERSIBLE EMPLOYEE PII - PREPARATION PHASE
-- PostgreSQL 15+
--
-- PostgreSQL stores only an AES-256-GCM envelope produced by an authorized
-- backend/RPA. Encryption and HMAC keys must remain in a KMS or secret vault;
-- they are never accepted by, or stored in, this database.
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS employee_private_data (
    employee_id       INTEGER PRIMARY KEY
        REFERENCES employee(employee_id) ON DELETE CASCADE,

    name_ciphertext   BYTEA,
    name_nonce        BYTEA,
    name_token        VARCHAR(96),
    name_masked       VARCHAR(150),

    email_ciphertext  BYTEA,
    email_nonce       BYTEA,
    email_token       VARCHAR(96),
    email_masked      VARCHAR(150),

    phone_ciphertext  BYTEA,
    phone_nonce       BYTEA,
    phone_token       VARCHAR(96),
    phone_masked      VARCHAR(80),

    key_version       SMALLINT,
    algorithm         VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    protection_state  VARCHAR(20) NOT NULL DEFAULT 'LEGACY_TOKEN',
    encrypted_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_employee_private_algorithm
        CHECK (algorithm = 'AES-256-GCM'),
    CONSTRAINT ck_employee_private_state
        CHECK (protection_state IN ('LEGACY_TOKEN', 'ENCRYPTED')),
    CONSTRAINT ck_employee_private_key_version
        CHECK (key_version IS NULL OR key_version > 0),
    CONSTRAINT ck_employee_private_name_envelope
        CHECK ((name_ciphertext IS NULL) = (name_nonce IS NULL)),
    CONSTRAINT ck_employee_private_email_envelope
        CHECK ((email_ciphertext IS NULL) = (email_nonce IS NULL)),
    CONSTRAINT ck_employee_private_phone_envelope
        CHECK ((phone_ciphertext IS NULL) = (phone_nonce IS NULL)),
    CONSTRAINT ck_employee_private_nonce_size
        CHECK (
            (name_nonce IS NULL OR octet_length(name_nonce) = 12)
            AND (email_nonce IS NULL OR octet_length(email_nonce) = 12)
            AND (phone_nonce IS NULL OR octet_length(phone_nonce) = 12)
        ),
    CONSTRAINT ck_employee_private_ciphertext_size
        CHECK (
            (name_ciphertext IS NULL OR octet_length(name_ciphertext) >= 17)
            AND (email_ciphertext IS NULL OR octet_length(email_ciphertext) >= 17)
            AND (phone_ciphertext IS NULL OR octet_length(phone_ciphertext) >= 17)
        ),
    CONSTRAINT ck_employee_private_hmac_format
        CHECK (
            (name_token IS NULL OR name_token ~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$'
                OR fn_is_sha256_token(name_token, 'EMP'))
            AND (email_token IS NULL OR email_token ~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$'
                OR fn_is_sha256_token(email_token, 'EMAIL'))
            AND (phone_token IS NULL OR phone_token ~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$'
                OR fn_is_sha256_token(phone_token, 'PHONE'))
        ),
    CONSTRAINT ck_employee_private_encrypted_state
        CHECK (
            protection_state <> 'ENCRYPTED'
            OR (
                name_ciphertext IS NOT NULL
                AND name_token ~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$'
                AND key_version IS NOT NULL
                AND encrypted_at IS NOT NULL
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_employee_private_email_token
    ON employee_private_data(email_token)
    WHERE email_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_employee_private_phone_token
    ON employee_private_data(phone_token)
    WHERE phone_token IS NOT NULL;

-- Preserve the existing irreversible tokens during the transition. They are
-- lookup material only and cannot populate ciphertext. The RPA must replace
-- each row with a complete AES-GCM envelope before finalization.
DO $$
BEGIN
    -- After finalization these columns no longer exist. Keeping the copy
    -- dynamic makes the module safe to reapply without recreating legacy PII.
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'name'
    ) THEN
        EXECUTE $sql$
            INSERT INTO employee_private_data (
                employee_id,
                name_token,
                name_masked,
                email_token,
                email_masked,
                phone_token,
                phone_masked,
                protection_state
            )
            SELECT
                employee_id,
                name,
                'EMPLOYEE_' || employee_id,
                email,
                CASE WHEN email IS NULL THEN NULL ELSE '***@***' END,
                phone,
                CASE WHEN phone IS NULL THEN NULL ELSE '***********' END,
                'LEGACY_TOKEN'
            FROM employee
            ON CONFLICT (employee_id) DO NOTHING
        $sql$;
    END IF;
END;
$$;

ALTER TABLE employee_private_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_private_data FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_private_data_tenant_policy
    ON employee_private_data;
CREATE POLICY employee_private_data_tenant_policy
    ON employee_private_data
    FOR ALL TO mottainai_api
    USING (
        EXISTS (
            SELECT 1
            FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    );

DROP POLICY IF EXISTS employee_private_data_legacy_import_policy
    ON employee_private_data;
CREATE POLICY employee_private_data_legacy_import_policy
    ON employee_private_data
    FOR ALL TO mottainai_migrator
    USING (
        EXISTS (
            SELECT 1
            FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    );

REVOKE ALL ON employee_private_data FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON employee_private_data TO mottainai_api;
GRANT SELECT, INSERT, UPDATE ON employee_private_data TO mottainai_migrator;

COMMENT ON TABLE employee_private_data IS
    'Tenant-isolated AES-256-GCM envelopes, HMAC lookup tokens and masked display values for employee identity data.';
COMMENT ON COLUMN employee_private_data.name_ciphertext IS
    'AES-256-GCM ciphertext including the authentication tag; the key remains outside PostgreSQL.';
COMMENT ON COLUMN employee_private_data.name_nonce IS
    'Unique 96-bit AES-GCM nonce generated by the authorized encrypting service.';
COMMENT ON COLUMN employee_private_data.name_token IS
    'Versioned HMAC-SHA-256 blind index used for equality checks; never a raw SHA-256 of the name.';
COMMENT ON COLUMN employee_private_data.key_version IS
    'External KMS key version required to decrypt the envelope and rotate keys safely.';
