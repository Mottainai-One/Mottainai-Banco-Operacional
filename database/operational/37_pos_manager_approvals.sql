-- Durable approval requests raised by the offline-capable POS API.
-- Cancellation execution continues to use the existing pos_cancel_request
-- workflow and sp_decide_pos_cancellation procedure.
BEGIN;

CREATE TABLE IF NOT EXISTS mottainai.pos_manager_approval_request (
    request_id UUID PRIMARY KEY,
    store_id INTEGER NOT NULL
        REFERENCES mottainai.retail_store(store_id) ON DELETE RESTRICT,
    terminal_id INTEGER NOT NULL
        REFERENCES mottainai.pos_terminal(terminal_id) ON DELETE RESTRICT,
    employee_id INTEGER NOT NULL
        REFERENCES mottainai.employee(employee_id) ON DELETE RESTRICT,
    sale_id INTEGER NOT NULL,
    sale_date TIMESTAMP NOT NULL,
    sale_item_id INTEGER
        REFERENCES mottainai.sale_item(sale_item_id) ON DELETE RESTRICT,
    cancellation_request_id INTEGER
        REFERENCES mottainai.pos_cancel_request(cancel_request_id) ON DELETE RESTRICT,
    request_type VARCHAR(32) NOT NULL
        CHECK (request_type IN (
            'CANCEL_PURCHASE', 'CANCEL_PRODUCT', 'REFUND', 'RETURN',
            'SPECIAL_DISCOUNT'
        )),
    reason VARCHAR(250) NOT NULL,
    requested_amount DECIMAL(12,2)
        CHECK (requested_amount IS NULL OR requested_amount > 0),
    discount_percent DECIMAL(7,4)
        CHECK (discount_percent IS NULL OR discount_percent BETWEEN 0.0001 AND 100),
    details JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(details) = 'object'),
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED')),
    idempotency_key TEXT NOT NULL,
    decided_by_employee_id INTEGER
        REFERENCES mottainai.employee(employee_id) ON DELETE RESTRICT,
    decided_by_firebase_uid TEXT,
    decision_observation VARCHAR(250),
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (terminal_id, idempotency_key),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES mottainai.sales_transaction(sale_id, sale_date)
        ON DELETE RESTRICT,
    CHECK ((request_type = 'CANCEL_PURCHASE' AND sale_item_id IS NULL)
        OR (request_type IN ('CANCEL_PRODUCT', 'SPECIAL_DISCOUNT') AND sale_item_id IS NOT NULL)
        OR request_type IN ('REFUND', 'RETURN')),
    CHECK ((request_type <> 'SPECIAL_DISCOUNT' AND discount_percent IS NULL)
        OR (request_type = 'SPECIAL_DISCOUNT' AND discount_percent IS NOT NULL)),
    CHECK (decided_at IS NULL OR status <> 'PENDING')
);

-- Allow manager-reviewed cancellations for both drafts and completed sales.
CREATE OR REPLACE FUNCTION mottainai.fn_request_pos_cancellation(
    p_sale_id INTEGER,
    p_sale_date TIMESTAMP,
    p_sale_item_id INTEGER,
    p_requested_by INTEGER,
    p_reason VARCHAR(250)
)
RETURNS INTEGER AS $$
DECLARE
    v_target mottainai.pos_cancel_target;
    v_request_id INTEGER;
BEGIN
    IF p_sale_item_id IS NULL THEN
        v_target := 'SALE';
    ELSE
        v_target := 'ITEM';
        IF NOT EXISTS (
            SELECT 1 FROM mottainai.sale_item
            WHERE sale_item_id = p_sale_item_id
              AND sale_id = p_sale_id
              AND sale_date = p_sale_date
              AND status IN ('SOLD', 'DRAFT')
        ) THEN
            RAISE EXCEPTION 'Item de venda inválido ou já cancelado';
        END IF;
    END IF;

    INSERT INTO mottainai.pos_cancel_request (
        sale_id, sale_date, sale_item_id, requested_by, target_type, reason
    )
    VALUES (p_sale_id, p_sale_date, p_sale_item_id, p_requested_by, v_target, p_reason)
    RETURNING cancel_request_id INTO v_request_id;
    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE mottainai.sp_decide_pos_cancellation(
    p_cancel_request_id INTEGER,
    p_manager_id INTEGER,
    p_approve BOOLEAN,
    p_observation TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_request mottainai.pos_cancel_request%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM mottainai.pos_cancel_request
    WHERE cancel_request_id = p_cancel_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitação de cancelamento não encontrada';
    END IF;
    IF v_request.status <> 'PENDING' THEN
        RAISE EXCEPTION 'Solicitação de cancelamento não está pendente';
    END IF;

    UPDATE mottainai.pos_cancel_request
    SET approved_by = p_manager_id,
        status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        decided_at = NOW(), decision_observation = p_observation, updated_at = NOW()
    WHERE cancel_request_id = p_cancel_request_id;

    IF p_approve THEN
        IF v_request.target_type = 'SALE' THEN
            UPDATE mottainai.sales_transaction
            SET status = 'CANCELED', updated_at = NOW(), version = version + 1
            WHERE sale_id = v_request.sale_id AND sale_date = v_request.sale_date;
            UPDATE mottainai.sale_item
            SET status = 'CANCELED', canceled_at = NOW()
            WHERE sale_id = v_request.sale_id AND sale_date = v_request.sale_date
              AND status IN ('SOLD', 'DRAFT');
        ELSE
            UPDATE mottainai.sale_item
            SET status = 'CANCELED', canceled_at = NOW()
            WHERE sale_item_id = v_request.sale_item_id
              AND sale_id = v_request.sale_id AND sale_date = v_request.sale_date
              AND status IN ('SOLD', 'DRAFT');
        END IF;
        UPDATE mottainai.pos_cancel_request
        SET status = 'EXECUTED', executed_at = NOW(), updated_at = NOW()
        WHERE cancel_request_id = p_cancel_request_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION mottainai.fn_request_pos_cancellation(
    INTEGER, TIMESTAMP, INTEGER, INTEGER, VARCHAR
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_request_pos_cancellation(
    INTEGER, TIMESTAMP, INTEGER, INTEGER, VARCHAR
) TO mottainai_api;
REVOKE ALL ON PROCEDURE mottainai.sp_decide_pos_cancellation(
    INTEGER, INTEGER, BOOLEAN, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE mottainai.sp_decide_pos_cancellation(
    INTEGER, INTEGER, BOOLEAN, TEXT
) TO mottainai_api;

CREATE INDEX IF NOT EXISTS ix_pos_manager_approval_store_pending
    ON mottainai.pos_manager_approval_request(store_id, created_at DESC)
    WHERE status = 'PENDING';

ALTER TABLE mottainai.pos_manager_approval_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.pos_manager_approval_request FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_manager_approval_store_scope
    ON mottainai.pos_manager_approval_request;
CREATE POLICY pos_manager_approval_store_scope
    ON mottainai.pos_manager_approval_request
    FOR ALL TO mottainai_api
    USING (store_id = mottainai.fn_get_current_store_id())
    WITH CHECK (store_id = mottainai.fn_get_current_store_id());

REVOKE ALL ON mottainai.pos_manager_approval_request FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE
    ON mottainai.pos_manager_approval_request TO mottainai_api;

CREATE TABLE IF NOT EXISTS mottainai.pos_manager_approval_dispatch (
    request_id UUID PRIMARY KEY
        REFERENCES mottainai.pos_manager_approval_request(request_id)
        ON DELETE CASCADE,
    store_id INTEGER NOT NULL
        REFERENCES mottainai.retail_store(store_id) ON DELETE RESTRICT,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_attempt_at TIMESTAMPTZ,
    dispatched_at TIMESTAMPTZ,
    last_error_code VARCHAR(80),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE mottainai.pos_manager_approval_dispatch ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.pos_manager_approval_dispatch FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_manager_approval_dispatch_store_scope
    ON mottainai.pos_manager_approval_dispatch;
CREATE POLICY pos_manager_approval_dispatch_store_scope
    ON mottainai.pos_manager_approval_dispatch
    FOR ALL TO mottainai_api
    USING (store_id = mottainai.fn_get_current_store_id())
    WITH CHECK (store_id = mottainai.fn_get_current_store_id());

REVOKE ALL ON mottainai.pos_manager_approval_dispatch FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE
    ON mottainai.pos_manager_approval_dispatch TO mottainai_api;

COMMIT;
