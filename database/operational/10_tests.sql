SET search_path TO mottainai, public;

DO $$
DECLARE
    v_missing TEXT[];
BEGIN
    SELECT array_agg(required.name)
    INTO v_missing
    FROM (VALUES
        ('product'), ('inventory'), ('sales_transaction'),
        ('store_product_price'), ('inventory_count'),
        ('password_reset_token'), ('event_queue')
    ) AS required(name)
    WHERE to_regclass('mottainai.' || required.name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Operational installation missing tables: %', v_missing;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'mottainai' AND table_name LIKE 'ai_%'
    ) THEN
        RAISE EXCEPTION 'AI tables must not be installed in the operational database';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'base_price'
    ) THEN
        RAISE EXCEPTION 'Column product.base_price required by the API is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'app_user'
          AND column_name = 'cpf'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Column app_user.cpf is missing or nullable';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        WHERE namespace.nspname = 'mottainai'
          AND parent.relname IN (
              'purchase_order', 'inventory_movement',
              'sales_transaction', 'audit_log'
          )
    ) < 76 THEN
        RAISE EXCEPTION 'Monthly operational partitions were not created';
    END IF;
END;
$$;
