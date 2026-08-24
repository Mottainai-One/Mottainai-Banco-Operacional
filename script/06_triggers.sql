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
