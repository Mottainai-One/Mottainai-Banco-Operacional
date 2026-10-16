-- ============================================================================
-- REVERSIBLE EMPLOYEE PII - FINALIZATION PHASE
-- Run only after the backend/RPA has populated employee_private_data and every
-- app_user has a Firebase UID. The preflight block makes this migration fail
-- closed instead of destroying the last available legacy token.
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
    v_incomplete_contact BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM employee e
        LEFT JOIN employee_private_data p USING (employee_id)
        WHERE p.employee_id IS NULL
           OR p.protection_state <> 'ENCRYPTED'
           OR p.name_ciphertext IS NULL
           OR p.name_nonce IS NULL
           OR p.name_token !~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$'
    ) THEN
        RAISE EXCEPTION
            'Refusing PII finalization: every employee must have a complete ENCRYPTED AES-GCM envelope and HMAC tokens';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'email'
    ) THEN
        EXECUTE $sql$
            SELECT EXISTS (
                SELECT 1
                FROM employee e
                JOIN employee_private_data p USING (employee_id)
                WHERE e.email IS NOT NULL
                  AND (p.email_ciphertext IS NULL OR p.email_nonce IS NULL
                       OR p.email_token !~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$')
            )
        $sql$ INTO v_incomplete_contact;

        IF v_incomplete_contact THEN
            RAISE EXCEPTION
                'Refusing PII finalization: employee email envelopes are incomplete';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee'
          AND column_name = 'phone'
    ) THEN
        EXECUTE $sql$
            SELECT EXISTS (
                SELECT 1
                FROM employee e
                JOIN employee_private_data p USING (employee_id)
                WHERE e.phone IS NOT NULL
                  AND (p.phone_ciphertext IS NULL OR p.phone_nonce IS NULL
                       OR p.phone_token !~ '^HMAC256_V[0-9]+_[A-F0-9]{64}$')
            )
        $sql$ INTO v_incomplete_contact;

        IF v_incomplete_contact THEN
            RAISE EXCEPTION
                'Refusing PII finalization: employee phone envelopes are incomplete';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1 FROM app_user
        WHERE firebase_uid IS NULL OR btrim(firebase_uid) = ''
    ) THEN
        RAISE EXCEPTION
            'Refusing app_user.email removal: every app_user must have firebase_uid';
    END IF;
END;
$$;

-- Keep the public signature used by the API, but remove email-based identity.
CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context(
    p_identity TEXT,
    p_lookup TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_lookup NOT IN ('CPF', 'FIREBASE_UID', 'INVITED_CPF') THEN
        RETURN FALSE;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM app_user u
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL
      AND s.active
      AND c.active
      AND r.active
      AND (
          (p_lookup = 'CPF' AND u.cpf = p_identity AND u.active AND e.active)
          OR
          (p_lookup = 'FIREBASE_UID' AND u.firebase_uid = p_identity
              AND u.active AND e.active)
          OR
          (p_lookup = 'INVITED_CPF' AND u.cpf = p_identity
              AND NOT u.active AND NOT e.active AND NOT u.password_set)
      );

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) TO mottainai_api;

ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_name_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_email_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_phone_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_email_token;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_email_protected;

ALTER TABLE employee
    DROP COLUMN IF EXISTS name,
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS phone;

ALTER TABLE app_user
    DROP COLUMN IF EXISTS email,
    ALTER COLUMN firebase_uid SET NOT NULL;

COMMENT ON COLUMN app_user.firebase_uid IS
    'Primary external authentication identity. Email is stored only as an encrypted employee private-data envelope.';
