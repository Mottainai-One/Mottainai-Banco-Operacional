\set ON_ERROR_STOP on

-- Demonstration data load for BI validation.
-- Execute connected to the operational database MOTTAINAI only when approved.
-- The script uses existing master data and is idempotent for the current date.

BEGIN;

CREATE TEMP TABLE demo_context ON COMMIT DROP AS
SELECT
    s.company_id,
    s.store_id,
    e.employee_id,
    t.terminal_id,
    p.product_id,
    i.batch_id
FROM mottainai.retail_store s
JOIN mottainai.employee e ON e.store_id = s.store_id AND e.active
LEFT JOIN mottainai.pos_terminal t ON t.store_id = s.store_id AND t.active
JOIN mottainai.inventory i ON i.store_id = s.store_id
JOIN mottainai.batch b ON b.batch_id = i.batch_id AND b.active
JOIN mottainai.product p ON p.product_id = b.product_id AND p.active
WHERE s.active
ORDER BY s.store_id, e.employee_id, p.product_id
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM demo_context) THEN
        RAISE EXCEPTION
            'No active store, employee, inventory and product context is available for demo data';
    END IF;
END $$;

-- Audited operational writes need a valid company context.
SELECT mottainai.fn_set_legacy_migration_context(company_id)
FROM demo_context;

INSERT INTO mottainai.pos_terminal (
    store_id, terminal_code, name, active
)
SELECT store_id, 'DEMO-01', 'BI demo terminal', TRUE
FROM demo_context
WHERE terminal_id IS NULL
ON CONFLICT (store_id, terminal_code) DO UPDATE
SET active = TRUE,
    updated_at = CURRENT_TIMESTAMP;

UPDATE demo_context c
SET terminal_id = t.terminal_id
FROM mottainai.pos_terminal t
WHERE t.store_id = c.store_id
  AND t.terminal_code = 'DEMO-01';

INSERT INTO mottainai.pos_shift (
    terminal_id, employee_id, opened_at, opening_amount, status, observation
)
SELECT terminal_id, employee_id, CURRENT_DATE + TIME '08:00', 0, 'OPEN',
       'DEMO_DATALOAD_' || CURRENT_DATE
FROM demo_context
WHERE NOT EXISTS (
    SELECT 1
    FROM mottainai.pos_shift ps
    WHERE ps.terminal_id = demo_context.terminal_id
      AND ps.employee_id = demo_context.employee_id
      AND ps.opened_at::date = CURRENT_DATE
      AND ps.observation = 'DEMO_DATALOAD_' || CURRENT_DATE
);

CREATE TEMP TABLE demo_sale ON COMMIT DROP AS
WITH context AS (
    SELECT c.*, sh.shift_id
    FROM demo_context c
    JOIN mottainai.pos_shift sh
      ON sh.terminal_id = c.terminal_id
     AND sh.employee_id = c.employee_id
     AND sh.opened_at::date = CURRENT_DATE
     AND sh.observation = 'DEMO_DATALOAD_' || CURRENT_DATE
), inserted AS (
    INSERT INTO mottainai.sales_transaction (
        store_id, employee_id, shift_id, sale_date, total_amount,
        status, observation
    )
    SELECT store_id, employee_id, shift_id,
           CURRENT_DATE + TIME '10:00', 25.00, 'COMPLETED',
           'DEMO_DATALOAD_' || CURRENT_DATE
    FROM context
    WHERE NOT EXISTS (
        SELECT 1
        FROM mottainai.sales_transaction existing
        WHERE existing.store_id = context.store_id
          AND existing.sale_date::date = CURRENT_DATE
          AND existing.observation = 'DEMO_DATALOAD_' || CURRENT_DATE
    )
    RETURNING sale_id, sale_date
)
SELECT inserted.sale_id, inserted.sale_date, context.product_id, context.batch_id
FROM inserted
JOIN context ON TRUE;

INSERT INTO mottainai.sale_item (
    sale_id, product_id, batch_id, quantity_sold, unit_price, sale_date
)
SELECT sale_id, product_id, batch_id, 1, 25.00, sale_date
FROM demo_sale
ON CONFLICT DO NOTHING;

INSERT INTO mottainai.sale_payment (
    sale_id, sale_date, payment_method, amount, installments,
    authorization_code, paid_at
)
SELECT sale_id, sale_date, 'PIX', 25.00, 1,
       'DEMO-' || CURRENT_DATE, sale_date
FROM demo_sale
ON CONFLICT DO NOTHING;

COMMIT;

SELECT
    CURRENT_DATE AS demo_date,
    COUNT(*) AS demo_sales_created
FROM mottainai.sales_transaction
WHERE observation = 'DEMO_DATALOAD_' || CURRENT_DATE;
