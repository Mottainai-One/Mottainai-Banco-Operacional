-- Restaura a exigência de consentimento na leitura interna de clientes para notificações.
-- Idempotente: substitui apenas a política notification_customer_read.
\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
    IF to_regclass('mottainai.customer') IS NULL THEN
        RAISE EXCEPTION 'Aplique o schema operacional antes da migração 43';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = 'mottainai.customer'::regclass
          AND attname = 'marketing_consent'
          AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'A coluna mottainai.customer.marketing_consent não existe';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_notification_owner'
    ) THEN
        RAISE EXCEPTION 'A role mottainai_notification_owner não existe; aplique a migração 42 primeiro';
    END IF;
END $$;

DROP POLICY IF EXISTS notification_customer_read ON mottainai.customer;
CREATE POLICY notification_customer_read
    ON mottainai.customer
    FOR SELECT TO mottainai_notification_owner
    USING (
        active IS TRUE
        AND deleted_at IS NULL
        AND marketing_consent IS TRUE
    );

DO $$
DECLARE
    v_using TEXT;
BEGIN
    SELECT pg_get_expr(polqual, polrelid)
    INTO v_using
    FROM pg_policy
    WHERE polrelid = 'mottainai.customer'::regclass
      AND polname = 'notification_customer_read';

    IF v_using IS NULL
       OR position('MARKETING_CONSENT IS TRUE' IN upper(v_using)) = 0 THEN
        RAISE EXCEPTION 'A política notification_customer_read não exige consentimento: %', v_using;
    END IF;
END $$;

COMMIT;
