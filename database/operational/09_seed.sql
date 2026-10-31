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
