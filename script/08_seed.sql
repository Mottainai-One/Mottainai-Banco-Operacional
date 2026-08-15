-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 31_INITIAL_DATA.SQL
-- ====================================================================

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
    ('Electronics', 'Electronic devices and accessories'),
    ('Food', 'Food and beverages'),
    ('Beverages', 'Drinks and beverages'),
    ('Cleaning', 'Cleaning supplies'),
    ('Personal Care', 'Personal hygiene products'),
    ('Clothing', 'Apparel and accessories')
ON CONFLICT (name) DO NOTHING;

INSERT INTO tax_profile (
    code, name, description, cfop, icms_cst, icms_rate,
    pis_cst, pis_rate, cofins_cst, cofins_rate
) VALUES (
    'DEFAULT', 'Perfil fiscal padrão', 'Perfil fiscal inicial para testes',
    '5102', '102', 0, '01', 0, '01', 0
)
ON CONFLICT (code) DO NOTHING;

INSERT INTO ai_model (name, version, model_type, description, parameters) VALUES
    ('DemandForecast', '1.0.0', 'FORECAST', 'Demand forecasting using ARIMA', '{"window": 30, "confidence": 0.95}'),
    ('ReplenishmentOptimizer', '1.0.0', 'OPTIMIZATION', 'Optimize replenishment quantities', '{"safety_stock": 1.2, "lead_time": 7}'),
    ('InventoryClassifier', '1.0.0', 'CLASSIFICATION', 'Classify inventory criticality', '{"thresholds": {"critical": 2, "high": 5}}')
ON CONFLICT (name, version) DO NOTHING;

INSERT INTO schema_version (version, description, type, script, installed_by) VALUES
    ('1', 'Initial Schema', 'SQL', 'V1__initial_schema.sql', CURRENT_USER),
    ('2', 'Add Soft Delete', 'SQL', 'V2__add_soft_delete.sql', CURRENT_USER),
    ('3', 'Add Partitions', 'SQL', 'V3__add_partitions.sql', CURRENT_USER),
    ('4', 'Add Audit Triggers', 'SQL', 'V4__add_audit_triggers.sql', CURRENT_USER),
    ('5', 'Add KPI Cache', 'SQL', 'V5__add_kpi_cache.sql', CURRENT_USER),
    ('6', 'Add AI Module', 'SQL', 'V6__add_ai_module.sql', CURRENT_USER),
    ('7', 'Add Partial Indexes', 'SQL', 'V7__add_partial_indexes.sql', CURRENT_USER),
    ('8', 'Add Documentation', 'SQL', 'V8__add_documentation.sql', CURRENT_USER),
    ('9', 'Add Customer Mobile, POS, Fiscal and Tax Modules', 'SQL', 'V9__add_customer_pos_fiscal_tax.sql', CURRENT_USER)
ON CONFLICT (version) DO NOTHING;
