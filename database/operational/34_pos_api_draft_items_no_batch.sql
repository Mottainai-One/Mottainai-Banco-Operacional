-- POS draft items must not reserve a FEFO batch or change stock before checkout.
-- Preserve the existing FEFO behavior for all non-draft sale items.
BEGIN;

CREATE OR REPLACE FUNCTION mottainai.fn_trg_select_batch_fefo()
RETURNS TRIGGER AS $$
DECLARE
    v_store_id INTEGER;
    v_batch_id INTEGER;
BEGIN
    IF NEW.status = 'DRAFT' THEN
        NEW.batch_id := NULL;
        RETURN NEW;
    END IF;

    IF NEW.batch_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT sale.store_id INTO v_store_id
      FROM mottainai.sales_transaction AS sale
     WHERE sale.sale_id = NEW.sale_id
       AND sale.sale_date = NEW.sale_date;

    v_batch_id := mottainai.fn_select_batch_fefo(
        NEW.product_id,
        v_store_id,
        NEW.quantity_sold
    );

    IF v_batch_id IS NULL THEN
        RAISE EXCEPTION
            'Insufficient stock for product % in store % (FEFO selection failed)',
            NEW.product_id,
            v_store_id;
    END IF;

    NEW.batch_id := v_batch_id;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO mottainai.error_log (
        error_message,
        function_name,
        parameters
    )
    VALUES (
        SQLERRM,
        'fn_trg_select_batch_fefo',
        jsonb_build_object('sale_id', NEW.sale_id, 'product_id', NEW.product_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;

COMMIT;
