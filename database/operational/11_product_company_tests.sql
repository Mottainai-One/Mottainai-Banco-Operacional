-- ====================================================================
-- PRODUCT OWNERSHIP BY COMPANY - STRUCTURAL TESTS
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_count INTEGER;
    v_policy_qual TEXT;
    v_policy_check TEXT;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'product'
      AND column_name = 'company_id'
      AND is_nullable = 'NO';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'product.company_id must exist and be NOT NULL';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_constraint
    WHERE conrelid = 'mottainai.product'::REGCLASS
      AND conname = 'fk_product_company'
      AND contype = 'f'
      AND confrelid = 'mottainai.company'::REGCLASS
      AND confdeltype = 'r';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'fk_product_company must reference company with ON DELETE RESTRICT';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'mottainai'
      AND tablename = 'product'
      AND indexname = 'idx_product_company_id';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'idx_product_company_id is missing';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_constraint
    WHERE conrelid = 'mottainai.product'::REGCLASS
      AND conname IN ('uq_product_company_sku', 'uq_product_company_barcode')
      AND contype = 'u';

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Company-scoped SKU and barcode unique constraints are missing';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_constraint c
    WHERE c.conrelid = 'mottainai.product'::REGCLASS
      AND c.contype = 'u'
      AND cardinality(c.conkey) = 1
      AND (
          SELECT a.attname
          FROM pg_attribute a
          WHERE a.attrelid = c.conrelid
            AND a.attnum = c.conkey[1]
      ) IN ('sku', 'barcode');

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Global single-column uniqueness still exists on product SKU or barcode';
    END IF;

    SELECT qual, with_check
    INTO v_policy_qual, v_policy_check
    FROM pg_policies
    WHERE schemaname = 'mottainai'
      AND tablename = 'product'
      AND policyname = 'product_policy';

    IF v_policy_qual IS NULL
       OR v_policy_check IS NULL
       OR position('fn_get_current_company_id' IN v_policy_qual) = 0
       OR position('fn_get_current_company_id' IN v_policy_check) = 0 THEN
        RAISE EXCEPTION 'product_policy must filter and validate company_id';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'mottainai'
      AND p.proname = 'fn_generate_sku'
      AND pg_get_function_identity_arguments(p.oid) =
          'p_company_id integer, p_product_name character varying, p_category_name character varying, p_brand character varying';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Company-aware fn_generate_sku overload is missing';
    END IF;

    RAISE NOTICE 'Product ownership by company tests passed';
END;
$$;
