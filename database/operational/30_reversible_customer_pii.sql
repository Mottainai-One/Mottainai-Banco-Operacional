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
        REFERENCES customer(customer_id) ON DELETE RESTRICT,
    payload_ciphertext  BYTEA NOT NULL,
    payload_nonce       BYTEA NOT NULL,
    key_version         SMALLINT NOT NULL,
    algorithm           VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    payload_format      VARCHAR(20) NOT NULL DEFAULT 'JSON_V1',
    encrypted_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at          TIMESTAMPTZ
);

-- Upgrade a table created from the preliminary ZIP migration without
-- rebuilding it or invalidating existing AES-GCM envelopes.
ALTER TABLE customer_private_data
    ADD COLUMN IF NOT EXISTS algorithm VARCHAR(20) NOT NULL DEFAULT 'AES-256-GCM',
    ADD COLUMN IF NOT EXISTS payload_format VARCHAR(20) NOT NULL DEFAULT 'JSON_V1',
    ADD COLUMN IF NOT EXISTS encrypted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- A logical deletion must keep the encrypted envelope. Replacing the old
-- cascading foreign key prevents a customer-row delete from destroying it.
ALTER TABLE customer_private_data
    DROP CONSTRAINT IF EXISTS customer_private_data_customer_id_fkey,
    DROP CONSTRAINT IF EXISTS fk_customer_private_data_customer;
ALTER TABLE customer_private_data
    ADD CONSTRAINT fk_customer_private_data_customer
        FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE RESTRICT;

-- Preserve existing envelopes for inactive customers while marking them as
-- logically unavailable through the normal application access paths.
UPDATE customer_private_data private_data
SET deleted_at = COALESCE(customer.deleted_at, CURRENT_TIMESTAMP)
FROM customer
WHERE customer.customer_id = private_data.customer_id
  AND private_data.deleted_at IS NULL
  AND (NOT customer.active OR customer.deleted_at IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_customer_private_data_active
    ON customer_private_data (customer_id)
    WHERE deleted_at IS NULL;

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
    USING (customer_id = fn_get_current_customer_id() AND deleted_at IS NULL);

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
    USING (customer_id = fn_get_current_customer_id() AND deleted_at IS NULL)
    WITH CHECK (customer_id = fn_get_current_customer_id() AND deleted_at IS NULL);

-- Staff access follows the existing employee_role.permission_level model.
-- Only active employees in Manager (80) or Administrator (100) roles can
-- retrieve an active customer's encrypted envelope, and only for customers
-- associated with their company through a non-deleted sale. The external
-- API/KMS decrypts it; PostgreSQL never stores or sees key material.
CREATE OR REPLACE FUNCTION fn_can_read_customer_private_data(p_customer_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_user u
        JOIN employee e ON e.employee_id = u.employee_id
        JOIN employee_role r ON r.role_id = e.role_id
        JOIN retail_store s ON s.store_id = e.store_id
        JOIN company c ON c.company_id = s.company_id
        JOIN customer cust ON cust.customer_id = p_customer_id
        WHERE u.user_id = fn_get_current_user_id()
          AND u.active AND e.active AND r.active AND s.active AND c.active
          AND u.deleted_at IS NULL
          AND e.deleted_at IS NULL
          AND r.deleted_at IS NULL
          AND s.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND cust.active AND cust.deleted_at IS NULL
          AND r.permission_level >= 80
          AND EXISTS (
              SELECT 1
              FROM sales_transaction sale
              JOIN retail_store sale_store ON sale_store.store_id = sale.store_id
              WHERE sale.customer_id = cust.customer_id
                AND sale.deleted_at IS NULL
                AND sale.status <> 'CANCELED'
                AND sale_store.company_id = fn_get_current_company_id()
                AND sale_store.active
                AND sale_store.deleted_at IS NULL
          )
    );
$$;

REVOKE ALL ON FUNCTION fn_can_read_customer_private_data(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_can_read_customer_private_data(INTEGER) TO mottainai_api;

CREATE OR REPLACE FUNCTION fn_customer_private_data_customer_is_inactive(
    p_customer_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM customer
        WHERE customer_id = p_customer_id
          AND (NOT active OR deleted_at IS NOT NULL)
    );
$$;

REVOKE ALL ON FUNCTION fn_customer_private_data_customer_is_inactive(INTEGER)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_customer_private_data_customer_is_inactive(INTEGER)
    TO mottainai_api, mottainai_customer_api;

DROP POLICY IF EXISTS customer_private_data_staff_select_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_staff_select_policy
    ON customer_private_data
    FOR SELECT TO mottainai_api
    USING (
        deleted_at IS NULL
        AND fn_can_read_customer_private_data(customer_id)
    );

DROP POLICY IF EXISTS customer_private_data_staff_soft_delete_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_staff_soft_delete_policy
    ON customer_private_data
    FOR UPDATE TO mottainai_api
    USING (
        deleted_at IS NULL
        AND fn_can_read_customer_private_data(customer_id)
    )
    WITH CHECK (
        deleted_at IS NOT NULL
        AND (
            fn_can_read_customer_private_data(customer_id)
            OR fn_customer_private_data_customer_is_inactive(customer_id)
        )
    );

-- Allows the lifecycle trigger to mark an envelope after the customer becomes
-- inactive. The application role can update only deleted_at, and the policy
-- permits this transition only when the parent customer is already inactive.
DROP POLICY IF EXISTS customer_private_data_lifecycle_soft_delete_policy
    ON customer_private_data;
CREATE POLICY customer_private_data_lifecycle_soft_delete_policy
    ON customer_private_data
    FOR UPDATE TO PUBLIC
    USING (
        deleted_at IS NULL
        AND fn_customer_private_data_customer_is_inactive(customer_id)
    )
    WITH CHECK (
        deleted_at IS NOT NULL
        AND fn_customer_private_data_customer_is_inactive(customer_id)
    );

CREATE OR REPLACE FUNCTION fn_trg_mark_customer_private_data_deleted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    IF (NOT NEW.active OR NEW.deleted_at IS NOT NULL)
       AND (OLD.active OR OLD.deleted_at IS NULL) THEN
        UPDATE customer_private_data
        SET deleted_at = COALESCE(NEW.deleted_at, CURRENT_TIMESTAMP)
        WHERE customer_id = NEW.customer_id
          AND deleted_at IS NULL;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_trg_mark_customer_private_data_deleted() FROM PUBLIC;
DROP TRIGGER IF EXISTS trg_mark_customer_private_data_deleted ON customer;
CREATE TRIGGER trg_mark_customer_private_data_deleted
AFTER UPDATE OF active, deleted_at ON customer
FOR EACH ROW EXECUTE FUNCTION fn_trg_mark_customer_private_data_deleted();

-- Revoke permissions possibly granted by the preliminary ZIP migration.
REVOKE ALL ON customer_private_data FROM PUBLIC;
REVOKE ALL ON customer_private_data FROM mottainai_api;
REVOKE ALL ON customer_private_data FROM mottainai_customer_api;
GRANT SELECT, INSERT, UPDATE ON customer_private_data
    TO mottainai_customer_api;
GRANT SELECT ON customer_private_data TO mottainai_api;
GRANT UPDATE (deleted_at) ON customer_private_data TO mottainai_api;

COMMENT ON TABLE customer_private_data IS
    'Customer-scoped AES-256-GCM envelope. Tokens remain in customer/customer_auth for lookup; encryption keys remain in external KMS.';
COMMENT ON COLUMN customer_private_data.payload_ciphertext IS
    'AES-256-GCM ciphertext including authentication tag for the JSON_V1 customer identity payload.';
COMMENT ON COLUMN customer_private_data.payload_nonce IS
    'Unique 96-bit nonce generated by the authorized encrypting service.';
COMMENT ON COLUMN customer_private_data.key_version IS
    'External KMS key version required for decryption and key rotation.';
COMMENT ON COLUMN customer_private_data.deleted_at IS
    'Logical erasure timestamp. The ciphertext is retained and remains encrypted; normal customer and staff reads are denied after this timestamp. Set automatically when the customer becomes inactive.';

INSERT INTO schema_version (
    version, description, type, script, installed_by
) VALUES (
    '30',
    'Add encrypted customer private data with logical deletion and permission-scoped staff reads',
    'SQL',
    '30_reversible_customer_pii.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
