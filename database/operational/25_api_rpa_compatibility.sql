-- ============================================================================
-- API AND LEGACY RPA COMPATIBILITY
-- PostgreSQL 15+
--
-- Evolves existing installations without disabling RLS, audit triggers or
-- protected-data constraints. This module is safe to reapply.
-- ============================================================================

SET search_path TO mottainai, public;

-- Domain values required by the current API contract.
ALTER TYPE promotion_status ADD VALUE IF NOT EXISTS 'CANCELLED';
ALTER TYPE suggested_action_type ADD VALUE IF NOT EXISTS 'PURCHASE_ORDER';

-- Soft-deletion columns consumed by JPA repositories and API query views.
ALTER TABLE inventory_count_item
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE purchase_order_item
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

-- Jobs are tenant-owned when they are exposed through the monitoring API.
-- Existing global rows remain NULL and are intentionally not visible to a
-- tenant until an administrator assigns their owning company.
ALTER TABLE job_log
    ADD COLUMN IF NOT EXISTS company_id INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'mottainai.job_log'::REGCLASS
          AND conname = 'fk_job_log_company'
    ) THEN
        ALTER TABLE job_log
            ADD CONSTRAINT fk_job_log_company
            FOREIGN KEY (company_id)
            REFERENCES company(company_id)
            ON DELETE RESTRICT;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_inventory_count_item_active
    ON inventory_count_item (inventory_count_id, inventory_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_order_item_active
    ON purchase_order_item (purchase_order_id, order_date, purchase_order_item_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_order_store_order_date_active
    ON purchase_order (store_id, order_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier_order_date_active
    ON purchase_order (supplier_id, order_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_receiving_receiving_date
    ON receiving (receiving_date DESC);

CREATE INDEX IF NOT EXISTS idx_event_queue_company_occurred_at
    ON event_queue (company_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_job_log_company_start_time
    ON job_log (company_id, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_product_history_product_changed_at
    ON product_history (product_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_price_history_product_changed_at
    ON product_price_history (product_id, changed_at DESC);

-- Empty transaction-local settings represent an intentionally absent user or
-- store during legacy imports and must resolve to NULL instead of failing a
-- cast to INTEGER.
CREATE OR REPLACE FUNCTION fn_get_current_user_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', TRUE), '')::INTEGER;
$$;

CREATE OR REPLACE FUNCTION fn_get_current_company_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
    SELECT NULLIF(current_setting('app.current_company_id', TRUE), '')::INTEGER;
$$;

CREATE OR REPLACE FUNCTION fn_get_current_store_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
    SELECT NULLIF(current_setting('app.current_store_id', TRUE), '')::INTEGER;
$$;

-- Protected values used by the legacy RPA. These functions keep their own
-- resolution independent from the caller's search_path.
CREATE OR REPLACE FUNCTION fn_is_legacy_masked_email(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~* '^EMAIL_[A-Z]+_[0-9]+$'
        OR p_value ~* '^USER_[0-9]+$'
        OR p_value ~ '^[A-Za-z0-9._%+-]*\*{3}@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_legacy_masked_phone(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT p_value ~* '^PHONE_[A-Z]+_[0-9]+$'
        OR p_value ~ '^\([0-9]{2}\) 9\*{4}-[0-9]{4}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_email(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT mottainai.fn_is_sha256_token(p_value, 'EMAIL')
        OR mottainai.fn_is_legacy_masked_email(p_value);
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_phone(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $$
    SELECT mottainai.fn_is_sha256_token(p_value, 'PHONE')
        OR mottainai.fn_is_legacy_masked_phone(p_value);
$$;

CREATE OR REPLACE FUNCTION fn_sync_app_user_cpf()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_employee_cpf VARCHAR(80);
BEGIN
    SELECT employee.cpf
    INTO v_employee_cpf
    FROM mottainai.employee
    WHERE employee.employee_id = NEW.employee_id;

    IF v_employee_cpf IS NULL THEN
        RAISE EXCEPTION
            'Employee % does not exist or has no protected CPF token',
            NEW.employee_id;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.cpf IS NULL THEN
        NEW.cpf := v_employee_cpf;
    ELSIF NEW.cpf IS DISTINCT FROM v_employee_cpf THEN
        RAISE EXCEPTION
            'app_user.cpf must match the protected employee CPF token';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_propagate_employee_cpf()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    UPDATE mottainai.app_user
    SET cpf = NEW.cpf
    WHERE employee_id = NEW.employee_id;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_is_legacy_masked_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_legacy_masked_phone(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_phone(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_sync_app_user_cpf() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_propagate_employee_cpf() FROM PUBLIC;

-- Dedicated, non-login role for controlled legacy imports. The actual RPA
-- login must receive membership through an out-of-band administrator action.
DO $$
DECLARE
    v_is_superuser BOOLEAN;
    v_has_replication BOOLEAN;
    v_bypasses_rls BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_migrator') THEN
        CREATE ROLE mottainai_migrator
            NOLOGIN
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT;
    END IF;

    SELECT rolsuper, rolreplication, rolbypassrls
    INTO v_is_superuser, v_has_replication, v_bypasses_rls
    FROM pg_roles
    WHERE rolname = 'mottainai_migrator';

    IF v_is_superuser OR v_has_replication OR v_bypasses_rls THEN
        RAISE EXCEPTION
            'Role mottainai_migrator must not be SUPERUSER, REPLICATION or BYPASSRLS';
    END IF;

    ALTER ROLE mottainai_migrator
        NOLOGIN
        NOCREATEDB
        NOCREATEROLE
        NOINHERIT;
END;
$$;

REVOKE SET ON PARAMETER app.current_operation FROM PUBLIC;
REVOKE SET ON PARAMETER app.legacy_context_authorized FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM mottainai_migrator;

CREATE OR REPLACE FUNCTION fn_set_legacy_migration_context(p_company_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    IF p_company_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM mottainai.company
        WHERE company.company_id = p_company_id
          AND company.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Company % is not valid for a legacy import', p_company_id;
    END IF;

    PERFORM pg_catalog.set_config('app.current_user_id', '', TRUE);
    PERFORM pg_catalog.set_config(
        'app.current_company_id', p_company_id::TEXT, TRUE);
    PERFORM pg_catalog.set_config('app.current_store_id', '', TRUE);
    PERFORM pg_catalog.set_config(
        'app.current_operation', 'legacy-import', TRUE);
    PERFORM pg_catalog.set_config(
        'app.legacy_context_authorized', 'true', TRUE);
    PERFORM pg_catalog.set_config(
        'application_name', 'legacy-import', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION fn_clear_legacy_migration_context()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    PERFORM pg_catalog.set_config('app.current_user_id', '', TRUE);
    PERFORM pg_catalog.set_config('app.current_company_id', '', TRUE);
    PERFORM pg_catalog.set_config('app.current_store_id', '', TRUE);
    PERFORM pg_catalog.set_config('app.current_operation', '', TRUE);
    PERFORM pg_catalog.set_config('app.legacy_context_authorized', '', TRUE);
    PERFORM pg_catalog.set_config('application_name', '', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION fn_set_legacy_migration_context(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_clear_legacy_migration_context() FROM PUBLIC;
GRANT USAGE ON SCHEMA mottainai TO mottainai_migrator;
GRANT EXECUTE ON FUNCTION fn_set_legacy_migration_context(INTEGER)
    TO mottainai_migrator;
GRANT EXECUTE ON FUNCTION fn_clear_legacy_migration_context()
    TO mottainai_migrator;
GRANT EXECUTE ON FUNCTION fn_is_sha256_token(TEXT, TEXT),
    fn_is_bcrypt_hash(TEXT),
    fn_is_legacy_masked_email(TEXT),
    fn_is_legacy_masked_phone(TEXT),
    fn_is_protected_email(TEXT),
    fn_is_protected_phone(TEXT)
TO mottainai_migrator;

GRANT SELECT, INSERT, UPDATE ON
    subscription_plan,
    address,
    company,
    employee_role,
    retail_store,
    employee,
    app_user,
    legacy_sync_record
TO mottainai_migrator;

GRANT USAGE, SELECT ON SEQUENCE
    subscription_plan_plan_id_seq,
    address_address_id_seq,
    company_company_id_seq,
    employee_role_role_id_seq,
    retail_store_store_id_seq,
    employee_employee_id_seq,
    app_user_user_id_seq,
    legacy_sync_record_legacy_sync_id_seq
TO mottainai_migrator;

ALTER TABLE company ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_legacy_import_policy ON company;
CREATE POLICY company_legacy_import_policy ON company
    FOR ALL TO mottainai_migrator
    USING (TRUE)
    WITH CHECK (TRUE);

ALTER TABLE retail_store ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS retail_store_legacy_import_policy ON retail_store;
CREATE POLICY retail_store_legacy_import_policy ON retail_store
    FOR ALL TO mottainai_migrator
    USING (company_id = fn_get_current_company_id())
    WITH CHECK (company_id = fn_get_current_company_id());

ALTER TABLE employee ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS employee_legacy_import_policy ON employee;
CREATE POLICY employee_legacy_import_policy ON employee
    FOR ALL TO mottainai_migrator
    USING (EXISTS (
        SELECT 1
        FROM retail_store
        WHERE retail_store.store_id = employee.store_id
          AND retail_store.company_id = fn_get_current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM retail_store
        WHERE retail_store.store_id = employee.store_id
          AND retail_store.company_id = fn_get_current_company_id()
    ));

ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_user_legacy_import_policy ON app_user;
CREATE POLICY app_user_legacy_import_policy ON app_user
    FOR ALL TO mottainai_migrator
    USING (EXISTS (
        SELECT 1
        FROM employee
        JOIN retail_store ON retail_store.store_id = employee.store_id
        WHERE employee.employee_id = app_user.employee_id
          AND retail_store.company_id = fn_get_current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM employee
        JOIN retail_store ON retail_store.store_id = employee.store_id
        WHERE employee.employee_id = app_user.employee_id
          AND retail_store.company_id = fn_get_current_company_id()
    ));

-- The audit trigger accepts a user-less legacy import only when the tenant was
-- established by the protected migration-context function. Normal API writes
-- continue to require both user and company context.
CREATE OR REPLACE FUNCTION fn_trg_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER := mottainai.fn_get_current_user_id();
    v_company_id INTEGER := mottainai.fn_get_current_company_id();
    v_store_id INTEGER := mottainai.fn_get_current_store_id();
    v_operation_context TEXT := NULLIF(
        current_setting('app.current_operation', TRUE), '');
    v_legacy_context_authorized BOOLEAN := COALESCE(
        NULLIF(current_setting('app.legacy_context_authorized', TRUE), '')::BOOLEAN,
        FALSE
    );
    v_is_legacy_import BOOLEAN;
    v_record_id TEXT;
BEGIN
    v_is_legacy_import := v_operation_context = 'legacy-import';

    IF v_is_legacy_import AND NOT v_legacy_context_authorized THEN
        RAISE EXCEPTION 'Legacy migration context is not authorized';
    END IF;

    IF v_is_legacy_import AND v_company_id IS NULL THEN
        RAISE EXCEPTION 'A company context is required for legacy imports';
    END IF;

    IF NOT v_is_legacy_import
       AND pg_has_role(session_user, 'mottainai_api', 'MEMBER')
       AND NOT EXISTS (
           SELECT 1
           FROM pg_roles
           WHERE rolname = session_user
             AND rolsuper
       )
       AND (v_user_id IS NULL OR v_company_id IS NULL) THEN
        RAISE EXCEPTION
            'A validated tenant context is required for audited API writes';
    END IF;

    v_record_id := COALESCE(
        to_jsonb(NEW)->>TG_ARGV[0],
        to_jsonb(OLD)->>TG_ARGV[0],
        '0'
    );

    INSERT INTO mottainai.audit_log (
        table_affected,
        operation,
        record_id,
        user_id,
        old_data,
        new_data,
        operation_date,
        company_id,
        store_id,
        client_ip,
        application_name,
        transaction_id
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP::mottainai.audit_operation,
        v_record_id,
        CASE WHEN v_is_legacy_import THEN NULL ELSE v_user_id END,
        mottainai.fn_sanitize_audit_json(
            CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END),
        mottainai.fn_sanitize_audit_json(
            CASE WHEN TG_OP IN ('UPDATE', 'INSERT') THEN to_jsonb(NEW) END),
        CURRENT_TIMESTAMP,
        v_company_id,
        v_store_id,
        inet_client_addr(),
        CASE
            WHEN v_is_legacy_import THEN 'legacy-import'
            ELSE current_setting('application_name', TRUE)
        END,
        txid_current()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION fn_trg_audit_log() FROM PUBLIC;

-- Outbox operations shared by idempotent API workflows.
CREATE OR REPLACE FUNCTION fn_find_outbox_event_by_key(
    p_idempotency_key TEXT
) RETURNS TABLE (
    event_type VARCHAR(50),
    aggregate_type VARCHAR(60),
    aggregate_id VARCHAR(120),
    event_data JSONB
)
LANGUAGE sql
STABLE
SET search_path = mottainai, pg_temp
AS $$
    SELECT queue.event_type,
           queue.aggregate_type,
           queue.aggregate_id,
           queue.event_data
    FROM mottainai.event_queue AS queue
    WHERE queue.idempotency_key = p_idempotency_key
    ORDER BY queue.event_id
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_publish_integration_event(
    p_event_type VARCHAR(50),
    p_aggregate_type VARCHAR(60),
    p_aggregate_id VARCHAR(120),
    p_event_data JSONB,
    p_company_id INTEGER DEFAULT NULL,
    p_store_id INTEGER DEFAULT NULL,
    p_idempotency_key VARCHAR(180) DEFAULT NULL,
    p_priority INTEGER DEFAULT 5
) RETURNS UUID
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    INSERT INTO mottainai.event_queue (
        event_type,
        aggregate_type,
        aggregate_id,
        event_data,
        company_id,
        store_id,
        idempotency_key,
        priority
    ) VALUES (
        p_event_type,
        p_aggregate_type,
        p_aggregate_id,
        p_event_data,
        p_company_id,
        p_store_id,
        p_idempotency_key,
        p_priority
    )
    ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING event_uuid INTO v_event_uuid;

    PERFORM pg_notify('mottainai_event', v_event_uuid::TEXT);
    RETURN v_event_uuid;
END;
$$;

-- Partition-aware inserts used by purchase and receiving repositories.
CREATE OR REPLACE FUNCTION fn_api_insert_purchase_order(
    p_store_id INTEGER,
    p_supplier_id INTEGER,
    p_employee_id INTEGER,
    p_expected_delivery_date DATE,
    p_observation TEXT,
    p_total_amount NUMERIC
) RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO mottainai.purchase_order (
        store_id,
        supplier_id,
        employee_id,
        expected_delivery_date,
        observation,
        total_amount
    ) VALUES (
        p_store_id,
        p_supplier_id,
        p_employee_id,
        p_expected_delivery_date,
        p_observation,
        p_total_amount
    )
    RETURNING purchase_order_id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_api_insert_receiving(
    p_purchase_order_id INTEGER,
    p_employee_id INTEGER,
    p_observation TEXT,
    p_order_date TIMESTAMP
) RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO mottainai.receiving (
        purchase_order_id,
        employee_id,
        observation,
        order_date
    ) VALUES (
        p_purchase_order_id,
        p_employee_id,
        p_observation,
        p_order_date
    )
    RETURNING receiving_id INTO v_id;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_api_upsert_inventory(
    p_store_id INTEGER,
    p_batch_id INTEGER
) RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO mottainai.inventory (
        store_id,
        batch_id,
        inventory_type,
        current_quantity,
        minimum_quantity
    ) VALUES (
        p_store_id,
        p_batch_id,
        'NORMAL',
        0,
        0
    )
    ON CONFLICT (store_id, batch_id, inventory_type)
    DO UPDATE SET
        deleted_at = NULL,
        updated_at = NOW()
    RETURNING inventory_id INTO v_id;

    RETURN v_id;
END;
$$;

-- API-facing views preserve the exact column contract used by repository
-- projections. security_invoker keeps all underlying RLS policies effective.
CREATE OR REPLACE VIEW vw_api_system_event
WITH (security_invoker = TRUE) AS
SELECT event_id,
       event_uuid,
       event_type,
       aggregate_type,
       aggregate_id,
       event_data::TEXT AS event_data,
       priority,
       status::TEXT AS status,
       retry_count,
       error_message,
       occurred_at,
       processed_at,
       company_id
FROM event_queue;

CREATE OR REPLACE VIEW vw_api_system_log
WITH (security_invoker = TRUE) AS
SELECT logs.id,
       logs.source,
       logs.level,
       logs.module,
       logs.message,
       logs.stack_trace,
       logs.user_id,
       logs.ip_address,
       logs.created_at,
       linked_store.company_id
FROM (
    SELECT log_id AS id,
           'SYSTEM' AS source,
           log_level::TEXT AS level,
           module,
           message,
           stack_trace,
           user_id,
           ip_address::TEXT AS ip_address,
           created_at
    FROM system_log
    UNION ALL
    SELECT error_id AS id,
           'ERROR' AS source,
           'ERROR' AS level,
           function_name AS module,
           error_message AS message,
           stack_trace,
           user_id,
           NULL AS ip_address,
           created_at
    FROM error_log
) AS logs
JOIN app_user AS linked_user ON linked_user.user_id = logs.user_id
JOIN employee AS linked_employee
  ON linked_employee.employee_id = linked_user.employee_id
JOIN retail_store AS linked_store
  ON linked_store.store_id = linked_employee.store_id;

CREATE OR REPLACE VIEW vw_api_system_job
WITH (security_invoker = TRUE) AS
SELECT job_id,
       job_name,
       job_type,
       start_time,
       end_time,
       duration_seconds,
       records_processed,
       success,
       details::TEXT AS details,
       company_id
FROM job_log;

CREATE OR REPLACE VIEW vw_api_purchase_order
WITH (security_invoker = TRUE) AS
SELECT purchase_order_id,
       store_id,
       supplier_id,
       employee_id,
       order_date,
       expected_delivery_date,
       status::TEXT AS status,
       observation,
       total_amount,
       version,
       deleted_at
FROM purchase_order;

CREATE OR REPLACE VIEW vw_api_purchase_order_item
WITH (security_invoker = TRUE) AS
SELECT purchase_order_item_id,
       purchase_order_id,
       product_id,
       requested_quantity,
       unit_price,
       subtotal,
       order_date,
       deleted_at
FROM purchase_order_item;

CREATE OR REPLACE VIEW vw_api_receiving
WITH (security_invoker = TRUE) AS
SELECT receiving.receiving_id,
       receiving.purchase_order_id,
       purchase.store_id,
       receiving.employee_id,
       receiving.receiving_date,
       receiving.status::TEXT AS status,
       receiving.observation,
       receiving.order_date,
       purchase.deleted_at AS purchase_order_deleted_at
FROM receiving
JOIN purchase_order AS purchase
  ON purchase.purchase_order_id = receiving.purchase_order_id
 AND purchase.order_date = receiving.order_date;

CREATE OR REPLACE VIEW vw_api_receiving_item
WITH (security_invoker = TRUE) AS
SELECT receiving_line.receiving_item_id,
       receiving_line.receiving_id,
       receiving_line.purchase_order_item_id,
       order_line.product_id,
       order_line.requested_quantity,
       receiving_line.received_quantity,
       receiving_line.unit_price,
       receiving_line.manufacture_date,
       receiving_line.expiration_date,
       receiving_line.observation,
       order_line.deleted_at
FROM receiving_item AS receiving_line
JOIN purchase_order_item AS order_line
  ON order_line.purchase_order_item_id =
     receiving_line.purchase_order_item_id;

CREATE OR REPLACE VIEW vw_api_store_product_price
WITH (security_invoker = TRUE) AS
SELECT store_product_price_id,
       store_id,
       product_id,
       regular_price,
       valid_from,
       valid_until,
       active,
       version
FROM store_product_price;

CREATE OR REPLACE VIEW vw_api_product_history
WITH (security_invoker = TRUE) AS
SELECT history_id,
       product_id,
       field_name,
       old_value,
       new_value,
       changed_by,
       changed_at
FROM product_history;

CREATE OR REPLACE VIEW vw_api_product_price_history
WITH (security_invoker = TRUE) AS
SELECT price_history_id,
       product_id,
       old_price,
       new_price,
       changed_by,
       changed_at
FROM product_price_history;

-- Tenant policies for the new monitoring and history surfaces.
ALTER TABLE event_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS event_queue_staff_policy ON event_queue;
CREATE POLICY event_queue_staff_policy ON event_queue
    FOR ALL TO mottainai_api
    USING (company_id = fn_get_current_company_id())
    WITH CHECK (
        company_id = fn_get_current_company_id()
        AND (
            store_id IS NULL
            OR fn_store_belongs_current_company(store_id)
        )
    );

DROP POLICY IF EXISTS event_queue_customer_policy ON event_queue;
CREATE POLICY event_queue_customer_policy ON event_queue
    FOR ALL TO mottainai_customer_api
    USING (
        company_id IS NULL
        AND event_data->>'customer_id' = fn_get_current_customer_id()::TEXT
    )
    WITH CHECK (
        company_id IS NULL
        AND event_data->>'customer_id' = fn_get_current_customer_id()::TEXT
    );

ALTER TABLE system_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS system_log_tenant_policy ON system_log;
CREATE POLICY system_log_tenant_policy ON system_log
    FOR SELECT TO mottainai_api
    USING (user_id IS NOT NULL AND fn_can_access_user(user_id));

ALTER TABLE error_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS error_log_tenant_policy ON error_log;
CREATE POLICY error_log_tenant_policy ON error_log
    FOR SELECT TO mottainai_api
    USING (user_id IS NOT NULL AND fn_can_access_user(user_id));

ALTER TABLE job_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_log_tenant_policy ON job_log;
CREATE POLICY job_log_tenant_policy ON job_log
    FOR SELECT TO mottainai_api
    USING (company_id = fn_get_current_company_id());

ALTER TABLE product_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_history_tenant_policy ON product_history;
CREATE POLICY product_history_tenant_policy ON product_history
    FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1
        FROM product
        WHERE product.product_id = product_history.product_id
          AND product.company_id = fn_get_current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM product
        WHERE product.product_id = product_history.product_id
          AND product.company_id = fn_get_current_company_id()
    ));

ALTER TABLE product_price_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_price_history_tenant_policy
    ON product_price_history;
CREATE POLICY product_price_history_tenant_policy ON product_price_history
    FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1
        FROM product
        WHERE product.product_id = product_price_history.product_id
          AND product.company_id = fn_get_current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM product
        WHERE product.product_id = product_price_history.product_id
          AND product.company_id = fn_get_current_company_id()
    ));

-- Least-privilege grants required by security-invoker views and repository
-- operations. DDL and physical deletes remain unavailable to application roles.
GRANT SELECT ON event_queue, system_log, error_log, job_log,
    product_history, product_price_history TO mottainai_api;
GRANT INSERT ON event_queue TO mottainai_api, mottainai_customer_api;
GRANT UPDATE (status, retry_count, error_message, processed_at, published_at)
    ON event_queue TO mottainai_api;
GRANT SELECT ON event_queue TO mottainai_customer_api;
GRANT INSERT ON product_history, product_price_history TO mottainai_api;

GRANT USAGE, SELECT ON SEQUENCE event_queue_event_id_seq
    TO mottainai_api, mottainai_customer_api;
GRANT USAGE, SELECT ON SEQUENCE product_history_history_id_seq,
    product_price_history_price_history_id_seq TO mottainai_api;

GRANT SELECT ON
    vw_api_system_event,
    vw_api_system_log,
    vw_api_system_job,
    vw_api_purchase_order,
    vw_api_purchase_order_item,
    vw_api_receiving,
    vw_api_receiving_item,
    vw_api_store_product_price,
    vw_api_product_history,
    vw_api_product_price_history
TO mottainai_api;

-- PostgreSQL also checks UPDATE privilege on a view selected with FOR UPDATE.
-- The underlying tables remain protected by column grants and RLS.
GRANT UPDATE ON
    vw_api_system_event,
    vw_api_purchase_order,
    vw_api_receiving,
    vw_api_store_product_price
TO mottainai_api;

REVOKE ALL ON FUNCTION fn_find_outbox_event_by_key(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_publish_integration_event(
    VARCHAR, VARCHAR, VARCHAR, JSONB, INTEGER, INTEGER, VARCHAR, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_insert_purchase_order(
    INTEGER, INTEGER, INTEGER, DATE, TEXT, NUMERIC
) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_insert_receiving(
    INTEGER, INTEGER, TEXT, TIMESTAMP
) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_api_upsert_inventory(INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_atomic_update_inventory(
    INTEGER, NUMERIC, movement_type, INTEGER, TEXT, INTEGER
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_find_outbox_event_by_key(TEXT)
    TO mottainai_api, mottainai_customer_api;
GRANT EXECUTE ON FUNCTION fn_publish_integration_event(
    VARCHAR, VARCHAR, VARCHAR, JSONB, INTEGER, INTEGER, VARCHAR, INTEGER
) TO mottainai_api, mottainai_customer_api;
GRANT EXECUTE ON FUNCTION fn_api_insert_purchase_order(
    INTEGER, INTEGER, INTEGER, DATE, TEXT, NUMERIC
) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_api_insert_receiving(
    INTEGER, INTEGER, TEXT, TIMESTAMP
) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_api_upsert_inventory(INTEGER, INTEGER)
    TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_atomic_update_inventory(
    INTEGER, NUMERIC, movement_type, INTEGER, TEXT, INTEGER
) TO mottainai_api;

COMMENT ON COLUMN inventory_count_item.deleted_at IS
    'Logical deletion timestamp used by the inventory-count API.';
COMMENT ON COLUMN purchase_order_item.deleted_at IS
    'Logical deletion timestamp used by purchase and receiving APIs.';
COMMENT ON COLUMN job_log.company_id IS
    'Owning tenant. NULL identifies a legacy global job hidden from tenant APIs.';
COMMENT ON FUNCTION fn_set_legacy_migration_context(INTEGER) IS
    'Sets a transaction-local tenant and audit context for an authorized legacy RPA import.';

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '25',
    'Align operational schema with API and legacy RPA contracts',
    'SQL',
    '25_api_rpa_compatibility.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
