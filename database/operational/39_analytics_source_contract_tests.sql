-- Read-only regression checks for columns consumed by the analytics daily RPA.
-- Run against MOTTAINAI after installing operational migrations through 38.
DO $$
DECLARE
    v_table TEXT;
    v_column TEXT;
BEGIN
    FOR v_table, v_column IN
        SELECT * FROM (VALUES
            ('inventory_count_item', 'inventory_count_item_id'),
            ('inventory_count_item', 'inventory_count_id'),
            ('inventory_count_item', 'system_quantity'),
            ('inventory_count_item', 'counted_quantity'),
            ('inventory_count_item', 'deleted_at'),
            ('inventory_count', 'started_at'),
            ('inventory_count', 'finished_at'),
            ('inventory_count', 'status'),
            ('inventory_count', 'store_id'),
            ('inventory', 'inventory_id'),
            ('inventory', 'batch_id'),
            ('inventory', 'inventory_type'),
            ('inventory', 'current_quantity'),
            ('inventory', 'minimum_quantity'),
            ('inventory', 'deleted_at'),
            ('batch', 'batch_id'),
            ('batch', 'product_id'),
            ('batch', 'unit_cost'),
            ('batch', 'expiration_date'),
            ('transfer_item', 'transfer_item_id'),
            ('transfer_item', 'transfer_id'),
            ('transfer_item', 'batch_id'),
            ('transfer_item', 'transferred_quantity'),
            ('transfer', 'transfer_id'),
            ('transfer', 'request_date'),
            ('transfer', 'completion_date'),
            ('transfer', 'source_store_id'),
            ('transfer', 'destination_store_id'),
            ('transfer', 'suggested_action_id'),
            ('transfer', 'status'),
            ('replenishment_pre_list_item', 'pre_list_item_id'),
            ('replenishment_pre_list_item', 'pre_list_id'),
            ('replenishment_pre_list_item', 'product_id'),
            ('replenishment_pre_list_item', 'suggested_quantity'),
            ('replenishment_pre_list', 'pre_list_id'),
            ('replenishment_pre_list', 'store_id'),
            ('replenishment_pre_list', 'generated_at'),
            ('replenishment_pre_list', 'status'),
            ('replenishment_execution_item', 'execution_item_id'),
            ('replenishment_execution_item', 'execution_id'),
            ('replenishment_execution_item', 'batch_id'),
            ('replenishment_execution_item', 'replenished_quantity'),
            ('replenishment_execution', 'execution_id'),
            ('replenishment_execution', 'pre_list_id'),
            ('replenishment_execution', 'start_date'),
            ('replenishment_execution', 'end_date'),
            ('donation_item', 'donation_item_id'),
            ('donation_item', 'donation_id'),
            ('donation_item', 'batch_id'),
            ('donation_item', 'donated_quantity'),
            ('donation', 'donation_id'),
            ('donation', 'donation_date'),
            ('donation', 'store_id'),
            ('donation', 'suggested_action_id'),
            ('donation', 'status'),
            ('disposal_item', 'disposal_item_id'),
            ('disposal_item', 'disposal_id'),
            ('disposal_item', 'batch_id'),
            ('disposal_item', 'disposed_quantity'),
            ('disposal', 'disposal_id'),
            ('disposal', 'disposal_date'),
            ('disposal', 'store_id'),
            ('disposal', 'suggested_action_id'),
            ('alert', 'alert_id'),
            ('alert', 'store_id'),
            ('alert', 'alert_type'),
            ('alert', 'priority'),
            ('alert', 'status'),
            ('alert', 'generated_at'),
            ('alert', 'resolved_at'),
            ('alert', 'updated_at'),
            ('suggested_action', 'suggested_action_id'),
            ('suggested_action', 'alert_id'),
            ('suggested_action', 'action_type'),
            ('suggested_action', 'status'),
            ('suggested_action', 'generated_at'),
            ('suggested_action', 'source_recommendation_uuid'),
            ('suggested_action', 'updated_at')
        ) AS contract(table_name, column_name)
    LOOP
        IF to_regclass(format('%I.%I', 'mottainai', v_table)) IS NULL THEN
            RAISE EXCEPTION 'Analytics source table mottainai.% is missing', v_table;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'mottainai'
              AND table_name = v_table
              AND column_name = v_column
        ) THEN
            RAISE EXCEPTION 'Analytics source column mottainai.%.% is missing', v_table, v_column;
        END IF;
    END LOOP;
END;
$$;

SELECT 'Analytics source contract checks passed' AS result;
