\set ON_ERROR_STOP on

-- Upgrade an existing MOTTAINAI operational database with migration 42 only.
-- Run with the administrative migration principal after migrations 38, 40,
-- and 41 are installed. This script does not load fixtures or test data.
--
-- Example from the repository root:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/operational/update_existing_customer_promotion_notifications.sql
--
-- A separate trusted server-side worker must poll
-- fn_claim_customer_promotion_notifications and publish through FCM. Grant
-- mottainai_notification_worker only to that worker's dedicated DB principal;
-- never grant it to mottainai_client_api or expose FCM credentials to clients.
-- Push delivery is at-least-once: the queue prevents duplicate campaign rows,
-- while the worker should use delivery_id as its provider idempotency key where
-- supported and tolerate provider retries.

\ir 42_customer_promotion_notifications.sql
