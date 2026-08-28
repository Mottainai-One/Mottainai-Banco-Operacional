-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 30_TESTES.SQL
-- ====================================================================

CREATE OR REPLACE FUNCTION test_01_validation()
RETURNS TEXT AS $$
BEGIN
    IF NOT fn_validate_cpf('12345678909') THEN
        RETURN 'FAIL: Valid CPF rejected';
    END IF;
    
    IF fn_validate_cpf('11111111111') THEN
        RETURN 'FAIL: Invalid CPF accepted';
    END IF;
    
    IF NOT fn_validate_cnpj('11222333000181') THEN
        RETURN 'FAIL: Valid CNPJ rejected';
    END IF;
    
    IF fn_validate_cnpj('11111111111111') THEN
        RETURN 'FAIL: Invalid CNPJ accepted';
    END IF;
    
    RETURN 'PASS: Validation tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_02_fefo()
RETURNS TEXT AS $$
DECLARE
    v_product_id INTEGER;
    v_store_id INTEGER;
    v_old_batch_id INTEGER;
    v_new_batch_id INTEGER;
    v_batch_id INTEGER;
BEGIN
    INSERT INTO product (
        category_id, sku, barcode, name, unit_measure, tax_profile_id, ncm
    )
    VALUES (
        (SELECT category_id FROM product_category ORDER BY category_id LIMIT 1),
        'TEST-FEFO-001',
        'BARCODE001',
        'Test Product FEFO',
        'UN',
        (SELECT tax_profile_id FROM tax_profile ORDER BY tax_profile_id LIMIT 1),
        '00000000'
    )
    RETURNING product_id INTO v_product_id;
    
    INSERT INTO retail_store (company_id, address_id, name, cnpj)
    VALUES (1, 1, 'Test Store FEFO', '11222333000181')
    RETURNING store_id INTO v_store_id;
    
    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-OLD', '2024-01-01', 100, 10.00)
    RETURNING batch_id INTO v_old_batch_id;
    
    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-NEW', '2024-06-01', 100, 10.00)
    RETURNING batch_id INTO v_new_batch_id;
    
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (v_store_id, v_old_batch_id, 100, 10);
    
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (v_store_id, v_new_batch_id, 100, 10);
    
    v_batch_id := fn_select_batch_fefo(v_product_id, v_store_id, 10);
    
    IF v_batch_id != v_old_batch_id THEN
        RETURN 'FAIL: FEFO selected newer batch instead of older';
    END IF;
    
    RETURN 'PASS: FEFO tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_03_inventory()
RETURNS TEXT AS $$
DECLARE
    v_inventory_id INTEGER;
    v_new_quantity DECIMAL;
BEGIN
    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    VALUES (1, 1, 100, 10)
    RETURNING inventory_id INTO v_inventory_id;
    
    BEGIN
        v_new_quantity := fn_atomic_update_inventory(v_inventory_id, -150, 'OUT');
        RETURN 'FAIL: Should not allow negative stock';
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    v_new_quantity := fn_atomic_update_inventory(v_inventory_id, -50, 'OUT');
    
    IF v_new_quantity != 50 THEN
        RETURN 'FAIL: Inventory update failed, expected 50 got ' || v_new_quantity;
    END IF;
    
    RETURN 'PASS: Inventory tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_04_audit()
RETURNS TEXT AS $$
DECLARE
    v_audit_count INTEGER;
BEGIN
    PERFORM fn_set_session_context(1, 1, 1);
    
    UPDATE product SET name = 'Updated Product' WHERE product_id = 1;
    
    SELECT COUNT(*) INTO v_audit_count
    FROM audit_log
    WHERE table_affected = 'product'
      AND record_id = '1'
      AND user_id = 1;
    
    IF v_audit_count = 0 THEN
        RETURN 'FAIL: Audit log not created';
    END IF;
    
    RETURN 'PASS: Audit tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION run_all_tests()
RETURNS TABLE(test_name TEXT, result TEXT) AS $$
BEGIN
    RETURN QUERY SELECT 'Validation'::TEXT, test_01_validation();
    RETURN QUERY SELECT 'FEFO'::TEXT, test_02_fefo();
    RETURN QUERY SELECT 'Inventory'::TEXT, test_03_inventory();
    RETURN QUERY SELECT 'Audit'::TEXT, test_04_audit();
END;
$$ LANGUAGE plpgsql;
