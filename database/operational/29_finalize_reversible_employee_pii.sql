-- ============================================================================
-- REVERSIBLE EMPLOYEE IDENTITY - FINALIZATION PHASE
-- Run after the backend/RPA has encrypted every employee name and CPF, any
-- populated email/phone, and populated the email uniqueness HMAC. The migration
-- fails closed before removing legacy PII or its uniqueness contract.
-- ============================================================================

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
    v_incomplete BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM employee e
        LEFT JOIN employee_private_data p USING (employee_id)
        WHERE p.employee_id IS NULL
           OR p.protection_state <> 'ENCRYPTED'
           OR p.name_ciphertext IS NULL OR p.name_nonce IS NULL
           OR p.cpf_ciphertext IS NULL OR p.cpf_nonce IS NULL
           OR p.key_version IS NULL OR p.encrypted_at IS NULL
    ) THEN
        RAISE EXCEPTION
            'Refusing PII finalization: every employee requires encrypted AES-GCM name and CPF envelopes';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai' AND table_name = 'employee'
          AND column_name = 'email'
    ) THEN
        EXECUTE $sql$
            SELECT EXISTS (
                SELECT 1 FROM employee e
                JOIN employee_private_data p USING (employee_id)
                WHERE e.email IS NOT NULL
                  AND (p.email_ciphertext IS NULL OR p.email_nonce IS NULL)
            )
        $sql$ INTO v_incomplete;
        IF v_incomplete THEN
            RAISE EXCEPTION 'Refusing PII finalization: employee email envelopes are incomplete';
        END IF;

        EXECUTE $sql$
            SELECT EXISTS (
                SELECT 1 FROM employee
                WHERE email IS NOT NULL AND email_lookup_hmac IS NULL
            )
        $sql$ INTO v_incomplete;
        IF v_incomplete THEN
            RAISE EXCEPTION
                'Refusing PII finalization: employee email uniqueness fingerprints are incomplete';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai' AND table_name = 'employee'
          AND column_name = 'phone'
    ) THEN
        EXECUTE $sql$
            SELECT EXISTS (
                SELECT 1 FROM employee e
                JOIN employee_private_data p USING (employee_id)
                WHERE e.phone IS NOT NULL
                  AND (p.phone_ciphertext IS NULL OR p.phone_nonce IS NULL)
            )
        $sql$ INTO v_incomplete;
        IF v_incomplete THEN
            RAISE EXCEPTION 'Refusing PII finalization: employee phone envelopes are incomplete';
        END IF;
    END IF;

    -- Pending invitations intentionally have no Firebase identity yet.
    IF EXISTS (
        SELECT 1
        FROM app_user u
        JOIN employee e USING (employee_id)
        WHERE u.active AND e.active
          AND (u.firebase_uid IS NULL OR btrim(u.firebase_uid) = '')
    ) THEN
        RAISE EXCEPTION
            'Refusing PII finalization: every active app_user requires firebase_uid';
    END IF;
END;
$$;

-- Public API identity lookup is Firebase-only. Pending invitations are resolved
-- by fn_bootstrap_staff_context_by_token using an EMPLOYEE_INVITATION token.
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
    IF p_lookup <> 'FIREBASE_UID' THEN
        RETURN FALSE;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
      INTO v_user_id, v_company_id, v_store_id
    FROM app_user u
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE u.firebase_uid = p_identity
      AND u.active AND e.active AND s.active AND c.active AND r.active
      AND u.deleted_at IS NULL AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL;

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

DROP TRIGGER IF EXISTS trg_sync_app_user_cpf ON app_user;
DROP TRIGGER IF EXISTS trg_propagate_employee_cpf ON employee;
DROP FUNCTION IF EXISTS fn_sync_app_user_cpf();
DROP FUNCTION IF EXISTS fn_propagate_employee_cpf();

ALTER TABLE employee
    DROP CONSTRAINT IF EXISTS uq_employee_cpf,
    DROP CONSTRAINT IF EXISTS uq_employee_cpf_token,
    DROP CONSTRAINT IF EXISTS ck_employee_cpf_valid,
    DROP CONSTRAINT IF EXISTS ck_employee_cpf_protected,
    DROP CONSTRAINT IF EXISTS ck_employee_name_protected,
    DROP CONSTRAINT IF EXISTS ck_employee_email_protected,
    DROP CONSTRAINT IF EXISTS ck_employee_phone_protected;

ALTER TABLE app_user
    DROP CONSTRAINT IF EXISTS uq_app_user_cpf,
    DROP CONSTRAINT IF EXISTS uq_app_user_cpf_token,
    DROP CONSTRAINT IF EXISTS ck_app_user_cpf_valid,
    DROP CONSTRAINT IF EXISTS ck_app_user_cpf_protected,
    DROP CONSTRAINT IF EXISTS uq_app_user_email_token,
    DROP CONSTRAINT IF EXISTS ck_app_user_email_protected;

ALTER TABLE employee
    DROP COLUMN IF EXISTS name,
    DROP COLUMN IF EXISTS cpf,
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS phone;

ALTER TABLE app_user
    DROP COLUMN IF EXISTS cpf,
    DROP COLUMN IF EXISTS email;

ALTER TABLE app_user
    DROP CONSTRAINT IF EXISTS ck_app_user_active_firebase_uid;
ALTER TABLE app_user
    ADD CONSTRAINT ck_app_user_active_firebase_uid
    CHECK (NOT active OR (firebase_uid IS NOT NULL AND btrim(firebase_uid) <> ''));

COMMENT ON COLUMN app_user.firebase_uid IS
    'External authentication identity. Nullable only while an invitation is pending; active users require a value.';
