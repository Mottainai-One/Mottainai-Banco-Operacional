-- Product image URLs are stored in Cloudinary, never as file bytes in PostgreSQL.
BEGIN;

ALTER TABLE mottainai.product
    ADD COLUMN IF NOT EXISTS image_url VARCHAR(2048);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'mottainai.product'::regclass
          AND conname = 'ck_product_image_url_cloudinary_https'
    ) THEN
        ALTER TABLE mottainai.product
            ADD CONSTRAINT ck_product_image_url_cloudinary_https
            CHECK (
                image_url IS NULL
                OR image_url ~ '^https://res[.]cloudinary[.]com/[A-Za-z0-9_-]+/image/upload/[^[:space:]?#]+([?][^[:space:]#]*)?$'
            );
    END IF;
END;
$$;

-- Existing product RLS remains in force; this only enables the API to use the
-- new column under the existing product/company policy.
GRANT SELECT (image_url), INSERT (image_url), UPDATE (image_url)
    ON mottainai.product TO mottainai_api;

INSERT INTO mottainai.schema_version
    (version, description, type, script, installed_by)
VALUES
    ('40', 'Add Cloudinary product image URL', 'SQL', '40_mobile_product_image_url.sql', CURRENT_USER)
ON CONFLICT (version) DO NOTHING;

COMMIT;
