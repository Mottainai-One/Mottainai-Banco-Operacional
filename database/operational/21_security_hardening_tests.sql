-- ====================================================================
-- PROFESSIONAL SECURITY HARDENING - STRUCTURAL TESTS
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_count INTEGER;
    v_role RECORD;
BEGIN
    SELECT rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication,
           rolbypassrls
    INTO v_role
    FROM pg_roles
    WHERE rolname = 'mottainai_api';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'mottainai_api role is missing';
    END IF;

    IF v_role.rolsuper OR v_role.rolcreaterole OR v_role.rolcreatedb
       OR v_role.rolcanlogin OR v_role.rolreplication OR v_role.rolbypassrls THEN
        RAISE EXCEPTION 'mottainai_api has forbidden administrative attributes';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'app_user'
      AND column_name = 'password_set'
      AND is_nullable = 'NO';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'app_user.password_set is missing or nullable';
    END IF;

    IF to_regclass('mottainai.staff_session') IS NULL THEN
        RAISE EXCEPTION 'staff_session table is missing';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'mottainai'
      AND procedure.proname IN (
          'fn_bootstrap_staff_context',
          'fn_bootstrap_staff_context_by_token',
          'fn_bootstrap_staff_context_by_session'
      )
      AND procedure.prosecdef
      AND 'search_path=mottainai, pg_temp' = ANY(procedure.proconfig);

    IF v_count <> 3 THEN
        RAISE EXCEPTION 'Bootstrap functions must be SECURITY DEFINER with a fixed search_path';
    END IF;

    IF has_function_privilege(
        'mottainai_api',
        'mottainai.fn_set_session_context(integer,integer,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'mottainai_api must not execute fn_set_session_context';
    END IF;

    IF has_parameter_privilege(
        'mottainai_api', 'app.current_user_id', 'SET'
    ) OR has_parameter_privilege(
        'mottainai_api', 'app.current_company_id', 'SET'
    ) OR has_parameter_privilege(
        'mottainai_api', 'app.current_store_id', 'SET'
    ) THEN
        RAISE EXCEPTION 'mottainai_api must not set tenant context parameters directly';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = 'mottainai'
      AND relation.relname IN (
          'company', 'retail_store', 'employee', 'app_user', 'inventory',
          'inventory_movement', 'purchase_order', 'sales_transaction',
          'staff_session', 'password_reset_token', 'audit_log'
      )
      AND relation.relrowsecurity;

    IF v_count <> 11 THEN
        RAISE EXCEPTION 'RLS is not enabled on every critical tenant table';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_policies
    WHERE schemaname = 'mottainai'
      AND tablename IN (
          'company', 'retail_store', 'employee', 'app_user', 'inventory',
          'inventory_movement', 'purchase_order', 'sales_transaction',
          'staff_session', 'password_reset_token', 'audit_log'
      )
      AND 'mottainai_api' = ANY(roles);

    IF v_count < 11 THEN
        RAISE EXCEPTION 'Tenant policies are not explicitly assigned to mottainai_api';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_class view_relation
    JOIN pg_namespace namespace ON namespace.oid = view_relation.relnamespace
    WHERE namespace.nspname = 'mottainai'
      AND view_relation.relname IN (
          'vw_expiring_products',
          'vw_critical_stock',
          'vw_current_store_price',
          'vw_active_customer_promotions'
      )
      AND 'security_invoker=true' = ANY(view_relation.reloptions);

    IF v_count <> 4 THEN
        RAISE EXCEPTION 'Every API view must use security_invoker=true';
    END IF;

    IF has_table_privilege('mottainai_api', 'mottainai.audit_log', 'INSERT')
       OR has_table_privilege('mottainai_api', 'mottainai.audit_log', 'UPDATE')
       OR has_table_privilege('mottainai_api', 'mottainai.audit_log', 'DELETE') THEN
        RAISE EXCEPTION 'Audit log must be immutable to mottainai_api';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'audit_log'
      AND column_name IN (
          'company_id', 'store_id', 'client_ip',
          'application_name', 'transaction_id'
      );

    IF v_count <> 5 THEN
        RAISE EXCEPTION 'Tenant-aware audit metadata is incomplete';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'company_id'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'mottainai'
              AND tablename = 'product'
              AND policyname = 'product_policy'
              AND 'mottainai_api' = ANY(roles)
        ) OR NOT has_table_privilege(
            'mottainai_api', 'mottainai.product', 'INSERT'
        ) THEN
            RAISE EXCEPTION 'Company-owned product is not protected and granted to mottainai_api';
        END IF;
    END IF;

    RAISE NOTICE 'Professional security hardening tests passed';
END;
$$;
