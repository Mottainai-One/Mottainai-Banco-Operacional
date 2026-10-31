-- Read-only checks for the physical design created by migration 16.
DO $$
DECLARE
    v_table TEXT;
    v_id_column TEXT;
    v_partition_column TEXT;
    v_relid REGCLASS;
    v_partitioned BOOLEAN;
    v_key_definition TEXT;
    v_expected_month TEXT;
BEGIN
    FOR v_table, v_id_column, v_partition_column IN
        SELECT * FROM (VALUES
            ('fact_inventory_count_line', 'inventory_count_item_id', 'count_date'),
            ('fact_transfer_line', 'transfer_item_id', 'request_date'),
            ('fact_replenishment_plan_line', 'pre_list_item_id', 'generated_at'),
            ('fact_replenishment_execution_line', 'execution_item_id', 'started_at'),
            ('fact_donation_line', 'donation_item_id', 'donation_date'),
            ('fact_disposal_line', 'disposal_item_id', 'disposal_date'),
            ('fact_alert_lifecycle', 'alert_id', 'generated_at'),
            ('fact_action_lifecycle', 'suggested_action_id', 'generated_at')
        ) AS facts(table_name, id_column, partition_column)
    LOOP
        v_relid := format('%I.%I', 'mottainai_analytics', v_table)::regclass;
        SELECT EXISTS (SELECT 1 FROM pg_partitioned_table WHERE partrelid = v_relid),
               pg_get_partkeydef(v_relid)
          INTO v_partitioned, v_key_definition;

        IF NOT v_partitioned OR v_key_definition <> format('RANGE (%I)', v_partition_column) THEN
            RAISE EXCEPTION '%.% must be partitioned by RANGE (%)',
                'mottainai_analytics', v_table, v_partition_column;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            WHERE c.conrelid = v_relid AND c.contype = 'p'
              AND pg_get_constraintdef(c.oid) = format('PRIMARY KEY (%I, %I)', v_id_column, v_partition_column)
        ) THEN
            RAISE EXCEPTION '%.% must use a composite primary key including its partition column',
                'mottainai_analytics', v_table;
        END IF;

        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_table || '_default')) IS NULL THEN
            RAISE EXCEPTION '%.% is missing its DEFAULT partition',
                'mottainai_analytics', v_table;
        END IF;

        v_expected_month := v_table || '_' || to_char(current_date, 'YYYY_MM');
        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_expected_month)) IS NULL THEN
            RAISE EXCEPTION '%.% is missing the current-month partition',
                'mottainai_analytics', v_table;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM mottainai_analytics.schema_version WHERE version = 15)
       OR NOT EXISTS (SELECT 1 FROM mottainai_analytics.schema_version WHERE version = 16) THEN
        RAISE EXCEPTION 'Analytics schema versions 15 and 16 must be recorded';
    END IF;
END;
$$;

SELECT 'Partitioned KPI fact checks passed' AS result;
