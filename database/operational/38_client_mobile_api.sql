-- ============================================================================
-- ISOLATED CUSTOMER MOBILE API CONTRACT
-- PostgreSQL 15+
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

-- Required deployment outside this file:
-- 1. Store a database LOGIN principal and credential in the external secret manager.
-- 2. Have a DBA create that LOGIN principal with NO SUPERUSER/CREATEDB/CREATEROLE/BYPASSRLS.
-- 3. Grant only mottainai_client_api to that principal. Do not put its name or
--    password here. The LOGIN principal remains server-side; mobile clients never
--    connect to PostgreSQL.
-- 4. Configure API TLS to PostgreSQL and verify bind-parameter logs do not record
--    password/reset-token arguments. This migration cannot safely change shared
--    database logging or network configuration.
--
-- Compatibility correction: operational PromotionItemRepository filters
-- PromotionItem.deletedAtIsNull, but the supplied consolidated SQL defines no
-- promotion_item.deleted_at column or ALTER for it. This nullable column is needed
-- for the operational customer promotion eligibility rule.
--
-- SAFETY:
-- * Roles below are NOLOGIN, NOBYPASSRLS and have no privileged attributes.
-- * The application role gets no direct access to customer_auth, password hashes,
--   promotion source tables, customer PII tokens, or INSERT on customer.
-- * Catalog access is through filtered security-barrier views owned by a
--   non-login role with column-only source grants.
-- * Customer operations are row-scoped by transaction-local RLS context.
-- * The database stores only protected lookup tokens and AES-GCM envelopes.
--   The API must use the existing operational AAD literal and key configuration.

DO $roles$
DECLARE
    v_name TEXT;
    v_super BOOLEAN;
    v_replication BOOLEAN;
    v_bypass BOOLEAN;
    v_login BOOLEAN;
BEGIN
    FOREACH v_name IN ARRAY ARRAY[
        'mottainai_client_api',
        'mottainai_client_catalog_owner',
        'mottainai_client_profile_owner',
        'mottainai_client_auth_owner'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = v_name) THEN
            EXECUTE format(
                'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                v_name
            );
        END IF;
        SELECT rolsuper, rolreplication, rolbypassrls, rolcanlogin
        INTO v_super, v_replication, v_bypass, v_login
        FROM pg_catalog.pg_roles WHERE rolname = v_name;
        IF v_super OR v_replication OR v_bypass OR v_login THEN
            RAISE EXCEPTION 'Role % must be non-login and non-privileged', v_name;
        END IF;
    END LOOP;
END;
$roles$;

-- Definer-owner roles must never be granted to login or application roles.
-- The client runtime role must not inherit privileges through any membership.
-- Recover safely from an older/interrupted execution that left only the
-- migration account as a temporary member. Memberships held by any other
-- principal remain a hard failure in the check below.
REVOKE mottainai_client_catalog_owner,
       mottainai_client_profile_owner,
       mottainai_client_auth_owner
    FROM CURRENT_USER;

DO $membership_check$
DECLARE
    v_api_oid OID;
    v_unexpected_members TEXT;
BEGIN
    SELECT oid INTO v_api_oid FROM pg_catalog.pg_roles
    WHERE rolname = 'mottainai_client_api';

    SELECT string_agg(
        format('%I -> %I', granted_role.rolname, member_role.rolname),
        ', ' ORDER BY granted_role.rolname, member_role.rolname
    )
    INTO v_unexpected_members
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS granted_role
      ON granted_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE granted_role.rolname IN (
        'mottainai_client_catalog_owner',
        'mottainai_client_profile_owner',
        'mottainai_client_auth_owner'
    );

    IF v_unexpected_members IS NOT NULL THEN
        RAISE EXCEPTION
            'Unexpected client SECURITY DEFINER owner membership: %',
            v_unexpected_members;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_auth_members AS membership
        WHERE membership.member = v_api_oid
    ) THEN
        RAISE EXCEPTION
            'mottainai_client_api must not inherit membership in another role';
    END IF;
END;
$membership_check$;

ALTER ROLE mottainai_client_api
    NOLOGIN NOCREATEDB NOCREATEROLE INHERIT;
ALTER ROLE mottainai_client_catalog_owner
    NOLOGIN NOCREATEDB NOCREATEROLE NOINHERIT;
ALTER ROLE mottainai_client_profile_owner
    NOLOGIN NOCREATEDB NOCREATEROLE NOINHERIT;
ALTER ROLE mottainai_client_auth_owner
    NOLOGIN NOCREATEDB NOCREATEROLE NOINHERIT;

-- PostgreSQL requires membership in the target role to transfer ownership.
-- Membership is temporary, the owner roles are NOINHERIT, and it is revoked
-- before commit. SET ROLE below also makes reapplication idempotent because
-- each object is recreated by its actual owner.
GRANT mottainai_client_catalog_owner,
      mottainai_client_profile_owner,
      mottainai_client_auth_owner
    TO CURRENT_USER;

DO $client_database_connect$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO mottainai_client_api', current_database());
END;
$client_database_connect$;

GRANT USAGE, CREATE ON SCHEMA mottainai TO mottainai_client_catalog_owner;
GRANT USAGE ON SCHEMA mottainai TO mottainai_client_api;
GRANT USAGE, CREATE ON SCHEMA mottainai TO
    mottainai_client_profile_owner,
    mottainai_client_auth_owner;

-- Required by the operational PromotionItemRepository query; no default is
-- assigned so existing rows remain eligible unless the item is soft-deleted.
ALTER TABLE mottainai.promotion_item
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

-- The catalog view owner receives only the columns in customer-facing DTOs.
GRANT SELECT (store_id, name, address_id, latitude, longitude, active, deleted_at)
    ON mottainai.retail_store TO mottainai_client_catalog_owner;
GRANT SELECT (address_id, zip_code, street, number, complement, neighborhood, city, state)
    ON mottainai.address TO mottainai_client_catalog_owner;
GRANT SELECT (promotion_id, store_id, name, description, promotion_type,
              starts_at, ends_at, status, active, deleted_at)
    ON mottainai.promotion TO mottainai_client_catalog_owner;
GRANT SELECT (promotion_item_id, promotion_id, product_id, original_price,
              promotional_price, quantity_available, deleted_at)
    ON mottainai.promotion_item TO mottainai_client_catalog_owner;
GRANT SELECT (product_id, name, active, deleted_at)
    ON mottainai.product TO mottainai_client_catalog_owner;

-- Store/product RLS normally limits reads to an employee company. These
-- additional policies apply only to the non-login catalog view owner.
DROP POLICY IF EXISTS client_catalog_store_select ON mottainai.retail_store;
CREATE POLICY client_catalog_store_select ON mottainai.retail_store
    FOR SELECT TO mottainai_client_catalog_owner
    USING (active IS TRUE AND deleted_at IS NULL);
DROP POLICY IF EXISTS client_catalog_address_select ON mottainai.address;
CREATE POLICY client_catalog_address_select ON mottainai.address
    FOR SELECT TO mottainai_client_catalog_owner
    USING (
        EXISTS (
            SELECT 1 FROM mottainai.retail_store s
            WHERE s.address_id = address.address_id
              AND s.active IS TRUE
              AND s.deleted_at IS NULL
        )
    );
DROP POLICY IF EXISTS client_catalog_product_select ON mottainai.product;
CREATE POLICY client_catalog_product_select ON mottainai.product
    FOR SELECT TO mottainai_client_catalog_owner
    USING (active IS TRUE AND deleted_at IS NULL);

SET ROLE mottainai_client_catalog_owner;

CREATE OR REPLACE VIEW mottainai.api_client_catalog_stores
WITH (security_barrier = true)
AS
SELECT
    s.store_id AS id,
    s.name,
    a.address_id,
    a.zip_code,
    a.street,
    a.number,
    a.complement,
    a.neighborhood,
    a.city,
    a.state,
    s.latitude,
    s.longitude
FROM mottainai.retail_store AS s
JOIN mottainai.address AS a ON a.address_id = s.address_id
WHERE s.active IS TRUE
  AND s.deleted_at IS NULL;
ALTER VIEW mottainai.api_client_catalog_stores
    OWNER TO mottainai_client_catalog_owner;

CREATE OR REPLACE VIEW mottainai.api_client_catalog_promotions
WITH (security_barrier = true)
AS
SELECT
    p.promotion_id AS id,
    p.name,
    p.description,
    p.promotion_type,
    p.starts_at,
    p.ends_at,
    s.store_id AS store_id,
    s.name AS store_name,
    a.address_id,
    a.zip_code,
    a.street,
    a.number,
    a.complement,
    a.neighborhood,
    a.city,
    a.state,
    s.latitude,
    s.longitude
FROM mottainai.promotion AS p
JOIN mottainai.retail_store AS s ON s.store_id = p.store_id
JOIN mottainai.address AS a ON a.address_id = s.address_id
WHERE p.status::TEXT = 'APPROVED'
  AND p.active IS TRUE
  AND p.deleted_at IS NULL
  AND p.starts_at <= CURRENT_TIMESTAMP
  AND p.ends_at > CURRENT_TIMESTAMP
  AND s.active IS TRUE
  AND s.deleted_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM mottainai.promotion_item AS i
      JOIN mottainai.product AS pr ON pr.product_id = i.product_id
      WHERE i.promotion_id = p.promotion_id
        AND i.deleted_at IS NULL
        AND i.quantity_available > 0
        AND pr.active IS TRUE
        AND pr.deleted_at IS NULL
  );
ALTER VIEW mottainai.api_client_catalog_promotions
    OWNER TO mottainai_client_catalog_owner;

CREATE OR REPLACE VIEW mottainai.api_client_catalog_promotion_items
WITH (security_barrier = true)
AS
SELECT
    i.promotion_item_id AS id,
    i.promotion_id,
    i.product_id,
    pr.name,
    i.original_price,
    i.promotional_price,
    i.quantity_available
FROM mottainai.promotion_item AS i
JOIN mottainai.product AS pr ON pr.product_id = i.product_id
JOIN mottainai.promotion AS p ON p.promotion_id = i.promotion_id
JOIN mottainai.retail_store AS s ON s.store_id = p.store_id
WHERE i.deleted_at IS NULL
  AND i.quantity_available > 0
  AND pr.active IS TRUE
  AND pr.deleted_at IS NULL
  AND p.status::TEXT = 'APPROVED'
  AND p.active IS TRUE
  AND p.deleted_at IS NULL
  AND p.starts_at <= CURRENT_TIMESTAMP
  AND p.ends_at > CURRENT_TIMESTAMP
  AND s.active IS TRUE
  AND s.deleted_at IS NULL;
ALTER VIEW mottainai.api_client_catalog_promotion_items
    OWNER TO mottainai_client_catalog_owner;

RESET ROLE;

GRANT SELECT ON mottainai.api_client_catalog_stores,
                mottainai.api_client_catalog_promotions,
                mottainai.api_client_catalog_promotion_items
    TO mottainai_client_api;

-- Restricted direct row access for routes with established customer RLS context.
GRANT EXECUTE ON FUNCTION mottainai.fn_get_current_customer_id()
    TO mottainai_client_api;
GRANT EXECUTE ON FUNCTION mottainai.fn_bootstrap_customer_context(TEXT)
    TO mottainai_client_api;
GRANT SELECT (customer_id, birth_year, active, marketing_consent, created_at,
              updated_at, deleted_at)
    ON mottainai.customer TO mottainai_client_api;
GRANT SELECT (customer_id, payload_ciphertext, payload_nonce, key_version,
              algorithm, payload_format, encrypted_at, created_at, updated_at, deleted_at)
    ON mottainai.customer_private_data TO mottainai_client_api;
GRANT SELECT (geofence_id, customer_id, store_id, radius_meters, active,
              created_at, updated_at)
    ON mottainai.customer_geofence TO mottainai_client_api;
GRANT INSERT (customer_id, store_id, radius_meters, active, created_at, updated_at),
      UPDATE (radius_meters, active, updated_at)
    ON mottainai.customer_geofence TO mottainai_client_api;
GRANT USAGE, SELECT ON SEQUENCE mottainai.customer_geofence_geofence_id_seq
    TO mottainai_client_api;
GRANT SELECT (loyalty_account_id, customer_id, points_balance, joined_at, active, updated_at)
    ON mottainai.loyalty_account TO mottainai_client_api;
GRANT SELECT (loyalty_transaction_id, loyalty_account_id, sale_id, sale_date,
              transaction_type, points, description, created_at)
    ON mottainai.loyalty_transaction TO mottainai_client_api;

DROP POLICY IF EXISTS client_api_customer_select ON mottainai.customer;
CREATE POLICY client_api_customer_select ON mottainai.customer
    FOR SELECT TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_api_private_data_select ON mottainai.customer_private_data;
CREATE POLICY client_api_private_data_select ON mottainai.customer_private_data
    FOR SELECT TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id() AND deleted_at IS NULL);
DROP POLICY IF EXISTS client_api_geofence_select ON mottainai.customer_geofence;
CREATE POLICY client_api_geofence_select ON mottainai.customer_geofence
    FOR SELECT TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_api_geofence_insert ON mottainai.customer_geofence;
CREATE POLICY client_api_geofence_insert ON mottainai.customer_geofence
    FOR INSERT TO mottainai_client_api
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_api_geofence_update ON mottainai.customer_geofence;
CREATE POLICY client_api_geofence_update ON mottainai.customer_geofence
    FOR UPDATE TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id())
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_api_loyalty_balance_select ON mottainai.loyalty_account;
CREATE POLICY client_api_loyalty_balance_select ON mottainai.loyalty_account
    FOR SELECT TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_api_loyalty_transaction_select ON mottainai.loyalty_transaction;
CREATE POLICY client_api_loyalty_transaction_select ON mottainai.loyalty_transaction
    FOR SELECT TO mottainai_client_api
    USING (EXISTS (
        SELECT 1
        FROM mottainai.loyalty_account AS account
        WHERE account.loyalty_account_id = loyalty_transaction.loyalty_account_id
          AND account.customer_id = mottainai.fn_get_current_customer_id()
    ));

-- Profile function owner can read protected lookup tokens only through its
-- SECURITY DEFINER function, insert validated protected rows, and write the
-- authenticated envelope and initial zero-balance account.
GRANT SELECT (customer_id, full_name, cpf, email, phone, address_token,
              external_auth_uid, birth_year, active, marketing_consent,
              created_at, updated_at, deleted_at)
    ON mottainai.customer TO mottainai_client_profile_owner;
GRANT INSERT (customer_id, full_name, cpf, email, phone, address_token,
              external_auth_uid, birth_year, active, marketing_consent,
              created_at, updated_at)
    ON mottainai.customer TO mottainai_client_profile_owner;
GRANT UPDATE (full_name, phone, marketing_consent, updated_at)
    ON mottainai.customer TO mottainai_client_profile_owner;
GRANT SELECT (customer_auth_id, login_email)
    ON mottainai.customer_auth TO mottainai_client_profile_owner;
GRANT SELECT, INSERT, UPDATE ON mottainai.customer_private_data
    TO mottainai_client_profile_owner;
GRANT INSERT (customer_id, points_balance, joined_at, active, updated_at)
    ON mottainai.loyalty_account TO mottainai_client_profile_owner;
GRANT USAGE, SELECT ON SEQUENCE mottainai.loyalty_account_loyalty_account_id_seq
    TO mottainai_client_profile_owner;
GRANT USAGE, SELECT ON SEQUENCE mottainai.customer_customer_id_seq
    TO mottainai_client_profile_owner;
GRANT EXECUTE ON FUNCTION mottainai.fn_is_sha256_token(TEXT, TEXT),
    mottainai.fn_bootstrap_customer_context(TEXT),
    mottainai.fn_get_current_customer_id()
    TO mottainai_client_profile_owner;

DROP POLICY IF EXISTS client_profile_owner_customer_select ON mottainai.customer;
CREATE POLICY client_profile_owner_customer_select ON mottainai.customer
    FOR SELECT TO mottainai_client_profile_owner USING (TRUE);
DROP POLICY IF EXISTS client_profile_owner_customer_insert ON mottainai.customer;
CREATE POLICY client_profile_owner_customer_insert ON mottainai.customer
    FOR INSERT TO mottainai_client_profile_owner
    WITH CHECK (
        mottainai.fn_is_sha256_token(full_name, 'CUS')
        AND cpf IS NOT NULL AND mottainai.fn_is_sha256_token(cpf, 'CPF')
        AND email IS NOT NULL AND mottainai.fn_is_sha256_token(email, 'EMAIL')
        AND (phone IS NULL OR mottainai.fn_is_sha256_token(phone, 'PHONE'))
        AND (address_token IS NULL OR mottainai.fn_is_sha256_token(address_token, 'ADDR'))
        AND external_auth_uid IS NOT NULL
        AND mottainai.fn_is_sha256_token(external_auth_uid, 'AUTH')
        AND active IS TRUE AND deleted_at IS NULL
    );
DROP POLICY IF EXISTS client_profile_owner_customer_update ON mottainai.customer;
CREATE POLICY client_profile_owner_customer_update ON mottainai.customer
    FOR UPDATE TO mottainai_client_profile_owner
    USING (customer_id = mottainai.fn_get_current_customer_id())
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_profile_owner_auth_select ON mottainai.customer_auth;
CREATE POLICY client_profile_owner_auth_select ON mottainai.customer_auth
    FOR SELECT TO mottainai_client_profile_owner USING (TRUE);
DROP POLICY IF EXISTS client_profile_owner_private_select ON mottainai.customer_private_data;
CREATE POLICY client_profile_owner_private_select ON mottainai.customer_private_data
    FOR SELECT TO mottainai_client_profile_owner
    USING (customer_id = mottainai.fn_get_current_customer_id() AND deleted_at IS NULL);
DROP POLICY IF EXISTS client_profile_owner_private_insert ON mottainai.customer_private_data;
CREATE POLICY client_profile_owner_private_insert ON mottainai.customer_private_data
    FOR INSERT TO mottainai_client_profile_owner
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS client_profile_owner_private_update ON mottainai.customer_private_data;
CREATE POLICY client_profile_owner_private_update ON mottainai.customer_private_data
    FOR UPDATE TO mottainai_client_profile_owner
    USING (customer_id = mottainai.fn_get_current_customer_id() AND deleted_at IS NULL)
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id() AND deleted_at IS NULL);
DROP POLICY IF EXISTS client_profile_owner_loyalty_insert ON mottainai.loyalty_account;
CREATE POLICY client_profile_owner_loyalty_insert ON mottainai.loyalty_account
    FOR INSERT TO mottainai_client_profile_owner
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());

-- Authentication owner can inspect credentials only inside functions that
-- compare BCrypt values and return no password or recovery hashes.
GRANT SELECT (customer_id, active, deleted_at)
    ON mottainai.customer TO mottainai_client_auth_owner;
GRANT SELECT (customer_auth_id, customer_id, login_email, password_hash,
              failed_attempts, locked_until, recovery_token_hash,
              recovery_expires_at, active, last_login_at,
              password_changed_at, updated_at)
    ON mottainai.customer_auth TO mottainai_client_auth_owner;
GRANT UPDATE (failed_attempts, locked_until, recovery_token_hash,
              recovery_expires_at, last_login_at, password_hash,
              password_changed_at, updated_at)
    ON mottainai.customer_auth TO mottainai_client_auth_owner;
GRANT EXECUTE ON FUNCTION mottainai.fn_is_sha256_token(TEXT, TEXT),
    mottainai.fn_is_bcrypt_hash(TEXT)
    TO mottainai_client_auth_owner;
GRANT EXECUTE ON FUNCTION public.crypt(TEXT, TEXT)
    TO mottainai_client_auth_owner;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    TO mottainai_client_auth_owner;
GRANT SET ON PARAMETER app.current_customer_id
    TO mottainai_client_auth_owner;

DROP POLICY IF EXISTS client_auth_owner_customer_select ON mottainai.customer;
CREATE POLICY client_auth_owner_customer_select ON mottainai.customer
    FOR SELECT TO mottainai_client_auth_owner
    USING (active IS TRUE AND deleted_at IS NULL);
DROP POLICY IF EXISTS client_auth_owner_auth_select ON mottainai.customer_auth;
CREATE POLICY client_auth_owner_auth_select ON mottainai.customer_auth
    FOR SELECT TO mottainai_client_auth_owner USING (TRUE);
DROP POLICY IF EXISTS client_auth_owner_auth_update ON mottainai.customer_auth;
CREATE POLICY client_auth_owner_auth_update ON mottainai.customer_auth
    FOR UPDATE TO mottainai_client_auth_owner
    USING (TRUE) WITH CHECK (TRUE);

-- Reserve an identity so the API can encrypt its envelope using the operational
-- customer-ID AAD before the atomic customer/envelope/account insert. An unused
-- reservation only consumes a sequence number and creates no customer row.
SET ROLE mottainai_client_profile_owner;

CREATE OR REPLACE FUNCTION mottainai.fn_api_reserve_customer_id()
RETURNS INTEGER
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
    SELECT pg_catalog.nextval(
        pg_catalog.pg_get_serial_sequence('mottainai.customer', 'customer_id')::regclass
    )::INTEGER;
$function$;
ALTER FUNCTION mottainai.fn_api_reserve_customer_id()
    OWNER TO mottainai_client_profile_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_reserve_customer_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_reserve_customer_id()
    TO mottainai_client_api;

CREATE OR REPLACE FUNCTION mottainai.fn_api_create_firebase_customer_profile(
    p_customer_id INTEGER,
    p_full_name_token TEXT,
    p_cpf_token TEXT,
    p_email_token TEXT,
    p_phone_token TEXT,
    p_address_token TEXT,
    p_external_auth_token TEXT,
    p_birth_year SMALLINT,
    p_marketing_consent BOOLEAN,
    p_payload_ciphertext BYTEA,
    p_payload_nonce BYTEA,
    p_key_version SMALLINT,
    p_now TIMESTAMP
)
RETURNS TABLE (
    result_code TEXT,
    customer_id INTEGER,
    birth_year SMALLINT,
    active BOOLEAN,
    marketing_consent BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_existing_customer_id INTEGER;
    v_existing_birth_year SMALLINT;
    v_existing_active BOOLEAN;
    v_existing_marketing_consent BOOLEAN;
    v_existing_created_at TIMESTAMP;
    v_existing_updated_at TIMESTAMP;
    v_context_customer_id INTEGER;
BEGIN
    IF p_customer_id IS NULL OR p_customer_id < 1
       OR p_full_name_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_full_name_token, 'CUS')
       OR p_cpf_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_cpf_token, 'CPF')
       OR p_email_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_email_token, 'EMAIL')
       OR (p_phone_token IS NOT NULL
           AND NOT mottainai.fn_is_sha256_token(p_phone_token, 'PHONE'))
       OR (p_address_token IS NOT NULL
           AND NOT mottainai.fn_is_sha256_token(p_address_token, 'ADDR'))
       OR p_external_auth_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_external_auth_token, 'AUTH')
       OR (p_birth_year IS NOT NULL AND
           (p_birth_year < 1900 OR p_birth_year > EXTRACT(YEAR FROM p_now)::INTEGER))
       OR p_payload_ciphertext IS NULL OR octet_length(p_payload_ciphertext) < 17
       OR p_payload_nonce IS NULL OR octet_length(p_payload_nonce) <> 12
       OR p_key_version IS NULL OR p_key_version < 1
       OR p_now IS NULL THEN
        RAISE EXCEPTION 'Invalid protected Firebase profile input'
            USING ERRCODE = '22023';
    END IF;

    SELECT c.customer_id, c.birth_year, c.active, c.marketing_consent,
           c.created_at, c.updated_at
    INTO v_existing_customer_id, v_existing_birth_year, v_existing_active,
         v_existing_marketing_consent, v_existing_created_at, v_existing_updated_at
    FROM mottainai.customer AS c
    WHERE c.external_auth_uid = p_external_auth_token;

    IF FOUND THEN
        IF v_existing_active IS TRUE AND EXISTS (
            SELECT 1 FROM mottainai.customer AS c
            WHERE c.customer_id = v_existing_customer_id AND c.deleted_at IS NULL
        ) THEN
            RETURN QUERY SELECT 'EXISTING_ACTIVE', v_existing_customer_id,
                v_existing_birth_year, v_existing_active, v_existing_marketing_consent,
                v_existing_created_at, v_existing_updated_at;
        ELSE
            RETURN QUERY SELECT 'INACTIVE_IDENTITY_CONFLICT', NULL::INTEGER,
                NULL::SMALLINT, NULL::BOOLEAN, NULL::BOOLEAN,
                NULL::TIMESTAMP, NULL::TIMESTAMP;
        END IF;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM mottainai.customer AS c
        WHERE c.deleted_at IS NULL
          AND (c.cpf = p_cpf_token OR c.email = p_email_token)
    ) OR EXISTS (
        SELECT 1 FROM mottainai.customer_auth AS a
        WHERE a.login_email = p_email_token
    ) THEN
        RETURN QUERY SELECT 'PROFILE_CONFLICT', NULL::INTEGER,
            NULL::SMALLINT, NULL::BOOLEAN, NULL::BOOLEAN,
            NULL::TIMESTAMP, NULL::TIMESTAMP;
        RETURN;
    END IF;

    IF pg_catalog.currval(
        pg_catalog.pg_get_serial_sequence('mottainai.customer', 'customer_id')::regclass
    ) IS DISTINCT FROM p_customer_id THEN
        RAISE EXCEPTION 'Customer ID was not reserved in this database session'
            USING ERRCODE = '22023';
    END IF;

    BEGIN
        INSERT INTO mottainai.customer (
            customer_id, full_name, cpf, email, phone, address_token,
            external_auth_uid, birth_year, active, marketing_consent,
            created_at, updated_at
        ) OVERRIDING SYSTEM VALUE
        VALUES (
            p_customer_id, p_full_name_token, p_cpf_token, p_email_token,
            p_phone_token, p_address_token, p_external_auth_token, p_birth_year,
            TRUE, COALESCE(p_marketing_consent, FALSE), p_now, p_now
        );

        v_context_customer_id :=
            mottainai.fn_bootstrap_customer_context(p_external_auth_token);
        IF v_context_customer_id IS DISTINCT FROM p_customer_id THEN
            RAISE EXCEPTION 'Could not establish Firebase customer context'
                USING ERRCODE = '42501';
        END IF;

        INSERT INTO mottainai.customer_private_data (
            customer_id, payload_ciphertext, payload_nonce, key_version,
            created_at, updated_at
        ) VALUES (
            p_customer_id, p_payload_ciphertext, p_payload_nonce, p_key_version,
            p_now, p_now
        );

        INSERT INTO mottainai.loyalty_account (
            customer_id, points_balance, joined_at, active, updated_at
        ) VALUES (p_customer_id, 0, p_now, TRUE, p_now);

        RETURN QUERY
        SELECT 'CREATED', c.customer_id, c.birth_year, c.active,
               c.marketing_consent, c.created_at, c.updated_at
        FROM mottainai.customer AS c
        WHERE c.customer_id = p_customer_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN QUERY SELECT 'PROFILE_CONFLICT', NULL::INTEGER,
            NULL::SMALLINT, NULL::BOOLEAN, NULL::BOOLEAN,
            NULL::TIMESTAMP, NULL::TIMESTAMP;
    END;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_create_firebase_customer_profile(
    INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BOOLEAN,
    BYTEA, BYTEA, SMALLINT, TIMESTAMP
) OWNER TO mottainai_client_profile_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_create_firebase_customer_profile(
    INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BOOLEAN,
    BYTEA, BYTEA, SMALLINT, TIMESTAMP
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_create_firebase_customer_profile(
    INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, SMALLINT, BOOLEAN,
    BYTEA, BYTEA, SMALLINT, TIMESTAMP
) TO mottainai_client_api;

CREATE OR REPLACE FUNCTION mottainai.fn_api_update_firebase_customer_profile(
    p_external_auth_token TEXT,
    p_full_name_token TEXT,
    p_phone_token TEXT,
    p_marketing_consent BOOLEAN,
    p_payload_ciphertext BYTEA,
    p_payload_nonce BYTEA,
    p_key_version SMALLINT,
    p_now TIMESTAMP
)
RETURNS TABLE (
    result_code TEXT,
    customer_id INTEGER,
    birth_year SMALLINT,
    active BOOLEAN,
    marketing_consent BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_customer_id INTEGER;
BEGIN
    IF p_external_auth_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_external_auth_token, 'AUTH')
       OR p_full_name_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_full_name_token, 'CUS')
       OR (p_phone_token IS NOT NULL
           AND NOT mottainai.fn_is_sha256_token(p_phone_token, 'PHONE'))
       OR p_marketing_consent IS NULL
       OR p_payload_ciphertext IS NULL OR octet_length(p_payload_ciphertext) < 17
       OR p_payload_nonce IS NULL OR octet_length(p_payload_nonce) <> 12
       OR p_key_version IS NULL OR p_key_version < 1
       OR p_now IS NULL THEN
        RAISE EXCEPTION 'Invalid protected Firebase profile update'
            USING ERRCODE = '22023';
    END IF;

    v_customer_id :=
        mottainai.fn_bootstrap_customer_context(p_external_auth_token);
    IF v_customer_id IS NULL THEN
        RETURN QUERY SELECT 'NOT_FOUND', NULL::INTEGER, NULL::SMALLINT,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::TIMESTAMP, NULL::TIMESTAMP;
        RETURN;
    END IF;

    UPDATE mottainai.customer AS c
    SET full_name = p_full_name_token,
        phone = p_phone_token,
        marketing_consent = p_marketing_consent,
        updated_at = p_now
    WHERE c.customer_id = v_customer_id
      AND c.active IS TRUE
      AND c.deleted_at IS NULL;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'NOT_FOUND', NULL::INTEGER, NULL::SMALLINT,
            NULL::BOOLEAN, NULL::BOOLEAN, NULL::TIMESTAMP, NULL::TIMESTAMP;
        RETURN;
    END IF;

    UPDATE mottainai.customer_private_data AS d
    SET payload_ciphertext = p_payload_ciphertext,
        payload_nonce = p_payload_nonce,
        key_version = p_key_version,
        updated_at = p_now
    WHERE d.customer_id = v_customer_id
      AND d.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer encrypted personal data is missing';
    END IF;

    RETURN QUERY
    SELECT 'UPDATED', c.customer_id, c.birth_year, c.active,
           c.marketing_consent, c.created_at, c.updated_at
    FROM mottainai.customer AS c
    WHERE c.customer_id = v_customer_id;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_update_firebase_customer_profile(
    TEXT, TEXT, TEXT, BOOLEAN, BYTEA, BYTEA, SMALLINT, TIMESTAMP
) OWNER TO mottainai_client_profile_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_update_firebase_customer_profile(
    TEXT, TEXT, TEXT, BOOLEAN, BYTEA, BYTEA, SMALLINT, TIMESTAMP
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_update_firebase_customer_profile(
    TEXT, TEXT, TEXT, BOOLEAN, BYTEA, BYTEA, SMALLINT, TIMESTAMP
) TO mottainai_client_api;

RESET ROLE;

GRANT EXECUTE ON FUNCTION mottainai.fn_customer_private_data_customer_is_inactive(INTEGER)
    TO mottainai_client_profile_owner;

SET ROLE mottainai_client_auth_owner;

CREATE OR REPLACE FUNCTION mottainai.fn_api_customer_login(
    p_login_email_token TEXT, p_raw_password TEXT, p_now TIMESTAMP
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_auth_id INTEGER;
    v_customer_id INTEGER;
    v_password_hash TEXT;
    v_failed_attempts INTEGER;
    v_locked_until TIMESTAMP;
BEGIN
    IF p_login_email_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_login_email_token, 'EMAIL')
       OR p_raw_password IS NULL OR p_now IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT a.customer_auth_id, a.customer_id, a.password_hash,
           a.failed_attempts, a.locked_until
    INTO v_auth_id, v_customer_id, v_password_hash,
         v_failed_attempts, v_locked_until
    FROM mottainai.customer_auth AS a
    JOIN mottainai.customer AS c ON c.customer_id = a.customer_id
    WHERE a.login_email = p_login_email_token
      AND a.active IS TRUE
      AND c.active IS TRUE
      AND c.deleted_at IS NULL
    FOR UPDATE OF a;

    IF NOT FOUND OR (v_locked_until IS NOT NULL AND v_locked_until > p_now) THEN
        RETURN NULL;
    END IF;

    IF public.crypt(p_raw_password, v_password_hash) IS DISTINCT FROM v_password_hash THEN
        v_failed_attempts := v_failed_attempts + 1;
        UPDATE mottainai.customer_auth
        SET failed_attempts = v_failed_attempts,
            locked_until = CASE WHEN v_failed_attempts >= 5
                                THEN p_now + INTERVAL '30 minutes'
                                ELSE locked_until END,
            updated_at = p_now
        WHERE customer_auth_id = v_auth_id;
        RETURN NULL;
    END IF;

    UPDATE mottainai.customer_auth
    SET failed_attempts = 0, locked_until = NULL,
        last_login_at = p_now, updated_at = p_now
    WHERE customer_auth_id = v_auth_id;
    RETURN v_customer_id;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_customer_login(TEXT, TEXT, TIMESTAMP)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_customer_login(TEXT, TEXT, TIMESTAMP) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_customer_login(TEXT, TEXT, TIMESTAMP)
    TO mottainai_client_api;

CREATE OR REPLACE FUNCTION mottainai.fn_api_request_customer_recovery(
    p_login_email_token TEXT, p_recovery_bcrypt_hash TEXT, p_now TIMESTAMP
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_auth_id INTEGER;
BEGIN
    IF p_login_email_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_login_email_token, 'EMAIL')
       OR p_recovery_bcrypt_hash IS NULL
       OR NOT mottainai.fn_is_bcrypt_hash(p_recovery_bcrypt_hash)
       OR p_now IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT a.customer_auth_id INTO v_auth_id
    FROM mottainai.customer_auth AS a
    JOIN mottainai.customer AS c ON c.customer_id = a.customer_id
    WHERE a.login_email = p_login_email_token
      AND a.active IS TRUE AND c.active IS TRUE AND c.deleted_at IS NULL
    FOR UPDATE OF a;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    UPDATE mottainai.customer_auth
    SET recovery_token_hash = p_recovery_bcrypt_hash,
        recovery_expires_at = p_now + INTERVAL '15 minutes',
        updated_at = p_now
    WHERE customer_auth_id = v_auth_id;
    RETURN v_auth_id;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_request_customer_recovery(TEXT, TEXT, TIMESTAMP)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_request_customer_recovery(TEXT, TEXT, TIMESTAMP)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_request_customer_recovery(TEXT, TEXT, TIMESTAMP)
    TO mottainai_client_api;

-- Revoke a token when SMTP delivery fails, matching the operational API's
-- after-commit cleanup behavior. The plaintext recovery secret is compared
-- inside this security-definer function and is never returned.
CREATE OR REPLACE FUNCTION mottainai.fn_api_clear_customer_recovery(
    p_customer_auth_id INTEGER, p_secret TEXT, p_now TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
BEGIN
    IF p_customer_auth_id IS NULL OR p_secret IS NULL OR p_now IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE mottainai.customer_auth AS a
    SET recovery_token_hash = NULL,
        recovery_expires_at = NULL,
        updated_at = p_now
    WHERE a.customer_auth_id = p_customer_auth_id
      AND a.active IS TRUE
      AND a.recovery_token_hash IS NOT NULL
      AND a.recovery_expires_at > p_now
      AND public.crypt(p_secret, a.recovery_token_hash) = a.recovery_token_hash;

    RETURN FOUND;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_clear_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_clear_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_clear_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    TO mottainai_client_api;

CREATE OR REPLACE FUNCTION mottainai.fn_api_validate_customer_recovery(
    p_customer_auth_id INTEGER, p_secret TEXT, p_now TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM mottainai.customer_auth AS a
        JOIN mottainai.customer AS c ON c.customer_id = a.customer_id
        WHERE a.customer_auth_id = p_customer_auth_id
          AND a.active IS TRUE AND c.active IS TRUE AND c.deleted_at IS NULL
          AND a.recovery_token_hash IS NOT NULL
          AND a.recovery_expires_at > p_now
          AND public.crypt(p_secret, a.recovery_token_hash) = a.recovery_token_hash
    );
$function$;
ALTER FUNCTION mottainai.fn_api_validate_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_validate_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_validate_customer_recovery(INTEGER, TEXT, TIMESTAMP)
    TO mottainai_client_api;

CREATE OR REPLACE FUNCTION mottainai.fn_api_reset_customer_password(
    p_customer_auth_id INTEGER, p_secret TEXT,
    p_new_password_bcrypt_hash TEXT, p_now TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
BEGIN
    IF p_customer_auth_id IS NULL OR p_secret IS NULL
       OR p_new_password_bcrypt_hash IS NULL
       OR NOT mottainai.fn_is_bcrypt_hash(p_new_password_bcrypt_hash)
       OR p_now IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE mottainai.customer_auth AS a
    SET password_hash = p_new_password_bcrypt_hash,
        password_changed_at = p_now,
        recovery_token_hash = NULL, recovery_expires_at = NULL,
        failed_attempts = 0, locked_until = NULL, updated_at = p_now
    FROM mottainai.customer AS c
    WHERE a.customer_auth_id = p_customer_auth_id
      AND c.customer_id = a.customer_id
      AND a.active IS TRUE AND c.active IS TRUE AND c.deleted_at IS NULL
      AND a.recovery_token_hash IS NOT NULL
      AND a.recovery_expires_at > p_now
      AND public.crypt(p_secret, a.recovery_token_hash) = a.recovery_token_hash;

    RETURN FOUND;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_reset_customer_password(INTEGER, TEXT, TEXT, TIMESTAMP)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_reset_customer_password(INTEGER, TEXT, TEXT, TIMESTAMP)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_reset_customer_password(INTEGER, TEXT, TEXT, TIMESTAMP)
    TO mottainai_client_api;

-- Call only after the API verifies the signed ROLE_CUSTOMER JWT and its subject
-- is the protected email token. This function returns no credentials. It does
-- not grant the app role direct SET or set_config access.
CREATE OR REPLACE FUNCTION mottainai.fn_api_bootstrap_legacy_customer_context(
    p_login_email_token TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_customer_id INTEGER;
BEGIN
    IF p_login_email_token IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_login_email_token, 'EMAIL') THEN
        RETURN NULL;
    END IF;

    SELECT c.customer_id INTO v_customer_id
    FROM mottainai.customer_auth AS a
    JOIN mottainai.customer AS c ON c.customer_id = a.customer_id
    WHERE a.login_email = p_login_email_token
      AND a.active IS TRUE AND c.active IS TRUE AND c.deleted_at IS NULL;

    IF v_customer_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM pg_catalog.set_config('app.current_customer_id', v_customer_id::TEXT, TRUE);
    RETURN v_customer_id;
END;
$function$;
ALTER FUNCTION mottainai.fn_api_bootstrap_legacy_customer_context(TEXT)
    OWNER TO mottainai_client_auth_owner;
REVOKE ALL ON FUNCTION mottainai.fn_api_bootstrap_legacy_customer_context(TEXT)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_bootstrap_legacy_customer_context(TEXT)
    TO mottainai_client_api;

RESET ROLE;

-- No CREATE privilege is needed after objects have been assigned their owners.
REVOKE CREATE ON SCHEMA mottainai FROM
    mottainai_client_catalog_owner,
    mottainai_client_profile_owner,
    mottainai_client_auth_owner;

REVOKE mottainai_client_catalog_owner,
       mottainai_client_profile_owner,
       mottainai_client_auth_owner
    FROM CURRENT_USER;

-- Service integration contracts:
-- * Firebase onboarding calls fn_api_reserve_customer_id and then
--   fn_api_create_firebase_customer_profile in the SAME transaction/session.
--   It encrypts the JSON envelope after receiving the reserved ID.
-- * Firebase PUT first decrypts the own-row envelope, preserves CPF/email/
--   birthDate/address, re-encrypts using the operational AAD, and calls the
--   update function. GET calls fn_bootstrap_customer_context before SELECT.
-- * The role can only read own non-PII customer fields, own encrypted envelope,
--   own geofences, points balance, and filtered catalog views.
-- * Store geofence validation uses api_client_catalog_stores; the API must use
--   a projection instead of selecting the full RetailStore entity.
-- * Legacy recovery remains generic HTTP 204 and email is sent after commit.
--   Password strength validation and token parsing remain in the API.
-- * Bind parameter log redaction and TLS must be verified before applying
--   functions that receive raw login/reset secrets.
-- * The migration executor must be authorized to create/alter objects and
--   transfer ownership to the NOLOGIN owner roles.
-- * Promotion views use CURRENT_TIMESTAMP; align database and operational API
--   time zones before deployment. Preserve operational ordering/pagination.
-- * pgcrypto is created without an explicit schema in the source. This SQL
--   assumes public.crypt exists; verify extension placement before applying.

INSERT INTO mottainai.schema_version (
    version, description, type, script, installed_by
) VALUES (
    '38',
    'Add least-privilege database contract for the customer mobile API',
    'SQL',
    '38_client_mobile_api.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
