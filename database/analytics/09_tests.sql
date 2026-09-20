DO $$
DECLARE
    required_table TEXT;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'dim_date', 'dim_product', 'fact_sales', 'fact_inventory_snapshot',
        'ai_model', 'ai_recommendation', 'ingestion_event', 'etl_checkpoint'
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
END $$;
