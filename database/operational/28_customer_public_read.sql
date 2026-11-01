-- Read-only, curated business information for the customer chat.
-- SECURITY DEFINER avoids granting direct SELECT on operational tables protected by staff RLS.
CREATE OR REPLACE FUNCTION fn_customer_public_stores(p_company_id INTEGER)
RETURNS TABLE (store_id INTEGER, store_name VARCHAR, latitude NUMERIC, longitude NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = mottainai, pg_temp
AS $$
    SELECT s.store_id, s.name, s.latitude, s.longitude
    FROM mottainai.retail_store AS s
    WHERE s.company_id = p_company_id AND s.active = TRUE AND s.deleted_at IS NULL
    ORDER BY s.name;
$$;

CREATE OR REPLACE FUNCTION fn_customer_active_promotions(p_company_id INTEGER)
RETURNS TABLE (
    promotion_id INTEGER, store_name VARCHAR, promotion_name VARCHAR, description TEXT,
    starts_at TIMESTAMP, ends_at TIMESTAMP, product_name VARCHAR,
    original_price NUMERIC, promotional_price NUMERIC, discount_percent NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = mottainai, pg_temp
AS $$
    SELECT p.promotion_id, s.name, p.name, p.description, p.starts_at, p.ends_at,
           pr.name, pi.original_price, pi.promotional_price, pi.discount_percent
    FROM mottainai.promotion AS p
    JOIN mottainai.retail_store AS s ON s.store_id = p.store_id
    JOIN mottainai.promotion_item AS pi ON pi.promotion_id = p.promotion_id
    JOIN mottainai.product AS pr ON pr.product_id = pi.product_id
    WHERE s.company_id = p_company_id AND s.active = TRUE AND s.deleted_at IS NULL
      AND p.active = TRUE AND p.status = 'APPROVED' AND p.deleted_at IS NULL
      AND p.starts_at <= CURRENT_TIMESTAMP AND p.ends_at > CURRENT_TIMESTAMP
      AND pr.active = TRUE AND pr.deleted_at IS NULL
    ORDER BY p.ends_at, s.name, p.name, pr.name;
$$;

REVOKE ALL ON FUNCTION fn_customer_public_stores(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_customer_active_promotions(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_customer_public_stores(INTEGER) TO mottainai_customer_api;
GRANT EXECUTE ON FUNCTION fn_customer_active_promotions(INTEGER) TO mottainai_customer_api;
