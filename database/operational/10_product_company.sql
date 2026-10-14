-- ====================================================================
-- PRODUCT OWNERSHIP BY COMPANY
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

-- Add the nullable column first so existing rows can be migrated safely.
ALTER TABLE product
    ADD COLUMN IF NOT EXISTS company_id INTEGER;

-- Infer the owning company from every store-scoped relationship currently
-- available. A product used by more than one company cannot be assigned
-- automatically because the new model requires one owner per product.
DROP TABLE IF EXISTS pg_temp.product_company_candidate;

CREATE TEMPORARY TABLE product_company_candidate AS
SELECT DISTINCT source.product_id, source.company_id
FROM (
    SELECT spp.product_id, rs.company_id
    FROM store_product_price spp
    JOIN retail_store rs ON rs.store_id = spp.store_id

    UNION ALL

    SELECT b.product_id, rs.company_id
    FROM inventory i
    JOIN batch b ON b.batch_id = i.batch_id
    JOIN retail_store rs ON rs.store_id = i.store_id

    UNION ALL

    SELECT poi.product_id, rs.company_id
    FROM purchase_order_item poi
    JOIN purchase_order po
      ON po.purchase_order_id = poi.purchase_order_id
     AND po.order_date = poi.order_date
    JOIN retail_store rs ON rs.store_id = po.store_id

    UNION ALL

    SELECT si.product_id, rs.company_id
    FROM sale_item si
    JOIN sales_transaction st
      ON st.sale_id = si.sale_id
     AND st.sale_date = si.sale_date
    JOIN retail_store rs ON rs.store_id = st.store_id

    UNION ALL

    SELECT pi.product_id, rs.company_id
    FROM promotion_item pi
    JOIN promotion p ON p.promotion_id = pi.promotion_id
    JOIN retail_store rs ON rs.store_id = p.store_id

    UNION ALL

    SELECT rpli.product_id, rs.company_id
    FROM replenishment_pre_list_item rpli
    JOIN replenishment_pre_list rpl ON rpl.pre_list_id = rpli.pre_list_id
    JOIN retail_store rs ON rs.store_id = rpl.store_id
) AS source;

DO $$
DECLARE
    v_conflicting_products TEXT;
BEGIN
    SELECT string_agg(conflict.product_id::TEXT, ', ' ORDER BY conflict.product_id)
    INTO v_conflicting_products
    FROM (
        SELECT candidate.product_id
        FROM product_company_candidate candidate
        GROUP BY candidate.product_id
        HAVING COUNT(DISTINCT candidate.company_id) > 1
    ) AS conflict;

    IF v_conflicting_products IS NOT NULL THEN
        RAISE EXCEPTION
            'Cannot assign product.company_id automatically. Products associated with more than one company: %',
            v_conflicting_products
            USING HINT = 'Duplicate these product records per company and repoint their operational references before rerunning this migration.';
    END IF;

    SELECT string_agg(p.product_id::TEXT, ', ' ORDER BY p.product_id)
    INTO v_conflicting_products
    FROM product p
    JOIN product_company_candidate candidate ON candidate.product_id = p.product_id
    WHERE p.company_id IS NOT NULL
      AND p.company_id <> candidate.company_id;

    IF v_conflicting_products IS NOT NULL THEN
        RAISE EXCEPTION
            'Existing product.company_id conflicts with store-scoped data for products: %',
            v_conflicting_products;
    END IF;
END;
$$;

UPDATE product p
SET company_id = candidate.company_id
FROM (
    SELECT product_id, MIN(company_id) AS company_id
    FROM product_company_candidate
    GROUP BY product_id
    HAVING COUNT(DISTINCT company_id) = 1
) AS candidate
WHERE p.product_id = candidate.product_id
  AND p.company_id IS NULL;

-- If the database has only one company, unreferenced catalog products can be
-- assigned without ambiguity. With multiple companies, explicit mapping is
-- required instead of guessing ownership.
DO $$
DECLARE
    v_company_count INTEGER;
    v_only_company_id INTEGER;
    v_unassigned_products TEXT;
BEGIN
    SELECT COUNT(*), MIN(company_id)
    INTO v_company_count, v_only_company_id
    FROM company;

    IF v_company_count = 1 THEN
        UPDATE product
        SET company_id = v_only_company_id
        WHERE company_id IS NULL;
    END IF;

    SELECT string_agg(product_id::TEXT, ', ' ORDER BY product_id)
    INTO v_unassigned_products
    FROM product
    WHERE company_id IS NULL;

    IF v_unassigned_products IS NOT NULL THEN
        RAISE EXCEPTION
            'Products still require an explicit company_id: %',
            v_unassigned_products
            USING HINT = 'Populate product.company_id with the owning company before rerunning this migration.';
    END IF;
END;
$$;

DROP TABLE product_company_candidate;

ALTER TABLE product
    ALTER COLUMN company_id SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'mottainai.product'::REGCLASS
          AND conname = 'fk_product_company'
    ) THEN
        ALTER TABLE product
            ADD CONSTRAINT fk_product_company
            FOREIGN KEY (company_id)
            REFERENCES company(company_id)
            ON DELETE RESTRICT;
    END IF;
END;
$$;

-- Replace global uniqueness with tenant-scoped uniqueness.
ALTER TABLE product DROP CONSTRAINT IF EXISTS product_sku_key;
ALTER TABLE product DROP CONSTRAINT IF EXISTS product_barcode_key;

DO $$
DECLARE
    v_constraint RECORD;
BEGIN
    FOR v_constraint IN
        SELECT c.conname
        FROM pg_constraint c
        WHERE c.conrelid = 'mottainai.product'::REGCLASS
          AND c.contype = 'u'
          AND cardinality(c.conkey) = 1
          AND (
              SELECT a.attname
              FROM pg_attribute a
              WHERE a.attrelid = c.conrelid
                AND a.attnum = c.conkey[1]
          ) IN ('sku', 'barcode')
    LOOP
        EXECUTE format(
            'ALTER TABLE mottainai.product DROP CONSTRAINT %I',
            v_constraint.conname
        );
    END LOOP;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'mottainai.product'::REGCLASS
          AND conname = 'uq_product_company_sku'
    ) THEN
        ALTER TABLE product
            ADD CONSTRAINT uq_product_company_sku UNIQUE (company_id, sku);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'mottainai.product'::REGCLASS
          AND conname = 'uq_product_company_barcode'
    ) THEN
        ALTER TABLE product
            ADD CONSTRAINT uq_product_company_barcode UNIQUE (company_id, barcode);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_product_company_id
    ON product(company_id);

COMMENT ON COLUMN product.company_id IS
    'Owning company. A company has many products and each product belongs to exactly one company.';

-- Generate SKUs within one company namespace.
CREATE OR REPLACE FUNCTION fn_generate_sku(
    p_company_id INTEGER,
    p_product_name VARCHAR(150),
    p_category_name VARCHAR(100),
    p_brand VARCHAR(100)
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_sku VARCHAR(50);
    v_counter INTEGER := 0;
    v_base_sku VARCHAR(40);
    v_words TEXT[];
    v_word VARCHAR(50);
    v_abbr VARCHAR(50) := '';
    v_suffix VARCHAR(10);
BEGIN
    IF p_company_id IS NULL THEN
        RAISE EXCEPTION 'company_id is required to generate a product SKU';
    END IF;

    v_words := string_to_array(trim(regexp_replace(p_product_name, '[^a-zA-Z0-9 ]', '', 'g')), ' ');

    IF array_length(v_words, 1) >= 3 THEN
        FOR i IN 1..3 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 1));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSIF array_length(v_words, 1) = 2 THEN
        FOR i IN 1..2 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 3));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSE
        v_abbr := UPPER(SUBSTRING(p_product_name, 1, 6));
    END IF;

    IF p_category_name IS NOT NULL AND p_category_name <> '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_category_name, 1, 2));
    END IF;

    IF p_brand IS NOT NULL AND p_brand <> '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_brand, 1, 2));
    END IF;

    v_abbr := regexp_replace(v_abbr, '[^A-Z0-9-]', '', 'g');

    IF LENGTH(v_abbr) < 4 THEN
        v_abbr := v_abbr || LPAD('X', 6 - LENGTH(v_abbr), 'X');
    END IF;

    v_base_sku := SUBSTRING(v_abbr, 1, 30);

    LOOP
        v_suffix := CASE
            WHEN v_counter > 0 THEN '-' || TO_CHAR(v_counter, 'FM000')
            ELSE ''
        END;
        v_sku := v_base_sku || v_suffix;

        IF NOT EXISTS (
            SELECT 1
            FROM product
            WHERE company_id = p_company_id
              AND sku = v_sku
        ) THEN
            RETURN v_sku;
        END IF;

        v_counter := v_counter + 1;

        IF v_counter > 999 THEN
            RETURN 'SKU-' || TO_CHAR(clock_timestamp(), 'YYYYMMDD-HH24MISS-US');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Compatibility wrapper for callers that already set the tenant context.
CREATE OR REPLACE FUNCTION fn_generate_sku(
    p_product_name VARCHAR(150),
    p_category_name VARCHAR(100),
    p_brand VARCHAR(100) DEFAULT NULL
) RETURNS VARCHAR(50) AS $$
BEGIN
    RETURN fn_generate_sku(
        fn_get_current_company_id(),
        p_product_name,
        p_category_name,
        p_brand
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_generate_product_sku(
    p_product_id INTEGER
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_company_id INTEGER;
    v_product_name VARCHAR(150);
    v_category_name VARCHAR(100);
    v_brand VARCHAR(100);
BEGIN
    SELECT p.company_id, p.name, pc.name, p.brand
    INTO v_company_id, v_product_name, v_category_name, v_brand
    FROM product p
    JOIN product_category pc ON pc.category_id = p.category_id
    WHERE p.product_id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % does not exist', p_product_id;
    END IF;

    RETURN fn_generate_sku(
        v_company_id,
        v_product_name,
        v_category_name,
        v_brand
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_trg_generate_sku()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF NEW.company_id IS NULL THEN
        RAISE EXCEPTION 'product.company_id is required';
    END IF;

    IF NEW.sku IS NULL OR NEW.sku = '' OR EXISTS (
        SELECT 1
        FROM product p
        WHERE p.company_id = NEW.company_id
          AND p.sku = NEW.sku
          AND p.product_id IS DISTINCT FROM NEW.product_id
    ) THEN
        SELECT name
        INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(
            NEW.company_id,
            NEW.name,
            v_category_name,
            NEW.brand
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_trg_update_sku_on_change()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    SELECT name
    INTO v_category_name
    FROM product_category
    WHERE category_id = NEW.category_id;

    NEW.sku := fn_generate_sku(
        NEW.company_id,
        NEW.name,
        v_category_name,
        NEW.brand
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_product_update_sku ON product;

CREATE TRIGGER trg_product_update_sku
    BEFORE UPDATE ON product
    FOR EACH ROW
    WHEN (OLD.name IS DISTINCT FROM NEW.name OR
          OLD.category_id IS DISTINCT FROM NEW.category_id OR
          OLD.brand IS DISTINCT FROM NEW.brand OR
          OLD.company_id IS DISTINCT FROM NEW.company_id)
    EXECUTE FUNCTION fn_trg_update_sku_on_change();

-- Product is now a tenant-owned entity and must be filtered by company.
ALTER TABLE product ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_policy ON product;

CREATE POLICY product_policy ON product
    FOR ALL
    USING (company_id = fn_get_current_company_id())
    WITH CHECK (company_id = fn_get_current_company_id());

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '11',
    'Assign every product to one company and enforce tenant isolation',
    'SQL',
    '10_product_company.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
