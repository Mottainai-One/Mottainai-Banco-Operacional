-- This enum addition must commit before the draft trigger migration uses DRAFT.
ALTER TYPE mottainai.sale_item_status
    ADD VALUE IF NOT EXISTS 'DRAFT';

BEGIN;

ALTER TABLE mottainai.pos_api_idempotency
    ADD COLUMN IF NOT EXISTS entity_partition_date TIMESTAMPTZ;

-- POS shift writes keep using the existing tenant-scoped RLS policy.
GRANT INSERT, UPDATE ON mottainai.pos_shift TO mottainai_api;
GRANT USAGE, SELECT ON SEQUENCE mottainai.pos_shift_shift_id_seq
    TO mottainai_api;

COMMIT;
