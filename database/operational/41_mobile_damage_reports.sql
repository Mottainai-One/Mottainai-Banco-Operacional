-- Store-scoped reports of product damage submitted by the staff API.
BEGIN;

CREATE TABLE IF NOT EXISTS mottainai.damage_report (
    damage_report_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id INTEGER NOT NULL
        REFERENCES mottainai.retail_store (store_id) ON DELETE RESTRICT,
    employee_id INTEGER NOT NULL
        REFERENCES mottainai.employee (employee_id) ON DELETE RESTRICT,
    product_id INTEGER NOT NULL
        REFERENCES mottainai.product (product_id) ON DELETE RESTRICT,
    reason VARCHAR(100) NOT NULL
        CHECK (btrim(reason) <> ''),
    quantity NUMERIC(12,3) NOT NULL
        CHECK (quantity > 0),
    note VARCHAR(500),
    photo_url VARCHAR(2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_damage_report_photo_cloudinary_https
        CHECK (
            photo_url IS NULL
            OR photo_url ~ '^https://res[.]cloudinary[.]com/[A-Za-z0-9_-]+/image/upload/[^[:space:]?#]+([?][^[:space:]#]*)?$'
        )
);

CREATE INDEX IF NOT EXISTS idx_damage_report_store_created_at
    ON mottainai.damage_report (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_damage_report_employee
    ON mottainai.damage_report (employee_id);
CREATE INDEX IF NOT EXISTS idx_damage_report_product
    ON mottainai.damage_report (product_id);

ALTER TABLE mottainai.damage_report ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS damage_report_api_select ON mottainai.damage_report;
CREATE POLICY damage_report_api_select
    ON mottainai.damage_report
    FOR SELECT TO mottainai_api
    USING (store_id = mottainai.fn_get_current_store_id());

DROP POLICY IF EXISTS damage_report_api_insert ON mottainai.damage_report;
CREATE POLICY damage_report_api_insert
    ON mottainai.damage_report
    FOR INSERT TO mottainai_api
    WITH CHECK (store_id = mottainai.fn_get_current_store_id());

REVOKE ALL ON TABLE mottainai.damage_report FROM PUBLIC;
GRANT SELECT (
    damage_report_id, store_id, employee_id, product_id,
    reason, quantity, note, photo_url, created_at
) ON mottainai.damage_report TO mottainai_api;
GRANT INSERT (
    store_id, employee_id, product_id, reason, quantity, note, photo_url
) ON mottainai.damage_report TO mottainai_api;
GRANT USAGE, SELECT
    ON SEQUENCE mottainai.damage_report_damage_report_id_seq
    TO mottainai_api;
GRANT EXECUTE ON FUNCTION mottainai.fn_get_current_store_id()
    TO mottainai_api;

INSERT INTO mottainai.schema_version
    (version, description, type, script, installed_by)
VALUES
    ('41', 'Add store-scoped product damage reports', 'SQL', '41_mobile_damage_reports.sql', CURRENT_USER)
ON CONFLICT (version) DO NOTHING;

COMMIT;
