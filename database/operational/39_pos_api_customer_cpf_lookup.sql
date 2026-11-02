-- Expose only the customer ID needed by the POS after server-side CPF hashing.
-- The PostgreSQL API role never receives the raw CPF.
BEGIN;

CREATE OR REPLACE FUNCTION mottainai.fn_pos_find_customer_by_cpf_token(
    p_cpf_token TEXT
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
       OR NOT mottainai.fn_is_sha256_token(p_cpf_token, 'CPF') THEN
        RETURN NULL;
    END IF;

    SELECT customer.customer_id INTO v_customer_id
      FROM mottainai.customer AS customer
     WHERE customer.cpf = p_cpf_token
       AND customer.active IS TRUE
       AND customer.deleted_at IS NULL;

    RETURN v_customer_id;
END;
$$;

REVOKE ALL
    ON FUNCTION mottainai.fn_pos_find_customer_by_cpf_token(TEXT)
    FROM PUBLIC;
GRANT EXECUTE
    ON FUNCTION mottainai.fn_pos_find_customer_by_cpf_token(TEXT)
    TO mottainai_api;

COMMIT;
