SET search_path TO mottainai_analytics, public;

CREATE INDEX IF NOT EXISTS idx_dim_store_company ON dim_store(company_id);
CREATE INDEX IF NOT EXISTS idx_dim_product_category ON dim_product(category_id);
CREATE INDEX IF NOT EXISTS idx_fact_sales_store_date ON fact_sales(store_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer_date ON fact_sales(customer_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_sale_item_product_date ON fact_sale_item(product_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_movement_product_date
    ON fact_inventory_movement(product_id, movement_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_snapshot_store_date
    ON fact_inventory_snapshot(store_id, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inventory_snapshot_expiration
    ON fact_inventory_snapshot(expiration_date) WHERE expiration_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_prediction_scope
    ON ai_prediction(store_id, product_id, predicted_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recommendation_pending
    ON ai_recommendation(priority, created_at DESC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_engine_suggestion_pending
    ON engine_suggestion(store_id, priority, created_at DESC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_ingestion_event_status
    ON ingestion_event(status, occurred_at);
CREATE INDEX IF NOT EXISTS idx_ingestion_event_aggregate
    ON ingestion_event(aggregate_type, aggregate_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_etl_dead_letter_unresolved
    ON etl_dead_letter(pipeline_name, last_failed_at) WHERE resolved_at IS NULL;
