SET search_path TO mottainai_analytics, public;

CREATE OR REPLACE VIEW vw_sales_daily_kpis AS
SELECT
    fs.sale_date,
    fs.company_id,
    fs.store_id,
    ds.name AS store_name,
    count(*) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS sale_count,
    sum(fs.item_count) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS item_count,
    sum(fs.gross_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS gross_revenue,
    sum(fs.discount_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS discount_amount,
    sum(fs.net_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS net_revenue,
    avg(fs.net_amount) FILTER (WHERE fs.status NOT IN ('CANCELED', 'RETURNED')) AS average_ticket
FROM fact_sales fs
LEFT JOIN dim_store ds ON ds.store_id = fs.store_id
GROUP BY fs.sale_date, fs.company_id, fs.store_id, ds.name;

CREATE OR REPLACE VIEW vw_top_selling_products AS
SELECT
    fsi.sale_date,
    fsi.store_id,
    fsi.product_id,
    dp.name AS product_name,
    dp.category_id,
    sum(fsi.quantity) AS units_sold,
    sum(fsi.subtotal) AS net_revenue,
    sum(fsi.discount_amount) AS discount_amount
FROM fact_sale_item fsi
LEFT JOIN dim_product dp ON dp.product_id = fsi.product_id
GROUP BY fsi.sale_date, fsi.store_id, fsi.product_id, dp.name, dp.category_id;

CREATE OR REPLACE VIEW vw_inventory_snapshot_current AS
SELECT DISTINCT ON (store_id, product_id, batch_id, inventory_type)
    snapshot_date,
    company_id,
    store_id,
    product_id,
    batch_id,
    inventory_type,
    quantity,
    reserved_quantity,
    quantity - reserved_quantity AS available_quantity,
    average_cost,
    expiration_date
FROM fact_inventory_snapshot
ORDER BY store_id, product_id, batch_id, inventory_type, snapshot_date DESC;

CREATE OR REPLACE VIEW vw_stockout_analysis AS
SELECT
    current_stock.store_id,
    current_stock.product_id,
    dp.name AS product_name,
    sum(current_stock.available_quantity) AS available_quantity,
    coalesce(sales.units_sold_30d, 0) AS units_sold_30d,
    CASE
        WHEN coalesce(sales.units_sold_30d, 0) = 0 THEN NULL
        ELSE sum(current_stock.available_quantity) / (sales.units_sold_30d / 30.0)
    END AS estimated_days_of_stock
FROM vw_inventory_snapshot_current current_stock
LEFT JOIN dim_product dp ON dp.product_id = current_stock.product_id
LEFT JOIN (
    SELECT store_id, product_id, sum(quantity) AS units_sold_30d
    FROM fact_sale_item
    WHERE sale_date >= current_date - 29
    GROUP BY store_id, product_id
) sales
    ON sales.store_id = current_stock.store_id
   AND sales.product_id = current_stock.product_id
GROUP BY current_stock.store_id, current_stock.product_id, dp.name, sales.units_sold_30d;

CREATE OR REPLACE VIEW vw_ai_performance AS
SELECT
    am.model_id,
    am.name AS model_name,
    am.model_type,
    count(DISTINCT ap.prediction_id) AS predictions,
    count(DISTINCT ar.recommendation_id) AS recommendations,
    count(DISTINCT ar.recommendation_id) FILTER (WHERE ar.status = 'ACCEPTED') AS accepted,
    count(DISTINCT ar.recommendation_id) FILTER (WHERE ar.status = 'EXECUTED') AS executed,
    avg(ap.confidence) AS average_confidence
FROM ai_model am
LEFT JOIN ai_prediction ap ON ap.model_id = am.model_id
LEFT JOIN ai_recommendation ar ON ar.prediction_id = ap.prediction_id
GROUP BY am.model_id, am.name, am.model_type;

CREATE OR REPLACE VIEW vw_engine_suggestion_metrics AS
SELECT
    created_at::date AS reference_date,
    store_id,
    action_type,
    count(*) AS suggestions,
    count(*) FILTER (WHERE status IN ('ACCEPTED', 'EXECUTED')) AS accepted_or_executed,
    count(*) FILTER (WHERE status = 'REJECTED') AS rejected
FROM engine_suggestion
GROUP BY created_at::date, store_id, action_type;

CREATE OR REPLACE VIEW vw_executive_dashboard AS
SELECT
    sales.reference_date,
    sales.company_id,
    sales.sale_count,
    sales.net_revenue,
    sales.discount_amount,
    sales.average_ticket,
    coalesce(loss.estimated_loss, 0) AS estimated_loss
FROM (
    SELECT
        sale_date AS reference_date,
        company_id,
        sum(sale_count) AS sale_count,
        sum(net_revenue) AS net_revenue,
        sum(discount_amount) AS discount_amount,
        CASE WHEN sum(sale_count) = 0 THEN NULL
             ELSE sum(net_revenue) / sum(sale_count) END AS average_ticket
    FROM vw_sales_daily_kpis
    GROUP BY sale_date, company_id
) sales
LEFT JOIN (
    SELECT loss_date, company_id, sum(estimated_value) AS estimated_loss
    FROM fact_loss_destination
    GROUP BY loss_date, company_id
) loss ON loss.loss_date = sales.reference_date AND loss.company_id = sales.company_id;

CREATE OR REPLACE VIEW vw_customer_loyalty_analysis AS
SELECT
    dc.anonymous_key,
    coalesce(sales.purchases, 0) AS purchases,
    sales.last_purchase_date,
    coalesce(sales.lifetime_value, 0) AS lifetime_value,
    coalesce(loyalty.points_delta, 0) AS points_delta
FROM dim_customer dc
LEFT JOIN (
    SELECT
        customer_id,
        count(DISTINCT sale_id) AS purchases,
        max(sale_date) AS last_purchase_date,
        sum(net_amount) AS lifetime_value
    FROM fact_sales
    WHERE status NOT IN ('CANCELED', 'RETURNED')
    GROUP BY customer_id
) sales ON sales.customer_id = dc.customer_id
LEFT JOIN (
    SELECT customer_id, sum(points_delta) AS points_delta
    FROM fact_loyalty
    GROUP BY customer_id
) loyalty ON loyalty.customer_id = dc.customer_id;
