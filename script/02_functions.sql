-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 03_VALIDATION_FUNCTIONS.SQL (TODAS IMMUTABLE)
-- ====================================================================

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
