-- Convert the event facts from migration 15 to monthly range-partitioned tables.
-- Existing rows are copied transactionally. Late or out-of-window dates use a
-- DEFAULT partition, so the daily RPA does not fail on old or future events.
BEGIN;
SET LOCAL search_path TO mottainai_analytics, public;
SET LOCAL TIME ZONE 'UTC';

DO $$
BEGIN
    IF current_database() IN ('MOTTAINAI', 'mottainai_operational', 'mottainai') THEN
        RAISE EXCEPTION 'Connect to MOTTAINAI_ANALITICO before migration 16';
    END IF;
    IF to_regclass('mottainai_analytics.schema_version') IS NULL
       OR to_regclass('mottainai_analytics.fact_inventory_count_line') IS NULL THEN
        RAISE EXCEPTION 'Apply analytics base schema and migration 15 before migration 16';
    END IF;
END;
$$;

DO $$
DECLARE
    v_table TEXT;
    v_id_column TEXT;
    v_partition_column TEXT;
    v_new_table TEXT;
    v_old_table TEXT;
    v_relkind "char";
    v_month DATE;
    v_columns TEXT;
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
        SELECT c.relkind INTO v_relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'mottainai_analytics' AND c.relname = v_table;

        IF v_relkind = 'p' THEN
            CONTINUE;
        END IF;
        IF v_relkind IS DISTINCT FROM 'r' THEN
            RAISE EXCEPTION 'Expected ordinary table mottainai_analytics.% from migration 15', v_table;
        END IF;

        v_new_table := v_table || '__partitioned_16';
        v_old_table := v_table || '__before_partition_16';
        IF to_regclass(format('%I.%I', 'mottainai_analytics', v_new_table)) IS NOT NULL
           OR to_regclass(format('%I.%I', 'mottainai_analytics', v_old_table)) IS NOT NULL THEN
            RAISE EXCEPTION 'Unexpected partial migration artifacts for %', v_table;
        END IF;

        EXECUTE format(
            'CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS '
            || 'INCLUDING GENERATED INCLUDING STORAGE INCLUDING COMMENTS) PARTITION BY RANGE (%I)',
            'mottainai_analytics', v_new_table,
            'mottainai_analytics', v_table,
            v_partition_column
        );
        EXECUTE format(
            'ALTER TABLE %I.%I ADD CONSTRAINT %I PRIMARY KEY (%I, %I)',
            'mottainai_analytics', v_new_table,
            v_new_table || '_pkey', v_id_column, v_partition_column
        );

        FOR v_month IN
            SELECT generate_series(
                date_trunc('month', current_date) - interval '12 months',
                date_trunc('month', current_date) + interval '6 months',
                interval '1 month'
            )::date
        LOOP
            EXECUTE format(
                'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                'mottainai_analytics', v_table || '_' || to_char(v_month, 'YYYY_MM'),
                'mottainai_analytics', v_new_table,
                v_month, (v_month + interval '1 month')::date
            );
        END LOOP;

        EXECUTE format(
            'CREATE TABLE %I.%I PARTITION OF %I.%I DEFAULT',
            'mottainai_analytics', v_table || '_default',
            'mottainai_analytics', v_new_table
        );

        SELECT string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum)
        INTO v_columns
        FROM pg_attribute a
        WHERE a.attrelid = format('%I.%I', 'mottainai_analytics', v_table)::regclass
          AND a.attnum > 0 AND NOT a.attisdropped;

        EXECUTE format(
            'INSERT INTO %I.%I (%s) SELECT %s FROM %I.%I',
            'mottainai_analytics', v_new_table, v_columns, v_columns,
            'mottainai_analytics', v_table
        );

        EXECUTE format('ALTER TABLE %I.%I RENAME TO %I',
            'mottainai_analytics', v_table, v_old_table);
        EXECUTE format('ALTER TABLE %I.%I RENAME TO %I',
            'mottainai_analytics', v_new_table, v_table);
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW vw_inventory_count_accuracy AS
SELECT count_date, store_id,
       count(*) AS counted_positions,
       count(*) FILTER (WHERE counted_quantity = system_quantity) AS matching_positions,
       round(count(*) FILTER (WHERE counted_quantity = system_quantity)::numeric / nullif(count(*), 0), 4) AS accuracy_rate,
       sum(abs(counted_quantity - system_quantity)) AS absolute_quantity_difference,
       CASE WHEN count(*) FILTER (WHERE unit_cost IS NULL) > 0 THEN NULL
            ELSE sum(abs(counted_quantity - system_quantity) * unit_cost) END AS absolute_difference_value,
       count(*) FILTER (WHERE unit_cost IS NULL) AS positions_without_cost
FROM fact_inventory_count_line
WHERE status = 'COMPLETED'
GROUP BY count_date, store_id;

CREATE OR REPLACE VIEW vw_transfer_execution AS
SELECT request_date, source_store_id, destination_store_id,
       count(DISTINCT transfer_id) AS transfers_with_items,
       count(DISTINCT transfer_id) FILTER (WHERE status = 'COMPLETED') AS completed_transfers,
       sum(transferred_quantity) AS requested_item_quantity,
       sum(transferred_quantity) FILTER (WHERE status = 'COMPLETED') AS completed_item_quantity,
       avg(extract(epoch FROM (completed_at - requested_at))/3600)
           FILTER (WHERE status = 'COMPLETED' AND completed_at IS NOT NULL) AS mean_completion_hours
FROM fact_transfer_line
GROUP BY request_date, source_store_id, destination_store_id;

CREATE OR REPLACE VIEW vw_replenishment_fulfillment AS
WITH plan AS (
    SELECT pre_list_id, store_id, product_id, generated_at::date AS plan_date,
           max(status) AS plan_status, sum(suggested_quantity) AS suggested_quantity
    FROM fact_replenishment_plan_line
    GROUP BY pre_list_id, store_id, product_id, generated_at::date
), execution AS (
    SELECT pre_list_id, store_id, product_id,
           sum(replenished_quantity) FILTER (WHERE completed_at IS NOT NULL) AS completed_quantity,
           count(*) FILTER (WHERE completed_at IS NOT NULL) AS completed_lines
    FROM fact_replenishment_execution_line
    GROUP BY pre_list_id, store_id, product_id
)
SELECT p.pre_list_id, p.store_id, p.product_id, p.plan_date, p.plan_status,
       p.suggested_quantity, e.completed_quantity,
       CASE WHEN e.completed_lines > 0 THEN e.completed_quantity / nullif(p.suggested_quantity, 0)
            ELSE NULL END AS fulfillment_rate
FROM plan p LEFT JOIN execution e
  ON e.pre_list_id = p.pre_list_id AND e.store_id = p.store_id AND e.product_id = p.product_id;

CREATE OR REPLACE VIEW vw_product_destinations AS
SELECT 'DONATION'::text AS destination_type, donation_date AS event_date,
       store_id, product_id, batch_id, status, donated_quantity AS quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE donated_quantity * unit_cost END AS value_at_cost,
       suggested_action_id
FROM fact_donation_line
UNION ALL
SELECT 'DISPOSAL', disposal_date, store_id, product_id, batch_id,
       'REGISTERED', disposed_quantity,
       CASE WHEN unit_cost IS NULL THEN NULL ELSE disposed_quantity * unit_cost END,
       suggested_action_id
FROM fact_disposal_line;

CREATE OR REPLACE VIEW vw_alert_action_funnel AS
SELECT a.generated_at::date AS alert_date, a.store_id,
       count(DISTINCT a.alert_id) AS alerts,
       count(DISTINCT a.alert_id) FILTER (WHERE a.status = 'RESOLVED') AS resolved_alerts,
       count(s.suggested_action_id) AS suggested_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'APPROVED') AS approved_actions,
       count(s.suggested_action_id) FILTER (WHERE s.status = 'EXECUTED') AS executed_actions
FROM fact_alert_lifecycle a
LEFT JOIN fact_action_lifecycle s ON s.alert_id = a.alert_id
GROUP BY a.generated_at::date, a.store_id;

COMMENT ON VIEW vw_inventory_count_accuracy IS
    'Accuracy among completed counted positions only; not inventory coverage or system-wide accuracy.';
COMMENT ON VIEW vw_transfer_execution IS
    'Measures transfer completion, not subsequent sale or avoided waste at destination.';
COMMENT ON VIEW vw_replenishment_fulfillment IS
    'Only completed executions count as supplied; no execution produces NULL rate, not zero.';
COMMENT ON VIEW vw_product_destinations IS
    'Recorded dispositions at cost; donation counts as completed only with status COMPLETED. No avoided-loss claim.';
COMMENT ON VIEW vw_alert_action_funnel IS
    'Current statuses by alert cohort; approval is not a historical transition and execution is not proven effective.';

-- Rebind dependencies after table replacement before removing the old table OIDs.
DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'fact_inventory_count_line', 'fact_transfer_line',
        'fact_replenishment_plan_line', 'fact_replenishment_execution_line',
        'fact_donation_line', 'fact_disposal_line',
        'fact_alert_lifecycle', 'fact_action_lifecycle'
    ]
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I.%I',
            'mottainai_analytics', v_table || '__before_partition_16');
    END LOOP;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_bi_count_store_date
    ON fact_inventory_count_line(store_id, count_date);
CREATE INDEX IF NOT EXISTS idx_bi_transfer_store_date
    ON fact_transfer_line(source_store_id, request_date);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_plan
    ON fact_replenishment_plan_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_execution
    ON fact_replenishment_execution_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_donation_store_date
    ON fact_donation_line(store_id, donation_date);
CREATE INDEX IF NOT EXISTS idx_bi_disposal_store_date
    ON fact_disposal_line(store_id, disposal_date);
CREATE INDEX IF NOT EXISTS idx_bi_action_alert
    ON fact_action_lifecycle(alert_id);

GRANT SELECT, INSERT, UPDATE ON
    fact_inventory_count_line, fact_transfer_line,
    fact_replenishment_plan_line, fact_replenishment_execution_line,
    fact_donation_line, fact_disposal_line,
    fact_alert_lifecycle, fact_action_lifecycle
TO mottainai_analytics_loader;
GRANT SELECT ON
    fact_inventory_count_line, fact_transfer_line,
    fact_replenishment_plan_line, fact_replenishment_execution_line,
    fact_donation_line, fact_disposal_line,
    fact_alert_lifecycle, fact_action_lifecycle,
    vw_inventory_count_accuracy, vw_transfer_execution,
    vw_replenishment_fulfillment, vw_product_destinations,
    vw_alert_action_funnel
TO mottainai_analytics_reader;

SELECT sp_create_monthly_fact_partitions(12, 6);

INSERT INTO schema_version (version, description)
VALUES
    (15, 'Operational KPI event facts and semantic views'),
    (16, 'Monthly partitioning for operational KPI event facts')
ON CONFLICT (version) DO UPDATE
SET description = EXCLUDED.description,
    applied_at = now();

COMMIT;
