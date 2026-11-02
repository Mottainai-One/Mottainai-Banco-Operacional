-- Adds explicit PostgreSQL execution identities to audit events.
-- Existing audit rows remain NULL; no historical identities are inferred.
\set ON_ERROR_STOP on
BEGIN;

DO $guard$
BEGIN
    IF upper(current_database()) <> 'MOTTAINAI' THEN
        RAISE EXCEPTION 'Connect to MOTTAINAI; current database: %', current_database();
    END IF;
    IF to_regclass('mottainai.audit_log') IS NULL
       OR to_regclass('mottainai.audit_log_archive') IS NULL THEN
        RAISE EXCEPTION 'Apply the operational schema before migration 44';
    END IF;
    IF to_regprocedure('mottainai.fn_get_current_user_id()') IS NULL
       OR to_regtype('mottainai.audit_operation') IS NULL THEN
        RAISE EXCEPTION 'Audit prerequisites are missing';
    END IF;
END
$guard$;

-- audit_log is partitioned; PostgreSQL propagates the new parent columns.
ALTER TABLE mottainai.audit_log
    ADD COLUMN IF NOT EXISTS database_current_user NAME,
    ADD COLUMN IF NOT EXISTS database_session_user NAME;

-- The archive is an independent table and needs matching appended columns.
ALTER TABLE mottainai.audit_log_archive
    ADD COLUMN IF NOT EXISTS database_current_user NAME,
    ADD COLUMN IF NOT EXISTS database_session_user NAME;

COMMENT ON COLUMN mottainai.audit_log.database_current_user IS
    'PostgreSQL CURRENT_USER at the time of the audited statement.';
COMMENT ON COLUMN mottainai.audit_log.database_session_user IS
    'PostgreSQL SESSION_USER for the connection that performed the audited statement.';
COMMENT ON COLUMN mottainai.audit_log_archive.database_current_user IS
    'CURRENT_USER copied from the original audit event.';
COMMENT ON COLUMN mottainai.audit_log_archive.database_session_user IS
    'SESSION_USER copied from the original audit event.';

-- Preserve the existing event shape and behavior; add only the two identities.
CREATE OR REPLACE FUNCTION mottainai.fn_trg_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $function$
DECLARE
    v_user_id INTEGER;
    v_record_id TEXT;
BEGIN
    v_user_id := fn_get_current_user_id();

    BEGIN
        v_record_id := COALESCE(
            to_jsonb(NEW)->>TG_ARGV[0],
            to_jsonb(OLD)->>TG_ARGV[0],
            '0'
        );
    EXCEPTION WHEN OTHERS THEN
        v_record_id := '0';
    END;

    INSERT INTO audit_log (
        table_affected,
        operation,
        record_id,
        user_id,
        old_data,
        new_data,
        operation_date,
        database_current_user,
        database_session_user
    )
    VALUES (
        TG_TABLE_NAME,
        TG_OP::audit_operation,
        v_record_id,
        v_user_id,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('UPDATE', 'INSERT') THEN to_jsonb(NEW) ELSE NULL END,
        CURRENT_TIMESTAMP,
        CURRENT_USER,
        SESSION_USER
    );

    RETURN COALESCE(NEW, OLD);
EXCEPTION
    WHEN OTHERS THEN
        RETURN COALESCE(NEW, OLD);
END;
$function$;

COMMIT;
