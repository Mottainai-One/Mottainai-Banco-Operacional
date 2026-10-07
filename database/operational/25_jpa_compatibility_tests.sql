SET LOCAL search_path TO mottainai, public;

DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.table_name || '.' || required.column_name, ', ')
    INTO v_missing
    FROM (VALUES
        ('app_user', 'password_set'),
        ('app_user', 'token_version'),
        ('app_user', 'firebase_uid'),
        ('password_reset_token', 'password_reset_token_id'),
        ('password_reset_token', 'code_hash'),
        ('password_reset_token', 'attempts'),
        ('password_reset_token', 'token_hash'),
        ('password_reset_token', 'token_type')
    ) AS required(table_name, column_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema = 'mottainai'
          AND c.table_name = required.table_name
          AND c.column_name = required.column_name
    );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'JPA compatibility columns missing: %', v_missing;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'mottainai.password_reset_token'::regclass
          AND tgname = 'trg_sync_password_reset_hash_alias'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'JPA password reset hash sync trigger missing';
    END IF;

    RAISE NOTICE 'JPA compatibility structure tests passed';
END $$;
