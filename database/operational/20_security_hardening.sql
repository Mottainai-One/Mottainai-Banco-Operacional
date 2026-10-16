-- ====================================================================
-- PROFESSIONAL SECURITY HARDENING
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

-- The application role is intentionally NOLOGIN. The real Render login must
-- be granted membership by a database administrator.
DO $$
DECLARE
    v_is_superuser BOOLEAN;
    v_has_replication BOOLEAN;
    v_bypasses_rls BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_api') THEN
        CREATE ROLE mottainai_api
            NOLOGIN
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT;
    END IF;

    SELECT rolsuper, rolreplication, rolbypassrls
    INTO v_is_superuser, v_has_replication, v_bypasses_rls
    FROM pg_roles
    WHERE rolname = 'mottainai_api';

    IF v_is_superuser OR v_has_replication OR v_bypasses_rls THEN
        RAISE EXCEPTION
            'Role mottainai_api has a privileged attribute (SUPERUSER, REPLICATION or BYPASSRLS). A PostgreSQL superuser must remove it before this migration can continue.';
    END IF;

    ALTER ROLE mottainai_api
        NOLOGIN
        NOCREATEDB
        NOCREATEROLE
        NOINHERIT;

    ALTER ROLE mottainai_api SET row_security = ON;
    ALTER ROLE mottainai_api SET statement_timeout = '30s';
    ALTER ROLE mottainai_api SET lock_timeout = '5s';
    ALTER ROLE mottainai_api SET idle_in_transaction_session_timeout = '30s';
END;
$$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA mottainai FROM PUBLIC;
GRANT USAGE ON SCHEMA mottainai TO mottainai_api;

DO $$
BEGIN
    EXECUTE format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO mottainai_api', current_database());
END;
$$;

-- Prevent future objects from accidentally becoming public.
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Initial-password and employee-invitation state.
ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS password_set BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN app_user.password_set IS
    'True after the employee has securely defined the initial password.';

ALTER TABLE password_reset_token
    ADD COLUMN IF NOT EXISTS token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET';

ALTER TABLE password_reset_token
    DROP CONSTRAINT IF EXISTS ck_password_reset_token_type;

ALTER TABLE password_reset_token
    ADD CONSTRAINT ck_password_reset_token_type
    CHECK (token_type IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION'));

CREATE INDEX IF NOT EXISTS idx_password_reset_token_user_type_active
    ON password_reset_token (user_id, token_type, created_at DESC)
    WHERE used_at IS NULL;

COMMENT ON COLUMN password_reset_token.token_type IS
    'Distinguishes password recovery from an employee invitation.';

-- Only token hashes are persisted. Logout and password changes revoke rows;
-- sessions are retained for investigation and never physically deleted by API.
CREATE TABLE IF NOT EXISTS staff_session (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    refresh_token_hash TEXT NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoked_reason VARCHAR(80),
    ip_address INET,
    user_agent VARCHAR(500),
    CONSTRAINT fk_staff_session_user
        FOREIGN KEY (user_id)
        REFERENCES app_user(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_staff_session_refresh_token_hash
        UNIQUE (refresh_token_hash),
    CONSTRAINT ck_staff_session_expiration
        CHECK (refresh_expires_at > created_at),
    CONSTRAINT ck_staff_session_last_used
        CHECK (last_used_at IS NULL OR last_used_at >= created_at),
    CONSTRAINT ck_staff_session_revoked
        CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT ck_staff_session_revoked_reason
        CHECK (revoked_at IS NOT NULL OR revoked_reason IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_staff_session_user_active
    ON staff_session (user_id, refresh_expires_at)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE staff_session IS
    'Auditable employee sessions. Contains only refresh-token hashes.';

-- The former setter accepted arbitrary IDs and persisted them for the whole
-- connection. It remains for owner compatibility but is unavailable to API.
REVOKE ALL ON FUNCTION fn_set_session_context(INTEGER, INTEGER, INTEGER)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_set_session_context(INTEGER, INTEGER, INTEGER)
    FROM mottainai_api;

-- PostgreSQL 15 parameter ACLs prevent the API from forging tenant GUCs with
-- SET or set_config(). Only the SECURITY DEFINER bootstrap functions may set
-- these transaction-local values.
REVOKE SET ON PARAMETER app.current_user_id FROM PUBLIC;
REVOKE SET ON PARAMETER app.current_company_id FROM PUBLIC;
REVOKE SET ON PARAMETER app.current_store_id FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM mottainai_api;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context(
    p_identity TEXT,
    p_lookup TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_lookup <> 'FIREBASE_UID' THEN
        RETURN FALSE;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM app_user u
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL
      AND s.active
      AND c.active
      AND r.active
      AND p_lookup = 'FIREBASE_UID'
      AND u.firebase_uid = p_identity
      AND u.active
      AND e.active;

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context_by_token(
    p_token_hash TEXT,
    p_token_type VARCHAR
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_token_type NOT IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION') THEN
        RETURN NULL;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM password_reset_token t
    JOIN app_user u ON u.user_id = t.user_id
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE t.token_hash = p_token_hash
      AND t.token_type = p_token_type
      AND t.used_at IS NULL
      AND t.expires_at > CURRENT_TIMESTAMP
      AND u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL
      AND s.active
      AND c.active
      AND r.active
      AND (
          (p_token_type = 'PASSWORD_RESET' AND u.active AND e.active)
          OR
          (p_token_type = 'EMPLOYEE_INVITATION'
              AND NOT u.active AND NOT e.active AND NOT u.password_set)
      );

    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context_by_session(
    p_session_id UUID,
    p_refresh_token_hash TEXT
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM staff_session ss
    JOIN app_user u ON u.user_id = ss.user_id
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE ss.session_id = p_session_id
      AND ss.refresh_token_hash = p_refresh_token_hash
      AND ss.revoked_at IS NULL
      AND ss.refresh_expires_at > CURRENT_TIMESTAMP
      AND u.active
      AND e.active
      AND s.active
      AND c.active
      AND r.active
      AND u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_staff_context_by_token(TEXT, VARCHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_staff_context_by_session(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context_by_token(TEXT, VARCHAR) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context_by_session(UUID, TEXT) TO mottainai_api;

-- Reusable tenant predicates. SECURITY DEFINER avoids recursive RLS checks;
-- fixed search paths prevent object-shadowing attacks.
CREATE OR REPLACE FUNCTION fn_current_user_is_company_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_user u
        JOIN employee e ON e.employee_id = u.employee_id
        JOIN employee_role r ON r.role_id = e.role_id
        JOIN retail_store s ON s.store_id = e.store_id
        WHERE u.user_id = fn_get_current_user_id()
          AND s.company_id = fn_get_current_company_id()
          AND upper(r.name) = 'ADMINISTRATOR'
          AND u.active AND e.active AND r.active AND s.active
          AND u.deleted_at IS NULL
          AND e.deleted_at IS NULL
          AND r.deleted_at IS NULL
          AND s.deleted_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION fn_store_belongs_current_company(p_store_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM retail_store s
        WHERE s.store_id = p_store_id
          AND s.company_id = fn_get_current_company_id()
          AND s.active
          AND s.deleted_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION fn_can_access_store(p_store_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT p_store_id = fn_get_current_store_id()
        OR (
            fn_current_user_is_company_admin()
            AND fn_store_belongs_current_company(p_store_id)
        );
$$;

CREATE OR REPLACE FUNCTION fn_can_access_user(p_user_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT p_user_id = fn_get_current_user_id()
        OR (
            fn_current_user_is_company_admin()
            AND EXISTS (
                SELECT 1
                FROM app_user u
                JOIN employee e ON e.employee_id = u.employee_id
                WHERE u.user_id = p_user_id
                  AND fn_store_belongs_current_company(e.store_id)
            )
        );
$$;

REVOKE ALL ON FUNCTION fn_current_user_is_company_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_store_belongs_current_company(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_access_store(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_access_user(INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_get_current_user_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_get_current_company_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_get_current_store_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_current_user_is_company_admin() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_store_belongs_current_company(INTEGER) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_can_access_store(INTEGER) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_can_access_user(INTEGER) TO mottainai_api;

-- Replace permissive legacy policies with explicit API policies and checks.
DROP POLICY IF EXISTS company_policy ON company;
CREATE POLICY company_policy ON company FOR ALL TO mottainai_api
    USING (company_id = fn_get_current_company_id())
    WITH CHECK (company_id = fn_get_current_company_id());

DROP POLICY IF EXISTS store_policy ON retail_store;
CREATE POLICY store_policy ON retail_store FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS employee_policy ON employee;
CREATE POLICY employee_policy ON employee FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS inventory_policy ON inventory;
CREATE POLICY inventory_policy ON inventory FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS sales_policy ON sales_transaction;
CREATE POLICY sales_policy ON sales_transaction FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS purchase_order_policy ON purchase_order;
CREATE POLICY purchase_order_policy ON purchase_order FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DO $$
DECLARE
    v_item RECORD;
BEGIN
    FOR v_item IN
        SELECT * FROM (VALUES
            ('pos_terminal', 'store_id'),
            ('alert', 'store_id'),
            ('promotion', 'store_id'),
            ('customer_geofence', 'store_id'),
            ('donation', 'store_id'),
            ('disposal', 'store_id'),
            ('replenishment_pre_list', 'store_id'),
            ('store_product_price', 'store_id'),
            ('inventory_count', 'store_id'),
            ('inventory_movement', 'store_id')
        ) AS policy_table(table_name, store_column)
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_item.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I',
            v_item.table_name || '_tenant_policy', v_item.table_name);
        EXECUTE format(
            'CREATE POLICY %I ON %I FOR ALL TO mottainai_api '
            || 'USING (fn_can_access_store(%I)) '
            || 'WITH CHECK (fn_can_access_store(%I))',
            v_item.table_name || '_tenant_policy',
            v_item.table_name,
            v_item.store_column,
            v_item.store_column
        );
    END LOOP;
END;
$$;

ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_user_tenant_policy ON app_user;
CREATE POLICY app_user_tenant_policy ON app_user FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE password_reset_token ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS password_reset_token_policy ON password_reset_token;
CREATE POLICY password_reset_token_policy ON password_reset_token FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE staff_session ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_session_policy ON staff_session;
CREATE POLICY staff_session_policy ON staff_session FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE inventory_count_item ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventory_count_item_policy ON inventory_count_item;
CREATE POLICY inventory_count_item_policy ON inventory_count_item FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1 FROM inventory_count count_header
        WHERE count_header.inventory_count_id = inventory_count_item.inventory_count_id
          AND fn_can_access_store(count_header.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM inventory_count count_header
        WHERE count_header.inventory_count_id = inventory_count_item.inventory_count_id
          AND fn_can_access_store(count_header.store_id)
    ));

ALTER TABLE batch ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS batch_tenant_policy ON batch;
CREATE POLICY batch_tenant_policy ON batch FOR ALL TO mottainai_api
    USING (
        EXISTS (
            SELECT 1 FROM inventory stock
            WHERE stock.batch_id = batch.batch_id
              AND fn_can_access_store(stock.store_id)
        )
        OR EXISTS (
            SELECT 1
            FROM receiving_item received_item
            JOIN receiving receiving_header
              ON receiving_header.receiving_id = received_item.receiving_id
            JOIN purchase_order purchase
              ON purchase.purchase_order_id = receiving_header.purchase_order_id
             AND purchase.order_date = receiving_header.order_date
            WHERE received_item.receiving_item_id = batch.receiving_item_id
              AND fn_can_access_store(purchase.store_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM inventory stock
            WHERE stock.batch_id = batch.batch_id
              AND fn_can_access_store(stock.store_id)
        )
        OR EXISTS (
            SELECT 1
            FROM receiving_item received_item
            JOIN receiving receiving_header
              ON receiving_header.receiving_id = received_item.receiving_id
            JOIN purchase_order purchase
              ON purchase.purchase_order_id = receiving_header.purchase_order_id
             AND purchase.order_date = receiving_header.order_date
            WHERE received_item.receiving_item_id = batch.receiving_item_id
              AND fn_can_access_store(purchase.store_id)
        )
    );

ALTER TABLE pos_shift ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_shift_tenant_policy ON pos_shift;
CREATE POLICY pos_shift_tenant_policy ON pos_shift FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1 FROM pos_terminal terminal
        WHERE terminal.terminal_id = pos_shift.terminal_id
          AND fn_can_access_store(terminal.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM pos_terminal terminal
        WHERE terminal.terminal_id = pos_shift.terminal_id
          AND fn_can_access_store(terminal.store_id)
    ));

ALTER TABLE pos_cash_movement ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_cash_movement_tenant_policy ON pos_cash_movement;
CREATE POLICY pos_cash_movement_tenant_policy ON pos_cash_movement FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1
        FROM pos_shift shift_record
        JOIN pos_terminal terminal ON terminal.terminal_id = shift_record.terminal_id
        WHERE shift_record.shift_id = pos_cash_movement.shift_id
          AND fn_can_access_store(terminal.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM pos_shift shift_record
        JOIN pos_terminal terminal ON terminal.terminal_id = shift_record.terminal_id
        WHERE shift_record.shift_id = pos_cash_movement.shift_id
          AND fn_can_access_store(terminal.store_id)
    ));

ALTER TABLE transfer ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS transfer_tenant_policy ON transfer;
CREATE POLICY transfer_tenant_policy ON transfer FOR ALL TO mottainai_api
    USING (fn_can_access_store(source_store_id)
        OR fn_can_access_store(destination_store_id))
    WITH CHECK (fn_can_access_store(source_store_id)
        AND fn_store_belongs_current_company(destination_store_id));

-- Child-table policies follow their tenant-scoped parent.
DO $$
DECLARE
    v_policy RECORD;
BEGIN
    FOR v_policy IN
        SELECT * FROM (VALUES
            ('purchase_order_item', 'purchase_order_item_policy',
             'EXISTS (SELECT 1 FROM purchase_order parent WHERE parent.purchase_order_id = purchase_order_item.purchase_order_id AND parent.order_date = purchase_order_item.order_date AND fn_can_access_store(parent.store_id))'),
            ('receiving', 'receiving_policy',
             'EXISTS (SELECT 1 FROM purchase_order parent WHERE parent.purchase_order_id = receiving.purchase_order_id AND parent.order_date = receiving.order_date AND fn_can_access_store(parent.store_id))'),
            ('receiving_item', 'receiving_item_policy',
             'EXISTS (SELECT 1 FROM receiving parent JOIN purchase_order po ON po.purchase_order_id = parent.purchase_order_id AND po.order_date = parent.order_date WHERE parent.receiving_id = receiving_item.receiving_id AND fn_can_access_store(po.store_id))'),
            ('sale_item', 'sale_item_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = sale_item.sale_id AND parent.sale_date = sale_item.sale_date AND fn_can_access_store(parent.store_id))'),
            ('sale_payment', 'sale_payment_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = sale_payment.sale_id AND parent.sale_date = sale_payment.sale_date AND fn_can_access_store(parent.store_id))'),
            ('fiscal_document', 'fiscal_document_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = fiscal_document.sale_id AND parent.sale_date = fiscal_document.sale_date AND fn_can_access_store(parent.store_id))'),
            ('pos_cancel_request', 'pos_cancel_request_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = pos_cancel_request.sale_id AND parent.sale_date = pos_cancel_request.sale_date AND fn_can_access_store(parent.store_id))'),
            ('promotion_item', 'promotion_item_policy',
             'EXISTS (SELECT 1 FROM promotion parent WHERE parent.promotion_id = promotion_item.promotion_id AND fn_can_access_store(parent.store_id))'),
            ('transfer_item', 'transfer_item_policy',
             'EXISTS (SELECT 1 FROM transfer parent WHERE parent.transfer_id = transfer_item.transfer_id AND (fn_can_access_store(parent.source_store_id) OR fn_can_access_store(parent.destination_store_id)))'),
            ('donation_item', 'donation_item_policy',
             'EXISTS (SELECT 1 FROM donation parent WHERE parent.donation_id = donation_item.donation_id AND fn_can_access_store(parent.store_id))'),
            ('disposal_item', 'disposal_item_policy',
             'EXISTS (SELECT 1 FROM disposal parent WHERE parent.disposal_id = disposal_item.disposal_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_pre_list_item', 'replenishment_pre_list_item_policy',
             'EXISTS (SELECT 1 FROM replenishment_pre_list parent WHERE parent.pre_list_id = replenishment_pre_list_item.pre_list_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_execution', 'replenishment_execution_policy',
             'EXISTS (SELECT 1 FROM replenishment_pre_list parent WHERE parent.pre_list_id = replenishment_execution.pre_list_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_execution_item', 'replenishment_execution_item_policy',
             'EXISTS (SELECT 1 FROM replenishment_execution execution JOIN replenishment_pre_list parent ON parent.pre_list_id = execution.pre_list_id WHERE execution.execution_id = replenishment_execution_item.execution_id AND fn_can_access_store(parent.store_id))')
        ) AS policy_data(table_name, policy_name, predicate)
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_policy.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I',
            v_policy.policy_name, v_policy.table_name);
        EXECUTE format(
            'CREATE POLICY %I ON %I FOR ALL TO mottainai_api '
            || 'USING (%s) WITH CHECK (%s)',
            v_policy.policy_name,
            v_policy.table_name,
            v_policy.predicate,
            v_policy.predicate
        );
    END LOOP;
END;
$$;

-- Views must evaluate RLS as the caller, never as their owner.
ALTER VIEW vw_expiring_products SET (security_invoker = TRUE);
ALTER VIEW vw_critical_stock SET (security_invoker = TRUE);
ALTER VIEW vw_current_store_price SET (security_invoker = TRUE);
ALTER VIEW vw_active_customer_promotions SET (security_invoker = TRUE);

-- Tenant-aware and tamper-resistant audit records.
ALTER TABLE audit_log
    ADD COLUMN IF NOT EXISTS company_id INTEGER,
    ADD COLUMN IF NOT EXISTS store_id INTEGER,
    ADD COLUMN IF NOT EXISTS client_ip INET,
    ADD COLUMN IF NOT EXISTS application_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS transaction_id BIGINT;

UPDATE audit_log audit
SET company_id = store.company_id,
    store_id = employee.store_id
FROM app_user app
JOIN employee ON employee.employee_id = app.employee_id
JOIN retail_store store ON store.store_id = employee.store_id
WHERE audit.user_id = app.user_id
  AND audit.company_id IS NULL;

CREATE OR REPLACE FUNCTION fn_sanitize_audit_json(p_data JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_data IS NULL THEN NULL
        ELSE p_data
            - 'password_hash'
            - 'token_hash'
            - 'refresh_token_hash'
            - 'recovery_token_hash'
            - 'cpf'
    END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER := fn_get_current_user_id();
    v_company_id INTEGER := fn_get_current_company_id();
    v_store_id INTEGER := fn_get_current_store_id();
    v_record_id TEXT;
BEGIN
    IF pg_has_role(session_user, 'mottainai_api', 'MEMBER')
       AND NOT EXISTS (
           SELECT 1 FROM pg_roles
           WHERE rolname = session_user
             AND rolsuper
       )
       AND (v_user_id IS NULL OR v_company_id IS NULL) THEN
        RAISE EXCEPTION 'A validated tenant context is required for audited API writes';
    END IF;

    v_record_id := COALESCE(
        to_jsonb(NEW)->>TG_ARGV[0],
        to_jsonb(OLD)->>TG_ARGV[0],
        '0'
    );

    INSERT INTO audit_log (
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
        TG_OP::audit_operation,
        v_record_id,
        v_user_id,
        fn_sanitize_audit_json(CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END),
        fn_sanitize_audit_json(CASE WHEN TG_OP IN ('UPDATE', 'INSERT') THEN to_jsonb(NEW) END),
        CURRENT_TIMESTAMP,
        v_company_id,
        v_store_id,
        inet_client_addr(),
        current_setting('application_name', TRUE),
        txid_current()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION fn_sanitize_audit_json(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_trg_audit_log() FROM PUBLIC;

DO $$
DECLARE
    v_trigger RECORD;
BEGIN
    FOR v_trigger IN
        SELECT * FROM (VALUES
            ('employee', 'employee_id'),
            ('app_user', 'user_id'),
            ('purchase_order', 'purchase_order_id'),
            ('sales_transaction', 'sale_id'),
            ('inventory_movement', 'movement_id'),
            ('password_reset_token', 'recovery_token_id'),
            ('staff_session', 'session_id')
        ) AS audit_target(table_name, id_column)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I',
            'trg_audit_' || v_trigger.table_name, v_trigger.table_name);
        EXECUTE format(
            'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I '
            || 'FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log(%L)',
            'trg_audit_' || v_trigger.table_name,
            v_trigger.table_name,
            v_trigger.id_column
        );
    END LOOP;
END;
$$;

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_log_read_policy ON audit_log;
CREATE POLICY audit_log_read_policy ON audit_log FOR SELECT TO mottainai_api
    USING (company_id = fn_get_current_company_id());

-- Least privilege for the API group role. DDL, partition maintenance, direct
-- audit writes, physical deletes, logs and archives remain owner-only.
REVOKE ALL ON ALL TABLES IN SCHEMA mottainai FROM mottainai_api;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA mottainai FROM mottainai_api;

GRANT SELECT ON
    subscription_plan,
    company,
    retail_store,
    employee_role,
    product_category,
    tax_profile,
    batch,
    pos_terminal,
    pos_shift,
    vw_expiring_products,
    vw_critical_stock,
    vw_current_store_price,
    vw_active_customer_promotions
TO mottainai_api;

-- Product becomes writable only when the company-ownership migration from
-- PR #22 is present. This prevents exposing the former global catalog.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'company_id'
          AND is_nullable = 'NO'
    ) AND EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'mottainai'
          AND tablename = 'product'
          AND policyname = 'product_policy'
    ) THEN
        DROP POLICY product_policy ON product;
        CREATE POLICY product_policy ON product FOR ALL TO mottainai_api
            USING (company_id = fn_get_current_company_id())
            WITH CHECK (company_id = fn_get_current_company_id());
        GRANT SELECT, INSERT, UPDATE ON product TO mottainai_api;
        GRANT USAGE, SELECT ON SEQUENCE product_product_id_seq TO mottainai_api;
    ELSE
        RAISE NOTICE 'Product API grants skipped until product company ownership is installed';
    END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE ON
    employee,
    app_user,
    password_reset_token,
    staff_session,
    inventory,
    inventory_movement,
    inventory_count,
    inventory_count_item,
    store_product_price,
    purchase_order,
    purchase_order_item,
    receiving,
    receiving_item,
    sales_transaction,
    sale_item,
    sale_payment,
    fiscal_document,
    pos_cash_movement,
    pos_cancel_request,
    alert,
    promotion,
    promotion_item,
    transfer,
    transfer_item,
    donation,
    donation_item,
    disposal,
    disposal_item,
    replenishment_pre_list,
    replenishment_pre_list_item,
    replenishment_execution,
    replenishment_execution_item
TO mottainai_api;

GRANT SELECT ON audit_log TO mottainai_api;

DO $$
DECLARE
    v_table_name TEXT;
    v_sequence_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'employee', 'app_user', 'password_reset_token', 'inventory',
        'inventory_movement', 'inventory_count', 'inventory_count_item',
        'store_product_price', 'purchase_order', 'purchase_order_item',
        'receiving', 'receiving_item', 'sales_transaction', 'sale_item',
        'sale_payment', 'fiscal_document', 'pos_cash_movement',
        'pos_cancel_request', 'alert', 'promotion', 'promotion_item',
        'transfer', 'transfer_item', 'donation', 'donation_item',
        'disposal', 'disposal_item', 'replenishment_pre_list',
        'replenishment_pre_list_item', 'replenishment_execution',
        'replenishment_execution_item'
    ] LOOP
        SELECT pg_get_serial_sequence('mottainai.' || v_table_name, column_name)
        INTO v_sequence_name
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = v_table_name
          AND is_identity = 'YES'
        ORDER BY ordinal_position
        LIMIT 1;

        IF v_sequence_name IS NOT NULL THEN
            EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO mottainai_api',
                v_sequence_name);
        END IF;
    END LOOP;

END;
$$;

-- UUID staff_session has no sequence. The dynamic block supports deployments
-- where identity sequence names differ.

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '20',
    'Professional tenant, session, privilege and audit hardening',
    'SQL',
    '20_security_hardening.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;
