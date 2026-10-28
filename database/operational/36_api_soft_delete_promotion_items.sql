-- Mirror Spring API Flyway V11 so promotion items can be soft-deleted and
-- replaced for the same promotion/product pair without losing history.
BEGIN;

ALTER TABLE mottainai.promotion_item
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

ALTER TABLE mottainai.promotion_item
    DROP CONSTRAINT IF EXISTS promotion_item_promotion_id_product_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_promotion_item_active_product
    ON mottainai.promotion_item (promotion_id, product_id)
    WHERE deleted_at IS NULL;

COMMIT;
