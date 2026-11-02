-- Exercises INSERT/UPDATE/DELETE audit identity capture in an isolated transaction.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO mottainai, pg_temp, public;

CREATE TEMP TABLE audit_identity_fixture (
    fixture_id INTEGER PRIMARY KEY,
    fixture_value TEXT NOT NULL
);

CREATE TRIGGER trg_audit_identity_fixture
AFTER INSERT OR UPDATE OR DELETE ON pg_temp.audit_identity_fixture
FOR EACH ROW
EXECUTE FUNCTION mottainai.fn_trg_audit_log('fixture_id');

INSERT INTO pg_temp.audit_identity_fixture VALUES (1, 'before');
UPDATE pg_temp.audit_identity_fixture
SET fixture_value = 'after'
WHERE fixture_id = 1;
DELETE FROM pg_temp.audit_identity_fixture WHERE fixture_id = 1;

DO $assert$
DECLARE
    v_current_user NAME := CURRENT_USER;
    v_session_user NAME := SESSION_USER;
    v_event_count INTEGER;
BEGIN
    SELECT count(*)
    INTO v_event_count
    FROM mottainai.audit_log
    WHERE table_affected = 'audit_identity_fixture'
      AND record_id = '1';

    IF v_event_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 audit events, found %', v_event_count;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM mottainai.audit_log
        WHERE table_affected = 'audit_identity_fixture'
          AND record_id = '1'
          AND (
              database_current_user IS DISTINCT FROM v_current_user
              OR database_session_user IS DISTINCT FROM v_session_user
          )
    ) THEN
        RAISE EXCEPTION 'Audit rows did not retain the PostgreSQL execution identities';
    END IF;

    IF (
        SELECT count(DISTINCT operation::TEXT)
        FROM mottainai.audit_log
        WHERE table_affected = 'audit_identity_fixture'
          AND record_id = '1'
    ) <> 3 THEN
        RAISE EXCEPTION 'Expected one audit row for each of INSERT, UPDATE and DELETE';
    END IF;
END
$assert$;

COMMIT;
