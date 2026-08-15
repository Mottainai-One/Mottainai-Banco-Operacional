-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 23_PARTITION_FUNCTIONS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION sp_create_future_partitions()
RETURNS VOID AS $$
DECLARE
    v_date DATE;
    v_partition_name TEXT;
    v_schema TEXT := 'mottainai';
    v_tables TEXT[] := ARRAY['inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_date IN 
            SELECT generate_series(
                DATE_TRUNC('month', NOW()),
                DATE_TRUNC('month', NOW() + interval '6 months'),
                interval '1 month'
            )::DATE
        LOOP
            v_partition_name := v_table || '_' || TO_CHAR(v_date, 'YYYY_MM');
            
            EXECUTE format('
                CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I
                FOR VALUES FROM (%L) TO (%L)
            ', v_schema, v_partition_name, v_schema, v_table, 
               v_date, v_date + interval '1 month');
        END LOOP;
    END LOOP;
    
    RAISE NOTICE 'Future partitions created for 6 months ahead';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_drop_old_partitions(p_months_to_keep INTEGER DEFAULT 12)
LANGUAGE plpgsql AS $$
DECLARE
    v_cutoff_date DATE := DATE_TRUNC('month', NOW()) - (p_months_to_keep || ' months')::INTERVAL;
    v_partition RECORD;
    v_tables TEXT[] := ARRAY['inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'];
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_partition IN
            SELECT 
                schemaname,
                tablename,
                partitionrangestart
            FROM pg_partitions
            WHERE schemaname = 'mottainai'
              AND tablename LIKE v_table || '_%'
              AND partitionrangestart::DATE < v_cutoff_date
        LOOP
            EXECUTE format('
                DROP TABLE IF EXISTS %I.%I
            ', v_partition.schemaname, v_partition.tablename);
            
            RAISE NOTICE 'Dropped partition: %.%', v_partition.schemaname, v_partition.tablename;
        END LOOP;
    END LOOP;
    
    RAISE NOTICE 'Old partitions dropped (keeping % months)', p_months_to_keep;
END;
$$;

-- 24_PARTITION_CREATION.SQL
-- ====================================================================

SELECT sp_create_future_partitions();

-- 29_BUSINESS_RULES.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_calculate_sustainability_metrics(
    p_store_id INTEGER,
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
)
RETURNS TABLE (
    donated_quantity DECIMAL(18,3),
    disposed_quantity DECIMAL(18,3),
    promoted_units_sold DECIMAL(18,3),
    sales_value_from_promoted_items DECIMAL(18,2)
) AS $$
BEGIN
    RETURN QUERY
    WITH donations AS (
        SELECT COALESCE(SUM(di.donated_quantity), 0)::DECIMAL(18,3) AS qty
        FROM donation d
        JOIN donation_item di ON di.donation_id = d.donation_id
        WHERE d.store_id = p_store_id
          AND d.donation_date >= p_start_date
          AND d.donation_date < p_end_date
          AND d.status <> 'CANCELED'
    ),
    disposals AS (
        SELECT COALESCE(SUM(di.disposed_quantity), 0)::DECIMAL(18,3) AS qty
        FROM disposal d
        JOIN disposal_item di ON di.disposal_id = d.disposal_id
        WHERE d.store_id = p_store_id
          AND d.disposal_date >= p_start_date
          AND d.disposal_date < p_end_date
    ),
    promoted_sales AS (
        SELECT
            COALESCE(SUM(si.quantity_sold), 0)::DECIMAL(18,3) AS qty,
            COALESCE(SUM(si.subtotal), 0)::DECIMAL(18,2) AS value
        FROM sales_transaction st
        JOIN sale_item si ON si.sale_id = st.sale_id AND si.sale_date = st.sale_date
        JOIN promotion_item pi
          ON pi.product_id = si.product_id
        JOIN promotion pr ON pr.promotion_id = pi.promotion_id
        WHERE st.store_id = p_store_id
          AND st.sale_date >= p_start_date
          AND st.sale_date < p_end_date
          AND st.status = 'COMPLETED'
          AND si.status = 'SOLD'
          AND pr.active = TRUE
          AND pr.starts_at <= st.sale_date
          AND (pr.ends_at IS NULL OR pr.ends_at >= st.sale_date)
    )
    SELECT donations.qty, disposals.qty, promoted_sales.qty, promoted_sales.value
    FROM donations, disposals, promoted_sales;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE PROCEDURE sp_decide_promotion(
    p_promotion_id INTEGER,
    p_manager_id INTEGER,
    p_approve BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE promotion
    SET approved_by = CASE WHEN p_approve THEN p_manager_id ELSE NULL END,
        approved_at = CASE WHEN p_approve THEN NOW() ELSE NULL END,
        status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        active = p_approve,
        updated_at = NOW()
    WHERE promotion_id = p_promotion_id
      AND status IN ('DRAFT', 'PENDING_APPROVAL');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Promoção não encontrada ou não está aguardando aprovação';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_request_pos_cancellation(
    p_sale_id INTEGER,
    p_sale_date TIMESTAMP,
    p_sale_item_id INTEGER,
    p_requested_by INTEGER,
    p_reason VARCHAR(250)
)
RETURNS INTEGER AS $$
DECLARE
    v_target pos_cancel_target;
    v_request_id INTEGER;
BEGIN
    IF p_sale_item_id IS NULL THEN
        v_target := 'SALE';
    ELSE
        v_target := 'ITEM';
        IF NOT EXISTS (
            SELECT 1 FROM sale_item
            WHERE sale_item_id = p_sale_item_id
              AND sale_id = p_sale_id
              AND sale_date = p_sale_date
              AND status = 'SOLD'
        ) THEN
            RAISE EXCEPTION 'Item de venda inválido ou já cancelado';
        END IF;
    END IF;

    INSERT INTO pos_cancel_request (
        sale_id, sale_date, sale_item_id, requested_by, target_type, reason
    )
    VALUES (
        p_sale_id, p_sale_date, p_sale_item_id, p_requested_by, v_target, p_reason
    )
    RETURNING cancel_request_id INTO v_request_id;

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_decide_pos_cancellation(
    p_cancel_request_id INTEGER,
    p_manager_id INTEGER,
    p_approve BOOLEAN,
    p_observation TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_request pos_cancel_request%ROWTYPE;
BEGIN
    SELECT * INTO v_request
    FROM pos_cancel_request
    WHERE cancel_request_id = p_cancel_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitação de cancelamento não encontrada';
    END IF;

    IF v_request.status <> 'PENDING' THEN
        RAISE EXCEPTION 'Solicitação de cancelamento não está pendente';
    END IF;

    UPDATE pos_cancel_request
    SET approved_by = p_manager_id,
        status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        decided_at = NOW(),
        decision_observation = p_observation,
        updated_at = NOW()
    WHERE cancel_request_id = p_cancel_request_id;

    IF p_approve THEN
        IF v_request.target_type = 'SALE' THEN
            UPDATE sales_transaction
            SET status = 'CANCELED', updated_at = NOW(), version = version + 1
            WHERE sale_id = v_request.sale_id AND sale_date = v_request.sale_date;

            UPDATE sale_item
            SET status = 'CANCELED', canceled_at = NOW()
            WHERE sale_id = v_request.sale_id AND sale_date = v_request.sale_date
              AND status = 'SOLD';
        ELSE
            UPDATE sale_item
            SET status = 'CANCELED', canceled_at = NOW()
            WHERE sale_item_id = v_request.sale_item_id AND status = 'SOLD';
        END IF;

        UPDATE pos_cancel_request
        SET status = 'EXECUTED', executed_at = NOW(), updated_at = NOW()
        WHERE cancel_request_id = p_cancel_request_id;
    END IF;
END;
$$;


-- ====================================================================
-- GRANTS
-- ====================================================================

-- 32_GRANTS.SQL
-- ====================================================================

-- GRANT USAGE ON SCHEMA mottainai TO app_user;
-- GRANT USAGE ON SCHEMA mottainai_analytics TO app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA mottainai TO app_user;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA mottainai TO app_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mottainai TO app_user;
-- GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA mottainai TO app_user;

-- ====================================================================
-- END OF SCRIPT - VERSION 9.1 ENTERPRISE FINAL - CLIENT MOBILE + POS + INTEGRITY
-- 100% PRODUCTION READY - TODOS OS ÍNDICES CORRIGIDOS
