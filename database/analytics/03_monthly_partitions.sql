SET search_path TO mottainai_analytics, public;

-- Particionamento mensal somente para os fatos de maior volume. As tabelas de
-- menor volume permanecem simples para evitar centenas de particoes vazias no
-- inicio do projeto.
CREATE OR REPLACE FUNCTION sp_create_monthly_fact_partitions(
    p_months_back INTEGER DEFAULT 12,
    p_months_ahead INTEGER DEFAULT 6
)
RETURNS VOID AS $$
DECLARE
    v_month DATE;
    v_table TEXT;
    v_partition_name TEXT;
    v_tables CONSTANT TEXT[] := ARRAY[
        'fact_sales',
        'fact_sale_item',
        'fact_inventory_movement',
        'fact_inventory_snapshot'
    ];
BEGIN
    IF p_months_back < 0 OR p_months_ahead < 0 THEN
        RAISE EXCEPTION 'Partition month ranges cannot be negative';
    END IF;

    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - make_interval(months => p_months_back),
                date_trunc('month', current_date) + make_interval(months => p_months_ahead),
                interval '1 month'
            )::date
        LOOP
            v_partition_name := v_table || '_' || to_char(v_month, 'YYYY_MM');

            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I '
                || 'FOR VALUES FROM (%L) TO (%L)',
                'mottainai_analytics', v_partition_name,
                'mottainai_analytics', v_table,
                v_month, (v_month + interval '1 month')::date
            );
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT sp_create_monthly_fact_partitions(12, 6);
