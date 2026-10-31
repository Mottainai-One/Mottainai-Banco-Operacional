SET search_path TO mottainai, public;

CREATE OR REPLACE VIEW vw_expiring_products AS
SELECT b.batch_id, b.batch_code, p.product_id, p.name AS product,
       s.store_id, s.name AS store, b.expiration_date,
       b.expiration_date - CURRENT_DATE AS days_to_expire,
       i.current_quantity
FROM batch b
JOIN inventory i ON i.batch_id = b.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE b.active AND i.current_quantity > 0
  AND b.deleted_at IS NULL AND i.deleted_at IS NULL
  AND b.expiration_date <= CURRENT_DATE + 15
ORDER BY b.expiration_date;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT i.inventory_id, p.product_id, p.name AS product,
       i.store_id, s.name AS store, i.current_quantity, i.minimum_quantity
FROM inventory i
JOIN batch b ON b.batch_id = i.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE i.current_quantity < i.minimum_quantity
  AND i.deleted_at IS NULL AND b.deleted_at IS NULL;

CREATE OR REPLACE VIEW vw_current_store_price AS
SELECT spp.store_id, spp.product_id, p.sku, p.barcode, p.name,
       spp.regular_price, spp.valid_from, spp.valid_until, spp.version
FROM store_product_price spp
JOIN product p ON p.product_id = spp.product_id
WHERE spp.active
  AND spp.valid_from <= CURRENT_TIMESTAMP
  AND (spp.valid_until IS NULL OR spp.valid_until > CURRENT_TIMESTAMP)
  AND p.active AND p.deleted_at IS NULL;

CREATE OR REPLACE VIEW vw_active_customer_promotions AS
SELECT p.promotion_id, p.store_id, s.name AS store_name,
       p.name AS promotion_name, p.starts_at, p.ends_at,
       pi.product_id, pr.sku, pr.name AS product_name,
       pi.original_price, pi.promotional_price, pi.discount_percent,
       pi.quantity_available
FROM promotion p
JOIN promotion_item pi ON pi.promotion_id = p.promotion_id
JOIN product pr ON pr.product_id = pi.product_id
JOIN retail_store s ON s.store_id = p.store_id
WHERE p.active AND p.status = 'APPROVED'
  AND p.starts_at <= CURRENT_TIMESTAMP AND p.ends_at > CURRENT_TIMESTAMP
  AND pr.active AND pr.deleted_at IS NULL;
