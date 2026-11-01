\set ON_ERROR_STOP on
\echo 'Applying the incremental POS API migrations to mottainai_operational'

-- Do not wrap this sequence in one transaction: enum values added in 31 and 33
-- must be committed before later migrations use those values.
\ir 31_pos_api_sale_draft.sql
\ir 32_pos_api_idempotency.sql
\ir 33_pos_api_draft_items_and_shift_grants.sql
\ir 34_pos_api_draft_items_no_batch.sql
\ir 35_pos_api_customer_lookup.sql
\ir 36_api_soft_delete_promotion_items.sql
\ir 37_pos_manager_approvals.sql

\echo 'POS API migrations applied successfully'
