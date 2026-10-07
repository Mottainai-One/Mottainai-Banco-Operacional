-- Mottainai Operational - instalador completo da PR #23
-- Gerado a partir de database/operational/install.sql em 2026-10-07.
-- Banco vazio: mottainai_operational. PostgreSQL 15+; execute com usuario de migracao.
-- psql -v ON_ERROR_STOP=1 -d mottainai_operational -f mottainai_operational_complete_pr23.sql
BEGIN;

-- ===== INICIO 00_database.sql =====
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS mottainai;
SET search_path TO mottainai, public;

COMMENT ON SCHEMA mottainai IS
    'Fonte oficial dos cadastros e processos transacionais do Mottainai.';

-- ===== FIM 00_database.sql =====

-- ===== INICIO 01_enums.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 02_ENUMS.SQL
-- ====================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_order_status') THEN
        CREATE TYPE purchase_order_status AS ENUM ('PENDING', 'APPROVED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'receiving_status') THEN
        CREATE TYPE receiving_status AS ENUM ('PENDING', 'CONFIRMED', 'DIVERGENT');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_status') THEN
        CREATE TYPE sale_status AS ENUM ('COMPLETED', 'CANCELED', 'RETURNED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_cancel_status') THEN
        CREATE TYPE pos_cancel_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_cancel_target') THEN
        CREATE TYPE pos_cancel_target AS ENUM ('ITEM', 'SALE');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_item_status') THEN
        CREATE TYPE sale_item_status AS ENUM ('SOLD', 'CANCELED', 'RETURNED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'promotion_status') THEN
        CREATE TYPE promotion_status AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'EXPIRED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'movement_type') THEN
        CREATE TYPE movement_type AS ENUM ('IN', 'OUT', 'ADJUSTMENT', 'TRANSFER', 'DONATION', 'DISPOSAL');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_type') THEN
        CREATE TYPE inventory_type AS ENUM ('NORMAL', 'CONSIGNED', 'QUARANTINE');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN
        CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        CREATE TYPE payment_method AS ENUM ('CASH', 'CARD', 'PIX', 'BOLETO');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_status') THEN
        CREATE TYPE inventory_status AS ENUM ('IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_status') THEN
        CREATE TYPE alert_status AS ENUM ('ACTIVE', 'ANALYZING', 'RESOLVED', 'IGNORED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type') THEN
        CREATE TYPE alert_type AS ENUM ('EXPIRATION', 'CRITICAL_STOCK', 'RUPTURE', 'SLOW_MOVING', 'OVERSTOCK');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_status') THEN
        CREATE TYPE suggested_action_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_type') THEN
        CREATE TYPE suggested_action_type AS ENUM ('PROMOTION', 'TRANSFER', 'DONATION', 'DISPOSAL', 'REORDER');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pre_list_status') THEN
        CREATE TYPE pre_list_status AS ENUM ('GENERATED', 'IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transfer_status') THEN
        CREATE TYPE transfer_status AS ENUM ('REQUESTED', 'IN_TRANSIT', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'donation_status') THEN
        CREATE TYPE donation_status AS ENUM ('REGISTERED', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_operation') THEN
        CREATE TYPE audit_operation AS ENUM ('INSERT', 'UPDATE', 'DELETE');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_model_type') THEN
        CREATE TYPE ai_model_type AS ENUM ('FORECAST', 'RECOMMENDATION', 'CLASSIFICATION', 'OPTIMIZATION');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
        CREATE TYPE event_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELED');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'log_level') THEN
        CREATE TYPE log_level AS ENUM ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'migration_type') THEN
        CREATE TYPE migration_type AS ENUM ('SQL', 'JAVA', 'GROOVY', 'SCRIPT');
    END IF;
END $$;

-- ===== FIM 01_enums.sql =====

-- ===== INICIO 02_functions.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 03_VALIDATION_FUNCTIONS.SQL (TODAS IMMUTABLE)
-- ====================================================================

-- CPF and CNPJ validation depends only on the supplied text and fixed
-- check-digit arithmetic. It performs no table lookup, configuration read,
-- clock access, or locale-dependent operation, so IMMUTABLE is intentional.
-- If the validation algorithm changes, deploy it with CREATE OR REPLACE
-- FUNCTION so PostgreSQL invalidates dependent plans normally.

CREATE OR REPLACE FUNCTION fn_validate_cpf(p_cpf CHAR(11))
RETURNS BOOLEAN AS $$
DECLARE
    v_cpf TEXT;
    v_sum INTEGER := 0;
    v_remainder INTEGER;
    v_digit1 INTEGER;
    v_digit2 INTEGER;
    v_i INTEGER;
BEGIN
    v_cpf := regexp_replace(p_cpf, '[^0-9]', '', 'g');

    IF LENGTH(v_cpf) != 11 THEN
        RETURN FALSE;
    END IF;

    IF v_cpf ~ '^(\d)\1{10}$' THEN
        RETURN FALSE;
    END IF;

    v_sum := 0;
    FOR v_i IN 1..9 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cpf, v_i, 1) AS INTEGER) * (11 - v_i));
    END LOOP;

    v_remainder := (v_sum * 10) % 11;
    IF v_remainder = 10 THEN
        v_remainder := 0;
    END IF;

    v_digit1 := CAST(SUBSTRING(v_cpf, 10, 1) AS INTEGER);
    IF v_digit1 != v_remainder THEN
        RETURN FALSE;
    END IF;

    v_sum := 0;
    FOR v_i IN 1..10 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cpf, v_i, 1) AS INTEGER) * (12 - v_i));
    END LOOP;

    v_remainder := (v_sum * 10) % 11;
    IF v_remainder = 10 THEN
        v_remainder := 0;
    END IF;

    v_digit2 := CAST(SUBSTRING(v_cpf, 11, 1) AS INTEGER);
    IF v_digit2 != v_remainder THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_validate_email(p_email VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_email IS NULL OR
           p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_validate_cnpj(p_cnpj CHAR(14))
RETURNS BOOLEAN AS $$
DECLARE
    v_cnpj TEXT;
    v_sum INTEGER := 0;
    v_remainder INTEGER;
    v_weight1 INTEGER;
    v_weight2 INTEGER;
    v_digit1 INTEGER;
    v_digit2 INTEGER;
    v_i INTEGER;
BEGIN
    v_cnpj := regexp_replace(p_cnpj, '[^0-9]', '', 'g');

    IF LENGTH(v_cnpj) != 14 THEN
        RETURN FALSE;
    END IF;

    IF v_cnpj ~ '^(\d)\1{13}$' THEN
        RETURN FALSE;
    END IF;

    v_sum := 0;
    v_weight1 := 5;
    FOR v_i IN 1..12 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cnpj, v_i, 1) AS INTEGER) * v_weight1);
        v_weight1 := CASE WHEN v_weight1 = 2 THEN 9 ELSE v_weight1 - 1 END;
    END LOOP;

    v_remainder := v_sum % 11;
    v_digit1 := CASE WHEN v_remainder < 2 THEN 0 ELSE 11 - v_remainder END;

    IF CAST(SUBSTRING(v_cnpj, 13, 1) AS INTEGER) != v_digit1 THEN
        RETURN FALSE;
    END IF;

    v_sum := 0;
    v_weight2 := 6;
    FOR v_i IN 1..13 LOOP
        v_sum := v_sum + (CAST(SUBSTRING(v_cnpj, v_i, 1) AS INTEGER) * v_weight2);
        v_weight2 := CASE WHEN v_weight2 = 2 THEN 9 ELSE v_weight2 - 1 END;
    END LOOP;

    v_remainder := v_sum % 11;
    v_digit2 := CASE WHEN v_remainder < 2 THEN 0 ELSE 11 - v_remainder END;

    IF CAST(SUBSTRING(v_cnpj, 14, 1) AS INTEGER) != v_digit2 THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 04_SESSION_CONTEXT.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_set_session_context(
    p_user_id INTEGER,
    p_company_id INTEGER,
    p_store_id INTEGER DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, FALSE);
    PERFORM set_config('app.current_company_id', p_company_id::TEXT, FALSE);
    IF p_store_id IS NOT NULL THEN
        PERFORM set_config('app.current_store_id', p_store_id::TEXT, FALSE);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_current_user_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_user_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_get_current_company_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_company_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_get_current_store_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_store_id', TRUE)::INTEGER, NULL);
END;
$$ LANGUAGE plpgsql STABLE;

-- 06B_FUNCTIONS_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_generate_sku(
    p_product_name VARCHAR(150),
    p_category_name VARCHAR(100),
    p_brand VARCHAR(100) DEFAULT NULL
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_sku VARCHAR(50);
    v_counter INTEGER := 0;
    v_base_sku VARCHAR(40);
    v_words TEXT[];
    v_word VARCHAR(50);
    v_abbr VARCHAR(50) := '';
    v_suffix VARCHAR(10);
BEGIN
    v_words := string_to_array(trim(regexp_replace(p_product_name, '[^a-zA-Z0-9 ]', '', 'g')), ' ');

    IF array_length(v_words, 1) >= 3 THEN
        FOR i IN 1..3 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 1));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSIF array_length(v_words, 1) = 2 THEN
        FOR i IN 1..2 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 3));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSE
        v_abbr := UPPER(SUBSTRING(p_product_name, 1, 6));
    END IF;

    IF p_category_name IS NOT NULL AND p_category_name != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_category_name, 1, 2));
    END IF;

    IF p_brand IS NOT NULL AND p_brand != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_brand, 1, 2));
    END IF;

    v_abbr := regexp_replace(v_abbr, '[^A-Z0-9-]', '', 'g');

    IF LENGTH(v_abbr) < 4 THEN
        v_abbr := v_abbr || LPAD('X', 6 - LENGTH(v_abbr), 'X');
    END IF;

    v_abbr := SUBSTRING(v_abbr, 1, 30);
    v_base_sku := v_abbr;

    LOOP
        v_suffix := '';
        IF v_counter > 0 THEN
            v_suffix := '-' || TO_CHAR(v_counter, 'FM000');
            v_sku := v_base_sku || v_suffix;
        ELSE
            v_sku := v_base_sku;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM product WHERE sku = v_sku AND deleted_at IS NULL) THEN
            RETURN v_sku;
        END IF;

        v_counter := v_counter + 1;

        IF v_counter > 999 THEN
            RETURN 'SKU-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                   LPAD((random() * 999)::INTEGER::TEXT, 3, '0');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_generate_product_sku(
    p_product_id INTEGER
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_product_name VARCHAR(150);
    v_category_name VARCHAR(100);
    v_brand VARCHAR(100);
    v_sku VARCHAR(50);
BEGIN
    SELECT
        p.name,
        pc.name,
        p.brand
    INTO
        v_product_name,
        v_category_name,
        v_brand
    FROM product p
    JOIN product_category pc ON pc.category_id = p.category_id
    WHERE p.product_id = p_product_id;

    v_sku := fn_generate_sku(v_product_name, v_category_name, v_brand);

    RETURN v_sku;
END;
$$ LANGUAGE plpgsql;

-- 25_FUNCTIONS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_calculate_average_consumption(
    p_product_id INTEGER,
    p_store_id INTEGER,
    p_days INTEGER DEFAULT 30
) RETURNS DECIMAL(10,3) AS $$
DECLARE
    v_total_output DECIMAL(12,3);
BEGIN
    SELECT COALESCE(SUM(ABS(im.moved_quantity)), 0)
    INTO v_total_output
    FROM inventory_movement im
    JOIN inventory i ON i.inventory_id = im.inventory_id
    JOIN batch b ON b.batch_id = i.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND im.movement_type = 'OUT'
      AND im.movement_date >= NOW() - (p_days || ' days')::INTERVAL
      AND i.deleted_at IS NULL
      AND b.deleted_at IS NULL;

    IF p_days <= 0 OR v_total_output = 0 THEN
        RETURN 0;
    END IF;

    RETURN ROUND(v_total_output / p_days, 3);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_coverage(
    p_product_id INTEGER,
    p_store_id INTEGER
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    v_current_stock DECIMAL(12,3);
    v_avg_consumption DECIMAL(10,3);
BEGIN
    SELECT COALESCE(SUM(i.current_quantity), 0)
    INTO v_current_stock
    FROM inventory i
    JOIN batch b ON b.batch_id = i.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND i.deleted_at IS NULL
      AND b.deleted_at IS NULL;

    v_avg_consumption := fn_calculate_average_consumption(p_product_id, p_store_id, 30);

    IF v_avg_consumption IS NULL OR v_avg_consumption = 0 THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(v_current_stock / v_avg_consumption, 2);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_criticality(
    p_product_id INTEGER,
    p_store_id INTEGER
) RETURNS priority_level AS $$
DECLARE
    v_coverage DECIMAL(10,2);
BEGIN
    v_coverage := fn_calculate_coverage(p_product_id, p_store_id);

    IF v_coverage IS NULL THEN
        RETURN 'MEDIUM'::priority_level;
    ELSIF v_coverage <= 2 THEN
        RETURN 'CRITICAL'::priority_level;
    ELSIF v_coverage <= 5 THEN
        RETURN 'HIGH'::priority_level;
    ELSIF v_coverage <= 10 THEN
        RETURN 'MEDIUM'::priority_level;
    ELSE
        RETURN 'LOW'::priority_level;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_calculate_economy(
    p_store_id INTEGER,
    p_start_date DATE,
    p_end_date DATE
) RETURNS DECIMAL(12,2) AS $$
DECLARE
    v_total_sales DECIMAL(12,2);
    v_total_cost DECIMAL(12,2);
BEGIN
    SELECT COALESCE(SUM(total_amount), 0)
    INTO v_total_sales
    FROM sales_transaction
    WHERE store_id = p_store_id
      AND sale_date BETWEEN p_start_date AND p_end_date
      AND status = 'COMPLETED'
      AND deleted_at IS NULL;

    SELECT COALESCE(SUM(si.quantity_sold * COALESCE(b.unit_cost, 0)), 0)
    INTO v_total_cost
    FROM sale_item si
    JOIN sales_transaction st ON st.sale_id = si.sale_id
    LEFT JOIN batch b ON b.batch_id = si.batch_id
    WHERE st.store_id = p_store_id
      AND st.sale_date BETWEEN p_start_date AND p_end_date
      AND st.status = 'COMPLETED'
      AND st.deleted_at IS NULL;

    RETURN ROUND(v_total_sales - v_total_cost, 2);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_select_batch_fefo(
    p_product_id INTEGER,
    p_store_id INTEGER,
    p_quantity DECIMAL(10,3)
) RETURNS INTEGER AS $$
DECLARE
    v_batch_id INTEGER;
BEGIN
    SELECT b.batch_id
    INTO v_batch_id
    FROM batch b
    JOIN inventory i ON i.batch_id = b.batch_id
    WHERE b.product_id = p_product_id
      AND i.store_id = p_store_id
      AND b.active = TRUE
      AND i.current_quantity >= p_quantity
      AND b.deleted_at IS NULL
      AND i.deleted_at IS NULL
    ORDER BY b.expiration_date ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    RETURN v_batch_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_atomic_update_inventory(
    p_inventory_id INTEGER,
    p_quantity DECIMAL,
    p_movement_type movement_type,
    p_employee_id INTEGER DEFAULT NULL,
    p_observation TEXT DEFAULT NULL,
    p_expected_version INTEGER DEFAULT NULL
) RETURNS DECIMAL AS $$
DECLARE
    v_new_quantity DECIMAL;
    v_current_version INTEGER;
    v_previous_balance DECIMAL;
    v_store_id INTEGER;
BEGIN
    SELECT current_quantity, version, store_id
    INTO v_previous_balance, v_current_version, v_store_id
    FROM inventory
    WHERE inventory_id = p_inventory_id
    FOR UPDATE;

    IF v_previous_balance IS NULL THEN
        RAISE EXCEPTION 'Inventory % not found', p_inventory_id;
    END IF;

    IF p_expected_version IS NOT NULL AND p_expected_version != v_current_version THEN
        RAISE EXCEPTION 'Inventory % was modified by another transaction (version %)',
            p_inventory_id, v_current_version;
    END IF;

    v_new_quantity := v_previous_balance + p_quantity;

    IF v_new_quantity < 0 THEN
        RAISE EXCEPTION 'Insufficient stock for inventory % (balance: %, requested: %)',
            p_inventory_id, v_previous_balance, p_quantity;
    END IF;

    UPDATE inventory
    SET current_quantity = v_new_quantity,
        updated_at = NOW(),
        version = version + 1
    WHERE inventory_id = p_inventory_id
      AND version = v_current_version
    RETURNING current_quantity INTO v_new_quantity;

    INSERT INTO inventory_movement (
        inventory_id,
        employee_id,
        movement_date,
        movement_type,
        moved_quantity,
        previous_balance,
        current_balance,
        observation,
        store_id
    ) VALUES (
        p_inventory_id,
        p_employee_id,
        NOW(),
        p_movement_type,
        p_quantity,
        v_previous_balance,
        v_new_quantity,
        p_observation,
        v_store_id
    );

    RETURN v_new_quantity;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_publish_event(
    p_event_type VARCHAR(50),
    p_event_data JSONB,
    p_priority INTEGER DEFAULT 5
) RETURNS BIGINT AS $$
DECLARE
    v_event_id BIGINT;
BEGIN
    INSERT INTO event_queue (event_type, event_data, priority)
    VALUES (p_event_type, p_event_data, p_priority)
    RETURNING event_id INTO v_event_id;

    PERFORM pg_notify('mottainai_event',
        json_build_object('event_id', v_event_id, 'type', p_event_type)::TEXT);

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 25B_COST_AND_PRICE.SQL
-- Custo medio ponderado (RF16) e sugestao de preco de venda.
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_calculate_avg_cost(
    p_product_id INTEGER
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    v_total_qty DECIMAL(18,3);
    v_total_cost DECIMAL(18,2);
    v_avg_cost DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(i.current_quantity), 0), COALESCE(SUM(i.current_quantity * b.unit_cost), 0)
    INTO v_total_qty, v_total_cost
    FROM inventory i
    JOIN batch b ON b.batch_id = i.batch_id
    WHERE b.product_id = p_product_id
      AND b.active = TRUE
      AND b.deleted_at IS NULL
      AND i.deleted_at IS NULL;

    IF v_total_qty = 0 THEN
        RETURN 0;
    END IF;

    v_avg_cost := ROUND(v_total_cost / v_total_qty, 2);
    RETURN v_avg_cost;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION fn_suggest_sale_price(
    p_product_id INTEGER,
    p_margin_pct DECIMAL(7,4) DEFAULT NULL
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    v_avg_cost DECIMAL(10,2);
    v_margin DECIMAL(7,4);
    v_rule_value TEXT;
    v_price DECIMAL(10,2);
BEGIN
    v_avg_cost := fn_calculate_avg_cost(p_product_id);

    IF p_margin_pct IS NOT NULL THEN
        v_margin := p_margin_pct;
    ELSE
        SELECT rule_value INTO v_rule_value
        FROM system_rule
        WHERE rule_category = 'PRICE'
          AND rule_key = 'DEFAULT_MARGIN'
          AND active = TRUE;
        v_margin := COALESCE(v_rule_value::DECIMAL(7,4), 30.0) / 100;
    END IF;

    v_price := ROUND(v_avg_cost * (1 + v_margin), 2);
    RETURN v_price;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_refresh_product_price(
    p_product_id INTEGER
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    v_old_price DECIMAL(10,2);
    v_new_avg_cost DECIMAL(10,2);
    v_suggested DECIMAL(10,2);
BEGIN
    SELECT avg_cost INTO v_old_price FROM product WHERE product_id = p_product_id;

    v_new_avg_cost := fn_calculate_avg_cost(p_product_id);
    v_suggested := fn_suggest_sale_price(p_product_id);

    UPDATE product
    SET avg_cost = v_new_avg_cost,
        suggested_price = v_suggested,
        updated_at = NOW()
    WHERE product_id = p_product_id;

    IF v_old_price IS NOT NULL AND v_old_price <> v_new_avg_cost THEN
        INSERT INTO product_price_history (product_id, old_price, new_price, changed_at)
        VALUES (p_product_id, v_old_price, v_new_avg_cost, NOW());
    END IF;

    RETURN v_new_avg_cost;
END;
$$ LANGUAGE plpgsql;

-- ===== FIM 02_functions.sql =====

-- ===== INICIO 03_tables.sql =====
-- 05_MIGRATION_CONTROL.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS schema_version (
    version_id      BIGSERIAL PRIMARY KEY,
    version         VARCHAR(20) NOT NULL UNIQUE,
    description     VARCHAR(200) NOT NULL,
    type            migration_type NOT NULL DEFAULT 'SQL',
    script          VARCHAR(100) NOT NULL,
    checksum        VARCHAR(64),
    installed_by    VARCHAR(100) NOT NULL,
    installed_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    execution_time  INTEGER,
    success         BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_schema_version_version ON schema_version(version);
CREATE INDEX IF NOT EXISTS idx_schema_version_installed_at ON schema_version(installed_at);

-- 06_CORE_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS subscription_plan (
    plan_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    price           DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    store_limit     INTEGER NOT NULL CHECK (store_limit > 0),
    user_limit      INTEGER NOT NULL CHECK (user_limit > 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS address (
    address_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zip_code        CHAR(8) NOT NULL CHECK (zip_code ~ '^\d{8}$'),
    street          VARCHAR(150) NOT NULL,
    number          VARCHAR(10) NOT NULL,
    complement      VARCHAR(100),
    neighborhood    VARCHAR(100) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    state           CHAR(2) NOT NULL CHECK (state ~ '^[A-Z]{2}$'),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS company (
    company_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_id         INTEGER NOT NULL REFERENCES subscription_plan(plan_id) ON DELETE RESTRICT,
    official_name   VARCHAR(150) NOT NULL,
    trade_name      VARCHAR(150),
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) NOT NULL CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    latitude        DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude       DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS employee_role (
    role_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(80) NOT NULL UNIQUE,
    description     TEXT,
    permission_level INTEGER NOT NULL CHECK (permission_level >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS retail_store (
    store_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      INTEGER NOT NULL REFERENCES company(company_id) ON DELETE RESTRICT,
    address_id      INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
    name            VARCHAR(120) NOT NULL,
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    latitude        DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude       DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS employee (
    employee_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    role_id         INTEGER NOT NULL REFERENCES employee_role(role_id) ON DELETE RESTRICT,
    name            VARCHAR(150) NOT NULL,
    cpf             CHAR(11) NOT NULL UNIQUE CHECK (fn_validate_cpf(cpf)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    hire_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_user (
    user_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id     INTEGER NOT NULL UNIQUE REFERENCES employee(employee_id) ON DELETE RESTRICT,
    email           VARCHAR(150) NOT NULL UNIQUE CHECK (fn_validate_email(email)),
    password_hash   VARCHAR(255) NOT NULL,
    last_login      TIMESTAMP,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product_category (
    category_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS supplier (
    supplier_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_id      INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
    trade_name      VARCHAR(150) NOT NULL,
    cnpj            CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj)),
    email           VARCHAR(150) CHECK (fn_validate_email(email)),
    phone           VARCHAR(20),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tax_profile (
    tax_profile_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                VARCHAR(30) NOT NULL UNIQUE,
    name                VARCHAR(120) NOT NULL,
    description         TEXT,
    cfop                VARCHAR(4),
    icms_cst            VARCHAR(3),
    icms_csosn          VARCHAR(4),
    icms_rate           DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (icms_rate BETWEEN 0 AND 100),
    ipi_cst             VARCHAR(2),
    ipi_rate             DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (ipi_rate BETWEEN 0 AND 100),
    pis_cst             VARCHAR(2),
    pis_rate             DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (pis_rate BETWEEN 0 AND 100),
    cofins_cst          VARCHAR(2),
    cofins_rate         DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (cofins_rate BETWEEN 0 AND 100),
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product (
    product_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id     INTEGER NOT NULL REFERENCES product_category(category_id) ON DELETE RESTRICT,
    tax_profile_id  INTEGER NOT NULL REFERENCES tax_profile(tax_profile_id) ON DELETE RESTRICT,
    sku             VARCHAR(50) NOT NULL UNIQUE,
    barcode         VARCHAR(30) NOT NULL UNIQUE,
    ncm             VARCHAR(8) NOT NULL CHECK (ncm ~ '^\d{8}$'),
    cest            VARCHAR(7) CHECK (cest IS NULL OR cest ~ '^\d{7}$'),
    name            VARCHAR(150) NOT NULL,
    description     TEXT,
    brand           VARCHAR(100),
    unit_measure    VARCHAR(20) NOT NULL,
    weight          DECIMAL(10,3) CHECK (weight >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER NOT NULL DEFAULT 1,
    avg_cost        DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (avg_cost >= 0),
    suggested_price DECIMAL(10,2) CHECK (suggested_price IS NULL OR suggested_price >= 0)
);

-- ====================================================================
-- 06B_FUNCTIONS_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_generate_sku(
    p_product_name VARCHAR(150),
    p_category_name VARCHAR(100),
    p_brand VARCHAR(100) DEFAULT NULL
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_sku VARCHAR(50);
    v_counter INTEGER := 0;
    v_base_sku VARCHAR(40);
    v_words TEXT[];
    v_word VARCHAR(50);
    v_abbr VARCHAR(50) := '';
    v_suffix VARCHAR(10);
BEGIN
    v_words := string_to_array(trim(regexp_replace(p_product_name, '[^a-zA-Z0-9 ]', '', 'g')), ' ');

    IF array_length(v_words, 1) >= 3 THEN
        FOR i IN 1..3 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 1));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSIF array_length(v_words, 1) = 2 THEN
        FOR i IN 1..2 LOOP
            v_word := UPPER(SUBSTRING(v_words[i], 1, 3));
            v_abbr := v_abbr || v_word;
        END LOOP;
    ELSE
        v_abbr := UPPER(SUBSTRING(p_product_name, 1, 6));
    END IF;

    IF p_category_name IS NOT NULL AND p_category_name != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_category_name, 1, 2));
    END IF;

    IF p_brand IS NOT NULL AND p_brand != '' THEN
        v_abbr := v_abbr || '-' || UPPER(SUBSTRING(p_brand, 1, 2));
    END IF;

    v_abbr := regexp_replace(v_abbr, '[^A-Z0-9-]', '', 'g');

    IF LENGTH(v_abbr) < 4 THEN
        v_abbr := v_abbr || LPAD('X', 6 - LENGTH(v_abbr), 'X');
    END IF;

    v_abbr := SUBSTRING(v_abbr, 1, 30);
    v_base_sku := v_abbr;

    LOOP
        v_suffix := '';
        IF v_counter > 0 THEN
            v_suffix := '-' || TO_CHAR(v_counter, 'FM000');
            v_sku := v_base_sku || v_suffix;
        ELSE
            v_sku := v_base_sku;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM product WHERE sku = v_sku AND deleted_at IS NULL) THEN
            RETURN v_sku;
        END IF;

        v_counter := v_counter + 1;

        IF v_counter > 999 THEN
            RETURN 'SKU-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                   LPAD((random() * 999)::INTEGER::TEXT, 3, '0');
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_generate_product_sku(
    p_product_id INTEGER
) RETURNS VARCHAR(50) AS $$
DECLARE
    v_product_name VARCHAR(150);
    v_category_name VARCHAR(100);
    v_brand VARCHAR(100);
    v_sku VARCHAR(50);
BEGIN
    SELECT
        p.name,
        pc.name,
        p.brand
    INTO
        v_product_name,
        v_category_name,
        v_brand
    FROM product p
    JOIN product_category pc ON pc.category_id = p.category_id
    WHERE p.product_id = p_product_id;

    v_sku := fn_generate_sku(v_product_name, v_category_name, v_brand);

    RETURN v_sku;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- 06C_TRIGGER_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_trg_generate_sku()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    IF EXISTS (SELECT 1 FROM product WHERE sku = NEW.sku AND product_id != NEW.product_id AND deleted_at IS NULL) THEN
        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_generate_sku
    BEFORE INSERT ON product
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_generate_sku();

CREATE OR REPLACE FUNCTION fn_trg_update_sku_on_change()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF (OLD.name IS DISTINCT FROM NEW.name) OR
       (OLD.category_id IS DISTINCT FROM NEW.category_id) OR
       (OLD.brand IS DISTINCT FROM NEW.brand) THEN

        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_update_sku
    BEFORE UPDATE ON product
    FOR EACH ROW
    WHEN (OLD.name IS DISTINCT FROM NEW.name OR
          OLD.category_id IS DISTINCT FROM NEW.category_id OR
          OLD.brand IS DISTINCT FROM NEW.brand)
    EXECUTE FUNCTION fn_trg_update_sku_on_change();

-- 07_SUPPLIER_PRODUCT.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS supplier_product (
    supplier_product_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id     INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    supplier_code   VARCHAR(50),
    purchase_price  DECIMAL(10,2) NOT NULL CHECK (purchase_price >= 0),
    lead_time       INTEGER NOT NULL CHECK (lead_time >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    UNIQUE (supplier_id, product_id)
);

-- 08_PURCHASE_ORDER.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS purchase_order (
    purchase_order_id INTEGER GENERATED ALWAYS AS IDENTITY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    supplier_id     INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    order_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    expected_delivery_date DATE,
    status          purchase_order_status NOT NULL DEFAULT 'PENDING',
    observation     TEXT,
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    PRIMARY KEY (purchase_order_id, order_date)
) PARTITION BY RANGE (order_date);

CREATE TABLE IF NOT EXISTS purchase_order_item (
    purchase_order_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    requested_quantity DECIMAL(10,3) NOT NULL CHECK (requested_quantity > 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal        DECIMAL(12,2) GENERATED ALWAYS AS (requested_quantity * unit_price) STORED,
    order_date      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (purchase_order_id, order_date)
        REFERENCES purchase_order(purchase_order_id, order_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS receiving (
    receiving_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id INTEGER NOT NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    receiving_date  TIMESTAMP NOT NULL DEFAULT NOW(),
    status          receiving_status NOT NULL DEFAULT 'PENDING',
    observation     TEXT,
    order_date      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (purchase_order_id, order_date)
        REFERENCES purchase_order(purchase_order_id, order_date) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS receiving_item (
    receiving_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receiving_id    INTEGER NOT NULL REFERENCES receiving(receiving_id) ON DELETE CASCADE,
    purchase_order_item_id INTEGER NOT NULL REFERENCES purchase_order_item(purchase_order_item_id) ON DELETE RESTRICT,
    received_quantity DECIMAL(10,3) NOT NULL CHECK (received_quantity >= 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    manufacture_date DATE,
    expiration_date DATE NOT NULL,
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (manufacture_date IS NULL OR manufacture_date <= expiration_date)
);

-- 09_INVENTORY.SQL
-- ====================================================================

CREATE SEQUENCE IF NOT EXISTS batch_code_seq START 1;

CREATE TABLE IF NOT EXISTS batch (
    batch_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    receiving_item_id INTEGER REFERENCES receiving_item(receiving_item_id) ON DELETE SET NULL,
    batch_code      VARCHAR(60) NOT NULL UNIQUE,
    manufacture_date DATE,
    expiration_date DATE NOT NULL,
    initial_quantity DECIMAL(10,3) NOT NULL CHECK (initial_quantity > 0),
    unit_cost       DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    CHECK (manufacture_date IS NULL OR manufacture_date <= expiration_date)
);

CREATE TABLE IF NOT EXISTS inventory (
    inventory_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    inventory_type  inventory_type NOT NULL DEFAULT 'NORMAL',
    current_quantity DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
    minimum_quantity DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (minimum_quantity >= 0),
    maximum_quantity DECIMAL(10,3) CHECK (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity),
    location        VARCHAR(80),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    UNIQUE (store_id, batch_id, inventory_type)
);

-- 10_INVENTORY_MOVEMENT.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS inventory_movement (
    movement_id     INTEGER GENERATED ALWAYS AS IDENTITY,
    inventory_id    INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT,
    employee_id     INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    movement_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    movement_type   movement_type NOT NULL,
    moved_quantity  DECIMAL(10,3) NOT NULL CHECK (moved_quantity <> 0),
    previous_balance DECIMAL(10,3) NOT NULL CHECK (previous_balance >= 0),
    current_balance DECIMAL(10,3) NOT NULL CHECK (current_balance >= 0),
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    store_id        INTEGER,
    CONSTRAINT ck_movement_direction CHECK (
        (movement_type IN ('OUT', 'DISPOSAL') AND moved_quantity < 0) OR
        (movement_type IN ('IN') AND moved_quantity > 0) OR
        (movement_type IN ('ADJUSTMENT', 'TRANSFER', 'DONATION') AND moved_quantity <> 0)
    ),
    PRIMARY KEY (movement_id, movement_date)
) PARTITION BY RANGE (movement_date);

-- 11_SALES.SQL (PARTITIONED)
-- ====================================================================

CREATE TABLE IF NOT EXISTS customer (
    customer_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name            VARCHAR(150) NOT NULL,
    cpf                  CHAR(11) UNIQUE CHECK (cpf IS NULL OR fn_validate_cpf(cpf)),
    email                VARCHAR(150) CHECK (fn_validate_email(email)),
    phone                VARCHAR(20),
    address_id           INTEGER REFERENCES address(address_id) ON DELETE SET NULL,
    external_auth_uid    VARCHAR(150) UNIQUE,
    birth_date           DATE,
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_consent    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at           TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_auth (
    customer_auth_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id            INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    login_email            VARCHAR(150) NOT NULL UNIQUE CHECK (fn_validate_email(login_email)),
    password_hash          TEXT NOT NULL,
    password_changed_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    failed_attempts        INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until           TIMESTAMP,
    recovery_token_hash    TEXT,
    recovery_expires_at    TIMESTAMP,
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at          TIMESTAMP,
    created_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK ((recovery_token_hash IS NULL AND recovery_expires_at IS NULL)
        OR (recovery_token_hash IS NOT NULL AND recovery_expires_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS pos_terminal (
    terminal_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    terminal_code        VARCHAR(30) NOT NULL,
    name                 VARCHAR(80) NOT NULL,
    hostname             VARCHAR(120),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (store_id, terminal_code)
);

CREATE TABLE IF NOT EXISTS pos_shift (
    shift_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    terminal_id          INTEGER NOT NULL REFERENCES pos_terminal(terminal_id) ON DELETE RESTRICT,
    employee_id          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    opened_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    opening_amount       DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (opening_amount >= 0),
    closed_at             TIMESTAMP,
    closing_amount       DECIMAL(12,2) CHECK (closing_amount IS NULL OR closing_amount >= 0),
    expected_amount      DECIMAL(12,2),
    status               VARCHAR(20) NOT NULL DEFAULT 'OPEN'
                         CHECK (status IN ('OPEN','CLOSED','CANCELED')),
    observation          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE IF NOT EXISTS pos_cash_movement (
    cash_movement_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shift_id             INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT,
    employee_id          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    movement_type        VARCHAR(12) NOT NULL CHECK (movement_type IN ('SANGRIA','SUPRIMENTO')),
    amount               DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    movement_date        TIMESTAMP NOT NULL DEFAULT NOW(),
    reason               VARCHAR(200) NOT NULL,
    observation          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sales_transaction (
    sale_id         INTEGER GENERATED ALWAYS AS IDENTITY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    shift_id        INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT,
    customer_id     INTEGER REFERENCES customer(customer_id) ON DELETE SET NULL,
    customer_document VARCHAR(14) CHECK (customer_document IS NULL OR customer_document ~ '^\d{11}(\d{3})?$'),
    sale_date       TIMESTAMP NOT NULL DEFAULT NOW(),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    status          sale_status NOT NULL DEFAULT 'COMPLETED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP,
    version         INTEGER DEFAULT 1,
    PRIMARY KEY (sale_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS sale_item (
    sale_item_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id         INTEGER NOT NULL,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    batch_id        INTEGER REFERENCES batch(batch_id) ON DELETE SET NULL,
    quantity_sold   DECIMAL(10,3) NOT NULL CHECK (quantity_sold > 0),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    status          sale_item_status NOT NULL DEFAULT 'SOLD',
    canceled_at     TIMESTAMP,
    subtotal        DECIMAL(12,2) GENERATED ALWAYS AS (quantity_sold * unit_price) STORED,
    sale_date       TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sale_payment (
    sale_payment_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id              INTEGER NOT NULL,
    sale_date            TIMESTAMP NOT NULL,
    payment_method       payment_method NOT NULL,
    amount               DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    installments         INTEGER NOT NULL DEFAULT 1 CHECK (installments > 0),
    authorization_code   VARCHAR(100),
    nsu                  VARCHAR(100),
    transaction_id       VARCHAR(150),
    paid_at              TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS fiscal_document (
    fiscal_document_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id              INTEGER NOT NULL,
    sale_date            TIMESTAMP NOT NULL,
    document_type        VARCHAR(10) NOT NULL CHECK (document_type IN ('NFE','NFCE','SAT')),
    series               VARCHAR(10),
    document_number      VARCHAR(30),
    access_key           VARCHAR(44) UNIQUE CHECK (access_key IS NULL OR access_key ~ '^\d{44}$'),
    status               VARCHAR(20) NOT NULL DEFAULT 'AUTHORIZED'
                         CHECK (status IN ('PENDING','AUTHORIZED','CANCELED','REJECTED')),
    issued_at            TIMESTAMP,
    total_amount         DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    protocol_number      VARCHAR(100),
    xml_content          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE RESTRICT
);

-- 12_ALERTS_AND_ACTIONS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS pos_cancel_request (
    cancel_request_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id               INTEGER NOT NULL,
    sale_date             TIMESTAMP NOT NULL,
    sale_item_id          INTEGER REFERENCES sale_item(sale_item_id) ON DELETE RESTRICT,
    requested_by          INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    approved_by           INTEGER REFERENCES employee(employee_id) ON DELETE RESTRICT,
    target_type           pos_cancel_target NOT NULL,
    reason                VARCHAR(250) NOT NULL,
    status                pos_cancel_status NOT NULL DEFAULT 'PENDING',
    requested_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    decided_at            TIMESTAMP,
    executed_at           TIMESTAMP,
    decision_observation  TEXT,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE RESTRICT,
    CHECK ((target_type = 'ITEM' AND sale_item_id IS NOT NULL)
        OR (target_type = 'SALE' AND sale_item_id IS NULL)),
    CHECK (decided_at IS NULL OR decided_at >= requested_at),
    CHECK (executed_at IS NULL OR decided_at IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS alert (
    alert_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    title           VARCHAR(120) NOT NULL,
    description     TEXT,
    alert_type      alert_type NOT NULL,
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    status          alert_status NOT NULL DEFAULT 'ACTIVE',
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (resolved_at IS NULL OR resolved_at >= generated_at)
);

CREATE TABLE IF NOT EXISTS suggested_action (
    suggested_action_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_id        INTEGER NOT NULL REFERENCES alert(alert_id) ON DELETE RESTRICT,
    action_type     suggested_action_type NOT NULL,
    description     TEXT,
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    status          suggested_action_status NOT NULL DEFAULT 'PENDING',
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promotion (
    promotion_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id  INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    name                 VARCHAR(150) NOT NULL,
    description          TEXT,
    promotion_type       VARCHAR(20) NOT NULL CHECK (promotion_type IN ('DISCOUNT_PERCENT','DISCOUNT_FIXED','SPECIAL_PRICE')),
    starts_at             TIMESTAMP NOT NULL,
    ends_at               TIMESTAMP NOT NULL,
    status                promotion_status NOT NULL DEFAULT 'PENDING_APPROVAL',
    active                BOOLEAN NOT NULL DEFAULT FALSE,
    created_by            INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    approved_by           INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    approved_at           TIMESTAMP,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMP,
    CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS promotion_item (
    promotion_item_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_id         INTEGER NOT NULL REFERENCES promotion(promotion_id) ON DELETE CASCADE,
    product_id           INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    original_price       DECIMAL(12,2) NOT NULL CHECK (original_price >= 0),
    promotional_price    DECIMAL(12,2) NOT NULL CHECK (promotional_price >= 0),
    discount_percent     DECIMAL(7,4) GENERATED ALWAYS AS (
        CASE WHEN original_price > 0
             THEN ((original_price - promotional_price) / original_price) * 100
             ELSE 0 END
    ) STORED,
    quantity_available  DECIMAL(12,3) CHECK (quantity_available IS NULL OR quantity_available >= 0),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (promotion_id, product_id),
    CHECK (promotional_price <= original_price)
);

CREATE TABLE IF NOT EXISTS customer_geofence (
    geofence_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    store_id             INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE CASCADE,
    radius_meters        INTEGER NOT NULL DEFAULT 1000 CHECK (radius_meters BETWEEN 50 AND 10000),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (customer_id, store_id)
);

CREATE TABLE IF NOT EXISTS loyalty_account (
    loyalty_account_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id          INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    points_balance       INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    joined_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    active               BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS loyalty_transaction (
    loyalty_transaction_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loyalty_account_id   INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE CASCADE,
    sale_id              INTEGER,
    sale_date            TIMESTAMP,
    transaction_type     VARCHAR(20) NOT NULL CHECK (transaction_type IN ('EARN','REDEEM','ADJUSTMENT','EXPIRE')),
    points               INTEGER NOT NULL CHECK (points <> 0),
    description          VARCHAR(255) NOT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (sale_id, sale_date)
        REFERENCES sales_transaction(sale_id, sale_date) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS loyalty_reward (
    reward_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                   VARCHAR(120) NOT NULL,
    description            TEXT,
    points_cost            INTEGER NOT NULL CHECK (points_cost > 0),
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    valid_from             TIMESTAMP,
    valid_until            TIMESTAMP,
    created_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

CREATE TABLE IF NOT EXISTS loyalty_redemption (
    redemption_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loyalty_account_id  INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE RESTRICT,
    reward_id            INTEGER NOT NULL REFERENCES loyalty_reward(reward_id) ON DELETE RESTRICT,
    points_spent         INTEGER NOT NULL CHECK (points_spent > 0),
    redeemed_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    status               VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'
                         CHECK (status IN ('PENDING','CONFIRMED','CANCELED')),
    UNIQUE (loyalty_account_id, reward_id, redeemed_at)
);

-- 13_TRANSFERS_DONATIONS_DISPOSALS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS transfer (
    transfer_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    source_store_id INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    destination_store_id INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    request_date    TIMESTAMP NOT NULL DEFAULT NOW(),
    completion_date TIMESTAMP,
    status          transfer_status NOT NULL DEFAULT 'REQUESTED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1,
    CHECK (source_store_id <> destination_store_id),
    CHECK (completion_date IS NULL OR completion_date >= request_date)
);

CREATE TABLE IF NOT EXISTS transfer_item (
    transfer_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id     INTEGER NOT NULL REFERENCES transfer(transfer_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    transferred_quantity DECIMAL(10,3) NOT NULL CHECK (transferred_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS donation (
    donation_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    institution     VARCHAR(150) NOT NULL,
    donation_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    status          donation_status NOT NULL DEFAULT 'REGISTERED',
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS donation_item (
    donation_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id     INTEGER NOT NULL REFERENCES donation(donation_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    donated_quantity DECIMAL(10,3) NOT NULL CHECK (donated_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS disposal (
    disposal_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    suggested_action_id INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    reason          VARCHAR(100) NOT NULL,
    disposal_date   TIMESTAMP NOT NULL DEFAULT NOW(),
    observation     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    version         INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS disposal_item (
    disposal_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    disposal_id     INTEGER NOT NULL REFERENCES disposal(disposal_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    disposed_quantity DECIMAL(10,3) NOT NULL CHECK (disposed_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 14_REPLENISHMENT.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS replenishment_pre_list (
    pre_list_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id        INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id     INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL,
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    status          pre_list_status NOT NULL DEFAULT 'GENERATED',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS replenishment_pre_list_item (
    pre_list_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pre_list_id     INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE CASCADE,
    product_id      INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    suggested_quantity DECIMAL(10,3) NOT NULL CHECK (suggested_quantity > 0),
    priority        priority_level NOT NULL DEFAULT 'MEDIUM',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS replenishment_execution (
    execution_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pre_list_id     INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE RESTRICT,
    employee_id     INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    start_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    end_date        TIMESTAMP,
    rating          INTEGER CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS replenishment_execution_item (
    execution_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    execution_id    INTEGER NOT NULL REFERENCES replenishment_execution(execution_id) ON DELETE CASCADE,
    batch_id        INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT,
    replenished_quantity DECIMAL(10,3) NOT NULL CHECK (replenished_quantity > 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 15_AUDIT_AND_LOGS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    audit_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    table_affected  VARCHAR(60) NOT NULL,
    operation       audit_operation NOT NULL,
    record_id       TEXT NOT NULL,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    old_data        JSONB,
    new_data        JSONB,
    operation_date  TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (audit_id, operation_date)
) PARTITION BY RANGE (operation_date);

CREATE TABLE IF NOT EXISTS system_log (
    log_id          BIGSERIAL PRIMARY KEY,
    log_level       log_level NOT NULL,
    module          VARCHAR(50),
    message         TEXT NOT NULL,
    stack_trace     TEXT,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    ip_address      INET,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS error_log (
    error_id        BIGSERIAL PRIMARY KEY,
    error_code      VARCHAR(20),
    error_message   TEXT NOT NULL,
    function_name   VARCHAR(100),
    parameters      JSONB,
    stack_trace     TEXT,
    user_id         INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS integration_log (
    integration_id  BIGSERIAL PRIMARY KEY,
    integration_type VARCHAR(50) NOT NULL,
    direction       VARCHAR(10) NOT NULL,
    payload         JSONB,
    response        JSONB,
    status          VARCHAR(20) NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS job_log (
    job_id          BIGSERIAL PRIMARY KEY,
    job_name        VARCHAR(100) NOT NULL,
    job_type        VARCHAR(50),
    start_time      TIMESTAMP NOT NULL,
    end_time        TIMESTAMP,
    duration_seconds INTEGER,
    records_processed INTEGER,
    success         BOOLEAN,
    details         JSONB,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 16_HISTORY_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS product_history (
    history_id      BIGSERIAL PRIMARY KEY,
    product_id      INTEGER REFERENCES product(product_id) ON DELETE CASCADE,
    field_name      VARCHAR(50) NOT NULL,
    old_value       TEXT,
    new_value       TEXT,
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS supplier_history (
    history_id      BIGSERIAL PRIMARY KEY,
    supplier_id     INTEGER REFERENCES supplier(supplier_id) ON DELETE CASCADE,
    field_name      VARCHAR(50) NOT NULL,
    old_value       TEXT,
    new_value       TEXT,
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_price_history (
    price_history_id BIGSERIAL PRIMARY KEY,
    product_id      INTEGER REFERENCES product(product_id) ON DELETE CASCADE,
    old_price       DECIMAL(10,2),
    new_price       DECIMAL(10,2),
    changed_by      INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);


-- 18_EVENTS.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS event_queue (
    event_id        BIGSERIAL PRIMARY KEY,
    event_type      VARCHAR(50) NOT NULL,
    event_data      JSONB NOT NULL,
    priority        INTEGER DEFAULT 5,
    status          event_status NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMP,
    retry_count     INTEGER DEFAULT 0,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_event_queue_status ON event_queue(status, priority);
CREATE INDEX IF NOT EXISTS idx_event_queue_created ON event_queue(created_at);


-- 21_ARCHIVE_TABLES.SQL
-- ====================================================================

CREATE TABLE IF NOT EXISTS audit_log_archive (LIKE audit_log);
CREATE TABLE IF NOT EXISTS inventory_movement_archive (LIKE inventory_movement);
CREATE TABLE IF NOT EXISTS sales_transaction_archive (LIKE sales_transaction);

-- ====================================================================

CREATE TABLE IF NOT EXISTS system_rule (
    rule_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_category  VARCHAR(30) NOT NULL
                   CHECK (rule_category IN ('ENGINE','FINANCIAL','EXPIRATION','PRICE','GENERAL')),
    rule_key       VARCHAR(60) NOT NULL,
    rule_name      VARCHAR(120),
    rule_value     TEXT,
    value_type     VARCHAR(20) NOT NULL DEFAULT 'TEXT'
                   CHECK (value_type IN ('TEXT','NUMBER','BOOLEAN','JSON')),
    description    TEXT,
    active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (rule_category, rule_key)
);
CREATE INDEX IF NOT EXISTS idx_system_rule_category ON system_rule(rule_category);

-- End of core table definitions. The supplier table is defined earlier in this file.

-- ===== FIM 03_tables.sql =====

-- ===== INICIO 04_additional_tables.sql =====
SET search_path TO mottainai, public;

-- O funcionario ja possui CPF. A conta de acesso tambem recebe o campo por
-- requisito da API, mas ele e preenchido a partir de employee para evitar
-- divergencia entre as duas copias do dado pessoal.
ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS cpf CHAR(11);

UPDATE app_user app
SET cpf = employee.cpf
FROM employee
WHERE employee.employee_id = app.employee_id
  AND app.cpf IS DISTINCT FROM employee.cpf;

ALTER TABLE app_user
    ALTER COLUMN cpf SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_app_user_cpf'
          AND conrelid = 'app_user'::regclass
    ) THEN
        ALTER TABLE app_user ADD CONSTRAINT uq_app_user_cpf UNIQUE (cpf);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_app_user_cpf_valid'
          AND conrelid = 'app_user'::regclass
    ) THEN
        ALTER TABLE app_user ADD CONSTRAINT ck_app_user_cpf_valid
            CHECK (fn_validate_cpf(cpf));
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_sync_app_user_cpf()
RETURNS TRIGGER AS $$
DECLARE
    v_employee_cpf CHAR(11);
BEGIN
    SELECT cpf INTO v_employee_cpf
    FROM employee
    WHERE employee_id = NEW.employee_id;

    IF v_employee_cpf IS NULL THEN
        RAISE EXCEPTION 'Employee % does not exist or has no CPF', NEW.employee_id;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.cpf IS NULL THEN
        NEW.cpf := v_employee_cpf;
    ELSIF NEW.cpf IS DISTINCT FROM v_employee_cpf THEN
        RAISE EXCEPTION 'app_user.cpf must match employee.cpf';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_app_user_cpf ON app_user;
CREATE TRIGGER trg_sync_app_user_cpf
BEFORE INSERT OR UPDATE OF employee_id, cpf ON app_user
FOR EACH ROW EXECUTE FUNCTION fn_sync_app_user_cpf();

CREATE OR REPLACE FUNCTION fn_propagate_employee_cpf()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE app_user SET cpf = NEW.cpf WHERE employee_id = NEW.employee_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_propagate_employee_cpf ON employee;
CREATE TRIGGER trg_propagate_employee_cpf
AFTER UPDATE OF cpf ON employee
FOR EACH ROW
WHEN (OLD.cpf IS DISTINCT FROM NEW.cpf)
EXECUTE FUNCTION fn_propagate_employee_cpf();

-- Campo exigido pelo contrato atual da API. O preco efetivo por loja fica
-- versionado em store_product_price; base_price e o valor-base do cadastro.
ALTER TABLE product
    ADD COLUMN IF NOT EXISTS base_price DECIMAL(12,2) NOT NULL DEFAULT 0
        CHECK (base_price >= 0);

CREATE INDEX IF NOT EXISTS idx_product_ncm ON product (ncm);

-- Preço efetivo por loja. product.suggested_price continua sendo apenas sugestão.
CREATE TABLE IF NOT EXISTS store_product_price (
    store_product_price_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id               INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    product_id             INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    regular_price          DECIMAL(12,2) NOT NULL CHECK (regular_price > 0),
    valid_from             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until            TIMESTAMPTZ,
    active                 BOOLEAN NOT NULL DEFAULT TRUE,
    version                INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (valid_until IS NULL OR valid_until > valid_from),
    EXCLUDE USING gist (
        store_id WITH =,
        product_id WITH =,
        tstzrange(valid_from, COALESCE(valid_until, 'infinity'::timestamptz), '[)') WITH &&
    ) WHERE (active)
);

CREATE INDEX IF NOT EXISTS idx_store_product_price_lookup
    ON store_product_price (store_id, product_id, valid_from DESC)
    WHERE active;

-- Contagem física e reconciliação de estoque.
CREATE TABLE IF NOT EXISTS inventory_count (
    inventory_count_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_id           INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT,
    employee_id        INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
    started_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at        TIMESTAMPTZ,
    status             inventory_status NOT NULL DEFAULT 'IN_PROGRESS',
    observation        TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE IF NOT EXISTS inventory_count_item (
    inventory_count_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_count_id      BIGINT NOT NULL REFERENCES inventory_count(inventory_count_id) ON DELETE CASCADE,
    inventory_id            INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT,
    system_quantity         DECIMAL(12,3) NOT NULL CHECK (system_quantity >= 0),
    counted_quantity        DECIMAL(12,3) NOT NULL CHECK (counted_quantity >= 0),
    difference              DECIMAL(12,3) GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,
    observation             TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (inventory_count_id, inventory_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_count_store_status
    ON inventory_count (store_id, status, started_at DESC);

-- Recuperação de acesso de funcionários. Apenas hash do token é persistido.
CREATE TABLE IF NOT EXISTS password_reset_token (
    recovery_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
    token_hash        TEXT NOT NULL UNIQUE,
    expires_at        TIMESTAMPTZ NOT NULL,
    used_at           TIMESTAMPTZ,
    requested_ip      INET,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (expires_at > created_at),
    CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_password_reset_token_active
    ON password_reset_token (user_id, expires_at)
    WHERE used_at IS NULL;

-- Correlação de recomendações analíticas com ações operacionais.
ALTER TABLE suggested_action
    ADD COLUMN IF NOT EXISTS source_recommendation_uuid UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_suggested_action_source_recommendation
    ON suggested_action (source_recommendation_uuid)
    WHERE source_recommendation_uuid IS NOT NULL;

-- Evolui event_queue para um outbox transacional idempotente.
ALTER TABLE event_queue
    ADD COLUMN IF NOT EXISTS event_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS aggregate_type VARCHAR(60),
    ADD COLUMN IF NOT EXISTS aggregate_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS company_id INTEGER,
    ADD COLUMN IF NOT EXISTS store_id INTEGER,
    ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(180);

CREATE UNIQUE INDEX IF NOT EXISTS uq_event_queue_event_uuid ON event_queue (event_uuid);
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_queue_idempotency
    ON event_queue (idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_queue_dispatch
    ON event_queue (status, priority, occurred_at) WHERE published_at IS NULL;

CREATE OR REPLACE FUNCTION fn_publish_integration_event(
    p_event_type VARCHAR(50),
    p_aggregate_type VARCHAR(60),
    p_aggregate_id VARCHAR(120),
    p_event_data JSONB,
    p_company_id INTEGER DEFAULT NULL,
    p_store_id INTEGER DEFAULT NULL,
    p_idempotency_key VARCHAR(180) DEFAULT NULL,
    p_priority INTEGER DEFAULT 5
) RETURNS UUID AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    INSERT INTO event_queue (
        event_type, aggregate_type, aggregate_id, event_data,
        company_id, store_id, idempotency_key, priority
    ) VALUES (
        p_event_type, p_aggregate_type, p_aggregate_id, p_event_data,
        p_company_id, p_store_id, p_idempotency_key, p_priority
    )
    ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING event_uuid INTO v_event_uuid;

    PERFORM pg_notify('mottainai_event', v_event_uuid::TEXT);
    RETURN v_event_uuid;
END;
$$ LANGUAGE plpgsql;

-- End of additional table definitions. The password reset token table is complete above.

-- ===== FIM 04_additional_tables.sql =====

-- ===== INICIO 04_security.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 29_ROW_LEVEL_SECURITY.SQL
-- ====================================================================

ALTER TABLE company ENABLE ROW LEVEL SECURITY;
ALTER TABLE retail_store ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_policy ON company;
CREATE POLICY company_policy ON company
    USING (company_id = fn_get_current_company_id());

DROP POLICY IF EXISTS store_policy ON retail_store;
CREATE POLICY store_policy ON retail_store
    USING (company_id = fn_get_current_company_id());

DROP POLICY IF EXISTS employee_policy ON employee;
CREATE POLICY employee_policy ON employee
    USING (store_id IN (
        SELECT store_id FROM retail_store
        WHERE company_id = fn_get_current_company_id()
    ));

DROP POLICY IF EXISTS inventory_policy ON inventory;
CREATE POLICY inventory_policy ON inventory
    USING (store_id IN (
        SELECT store_id FROM retail_store
        WHERE company_id = fn_get_current_company_id()
    ));

DROP POLICY IF EXISTS sales_policy ON sales_transaction;
CREATE POLICY sales_policy ON sales_transaction
    USING (store_id IN (
        SELECT store_id FROM retail_store
        WHERE company_id = fn_get_current_company_id()
    ));

DROP POLICY IF EXISTS purchase_order_policy ON purchase_order;
CREATE POLICY purchase_order_policy ON purchase_order
    USING (store_id IN (
        SELECT store_id FROM retail_store
        WHERE company_id = fn_get_current_company_id()
    ));

-- ===== FIM 04_security.sql =====

-- ===== INICIO 05_indexes.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 22_INDEXES.SQL - SEM FUNÇÕES NÃO IMUTÁVEIS (CORRIGIDO)
-- ====================================================================

-- Índices Únicos
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_cpf_global ON employee(cpf) WHERE active = true AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_cnpj_global ON supplier(cnpj) WHERE active = true AND deleted_at IS NULL;

-- Índices Parciais - APENAS COM COLUNAS, SEM FUNÇÕES
CREATE INDEX IF NOT EXISTS idx_product_active_name ON product(name) WHERE active = true AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_category_active ON product_category(name) WHERE active = true AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_positive ON inventory(store_id, batch_id)
WHERE current_quantity > 0 AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_alert_active_store ON alert(store_id, priority) WHERE status = 'ACTIVE';

-- CORREÇÃO: REMOVIDO date_trunc do índice
-- CREATE INDEX IF NOT EXISTS idx_sales_current_month ON sales_transaction(store_id, sale_date)
-- WHERE sale_date >= date_trunc('month', CURRENT_DATE) AND deleted_at IS NULL;

-- CORREÇÃO: REMOVIDO status IN do índice (usa enum)
-- CREATE INDEX IF NOT EXISTS idx_purchase_order_pending ON purchase_order(supplier_id)
-- WHERE status = 'PENDING' AND deleted_at IS NULL;

-- Índices Compostos
CREATE INDEX IF NOT EXISTS idx_alert_store_status_created ON alert(store_id, status, created_at)
WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_batch_product_expiration ON batch(product_id, expiration_date)
WHERE active = true AND deleted_at IS NULL;

-- CORREÇÃO: REMOVIDO date_trunc do índice
-- CREATE INDEX IF NOT EXISTS idx_movement_store_date ON inventory_movement(store_id, movement_date)
-- WHERE movement_date >= date_trunc('month', CURRENT_DATE) - interval '3 months';

-- CORREÇÃO: REMOVIDO status IN do índice
-- CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier_status ON purchase_order(supplier_id, status)
-- WHERE status IN ('APPROVED', 'PENDING') AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_store_product ON inventory(store_id, batch_id)
WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_store_status_date ON sales_transaction(store_id, status, sale_date)
WHERE deleted_at IS NULL;

-- Índices para Foreign Keys (todos sem funções)
CREATE INDEX IF NOT EXISTS idx_product_category_id ON product(category_id);
CREATE INDEX IF NOT EXISTS idx_supplier_product_supplier_id ON supplier_product(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_product_product_id ON supplier_product(product_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_store_id ON purchase_order(store_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_supplier_id ON purchase_order(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_employee_id ON purchase_order(employee_id);
CREATE INDEX IF NOT EXISTS idx_receiving_purchase_order_id ON receiving(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_receiving_employee_id ON receiving(employee_id);
CREATE INDEX IF NOT EXISTS idx_receiving_item_receiving_id ON receiving_item(receiving_id);
CREATE INDEX IF NOT EXISTS idx_receiving_item_order_item_id ON receiving_item(purchase_order_item_id);
CREATE INDEX IF NOT EXISTS idx_batch_product_id ON batch(product_id);
CREATE INDEX IF NOT EXISTS idx_batch_receiving_item_id ON batch(receiving_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_batch_id ON inventory(batch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movement_inventory_id ON inventory_movement(inventory_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_id ON sale_item(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_product_id ON sale_item(product_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_batch_id ON sale_item(batch_id);
CREATE INDEX IF NOT EXISTS idx_alert_store_id ON alert(store_id);
CREATE INDEX IF NOT EXISTS idx_transfer_source_store ON transfer(source_store_id);
CREATE INDEX IF NOT EXISTS idx_transfer_destination_store ON transfer(destination_store_id);
CREATE INDEX IF NOT EXISTS idx_donation_store_id ON donation(store_id);
CREATE INDEX IF NOT EXISTS idx_disposal_store_id ON disposal(store_id);

CREATE INDEX IF NOT EXISTS idx_product_tax_profile_id ON product(tax_profile_id);
CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON sales_transaction(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_shift_id ON sales_transaction(shift_id);
CREATE INDEX IF NOT EXISTS idx_sale_payment_sale ON sale_payment(sale_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_fiscal_document_sale ON fiscal_document(sale_id, sale_date);
CREATE INDEX IF NOT EXISTS idx_pos_terminal_store ON pos_terminal(store_id);
CREATE INDEX IF NOT EXISTS idx_pos_shift_terminal_status ON pos_shift(terminal_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_shift_one_open_terminal
    ON pos_shift(terminal_id) WHERE status = 'OPEN';
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_shift_one_open_employee
    ON pos_shift(employee_id) WHERE status = 'OPEN';
CREATE INDEX IF NOT EXISTS idx_pos_cash_movement_shift ON pos_cash_movement(shift_id, movement_date);
CREATE INDEX IF NOT EXISTS idx_promotion_store_active ON promotion(store_id, starts_at, ends_at) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_promotion_item_product ON promotion_item(product_id);
CREATE INDEX IF NOT EXISTS idx_customer_geofence_store ON customer_geofence(store_id) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_loyalty_transaction_account ON loyalty_transaction(loyalty_account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_loyalty_redemption_account ON loyalty_redemption(loyalty_account_id, redeemed_at);

-- ===== FIM 05_indexes.sql =====

-- ===== INICIO 06_triggers.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 06C_TRIGGER_SKU.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_trg_generate_sku()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    IF EXISTS (SELECT 1 FROM product WHERE sku = NEW.sku AND product_id != NEW.product_id AND deleted_at IS NULL) THEN
        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_generate_sku
    BEFORE INSERT ON product
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_generate_sku();

CREATE OR REPLACE FUNCTION fn_trg_update_sku_on_change()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name VARCHAR(100);
BEGIN
    IF (OLD.name IS DISTINCT FROM NEW.name) OR
       (OLD.category_id IS DISTINCT FROM NEW.category_id) OR
       (OLD.brand IS DISTINCT FROM NEW.brand) THEN

        SELECT name INTO v_category_name
        FROM product_category
        WHERE category_id = NEW.category_id;

        NEW.sku := fn_generate_sku(NEW.name, v_category_name, NEW.brand);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_update_sku
    BEFORE UPDATE ON product
    FOR EACH ROW
    WHEN (OLD.name IS DISTINCT FROM NEW.name OR
          OLD.category_id IS DISTINCT FROM NEW.category_id OR
          OLD.brand IS DISTINCT FROM NEW.brand)
    EXECUTE FUNCTION fn_trg_update_sku_on_change();

-- 26_TRIGGERS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_soft_delete_product()
RETURNS TRIGGER AS $$
BEGIN
    NEW.active = false;
    NEW.deleted_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_soft_delete_product
    BEFORE UPDATE OF active ON product
    FOR EACH ROW
    WHEN (NEW.active = false AND OLD.active = true)
    EXECUTE FUNCTION fn_soft_delete_product();

CREATE OR REPLACE FUNCTION fn_trg_create_batch() RETURNS TRIGGER AS $$
DECLARE
    v_batch_code VARCHAR(60);
    v_product_id INTEGER;
    v_unit_price DECIMAL(10,2);
BEGIN
    SELECT po_item.product_id, po_item.unit_price
    INTO v_product_id, v_unit_price
    FROM purchase_order_item po_item
    WHERE po_item.purchase_order_item_id = NEW.purchase_order_item_id;

    v_batch_code := 'BATCH-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                     LPAD(NEXTVAL('batch_code_seq')::TEXT, 6, '0');

    INSERT INTO batch (
        product_id,
        receiving_item_id,
        batch_code,
        manufacture_date,
        expiration_date,
        initial_quantity,
        unit_cost
    ) VALUES (
        v_product_id,
        NEW.receiving_item_id,
        v_batch_code,
        NEW.manufacture_date,
        NEW.expiration_date,
        NEW.received_quantity,
        NEW.unit_price
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO error_log (error_message, function_name, parameters)
        VALUES (SQLERRM, 'fn_trg_create_batch',
                jsonb_build_object('receiving_item_id', NEW.receiving_item_id));
        RAISE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_create_batch
    AFTER INSERT ON receiving_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_create_batch();

CREATE OR REPLACE FUNCTION fn_trg_select_batch_fefo() RETURNS TRIGGER AS $$
DECLARE
    v_store_id INTEGER;
    v_batch_id INTEGER;
BEGIN
    IF NEW.batch_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT s.store_id INTO v_store_id
    FROM sales_transaction s
    WHERE s.sale_id = NEW.sale_id;

    v_batch_id := fn_select_batch_fefo(NEW.product_id, v_store_id, NEW.quantity_sold);

    IF v_batch_id IS NULL THEN
        RAISE EXCEPTION 'Insufficient stock for product % in store % (FEFO selection failed)',
            NEW.product_id, v_store_id;
    END IF;

    NEW.batch_id := v_batch_id;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO error_log (error_message, function_name, parameters)
        VALUES (SQLERRM, 'fn_trg_select_batch_fefo',
                jsonb_build_object('sale_id', NEW.sale_id, 'product_id', NEW.product_id));
        RAISE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_select_batch_fefo
    BEFORE INSERT ON sale_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_select_batch_fefo();

CREATE OR REPLACE FUNCTION fn_trg_audit_log() RETURNS TRIGGER AS $$
DECLARE
    v_user_id INTEGER;
    v_record_id TEXT;
BEGIN
    v_user_id := fn_get_current_user_id();

    BEGIN
        v_record_id := COALESCE(
            (to_jsonb(NEW)->>TG_ARGV[0]),
            (to_jsonb(OLD)->>TG_ARGV[0]),
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
        operation_date
    )
    VALUES (
        TG_TABLE_NAME,
        TG_OP::audit_operation,
        v_record_id,
        v_user_id,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) ELSE NULL END,
        NOW()
    );

    RETURN COALESCE(NEW, OLD);
EXCEPTION
    WHEN OTHERS THEN
        RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_audit_disposal
    AFTER INSERT OR UPDATE OR DELETE ON disposal
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('disposal_id');

CREATE OR REPLACE TRIGGER trg_audit_transfer
    AFTER INSERT OR UPDATE OR DELETE ON transfer
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('transfer_id');

CREATE OR REPLACE TRIGGER trg_audit_donation
    AFTER INSERT OR UPDATE OR DELETE ON donation
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('donation_id');

CREATE OR REPLACE FUNCTION fn_trg_product_history() RETURNS TRIGGER AS $$
DECLARE
    v_user_id INTEGER := fn_get_current_user_id();
BEGIN
    IF OLD IS NOT NULL AND NEW IS NOT NULL THEN
        IF OLD.name IS DISTINCT FROM NEW.name THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'name', OLD.name, NEW.name, v_user_id);
        END IF;

        IF OLD.brand IS DISTINCT FROM NEW.brand THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'brand', OLD.brand, NEW.brand, v_user_id);
        END IF;

        IF OLD.weight IS DISTINCT FROM NEW.weight THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'weight', OLD.weight::TEXT, NEW.weight::TEXT, v_user_id);
        END IF;

        IF OLD.unit_measure IS DISTINCT FROM NEW.unit_measure THEN
            INSERT INTO product_history (product_id, field_name, old_value, new_value, changed_by)
            VALUES (NEW.product_id, 'unit_measure', OLD.unit_measure, NEW.unit_measure, v_user_id);
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_product_history
    BEFORE UPDATE ON product
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_product_history();

-- ====================================================================
-- 26B_TRIGGER_COST.SQL
-- Recalcula custo medio (RF16) automaticamente ao entrar novo lote.
-- ====================================================================

CREATE OR REPLACE FUNCTION fn_trg_refresh_product_cost()
RETURNS TRIGGER AS $$
DECLARE
    v_new_avg DECIMAL(10,2);
    v_old_avg DECIMAL(10,2);
    v_suggested DECIMAL(10,2);
BEGIN
    SELECT avg_cost INTO v_old_avg FROM product WHERE product_id = NEW.product_id;

    v_new_avg := fn_calculate_avg_cost(NEW.product_id);
    v_suggested := fn_suggest_sale_price(NEW.product_id);

    UPDATE product
    SET avg_cost = v_new_avg,
        suggested_price = v_suggested,
        updated_at = NOW()
    WHERE product_id = NEW.product_id;

    IF v_old_avg IS NOT NULL AND v_old_avg <> v_new_avg AND NEW.unit_cost > 0 THEN
        INSERT INTO product_price_history (product_id, old_price, new_price, changed_at)
        VALUES (NEW.product_id, v_old_avg, v_new_avg, NOW());
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_batch_update_cost
    AFTER INSERT ON batch
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_refresh_product_cost();

-- End of trigger definitions. The audit-log trigger function is complete above.

-- ===== FIM 06_triggers.sql =====

-- ===== INICIO 07_views.sql =====
SET search_path TO mottainai, public;

CREATE OR REPLACE VIEW vw_expiring_products AS
SELECT b.batch_id, b.batch_code, p.product_id, p.name AS product,
       s.store_id, s.name AS store, b.expiration_date,
       b.expiration_date - CURRENT_DATE AS days_to_expire,
       i.current_quantity
FROM batch b
JOIN inventory i ON i.batch_id = b.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE b.active AND i.current_quantity > 0
  AND b.deleted_at IS NULL AND i.deleted_at IS NULL
  AND b.expiration_date <= CURRENT_DATE + 15
ORDER BY b.expiration_date;

CREATE OR REPLACE VIEW vw_critical_stock AS
SELECT i.inventory_id, p.product_id, p.name AS product,
       i.store_id, s.name AS store, i.current_quantity, i.minimum_quantity
FROM inventory i
JOIN batch b ON b.batch_id = i.batch_id
JOIN product p ON p.product_id = b.product_id
JOIN retail_store s ON s.store_id = i.store_id
WHERE i.current_quantity < i.minimum_quantity
  AND i.deleted_at IS NULL AND b.deleted_at IS NULL;

CREATE OR REPLACE VIEW vw_current_store_price AS
SELECT spp.store_id, spp.product_id, p.sku, p.barcode, p.name,
       spp.regular_price, spp.valid_from, spp.valid_until, spp.version
FROM store_product_price spp
JOIN product p ON p.product_id = spp.product_id
WHERE spp.active
  AND spp.valid_from <= CURRENT_TIMESTAMP
  AND (spp.valid_until IS NULL OR spp.valid_until > CURRENT_TIMESTAMP)
  AND p.active AND p.deleted_at IS NULL;

CREATE OR REPLACE VIEW vw_active_customer_promotions AS
SELECT p.promotion_id, p.store_id, s.name AS store_name,
       p.name AS promotion_name, p.starts_at, p.ends_at,
       pi.product_id, pr.sku, pr.name AS product_name,
       pi.original_price, pi.promotional_price, pi.discount_percent,
       pi.quantity_available
FROM promotion p
JOIN promotion_item pi ON pi.promotion_id = p.promotion_id
JOIN product pr ON pr.product_id = pi.product_id
JOIN retail_store s ON s.store_id = p.store_id
WHERE p.active AND p.status = 'APPROVED'
  AND p.starts_at <= CURRENT_TIMESTAMP AND p.ends_at > CURRENT_TIMESTAMP
  AND pr.active AND pr.deleted_at IS NULL;

-- ===== FIM 07_views.sql =====

-- ===== INICIO 08_procedures.sql =====
-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 23_PARTITION_FUNCTIONS.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION sp_create_monthly_partitions(
    p_months_back INTEGER DEFAULT 12,
    p_months_ahead INTEGER DEFAULT 6
)
RETURNS VOID AS $$
DECLARE
    v_date DATE;
    v_partition_name TEXT;
    v_schema TEXT := 'mottainai';
    v_tables TEXT[] := ARRAY['inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'];
    v_table TEXT;
BEGIN
    IF p_months_back < 0 OR p_months_ahead < 0 THEN
        RAISE EXCEPTION 'Partition month ranges cannot be negative';
    END IF;

    FOREACH v_table IN ARRAY v_tables
    LOOP
        FOR v_date IN
            SELECT generate_series(
                DATE_TRUNC('month', NOW()) - make_interval(months => p_months_back),
                DATE_TRUNC('month', NOW()) + make_interval(months => p_months_ahead),
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

    RAISE NOTICE 'Monthly partitions created: % months back and % months ahead',
        p_months_back, p_months_ahead;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sp_create_future_partitions()
RETURNS VOID AS $$
    SELECT sp_create_monthly_partitions(12, 6);
$$ LANGUAGE sql;

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

-- ===== FIM 08_procedures.sql =====

-- ===== INICIO 08_partition_maintenance_fix.sql =====
SET search_path TO mottainai, public;

-- Substitui a consulta herdada a pg_partitions (view que nao existe no
-- PostgreSQL) pelo catalogo nativo de heranca/particionamento.
CREATE OR REPLACE PROCEDURE sp_drop_old_partitions(p_months_to_keep INTEGER DEFAULT 12)
LANGUAGE plpgsql AS $$
DECLARE
    v_cutoff_date DATE := date_trunc('month', current_date)
        - make_interval(months => p_months_to_keep);
    v_partition RECORD;
BEGIN
    IF p_months_to_keep < 1 THEN
        RAISE EXCEPTION 'p_months_to_keep must be greater than zero';
    END IF;

    FOR v_partition IN
        SELECT child_ns.nspname AS schema_name, child.relname AS partition_name
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
        WHERE parent_ns.nspname = 'mottainai'
          AND parent.relname IN (
              'inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'
          )
          AND child.relname ~ '_[0-9]{4}_[0-9]{2}$'
          AND to_date(substring(child.relname FROM '([0-9]{4}_[0-9]{2})$'), 'YYYY_MM')
              < v_cutoff_date
    LOOP
        EXECUTE format(
            'DROP TABLE IF EXISTS %I.%I',
            v_partition.schema_name,
            v_partition.partition_name
        );
    END LOOP;
END;
$$;

-- ===== FIM 08_partition_maintenance_fix.sql =====

-- ===== INICIO 09_seed.sql =====
SET search_path TO mottainai, public;

INSERT INTO employee_role (name, description, permission_level) VALUES
    ('Administrator', 'Full system access', 100),
    ('Manager', 'Store management', 80),
    ('Supervisor', 'Team supervision', 60),
    ('Operator', 'Standard operations', 40),
    ('Intern', 'Limited access', 20)
ON CONFLICT (name) DO NOTHING;

INSERT INTO subscription_plan (name, description, price, store_limit, user_limit) VALUES
    ('Free', 'Basic plan for small businesses', 0, 1, 3),
    ('Basic', 'Essential features for growing businesses', 99.90, 5, 10),
    ('Professional', 'Advanced features for medium businesses', 299.90, 20, 50),
    ('Enterprise', 'Full features for large organizations', 999.90, 100, 999)
ON CONFLICT (name) DO NOTHING;

INSERT INTO product_category (name, description) VALUES
    ('Food', 'Food and beverages'),
    ('Beverages', 'Drinks and beverages'),
    ('Cleaning', 'Cleaning supplies'),
    ('Personal Care', 'Personal hygiene products')
ON CONFLICT (name) DO NOTHING;

INSERT INTO tax_profile (
    code, name, description, cfop, icms_cst, icms_rate,
    pis_cst, pis_rate, cofins_cst, cofins_rate
) VALUES (
    'DEFAULT', 'Perfil fiscal padrão', 'Configuração inicial sujeita à validação fiscal',
    '5102', '102', 0, '01', 0, '01', 0
)
ON CONFLICT (code) DO NOTHING;

-- Perfis pedidos no relatorio ficam inativos ate validacao do contador/fiscal.
INSERT INTO tax_profile (code, name, description, icms_cst, icms_rate, active)
VALUES
    ('ISENTO', 'Isento de tributacao', 'Validar CST, CFOP, PIS e COFINS antes de ativar', '40', 0, FALSE),
    ('ALIQ_18', 'Aliquota ICMS 18%', 'Perfil preliminar; exige validacao fiscal', '00', 18, FALSE),
    ('ALIQ_12', 'Aliquota ICMS 12%', 'Perfil preliminar; exige validacao fiscal', '00', 12, FALSE),
    ('SUBST_TRIB', 'Substituicao tributaria', 'Validar regras de ST antes de ativar', '60', 0, FALSE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO schema_version (version, description, type, script, installed_by) VALUES
    ('10', 'Split physical operational database', 'SQL', 'database/operational', CURRENT_USER)
ON CONFLICT (version) DO NOTHING;

-- ===== FIM 09_seed.sql =====

-- ===== INICIO 10_tests.sql =====
SET search_path TO mottainai, public;

DO $$
DECLARE
    v_missing TEXT[];
BEGIN
    SELECT array_agg(required.name)
    INTO v_missing
    FROM (VALUES
        ('product'), ('inventory'), ('sales_transaction'),
        ('store_product_price'), ('inventory_count'),
        ('password_reset_token'), ('event_queue')
    ) AS required(name)
    WHERE to_regclass('mottainai.' || required.name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Operational installation missing tables: %', v_missing;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'mottainai' AND table_name LIKE 'ai_%'
    ) THEN
        RAISE EXCEPTION 'AI tables must not be installed in the operational database';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'base_price'
    ) THEN
        RAISE EXCEPTION 'Column product.base_price required by the API is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'app_user'
          AND column_name = 'cpf'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Column app_user.cpf is missing or nullable';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace namespace ON namespace.oid = parent.relnamespace
        WHERE namespace.nspname = 'mottainai'
          AND parent.relname IN (
              'purchase_order', 'inventory_movement',
              'sales_transaction', 'audit_log'
          )
    ) < 76 THEN
        RAISE EXCEPTION 'Monthly operational partitions were not created';
    END IF;
END;
$$;

-- ===== FIM 10_tests.sql =====

-- ===== INICIO 20_security_hardening.sql =====
-- ====================================================================
-- PROFESSIONAL SECURITY HARDENING
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

-- The application role is intentionally NOLOGIN. The real Render login must
-- be granted membership by a database administrator.
DO $$
DECLARE
    v_is_superuser BOOLEAN;
    v_has_replication BOOLEAN;
    v_bypasses_rls BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_api') THEN
        CREATE ROLE mottainai_api
            NOLOGIN
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT;
    END IF;

    SELECT rolsuper, rolreplication, rolbypassrls
    INTO v_is_superuser, v_has_replication, v_bypasses_rls
    FROM pg_roles
    WHERE rolname = 'mottainai_api';

    IF v_is_superuser OR v_has_replication OR v_bypasses_rls THEN
        RAISE EXCEPTION
            'Role mottainai_api has a privileged attribute (SUPERUSER, REPLICATION or BYPASSRLS). A PostgreSQL superuser must remove it before this migration can continue.';
    END IF;

    ALTER ROLE mottainai_api
        NOLOGIN
        NOCREATEDB
        NOCREATEROLE
        NOINHERIT;

    ALTER ROLE mottainai_api SET row_security = ON;
    ALTER ROLE mottainai_api SET statement_timeout = '30s';
    ALTER ROLE mottainai_api SET lock_timeout = '5s';
    ALTER ROLE mottainai_api SET idle_in_transaction_session_timeout = '30s';
END;
$$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA mottainai FROM PUBLIC;
GRANT USAGE ON SCHEMA mottainai TO mottainai_api;

DO $$
BEGIN
    EXECUTE format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO mottainai_api', current_database());
END;
$$;

-- Prevent future objects from accidentally becoming public.
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA mottainai
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Initial-password and employee-invitation state.
ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS password_set BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN app_user.password_set IS
    'True after the employee has securely defined the initial password.';

ALTER TABLE password_reset_token
    ADD COLUMN IF NOT EXISTS token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET';

ALTER TABLE password_reset_token
    DROP CONSTRAINT IF EXISTS ck_password_reset_token_type;

ALTER TABLE password_reset_token
    ADD CONSTRAINT ck_password_reset_token_type
    CHECK (token_type IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION'));

CREATE INDEX IF NOT EXISTS idx_password_reset_token_user_type_active
    ON password_reset_token (user_id, token_type, created_at DESC)
    WHERE used_at IS NULL;

COMMENT ON COLUMN password_reset_token.token_type IS
    'Distinguishes password recovery from an employee invitation.';

-- Only token hashes are persisted. Logout and password changes revoke rows;
-- sessions are retained for investigation and never physically deleted by API.
CREATE TABLE IF NOT EXISTS staff_session (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    refresh_token_hash TEXT NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoked_reason VARCHAR(80),
    ip_address INET,
    user_agent VARCHAR(500),
    CONSTRAINT fk_staff_session_user
        FOREIGN KEY (user_id)
        REFERENCES app_user(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_staff_session_refresh_token_hash
        UNIQUE (refresh_token_hash),
    CONSTRAINT ck_staff_session_expiration
        CHECK (refresh_expires_at > created_at),
    CONSTRAINT ck_staff_session_last_used
        CHECK (last_used_at IS NULL OR last_used_at >= created_at),
    CONSTRAINT ck_staff_session_revoked
        CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT ck_staff_session_revoked_reason
        CHECK (revoked_at IS NOT NULL OR revoked_reason IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_staff_session_user_active
    ON staff_session (user_id, refresh_expires_at)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE staff_session IS
    'Auditable employee sessions. Contains only refresh-token hashes.';

-- The former setter accepted arbitrary IDs and persisted them for the whole
-- connection. It remains for owner compatibility but is unavailable to API.
REVOKE ALL ON FUNCTION fn_set_session_context(INTEGER, INTEGER, INTEGER)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_set_session_context(INTEGER, INTEGER, INTEGER)
    FROM mottainai_api;

-- PostgreSQL 15 parameter ACLs prevent the API from forging tenant GUCs with
-- SET or set_config(). Only the SECURITY DEFINER bootstrap functions may set
-- these transaction-local values.
REVOKE SET ON PARAMETER app.current_user_id FROM PUBLIC;
REVOKE SET ON PARAMETER app.current_company_id FROM PUBLIC;
REVOKE SET ON PARAMETER app.current_store_id FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM mottainai_api;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context(
    p_identity TEXT,
    p_lookup TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_lookup NOT IN ('CPF', 'EMAIL', 'INVITED_CPF') THEN
        RETURN FALSE;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM app_user u
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL
      AND s.active
      AND c.active
      AND r.active
      AND (
          (p_lookup = 'CPF' AND u.cpf = p_identity AND u.active AND e.active)
          OR
          (p_lookup = 'EMAIL' AND lower(u.email) = lower(p_identity) AND u.active AND e.active)
          OR
          (p_lookup = 'INVITED_CPF' AND u.cpf = p_identity
              AND NOT u.active AND NOT e.active AND NOT u.password_set)
      );

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context_by_token(
    p_token_hash TEXT,
    p_token_type VARCHAR
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    IF p_token_type NOT IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION') THEN
        RETURN NULL;
    END IF;

    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM password_reset_token t
    JOIN app_user u ON u.user_id = t.user_id
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE t.token_hash = p_token_hash
      AND t.token_type = p_token_type
      AND t.used_at IS NULL
      AND t.expires_at > CURRENT_TIMESTAMP
      AND u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL
      AND s.active
      AND c.active
      AND r.active
      AND (
          (p_token_type = 'PASSWORD_RESET' AND u.active AND e.active)
          OR
          (p_token_type = 'EMPLOYEE_INVITATION'
              AND NOT u.active AND NOT e.active AND NOT u.password_set)
      );

    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_staff_context_by_session(
    p_session_id UUID,
    p_refresh_token_hash TEXT
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
BEGIN
    SELECT u.user_id, s.company_id, s.store_id
    INTO v_user_id, v_company_id, v_store_id
    FROM staff_session ss
    JOIN app_user u ON u.user_id = ss.user_id
    JOIN employee e ON e.employee_id = u.employee_id
    JOIN retail_store s ON s.store_id = e.store_id
    JOIN company c ON c.company_id = s.company_id
    JOIN employee_role r ON r.role_id = e.role_id
    WHERE ss.session_id = p_session_id
      AND ss.refresh_token_hash = p_refresh_token_hash
      AND ss.revoked_at IS NULL
      AND ss.refresh_expires_at > CURRENT_TIMESTAMP
      AND u.active
      AND e.active
      AND s.active
      AND c.active
      AND r.active
      AND u.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND s.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND r.deleted_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('app.current_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('app.current_company_id', v_company_id::TEXT, TRUE);
    PERFORM set_config('app.current_store_id', v_store_id::TEXT, TRUE);
    RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_staff_context_by_token(TEXT, VARCHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_staff_context_by_session(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context(TEXT, TEXT) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context_by_token(TEXT, VARCHAR) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_staff_context_by_session(UUID, TEXT) TO mottainai_api;

-- Reusable tenant predicates. SECURITY DEFINER avoids recursive RLS checks;
-- fixed search paths prevent object-shadowing attacks.
CREATE OR REPLACE FUNCTION fn_current_user_is_company_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_user u
        JOIN employee e ON e.employee_id = u.employee_id
        JOIN employee_role r ON r.role_id = e.role_id
        JOIN retail_store s ON s.store_id = e.store_id
        WHERE u.user_id = fn_get_current_user_id()
          AND s.company_id = fn_get_current_company_id()
          AND upper(r.name) = 'ADMINISTRATOR'
          AND u.active AND e.active AND r.active AND s.active
          AND u.deleted_at IS NULL
          AND e.deleted_at IS NULL
          AND r.deleted_at IS NULL
          AND s.deleted_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION fn_store_belongs_current_company(p_store_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM retail_store s
        WHERE s.store_id = p_store_id
          AND s.company_id = fn_get_current_company_id()
          AND s.active
          AND s.deleted_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION fn_can_access_store(p_store_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT p_store_id = fn_get_current_store_id()
        OR (
            fn_current_user_is_company_admin()
            AND fn_store_belongs_current_company(p_store_id)
        );
$$;

CREATE OR REPLACE FUNCTION fn_can_access_user(p_user_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
    SELECT p_user_id = fn_get_current_user_id()
        OR (
            fn_current_user_is_company_admin()
            AND EXISTS (
                SELECT 1
                FROM app_user u
                JOIN employee e ON e.employee_id = u.employee_id
                WHERE u.user_id = p_user_id
                  AND fn_store_belongs_current_company(e.store_id)
            )
        );
$$;

REVOKE ALL ON FUNCTION fn_current_user_is_company_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_store_belongs_current_company(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_access_store(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_can_access_user(INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_get_current_user_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_get_current_company_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_get_current_store_id() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_current_user_is_company_admin() TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_store_belongs_current_company(INTEGER) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_can_access_store(INTEGER) TO mottainai_api;
GRANT EXECUTE ON FUNCTION fn_can_access_user(INTEGER) TO mottainai_api;

-- Replace permissive legacy policies with explicit API policies and checks.
DROP POLICY IF EXISTS company_policy ON company;
CREATE POLICY company_policy ON company FOR ALL TO mottainai_api
    USING (company_id = fn_get_current_company_id())
    WITH CHECK (company_id = fn_get_current_company_id());

DROP POLICY IF EXISTS store_policy ON retail_store;
CREATE POLICY store_policy ON retail_store FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS employee_policy ON employee;
CREATE POLICY employee_policy ON employee FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS inventory_policy ON inventory;
CREATE POLICY inventory_policy ON inventory FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS sales_policy ON sales_transaction;
CREATE POLICY sales_policy ON sales_transaction FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DROP POLICY IF EXISTS purchase_order_policy ON purchase_order;
CREATE POLICY purchase_order_policy ON purchase_order FOR ALL TO mottainai_api
    USING (fn_can_access_store(store_id))
    WITH CHECK (fn_can_access_store(store_id));

DO $$
DECLARE
    v_item RECORD;
BEGIN
    FOR v_item IN
        SELECT * FROM (VALUES
            ('pos_terminal', 'store_id'),
            ('alert', 'store_id'),
            ('promotion', 'store_id'),
            ('customer_geofence', 'store_id'),
            ('donation', 'store_id'),
            ('disposal', 'store_id'),
            ('replenishment_pre_list', 'store_id'),
            ('store_product_price', 'store_id'),
            ('inventory_count', 'store_id'),
            ('inventory_movement', 'store_id')
        ) AS policy_table(table_name, store_column)
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_item.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I',
            v_item.table_name || '_tenant_policy', v_item.table_name);
        EXECUTE format(
            'CREATE POLICY %I ON %I FOR ALL TO mottainai_api '
            || 'USING (fn_can_access_store(%I)) '
            || 'WITH CHECK (fn_can_access_store(%I))',
            v_item.table_name || '_tenant_policy',
            v_item.table_name,
            v_item.store_column,
            v_item.store_column
        );
    END LOOP;
END;
$$;

ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_user_tenant_policy ON app_user;
CREATE POLICY app_user_tenant_policy ON app_user FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE password_reset_token ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS password_reset_token_policy ON password_reset_token;
CREATE POLICY password_reset_token_policy ON password_reset_token FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE staff_session ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_session_policy ON staff_session;
CREATE POLICY staff_session_policy ON staff_session FOR ALL TO mottainai_api
    USING (fn_can_access_user(user_id))
    WITH CHECK (fn_can_access_user(user_id));

ALTER TABLE inventory_count_item ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventory_count_item_policy ON inventory_count_item;
CREATE POLICY inventory_count_item_policy ON inventory_count_item FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1 FROM inventory_count count_header
        WHERE count_header.inventory_count_id = inventory_count_item.inventory_count_id
          AND fn_can_access_store(count_header.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM inventory_count count_header
        WHERE count_header.inventory_count_id = inventory_count_item.inventory_count_id
          AND fn_can_access_store(count_header.store_id)
    ));

ALTER TABLE batch ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS batch_tenant_policy ON batch;
CREATE POLICY batch_tenant_policy ON batch FOR ALL TO mottainai_api
    USING (
        EXISTS (
            SELECT 1 FROM inventory stock
            WHERE stock.batch_id = batch.batch_id
              AND fn_can_access_store(stock.store_id)
        )
        OR EXISTS (
            SELECT 1
            FROM receiving_item received_item
            JOIN receiving receiving_header
              ON receiving_header.receiving_id = received_item.receiving_id
            JOIN purchase_order purchase
              ON purchase.purchase_order_id = receiving_header.purchase_order_id
             AND purchase.order_date = receiving_header.order_date
            WHERE received_item.receiving_item_id = batch.receiving_item_id
              AND fn_can_access_store(purchase.store_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM inventory stock
            WHERE stock.batch_id = batch.batch_id
              AND fn_can_access_store(stock.store_id)
        )
        OR EXISTS (
            SELECT 1
            FROM receiving_item received_item
            JOIN receiving receiving_header
              ON receiving_header.receiving_id = received_item.receiving_id
            JOIN purchase_order purchase
              ON purchase.purchase_order_id = receiving_header.purchase_order_id
             AND purchase.order_date = receiving_header.order_date
            WHERE received_item.receiving_item_id = batch.receiving_item_id
              AND fn_can_access_store(purchase.store_id)
        )
    );

ALTER TABLE pos_shift ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_shift_tenant_policy ON pos_shift;
CREATE POLICY pos_shift_tenant_policy ON pos_shift FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1 FROM pos_terminal terminal
        WHERE terminal.terminal_id = pos_shift.terminal_id
          AND fn_can_access_store(terminal.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM pos_terminal terminal
        WHERE terminal.terminal_id = pos_shift.terminal_id
          AND fn_can_access_store(terminal.store_id)
    ));

ALTER TABLE pos_cash_movement ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_cash_movement_tenant_policy ON pos_cash_movement;
CREATE POLICY pos_cash_movement_tenant_policy ON pos_cash_movement FOR ALL TO mottainai_api
    USING (EXISTS (
        SELECT 1
        FROM pos_shift shift_record
        JOIN pos_terminal terminal ON terminal.terminal_id = shift_record.terminal_id
        WHERE shift_record.shift_id = pos_cash_movement.shift_id
          AND fn_can_access_store(terminal.store_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1
        FROM pos_shift shift_record
        JOIN pos_terminal terminal ON terminal.terminal_id = shift_record.terminal_id
        WHERE shift_record.shift_id = pos_cash_movement.shift_id
          AND fn_can_access_store(terminal.store_id)
    ));

ALTER TABLE transfer ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS transfer_tenant_policy ON transfer;
CREATE POLICY transfer_tenant_policy ON transfer FOR ALL TO mottainai_api
    USING (fn_can_access_store(source_store_id)
        OR fn_can_access_store(destination_store_id))
    WITH CHECK (fn_can_access_store(source_store_id)
        AND fn_store_belongs_current_company(destination_store_id));

-- Child-table policies follow their tenant-scoped parent.
DO $$
DECLARE
    v_policy RECORD;
BEGIN
    FOR v_policy IN
        SELECT * FROM (VALUES
            ('purchase_order_item', 'purchase_order_item_policy',
             'EXISTS (SELECT 1 FROM purchase_order parent WHERE parent.purchase_order_id = purchase_order_item.purchase_order_id AND parent.order_date = purchase_order_item.order_date AND fn_can_access_store(parent.store_id))'),
            ('receiving', 'receiving_policy',
             'EXISTS (SELECT 1 FROM purchase_order parent WHERE parent.purchase_order_id = receiving.purchase_order_id AND parent.order_date = receiving.order_date AND fn_can_access_store(parent.store_id))'),
            ('receiving_item', 'receiving_item_policy',
             'EXISTS (SELECT 1 FROM receiving parent JOIN purchase_order po ON po.purchase_order_id = parent.purchase_order_id AND po.order_date = parent.order_date WHERE parent.receiving_id = receiving_item.receiving_id AND fn_can_access_store(po.store_id))'),
            ('sale_item', 'sale_item_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = sale_item.sale_id AND parent.sale_date = sale_item.sale_date AND fn_can_access_store(parent.store_id))'),
            ('sale_payment', 'sale_payment_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = sale_payment.sale_id AND parent.sale_date = sale_payment.sale_date AND fn_can_access_store(parent.store_id))'),
            ('fiscal_document', 'fiscal_document_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = fiscal_document.sale_id AND parent.sale_date = fiscal_document.sale_date AND fn_can_access_store(parent.store_id))'),
            ('pos_cancel_request', 'pos_cancel_request_policy',
             'EXISTS (SELECT 1 FROM sales_transaction parent WHERE parent.sale_id = pos_cancel_request.sale_id AND parent.sale_date = pos_cancel_request.sale_date AND fn_can_access_store(parent.store_id))'),
            ('promotion_item', 'promotion_item_policy',
             'EXISTS (SELECT 1 FROM promotion parent WHERE parent.promotion_id = promotion_item.promotion_id AND fn_can_access_store(parent.store_id))'),
            ('transfer_item', 'transfer_item_policy',
             'EXISTS (SELECT 1 FROM transfer parent WHERE parent.transfer_id = transfer_item.transfer_id AND (fn_can_access_store(parent.source_store_id) OR fn_can_access_store(parent.destination_store_id)))'),
            ('donation_item', 'donation_item_policy',
             'EXISTS (SELECT 1 FROM donation parent WHERE parent.donation_id = donation_item.donation_id AND fn_can_access_store(parent.store_id))'),
            ('disposal_item', 'disposal_item_policy',
             'EXISTS (SELECT 1 FROM disposal parent WHERE parent.disposal_id = disposal_item.disposal_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_pre_list_item', 'replenishment_pre_list_item_policy',
             'EXISTS (SELECT 1 FROM replenishment_pre_list parent WHERE parent.pre_list_id = replenishment_pre_list_item.pre_list_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_execution', 'replenishment_execution_policy',
             'EXISTS (SELECT 1 FROM replenishment_pre_list parent WHERE parent.pre_list_id = replenishment_execution.pre_list_id AND fn_can_access_store(parent.store_id))'),
            ('replenishment_execution_item', 'replenishment_execution_item_policy',
             'EXISTS (SELECT 1 FROM replenishment_execution execution JOIN replenishment_pre_list parent ON parent.pre_list_id = execution.pre_list_id WHERE execution.execution_id = replenishment_execution_item.execution_id AND fn_can_access_store(parent.store_id))')
        ) AS policy_data(table_name, policy_name, predicate)
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_policy.table_name);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I',
            v_policy.policy_name, v_policy.table_name);
        EXECUTE format(
            'CREATE POLICY %I ON %I FOR ALL TO mottainai_api '
            || 'USING (%s) WITH CHECK (%s)',
            v_policy.policy_name,
            v_policy.table_name,
            v_policy.predicate,
            v_policy.predicate
        );
    END LOOP;
END;
$$;

-- Views must evaluate RLS as the caller, never as their owner.
ALTER VIEW vw_expiring_products SET (security_invoker = TRUE);
ALTER VIEW vw_critical_stock SET (security_invoker = TRUE);
ALTER VIEW vw_current_store_price SET (security_invoker = TRUE);
ALTER VIEW vw_active_customer_promotions SET (security_invoker = TRUE);

-- Tenant-aware and tamper-resistant audit records.
ALTER TABLE audit_log
    ADD COLUMN IF NOT EXISTS company_id INTEGER,
    ADD COLUMN IF NOT EXISTS store_id INTEGER,
    ADD COLUMN IF NOT EXISTS client_ip INET,
    ADD COLUMN IF NOT EXISTS application_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS transaction_id BIGINT;

UPDATE audit_log audit
SET company_id = store.company_id,
    store_id = employee.store_id
FROM app_user app
JOIN employee ON employee.employee_id = app.employee_id
JOIN retail_store store ON store.store_id = employee.store_id
WHERE audit.user_id = app.user_id
  AND audit.company_id IS NULL;

CREATE OR REPLACE FUNCTION fn_sanitize_audit_json(p_data JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_data IS NULL THEN NULL
        ELSE p_data
            - 'password_hash'
            - 'token_hash'
            - 'refresh_token_hash'
            - 'recovery_token_hash'
            - 'cpf'
    END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_user_id INTEGER := fn_get_current_user_id();
    v_company_id INTEGER := fn_get_current_company_id();
    v_store_id INTEGER := fn_get_current_store_id();
    v_record_id TEXT;
BEGIN
    IF pg_has_role(session_user, 'mottainai_api', 'MEMBER')
       AND NOT EXISTS (
           SELECT 1 FROM pg_roles
           WHERE rolname = session_user
             AND rolsuper
       )
       AND (v_user_id IS NULL OR v_company_id IS NULL) THEN
        RAISE EXCEPTION 'A validated tenant context is required for audited API writes';
    END IF;

    v_record_id := COALESCE(
        to_jsonb(NEW)->>TG_ARGV[0],
        to_jsonb(OLD)->>TG_ARGV[0],
        '0'
    );

    INSERT INTO audit_log (
        table_affected,
        operation,
        record_id,
        user_id,
        old_data,
        new_data,
        operation_date,
        company_id,
        store_id,
        client_ip,
        application_name,
        transaction_id
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP::audit_operation,
        v_record_id,
        v_user_id,
        fn_sanitize_audit_json(CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END),
        fn_sanitize_audit_json(CASE WHEN TG_OP IN ('UPDATE', 'INSERT') THEN to_jsonb(NEW) END),
        CURRENT_TIMESTAMP,
        v_company_id,
        v_store_id,
        inet_client_addr(),
        current_setting('application_name', TRUE),
        txid_current()
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION fn_sanitize_audit_json(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_trg_audit_log() FROM PUBLIC;

DO $$
DECLARE
    v_trigger RECORD;
BEGIN
    FOR v_trigger IN
        SELECT * FROM (VALUES
            ('employee', 'employee_id'),
            ('app_user', 'user_id'),
            ('purchase_order', 'purchase_order_id'),
            ('sales_transaction', 'sale_id'),
            ('inventory_movement', 'movement_id'),
            ('password_reset_token', 'recovery_token_id'),
            ('staff_session', 'session_id')
        ) AS audit_target(table_name, id_column)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I',
            'trg_audit_' || v_trigger.table_name, v_trigger.table_name);
        EXECUTE format(
            'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I '
            || 'FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log(%L)',
            'trg_audit_' || v_trigger.table_name,
            v_trigger.table_name,
            v_trigger.id_column
        );
    END LOOP;
END;
$$;

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_log_read_policy ON audit_log;
CREATE POLICY audit_log_read_policy ON audit_log FOR SELECT TO mottainai_api
    USING (company_id = fn_get_current_company_id());

-- Least privilege for the API group role. DDL, partition maintenance, direct
-- audit writes, physical deletes, logs and archives remain owner-only.
REVOKE ALL ON ALL TABLES IN SCHEMA mottainai FROM mottainai_api;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA mottainai FROM mottainai_api;

GRANT SELECT ON
    subscription_plan,
    company,
    retail_store,
    employee_role,
    product_category,
    tax_profile,
    batch,
    pos_terminal,
    pos_shift,
    vw_expiring_products,
    vw_critical_stock,
    vw_current_store_price,
    vw_active_customer_promotions
TO mottainai_api;

-- Product becomes writable only when the company-ownership migration from
-- PR #22 is present. This prevents exposing the former global catalog.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'company_id'
          AND is_nullable = 'NO'
    ) AND EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'mottainai'
          AND tablename = 'product'
          AND policyname = 'product_policy'
    ) THEN
        DROP POLICY product_policy ON product;
        CREATE POLICY product_policy ON product FOR ALL TO mottainai_api
            USING (company_id = fn_get_current_company_id())
            WITH CHECK (company_id = fn_get_current_company_id());
        GRANT SELECT, INSERT, UPDATE ON product TO mottainai_api;
        GRANT USAGE, SELECT ON SEQUENCE product_product_id_seq TO mottainai_api;
    ELSE
        RAISE NOTICE 'Product API grants skipped until product company ownership is installed';
    END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE ON
    employee,
    app_user,
    password_reset_token,
    staff_session,
    inventory,
    inventory_movement,
    inventory_count,
    inventory_count_item,
    store_product_price,
    purchase_order,
    purchase_order_item,
    receiving,
    receiving_item,
    sales_transaction,
    sale_item,
    sale_payment,
    fiscal_document,
    pos_cash_movement,
    pos_cancel_request,
    alert,
    promotion,
    promotion_item,
    transfer,
    transfer_item,
    donation,
    donation_item,
    disposal,
    disposal_item,
    replenishment_pre_list,
    replenishment_pre_list_item,
    replenishment_execution,
    replenishment_execution_item
TO mottainai_api;

GRANT SELECT ON audit_log TO mottainai_api;

DO $$
DECLARE
    v_table_name TEXT;
    v_sequence_name TEXT;
BEGIN
    FOREACH v_table_name IN ARRAY ARRAY[
        'employee', 'app_user', 'password_reset_token', 'inventory',
        'inventory_movement', 'inventory_count', 'inventory_count_item',
        'store_product_price', 'purchase_order', 'purchase_order_item',
        'receiving', 'receiving_item', 'sales_transaction', 'sale_item',
        'sale_payment', 'fiscal_document', 'pos_cash_movement',
        'pos_cancel_request', 'alert', 'promotion', 'promotion_item',
        'transfer', 'transfer_item', 'donation', 'donation_item',
        'disposal', 'disposal_item', 'replenishment_pre_list',
        'replenishment_pre_list_item', 'replenishment_execution',
        'replenishment_execution_item'
    ] LOOP
        SELECT pg_get_serial_sequence('mottainai.' || v_table_name, column_name)
        INTO v_sequence_name
        FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = v_table_name
          AND is_identity = 'YES'
        ORDER BY ordinal_position
        LIMIT 1;

        IF v_sequence_name IS NOT NULL THEN
            EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO mottainai_api',
                v_sequence_name);
        END IF;
    END LOOP;

END;
$$;

-- UUID staff_session has no sequence. The dynamic block supports deployments
-- where identity sequence names differ.

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '20',
    'Professional tenant, session, privilege and audit hardening',
    'SQL',
    '20_security_hardening.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;

-- ===== FIM 20_security_hardening.sql =====

-- ===== INICIO 21_security_hardening_tests.sql =====
-- ====================================================================
-- PROFESSIONAL SECURITY HARDENING - STRUCTURAL TESTS
-- PostgreSQL 15+
-- ====================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_count INTEGER;
    v_role RECORD;
BEGIN
    SELECT rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication,
           rolbypassrls
    INTO v_role
    FROM pg_roles
    WHERE rolname = 'mottainai_api';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'mottainai_api role is missing';
    END IF;

    IF v_role.rolsuper OR v_role.rolcreaterole OR v_role.rolcreatedb
       OR v_role.rolcanlogin OR v_role.rolreplication OR v_role.rolbypassrls THEN
        RAISE EXCEPTION 'mottainai_api has forbidden administrative attributes';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'app_user'
      AND column_name = 'password_set'
      AND is_nullable = 'NO';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'app_user.password_set is missing or nullable';
    END IF;

    IF to_regclass('mottainai.staff_session') IS NULL THEN
        RAISE EXCEPTION 'staff_session table is missing';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'mottainai'
      AND procedure.proname IN (
          'fn_bootstrap_staff_context',
          'fn_bootstrap_staff_context_by_token',
          'fn_bootstrap_staff_context_by_session'
      )
      AND procedure.prosecdef
      AND 'search_path=mottainai, pg_temp' = ANY(procedure.proconfig);

    IF v_count <> 3 THEN
        RAISE EXCEPTION 'Bootstrap functions must be SECURITY DEFINER with a fixed search_path';
    END IF;

    IF has_function_privilege(
        'mottainai_api',
        'mottainai.fn_set_session_context(integer,integer,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'mottainai_api must not execute fn_set_session_context';
    END IF;

    IF has_parameter_privilege(
        'mottainai_api', 'app.current_user_id', 'SET'
    ) OR has_parameter_privilege(
        'mottainai_api', 'app.current_company_id', 'SET'
    ) OR has_parameter_privilege(
        'mottainai_api', 'app.current_store_id', 'SET'
    ) THEN
        RAISE EXCEPTION 'mottainai_api must not set tenant context parameters directly';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = 'mottainai'
      AND relation.relname IN (
          'company', 'retail_store', 'employee', 'app_user', 'inventory',
          'inventory_movement', 'purchase_order', 'sales_transaction',
          'staff_session', 'password_reset_token', 'audit_log'
      )
      AND relation.relrowsecurity;

    IF v_count <> 11 THEN
        RAISE EXCEPTION 'RLS is not enabled on every critical tenant table';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_policies
    WHERE schemaname = 'mottainai'
      AND tablename IN (
          'company', 'retail_store', 'employee', 'app_user', 'inventory',
          'inventory_movement', 'purchase_order', 'sales_transaction',
          'staff_session', 'password_reset_token', 'audit_log'
      )
      AND 'mottainai_api' = ANY(roles);

    IF v_count < 11 THEN
        RAISE EXCEPTION 'Tenant policies are not explicitly assigned to mottainai_api';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM pg_class view_relation
    JOIN pg_namespace namespace ON namespace.oid = view_relation.relnamespace
    WHERE namespace.nspname = 'mottainai'
      AND view_relation.relname IN (
          'vw_expiring_products',
          'vw_critical_stock',
          'vw_current_store_price',
          'vw_active_customer_promotions'
      )
      AND 'security_invoker=true' = ANY(view_relation.reloptions);

    IF v_count <> 4 THEN
        RAISE EXCEPTION 'Every API view must use security_invoker=true';
    END IF;

    IF has_table_privilege('mottainai_api', 'mottainai.audit_log', 'INSERT')
       OR has_table_privilege('mottainai_api', 'mottainai.audit_log', 'UPDATE')
       OR has_table_privilege('mottainai_api', 'mottainai.audit_log', 'DELETE') THEN
        RAISE EXCEPTION 'Audit log must be immutable to mottainai_api';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'audit_log'
      AND column_name IN (
          'company_id', 'store_id', 'client_ip',
          'application_name', 'transaction_id'
      );

    IF v_count <> 5 THEN
        RAISE EXCEPTION 'Tenant-aware audit metadata is incomplete';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'product'
          AND column_name = 'company_id'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'mottainai'
              AND tablename = 'product'
              AND policyname = 'product_policy'
              AND 'mottainai_api' = ANY(roles)
        ) OR NOT has_table_privilege(
            'mottainai_api', 'mottainai.product', 'INSERT'
        ) THEN
            RAISE EXCEPTION 'Company-owned product is not protected and granted to mottainai_api';
        END IF;
    END IF;

    RAISE NOTICE 'Professional security hardening tests passed';
END;
$$;

-- ===== FIM 21_security_hardening_tests.sql =====

-- ===== INICIO 22_sensitive_data_contract.sql =====
-- ============================================================================
-- SENSITIVE DATA CONTRACT
-- PostgreSQL 15+
--
-- The operational database stores only values already treated by the source
-- backend. SHA-256 tokens are prefixed by their semantic type. Passwords and
-- low-entropy recovery codes use BCrypt. The database never receives keys and
-- must not be used as an encryption/decryption service.
-- ============================================================================

SET search_path TO mottainai, public;

CREATE OR REPLACE FUNCTION fn_is_sha256_token(p_value TEXT, p_prefix TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT p_value ~ ('^' || p_prefix || '_SHA256_[A-Fa-f0-9]{64}$');
$$;

CREATE OR REPLACE FUNCTION fn_is_bcrypt_hash(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT p_value ~ '^\$2[aby]\$[0-3][0-9]\$[./A-Za-z0-9]{53}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_email(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT fn_is_sha256_token(p_value, 'EMAIL')
        OR p_value ~ '^EMAIL_[A-Z]+_[0-9]+$'
        OR p_value ~ '^USER_[0-9]+$'
        OR p_value ~ '^[A-Za-z0-9._%+-]*\*{3}@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
$$;

CREATE OR REPLACE FUNCTION fn_is_protected_phone(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT fn_is_sha256_token(p_value, 'PHONE')
        OR p_value ~ '^PHONE_[A-Z]+_[0-9]+$'
        OR p_value ~ '^\([0-9]{2}\) 9\*{4}-[0-9]{4}$';
$$;

REVOKE ALL ON FUNCTION fn_is_sha256_token(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_bcrypt_hash(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_protected_phone(TEXT) FROM PUBLIC;

-- Remove plaintext-oriented validation before widening protected columns.
ALTER TABLE company DROP CONSTRAINT IF EXISTS company_email_check;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS retail_store_email_check;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS supplier_email_check;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_cpf_check;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_cpf_key;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS employee_email_check;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS app_user_email_check;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS app_user_email_key;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_cpf_valid;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_cpf;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_cpf_check;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_cpf_key;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_email_check;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS customer_external_auth_uid_key;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS customer_auth_login_email_check;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS customer_auth_login_email_key;
ALTER TABLE sales_transaction DROP CONSTRAINT IF EXISTS sales_transaction_customer_document_check;
ALTER TABLE company DROP CONSTRAINT IF EXISTS ck_company_email_protected;
ALTER TABLE company DROP CONSTRAINT IF EXISTS ck_company_phone_protected;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS ck_store_email_protected;
ALTER TABLE retail_store DROP CONSTRAINT IF EXISTS ck_store_phone_protected;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS ck_supplier_email_protected;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS ck_supplier_phone_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS uq_employee_cpf_token;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_name_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_cpf_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_email_protected;
ALTER TABLE employee DROP CONSTRAINT IF EXISTS ck_employee_phone_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_email_token;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS uq_app_user_cpf_token;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_email_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_cpf_protected;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_password_bcrypt;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS uq_customer_cpf_token;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS uq_customer_external_auth_token;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_name_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_cpf_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_email_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_phone_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_external_auth_protected;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_birth_year_minimized;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_address_not_linked;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS ck_customer_address_token_protected;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS uq_customer_auth_login_token;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_login_protected;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_password_bcrypt;
ALTER TABLE customer_auth DROP CONSTRAINT IF EXISTS ck_customer_auth_recovery_bcrypt;
ALTER TABLE sales_transaction DROP CONSTRAINT IF EXISTS ck_sales_customer_document_protected;
ALTER TABLE staff_session DROP CONSTRAINT IF EXISTS ck_staff_session_refresh_sha256;
ALTER TABLE password_reset_token DROP CONSTRAINT IF EXISTS ck_password_reset_hash_algorithm;

DROP TRIGGER IF EXISTS trg_sync_app_user_cpf ON app_user;
DROP TRIGGER IF EXISTS trg_propagate_employee_cpf ON employee;

ALTER TABLE company ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE retail_store ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE supplier ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE employee ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf);
ALTER TABLE employee ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE app_user ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf);
ALTER TABLE customer ALTER COLUMN cpf TYPE VARCHAR(80) USING btrim(cpf);
ALTER TABLE customer ALTER COLUMN phone TYPE VARCHAR(80);
ALTER TABLE customer_auth ALTER COLUMN login_email TYPE VARCHAR(150);
ALTER TABLE sales_transaction
    ALTER COLUMN customer_document TYPE VARCHAR(80) USING btrim(customer_document);

-- Existing clear values are irreversibly converted once. New writes must
-- arrive protected by the backend before reaching PostgreSQL.
UPDATE company
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE NOT fn_is_protected_email(email);

UPDATE company
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE retail_store
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_protected_email(email);

UPDATE retail_store
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE supplier
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_protected_email(email);

UPDATE supplier
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE employee
SET name = 'EMP_SHA256_' || upper(encode(digest(btrim(name), 'sha256'), 'hex'))
WHERE name !~ '^EMP_[0-9]+$'
  AND NOT fn_is_sha256_token(name, 'EMP');

UPDATE employee
SET cpf = 'CPF_SHA256_' || upper(encode(digest(regexp_replace(cpf, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE cpf !~ '^CPF_TKN_[A-Fa-f0-9]{6}$'
  AND NOT fn_is_sha256_token(cpf, 'CPF');

UPDATE employee
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_protected_email(email);

UPDATE employee
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_protected_phone(phone);

UPDATE app_user app
SET cpf = employee.cpf
FROM employee
WHERE employee.employee_id = app.employee_id
  AND app.cpf IS DISTINCT FROM employee.cpf;

UPDATE app_user
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE NOT fn_is_protected_email(email);

ALTER TABLE customer
    ADD COLUMN IF NOT EXISTS birth_year SMALLINT,
    ADD COLUMN IF NOT EXISTS address_token VARCHAR(80),
    ADD COLUMN IF NOT EXISTS data_protection_version SMALLINT NOT NULL DEFAULT 1;

UPDATE customer
SET full_name = 'CUS_SHA256_' || upper(encode(digest(btrim(full_name), 'sha256'), 'hex'))
WHERE NOT fn_is_sha256_token(full_name, 'CUS');

UPDATE customer
SET cpf = 'CPF_SHA256_' || upper(encode(digest(regexp_replace(cpf, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE cpf IS NOT NULL AND NOT fn_is_sha256_token(cpf, 'CPF');

UPDATE customer
SET email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(email)), 'sha256'), 'hex'))
WHERE email IS NOT NULL AND NOT fn_is_sha256_token(email, 'EMAIL');

UPDATE customer
SET phone = 'PHONE_SHA256_' || upper(encode(digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE phone IS NOT NULL AND NOT fn_is_sha256_token(phone, 'PHONE');

UPDATE customer
SET external_auth_uid = 'AUTH_SHA256_' || upper(encode(digest(btrim(external_auth_uid), 'sha256'), 'hex'))
WHERE external_auth_uid IS NOT NULL
  AND NOT fn_is_sha256_token(external_auth_uid, 'AUTH');

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'customer'
          AND column_name = 'birth_date'
    ) THEN
        EXECUTE 'UPDATE customer '
            || 'SET birth_year = EXTRACT(YEAR FROM birth_date)::SMALLINT '
            || 'WHERE birth_date IS NOT NULL AND birth_year IS NULL';
    END IF;
END;
$$;

UPDATE customer customer_record
SET address_token = 'ADDR_SHA256_' || upper(encode(digest(concat_ws('|',
        address.zip_code,
        address.street,
        address.number,
        address.complement,
        address.neighborhood,
        address.city,
        address.state
    ), 'sha256'), 'hex')),
    address_id = NULL
FROM address
WHERE address.address_id = customer_record.address_id;

ALTER TABLE customer DROP COLUMN IF EXISTS birth_date;

UPDATE customer_auth
SET login_email = 'EMAIL_SHA256_' || upper(encode(digest(lower(btrim(login_email)), 'sha256'), 'hex'))
WHERE NOT fn_is_sha256_token(login_email, 'EMAIL');

UPDATE sales_transaction
SET customer_document = 'DOC_SHA256_' || upper(encode(digest(regexp_replace(customer_document, '\D', '', 'g'), 'sha256'), 'hex'))
WHERE customer_document IS NOT NULL
  AND NOT fn_is_sha256_token(customer_document, 'DOC');

-- Recreate synchronization with the protected CPF token size.
CREATE OR REPLACE FUNCTION fn_sync_app_user_cpf()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_employee_cpf VARCHAR(80);
BEGIN
    SELECT cpf INTO v_employee_cpf
    FROM employee
    WHERE employee_id = NEW.employee_id;

    IF v_employee_cpf IS NULL THEN
        RAISE EXCEPTION 'Employee % does not exist or has no protected CPF token', NEW.employee_id;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.cpf IS NULL THEN
        NEW.cpf := v_employee_cpf;
    ELSIF NEW.cpf IS DISTINCT FROM v_employee_cpf THEN
        RAISE EXCEPTION 'app_user.cpf must match the protected employee CPF token';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_app_user_cpf
BEFORE INSERT OR UPDATE OF employee_id, cpf ON app_user
FOR EACH ROW EXECUTE FUNCTION fn_sync_app_user_cpf();

CREATE TRIGGER trg_propagate_employee_cpf
AFTER UPDATE OF cpf ON employee
FOR EACH ROW
WHEN (OLD.cpf IS DISTINCT FROM NEW.cpf)
EXECUTE FUNCTION fn_propagate_employee_cpf();

ALTER TABLE company ADD CONSTRAINT ck_company_email_protected
    CHECK (fn_is_protected_email(email));
ALTER TABLE company ADD CONSTRAINT ck_company_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));
ALTER TABLE retail_store ADD CONSTRAINT ck_store_email_protected
    CHECK (email IS NULL OR fn_is_protected_email(email));
ALTER TABLE retail_store ADD CONSTRAINT ck_store_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));
ALTER TABLE supplier ADD CONSTRAINT ck_supplier_email_protected
    CHECK (email IS NULL OR fn_is_protected_email(email));
ALTER TABLE supplier ADD CONSTRAINT ck_supplier_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));

ALTER TABLE employee ADD CONSTRAINT uq_employee_cpf_token UNIQUE (cpf);
ALTER TABLE employee ADD CONSTRAINT ck_employee_name_protected
    CHECK (name ~ '^EMP_[0-9]+$' OR fn_is_sha256_token(name, 'EMP'));
ALTER TABLE employee ADD CONSTRAINT ck_employee_cpf_protected
    CHECK (cpf ~ '^CPF_TKN_[A-Fa-f0-9]{6}$' OR fn_is_sha256_token(cpf, 'CPF'));
ALTER TABLE employee ADD CONSTRAINT ck_employee_email_protected
    CHECK (email IS NULL OR fn_is_protected_email(email));
ALTER TABLE employee ADD CONSTRAINT ck_employee_phone_protected
    CHECK (phone IS NULL OR fn_is_protected_phone(phone));

ALTER TABLE app_user ADD CONSTRAINT uq_app_user_email_token UNIQUE (email);
ALTER TABLE app_user ADD CONSTRAINT uq_app_user_cpf_token UNIQUE (cpf);
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_email_protected
    CHECK (fn_is_protected_email(email));
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_cpf_protected
    CHECK (cpf ~ '^CPF_TKN_[A-Fa-f0-9]{6}$' OR fn_is_sha256_token(cpf, 'CPF'));
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_password_bcrypt
    CHECK (fn_is_bcrypt_hash(password_hash));

ALTER TABLE customer ADD CONSTRAINT uq_customer_cpf_token UNIQUE (cpf);
ALTER TABLE customer ADD CONSTRAINT uq_customer_external_auth_token UNIQUE (external_auth_uid);
ALTER TABLE customer ADD CONSTRAINT ck_customer_name_protected
    CHECK (fn_is_sha256_token(full_name, 'CUS'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_cpf_protected
    CHECK (cpf IS NULL OR fn_is_sha256_token(cpf, 'CPF'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_email_protected
    CHECK (email IS NULL OR fn_is_sha256_token(email, 'EMAIL'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_phone_protected
    CHECK (phone IS NULL OR fn_is_sha256_token(phone, 'PHONE'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_external_auth_protected
    CHECK (external_auth_uid IS NULL OR fn_is_sha256_token(external_auth_uid, 'AUTH'));
ALTER TABLE customer ADD CONSTRAINT ck_customer_birth_year_minimized
    CHECK (birth_year IS NULL OR birth_year BETWEEN 1900 AND EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER);
ALTER TABLE customer ADD CONSTRAINT ck_customer_address_not_linked
    CHECK (address_id IS NULL);
ALTER TABLE customer ADD CONSTRAINT ck_customer_address_token_protected
    CHECK (address_token IS NULL OR fn_is_sha256_token(address_token, 'ADDR'));

ALTER TABLE customer_auth ADD CONSTRAINT uq_customer_auth_login_token UNIQUE (login_email);
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_login_protected
    CHECK (fn_is_sha256_token(login_email, 'EMAIL'));
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_password_bcrypt
    CHECK (fn_is_bcrypt_hash(password_hash));
ALTER TABLE customer_auth ADD CONSTRAINT ck_customer_auth_recovery_bcrypt
    CHECK (recovery_token_hash IS NULL OR fn_is_bcrypt_hash(recovery_token_hash));

ALTER TABLE sales_transaction ADD CONSTRAINT ck_sales_customer_document_protected
    CHECK (customer_document IS NULL OR fn_is_sha256_token(customer_document, 'DOC'));

ALTER TABLE staff_session ADD CONSTRAINT ck_staff_session_refresh_sha256
    CHECK (refresh_token_hash ~ '^[A-Fa-f0-9]{64}$');

ALTER TABLE password_reset_token ADD CONSTRAINT ck_password_reset_hash_algorithm
    CHECK (
        (token_type = 'PASSWORD_RESET' AND fn_is_bcrypt_hash(token_hash))
        OR (token_type = 'EMPLOYEE_INVITATION' AND token_hash ~ '^[A-Fa-f0-9]{64}$')
    );

-- Customer consent is append-oriented and keeps no personal value.
CREATE TABLE IF NOT EXISTS customer_consent (
    customer_consent_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    consent_type VARCHAR(40) NOT NULL,
    granted BOOLEAN NOT NULL,
    policy_version VARCHAR(40) NOT NULL,
    collection_channel VARCHAR(30) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    withdrawn_at TIMESTAMPTZ,
    CONSTRAINT ck_customer_consent_type
        CHECK (consent_type IN ('PRIVACY_POLICY', 'MARKETING', 'GEOLOCATION', 'LOYALTY')),
    CONSTRAINT ck_customer_consent_channel
        CHECK (collection_channel IN ('MOBILE_APP', 'WEB', 'SUPPORT', 'MIGRATION')),
    CONSTRAINT ck_customer_consent_withdrawal
        CHECK ((granted AND withdrawn_at IS NULL) OR (NOT granted AND withdrawn_at IS NOT NULL)),
    UNIQUE (customer_id, consent_type, policy_version, recorded_at)
);

CREATE INDEX IF NOT EXISTS idx_customer_consent_history
    ON customer_consent (customer_id, consent_type, recorded_at DESC);

-- RPA correlation stores metadata and hashes only, never transferred payloads.
CREATE TABLE IF NOT EXISTS legacy_sync_record (
    legacy_sync_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system VARCHAR(40) NOT NULL DEFAULT 'LEGACY_POSTGRES',
    source_table VARCHAR(80) NOT NULL,
    source_record_id VARCHAR(120) NOT NULL,
    target_table VARCHAR(80) NOT NULL,
    target_record_id VARCHAR(120) NOT NULL,
    payload_sha256 CHAR(64) NOT NULL CHECK (payload_sha256 ~ '^[A-Fa-f0-9]{64}$'),
    sync_status VARCHAR(20) NOT NULL DEFAULT 'APPLIED'
        CHECK (sync_status IN ('PENDING', 'APPLIED', 'REJECTED', 'REPLAYED')),
    synchronized_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_code VARCHAR(40),
    UNIQUE (source_system, source_table, source_record_id)
);

CREATE INDEX IF NOT EXISTS idx_legacy_sync_target
    ON legacy_sync_record (target_table, target_record_id);

-- Dedicated client API role and transaction-local customer context.
DO $$
DECLARE
    v_is_superuser BOOLEAN;
    v_has_replication BOOLEAN;
    v_bypasses_rls BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_customer_api') THEN
        CREATE ROLE mottainai_customer_api NOLOGIN NOCREATEDB
            NOCREATEROLE NOINHERIT;
    END IF;

    SELECT rolsuper, rolreplication, rolbypassrls
    INTO v_is_superuser, v_has_replication, v_bypasses_rls
    FROM pg_roles
    WHERE rolname = 'mottainai_customer_api';

    IF v_is_superuser OR v_has_replication OR v_bypasses_rls THEN
        RAISE EXCEPTION
            'Role mottainai_customer_api has a privileged attribute (SUPERUSER, REPLICATION or BYPASSRLS). A PostgreSQL superuser must remove it before this migration can continue.';
    END IF;

    ALTER ROLE mottainai_customer_api
        NOLOGIN
        NOCREATEDB
        NOCREATEROLE
        NOINHERIT;
END;
$$;

DO $$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO mottainai_customer_api',
        current_database()
    );
END;
$$;
GRANT USAGE ON SCHEMA mottainai TO mottainai_customer_api;

REVOKE SET ON PARAMETER app.current_customer_id FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_catalog.set_config(TEXT, TEXT, BOOLEAN)
    FROM mottainai_customer_api;

CREATE OR REPLACE FUNCTION fn_get_current_customer_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_customer_id', TRUE), '')::INTEGER;
$$;

CREATE OR REPLACE FUNCTION fn_bootstrap_customer_context(p_external_auth_token TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = mottainai, pg_temp
AS $$
DECLARE
    v_customer_id INTEGER;
BEGIN
    IF NOT fn_is_sha256_token(p_external_auth_token, 'AUTH') THEN
        RETURN NULL;
    END IF;

    SELECT customer_id INTO v_customer_id
    FROM customer
    WHERE external_auth_uid = p_external_auth_token
      AND active
      AND deleted_at IS NULL;

    IF v_customer_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('app.current_customer_id', v_customer_id::TEXT, TRUE);
    RETURN v_customer_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_get_current_customer_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bootstrap_customer_context(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_get_current_customer_id() TO mottainai_customer_api;
GRANT EXECUTE ON FUNCTION fn_bootstrap_customer_context(TEXT) TO mottainai_customer_api;

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_self_policy ON customer;
CREATE POLICY customer_self_policy ON customer FOR SELECT TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id());
DROP POLICY IF EXISTS customer_consent_update_policy ON customer;
CREATE POLICY customer_consent_update_policy ON customer FOR UPDATE TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_auth ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_auth_self_policy ON customer_auth;
CREATE POLICY customer_auth_self_policy ON customer_auth FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_geofence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_geofence_self_policy ON customer_geofence;
CREATE POLICY customer_geofence_self_policy ON customer_geofence FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE customer_consent ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_consent_self_policy ON customer_consent;
CREATE POLICY customer_consent_self_policy ON customer_consent FOR ALL TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id())
    WITH CHECK (customer_id = fn_get_current_customer_id());

ALTER TABLE loyalty_account ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_account_self_policy ON loyalty_account;
CREATE POLICY loyalty_account_self_policy ON loyalty_account FOR SELECT TO mottainai_customer_api
    USING (customer_id = fn_get_current_customer_id());

ALTER TABLE loyalty_transaction ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_transaction_self_policy ON loyalty_transaction;
CREATE POLICY loyalty_transaction_self_policy ON loyalty_transaction FOR SELECT TO mottainai_customer_api
    USING (EXISTS (
        SELECT 1 FROM loyalty_account account
        WHERE account.loyalty_account_id = loyalty_transaction.loyalty_account_id
          AND account.customer_id = fn_get_current_customer_id()
    ));

ALTER TABLE loyalty_redemption ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_redemption_self_policy ON loyalty_redemption;
CREATE POLICY loyalty_redemption_self_policy ON loyalty_redemption FOR SELECT TO mottainai_customer_api
    USING (EXISTS (
        SELECT 1 FROM loyalty_account account
        WHERE account.loyalty_account_id = loyalty_redemption.loyalty_account_id
          AND account.customer_id = fn_get_current_customer_id()
    ));

ALTER TABLE loyalty_reward ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loyalty_reward_active_policy ON loyalty_reward;
CREATE POLICY loyalty_reward_active_policy ON loyalty_reward FOR SELECT TO mottainai_customer_api
    USING (active AND (valid_from IS NULL OR valid_from <= CURRENT_TIMESTAMP)
        AND (valid_until IS NULL OR valid_until > CURRENT_TIMESTAMP));

GRANT SELECT ON customer TO mottainai_customer_api;
GRANT UPDATE (marketing_consent, updated_at) ON customer TO mottainai_customer_api;
GRANT SELECT, INSERT, UPDATE ON customer_auth, customer_geofence, customer_consent
    TO mottainai_customer_api;
GRANT SELECT ON loyalty_account, loyalty_transaction, loyalty_redemption, loyalty_reward
    TO mottainai_customer_api;
GRANT USAGE, SELECT ON SEQUENCE customer_auth_customer_auth_id_seq,
    customer_geofence_geofence_id_seq,
    customer_consent_customer_consent_id_seq
    TO mottainai_customer_api;

-- Recursive log redaction protects nested JSON objects and arrays.
CREATE OR REPLACE FUNCTION fn_sanitize_audit_json(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_data IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(p_data) = 'object' THEN
        SELECT jsonb_object_agg(entry.key,
            CASE
                WHEN lower(entry.key) = ANY (ARRAY[
                    'password', 'password_hash', 'token', 'token_hash',
                    'refresh_token', 'refresh_token_hash', 'recovery_token_hash',
                    'cpf', 'customer_document', 'email', 'login_email', 'phone',
                    'full_name', 'birth_date', 'external_auth_uid', 'address_token'
                ]) THEN '"[REDACTED]"'::JSONB
                ELSE fn_sanitize_audit_json(entry.value)
            END)
        INTO v_result
        FROM jsonb_each(p_data) AS entry;
        RETURN COALESCE(v_result, '{}'::JSONB);
    END IF;

    IF jsonb_typeof(p_data) = 'array' THEN
        SELECT jsonb_agg(fn_sanitize_audit_json(item.value))
        INTO v_result
        FROM jsonb_array_elements(p_data) AS item;
        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    RETURN p_data;
END;
$$;

REVOKE ALL ON FUNCTION fn_sanitize_audit_json(JSONB) FROM PUBLIC;

CREATE OR REPLACE FUNCTION fn_trg_sanitize_log_payload()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'integration_log' THEN
        NEW.payload := fn_sanitize_audit_json(NEW.payload);
        NEW.response := fn_sanitize_audit_json(NEW.response);
    ELSIF TG_TABLE_NAME = 'error_log' THEN
        NEW.parameters := fn_sanitize_audit_json(NEW.parameters);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sanitize_integration_log ON integration_log;
CREATE TRIGGER trg_sanitize_integration_log
BEFORE INSERT OR UPDATE OF payload, response ON integration_log
FOR EACH ROW EXECUTE FUNCTION fn_trg_sanitize_log_payload();

DROP TRIGGER IF EXISTS trg_sanitize_error_log ON error_log;
CREATE TRIGGER trg_sanitize_error_log
BEFORE INSERT OR UPDATE OF parameters ON error_log
FOR EACH ROW EXECUTE FUNCTION fn_trg_sanitize_log_payload();

DO $$
DECLARE
    v_trigger RECORD;
BEGIN
    FOR v_trigger IN SELECT * FROM (VALUES
        ('customer', 'customer_id'),
        ('customer_auth', 'customer_auth_id'),
        ('customer_consent', 'customer_consent_id')
    ) AS protected_table(table_name, id_column)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I',
            'trg_audit_' || v_trigger.table_name, v_trigger.table_name);
        EXECUTE format(
            'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I '
            || 'FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log(%L)',
            'trg_audit_' || v_trigger.table_name,
            v_trigger.table_name,
            v_trigger.id_column
        );
    END LOOP;
END;
$$;

COMMENT ON TABLE customer IS
    'Pseudonymized customer registry. Personal values must arrive as SHA-256-prefixed tokens.';
COMMENT ON COLUMN customer.external_auth_uid IS
    'SHA-256 token of the external identity subject; never store the original Firebase UID.';
COMMENT ON COLUMN customer.birth_year IS
    'Data-minimized year only; the exact birth date is intentionally not stored.';
COMMENT ON TABLE legacy_sync_record IS
    'Idempotent RPA correlation metadata; transferred payloads and personal values are forbidden.';

INSERT INTO schema_version (
    version,
    description,
    type,
    script,
    installed_by
) VALUES (
    '22',
    'Sensitive data tokenization, client isolation and RPA correlation contract',
    'SQL',
    '22_sensitive_data_contract.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;

-- ===== FIM 22_sensitive_data_contract.sql =====

-- ===== INICIO 23_sensitive_data_contract_tests.sql =====
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

-- ===== FIM 23_sensitive_data_contract_tests.sql =====

-- ===== INICIO 24_jpa_compatibility.sql =====
-- Atualização aditiva para um banco mottainai_operational já instalado.
-- Usar update_existing_jpa.sql para aplicar em banco existente; o install.sql
-- inclui este arquivo na instalação limpa. Ambos abrem uma transação.
-- Pode ser repetida; não apaga usuários nem tokens.
-- Alvo: esquema mottainai e entidade AppUser/PasswordResetToken do HEAD
-- 7d4d521 de Mottainai-Spring-Api-SQL em 2026-10-06.
-- IMPORTANTE: este script alinha COLUNAS. Não substitui as migrações Flyway
-- da API nem resolve sozinho a tokenização irreversível de e-mails da versão
-- 22_sensitive_data_contract.sql; veja as notas ao final.

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
    IF to_regclass('mottainai.app_user') IS NULL THEN
        RAISE EXCEPTION 'Tabela mottainai.app_user não existe. Instale o banco operacional primeiro.';
    END IF;
END $$;

-- Estado do convite inicial. TRUE preserva o estado das contas já existentes.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS password_set BOOLEAN NOT NULL DEFAULT TRUE;

-- Necessário para AppUser.tokenVersion e invalidação dos JWTs antigos.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;

-- Necessário para AppUser.firebaseUid. NULL para contas sem vínculo Firebase.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS firebase_uid VARCHAR(255);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.app_user'::regclass
          AND conname = 'ck_app_user_token_version_nonnegative'
    ) THEN
        ALTER TABLE mottainai.app_user
            ADD CONSTRAINT ck_app_user_token_version_nonnegative
            CHECK (token_version >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.app_user'::regclass
          AND conname = 'uq_app_user_firebase_uid'
    ) THEN
        ALTER TABLE mottainai.app_user
            ADD CONSTRAINT uq_app_user_firebase_uid UNIQUE (firebase_uid);
    END IF;
END $$;

COMMENT ON COLUMN mottainai.app_user.password_set IS
    'TRUE após o funcionário definir a senha inicial; convite novo usa FALSE.';
COMMENT ON COLUMN mottainai.app_user.token_version IS
    'Versão do token JWT; incrementar quando a senha ou autorização mudar.';

-- A versão operacional endurecida usa recovery_token_id/token_hash, enquanto
-- o JPA atual espera password_reset_token_id/code_hash/attempts. Mantemos os
-- nomes antigos usados pelas funções do banco e acrescentamos aliases reais.
-- Bancos locais instalados antes de 04_additional_tables.sql não têm esta
-- tabela. Criá-la aqui evita exigir reinstalação e preserva instalações novas.
CREATE TABLE IF NOT EXISTS mottainai.password_reset_token (
    recovery_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES mottainai.app_user(user_id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    requested_ip INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET'
        CHECK (token_type IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION')),
    CHECK (expires_at > created_at),
    CHECK (used_at IS NULL OR used_at >= created_at)
);

ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS password_reset_token_id INTEGER;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS code_hash VARCHAR(255);
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS token_hash TEXT;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET';

CREATE SEQUENCE IF NOT EXISTS mottainai.password_reset_token_jpa_id_seq AS INTEGER;
DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        ALTER SEQUENCE mottainai.password_reset_token_jpa_id_seq
            OWNED BY mottainai.password_reset_token.password_reset_token_id;
        ALTER TABLE mottainai.password_reset_token
            ALTER COLUMN password_reset_token_id
            SET DEFAULT nextval('mottainai.password_reset_token_jpa_id_seq'::regclass);
    END IF;
END $$;

-- Reserva a sequência acima dos IDs eventualmente já existentes.
DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        PERFORM setval(
            'mottainai.password_reset_token_jpa_id_seq'::regclass,
            GREATEST(COALESCE((SELECT MAX(password_reset_token_id)
                               FROM mottainai.password_reset_token), 0), 1),
            EXISTS (SELECT 1 FROM mottainai.password_reset_token
                    WHERE password_reset_token_id IS NOT NULL)
        );
    END IF;
END $$;

DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        UPDATE mottainai.password_reset_token
        SET password_reset_token_id =
            nextval('mottainai.password_reset_token_jpa_id_seq'::regclass)
        WHERE password_reset_token_id IS NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'password_reset_token'
          AND column_name = 'token_hash'
    ) THEN
        EXECUTE 'UPDATE mottainai.password_reset_token
                 SET code_hash = token_hash
                 WHERE code_hash IS NULL';
    END IF;
END $$;

UPDATE mottainai.password_reset_token
SET token_hash = code_hash
WHERE token_hash IS NULL AND code_hash IS NOT NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM mottainai.password_reset_token
               WHERE code_hash IS NULL OR token_hash IS NULL
                  OR password_reset_token_id IS NULL) THEN
        RAISE EXCEPTION 'Não foi possível preencher os aliases de hash/ID do token.';
    END IF;
END $$;

ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN password_reset_token_id SET NOT NULL;
ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN code_hash SET NOT NULL;
ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN token_hash SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_password_reset_token_token_hash_compat
    ON mottainai.password_reset_token (token_hash);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.password_reset_token'::regclass
          AND conname = 'uq_password_reset_token_jpa_id'
    ) THEN
        ALTER TABLE mottainai.password_reset_token
            ADD CONSTRAINT uq_password_reset_token_jpa_id
            UNIQUE (password_reset_token_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.password_reset_token'::regclass
          AND conname = 'ck_password_reset_attempts_nonnegative'
    ) THEN
        ALTER TABLE mottainai.password_reset_token
            ADD CONSTRAINT ck_password_reset_attempts_nonnegative
            CHECK (attempts >= 0);
    END IF;
END $$;

-- Nas instalações endurecidas, token_hash é NOT NULL e alimenta funções do
-- banco. O JPA escreve code_hash. Este trigger sincroniza os dois sentidos.
CREATE OR REPLACE FUNCTION mottainai.fn_sync_password_reset_hash_alias()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.code_hash IS NULL THEN NEW.code_hash := NEW.token_hash; END IF;
        IF NEW.token_hash IS NULL THEN NEW.token_hash := NEW.code_hash; END IF;
    ELSE
        IF NEW.code_hash IS DISTINCT FROM OLD.code_hash THEN
            NEW.token_hash := NEW.code_hash;
        ELSIF NEW.token_hash IS DISTINCT FROM OLD.token_hash THEN
            NEW.code_hash := NEW.token_hash;
        END IF;
    END IF;
    IF NEW.code_hash IS DISTINCT FROM NEW.token_hash THEN
        RAISE EXCEPTION 'code_hash e token_hash divergentes';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'password_reset_token'
          AND column_name = 'token_hash'
    ) THEN
        DROP TRIGGER IF EXISTS trg_sync_password_reset_hash_alias
            ON mottainai.password_reset_token;
        CREATE TRIGGER trg_sync_password_reset_hash_alias
            BEFORE INSERT OR UPDATE OF code_hash, token_hash
            ON mottainai.password_reset_token
            FOR EACH ROW EXECUTE FUNCTION mottainai.fn_sync_password_reset_hash_alias();
    END IF;
END $$;

-- O JPA gera o identificador e faz INSERT; a role precisa usar a sequência.
DO $$
DECLARE
    v_recovery_sequence TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_api') THEN
        GRANT USAGE, SELECT ON SEQUENCE
            mottainai.password_reset_token_jpa_id_seq TO mottainai_api;

        -- Se a tabela foi criada apenas nesta atualização em uma instalação
        -- já endurecida, restaurar a mesma política de 20_security_hardening.
        IF to_regprocedure('mottainai.fn_can_access_user(integer)') IS NOT NULL THEN
            ALTER TABLE mottainai.password_reset_token ENABLE ROW LEVEL SECURITY;
            IF NOT EXISTS (
                SELECT 1 FROM pg_policies
                WHERE schemaname = 'mottainai'
                  AND tablename = 'password_reset_token'
                  AND policyname = 'password_reset_token_policy'
            ) THEN
                CREATE POLICY password_reset_token_policy
                    ON mottainai.password_reset_token FOR ALL TO mottainai_api
                    USING (mottainai.fn_can_access_user(user_id))
                    WITH CHECK (mottainai.fn_can_access_user(user_id));
            END IF;
            GRANT SELECT, INSERT, UPDATE ON mottainai.password_reset_token
                TO mottainai_api;
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'mottainai'
                  AND table_name = 'password_reset_token'
                  AND column_name = 'recovery_token_id'
            ) THEN
                v_recovery_sequence := pg_get_serial_sequence(
                    'mottainai.password_reset_token', 'recovery_token_id');
                IF v_recovery_sequence IS NOT NULL THEN
                    EXECUTE format(
                        'GRANT USAGE, SELECT ON SEQUENCE %s TO mottainai_api',
                        v_recovery_sequence);
                END IF;
            END IF;
        END IF;
    END IF;
END $$;

-- Validação estrutural da migração, sem expor valores pessoais.
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.name, ', ')
    INTO v_missing
    FROM (VALUES ('password_set'), ('token_version'), ('firebase_uid')) AS required(name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema = 'mottainai'
          AND c.table_name = 'app_user'
          AND c.column_name = required.name
    );
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Campos app_user ausentes: %', v_missing;
    END IF;
END $$;


-- VERIFICAÇÃO MANUAL APÓS EXECUTAR:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema='mottainai' AND table_name='app_user'
-- ORDER BY ordinal_position;
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema='mottainai' AND table_name='password_reset_token'
-- ORDER BY ordinal_position;

-- LIMITES IMPORTANTES:
-- 1) A API Flyway V9 cria password_reset_token sem IF NOT EXISTS. Se o Flyway
--    não estiver sincronizado com esse banco, a inicialização ainda falhará;
--    não altere flyway_schema_history manualmente sem plano de baseline.
-- 2) Se 22_sensitive_data_contract.sql foi executado, e-mails foram convertidos
--    em tokens SHA-256. O JPA atual pesquisa e envia e-mail em texto puro;
--    SQL não consegue recuperar o e-mail original. A API precisa adaptar o
--    lookup e manter canal seguro de entrega; esta migração não corrige isso.
-- 3) O JPA atual apaga tokens antigos via deleteByUserId. A role endurecida
--    não recebe DELETE na tabela. Não ampliamos o privilégio aqui: o serviço
--    deve passar a marcar tokens usados/revogados e manter auditoria.
-- 4) password_set foi criado no banco, mas AppUser.java ainda não o mapeia.
--    O campo existirá; a API só controlará o fluxo de convite após mapear
--    esse atributo e definir FALSE/TRUE nos momentos corretos.

-- ===== FIM 24_jpa_compatibility.sql =====

-- ===== INICIO 25_jpa_compatibility_tests.sql =====
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

-- ===== FIM 25_jpa_compatibility_tests.sql =====

COMMIT;
