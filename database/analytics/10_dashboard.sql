-- Dados e views que sustentam o dashboard de empresas, lojas e funcionarios.
-- Execute conectado ao banco fisico analitico.
SET search_path TO mottainai_analytics, public;

ALTER TABLE dim_company ADD COLUMN IF NOT EXISTS plan_name VARCHAR(150);

CREATE TABLE IF NOT EXISTS fact_store_daily (
    snapshot_date DATE NOT NULL,
    company_id BIGINT NOT NULL,
    store_id BIGINT NOT NULL,
    employees_total INTEGER NOT NULL DEFAULT 0,
    employees_active INTEGER NOT NULL DEFAULT 0,
    users_total INTEGER NOT NULL DEFAULT 0,
    users_active INTEGER NOT NULL DEFAULT 0,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (snapshot_date, store_id)
);

CREATE INDEX IF NOT EXISTS idx_fact_store_daily_company_date
    ON fact_store_daily (company_id, snapshot_date DESC);

CREATE OR REPLACE VIEW vw_company_kpis AS
WITH latest_store AS (
    SELECT f.*,
           row_number() OVER (PARTITION BY store_id ORDER BY snapshot_date DESC) AS rn
    FROM fact_store_daily f
), totals AS (
    SELECT c.company_id,
           c.legal_name AS official_name,
           c.plan_name,
           coalesce(sum(f.employees_total), 0)::integer AS employees_total,
           coalesce(sum(f.employees_active), 0)::integer AS employees_active,
           coalesce(sum(f.users_total), 0)::integer AS users_total,
           coalesce(sum(f.users_active), 0)::integer AS users_active,
           count(f.store_id)::integer AS stores_total
    FROM dim_company c
    LEFT JOIN latest_store f ON f.company_id = c.company_id AND f.rn = 1
    GROUP BY c.company_id, c.legal_name, c.plan_name
)
SELECT totals.*,
       rank() OVER (ORDER BY employees_active DESC, users_active DESC) AS active_rank
FROM totals;

CREATE OR REPLACE VIEW vw_employee_distribution AS
WITH role_counts AS (
    SELECT coalesce(role_name, 'Sem funcao') AS role_name,
           count(*)::integer AS employees_total,
           count(*) FILTER (WHERE active)::integer AS employees_active
    FROM dim_employee
    GROUP BY coalesce(role_name, 'Sem funcao')
)
SELECT role_name, employees_total, employees_active,
       round(100.0 * employees_active / nullif(sum(employees_active) OVER (), 0), 2)
           AS active_share_percent
FROM role_counts;

CREATE OR REPLACE VIEW vw_store_daily_kpis AS
SELECT f.snapshot_date AS full_date,
       c.company_id, c.legal_name AS official_name,
       s.store_id, s.name AS store_name, s.city, s.state_code AS state,
       f.employees_total, f.employees_active, f.users_total, f.users_active,
       f.users_active - lag(f.users_active) OVER
           (PARTITION BY f.store_id ORDER BY f.snapshot_date) AS users_active_delta
FROM fact_store_daily f
JOIN dim_company c ON c.company_id = f.company_id
JOIN dim_store s ON s.store_id = f.store_id;
