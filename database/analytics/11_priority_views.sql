-- Views do dashboard derivadas apenas de dimensoes e fatos do banco fisico analitico.
SET search_path TO mottainai_analytics, public;

ALTER TABLE fact_inventory_snapshot
    ADD COLUMN IF NOT EXISTS inventory_id BIGINT,
    ADD COLUMN IF NOT EXISTS minimum_quantity NUMERIC(15,3);

CREATE TABLE IF NOT EXISTS fact_alert_snapshot (
    snapshot_date DATE NOT NULL,
    alert_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    PRIMARY KEY (snapshot_date, alert_id)
);

CREATE OR REPLACE VIEW vw_inventory_snapshot_current AS
SELECT DISTINCT ON (store_id, product_id, batch_id, inventory_type)
       snapshot_date, company_id, store_id, product_id, batch_id,
       inventory_type, quantity, reserved_quantity,
       quantity - reserved_quantity AS available_quantity,
       average_cost, expiration_date, inventory_id, minimum_quantity
FROM fact_inventory_snapshot
ORDER BY store_id, product_id, batch_id, inventory_type, snapshot_date DESC;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT i.inventory_id, i.product_id, p.name AS product,
       i.store_id, s.name AS store,
       i.quantity AS current_quantity, i.minimum_quantity
FROM vw_inventory_snapshot_current i
JOIN dim_product p ON p.product_id = i.product_id
JOIN dim_store s ON s.store_id = i.store_id
WHERE i.minimum_quantity IS NOT NULL
  AND i.quantity < i.minimum_quantity;

CREATE OR REPLACE VIEW vw_monthly_summary AS
WITH sales AS (
    SELECT date_trunc('month', sale_date)::date AS month_start, store_id,
           count(*) AS total_sales, sum(net_amount) AS total_revenue,
           avg(net_amount) AS avg_ticket,
           count(DISTINCT employee_id) AS active_sellers
    FROM fact_sales
    WHERE status = 'COMPLETED'
    GROUP BY 1, 2
), units AS (
    SELECT date_trunc('month', i.sale_date)::date AS month_start, i.store_id,
           sum(i.quantity) AS units_sold
    FROM fact_sale_item i
    JOIN fact_sales s ON s.sale_id = i.sale_id AND s.sale_date = i.sale_date
    WHERE s.status = 'COMPLETED'
    GROUP BY 1, 2
)
SELECT sales.month_start, sales.store_id, ds.name AS store_name,
       sales.total_sales, sales.total_revenue, sales.avg_ticket,
       sales.active_sellers, coalesce(units.units_sold, 0) AS units_sold
FROM sales
JOIN dim_store ds ON ds.store_id = sales.store_id
LEFT JOIN units ON units.month_start = sales.month_start AND units.store_id = sales.store_id;

CREATE OR REPLACE VIEW vw_product_risk_ranking AS
WITH expiration AS (
    SELECT i.store_id, i.product_id,
           sum(i.quantity) FILTER (WHERE i.expiration_date BETWEEN current_date AND current_date + 15)
               AS quantity_at_expiration_risk,
           sum(i.quantity * coalesce(i.average_cost, 0)) FILTER
               (WHERE i.expiration_date BETWEEN current_date AND current_date + 15)
               AS value_at_expiration_risk,
           min(i.expiration_date - current_date) FILTER
               (WHERE i.expiration_date >= current_date) AS nearest_expiration_days
    FROM vw_inventory_snapshot_current i
    GROUP BY i.store_id, i.product_id
)
SELECT x.store_id, s.name AS store_name, x.product_id, x.product_name,
       CASE WHEN x.available_quantity <= 0 THEN 'CRITICAL'
            WHEN x.estimated_days_of_stock < 7 THEN 'HIGH'
            WHEN x.estimated_days_of_stock < 15 THEN 'MEDIUM'
            ELSE 'LOW' END AS stockout_risk,
       x.available_quantity AS current_stock,
       x.estimated_days_of_stock AS days_of_coverage,
       coalesce(e.quantity_at_expiration_risk, 0)::numeric(18,3) AS quantity_at_expiration_risk,
       coalesce(e.value_at_expiration_risk, 0)::numeric(18,2) AS value_at_expiration_risk,
       e.nearest_expiration_days,
       CASE WHEN x.available_quantity <= 0 OR coalesce(e.value_at_expiration_risk,0) >= 1000 THEN 'CRITICAL'
            WHEN x.estimated_days_of_stock < 7 OR coalesce(e.value_at_expiration_risk,0) > 0 THEN 'HIGH'
            WHEN x.estimated_days_of_stock < 15 THEN 'MEDIUM'
            ELSE 'LOW' END AS consolidated_risk
FROM vw_stockout_analysis x
JOIN dim_store s ON s.store_id = x.store_id
LEFT JOIN expiration e ON e.store_id = x.store_id AND e.product_id = x.product_id;

-- Uma linha por loja. Atualizada ao fim de cada carga diaria; nunca consulta o operacional.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_dashboard_metrics AS
WITH sales AS (
    SELECT store_id, count(*) AS transactions, sum(net_amount) AS revenue,
           avg(net_amount) AS avg_ticket
    FROM fact_sales
    WHERE sale_date >= current_date - 1 AND status = 'COMPLETED'
    GROUP BY store_id
), products AS (
    SELECT i.store_id, count(DISTINCT i.product_id) AS products_sold
    FROM fact_sale_item i
    JOIN fact_sales s ON s.sale_id = i.sale_id AND s.sale_date = i.sale_date
    WHERE i.sale_date >= current_date - 1 AND s.status = 'COMPLETED'
    GROUP BY i.store_id
), alerts AS (
    SELECT store_id, count(*) AS active_alerts
    FROM fact_alert_snapshot
    WHERE snapshot_date = (SELECT max(snapshot_date) FROM fact_alert_snapshot)
      AND status = 'ACTIVE'
    GROUP BY store_id
), ruptures AS (
    SELECT store_id, count(DISTINCT inventory_id) AS products_in_rupture
    FROM vw_critical_stock
    GROUP BY store_id
)
SELECT s.store_id, s.name AS store_name,
       coalesce(a.active_alerts,0) AS active_alerts,
       coalesce(r.products_in_rupture,0) AS products_in_rupture,
       coalesce(x.revenue,0) AS daily_revenue,
       coalesce(x.avg_ticket,0) AS avg_ticket,
       coalesce(x.transactions,0) AS daily_transactions,
       coalesce(p.products_sold,0) AS products_sold,
       NULL::numeric(18,2) AS monthly_economy
FROM dim_store s
LEFT JOIN sales x ON x.store_id = s.store_id
LEFT JOIN products p ON p.store_id = s.store_id
LEFT JOIN alerts a ON a.store_id = s.store_id
LEFT JOIN ruptures r ON r.store_id = s.store_id
WHERE s.active
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_dashboard_metrics_store
    ON mv_dashboard_metrics(store_id);
