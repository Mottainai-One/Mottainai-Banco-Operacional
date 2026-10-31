-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 27_VIEWS.SQL
-- ====================================================================

CREATE OR REPLACE VIEW vw_expiring_products AS
SELECT 
    b.batch_id,
    b.batch_code,
    p.product_id,
    p.name AS product,
    s.store_id,
    s.name AS store,
    b.expiration_date,
    (b.expiration_date - CURRENT_DATE) AS days_to_expire,
    i.current_quantity
FROM batch b
JOIN inventory i ON i.batch_id = b.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE b.active = TRUE
  AND i.current_quantity > 0
  AND b.deleted_at IS NULL
  AND i.deleted_at IS NULL
  AND b.expiration_date <= CURRENT_DATE + INTERVAL '15 days'
ORDER BY b.expiration_date ASC;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT 
    i.inventory_id,
    p.product_id,
    p.name AS product,
    i.store_id,
    s.name AS store,
    i.current_quantity,
    i.minimum_quantity
FROM inventory i
JOIN batch b ON b.batch_id = i.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE i.current_quantity < i.minimum_quantity
  AND i.deleted_at IS NULL
  AND b.deleted_at IS NULL
ORDER BY i.current_quantity ASC;

CREATE OR REPLACE VIEW vw_stock_coverage AS
SELECT 
    p.product_id,
    p.name AS product_name,
    s.store_id,
    s.name AS store_name,
    COALESCE(SUM(i.current_quantity), 0) AS total_stock,
    fn_calculate_average_consumption(p.product_id, s.store_id, 30) AS daily_consumption,
    fn_calculate_coverage(p.product_id, s.store_id) AS days_coverage,
    fn_calculate_criticality(p.product_id, s.store_id) AS criticality
FROM product p
CROSS JOIN retail_store s
LEFT JOIN inventory i ON i.store_id = s.store_id
LEFT JOIN batch b ON b.batch_id = i.batch_id AND b.product_id = p.product_id
WHERE s.active = TRUE
  AND s.deleted_at IS NULL
  AND p.active = TRUE
  AND p.deleted_at IS NULL
GROUP BY p.product_id, p.name, s.store_id, s.name;

CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT 
    DATE_TRUNC('month', sale_date) AS month,
    store_id,
    COUNT(*) AS total_sales,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_ticket,
    COUNT(DISTINCT employee_id) AS active_sellers
FROM sales_transaction
WHERE status = 'COMPLETED'
  AND deleted_at IS NULL
GROUP BY DATE_TRUNC('month', sale_date), store_id;

CREATE OR REPLACE VIEW vw_active_customer_promotions AS
SELECT
    p.promotion_id,
    p.store_id,
    s.name AS store_name,
    s.latitude,
    s.longitude,
    p.name AS promotion_name,
    p.description,
    p.starts_at,
    p.ends_at,
    pi.product_id,
    pr.sku,
    pr.name AS product_name,
    pi.original_price,
    pi.promotional_price,
    pi.discount_percent,
    pi.quantity_available
FROM promotion p
JOIN promotion_item pi ON pi.promotion_id = p.promotion_id
JOIN product pr ON pr.product_id = pi.product_id
JOIN retail_store s ON s.store_id = p.store_id
WHERE p.active = TRUE
  AND p.status = 'APPROVED'
  AND p.starts_at <= CURRENT_TIMESTAMP
  AND p.ends_at > CURRENT_TIMESTAMP
  AND pr.active = TRUE
  AND pr.deleted_at IS NULL;

-- 28_MATERIALIZED_VIEWS.SQL
-- ====================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_dashboard_metrics AS
WITH stats AS (
    SELECT 
        s.store_id,
        COUNT(DISTINCT a.alert_id) AS alerts,
        COUNT(DISTINCT i.inventory_id) AS ruptures,
        COUNT(DISTINCT st.sale_id) AS transactions,
        COALESCE(SUM(st.total_amount), 0) AS revenue,
        COALESCE(AVG(st.total_amount), 0) AS avg_ticket
    FROM retail_store s
    LEFT JOIN alert a ON a.store_id = s.store_id AND a.status = 'ACTIVE'
    LEFT JOIN inventory i ON i.store_id = s.store_id AND i.current_quantity < i.minimum_quantity
        AND i.deleted_at IS NULL
    LEFT JOIN sales_transaction st ON st.store_id = s.store_id 
        AND st.sale_date >= CURRENT_DATE - INTERVAL '1 day'
        AND st.status = 'COMPLETED'
        AND st.deleted_at IS NULL
    WHERE s.active = TRUE
      AND s.deleted_at IS NULL
    GROUP BY s.store_id
)
SELECT 
    store_id,
    (SELECT name FROM retail_store WHERE store_id = stats.store_id) AS store_name,
    alerts AS active_alerts,
    ruptures AS products_in_rupture,
    revenue AS daily_revenue,
    avg_ticket,
    transactions AS daily_transactions,
    (SELECT COUNT(DISTINCT product_id) FROM sale_item si 
     JOIN sales_transaction st ON st.sale_id = si.sale_id 
     WHERE st.store_id = stats.store_id 
       AND st.sale_date >= CURRENT_DATE - INTERVAL '1 day'
       AND st.deleted_at IS NULL) AS products_sold,
    fn_calculate_economy(store_id, DATE_TRUNC('month', CURRENT_DATE)::DATE, CURRENT_DATE) AS monthly_economy
FROM stats;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_dashboard_store ON mv_dashboard_metrics(store_id);


-- ====================================================================
-- ANALYTICS VIEWS (mottainai_analytics schema)
-- ====================================================================

-- ============================================================================
-- MOTTAINAI - CAMADA ANALÍTICA
-- Fonte de dados: schema mottainai
-- Este arquivo cria SOMENTE VIEWS. Não cria índices, tabelas ou materialized views.
-- Compatível com o script_completo_mottainai_v9.sql
-- PostgreSQL 15+
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS mottainai_analytics;
SET search_path TO mottainai_analytics, mottainai, public;

-- ============================================================================
-- 01. VENDAS DIÁRIAS / KPI COMERCIAL
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_sales_daily_kpis AS
WITH daily AS (
    SELECT
        st.store_id,
        rs.name AS store_name,
        st.sale_date::date AS sale_day,
        COUNT(DISTINCT (st.sale_id, st.sale_date)) AS sales_count,
        COALESCE(SUM(st.total_amount) FILTER (WHERE st.status = 'COMPLETED'), 0)::numeric(18,2) AS revenue,
        COALESCE(SUM(si.quantity_sold) FILTER (WHERE si.status = 'SOLD'), 0)::numeric(18,3) AS units_sold,
        COUNT(DISTINCT st.employee_id) FILTER (WHERE st.status = 'COMPLETED') AS active_sellers
    FROM mottainai.sales_transaction st
    JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
    LEFT JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
    WHERE st.deleted_at IS NULL
    GROUP BY st.store_id, rs.name, st.sale_date::date
)
SELECT
    store_id,
    store_name,
    sale_day,
    sales_count,
    revenue,
    units_sold,
    active_sellers,
    CASE WHEN sales_count > 0 THEN ROUND(revenue / sales_count, 2) ELSE 0 END AS avg_ticket,
    ROUND(AVG(revenue) OVER (
        PARTITION BY store_id ORDER BY sale_day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS revenue_7d_avg,
    ROUND(AVG(revenue) OVER (
        PARTITION BY store_id ORDER BY sale_day
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2) AS revenue_30d_avg,
    LAG(revenue) OVER (PARTITION BY store_id ORDER BY sale_day) AS previous_day_revenue,
    CASE
        WHEN LAG(revenue) OVER (PARTITION BY store_id ORDER BY sale_day) IS NULL
          OR LAG(revenue) OVER (PARTITION BY store_id ORDER BY sale_day) = 0
        THEN NULL
        ELSE ROUND(
            ((revenue - LAG(revenue) OVER (PARTITION BY store_id ORDER BY sale_day))
             / LAG(revenue) OVER (PARTITION BY store_id ORDER BY sale_day)) * 100, 2
        )
    END AS day_over_day_growth_pct
FROM daily;

-- ============================================================================
-- 02. TENDÊNCIA DE VENDAS POR PERÍODO
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_sales_trend AS
SELECT
    store_id,
    store_name,
    sale_day,
    DATE_TRUNC('week', sale_day::timestamp)::date AS week_start,
    DATE_TRUNC('month', sale_day::timestamp)::date AS month_start,
    sales_count,
    units_sold,
    revenue,
    avg_ticket,
    revenue_7d_avg,
    revenue_30d_avg,
    day_over_day_growth_pct,
    CASE
        WHEN revenue_30d_avg IS NULL OR revenue_30d_avg = 0 THEN NULL
        ELSE ROUND(((revenue - revenue_30d_avg) / revenue_30d_avg) * 100, 2)
    END AS deviation_from_30d_avg_pct
FROM mottainai_analytics.vw_sales_daily_kpis;

-- ============================================================================
-- 03. PRODUTOS MAIS VENDIDOS
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_top_selling_products AS
WITH product_sales AS (
    SELECT
        st.store_id,
        rs.name AS store_name,
        p.product_id,
        p.sku,
        p.name AS product_name,
        pc.category_id,
        pc.name AS category_name,
        SUM(si.quantity_sold) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD')::numeric(18,3) AS quantity_sold,
        SUM(si.subtotal) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD')::numeric(18,2) AS revenue,
        COUNT(DISTINCT (st.sale_id, st.sale_date)) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD') AS sales_count,
        AVG(si.unit_price) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD')::numeric(18,2) AS avg_unit_price
    FROM mottainai.sales_transaction st
    JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
    JOIN mottainai.product p ON p.product_id = si.product_id
    JOIN mottainai.product_category pc ON pc.category_id = p.category_id
    JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
    WHERE st.deleted_at IS NULL
    GROUP BY st.store_id, rs.name, p.product_id, p.sku, p.name, pc.category_id, pc.name
)
SELECT
    *,
    DENSE_RANK() OVER (PARTITION BY store_id ORDER BY quantity_sold DESC NULLS LAST) AS quantity_rank,
    DENSE_RANK() OVER (PARTITION BY store_id ORDER BY revenue DESC NULLS LAST) AS revenue_rank
FROM product_sales
WHERE quantity_sold > 0;

-- ============================================================================
-- 04. GIRO E COBERTURA DE ESTOQUE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_inventory_turnover AS
WITH stock AS (
    SELECT
        i.store_id,
        i.batch_id,
        b.product_id,
        SUM(i.current_quantity) AS current_stock
    FROM mottainai.inventory i
    JOIN mottainai.batch b ON b.batch_id = i.batch_id
    WHERE i.deleted_at IS NULL
      AND b.deleted_at IS NULL
      AND b.active = TRUE
    GROUP BY i.store_id, i.batch_id, b.product_id
), stock_by_product AS (
    SELECT store_id, product_id, SUM(current_stock) AS current_stock
    FROM stock
    GROUP BY store_id, product_id
), sales_30d AS (
    SELECT
        st.store_id,
        si.product_id,
        SUM(si.quantity_sold) AS units_30d,
        SUM(si.subtotal) AS revenue_30d
    FROM mottainai.sales_transaction st
    JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
    WHERE st.status = 'COMPLETED'
      AND si.status = 'SOLD'
      AND st.deleted_at IS NULL
      AND st.sale_date >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY st.store_id, si.product_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    p.product_id,
    p.sku,
    p.name AS product_name,
    COALESCE(s.current_stock, 0)::numeric(18,3) AS current_stock,
    COALESCE(s30.units_30d, 0)::numeric(18,3) AS units_sold_30d,
    ROUND(COALESCE(s30.units_30d, 0) / 30.0, 3) AS avg_daily_consumption,
    CASE
        WHEN COALESCE(s30.units_30d, 0) > 0
        THEN ROUND(COALESCE(s.current_stock, 0) / (s30.units_30d / 30.0), 2)
        ELSE NULL
    END AS days_of_coverage,
    CASE
        WHEN COALESCE(s30.units_30d, 0) = 0 AND COALESCE(s.current_stock, 0) > 0 THEN 'NO_MOVEMENT'
        WHEN COALESCE(s30.units_30d, 0) = 0 THEN 'NO_STOCK'
        WHEN COALESCE(s.current_stock, 0) / NULLIF(s30.units_30d / 30.0, 0) <= 3 THEN 'HIGH_TURNOVER'
        WHEN COALESCE(s.current_stock, 0) / NULLIF(s30.units_30d / 30.0, 0) <= 15 THEN 'MEDIUM_TURNOVER'
        ELSE 'LOW_TURNOVER'
    END AS turnover_class,
    COALESCE(s30.revenue_30d, 0)::numeric(18,2) AS revenue_30d
FROM mottainai.retail_store rs
JOIN mottainai.product p ON p.active = TRUE AND p.deleted_at IS NULL
LEFT JOIN stock_by_product s ON s.store_id = rs.store_id AND s.product_id = p.product_id
LEFT JOIN sales_30d s30 ON s30.store_id = rs.store_id AND s30.product_id = p.product_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 05. RISCO DE RUPTURA
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_stockout_analysis AS
WITH product_stock AS (
    SELECT
        i.store_id,
        b.product_id,
        SUM(i.current_quantity) AS current_stock,
        MAX(i.minimum_quantity) AS minimum_quantity,
        MAX(i.maximum_quantity) AS maximum_quantity
    FROM mottainai.inventory i
    JOIN mottainai.batch b ON b.batch_id = i.batch_id
    WHERE i.deleted_at IS NULL AND b.deleted_at IS NULL
    GROUP BY i.store_id, b.product_id
), consumption AS (
    SELECT
        st.store_id,
        si.product_id,
        SUM(si.quantity_sold) / 30.0 AS daily_consumption
    FROM mottainai.sales_transaction st
    JOIN mottainai.sale_item si ON si.sale_id = st.sale_id AND si.sale_date = st.sale_date
    WHERE st.status = 'COMPLETED'
      AND si.status = 'SOLD'
      AND st.sale_date >= CURRENT_TIMESTAMP - INTERVAL '30 days'
      AND st.deleted_at IS NULL
    GROUP BY st.store_id, si.product_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    p.product_id,
    p.sku,
    p.name AS product_name,
    COALESCE(ps.current_stock, 0)::numeric(18,3) AS current_stock,
    COALESCE(ps.minimum_quantity, 0)::numeric(18,3) AS minimum_quantity,
    COALESCE(c.daily_consumption, 0)::numeric(18,3) AS daily_consumption,
    CASE WHEN c.daily_consumption > 0
         THEN ROUND(COALESCE(ps.current_stock,0) / c.daily_consumption, 2)
         ELSE NULL END AS days_of_coverage,
    CASE
        WHEN COALESCE(ps.current_stock, 0) <= 0 THEN 'CRITICAL'
        WHEN COALESCE(ps.current_stock, 0) <= COALESCE(ps.minimum_quantity, 0) THEN 'HIGH'
        WHEN c.daily_consumption > 0 AND ps.current_stock / c.daily_consumption <= 3 THEN 'HIGH'
        WHEN c.daily_consumption > 0 AND ps.current_stock / c.daily_consumption <= 7 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS stockout_risk
FROM mottainai.retail_store rs
JOIN mottainai.product p ON p.active = TRUE AND p.deleted_at IS NULL
LEFT JOIN product_stock ps ON ps.store_id = rs.store_id AND ps.product_id = p.product_id
LEFT JOIN consumption c ON c.store_id = rs.store_id AND c.product_id = p.product_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 06. PREVISÃO SIMPLES DE PERDA POR VENCIMENTO
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_expiration_loss_forecast AS
WITH consumption AS (
    SELECT
        st.store_id,
        si.product_id,
        SUM(si.quantity_sold) / 30.0 AS daily_consumption
    FROM mottainai.sales_transaction st
    JOIN mottainai.sale_item si ON si.sale_id = st.sale_id AND si.sale_date = st.sale_date
    WHERE st.status = 'COMPLETED'
      AND si.status = 'SOLD'
      AND st.deleted_at IS NULL
      AND st.sale_date >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY st.store_id, si.product_id
)
SELECT
    i.store_id,
    rs.name AS store_name,
    b.batch_id,
    b.batch_code,
    p.product_id,
    p.sku,
    p.name AS product_name,
    b.expiration_date,
    (b.expiration_date - CURRENT_DATE) AS days_to_expire,
    i.current_quantity,
    COALESCE(c.daily_consumption, 0)::numeric(18,3) AS daily_consumption,
    CASE WHEN c.daily_consumption > 0
         THEN ROUND(i.current_quantity / c.daily_consumption, 2)
         ELSE NULL END AS days_of_coverage,
    CASE
        WHEN i.current_quantity <= 0 THEN 0::numeric
        WHEN c.daily_consumption <= 0 THEN i.current_quantity
        WHEN (b.expiration_date - CURRENT_DATE) <= 0 THEN i.current_quantity
        WHEN i.current_quantity > c.daily_consumption * (b.expiration_date - CURRENT_DATE)
        THEN ROUND(i.current_quantity - (c.daily_consumption * (b.expiration_date - CURRENT_DATE)), 3)
        ELSE 0::numeric
    END AS estimated_quantity_at_risk,
    CASE
        WHEN i.current_quantity <= 0 THEN 0::numeric
        WHEN c.daily_consumption <= 0 THEN i.current_quantity * b.unit_cost
        WHEN (b.expiration_date - CURRENT_DATE) <= 0 THEN i.current_quantity * b.unit_cost
        WHEN i.current_quantity > c.daily_consumption * (b.expiration_date - CURRENT_DATE)
        THEN ROUND((i.current_quantity - (c.daily_consumption * (b.expiration_date - CURRENT_DATE))) * b.unit_cost, 2)
        ELSE 0::numeric
    END AS estimated_value_at_risk,
    CASE
        WHEN b.expiration_date < CURRENT_DATE THEN 'EXPIRED'
        WHEN b.expiration_date <= CURRENT_DATE + 3 THEN 'CRITICAL'
        WHEN b.expiration_date <= CURRENT_DATE + 7 THEN 'HIGH'
        WHEN b.expiration_date <= CURRENT_DATE + 15 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS expiration_risk
FROM mottainai.inventory i
JOIN mottainai.batch b ON b.batch_id = i.batch_id
JOIN mottainai.product p ON p.product_id = b.product_id
JOIN mottainai.retail_store rs ON rs.store_id = i.store_id
LEFT JOIN consumption c ON c.store_id = i.store_id AND c.product_id = b.product_id
WHERE i.current_quantity > 0
  AND i.deleted_at IS NULL
  AND b.deleted_at IS NULL
  AND b.active = TRUE
  AND p.active = TRUE
  AND p.deleted_at IS NULL;

-- ============================================================================
-- 07. ALERTAS E RISCO CONSOLIDADO
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_product_risk_ranking AS
SELECT
    x.store_id,
    x.store_name,
    x.product_id,
    x.product_name,
    x.stockout_risk,
    x.current_stock,
    x.days_of_coverage,
    COALESCE(SUM(e.estimated_quantity_at_risk), 0)::numeric(18,3) AS quantity_at_expiration_risk,
    COALESCE(SUM(e.estimated_value_at_risk), 0)::numeric(18,2) AS value_at_expiration_risk,
    MAX(e.days_to_expire) FILTER (WHERE e.days_to_expire IS NOT NULL) AS nearest_expiration_days,
    CASE
        WHEN x.stockout_risk = 'CRITICAL'
          OR COALESCE(SUM(e.estimated_value_at_risk),0) >= 1000 THEN 'CRITICAL'
        WHEN x.stockout_risk = 'HIGH'
          OR COALESCE(SUM(e.estimated_value_at_risk),0) > 0 THEN 'HIGH'
        WHEN x.stockout_risk = 'MEDIUM' THEN 'MEDIUM'
        ELSE 'LOW'
    END AS consolidated_risk
FROM (
    SELECT
        store_id, store_name, product_id, product_name,
        current_stock, days_of_coverage, stockout_risk
    FROM mottainai_analytics.vw_stockout_analysis
) x
LEFT JOIN mottainai_analytics.vw_expiration_loss_forecast e
  ON e.store_id = x.store_id
 AND e.product_id = x.product_id
GROUP BY x.store_id, x.store_name, x.product_id, x.product_name,
         x.current_stock, x.days_of_coverage, x.stockout_risk;

-- ============================================================================
-- 08. ABASTECIMENTO / ASSERTIVIDADE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_replenishment_performance AS
WITH suggested AS (
    SELECT
        pl.pre_list_id,
        pl.store_id,
        pl.generated_at,
        pl.status,
        SUM(pli.suggested_quantity) AS suggested_quantity,
        COUNT(*) AS suggested_items
    FROM mottainai.replenishment_pre_list pl
    JOIN mottainai.replenishment_pre_list_item pli ON pli.pre_list_id = pl.pre_list_id
    GROUP BY pl.pre_list_id, pl.store_id, pl.generated_at, pl.status
), executed AS (
    SELECT
        re.pre_list_id,
        SUM(rei.replenished_quantity) AS executed_quantity,
        COUNT(DISTINCT rei.batch_id) AS executed_batches,
        MIN(re.start_date) AS start_date,
        MAX(re.end_date) AS end_date,
        AVG(re.rating) AS avg_rating
    FROM mottainai.replenishment_execution re
    JOIN mottainai.replenishment_execution_item rei ON rei.execution_id = re.execution_id
    GROUP BY re.pre_list_id
)
SELECT
    s.pre_list_id,
    s.store_id,
    rs.name AS store_name,
    s.generated_at,
    s.status,
    s.suggested_quantity::numeric(18,3),
    COALESCE(e.executed_quantity, 0)::numeric(18,3) AS executed_quantity,
    s.suggested_items,
    COALESCE(e.executed_batches, 0) AS executed_batches,
    CASE
        WHEN s.suggested_quantity = 0 THEN NULL
        ELSE ROUND((LEAST(COALESCE(e.executed_quantity,0), s.suggested_quantity) / s.suggested_quantity) * 100, 2)
    END AS execution_accuracy_pct,
    CASE WHEN e.start_date IS NOT NULL AND e.end_date IS NOT NULL
         THEN EXTRACT(EPOCH FROM (e.end_date - e.start_date)) / 60.0
         ELSE NULL END AS execution_minutes,
    ROUND(COALESCE(e.avg_rating, 0), 2) AS avg_rating
FROM suggested s
JOIN mottainai.retail_store rs ON rs.store_id = s.store_id
LEFT JOIN executed e ON e.pre_list_id = s.pre_list_id;

-- ============================================================================
-- 09. TRANSFERÊNCIAS ENTRE LOJAS
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_transfer_analysis AS
SELECT
    t.transfer_id,
    t.request_date,
    t.completion_date,
    t.status,
    t.source_store_id,
    src.name AS source_store,
    t.destination_store_id,
    dst.name AS destination_store,
    COUNT(ti.transfer_item_id) AS item_lines,
    COALESCE(SUM(ti.transferred_quantity), 0)::numeric(18,3) AS transferred_quantity,
    COALESCE(SUM(ti.transferred_quantity * b.unit_cost), 0)::numeric(18,2) AS transferred_cost_value,
    CASE WHEN t.completion_date IS NOT NULL
         THEN EXTRACT(EPOCH FROM (t.completion_date - t.request_date)) / 86400.0
         ELSE NULL END AS lead_time_days
FROM mottainai.transfer t
JOIN mottainai.retail_store src ON src.store_id = t.source_store_id
JOIN mottainai.retail_store dst ON dst.store_id = t.destination_store_id
LEFT JOIN mottainai.transfer_item ti ON ti.transfer_id = t.transfer_id
LEFT JOIN mottainai.batch b ON b.batch_id = ti.batch_id
GROUP BY t.transfer_id, t.request_date, t.completion_date, t.status,
         t.source_store_id, src.name, t.destination_store_id, dst.name;

-- ============================================================================
-- 10. EFETIVIDADE DAS TRANSFERÊNCIAS
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_transfer_effectiveness AS
WITH transferred AS (
    SELECT
        t.transfer_id,
        t.destination_store_id,
        ti.batch_id,
        b.product_id,
        ti.transferred_quantity,
        b.unit_cost,
        t.completion_date
    FROM mottainai.transfer t
    JOIN mottainai.transfer_item ti ON ti.transfer_id = t.transfer_id
    JOIN mottainai.batch b ON b.batch_id = ti.batch_id
    WHERE t.status = 'COMPLETED'
), destination_sales AS (
    SELECT
        tr.transfer_id,
        SUM(si.quantity_sold) AS sold_quantity,
        SUM(si.subtotal) AS sales_value
    FROM transferred tr
    JOIN mottainai.sales_transaction st
      ON st.store_id = tr.destination_store_id
     AND st.sale_date >= COALESCE(tr.completion_date, CURRENT_TIMESTAMP)
     AND st.sale_date < COALESCE(tr.completion_date, CURRENT_TIMESTAMP) + INTERVAL '30 days'
     AND st.status = 'COMPLETED'
    JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
     AND si.product_id = tr.product_id
     AND si.status = 'SOLD'
    GROUP BY tr.transfer_id
)
SELECT
    tr.transfer_id,
    tr.destination_store_id,
    tr.product_id,
    tr.batch_id,
    tr.transferred_quantity,
    tr.unit_cost,
    (tr.transferred_quantity * tr.unit_cost)::numeric(18,2) AS transferred_cost_value,
    COALESCE(ds.sold_quantity, 0)::numeric(18,3) AS sold_quantity_within_30d,
    COALESCE(ds.sales_value, 0)::numeric(18,2) AS sales_value_within_30d,
    CASE WHEN tr.transferred_quantity > 0
         THEN ROUND((COALESCE(ds.sold_quantity,0) / tr.transferred_quantity) * 100, 2)
         ELSE 0 END AS sell_through_pct
FROM transferred tr
LEFT JOIN destination_sales ds ON ds.transfer_id = tr.transfer_id;

-- ============================================================================
-- 11. VALOR RECUPERADO / PERDAS EVITADAS
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_saved_value AS
WITH donations AS (
    SELECT
        d.store_id,
        SUM(di.donated_quantity * b.unit_cost) AS donated_cost_value
    FROM mottainai.donation d
    JOIN mottainai.donation_item di ON di.donation_id = d.donation_id
    JOIN mottainai.batch b ON b.batch_id = di.batch_id
    WHERE d.status <> 'CANCELED'
    GROUP BY d.store_id
), transfers AS (
    SELECT
        t.source_store_id AS store_id,
        SUM(ti.transferred_quantity * b.unit_cost) AS transferred_cost_value
    FROM mottainai.transfer t
    JOIN mottainai.transfer_item ti ON ti.transfer_id = t.transfer_id
    JOIN mottainai.batch b ON b.batch_id = ti.batch_id
    WHERE t.status IN ('IN_TRANSIT', 'COMPLETED')
    GROUP BY t.source_store_id
), disposals AS (
    SELECT
        d.store_id,
        SUM(di.disposed_quantity * b.unit_cost) AS disposed_cost_value
    FROM mottainai.disposal d
    JOIN mottainai.disposal_item di ON di.disposal_id = d.disposal_id
    JOIN mottainai.batch b ON b.batch_id = di.batch_id
    GROUP BY d.store_id
), promotion_sales AS (
    SELECT
        st.store_id,
        SUM(si.quantity_sold * b.unit_cost) AS promoted_cost_value,
        SUM(si.subtotal) AS promoted_revenue
    FROM mottainai.sales_transaction st
    JOIN mottainai.sale_item si ON si.sale_id = st.sale_id AND si.sale_date = st.sale_date
    LEFT JOIN mottainai.batch b ON b.batch_id = si.batch_id
    JOIN mottainai.promotion_item pi ON pi.product_id = si.product_id
    JOIN mottainai.promotion p ON p.promotion_id = pi.promotion_id
    WHERE st.status = 'COMPLETED'
      AND si.status = 'SOLD'
      AND p.status = 'APPROVED'
      AND p.active = TRUE
      AND st.sale_date BETWEEN p.starts_at AND p.ends_at
    GROUP BY st.store_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    COALESCE(d.donated_cost_value,0)::numeric(18,2) AS donated_value,
    COALESCE(t.transferred_cost_value,0)::numeric(18,2) AS transferred_value,
    COALESCE(ps.promoted_cost_value,0)::numeric(18,2) AS promoted_cost_value,
    COALESCE(ps.promoted_revenue,0)::numeric(18,2) AS promoted_revenue,
    COALESCE(ds.disposed_cost_value,0)::numeric(18,2) AS disposed_value,
    (
        COALESCE(d.donated_cost_value,0)
        + COALESCE(t.transferred_cost_value,0)
        + COALESCE(ps.promoted_cost_value,0)
    )::numeric(18,2) AS estimated_recovered_value,
    (
        COALESCE(d.donated_cost_value,0)
        + COALESCE(t.transferred_cost_value,0)
    )::numeric(18,2) AS non_disposal_recovery_value
FROM mottainai.retail_store rs
LEFT JOIN donations d ON d.store_id = rs.store_id
LEFT JOIN transfers t ON t.store_id = rs.store_id
LEFT JOIN disposals ds ON ds.store_id = rs.store_id
LEFT JOIN promotion_sales ps ON ps.store_id = rs.store_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 12. EFETIVIDADE DAS PROMOÇÕES
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_promotion_performance AS
WITH promo_sales AS (
    SELECT
        p.promotion_id,
        pi.product_id,
        COUNT(DISTINCT (st.sale_id, st.sale_date)) AS sales_count,
        SUM(si.quantity_sold) AS quantity_sold,
        SUM(si.subtotal) AS revenue
    FROM mottainai.promotion p
    JOIN mottainai.promotion_item pi ON pi.promotion_id = p.promotion_id
    JOIN mottainai.sales_transaction st
      ON st.store_id = p.store_id
     AND st.sale_date BETWEEN p.starts_at AND p.ends_at
     AND st.status = 'COMPLETED'
    JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
     AND si.product_id = pi.product_id
     AND si.status = 'SOLD'
    WHERE p.status = 'APPROVED'
    GROUP BY p.promotion_id, pi.product_id
), before_sales AS (
    SELECT
        p.promotion_id,
        pi.product_id,
        COALESCE(SUM(si.quantity_sold),0) AS quantity_before
    FROM mottainai.promotion p
    JOIN mottainai.promotion_item pi ON pi.promotion_id = p.promotion_id
    LEFT JOIN mottainai.sales_transaction st
      ON st.store_id = p.store_id
     AND st.sale_date >= p.starts_at - (p.ends_at - p.starts_at)
     AND st.sale_date < p.starts_at
     AND st.status = 'COMPLETED'
    LEFT JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
     AND si.product_id = pi.product_id
     AND si.status = 'SOLD'
    GROUP BY p.promotion_id, pi.product_id
)
SELECT
    p.promotion_id,
    p.store_id,
    rs.name AS store_name,
    p.name AS promotion_name,
    p.promotion_type,
    p.starts_at,
    p.ends_at,
    p.status,
    pi.product_id,
    pr.sku,
    pr.name AS product_name,
    pi.original_price,
    pi.promotional_price,
    pi.discount_percent,
    COALESCE(ps.sales_count,0) AS sales_count,
    COALESCE(ps.quantity_sold,0)::numeric(18,3) AS quantity_sold,
    COALESCE(ps.revenue,0)::numeric(18,2) AS revenue,
    COALESCE(bs.quantity_before,0)::numeric(18,3) AS quantity_sold_before,
    CASE
        WHEN COALESCE(bs.quantity_before,0) = 0 THEN NULL
        ELSE ROUND(((COALESCE(ps.quantity_sold,0) - bs.quantity_before) / bs.quantity_before) * 100, 2)
    END AS sales_lift_pct
FROM mottainai.promotion p
JOIN mottainai.promotion_item pi ON pi.promotion_id = p.promotion_id
JOIN mottainai.product pr ON pr.product_id = pi.product_id
JOIN mottainai.retail_store rs ON rs.store_id = p.store_id
LEFT JOIN promo_sales ps ON ps.promotion_id = p.promotion_id AND ps.product_id = pi.product_id
LEFT JOIN before_sales bs ON bs.promotion_id = p.promotion_id AND bs.product_id = pi.product_id;

-- ============================================================================
-- 13. PERFORMANCE DOS MODELOS DE IA
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_ai_performance AS
SELECT
    am.model_id,
    am.name AS model_name,
    am.version AS model_version,
    am.model_type,
    am.accuracy AS registered_accuracy,
    COUNT(ap.prediction_id) AS prediction_count,
    COUNT(ap.prediction_id) FILTER (WHERE ap.actual_quantity IS NOT NULL) AS evaluated_predictions,
    AVG(ap.confidence) AS avg_confidence,
    AVG(ABS(ap.predicted_quantity - ap.actual_quantity))
        FILTER (WHERE ap.actual_quantity IS NOT NULL) AS mean_absolute_error,
    AVG(
        CASE
            WHEN ap.actual_quantity IS NULL OR ap.actual_quantity = 0 THEN NULL
            ELSE ABS(ap.predicted_quantity - ap.actual_quantity) / ABS(ap.actual_quantity) * 100
        END
    ) AS mean_absolute_percentage_error,
    COUNT(ar.recommendation_id) AS recommendations_generated,
    COUNT(ar.recommendation_id) FILTER (WHERE ar.status = 'APPROVED') AS recommendations_approved,
    COUNT(ar.recommendation_id) FILTER (WHERE ar.status = 'REJECTED') AS recommendations_rejected,
    COUNT(ae.execution_id) AS executions,
    COUNT(ae.execution_id) FILTER (WHERE ae.success = TRUE) AS successful_executions,
    AVG(af.rating) AS avg_feedback_rating
FROM mottainai.ai_model am
LEFT JOIN mottainai.ai_prediction ap ON ap.model_id = am.model_id
LEFT JOIN mottainai.ai_recommendation ar ON ar.prediction_id = ap.prediction_id
LEFT JOIN mottainai.ai_execution ae ON ae.recommendation_id = ar.recommendation_id
LEFT JOIN mottainai.ai_feedback af ON af.recommendation_id = ar.recommendation_id
GROUP BY am.model_id, am.name, am.version, am.model_type, am.accuracy;

-- ============================================================================
-- 14. EFETIVIDADE DAS RECOMENDAÇÕES DA IA
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_ai_recommendation_effectiveness AS
SELECT
    ar.recommendation_id,
    ar.action_type,
    ar.priority,
    ar.status,
    ar.created_at,
    ap.prediction_id,
    ap.product_id,
    p.name AS product_name,
    ap.store_id,
    rs.name AS store_name,
    ap.predicted_date,
    ap.predicted_quantity,
    ap.actual_quantity,
    ap.confidence,
    COUNT(DISTINCT af.feedback_id) AS feedback_count,
    AVG(af.rating) AS avg_rating,
    COUNT(DISTINCT ae.execution_id) AS execution_count,
    BOOL_OR(ae.success) AS ever_executed_successfully,
    MIN(ae.executed_at) AS first_execution_at
FROM mottainai.ai_recommendation ar
LEFT JOIN mottainai.ai_prediction ap ON ap.prediction_id = ar.prediction_id
LEFT JOIN mottainai.product p ON p.product_id = ap.product_id
LEFT JOIN mottainai.retail_store rs ON rs.store_id = ap.store_id
LEFT JOIN mottainai.ai_feedback af ON af.recommendation_id = ar.recommendation_id
LEFT JOIN mottainai.ai_execution ae ON ae.recommendation_id = ar.recommendation_id
GROUP BY ar.recommendation_id, ar.action_type, ar.priority, ar.status, ar.created_at,
         ap.prediction_id, ap.product_id, p.name, ap.store_id, rs.name,
         ap.predicted_date, ap.predicted_quantity, ap.actual_quantity, ap.confidence;

-- ============================================================================
-- 15. SUSTENTABILIDADE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_sustainability_dashboard AS
WITH donations AS (
    SELECT
        d.store_id,
        SUM(di.donated_quantity) AS donated_quantity,
        SUM(di.donated_quantity * b.unit_cost) AS donated_value
    FROM mottainai.donation d
    JOIN mottainai.donation_item di ON di.donation_id = d.donation_id
    JOIN mottainai.batch b ON b.batch_id = di.batch_id
    WHERE d.status <> 'CANCELED'
    GROUP BY d.store_id
), disposals AS (
    SELECT
        d.store_id,
        SUM(di.disposed_quantity) AS disposed_quantity,
        SUM(di.disposed_quantity * b.unit_cost) AS disposed_value
    FROM mottainai.disposal d
    JOIN mottainai.disposal_item di ON di.disposal_id = d.disposal_id
    JOIN mottainai.batch b ON b.batch_id = di.batch_id
    GROUP BY d.store_id
), transfers AS (
    SELECT
        t.source_store_id AS store_id,
        SUM(ti.transferred_quantity) AS transferred_quantity,
        SUM(ti.transferred_quantity * b.unit_cost) AS transferred_value
    FROM mottainai.transfer t
    JOIN mottainai.transfer_item ti ON ti.transfer_id = t.transfer_id
    JOIN mottainai.batch b ON b.batch_id = ti.batch_id
    WHERE t.status = 'COMPLETED'
    GROUP BY t.source_store_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    COALESCE(d.donated_quantity,0)::numeric(18,3) AS donated_quantity,
    COALESCE(d.donated_value,0)::numeric(18,2) AS donated_value,
    COALESCE(ds.disposed_quantity,0)::numeric(18,3) AS disposed_quantity,
    COALESCE(ds.disposed_value,0)::numeric(18,2) AS disposed_value,
    COALESCE(t.transferred_quantity,0)::numeric(18,3) AS transferred_quantity,
    COALESCE(t.transferred_value,0)::numeric(18,2) AS transferred_value,
    CASE
        WHEN COALESCE(d.donated_quantity,0) + COALESCE(ds.disposed_quantity,0) = 0 THEN NULL
        ELSE ROUND(
            COALESCE(d.donated_quantity,0)
            / (COALESCE(d.donated_quantity,0) + COALESCE(ds.disposed_quantity,0)) * 100, 2
        )
    END AS donation_share_of_non_sale_destinations_pct,
    CASE
        WHEN COALESCE(d.donated_quantity,0) + COALESCE(ds.disposed_quantity,0) = 0 THEN NULL
        ELSE ROUND(
            COALESCE(ds.disposed_quantity,0)
            / (COALESCE(d.donated_quantity,0) + COALESCE(ds.disposed_quantity,0)) * 100, 2
        )
    END AS disposal_share_pct
FROM mottainai.retail_store rs
LEFT JOIN donations d ON d.store_id = rs.store_id
LEFT JOIN disposals ds ON ds.store_id = rs.store_id
LEFT JOIN transfers t ON t.store_id = rs.store_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 16. FORMAS DE PAGAMENTO
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_payment_analysis AS
SELECT
    st.store_id,
    rs.name AS store_name,
    DATE_TRUNC('month', sp.paid_at)::date AS month_start,
    sp.payment_method,
    COUNT(*) AS payment_count,
    SUM(sp.amount)::numeric(18,2) AS payment_amount,
    ROUND(
        SUM(sp.amount)
        / NULLIF(SUM(SUM(sp.amount)) OVER (PARTITION BY st.store_id, DATE_TRUNC('month', sp.paid_at)), 0)
        * 100, 2
    ) AS payment_share_pct,
    AVG(sp.installments)::numeric(10,2) AS avg_installments
FROM mottainai.sale_payment sp
JOIN mottainai.sales_transaction st
  ON st.sale_id = sp.sale_id
 AND st.sale_date = sp.sale_date
JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
WHERE st.status = 'COMPLETED'
  AND st.deleted_at IS NULL
GROUP BY st.store_id, rs.name, DATE_TRUNC('month', sp.paid_at), sp.payment_method;

-- ============================================================================
-- 17. FIDELIDADE / CLIENTE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_customer_loyalty_analysis AS
WITH accounts AS (
    SELECT COUNT(*) FILTER (WHERE active) AS active_accounts,
           COUNT(*) AS total_accounts,
           COALESCE(SUM(points_balance) FILTER (WHERE active),0) AS current_points
    FROM mottainai.loyalty_account
), transactions AS (
    SELECT
        COUNT(*) FILTER (WHERE transaction_type = 'EARN') AS points_earn_events,
        COALESCE(SUM(points) FILTER (WHERE transaction_type = 'EARN'),0) AS points_earned,
        COALESCE(SUM(points) FILTER (WHERE transaction_type = 'REDEEM'),0) AS points_redeemed,
        COALESCE(SUM(points) FILTER (WHERE transaction_type = 'EXPIRE'),0) AS points_expired,
        COUNT(*) FILTER (WHERE transaction_type = 'ADJUSTMENT') AS adjustment_events
    FROM mottainai.loyalty_transaction
), redemptions AS (
    SELECT
        COUNT(*) AS redemptions_total,
        COUNT(*) FILTER (WHERE status = 'CONFIRMED') AS confirmed_redemptions,
        COALESCE(SUM(points_spent) FILTER (WHERE status = 'CONFIRMED'),0) AS confirmed_points_spent
    FROM mottainai.loyalty_redemption
)
SELECT
    a.total_accounts,
    a.active_accounts,
    a.current_points,
    t.points_earn_events,
    t.points_earned,
    t.points_redeemed,
    t.points_expired,
    t.adjustment_events,
    r.redemptions_total,
    r.confirmed_redemptions,
    r.confirmed_points_spent
FROM accounts a CROSS JOIN transactions t CROSS JOIN redemptions r;

-- ============================================================================
-- 18. COMPORTAMENTO DE COMPRA DO CLIENTE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_customer_purchase_behavior AS
SELECT
    c.customer_id,
    c.full_name,
    c.cpf,
    COUNT(DISTINCT (st.sale_id, st.sale_date)) FILTER (WHERE st.status = 'COMPLETED') AS purchase_count,
    COALESCE(SUM(st.total_amount) FILTER (WHERE st.status = 'COMPLETED'),0)::numeric(18,2) AS total_spent,
    CASE
        WHEN COUNT(DISTINCT (st.sale_id, st.sale_date)) FILTER (WHERE st.status = 'COMPLETED') = 0 THEN 0
        ELSE ROUND(
            SUM(st.total_amount) FILTER (WHERE st.status = 'COMPLETED')
            / COUNT(DISTINCT (st.sale_id, st.sale_date)) FILTER (WHERE st.status = 'COMPLETED'), 2
        )
    END AS avg_ticket,
    MIN(st.sale_date) FILTER (WHERE st.status = 'COMPLETED') AS first_purchase_at,
    MAX(st.sale_date) FILTER (WHERE st.status = 'COMPLETED') AS last_purchase_at,
    COUNT(DISTINCT si.product_id) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD') AS distinct_products_bought,
    COALESCE(SUM(si.quantity_sold) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD'),0)::numeric(18,3) AS units_bought
FROM mottainai.customer c
LEFT JOIN mottainai.sales_transaction st ON st.customer_id = c.customer_id AND st.deleted_at IS NULL
LEFT JOIN mottainai.sale_item si ON si.sale_id = st.sale_id AND si.sale_date = st.sale_date
GROUP BY c.customer_id, c.full_name, c.cpf;

-- ============================================================================
-- 19. PERFORMANCE POR LOJA
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_store_performance AS
WITH sales AS (
    SELECT
        store_id,
        COUNT(DISTINCT (st.sale_id, st.sale_date)) AS sales_count,
        SUM(st.total_amount) AS revenue,
        AVG(st.total_amount) AS avg_ticket
    FROM mottainai.sales_transaction st
    WHERE st.status = 'COMPLETED' AND st.deleted_at IS NULL
    GROUP BY st.store_id
), stock AS (
    SELECT
        i.store_id,
        SUM(i.current_quantity) AS stock_quantity,
        COUNT(DISTINCT b.product_id) AS stocked_products,
        COUNT(*) FILTER (WHERE i.current_quantity <= i.minimum_quantity) AS critical_inventory_lines
    FROM mottainai.inventory i
    JOIN mottainai.batch b ON b.batch_id = i.batch_id
    WHERE i.deleted_at IS NULL AND b.deleted_at IS NULL
    GROUP BY i.store_id
), risk AS (
    SELECT
        store_id,
        COALESCE(SUM(estimated_value_at_risk),0) AS expiration_risk_value
    FROM mottainai_analytics.vw_expiration_loss_forecast
    GROUP BY store_id
), sustain AS (
    SELECT
        store_id,
        donated_value,
        disposed_value,
        transferred_value
    FROM mottainai_analytics.vw_sustainability_dashboard
), repl AS (
    SELECT
        store_id,
        AVG(execution_accuracy_pct) AS avg_replenishment_accuracy
    FROM mottainai_analytics.vw_replenishment_performance
    GROUP BY store_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    COALESCE(s.sales_count,0) AS sales_count,
    COALESCE(s.revenue,0)::numeric(18,2) AS revenue,
    COALESCE(s.avg_ticket,0)::numeric(18,2) AS avg_ticket,
    COALESCE(st.stock_quantity,0)::numeric(18,3) AS stock_quantity,
    COALESCE(st.stocked_products,0) AS stocked_products,
    COALESCE(st.critical_inventory_lines,0) AS critical_inventory_lines,
    COALESCE(r.expiration_risk_value,0)::numeric(18,2) AS expiration_risk_value,
    COALESCE(su.donated_value,0)::numeric(18,2) AS donated_value,
    COALESCE(su.disposed_value,0)::numeric(18,2) AS disposed_value,
    COALESCE(su.transferred_value,0)::numeric(18,2) AS transferred_value,
    ROUND(COALESCE(re.avg_replenishment_accuracy,0),2) AS avg_replenishment_accuracy_pct,
    DENSE_RANK() OVER (ORDER BY COALESCE(s.revenue,0) DESC) AS revenue_rank,
    DENSE_RANK() OVER (ORDER BY COALESCE(r.expiration_risk_value,0) ASC) AS expiration_risk_rank
FROM mottainai.retail_store rs
LEFT JOIN sales s ON s.store_id = rs.store_id
LEFT JOIN stock st ON st.store_id = rs.store_id
LEFT JOIN risk r ON r.store_id = rs.store_id
LEFT JOIN sustain su ON su.store_id = rs.store_id
LEFT JOIN repl re ON re.store_id = rs.store_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 20. DASHBOARD EXECUTIVO
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_executive_dashboard AS
WITH sales_30d AS (
    SELECT
        store_id,
        COUNT(DISTINCT (st.sale_id, st.sale_date)) AS sales_count,
        SUM(st.total_amount) AS revenue,
        AVG(st.total_amount) AS avg_ticket,
        SUM(si.quantity_sold) AS units_sold
    FROM mottainai.sales_transaction st
    LEFT JOIN mottainai.sale_item si
      ON si.sale_id = st.sale_id
     AND si.sale_date = st.sale_date
     AND si.status = 'SOLD'
    WHERE st.status = 'COMPLETED'
      AND st.deleted_at IS NULL
      AND st.sale_date >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY store_id
), inventory AS (
    SELECT
        i.store_id,
        SUM(i.current_quantity) AS stock_quantity,
        COUNT(*) FILTER (WHERE i.current_quantity <= i.minimum_quantity) AS critical_lines
    FROM mottainai.inventory i
    JOIN mottainai.batch b ON b.batch_id = i.batch_id
    WHERE i.deleted_at IS NULL AND b.deleted_at IS NULL
    GROUP BY i.store_id
), expiring AS (
    SELECT
        store_id,
        COUNT(*) AS expiring_lines,
        COALESCE(SUM(estimated_value_at_risk),0) AS value_at_risk
    FROM mottainai_analytics.vw_expiration_loss_forecast
    WHERE days_to_expire <= 15
    GROUP BY store_id
), alerts AS (
    SELECT
        store_id,
        COUNT(*) FILTER (WHERE status = 'ACTIVE') AS active_alerts
    FROM mottainai.alert
    GROUP BY store_id
), sustain AS (
    SELECT store_id, donated_value, disposed_value, transferred_value
    FROM mottainai_analytics.vw_sustainability_dashboard
), replenishment AS (
    SELECT store_id, AVG(execution_accuracy_pct) AS replenishment_accuracy
    FROM mottainai_analytics.vw_replenishment_performance
    GROUP BY store_id
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    COALESCE(s30.sales_count,0) AS sales_30d,
    COALESCE(s30.revenue,0)::numeric(18,2) AS revenue_30d,
    COALESCE(s30.avg_ticket,0)::numeric(18,2) AS avg_ticket_30d,
    COALESCE(s30.units_sold,0)::numeric(18,3) AS units_sold_30d,
    COALESCE(inv.stock_quantity,0)::numeric(18,3) AS current_stock,
    COALESCE(inv.critical_lines,0) AS critical_stock_lines,
    COALESCE(ex.expiring_lines,0) AS expiring_lines_15d,
    COALESCE(ex.value_at_risk,0)::numeric(18,2) AS expiration_value_at_risk,
    COALESCE(a.active_alerts,0) AS active_alerts,
    COALESCE(su.donated_value,0)::numeric(18,2) AS donated_value,
    COALESCE(su.disposed_value,0)::numeric(18,2) AS disposed_value,
    COALESCE(su.transferred_value,0)::numeric(18,2) AS transferred_value,
    ROUND(COALESCE(r.replenishment_accuracy,0),2) AS replenishment_accuracy_pct,
    CASE
        WHEN COALESCE(ex.value_at_risk,0) >= 10000 OR COALESCE(inv.critical_lines,0) >= 20 THEN 'CRITICAL'
        WHEN COALESCE(ex.value_at_risk,0) >= 5000 OR COALESCE(inv.critical_lines,0) >= 10 THEN 'HIGH'
        WHEN COALESCE(ex.value_at_risk,0) > 0 OR COALESCE(inv.critical_lines,0) > 0 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS operational_risk
FROM mottainai.retail_store rs
LEFT JOIN sales_30d s30 ON s30.store_id = rs.store_id
LEFT JOIN inventory inv ON inv.store_id = rs.store_id
LEFT JOIN expiring ex ON ex.store_id = rs.store_id
LEFT JOIN alerts a ON a.store_id = rs.store_id
LEFT JOIN sustain su ON su.store_id = rs.store_id
LEFT JOIN replenishment r ON r.store_id = rs.store_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL;

-- ============================================================================
-- 21. HISTÓRICO MENSAL GERENCIAL
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_monthly_summary AS
SELECT
    DATE_TRUNC('month', st.sale_date)::date AS month_start,
    st.store_id,
    rs.name AS store_name,
    COUNT(DISTINCT (st.sale_id, st.sale_date)) AS total_sales,
    COALESCE(SUM(st.total_amount),0)::numeric(18,2) AS total_revenue,
    COALESCE(AVG(st.total_amount),0)::numeric(18,2) AS avg_ticket,
    COUNT(DISTINCT st.employee_id) AS active_sellers,
    COALESCE(SUM(si.quantity_sold) FILTER (WHERE si.status = 'SOLD'),0)::numeric(18,3) AS units_sold
FROM mottainai.sales_transaction st
JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
LEFT JOIN mottainai.sale_item si
  ON si.sale_id = st.sale_id
 AND si.sale_date = st.sale_date
WHERE st.status = 'COMPLETED'
  AND st.deleted_at IS NULL
GROUP BY DATE_TRUNC('month', st.sale_date), st.store_id, rs.name;

-- ============================================================================
-- 22. PROMOÇÕES ATIVAS PARA O MOBILE CLIENTE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_active_customer_promotions AS
SELECT
    p.promotion_id,
    p.store_id,
    s.name AS store_name,
    s.latitude,
    s.longitude,
    p.name AS promotion_name,
    p.description,
    p.starts_at,
    p.ends_at,
    pi.product_id,
    pr.sku,
    pr.name AS product_name,
    pi.original_price,
    pi.promotional_price,
    pi.discount_percent,
    pi.quantity_available
FROM mottainai.promotion p
JOIN mottainai.promotion_item pi ON pi.promotion_id = p.promotion_id
JOIN mottainai.product pr ON pr.product_id = pi.product_id
JOIN mottainai.retail_store s ON s.store_id = p.store_id
WHERE p.active = TRUE
  AND p.status = 'APPROVED'
  AND p.starts_at <= CURRENT_TIMESTAMP
  AND p.ends_at > CURRENT_TIMESTAMP
  AND pr.active = TRUE
  AND pr.deleted_at IS NULL;

-- ============================================================================
-- 23. HISTÓRICO DE COMPRAS DO CLIENTE PARA O MOBILE
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_customer_purchase_history AS
SELECT
    c.customer_id,
    st.sale_id,
    st.sale_date,
    st.store_id,
    rs.name AS store_name,
    st.total_amount,
    st.status AS sale_status,
    si.sale_item_id,
    si.product_id,
    p.sku,
    p.name AS product_name,
    si.quantity_sold,
    si.unit_price,
    si.subtotal,
    si.status AS item_status
FROM mottainai.customer c
JOIN mottainai.sales_transaction st ON st.customer_id = c.customer_id
JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
JOIN mottainai.sale_item si
  ON si.sale_id = st.sale_id
 AND si.sale_date = st.sale_date
JOIN mottainai.product p ON p.product_id = si.product_id
WHERE st.deleted_at IS NULL;

-- ============================================================================
-- 24. RESUMO DE RISCO E AÇÃO DA IA
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_ai_action_funnel AS
SELECT
    ar.action_type,
    COUNT(*) AS recommendations,
    COUNT(*) FILTER (WHERE ar.status = 'APPROVED') AS approved,
    COUNT(*) FILTER (WHERE ar.status = 'REJECTED') AS rejected,
    COUNT(*) FILTER (WHERE ar.status = 'EXECUTED') AS executed_status,
    COUNT(DISTINCT ae.recommendation_id) AS executed_records,
    COUNT(DISTINCT ae.recommendation_id) FILTER (WHERE ae.success) AS successful_executions,
    CASE WHEN COUNT(*) = 0 THEN 0
         ELSE ROUND(COUNT(*) FILTER (WHERE ar.status = 'APPROVED')::numeric / COUNT(*) * 100, 2)
    END AS approval_rate_pct,
    CASE WHEN COUNT(DISTINCT ae.recommendation_id) = 0 THEN 0
         ELSE ROUND(COUNT(DISTINCT ae.recommendation_id) FILTER (WHERE ae.success)::numeric
                    / COUNT(DISTINCT ae.recommendation_id) * 100, 2)
    END AS execution_success_rate_pct
FROM mottainai.ai_recommendation ar
LEFT JOIN mottainai.ai_execution ae ON ae.recommendation_id = ar.recommendation_id
GROUP BY ar.action_type;

-- ============================================================================
-- 25. RANKING DE PRODUTOS COM MAIS PERDAS (tela Inicio)
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_top_loss_products AS
WITH losses AS (
    SELECT
        d.store_id,
        di.batch_id,
        b.product_id,
        'DISPOSAL'::TEXT AS loss_type,
        di.disposed_quantity AS quantity,
        di.disposed_quantity * b.unit_cost AS value
    FROM mottainai.disposal d
    JOIN mottainai.disposal_item di ON di.disposal_id = d.disposal_id
    JOIN mottainai.batch b ON b.batch_id = di.batch_id
    UNION ALL
    SELECT
        dn.store_id,
        dni.batch_id,
        b.product_id,
        'DONATION'::TEXT,
        dni.donated_quantity,
        dni.donated_quantity * b.unit_cost
    FROM mottainai.donation dn
    JOIN mottainai.donation_item dni ON dni.donation_id = dn.donation_id
    JOIN mottainai.batch b ON b.batch_id = dni.batch_id
    WHERE dn.status <> 'CANCELED'
)
SELECT
    rs.store_id,
    rs.name AS store_name,
    l.product_id,
    p.sku,
    p.name AS product_name,
    pc.name AS category_name,
    COUNT(*) AS loss_events,
    COALESCE(SUM(l.quantity), 0)::numeric(18,3) AS total_lost_quantity,
    COALESCE(SUM(l.value), 0)::numeric(18,2) AS total_lost_value,
    SUM(l.quantity) FILTER (WHERE l.loss_type = 'DISPOSAL')::numeric(18,3) AS disposed_quantity,
    SUM(l.value) FILTER (WHERE l.loss_type = 'DISPOSAL')::numeric(18,2) AS disposed_value,
    DENSE_RANK() OVER (PARTITION BY rs.store_id ORDER BY COALESCE(SUM(l.value), 0) DESC) AS loss_rank
FROM losses l
JOIN mottainai.retail_store rs ON rs.store_id = l.store_id
JOIN mottainai.product p ON p.product_id = l.product_id
JOIN mottainai.product_category pc ON pc.category_id = p.category_id
WHERE rs.active = TRUE
  AND rs.deleted_at IS NULL
GROUP BY rs.store_id, rs.name, l.product_id, p.sku, p.name, pc.name
HAVING COALESCE(SUM(l.value), 0) > 0
ORDER BY rs.store_id ASC, total_lost_value DESC;

-- ============================================================================
-- 26. SAZONALIDADE - VENDAS POR DIA DA SEMANA (tela Habitos)
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_seasonality_by_weekday AS
SELECT
    st.store_id,
    rs.name AS store_name,
    EXTRACT(DOW FROM st.sale_date)::INTEGER AS weekday_number,
    TO_CHAR(st.sale_date, 'TMDay') AS weekday_name,
    COUNT(DISTINCT (st.sale_id, st.sale_date)) AS sales_count,
    COALESCE(SUM(st.total_amount) FILTER (WHERE st.status = 'COMPLETED'), 0)::numeric(18,2) AS revenue,
    COALESCE(SUM(si.quantity_sold) FILTER (WHERE si.status = 'SOLD'), 0)::numeric(18,3) AS units_sold,
    ROUND(COALESCE(AVG(st.total_amount) FILTER (WHERE st.status = 'COMPLETED'), 0), 2) AS avg_ticket
FROM mottainai.sales_transaction st
JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
LEFT JOIN mottainai.sale_item si
  ON si.sale_id = st.sale_id
 AND si.sale_date = st.sale_date
WHERE st.deleted_at IS NULL
GROUP BY st.store_id, rs.name, EXTRACT(DOW FROM st.sale_date), TO_CHAR(st.sale_date, 'TMDay')
ORDER BY st.store_id ASC, weekday_number ASC;

-- ============================================================================
-- 27. CATEGORIA DE MAIOR SAIDA (tela Habitos)
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_top_selling_categories AS
SELECT
    st.store_id,
    rs.name AS store_name,
    pc.category_id,
    pc.name AS category_name,
    SUM(si.quantity_sold) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD')::numeric(18,3) AS quantity_sold,
    SUM(si.subtotal) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD')::numeric(18,2) AS revenue,
    COUNT(DISTINCT p.product_id) AS distinct_products,
    DENSE_RANK() OVER (PARTITION BY st.store_id ORDER BY
        SUM(si.quantity_sold) FILTER (WHERE st.status = 'COMPLETED' AND si.status = 'SOLD') DESC) AS category_rank
FROM mottainai.sales_transaction st
JOIN mottainai.retail_store rs ON rs.store_id = st.store_id
JOIN mottainai.sale_item si
  ON si.sale_id = st.sale_id
 AND si.sale_date = st.sale_date
JOIN mottainai.product p ON p.product_id = si.product_id
JOIN mottainai.product_category pc ON pc.category_id = p.category_id
WHERE st.deleted_at IS NULL
GROUP BY st.store_id, rs.name, pc.category_id, pc.name
ORDER BY st.store_id ASC, quantity_sold DESC;

-- ============================================================================
-- 28. DIAGNOSTICO DO MOTOR (tela Visao Geral)
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_engine_diagnostics AS
SELECT
    es.store_id,
    rs.name AS store_name,
    MAX(es.scanned_at) AS last_scan_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(es.scanned_at))) / 60 AS minutes_since_last_scan,
    COALESCE(SUM(es.skus_scanned), 0) AS total_skus_scanned,
    COALESCE(SUM(es.diagnostics_count), 0) AS total_diagnostics,
    ROUND(COALESCE(AVG(es.assertiveness_rate), 0), 2) AS avg_assertiveness_rate,
    COUNT(es.scan_id) AS scan_count,
    (SELECT COUNT(*) FROM mottainai.engine_suggestion s
      WHERE s.store_id = es.store_id) AS total_suggestions
FROM mottainai.engine_scan_log es
JOIN mottainai.retail_store rs ON rs.store_id = es.store_id
WHERE rs.active = TRUE AND rs.deleted_at IS NULL
GROUP BY es.store_id, rs.name;

-- ============================================================================
-- 29. METRICAS DE SUGESTOES DO MOTOR (tela Visao Geral)
-- ============================================================================
CREATE OR REPLACE VIEW mottainai_analytics.vw_engine_suggestion_metrics AS
WITH per_store AS (
    SELECT
        es.store_id,
        rs.name AS store_name,
        es.tactic,
        es.status,
        COUNT(*) AS total
    FROM mottainai.engine_suggestion es
    JOIN mottainai.retail_store rs ON rs.store_id = es.store_id
    WHERE rs.active = TRUE AND rs.deleted_at IS NULL
    GROUP BY es.store_id, rs.name, es.tactic, es.status
)
SELECT
    store_id,
    store_name,
    tactic,
    COALESCE(SUM(total) FILTER (WHERE status = 'ACCEPTED'), 0) AS accepted,
    COALESCE(SUM(total) FILTER (WHERE status = 'REJECTED'), 0) AS rejected,
    COALESCE(SUM(total) FILTER (WHERE status = 'EDITED'), 0) AS edited,
    COALESCE(SUM(total) FILTER (WHERE status = 'EXECUTED'), 0) AS executed,
    COALESCE(SUM(total) FILTER (WHERE status IN ('ACCEPTED','EXECUTED')), 0) AS accepted_or_executed,
    COALESCE(SUM(total), 0) AS total_suggestions
FROM per_store
GROUP BY store_id, store_name, tactic
ORDER BY store_id ASC, total_suggestions DESC;

-- ============================================================================
-- FIM
-- ============================================================================
