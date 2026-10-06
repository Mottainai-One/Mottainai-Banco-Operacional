-- ============================================================================
-- SENSITIVE DATA CONTRACT - STRUCTURAL TESTS
-- ============================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_column_type TEXT;
BEGIN
    IF NOT fn_is_sha256_token(
        'CPF_SHA256_' || repeat('A', 64),
        'CPF'
    ) THEN
        RAISE EXCEPTION 'SHA-256 token validation failed';
    END IF;

    IF fn_is_sha256_token('12345678901', 'CPF') THEN
        RAISE EXCEPTION 'Plain CPF was accepted as protected';
    END IF;

    IF NOT fn_is_bcrypt_hash('$2b$12$IXmU5oLQCmpUXCfYVoJ32GDKlllRwIyGjc9xgNWjLvGbc91EJqWA6') THEN
        RAISE EXCEPTION 'BCrypt validation failed';
    END IF;

    IF fn_is_bcrypt_hash('plain-password') THEN
        RAISE EXCEPTION 'Plain password was accepted as BCrypt';
    END IF;

    SELECT data_type INTO v_column_type
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'customer'
      AND column_name = 'birth_year';

    IF v_column_type <> 'smallint' THEN
        RAISE EXCEPTION 'customer.birth_year is missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'customer'
          AND column_name = 'birth_date'
    ) THEN
        RAISE EXCEPTION 'Exact customer birth date is still stored';
    END IF;

    IF to_regclass('mottainai.customer_consent') IS NULL
       OR to_regclass('mottainai.legacy_sync_record') IS NULL THEN
        RAISE EXCEPTION 'Privacy or RPA contract table is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mottainai_customer_api'
          AND NOT rolcanlogin
          AND NOT rolsuper
          AND NOT rolcreaterole
          AND NOT rolcreatedb
          AND NOT rolreplication
          AND NOT rolbypassrls
    ) THEN
        RAISE EXCEPTION 'Customer API role is missing or has an administrative attribute';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'mottainai'
          AND tablename = 'customer'
          AND policyname = 'customer_self_policy'
    ) THEN
        RAISE EXCEPTION 'Customer self-isolation policy is missing';
    END IF;

    IF has_table_privilege('mottainai_customer_api', 'mottainai.audit_log', 'SELECT')
       OR has_table_privilege('mottainai_customer_api', 'mottainai.legacy_sync_record', 'SELECT') THEN
        RAISE EXCEPTION 'Customer API can read audit or RPA metadata';
    END IF;

    IF fn_sanitize_audit_json(
        '{"profile":{"cpf":"12345678901","email":"person@example.com"}}'::JSONB
    ) #>> '{profile,cpf}' <> '[REDACTED]' THEN
        RAISE EXCEPTION 'Nested audit redaction failed';
    END IF;

    RAISE NOTICE 'Sensitive data contract tests passed';
END;
$$;
