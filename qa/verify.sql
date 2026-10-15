\set ON_ERROR_STOP on

DO $$
BEGIN
    IF current_user <> 'mottainai_qa_app' THEN
        RAISE EXCEPTION 'QA verification must use the application login';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = current_user AND NOT rolsuper AND NOT rolbypassrls
    ) THEN
        RAISE EXCEPTION 'QA application login has privileged attributes';
    END IF;
    IF to_regclass('mottainai.company') IS NULL THEN
        RAISE EXCEPTION 'Operational schema was not installed';
    END IF;
END $$;

SELECT company_id FROM mottainai.company LIMIT 0;
