DO $$
DECLARE
    required_table TEXT;
    partitioned_table TEXT;
    current_partition_bound TEXT;
    current_month DATE := date_trunc('month', current_date)::date;
    next_month DATE := (date_trunc('month', current_date) + interval '1 month')::date;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'dim_date', 'dim_product', 'fact_sales', 'fact_inventory_snapshot',
        'fact_transfer', 'ai_model', 'ai_recommendation',
        'ingestion_event', 'etl_checkpoint'
    ]
    LOOP
        IF to_regclass('mottainai_analytics.' || required_table) IS NULL THEN
            RAISE EXCEPTION 'Tabela analitica obrigatoria ausente: %', required_table;
        END IF;
    END LOOP;

    IF to_regclass('mottainai_analytics.inventory') IS NOT NULL
       OR to_regclass('mottainai_analytics.sales_transaction') IS NOT NULL THEN
        RAISE EXCEPTION 'Tabelas transacionais nao devem existir no banco analitico';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai_analytics'
          AND table_name = 'dim_customer'
          AND column_name IN ('cpf', 'email', 'phone', 'full_name')
    ) THEN
        RAISE EXCEPTION 'A dimensao de cliente contem dados pessoais desnecessarios';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        WHERE namespace.nspname = 'mottainai_analytics'
          AND parent.relname IN (
              'fact_sales', 'fact_sale_item',
              'fact_inventory_movement', 'fact_inventory_snapshot'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM pg_class child
              WHERE child.oid = inheritance.inhrelid
                AND child.relname LIKE '%_default'
          )
    ) < 76 THEN
        RAISE EXCEPTION 'Monthly analytical partitions were not created';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai_analytics'
          AND table_name = 'fact_transfer'
          AND column_name = 'destination_store_id'
    ) THEN
        RAISE EXCEPTION 'fact_transfer definition is incomplete';
    END IF;

    FOREACH partitioned_table IN ARRAY ARRAY[
        'fact_sales', 'fact_sale_item',
        'fact_inventory_movement', 'fact_inventory_snapshot'
    ]
    LOOP
        SELECT pg_get_expr(child.relpartbound, child.oid)
        INTO current_partition_bound
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        WHERE namespace.nspname = 'mottainai_analytics'
          AND parent.relname = partitioned_table
          AND child.relname = partitioned_table || '_' || to_char(current_month, 'YYYY_MM');

        IF current_partition_bound IS NULL
           OR position(current_month::text IN current_partition_bound) = 0
           OR position(next_month::text IN current_partition_bound) = 0 THEN
            RAISE EXCEPTION 'Invalid current-month partition bound for %: %',
                partitioned_table, current_partition_bound;
        END IF;
    END LOOP;
END $$;
