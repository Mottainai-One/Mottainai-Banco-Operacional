-- ============================================================================
-- SENSITIVE DATA CONTRACT
-- PostgreSQL 15+
--
-- The operational database stores only values already treated by the source
-- backend. SHA-256 tokens are prefixed by their semantic type. Passwords and
-- low-entropy recovery codes use BCrypt. The database never receives keys and
-- must not be used as an encryption/decryption service.
-- ============================================================================

SET search_path TO mottainai, public;

CREATE OR REPLACE FUNCTION fn_is_sha256_token(p_value TEXT, p_prefix TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~ ('^' || p_prefix || '_SHA256_[A-Fa-f0-9]{64}$');
$$;

CREATE OR REPLACE FUNCTION fn_is_bcrypt_hash(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~ '^\$2[aby]\$[0-3][0-9]\$[./A-Za-z0-9]{53}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_legacy_masked_email(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~* '^EMAIL_[A-Z]+_[0-9]+$'
        OR p_value ~* '^USER_[0-9]+$'
        OR p_value ~ '^[A-Za-z0-9._%+-]*\*{3}@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_legacy_masked_phone(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~* '^PHONE_[A-Z]+_[0-9]+$'
        OR p_value ~ '^\([0-9]{2}\) 9\*{4}-[0-9]{4}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_email(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT mottainai.fn_is_sha256_token(p_value, 'EMAIL')
        OR mottainai.fn_is_legacy_masked_email(p_value);
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_phone(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT mottainai.fn_is_sha256_token(p_value, 'PHONE')
        OR mottainai.fn_is_legacy_masked_phone(p_value);
$$;

REVOKE ALL ON FUNCTION fn_is_sha256_token(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_bcrypt_hash(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_legacy_masked_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_legacy_masked_phone(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_phone(TEXT) FROM PUBLIC;

-- Remove plaintext-oriented validation before widening protected columns.
ALTER TABLE company DROP CONSTRAINT IF EXISTS company_email_check;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS retail_store_email_check;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS supplier_email_check;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_cpf_check;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_cpf_key;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_email_check;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS app_user_email_check;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS app_user_email_key;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_cpf_valid;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_cpf;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_cpf_check;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_cpf_key;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_email_check;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_external_auth_uid_key;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS customer_auth_login_email_check;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS customer_auth_login_email_key;
ALTER TABLE sales_transaction DROP CONSTRAINT IF EXISTS sales_transaction_customer_document_check;
ALTER TABLE company DROP CONSTRAINT IF EXISTS ck_company_email_protected;
ALTER TABLE company DROP CONSTRAINT IF EXISTS ck_company_phone_protected;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS ck_store_email_protected;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS ck_store_phone_protected;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS ck_supplier_email_protected;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS ck_supplier_phone_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS uq_employee_cpf_token;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_name_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_cpf_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_email_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_phone_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_email_token;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_cpf_token;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_email_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_cpf_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_password_bcrypt;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS uq_customer_cpf_token;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS uq_customer_external_auth_token;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_name_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_cpf_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_email_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_phone_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_external_auth_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_birth_year_minimized;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_address_not_linked;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_address_token_protected;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS uq_customer_auth_login_token;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_login_protected;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_password_bcrypt;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_recovery_bcrypt;
ALTER TABLE sales_transaction DROP CONSTRAINT IF EXISTS ck_sales_customer_document_protected;
ALTER TABLE staff_session DROP CONSTRAINT IF EXISTS ck_staff_session_refresh_sha256;
ALTER TABLE password_reset_token DROP CONSTRAINT IF EXISTS ck_password_reset_hash_algorithm;

DROP TRIGGER IF EXISTS trg_sync_app_user_cpf ON app_user;
DROP TRIGGER IF EXISTS trg_propagate_employee_cpf ON employee;

-- A database that already received module 38 has mobile-owner policies whose
-- expressions depend on the protected customer/auth columns below. PostgreSQL
-- does not allow ALTER TYPE while such policies exist. The consolidated updater
-- reapplies module 38 in the same transaction, so remove only those policies
-- before normalizing the column types.
DROP POLICY IF EXISTS client_api_customer_select ON customer;
DROP POLICY IF EXISTS client_profile_owner_customer_select ON customer;
DROP POLICY IF EXISTS client_profile_owner_customer_insert ON customer;
DROP POLICY IF EXISTS client_profile_owner_customer_update ON customer;
DROP POLICY IF EXISTS client_auth_owner_customer_select ON customer;
DROP POLICY IF EXISTS client_profile_owner_auth_select ON customer_auth;
DROP POLICY IF EXISTS client_auth_owner_auth_select ON customer_auth;
DROP POLICY IF EXISTS client_auth_owner_auth_update ON customer_auth;

ALTER TABLE company ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE retail_store ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE supplier ALTER COLUMN phone TYPE VARCHAR(80);
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'employee' AND column_name = 'cpf') THEN
        EXECUTE 'ALTER TABLE employee ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'app_user' AND column_name = 'cpf') THEN
        EXECUTE 'ALTER TABLE app_user ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf)';
    END IF;
END $$;
ALTER TABLE customer ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf);
ALTER TABLE customer ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE customer_auth ALTER COLUMN login_email TYPE VARCHAR(150);
ALTER TABLE sales_transaction
    ALTER COLUMN customer_document TYPE VARCHAR(80) USING btrim(customer_document);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'phone'
    ) THEN
        EXECUTE 'ALTER TABLE employee ALTER COLUMN phone TYPE VARCHAR(80)';
    END IF;
END;
$$;

-- Existing clear values are irreversibly converted once. New writes must
-- arrive protected by the backend before reaching PostgreSQL.
UPDATE company
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE NOT fn_is_protected_email(email);

UPDATE company
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE retail_store
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_protected_email(email);

UPDATE retail_store
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE supplier
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_protected_email(email);

UPDATE supplier
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'name'
    ) THEN
        EXECUTE $sql$
            UPDATE employee
            SET name = 'EMP_SHA256_' || upper(encode(digest(btrim(name), 'sha256'), 'hex'))
            WHERE name !~ '^EMP_[0-9]+$'
              AND NOT fn_is_sha256_token(name, 'EMP')
        $sql$;
    END IF;
END;
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'employee' AND column_name = 'cpf') THEN
        EXECUTE $sql$
            UPDATE employee
            SET cpf = 'CPF_SHA256_' || upper(encode(digest(regexp_replace(cpf, '\D', '', 'g'), 'sha256'), 'hex'))
            WHERE cpf !~ '^CPF_TKN_[A-Fa-f0-9]{6}$'
              AND NOT fn_is_sha256_token(cpf, 'CPF')
        $sql$;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'email'
    ) THEN
        EXECUTE $sql$
            UPDATE employee
            SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
            WHERE email IS NOT NULL AND NOT fn_is_protected_email(email)
        $sql$;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'phone'
    ) THEN
        EXECUTE $sql$
            UPDATE employee
            SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
            WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone)
        $sql$;
    END IF;
END;
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'employee' AND column_name = 'cpf')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'app_user' AND column_name = 'cpf') THEN
        EXECUTE 'UPDATE app_user app SET cpf = employee.cpf FROM employee '
             || 'WHERE employee.employee_id = app.employee_id '
             || 'AND app.cpf IS DISTINCT FROM employee.cpf';
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'app_user'
          AND column_name = 'email'
    ) THEN
        EXECUTE $sql$
            UPDATE app_user
            SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
            WHERE NOT fn_is_protected_email(email)
        $sql$;
    END IF;
END;
$$;

ALTER TABLE customer
    ADD COLUMN IF NOT EXISTS birth_year SMALLINT,
    ADD COLUMN IF NOT EXISTS address_token VARCHAR(80),
    ADD COLUMN IF NOT EXISTS data_protection_version SMALLINT NOT NULL DEFAULT 1;

UPDATE customer
SET full_name = 'CUS_SHA256_' || upper(encode(digest(btrim(full_name), 'sha256'), 'hex'))
WHERE NOT fn_is_sha256_token(full_name, 'CUS');

UPDATE customer
SET cpf = 'CPF_SHA256_' || upper(encode(digest(regexp_replace(cpf, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE cpf IS NOT NULL AND NOT fn_is_sha256_token(cpf, 'CPF');

UPDATE customer
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_sha256_token(email, 'EMAIL');

UPDATE customer
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_sha256_token(phone, 'PHONE');

UPDATE customer
SET external_auth_uid = 'AUTH_SHA256_' || upper(encode(digest(btrim(external_auth_uid), 'sha256'), 'hex'))
WHERE external_auth_uid IS NOT NULL
  AND NOT fn_is_sha256_token(external_auth_uid, 'AUTH');

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'customer'
          AND column_name = 'birth_date'
    ) THEN
        EXECUTE 'UPDATE customer '
            || 'SET birth_year = EXTRACT(YEAR FROM birth_date)::SMALLINT '
            || 'WHERE birth_date IS NOT NULL AND birth_year IS NULL';
    END IF;
END;
$$;

UPDATE customer customer_record
SET address_token = 'ADDR_SHA256_' || upper(encode(digest(concat_ws('|',
        address.zip_code,
        address.street,
        address.number,
        address.complement,
        address.neighborhood,
        address.city,
        address.state
    ), 'sha256'), 'hex')),
    address_id = NULL
FROM address
WHERE address.address_id = customer_record.address_id;

ALTER TABLE customer DROP COLUMN IF EXISTS birth_date;

UPDATE customer_auth
SET login_email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(login_email)), 'sha256'), 'hex'))
WHERE NOT fn_is_sha256_token(login_email, 'EMAIL');

UPDATE sales_transaction
SET customer_document = 'DOC_SHA256_' || upper(encode(digest(regexp_replace(customer_document, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE customer_document IS NOT NULL
  AND NOT fn_is_sha256_token(customer_document, 'DOC');

-- Legacy-only synchronization. It is skipped after module 29 removes the
-- duplicated CPF columns in favor of employee_private_data.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'employee' AND column_name = 'cpf')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'app_user' AND column_name = 'cpf') THEN
        EXECUTE $fn$
            CREATE OR REPLACE FUNCTION fn_sync_app_user_cpf()
            RETURNS TRIGGER LANGUAGE plpgsql SET search_path = mottainai, pg_temp
            AS $body$
            DECLARE v_employee_cpf VARCHAR(80);
            BEGIN
                SELECT cpf INTO v_employee_cpf FROM mottainai.employee
                WHERE employee_id = NEW.employee_id;
                IF v_employee_cpf IS NULL THEN
                    RAISE EXCEPTION 'Employee % does not exist or has no protected CPF token', NEW.employee_id;
                END IF;
                IF TG_OP = 'INSERT' AND NEW.cpf IS NULL THEN
                    NEW.cpf := v_employee_cpf;
                ELSIF NEW.cpf IS DISTINCT FROM v_employee_cpf THEN
                    RAISE EXCEPTION 'app_user.cpf must match the protected employee CPF token';
                END IF;
                RETURN NEW;
            END $body$
        $fn$;
        EXECUTE 'CREATE TRIGGER trg_sync_app_user_cpf BEFORE INSERT OR UPDATE OF employee_id, cpf '
             || 'ON app_user FOR EACH ROW EXECUTE FUNCTION fn_sync_app_user_cpf()';
        EXECUTE 'CREATE TRIGGER trg_propagate_employee_cpf AFTER UPDATE OF cpf ON employee '
             || 'FOR EACH ROW WHEN (OLD.cpf IS DISTINCT FROM NEW.cpf) '
             || 'EXECUTE FUNCTION fn_propagate_employee_cpf()';
    END IF;
END $$;

ALTER TABLE company ADD CONSTRAINT ck_company_email_protected
    CHECK (fn_is_protected_email(email));
ALTER TABLE company ADD CONSTRAINT ck_company_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));
ALTER TABLE retail_store ADD CONSTRAINT ck_store_email_protected
    CHECK (email IS NULL OR fn_is_protected_email(email));
ALTER TABLE retail_store ADD CONSTRAINT ck_store_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));
ALTER TABLE supplier ADD CONSTRAINT ck_supplier_email_protected
    CHECK (email IS NULL OR fn_is_protected_email(email));
ALTER TABLE supplier ADD CONSTRAINT ck_supplier_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'employee' AND column_name = 'cpf') THEN
        ALTER TABLE employee ADD CONSTRAINT uq_employee_cpf_token UNIQUE (cpf);
        ALTER TABLE employee ADD CONSTRAINT ck_employee_cpf_protected
            CHECK (cpf ~ '^CPF_TKN_[A-Fa-f0-9]{6}$' OR fn_is_sha256_token(cpf, 'CPF'));
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'mottainai' AND table_name = 'app_user' AND column_name = 'cpf') THEN
        ALTER TABLE app_user ADD CONSTRAINT uq_app_user_cpf_token UNIQUE (cpf);
        ALTER TABLE app_user ADD CONSTRAINT ck_app_user_cpf_protected
            CHECK (cpf ~ '^CPF_TKN_[A-Fa-f0-9]{6}$' OR fn_is_sha256_token(cpf, 'CPF'));
    END IF;
END $$;
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_password_bcrypt
    CHECK (fn_is_bcrypt_hash(password_hash));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'name'
    ) THEN
        ALTER TABLE employee ADD CONSTRAINT ck_employee_name_protected
            CHECK (name ~ '^EMP_[0-9]+$' OR fn_is_sha256_token(name, 'EMP'));
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'email'
    ) THEN
        ALTER TABLE employee ADD CONSTRAINT ck_employee_email_protected
            CHECK (email IS NULL OR fn_is_protected_email(email));
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'phone'
    ) THEN
        ALTER TABLE employee ADD CONSTRAINT ck_employee_phone_protected
            CHECK (phone IS NULL OR fn_is_protected_phone(phone));
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'app_user'
          AND column_name = 'email'
    ) THEN
        ALTER TABLE app_user ADD CONSTRAINT uq_app_user_email_token UNIQUE (email);
        ALTER TABLE app_user ADD CONSTRAINT ck_app_user_email_protected
            CHECK (fn_is_protected_email(email));
    END IF;
END;
$$;

ALTER TABLE customer ADD CONSTRAINT uq_customer_cpf_token UNIQUE (cpf);
ALTER TABLE customer ADD CONSTRAINT uq_customer_external_auth_token UNIQUE (external_auth_uid);
ALTER TABLE customer ADD CONSTRAINT ck_customer_name_protected
    CHECK (fn_is_sha256_token(full_name, 'CUS'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_cpf_protected
    CHECK (cpf IS NULL OR fn_is_sha256_token(cpf, 'CPF'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_email_protected
    CHECK (email IS NULL OR fn_is_sha256_token(email, 'EMAIL'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_phone_protected
    CHECK (phone IS NULL OR fn_is_sha256_token(phone, 'PHONE'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_external_auth_protected
    CHECK (external_auth_uid IS NULL OR fn_is_sha256_token(external_auth_uid, 'AUTH'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_birth_year_minimized
    CHECK (birth_year IS NULL OR birth_year BETWEEN 1900 AND EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER);
ALTER TABLE customer ADD CONSTRAINT ck_customer_address_not_linked
    CHECK (address_id IS NULL);
ALTER TABLE customer ADD CONSTRAINT ck_customer_address_token_protected
    CHECK (address_token IS NULL OR fn_is_sha256_token(address_token, 'ADDR'));

ALTER TABLE customer_auth ADD CONSTRAINT uq_customer_auth_login_token UNIQUE (login_email);
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_login_protected
    CHECK (fn_is_sha256_token(login_email, 'EMAIL'));
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_password_bcrypt
    CHECK (fn_is_bcrypt_hash(password_hash));
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_recovery_bcrypt
    CHECK (recovery_token_hash IS NULL OR fn_is_bcrypt_hash(recovery_token_hash));

ALTER TABLE sales_transaction ADD CONSTRAINT ck_sales_customer_document_protected
    CHECK (customer_document IS NULL OR fn_is_sha256_token(customer_document, 'DOC'));

ALTER TABLE staff_session ADD CONSTRAINT ck_staff_session_refresh_sha256
    CHECK (refresh_token_hash ~ '^[A-Fa-f0-9]{64}$');

ALTER TABLE password_reset_token ADD CONSTRAINT ck_password_reset_hash_algorithm
    CHECK (
        (token_type = 'PASSWORD_RESET' AND fn_is_bcrypt_hash(token_hash))
        OR (token_type = 'EMPLOYEE_INVITATION' AND token_hash ~ '^[A-Fa-f0-9]{64}$')
    );

-- Customer consent is append-oriented and keeps no personal value.
CREATE TABLE IF NOT EXISTS customer_consent (
    customer_consent_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    consent_type VARCHAR(40) NOT NULL,
    granted BOOLEAN NOT NULL,
    policy_version VARCHAR(40) NOT NULL,
    collection_channel VARCHAR(30) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    withdrawn_at TIMESTAMPTZ,
    CONSTRAINT ck_customer_consent_type
        CHECK (consent_type IN ('PRIVACY_POLICY', 'MARKETING', 'GEOLOCATION', 'LOYALTY')),
    CONSTRAINT ck_customer_consent_channel
        CHECK (collection_channel IN ('MOBILE_APP', 'WEB', 'SUPPORT', 'MIGRATION')),
    CONSTRAINT ck_customer_consent_withdrawal
        CHECK ((granted AND withdrawn_at IS NULL) OR (NOT granted AND withdrawn_at IS NOT NULL)),
    UNIQUE (customer_id, consent_type, policy_version, recorded_at)
);

CREATE INDEX IF NOT EXISTS idx_customer_consent_history
    ON customer_consent (customer_id, consent_type, recorded_at DESC);

-- RPA correlation stores metadata and hashes only, never transferred payloads.
CREATE TABLE IF NOT EXISTS legacy_sync_record (
    legacy_sync_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system VARCHAR(40) NOT NULL DEFAULT 'LEGACY_POSTGRES',
    source_table VARCHAR(80) NOT NULL,
    source_record_id VARCHAR(120) NOT NULL,
    target_table VARCHAR(80) NOT NULL,
    target_record_id VARCHAR(120) NOT NULL,
    payload_sha256 CHAR(64) NOT NULL CHECK (payload_sha256 ~ '^[A-Fa-f0-9]{64}$'),
    sync_status VARCHAR(20) NOT NULL DEFAULT 'APPLIED'
        CHECK (sync_status IN ('PENDING', 'APPLIED', 'REJECTED', 'REPLAYED')),
    synchronized_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_code VARCHAR(40),
    UNIQUE (source_system, source_table, source_record_id)
);

CREATE INDEX IF NOT EXISTS idx_legacy_sync_target
    ON legacy_sync_record (target_table, target_record_id);

-- Dedicated client API role and transaction-local customer context.
DO $$
DECLARE
    v_is_superuser BOOLEAN;
    v_has_replication BOOLEAN;
    v_bypasses_rls BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_customer_api') THEN
        CREATE ROLE mottainai_customer_api NOLOGIN NOCREATEDB
            NOCREATEROLE NOINHERIT;
    END IF;

    SELECT rolsuper, rolreplication, rolbypassrls
    INTO v_is_superuser, v_has_replication, v_bypasses_rls
    FROM pg_roles
    WHERE rolname = 'mottainai_customer_api';

    IF v_is_superuser OR v_has_replication OR v_bypasses_rls THEN
        RAISE EXCEPTION
            'Role mottainai_customer_api has a privileged attribute (SUPERUSER, REPLICATION or BYPASSRLS). A PostgreSQL superuser must remove it before this migration can continue.';
    END IF;

    ALTER ROLE mottainai_customer_api
        NOLOGIN
        NOCREATEDB
        NOCREATEROLE
        NOINHERIT;
END;
$$;

DO $$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO mottainai_customer_api',
        current_database()
    );
END;
$$;
GRANT USAGE ON SCHEMA mottainai TO mottainai_customer_api;

CREATE TABLE IF NOT EXISTS api_customer_transaction_context (
    backend_pid INTEGER PRIMARY KEY,
    transaction_id BIGINT NOT NULL,
    customer_id INTEGER NOT NULL,
    established_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT fk_api_customer_transaction_context_customer
        FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE CASCADE
);
REVOKE ALL ON api_customer_transaction_context FROM PUBLIC;
REVOKE ALL ON api_customer_transaction_context FROM mottainai_customer_api;

CREATE OR REPLACE FUNCTION fn_get_current_customer_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $$
    SELECT context.customer_id
    FROM mottainai.api_customer_transaction_context AS context
    WHERE context.backend_pid = pg_catalog.pg_backend_pid()
      AND context.transaction_id = pg_catalog.txid_current();
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_customer_context(p_external_auth_token TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $$
DECLARE
    v_customer_id INTEGER;
BEGIN
    IF NOT mottainai.fn_is_sha256_token(p_external_auth_token, 'AUTH') THEN
        RETURN NULL;
    END IF;

    SELECT customer_id INTO v_customer_id
    FROM mottainai.customer
    WHERE external_auth_uid = p_external_auth_token
      AND active IS TRUE
      AND deleted_at IS NULL;

    IF v_customer_id IS NULL THEN
        RETURN NULL;
    END IF;

    INSERT INTO mottainai.api_customer_transaction_context AS context (
        backend_pid, transaction_id, customer_id, established_at
    ) VALUES (
        pg_catalog.pg_backend_pid(), pg_catalog.txid_current(),
        v_customer_id, pg_catalog.clock_timestamp()
    )
    ON CONFLICT (backend_pid) DO UPDATE
    SET transaction_id = EXCLUDED.transaction_id,
        customer_id = EXCLUDED.customer_id,
        established_at = EXCLUDED.established_at;

    RETURN v_customer_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_get_current_customer_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_customer_context(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_get_current_customer_id() TO mottainai_customer_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_customer_context(TEXT) TO mottainai_customer_api;

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_self_policy ON customer;
CREATE POLICY customer_self_policy ON customer FOR SELECT TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id());
DROP POLICY IF EXISTS customer_consent_update_policy ON customer;
CREATE POLICY customer_consent_update_policy ON customer FOR UPDATE TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_auth ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_auth_self_policy ON customer_auth;
CREATE POLICY customer_auth_self_policy ON customer_auth FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_geofence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_geofence_self_policy ON customer_geofence;
CREATE POLICY customer_geofence_self_policy ON customer_geofence FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_consent ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_consent_self_policy ON customer_consent;
CREATE POLICY customer_consent_self_policy ON customer_consent FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE loyalty_account ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_account_self_policy ON loyalty_account;
CREATE POLICY loyalty_account_self_policy ON loyalty_account FOR SELECT TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id());

ALTER TABLE loyalty_transaction ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_transaction_self_policy ON loyalty_transaction;
CREATE POLICY loyalty_transaction_self_policy ON loyalty_transaction FOR SELECT TO mottainai_customer_api
    USING (EXISTS (
        SELECT 1 FROM loyalty_account account
        WHERE account.loyalty_account_id = loyalty_transaction.loyalty_account_id
          AND account.customer_id = fn_get_current_customer_id()
    ));

ALTER TABLE loyalty_redemption ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_redemption_self_policy ON loyalty_redemption;
CREATE POLICY loyalty_redemption_self_policy ON loyalty_redemption FOR SELECT TO mottainai_customer_api
    USING (EXISTS (
        SELECT 1 FROM loyalty_account account
        WHERE account.loyalty_account_id = loyalty_redemption.loyalty_account_id
          AND account.customer_id = fn_get_current_customer_id()
    ));

ALTER TABLE loyalty_reward ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_reward_active_policy ON loyalty_reward;
CREATE POLICY loyalty_reward_active_policy ON loyalty_reward FOR SELECT TO mottainai_customer_api
    USING (active AND (valid_from IS NULL OR valid_from <= CURRENT_TIMESTAMP)
        AND (valid_until IS NULL OR valid_until > CURRENT_TIMESTAMP));

GRANT SELECT ON customer TO mottainai_customer_api;
GRANT UPDATE (marketing_consent, updated_at) ON customer TO mottainai_customer_api;
GRANT SELECT, INSERT, UPDATE ON customer_auth, customer_geofence, customer_consent
    TO mottainai_customer_api;
GRANT SELECT ON loyalty_account, loyalty_transaction, loyalty_redemption, loyalty_reward
    TO mottainai_customer_api;
GRANT USAGE, SELECT ON SEQUENCE customer_auth_customer_auth_id_seq,
    customer_geofence_geofence_id_seq,
    customer_consent_customer_consent_id_seq
    TO mottainai_customer_api;

-- Recursive log redaction protects nested JSON objects and arrays.
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

CREATE OR REPLACE FUNCTION fn_trg_sanitize_log_payload()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'integration_log' THEN
        NEW.payload := fn_sanitize_audit_json(NEW.payload);
        NEW.response := fn_sanitize_audit_json(NEW.response);
    ELSIF TG_TABLE_NAME = 'error_log' THEN
        NEW.parameters := fn_sanitize_audit_json(NEW.parameters);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sanitize_integration_log ON integration_log;
CREATE TRIGGER trg_sanitize_integration_log
BEFORE INSERT OR UPDATE OF payload, response ON integration_log
FOR EACH ROW EXECUTE FUNCTION fn_trg_sanitize_log_payload();

DROP TRIGGER IF EXISTS trg_sanitize_error_log ON error_log;
CREATE TRIGGER trg_sanitize_error_log
BEFORE INSERT OR UPDATE OF parameters ON error_log
FOR EACH ROW EXECUTE FUNCTION fn_trg_sanitize_log_payload();

DO $$
DECLARE
    v_trigger RECORD;
BEGIN
    FOR v_trigger IN SELECT * FROM (VALUES
        ('customer', 'customer_id'),
        ('customer_auth', 'customer_auth_id'),
        ('customer_consent', 'customer_consent_id')
    ) AS protected_table(table_name, id_column)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I',
            'trg_audit_' || v_trigger.table_name, v_trigger.table_name);
        EXECUTE format(
            'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I '
            || 'FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log(%L)',
            'trg_audit_' || v_trigger.table_name,
            v_trigger.table_name,
            v_trigger.id_column
        );
    END LOOP;
END;
$$;

COMMENT ON TABLE customer IS
    'Pseudonymized customer registry. Personal values must arrive as SHA-256-prefixed tokens.';
COMMENT ON COLUMN customer.external_auth_uid IS
    'SHA-256 token of the external identity subject; never store the original Firebase UID.';
COMMENT ON COLUMN customer.birth_year IS
    'Data-minimized year only; the exact birth date is intentionally not stored.';
COMMENT ON TABLE legacy_sync_record IS
    'Idempotent RPA correlation metadata; transferred payloads and personal values are forbidden.';

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '22',
    'Sensitive data tokenization, client isolation and RPA correlation contract',
    'SQL',
    '22_sensitive_data_contract.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
