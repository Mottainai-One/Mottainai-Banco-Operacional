-- Executed by CI on a fresh PostgreSQL service. All fixture rows roll back.
BEGIN;
SET LOCAL search_path TO mottainai_analytics, public;

INSERT INTO fact_inventory_count_line
  (inventory_count_item_id, inventory_count_id, count_date, store_id, product_id,
   inventory_id, batch_id, status, system_quantity, counted_quantity, unit_cost)
VALUES
  (-10001, -10001, DATE '2026-10-29', -10001, -10001, -10001, -10001, 'COMPLETED', 10, 8, 5),
  (-10002, -10001, DATE '2026-10-29', -10001, -10001, -10002, -10001, 'COMPLETED', 3, 3, 5),
  (-10003, -10002, DATE '2026-10-29', -10001, -10001, -10003, -10001, 'IN_PROGRESS', 5, 0, 5);

INSERT INTO fact_transfer_line
  (transfer_item_id, transfer_id, request_date, requested_at, completed_at,
   source_store_id, destination_store_id, product_id, batch_id, status,
   transferred_quantity, unit_cost)
VALUES
  (-10001, -10001, DATE '2026-10-29', TIMESTAMPTZ '2026-10-29 10:00-03',
   TIMESTAMPTZ '2026-10-29 12:00-03', -10001, -10002, -10001, -10001,
   'COMPLETED', 4, 5),
  (-10002, -10002, DATE '2026-10-29', TIMESTAMPTZ '2026-10-29 11:00-03',
   NULL, -10001, -10002, -10001, -10001, 'REQUESTED', 6, 5);

INSERT INTO fact_replenishment_plan_line
  (pre_list_item_id, pre_list_id, store_id, product_id, generated_at, status,
   suggested_quantity)
VALUES
  (-10001, -10001, -10001, -10001, TIMESTAMPTZ '2026-10-29 10:00-03', 'COMPLETED', 10),
  (-10002, -10002, -10001, -10002, TIMESTAMPTZ '2026-10-29 10:00-03', 'GENERATED', 10);

INSERT INTO fact_replenishment_execution_line
  (execution_item_id, execution_id, pre_list_id, store_id, product_id,
   batch_id, started_at, completed_at, replenished_quantity)
VALUES
  (-10001, -10001, -10001, -10001, -10001, -10001,
   TIMESTAMPTZ '2026-10-29 11:00-03', TIMESTAMPTZ '2026-10-29 12:00-03', 5);

INSERT INTO fact_donation_line
  (donation_item_id, donation_id, donation_date, store_id, product_id, batch_id,
   status, donated_quantity, unit_cost)
VALUES (-10001, -10001, DATE '2026-10-29', -10001, -10001, -10001, 'COMPLETED', 2, 5);

INSERT INTO fact_disposal_line
  (disposal_item_id, disposal_id, disposal_date, store_id, product_id, batch_id,
   disposed_quantity, unit_cost)
VALUES (-10001, -10001, DATE '2026-10-29', -10001, -10001, -10001,
        1, 5);

INSERT INTO fact_alert_lifecycle
  (alert_id, store_id, alert_type, priority, status, generated_at, source_updated_at)
VALUES (-10001, -10001, 'EXPIRATION', 'HIGH', 'RESOLVED',
        TIMESTAMPTZ '2026-10-29 10:00-03', TIMESTAMPTZ '2026-10-29 12:00-03');

INSERT INTO fact_action_lifecycle
  (suggested_action_id, alert_id, store_id, action_type, status, generated_at, source_updated_at)
VALUES (-10001, -10001, -10001, 'DONATION', 'EXECUTED',
        TIMESTAMPTZ '2026-10-29 10:05-03', TIMESTAMPTZ '2026-10-29 12:00-03');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vw_inventory_count_accuracy
    WHERE store_id=-10001 AND counted_positions=2 AND matching_positions=1
      AND accuracy_rate=0.5000 AND absolute_quantity_difference=2
      AND absolute_difference_value=10
  ) THEN RAISE EXCEPTION 'Inventory accuracy includes unfinished counts or misstates value'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vw_transfer_execution
    WHERE source_store_id=-10001 AND transfers_with_items=2
      AND completed_transfers=1 AND completed_item_quantity=4
  ) THEN RAISE EXCEPTION 'Transfer completion is incorrect'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vw_replenishment_fulfillment
    WHERE pre_list_id=-10001 AND fulfillment_rate=0.5
  ) OR NOT EXISTS (
    SELECT 1 FROM vw_replenishment_fulfillment
    WHERE pre_list_id=-10002 AND fulfillment_rate IS NULL
  ) THEN RAISE EXCEPTION 'Replenishment must distinguish no execution from zero'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vw_product_destinations
    WHERE destination_type='DONATION' AND status='COMPLETED'
      AND quantity=2 AND value_at_cost=10
  ) OR NOT EXISTS (
    SELECT 1 FROM vw_product_destinations
    WHERE destination_type='DISPOSAL' AND quantity=1 AND value_at_cost=5
  ) THEN RAISE EXCEPTION 'Disposition quantities or cost values are incorrect'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vw_alert_action_funnel
    WHERE store_id=-10001 AND alerts=1 AND resolved_alerts=1
      AND suggested_actions=1 AND executed_actions=1
  ) THEN RAISE EXCEPTION 'Alert-action funnel is incorrect'; END IF;
END;
$$;

ROLLBACK;
