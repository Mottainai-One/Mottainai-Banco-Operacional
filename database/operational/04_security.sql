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
