-- ============================================================================
-- DAILY ANALYTICS BATCH CONTRACT TESTS
-- Test-only module.
-- ============================================================================

SET search_path TO mottainai_analytics, public;

DO $$
DECLARE
    v_required TEXT[];
BEGIN
    SELECT array_agg(required.object_name ORDER BY required.object_name)
    INTO v_required
    FROM (VALUES
        ('etl_pipeline_config'),
        ('etl_source_contract'),
        ('etl_daily_batch'),
        ('stg_operational_row'),
        ('etl_reconciliation'),
        ('etl_table_checkpoint'),
        ('etl_rejected_row')
    ) required(object_name)
    WHERE to_regclass('mottainai_analytics.' || required.object_name) IS NULL;

    IF v_required IS NOT NULL THEN
        RAISE EXCEPTION 'Missing daily batch objects: %', v_required;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM etl_pipeline_config
        WHERE pipeline_name = 'operational_to_analytics_daily'
          AND timezone_name = 'America/Sao_Paulo'
          AND schedule_local_time = TIME '02:00:00'
          AND enabled
    ) THEN
        RAISE EXCEPTION 'The daily 02:00 schedule contract is missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM etl_source_contract
        WHERE source_table IN (
            'employee_private_data', 'app_user', 'customer_auth', 'staff_session',
            'password_reset_token', 'integration_log'
        )
          AND (enabled OR payload_policy <> 'EXCLUDED')
    ) THEN
        RAISE EXCEPTION 'Credential-bearing sources are enabled for analytics';
    END IF;

    IF NOT fn_payload_has_forbidden_key(
        '{"employee_id":1,"name_ciphertext":"secret"}'::jsonb
    ) OR NOT fn_payload_has_forbidden_key(
        '{"employee_id":1,"email_masked":"a***@example.com"}'::jsonb
    ) THEN
        RAISE EXCEPTION 'Encrypted or masked identity fields are not blocked from analytics';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mottainai_analytics_loader'
          AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mottainai_analytics_reader'
          AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
    ) THEN
        RAISE EXCEPTION 'Safe analytics roles are missing';
    END IF;

    RAISE NOTICE 'Daily batch structural tests passed';
END;
$$;

DO $$
DECLARE
    v_batch_id UUID;
    v_expected JSONB;
    v_staged BOOLEAN;
BEGIN
    BEGIN
        v_batch_id := fn_begin_daily_batch(
            current_date - 1,
            NULL,
            'contract-test-transaction',
            '{"test":true}'::jsonb
        );

        IF (SELECT (scheduled_at AT TIME ZONE 'America/Sao_Paulo')::TIME
            FROM etl_daily_batch WHERE batch_id = v_batch_id)
            <> TIME '02:00:00' THEN
            RAISE EXCEPTION 'Batch was not scheduled at 02:00 Sao Paulo time';
        END IF;

        v_staged := fn_stage_operational_row(
            v_batch_id,
            'company',
            'company_id=1',
            '{"company_id":1,"legal_name":"Contract Test","active":true}'::jsonb,
            1,
            NULL,
            now() - interval '2 days',
            now() - interval '1 day',
            NULL
        );

        IF NOT v_staged THEN
            RAISE EXCEPTION 'Safe company row was rejected';
        END IF;

        SELECT jsonb_object_agg(
            source_table,
            CASE WHEN source_table = 'company' THEN 1 ELSE 0 END
        )
        INTO v_expected
        FROM etl_source_contract
        WHERE enabled AND required;

        IF NOT fn_reconcile_daily_batch(v_batch_id, v_expected) THEN
            RAISE EXCEPTION 'Valid batch reconciliation failed';
        END IF;

        PERFORM fn_mark_daily_batch_transformed(
            v_batch_id, 1, '{"transform":"contract-test"}'::jsonb);
        PERFORM fn_publish_daily_batch(v_batch_id);

        IF NOT EXISTS (
            SELECT 1 FROM etl_daily_batch
            WHERE batch_id = v_batch_id
              AND status = 'PUBLISHED'
              AND expected_rows = 1
              AND staged_rows = 1
              AND rows_written = 1
        ) THEN
            RAISE EXCEPTION 'Daily batch was not published correctly';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM etl_table_checkpoint
            WHERE last_batch_id = v_batch_id
              AND source_table = 'company'
        ) THEN
            RAISE EXCEPTION 'Table checkpoint was not advanced after publication';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001', MESSAGE = 'rollback-daily-batch-contract-test';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'rollback-daily-batch-contract-test' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Daily batch lifecycle test passed';
END;
$$;

DO $$
DECLARE
    v_batch_id UUID;
    v_result BOOLEAN;
BEGIN
    BEGIN
        v_batch_id := fn_begin_daily_batch(
            current_date - 2,
            NULL,
            'privacy-contract-test',
            '{"test":true}'::jsonb
        );

        v_result := fn_stage_operational_row(
            v_batch_id,
            'customer',
            'customer_id=1',
            '{"customer_id":1,"cpf":"12345678901"}'::jsonb
        );

        IF v_result OR NOT EXISTS (
            SELECT 1 FROM etl_rejected_row WHERE batch_id = v_batch_id
        ) THEN
            RAISE EXCEPTION 'Sensitive customer payload was not rejected';
        END IF;

        IF EXISTS (
            SELECT 1 FROM stg_operational_row WHERE batch_id = v_batch_id
        ) THEN
            RAISE EXCEPTION 'Sensitive payload reached analytics staging';
        END IF;

        RAISE EXCEPTION USING
            ERRCODE = 'P0001', MESSAGE = 'rollback-daily-batch-privacy-test';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'rollback-daily-batch-privacy-test' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Daily batch privacy test passed';
END;
$$;
