-- Makes the existing staff bootstrap function explicitly fail closed for
-- unsupported or NULL lookup types. The API must validate Firebase tokens before
-- calling this function with FIREBASE_UID.
-- This migration preserves the function signature, owner, existing ACLs and RLS.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $guard$
BEGIN
    IF upper(current_database()) NOT IN ('MOTTAINAI', 'MOTTAINAI_QA', 'MOTTAINAI_MANAGED') THEN
        RAISE EXCEPTION
            'Connect to MOTTAINAI (or isolated MOTTAINAI_QA/MOTTAINAI_MANAGED for CI); current database: %',
            current_database();
    END IF;
    IF to_regprocedure('mottainai.fn_bootstrap_staff_context(text,text)') IS NULL THEN
        RAISE EXCEPTION 'Apply the staff identity schema before this migration';
    END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION mottainai.fn_bootstrap_staff_context(
    p_identity TEXT,
    p_lookup TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $function$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_lookup IS DISTINCT FROM 'FIREBASE_UID'
       OR p_identity IS NULL
       OR btrim(p_identity) = '' THEN
        RETURN FALSE;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
      INTO v_user_id, v_company_id, v_store_id
    FROM mottainai.app_user AS u
    JOIN mottainai.employee AS e ON e.employee_id = u.employee_id
    JOIN mottainai.retail_store AS s ON s.store_id = e.store_id
    JOIN mottainai.company AS c ON c.company_id = s.company_id
    JOIN mottainai.employee_role AS r ON r.role_id = e.role_id
    WHERE u.firebase_uid = p_identity
      AND u.active IS TRUE
      AND e.active IS TRUE
      AND s.active IS TRUE
      AND c.active IS TRUE
      AND r.active IS TRUE
      AND u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN TRUE;
END;
$function$;

COMMIT;
