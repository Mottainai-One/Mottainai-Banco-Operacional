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
    v_disposal_id INTEGER;
BEGIN
    PERFORM fn_set_session_context(1, 1, 1);

    INSERT INTO disposal (store_id, employee_id, reason)
    VALUES (1, 1, 'Test disposal for audit')
    RETURNING disposal_id INTO v_disposal_id;

    UPDATE disposal SET observation = 'Updated by test' WHERE disposal_id = v_disposal_id;

    SELECT COUNT(*) INTO v_audit_count
    FROM audit_log
    WHERE table_affected = 'disposal'
      AND record_id = v_disposal_id::TEXT
      AND user_id = 1;

    IF v_audit_count = 0 THEN
        RETURN 'FAIL: Audit log not created for disposal';
    END IF;

    RETURN 'PASS: Audit tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_05_avg_cost()
RETURNS TEXT AS $$
DECLARE
    v_product_id INTEGER;
    v_avg DECIMAL(10,2);
    v_suggested DECIMAL(10,2);
BEGIN
    INSERT INTO product (
        category_id, sku, barcode, name, unit_measure, tax_profile_id, ncm
    )
    VALUES (
        (SELECT category_id FROM product_category ORDER BY category_id LIMIT 1),
        'TEST-COST-001',
        'BARCODECOST001',
        'Test Product Cost',
        'UN',
        (SELECT tax_profile_id FROM tax_profile ORDER BY tax_profile_id LIMIT 1),
        '00000000'
    )
    RETURNING product_id INTO v_product_id;

    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-COST-A', '2025-01-01', 100, 10.00);

    INSERT INTO batch (product_id, receiving_item_id, batch_code, expiration_date, initial_quantity, unit_cost)
    VALUES (v_product_id, NULL, 'BATCH-COST-B', '2025-06-01', 100, 20.00);

    INSERT INTO inventory (store_id, batch_id, current_quantity, minimum_quantity)
    SELECT 1, batch_id, initial_quantity, 10 FROM batch WHERE product_id = v_product_id;

    v_avg := fn_calculate_avg_cost(v_product_id);

    IF v_avg != 15.00 THEN
        RETURN 'FAIL: Expected average cost 15.00, got ' || v_avg;
    END IF;

    v_suggested := fn_suggest_sale_price(v_product_id, 0.20);
    IF v_suggested != 18.00 THEN
        RETURN 'FAIL: Expected suggested price 18.00, got ' || v_suggested;
    END IF;

    RETURN 'PASS: Average cost tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_06_engine_diagnostic()
RETURNS TEXT AS $$
DECLARE
    v_scan_count INTEGER;
    v_diag_row RECORD;
BEGIN
    SELECT COUNT(*) INTO v_scan_count FROM engine_scan_log;
    IF v_scan_count = 0 THEN
        RETURN 'FAIL: No engine scan records found';
    END IF;

    SELECT COUNT(*) INTO v_scan_count FROM engine_suggestion;
    IF v_scan_count = 0 THEN
        RETURN 'FAIL: No engine suggestion records found';
    END IF;

    FOR v_diag_row IN SELECT store_id, total_skus_scanned FROM mottainai_analytics.vw_engine_diagnostics
    LOOP
        IF v_diag_row.total_skus_scanned <= 0 THEN
            RETURN 'FAIL: Engine diagnostics view returned no scanned SKUs';
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM vw_top_selling_categories LIMIT 1) THEN
        RETURN 'FAIL: Top selling categories view is empty';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM vw_seasonality_by_weekday LIMIT 1) THEN
        RETURN 'FAIL: Seasonality view is empty';
    END IF;

    RETURN 'PASS: Engine diagnostic tests passed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION run_all_tests()
RETURNS TABLE(test_name TEXT, result TEXT) AS $$
BEGIN
    RETURN QUERY SELECT 'Validation'::TEXT, test_01_validation();
    RETURN QUERY SELECT 'FEFO'::TEXT, test_02_fefo();
    RETURN QUERY SELECT 'Inventory'::TEXT, test_03_inventory();
    RETURN QUERY SELECT 'Audit'::TEXT, test_04_audit();
    RETURN QUERY SELECT 'AvgCost'::TEXT, test_05_avg_cost();
    RETURN QUERY SELECT 'EngineDiagnostic'::TEXT, test_06_engine_diagnostic();
END;
$$ LANGUAGE plpgsql;
