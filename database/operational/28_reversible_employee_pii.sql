-- ============================================================================
-- REVERSIBLE EMPLOYEE IDENTITY - PREPARATION PHASE
-- PostgreSQL 15+
--
-- PostgreSQL stores only AES-256-GCM envelopes produced by the backend/RPA.
-- Keys remain in KMS/secret vault and are never stored in this database.
-- CPF and email lookup HMACs remain in the employee row as non-reversible,
-- domain-separated fingerprints; raw values stay only in the AES-GCM envelope.
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

ALTER TABLE employee
    ADD COLUMN IF NOT EXISTS cpf_lookup_hmac BYTEA,
    ADD COLUMN IF NOT EXISTS email_lookup_hmac BYTEA;

CREATE UNIQUE INDEX IF NOT EXISTS uq_employee_cpf_lookup_hmac
    ON employee (cpf_lookup_hmac)
    WHERE cpf_lookup_hmac IS NOT NULL AND deleted_at IS NULL;

-- Keep the existing unique-email behavior without retaining readable email.
CREATE UNIQUE INDEX IF NOT EXISTS uq_employee_email_lookup_hmac
    ON employee (email_lookup_hmac)
    WHERE email_lookup_hmac IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS employee_private_data (
    employee_id       INTEGER PRIMARY KEY
        REFERENCES employee(employee_id) ON DELETE CASCADE,
    name_ciphertext   BYTEA,
    name_nonce        BYTEA,
    name_masked       VARCHAR(150),
    cpf_ciphertext    BYTEA,
    cpf_nonce         BYTEA,
    cpf_masked        VARCHAR(20),
    email_ciphertext  BYTEA,
    email_nonce       BYTEA,
    email_masked      VARCHAR(150),
    phone_ciphertext  BYTEA,
    phone_nonce       BYTEA,
    phone_masked      VARCHAR(80),
    key_version       SMALLINT,
    algorithm         VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    protection_state  VARCHAR(20) NOT NULL DEFAULT 'MIGRATION_PENDING',
    encrypted_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Upgrade installations that already ran the previous HMAC-based draft.
ALTER TABLE employee_private_data
    ADD COLUMN IF NOT EXISTS cpf_ciphertext BYTEA,
    ADD COLUMN IF NOT EXISTS cpf_nonce BYTEA,
    ADD COLUMN IF NOT EXISTS cpf_masked VARCHAR(20);

DROP INDEX IF EXISTS uq_employee_private_email_token;
DROP INDEX IF EXISTS idx_employee_private_email_token;
DROP INDEX IF EXISTS idx_employee_private_phone_token;

ALTER TABLE employee_private_data
    DROP CONSTRAINT IF EXISTS ck_employee_private_algorithm,
    DROP CONSTRAINT IF EXISTS ck_employee_private_state,
    DROP CONSTRAINT IF EXISTS ck_employee_private_key_version,
    DROP CONSTRAINT IF EXISTS ck_employee_private_name_envelope,
    DROP CONSTRAINT IF EXISTS ck_employee_private_cpf_envelope,
    DROP CONSTRAINT IF EXISTS ck_employee_private_email_envelope,
    DROP CONSTRAINT IF EXISTS ck_employee_private_phone_envelope,
    DROP CONSTRAINT IF EXISTS ck_employee_private_nonce_size,
    DROP CONSTRAINT IF EXISTS ck_employee_private_ciphertext_size,
    DROP CONSTRAINT IF EXISTS ck_employee_private_hmac_format,
    DROP CONSTRAINT IF EXISTS ck_employee_private_encrypted_state;

ALTER TABLE employee_private_data
    DROP COLUMN IF EXISTS name_token,
    DROP COLUMN IF EXISTS email_token,
    DROP COLUMN IF EXISTS phone_token;

-- A row created by the former draft is not complete until CPF is encrypted.
UPDATE employee_private_data
SET protection_state = 'MIGRATION_PENDING'
WHERE protection_state = 'ENCRYPTED'
  AND (name_ciphertext IS NULL OR name_nonce IS NULL
       OR cpf_ciphertext IS NULL OR cpf_nonce IS NULL);

UPDATE employee_private_data
SET protection_state = 'MIGRATION_PENDING'
WHERE protection_state = 'LEGACY_TOKEN';

ALTER TABLE employee_private_data
    ALTER COLUMN protection_state SET DEFAULT 'MIGRATION_PENDING';

ALTER TABLE employee_private_data
    ADD CONSTRAINT ck_employee_private_algorithm
        CHECK (algorithm = 'AES-256-GCM'),
    ADD CONSTRAINT ck_employee_private_state
        CHECK (protection_state IN ('MIGRATION_PENDING', 'ENCRYPTED')),
    ADD CONSTRAINT ck_employee_private_key_version
        CHECK (key_version IS NULL OR key_version > 0),
    ADD CONSTRAINT ck_employee_private_name_envelope
        CHECK ((name_ciphertext IS NULL) = (name_nonce IS NULL)),
    ADD CONSTRAINT ck_employee_private_cpf_envelope
        CHECK ((cpf_ciphertext IS NULL) = (cpf_nonce IS NULL)),
    ADD CONSTRAINT ck_employee_private_email_envelope
        CHECK ((email_ciphertext IS NULL) = (email_nonce IS NULL)),
    ADD CONSTRAINT ck_employee_private_phone_envelope
        CHECK ((phone_ciphertext IS NULL) = (phone_nonce IS NULL)),
    ADD CONSTRAINT ck_employee_private_nonce_size
        CHECK (
            (name_nonce IS NULL OR octet_length(name_nonce) = 12)
            AND (cpf_nonce IS NULL OR octet_length(cpf_nonce) = 12)
            AND (email_nonce IS NULL OR octet_length(email_nonce) = 12)
            AND (phone_nonce IS NULL OR octet_length(phone_nonce) = 12)
        ),
    ADD CONSTRAINT ck_employee_private_ciphertext_size
        CHECK (
            (name_ciphertext IS NULL OR octet_length(name_ciphertext) >= 17)
            AND (cpf_ciphertext IS NULL OR octet_length(cpf_ciphertext) >= 17)
            AND (email_ciphertext IS NULL OR octet_length(email_ciphertext) >= 17)
            AND (phone_ciphertext IS NULL OR octet_length(phone_ciphertext) >= 17)
        ),
    ADD CONSTRAINT ck_employee_private_encrypted_state
        CHECK (
            protection_state <> 'ENCRYPTED'
            OR (
                name_ciphertext IS NOT NULL
                AND cpf_ciphertext IS NOT NULL
                AND key_version IS NOT NULL
                AND encrypted_at IS NOT NULL
            )
        );

-- Legacy irreversible values cannot become ciphertext. Create only a migration
-- placeholder; the backend/RPA must replace it with valid AES-GCM envelopes.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'name'
    ) THEN
        EXECUTE $sql$
            INSERT INTO employee_private_data (
                employee_id, name_masked, cpf_masked, email_masked,
                phone_masked, protection_state
            )
            SELECT employee_id,
                   'EMPLOYEE_' || employee_id,
                   CASE WHEN cpf IS NULL THEN NULL ELSE '***.***.***-**' END,
                   CASE WHEN email IS NULL THEN NULL ELSE '***@***' END,
                   CASE WHEN phone IS NULL THEN NULL ELSE '***********' END,
                   'MIGRATION_PENDING'
            FROM employee
            ON CONFLICT (employee_id) DO NOTHING
        $sql$;
    END IF;
END;
$$;

ALTER TABLE employee_private_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_private_data FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_private_data_tenant_policy ON employee_private_data;
CREATE POLICY employee_private_data_tenant_policy
    ON employee_private_data FOR ALL TO mottainai_api
    USING (
        EXISTS (
            SELECT 1 FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    );

DROP POLICY IF EXISTS employee_private_data_legacy_import_policy ON employee_private_data;
CREATE POLICY employee_private_data_legacy_import_policy
    ON employee_private_data FOR ALL TO mottainai_migrator
    USING (
        EXISTS (
            SELECT 1 FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM employee
            JOIN retail_store USING (store_id)
            WHERE employee.employee_id = employee_private_data.employee_id
              AND retail_store.company_id = fn_get_current_company_id()
        )
    );

REVOKE ALL ON employee_private_data FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON employee_private_data TO mottainai_api;
GRANT SELECT, INSERT, UPDATE ON employee_private_data TO mottainai_migrator;

COMMENT ON TABLE employee_private_data IS
    'Tenant-isolated AES-256-GCM envelopes and masked display values for employee name, CPF, email and phone. No HMAC tokens are stored.';
COMMENT ON COLUMN employee_private_data.key_version IS
    'External KMS key version used to decrypt and rotate the envelopes.';
