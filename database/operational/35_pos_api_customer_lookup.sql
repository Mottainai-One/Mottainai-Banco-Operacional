-- Expose only the customer ID lookup required by the POS.
-- The Firebase UID arrives as its AUTH_SHA256 token; no PII is returned.
BEGIN;

CREATE OR REPLACE FUNCTION mottainai.fn_pos_find_customer_by_auth_token(
    p_auth_token TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_customer_id INTEGER;
BEGIN
    IF mottainai.fn_get_current_user_id() IS NULL
       OR mottainai.fn_get_current_store_id() IS NULL
       OR NOT mottainai.fn_is_sha256_token(p_auth_token, 'AUTH') THEN
        RETURN NULL;
    END IF;

    SELECT customer.customer_id INTO v_customer_id
      FROM mottainai.customer AS customer
     WHERE customer.external_auth_uid = p_auth_token
       AND customer.active
       AND customer.deleted_at IS NULL;

    RETURN v_customer_id;
END;
$$;

REVOKE ALL
    ON FUNCTION mottainai.fn_pos_find_customer_by_auth_token(TEXT)
    FROM PUBLIC;
GRANT EXECUTE
    ON FUNCTION mottainai.fn_pos_find_customer_by_auth_token(TEXT)
    TO mottainai_api;

COMMIT;
