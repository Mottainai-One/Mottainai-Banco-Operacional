-- ============================================================================
-- API AND LEGACY RPA COMPATIBILITY - TESTS
-- PostgreSQL 15+
--
-- Test-only module. Do not include it in the production installer.
-- ============================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_count INTEGER;
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
    INTO v_missing
    FROM (VALUES
        ('inventory_count_item', 'deleted_at'),
        ('purchase_order_item', 'deleted_at'),
        ('job_log', 'company_id'),
        ('promotion_item', 'deleted_at')
    ) AS required(table_name, column_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns AS columns
        WHERE columns.table_schema = 'mottainai'
          AND columns.table_name = required.table_name
          AND columns.column_name = required.column_name
    );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Required API columns are missing: %', v_missing;
    END IF;

    IF to_regclass('mottainai.employee_private_data') IS NULL THEN
        RAISE EXCEPTION 'Reversible employee private-data table is missing';
    END IF;

    IF to_regclass('mottainai.customer_private_data') IS NULL THEN
        RAISE EXCEPTION 'Reversible customer private-data table is missing';
    END IF;

    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
    INTO v_missing
    FROM (VALUES
        ('payload_ciphertext'), ('payload_nonce'), ('key_version'),
        ('algorithm'), ('payload_format'), ('encrypted_at'), ('deleted_at')
    ) AS required(column_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns AS columns
        WHERE columns.table_schema = 'mottainai'
          AND columns.table_name = 'customer_private_data'
          AND columns.column_name = required.column_name
    );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Customer private-data columns are missing: %', v_missing;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class relation
        JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'mottainai'
          AND relation.relname = 'customer_private_data'
          AND relation.relrowsecurity
          AND relation.relforcerowsecurity
    ) THEN
        RAISE EXCEPTION 'Customer private-data RLS must be enabled and forced';
    END IF;

    IF NOT has_table_privilege(
           'mottainai_api', 'mottainai.customer_private_data', 'SELECT')
       OR NOT has_column_privilege(
           'mottainai_api', 'mottainai.customer_private_data',
           'deleted_at', 'UPDATE')
       OR has_column_privilege(
           'mottainai_api', 'mottainai.customer_private_data',
           'payload_ciphertext', 'UPDATE')
       OR has_table_privilege(
           'mottainai_api', 'mottainai.customer_private_data', 'INSERT')
       OR has_table_privilege(
           'mottainai_api', 'mottainai.customer_private_data', 'DELETE')
       OR NOT has_table_privilege(
           'mottainai_customer_api', 'mottainai.customer_private_data', 'SELECT')
       OR NOT has_table_privilege(
           'mottainai_customer_api', 'mottainai.customer_private_data', 'INSERT')
       OR NOT has_table_privilege(
           'mottainai_customer_api', 'mottainai.customer_private_data', 'UPDATE')
       OR has_table_privilege(
           'mottainai_customer_api', 'mottainai.customer_private_data', 'DELETE') THEN
        RAISE EXCEPTION 'Customer private-data privileges violate least privilege';
    END IF;

    SELECT string_agg(required.policy_name, ', ' ORDER BY required.policy_name)
    INTO v_missing
    FROM (VALUES
        ('customer_private_data_select_policy'),
        ('customer_private_data_insert_policy'),
        ('customer_private_data_update_policy'),
        ('customer_private_data_staff_select_policy'),
        ('customer_private_data_staff_soft_delete_policy'),
        ('customer_private_data_lifecycle_soft_delete_policy'),
        ('client_api_private_data_select'),
        ('client_profile_owner_private_select'),
        ('client_profile_owner_private_insert'),
        ('client_profile_owner_private_update')
    ) AS required(policy_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'mottainai'
          AND tablename = 'customer_private_data'
          AND policyname = required.policy_name
    );

    IF v_missing IS NOT NULL OR EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'mottainai'
          AND tablename = 'customer_private_data'
          AND policyname = 'customer_private_data_self_policy'
    ) THEN
        RAISE EXCEPTION 'Customer private-data RLS policies are incomplete or overly broad: %',
            COALESCE(v_missing, 'legacy FOR ALL policy');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.customer_private_data'::regclass
          AND contype = 'f'
          AND confrelid = 'mottainai.customer'::regclass
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'Customer private-data must retain envelopes with ON DELETE RESTRICT';
    END IF;

    IF fn_sanitize_audit_json(
        '{"payload_ciphertext":"secret","payload_nonce":"secret"}'::JSONB
       )->>'payload_ciphertext' <> '[REDACTED]' THEN
        RAISE EXCEPTION 'Encrypted customer payload is not redacted from logs';
    END IF;

    SELECT string_agg(required.role_name, ', ' ORDER BY required.role_name)
    INTO v_missing
    FROM (VALUES
        ('mottainai_client_api'),
        ('mottainai_client_catalog_owner'),
        ('mottainai_client_profile_owner'),
        ('mottainai_client_auth_owner')
    ) AS required(role_name)
    LEFT JOIN pg_roles role_record ON role_record.rolname = required.role_name
    WHERE role_record.oid IS NULL
       OR role_record.rolcanlogin
       OR role_record.rolsuper
       OR role_record.rolcreaterole
       OR role_record.rolcreatedb
       OR role_record.rolreplication
       OR role_record.rolbypassrls;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Mobile API roles are missing or privileged: %', v_missing;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_auth_members membership
        JOIN pg_roles owner_role ON owner_role.oid = membership.roleid
        WHERE owner_role.rolname IN (
            'mottainai_client_catalog_owner',
            'mottainai_client_profile_owner',
            'mottainai_client_auth_owner'
        )
    ) THEN
        RAISE EXCEPTION 'SECURITY DEFINER owner roles retain a member after installation';
    END IF;

    IF has_table_privilege(
           'mottainai_client_api', 'mottainai.customer_auth', 'SELECT')
       OR has_table_privilege(
           'mottainai_client_api', 'mottainai.customer', 'INSERT')
       OR has_table_privilege(
           'mottainai_client_api', 'mottainai.customer_private_data', 'UPDATE')
       OR NOT has_table_privilege(
           'mottainai_client_api', 'mottainai.api_client_catalog_stores', 'SELECT')
       OR NOT has_table_privilege(
           'mottainai_client_api', 'mottainai.api_client_catalog_promotions', 'SELECT')
       OR NOT has_table_privilege(
           'mottainai_client_api', 'mottainai.api_client_catalog_promotion_items', 'SELECT') THEN
        RAISE EXCEPTION 'Mobile API grants violate least privilege';
    END IF;

    SELECT string_agg(required.view_name, ', ' ORDER BY required.view_name)
    INTO v_missing
    FROM (VALUES
        ('api_client_catalog_stores'),
        ('api_client_catalog_promotions'),
        ('api_client_catalog_promotion_items')
    ) AS required(view_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_class relation
        JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'mottainai'
          AND relation.relname = required.view_name
          AND relation.relkind = 'v'
          AND 'security_barrier=true' = ANY (relation.reloptions)
    );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Secure mobile catalog views are missing: %', v_missing;
    END IF;

    SELECT string_agg(required.signature, ', ' ORDER BY required.signature)
    INTO v_missing
    FROM (VALUES
        ('mottainai.fn_api_reserve_customer_id()'),
        ('mottainai.fn_api_create_firebase_customer_profile(integer,text,text,text,text,text,text,smallint,boolean,bytea,bytea,smallint,timestamp without time zone)'),
        ('mottainai.fn_api_update_firebase_customer_profile(text,text,text,boolean,bytea,bytea,smallint,timestamp without time zone)'),
        ('mottainai.fn_api_customer_login(text,text,timestamp without time zone)'),
        ('mottainai.fn_api_request_customer_recovery(text,text,timestamp without time zone)'),
        ('mottainai.fn_api_clear_customer_recovery(integer,text,timestamp without time zone)'),
        ('mottainai.fn_api_validate_customer_recovery(integer,text,timestamp without time zone)'),
        ('mottainai.fn_api_reset_customer_password(integer,text,text,timestamp without time zone)'),
        ('mottainai.fn_api_bootstrap_legacy_customer_context(text)')
    ) AS required(signature)
    WHERE to_regprocedure(required.signature) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Mobile API functions are missing: %', v_missing;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND (
              (table_name = 'employee' AND column_name IN ('name', 'cpf', 'email', 'phone'))
              OR (table_name = 'app_user' AND column_name IN ('cpf', 'email'))
          )
    ) THEN
        RAISE EXCEPTION 'Legacy employee/app_user personal columns were not removed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.app_user'::regclass
          AND conname = 'ck_app_user_active_firebase_uid'
    ) THEN
        RAISE EXCEPTION 'Active-user Firebase UID constraint is missing';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_enum
    JOIN pg_type ON pg_type.oid = pg_enum.enumtypid
    JOIN pg_namespace ON pg_namespace.oid = pg_type.typnamespace
    WHERE pg_namespace.nspname = 'mottainai'
      AND (
          (pg_type.typname = 'promotion_status'
           AND pg_enum.enumlabel = 'CANCELLED')
          OR
          (pg_type.typname = 'suggested_action_type'
           AND pg_enum.enumlabel = 'PURCHASE_ORDER')
      );

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Required API enum values are missing';
    END IF;

    SELECT string_agg(required.name, ', ' ORDER BY required.name)
    INTO v_missing
    FROM (VALUES
        ('vw_api_system_event'),
        ('vw_api_system_log'),
        ('vw_api_system_job'),
        ('vw_api_purchase_order'),
        ('vw_api_purchase_order_item'),
        ('vw_api_receiving'),
        ('vw_api_receiving_item'),
        ('vw_api_store_product_price'),
        ('vw_api_product_history'),
        ('vw_api_product_price_history')
    ) AS required(name)
    WHERE to_regclass('mottainai.' || required.name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Required API views are missing: %', v_missing;
    END IF;

    SELECT string_agg(required.signature, ', ' ORDER BY required.signature)
    INTO v_missing
    FROM (VALUES
        ('mottainai.fn_find_outbox_event_by_key(text)'),
        ('mottainai.fn_api_insert_purchase_order(integer,integer,integer,date,text,numeric)'),
        ('mottainai.fn_api_insert_receiving(integer,integer,text,timestamp without time zone)'),
        ('mottainai.fn_api_upsert_inventory(integer,integer)'),
        ('mottainai.fn_set_legacy_migration_context(integer)'),
        ('mottainai.fn_clear_legacy_migration_context()'),
        ('mottainai.fn_is_legacy_masked_email(text)'),
        ('mottainai.fn_is_legacy_masked_phone(text)')
    ) AS required(signature)
    WHERE to_regprocedure(required.signature) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Required functions are missing: %', v_missing;
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM pg_class
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'mottainai'
      AND pg_class.relname IN (
          'event_queue',
          'system_log',
          'error_log',
          'job_log',
          'product_history',
          'product_price_history'
      )
      AND pg_class.relrowsecurity;

    IF v_count <> 6 THEN
        RAISE EXCEPTION 'RLS is missing from one or more API source tables';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM (VALUES
        ('mottainai.vw_api_system_event'),
        ('mottainai.vw_api_purchase_order'),
        ('mottainai.vw_api_receiving'),
        ('mottainai.vw_api_store_product_price')
    ) AS locking_view(name)
    WHERE has_table_privilege('mottainai_api', locking_view.name, 'UPDATE');

    IF v_count <> 4 THEN
        RAISE EXCEPTION
            'API views used with FOR UPDATE lack the required privilege';
    END IF;

    IF NOT has_table_privilege(
        'mottainai_migrator', 'mottainai.company', 'INSERT')
       OR NOT has_table_privilege(
           'mottainai_migrator', 'mottainai.app_user', 'UPDATE')
       OR NOT has_function_privilege(
           'mottainai_migrator',
           'mottainai.fn_set_legacy_migration_context(integer)',
           'EXECUTE') THEN
        RAISE EXCEPTION 'The dedicated RPA role lacks required privileges';
    END IF;

    IF NOT mottainai.fn_is_protected_email('email_emp_001')
       OR NOT mottainai.fn_is_protected_phone('PHONE_EMP_001') THEN
        RAISE EXCEPTION 'Legacy masked values are not recognized';
    END IF;

    RAISE NOTICE 'API and RPA structural compatibility tests passed';
END;
$$;

DO $$
DECLARE
    v_customer_id INTEGER;
    v_deleted_at TIMESTAMPTZ;
    v_delete_restricted BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO customer (full_name, active)
        VALUES ('CUS_SHA256_' || repeat('A', 64), TRUE)
        RETURNING customer_id INTO v_customer_id;

        INSERT INTO customer_private_data (
            customer_id, payload_ciphertext, payload_nonce, key_version
        ) VALUES (
            v_customer_id,
            decode(repeat('AB', 17), 'hex'),
            decode(repeat('CD', 12), 'hex'),
            1
        );

        UPDATE customer SET active = FALSE
        WHERE customer_id = v_customer_id;

        SELECT deleted_at INTO v_deleted_at
        FROM customer_private_data
        WHERE customer_id = v_customer_id;

        IF v_deleted_at IS NULL THEN
            RAISE EXCEPTION 'Customer private-data lifecycle trigger did not apply soft deletion';
        END IF;

        BEGIN
            DELETE FROM customer WHERE customer_id = v_customer_id;
        EXCEPTION WHEN foreign_key_violation THEN
            v_delete_restricted := TRUE;
        END;

        IF NOT v_delete_restricted THEN
            RAISE EXCEPTION 'Customer private-data foreign key allowed physical deletion';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'rollback-customer-private-data-lifecycle-test';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'rollback-customer-private-data-lifecycle-test' THEN
            RAISE;
        END IF;
    END;

    RAISE NOTICE 'Customer private-data lifecycle test passed';
END;
$$;

DO $$
DECLARE
    v_idempotency_key TEXT :=
        'db-contract-test-' || txid_current()::TEXT;
    v_first_uuid UUID;
    v_second_uuid UUID;
    v_event_type TEXT;
    v_count INTEGER;
BEGIN
    v_first_uuid := fn_publish_integration_event(
        'DATABASE_CONTRACT_TEST',
        'database_contract',
        txid_current()::TEXT,
        jsonb_build_object('test', TRUE),
        NULL,
        NULL,
        v_idempotency_key,
        5
    );

    v_second_uuid := fn_publish_integration_event(
        'DATABASE_CONTRACT_TEST',
        'database_contract',
        txid_current()::TEXT,
        jsonb_build_object('test', TRUE),
        NULL,
        NULL,
        v_idempotency_key,
        5
    );

    SELECT event.event_type
    INTO v_event_type
    FROM fn_find_outbox_event_by_key(v_idempotency_key) AS event;

    SELECT COUNT(*)
    INTO v_count
    FROM event_queue
    WHERE idempotency_key = v_idempotency_key;

    IF v_first_uuid IS DISTINCT FROM v_second_uuid
       OR v_count <> 1
       OR v_event_type IS DISTINCT FROM 'DATABASE_CONTRACT_TEST' THEN
        RAISE EXCEPTION 'Outbox idempotency contract failed';
    END IF;

    DELETE FROM event_queue WHERE idempotency_key = v_idempotency_key;
    RAISE NOTICE 'Outbox idempotency test passed';
END;
$$;

DO $$
DECLARE
    v_plan_id INTEGER;
    v_role_id INTEGER;
    v_address_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
    v_supplier_id INTEGER;
    v_employee_id INTEGER;
    v_order_id INTEGER;
    v_receiving_id INTEGER;
    v_order_date TIMESTAMP;
    v_audit_count INTEGER;
BEGIN
    BEGIN
        SELECT MIN(plan_id) INTO v_plan_id FROM subscription_plan;
        SELECT MIN(role_id) INTO v_role_id FROM employee_role;

        IF v_plan_id IS NULL OR v_role_id IS NULL THEN
            RAISE EXCEPTION
                'Reference seed data is required for API smoke tests';
        END IF;

        INSERT INTO address (
            zip_code, street, number, neighborhood, city, state
        ) VALUES (
            '01001000', 'Database Contract Test', '1',
            'Test', 'Sao Paulo', 'SP'
        )
        RETURNING address_id INTO v_address_id;

        INSERT INTO company (
            plan_id, official_name, trade_name, cnpj, email
        ) VALUES (
            v_plan_id,
            'Database Contract Test',
            'Database Contract Test',
            '11222333000181',
            'EMAIL_SHA256_' || repeat('A', 64)
        )
        RETURNING company_id INTO v_company_id;

        PERFORM fn_set_legacy_migration_context(v_company_id);

        IF NULLIF(current_setting('app.current_company_id', TRUE), '')::INTEGER
           IS DISTINCT FROM v_company_id
           OR current_setting('app.current_operation', TRUE)
              IS DISTINCT FROM 'legacy-import' THEN
            RAISE EXCEPTION 'Legacy migration context was not established';
        END IF;

        INSERT INTO retail_store (
            company_id, address_id, name, cnpj
        ) VALUES (
            v_company_id, v_address_id, 'Database Contract Store',
            '11222333000181'
        )
        RETURNING store_id INTO v_store_id;

        INSERT INTO employee (store_id, role_id)
        VALUES (v_store_id, v_role_id)
        RETURNING employee_id INTO v_employee_id;

        INSERT INTO employee_private_data (
            employee_id,
            name_ciphertext,
            name_nonce,
            name_masked,
            cpf_ciphertext,
            cpf_nonce,
            cpf_masked,
            key_version,
            protection_state,
            encrypted_at
        ) VALUES (
            v_employee_id,
            decode(repeat('AB', 17), 'hex'),
            decode(repeat('CD', 12), 'hex'),
            'EMPLOYEE_TEST',
            decode(repeat('EF', 17), 'hex'),
            decode(repeat('01', 12), 'hex'),
            '***.***.***-**',
            1,
            'ENCRYPTED',
            CURRENT_TIMESTAMP
        );

        SELECT COUNT(*)
        INTO v_audit_count
        FROM audit_log
        WHERE table_affected = 'employee'
          AND record_id = v_employee_id::TEXT
          AND company_id = v_company_id
          AND user_id IS NULL
          AND application_name = 'legacy-import';

        IF v_audit_count <> 1 THEN
            RAISE EXCEPTION
                'Legacy import audit context did not preserve a NULL user';
        END IF;

        INSERT INTO supplier (address_id, trade_name, cnpj)
        VALUES (v_address_id, 'Database Contract Supplier', '11222333000181')
        RETURNING supplier_id INTO v_supplier_id;

        v_order_id := fn_api_insert_purchase_order(
            v_store_id,
            v_supplier_id,
            v_employee_id,
            CURRENT_DATE + 1,
            'database contract test',
            0
        );

        SELECT order_date
        INTO v_order_date
        FROM vw_api_purchase_order
        WHERE purchase_order_id = v_order_id;

        v_receiving_id := fn_api_insert_receiving(
            v_order_id,
            v_employee_id,
            'database contract test',
            v_order_date
        );

        IF v_order_id IS NULL OR v_receiving_id IS NULL THEN
            RAISE EXCEPTION 'Purchase or receiving API insert failed';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'rollback-api-contract-smoke-test';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'rollback-api-contract-smoke-test' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Legacy context, audit, purchase and receiving tests passed';
END;
$$;
