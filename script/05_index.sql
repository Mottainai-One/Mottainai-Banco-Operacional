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
