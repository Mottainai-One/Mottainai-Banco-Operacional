-- Run against MOTTAINAI_ANALITICO after the base analytics schema is installed.
-- This migration only creates analytical facts/views. It does not read MOTTAINAI,
-- start a load, change source tables, or synthesize KPI values.
BEGIN;
SET LOCAL search_path TO mottainai_analytics, public;
DO $$
BEGIN
    IF current_database() IN ('MOTTAINAI', 'mottainai_operational', 'mottainai') THEN
        RAISE EXCEPTION 'Connect to MOTTAINAI_ANALITICO before applying BI fact migration';
    END IF;
    IF to_regclass('mottainai_analytics.fact_sales') IS NULL THEN
        RAISE EXCEPTION 'Base analytical schema is missing; install it before migration 15';
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS fact_inventory_count_line (
    inventory_count_item_id BIGINT PRIMARY KEY,
    inventory_count_id BIGINT NOT NULL,
    count_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    inventory_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    system_quantity NUMERIC(15,3) NOT NULL,
    counted_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    finished_at TIMESTAMPTZ,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (system_quantity >= 0 AND counted_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS fact_transfer_line (
    transfer_item_id BIGINT PRIMARY KEY,
    transfer_id BIGINT NOT NULL,
    request_date DATE NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    source_store_id BIGINT NOT NULL,
    destination_store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    status VARCHAR(30) NOT NULL,
    transferred_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (transferred_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_replenishment_plan_line (
    pre_list_item_id BIGINT PRIMARY KEY,
    pre_list_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL,
    suggested_quantity NUMERIC(15,3) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (suggested_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_replenishment_execution_line (
    execution_item_id BIGINT PRIMARY KEY,
    execution_id BIGINT NOT NULL,
    pre_list_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    replenished_quantity NUMERIC(15,3) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (replenished_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_donation_line (
    donation_item_id BIGINT PRIMARY KEY,
    donation_id BIGINT NOT NULL,
    donation_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    status VARCHAR(30) NOT NULL,
    donated_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (donated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_disposal_line (
    disposal_item_id BIGINT PRIMARY KEY,
    disposal_id BIGINT NOT NULL,
    disposal_date DATE NOT NULL,
    store_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    batch_id BIGINT NOT NULL,
    suggested_action_id BIGINT,
    disposed_quantity NUMERIC(15,3) NOT NULL,
    unit_cost NUMERIC(15,4),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (disposed_quantity > 0)
);

CREATE TABLE IF NOT EXISTS fact_alert_lifecycle (
    alert_id BIGINT PRIMARY KEY,
    store_id BIGINT NOT NULL,
    alert_type VARCHAR(40) NOT NULL,
    priority VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ,
    source_updated_at TIMESTAMPTZ NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_action_lifecycle (
    suggested_action_id BIGINT PRIMARY KEY,
    alert_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    action_type VARCHAR(40) NOT NULL,
    status VARCHAR(30) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    source_recommendation_uuid UUID,
    source_updated_at TIMESTAMPTZ NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bi_count_store_date ON fact_inventory_count_line(store_id, count_date);
CREATE INDEX IF NOT EXISTS idx_bi_transfer_store_date ON fact_transfer_line(source_store_id, request_date);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_plan ON fact_replenishment_plan_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_replenishment_execution ON fact_replenishment_execution_line(pre_list_id, product_id);
CREATE INDEX IF NOT EXISTS idx_bi_donation_store_date ON fact_donation_line(store_id, donation_date);
CREATE INDEX IF NOT EXISTS idx_bi_disposal_store_date ON fact_disposal_line(store_id, disposal_date);
CREATE INDEX IF NOT EXISTS idx_bi_action_alert ON fact_action_lifecycle(alert_id);

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

COMMENT ON VIEW vw_inventory_count_accuracy IS
    'Accuracy among completed counted positions only; not inventory coverage or system-wide accuracy.';

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

COMMENT ON VIEW vw_transfer_execution IS
    'Measures transfer completion, not subsequent sale or avoided waste at destination.';

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

COMMENT ON VIEW vw_replenishment_fulfillment IS
    'Only completed executions count as supplied; no execution produces NULL rate, not zero.';

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

COMMENT ON VIEW vw_product_destinations IS
    'Recorded dispositions at cost; donation counts as completed only with status COMPLETED. No avoided-loss claim.';

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

COMMENT ON VIEW vw_alert_action_funnel IS
    'Current statuses by alert cohort; approval is not a historical transition and execution is not proven effective.';

COMMIT;
