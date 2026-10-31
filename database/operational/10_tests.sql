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
        ('password_reset_token'), ('event_queue'),
        ('customer_private_data')
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

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'app_user'
          AND column_name = 'cpf'
    ) THEN
        RAISE EXCEPTION 'Legacy app_user.cpf must be removed after AES-GCM finalization';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'employee_private_data'
          AND column_name = 'cpf_ciphertext'
    ) THEN
        RAISE EXCEPTION 'employee_private_data.cpf_ciphertext is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'customer_private_data'
          AND column_name = 'deleted_at'
    ) THEN
        RAISE EXCEPTION 'customer_private_data.deleted_at is required for logical deletion';
    END IF;

    IF has_table_privilege('mottainai_api', 'mottainai.customer_private_data', 'DELETE') THEN
        RAISE EXCEPTION 'mottainai_api must not physically delete customer private data';
    END IF;

    IF has_table_privilege('mottainai_customer_api', 'mottainai.customer_private_data', 'DELETE') THEN
        RAISE EXCEPTION 'mottainai_customer_api must not physically delete customer private data';
    END IF;

    IF NOT has_table_privilege('mottainai_api', 'mottainai.customer_private_data', 'SELECT') THEN
        RAISE EXCEPTION 'mottainai_api needs permission-scoped SELECT for authorized staff reads';
    END IF;

    IF NOT (
        SELECT relrowsecurity AND relforcerowsecurity
        FROM pg_class
        WHERE oid = 'mottainai.customer_private_data'::regclass
    ) THEN
        RAISE EXCEPTION 'customer_private_data must enable and force row-level security';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'mottainai.customer_private_data'::regclass
          AND polname = 'customer_private_data_staff_select_policy'
          AND polcmd = 'r'
    ) THEN
        RAISE EXCEPTION 'Permission-scoped staff SELECT policy is missing';
    END IF;

    IF NOT has_column_privilege(
        'mottainai_api', 'mottainai.customer_private_data', 'deleted_at', 'UPDATE'
    ) THEN
        RAISE EXCEPTION 'mottainai_api needs column-scoped UPDATE to perform logical deletion';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'mottainai.customer'::regclass
          AND tgname = 'trg_mark_customer_private_data_deleted'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Customer inactivation must logically delete the private-data envelope';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'mottainai.customer_private_data'::regclass
          AND conname = 'fk_customer_private_data_customer'
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'Customer private-data foreign key must restrict physical deletion';
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
