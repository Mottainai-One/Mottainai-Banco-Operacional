-- Add the POS cart state to the operational sale status contract.
-- Keep this ALTER TYPE in its own autocommitted migration. PostgreSQL does
-- not allow a newly added enum value to be used before its transaction ends.
ALTER TYPE mottainai.sale_status
    ADD VALUE IF NOT EXISTS 'DRAFT' BEFORE 'COMPLETED';
