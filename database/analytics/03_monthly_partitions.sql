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
    v_partition_column TEXT;
    v_partition_name TEXT;
    v_has_default_rows BOOLEAN;
    v_tables CONSTANT TEXT[] := ARRAY[
        'fact_sales',
        'fact_sale_item',
        'fact_inventory_movement',
        'fact_inventory_snapshot',
        'fact_inventory_count_line',
        'fact_transfer_line',
        'fact_replenishment_plan_line',
        'fact_replenishment_execution_line',
        'fact_donation_line',
        'fact_disposal_line',
        'fact_alert_lifecycle',
        'fact_action_lifecycle'
    ];
BEGIN
    IF p_months_back < 0 OR p_months_ahead < 0 THEN
        RAISE EXCEPTION 'Partition month ranges cannot be negative';
    END IF;

    FOREACH v_table IN ARRAY v_tables
    LOOP
        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_table)) IS NULL THEN
            CONTINUE;
        END IF;

        v_partition_column := CASE v_table
            WHEN 'fact_sales' THEN 'sale_date'
            WHEN 'fact_sale_item' THEN 'sale_date'
            WHEN 'fact_inventory_movement' THEN 'movement_date'
            WHEN 'fact_inventory_snapshot' THEN 'snapshot_date'
            WHEN 'fact_inventory_count_line' THEN 'count_date'
            WHEN 'fact_transfer_line' THEN 'request_date'
            WHEN 'fact_replenishment_plan_line' THEN 'generated_at'
            WHEN 'fact_replenishment_execution_line' THEN 'started_at'
            WHEN 'fact_donation_line' THEN 'donation_date'
            WHEN 'fact_disposal_line' THEN 'disposal_date'
            WHEN 'fact_alert_lifecycle' THEN 'generated_at'
            WHEN 'fact_action_lifecycle' THEN 'generated_at'
        END;

        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - make_interval(months => p_months_back),
                date_trunc('month', current_date) + make_interval(months => p_months_ahead),
                interval '1 month'
            )::date
        LOOP
            v_partition_name := v_table || '_' || to_char(v_month, 'YYYY_MM');

            -- Keep late/out-of-window rows in the default partition. PostgreSQL
            -- refuses a new range partition when its default already contains
            -- matching rows, so leave that month there until it can be moved
            -- during a maintenance window.
            IF to_regclass(format('%I.%I', 'mottainai_analytics', v_table || '_default')) IS NOT NULL THEN
                EXECUTE format(
                    'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I >= $1 AND %I < $2 LIMIT 1)',
                    'mottainai_analytics', v_table || '_default',
                    v_partition_column, v_partition_column
                ) INTO STRICT v_has_default_rows USING
                    v_month,
                    (v_month + interval '1 month')::date;
                IF v_has_default_rows THEN
                    CONTINUE;
                END IF;
            END IF;

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
$$ LANGUAGE plpgsql
SET timezone TO 'UTC';

SELECT sp_create_monthly_fact_partitions(12, 6);
