-- ============================================================================
-- PROTECTED DATA REINSTALL - TEST FIXTURE
-- PostgreSQL 15+
--
-- CI-only fixture. It persists one protected employee and app_user so the
-- complete installer can be reapplied against a populated, hardened database.
-- ============================================================================

SET search_path TO mottainai, public;

DO $$
DECLARE
    v_plan_id INTEGER;
    v_role_id INTEGER;
    v_address_id INTEGER;
    v_company_id INTEGER;
    v_store_id INTEGER;
    v_employee_id INTEGER;
BEGIN
    SELECT MIN(plan_id) INTO v_plan_id FROM subscription_plan;
    SELECT MIN(role_id) INTO v_role_id FROM employee_role;

    IF v_plan_id IS NULL OR v_role_id IS NULL THEN
        RAISE EXCEPTION 'Reference seed data is required for reinstall fixture';
    END IF;

    INSERT INTO address (
        zip_code, street, number, neighborhood, city, state
    ) VALUES (
        '01001000', 'Protected Reinstall Fixture', '1',
        'Test', 'Sao Paulo', 'SP'
    )
    RETURNING address_id INTO v_address_id;

    INSERT INTO company (
        plan_id, official_name, trade_name, cnpj, email
    ) VALUES (
        v_plan_id,
        'Protected Reinstall Fixture',
        'Protected Reinstall Fixture',
        '11222333000181',
        'EMAIL_SHA256_' || repeat('D', 64)
    )
    RETURNING company_id INTO v_company_id;

    PERFORM fn_set_legacy_migration_context(v_company_id);

    INSERT INTO retail_store (
        company_id, address_id, name, cnpj
    ) VALUES (
        v_company_id,
        v_address_id,
        'Protected Reinstall Store',
        '11222333000181'
    )
    RETURNING store_id INTO v_store_id;

    INSERT INTO employee (
        store_id, role_id, active, cpf_lookup_hmac
    ) VALUES (
        v_store_id, v_role_id, FALSE, decode(repeat('77', 32), 'hex')
    )
    RETURNING employee_id INTO v_employee_id;

    INSERT INTO employee_private_data (
        employee_id,
        name_ciphertext,
        name_nonce,
        name_masked,
        cpf_ciphertext,
        cpf_nonce,
        cpf_masked,
        email_ciphertext,
        email_nonce,
        email_masked,
        key_version,
        protection_state,
        encrypted_at
    ) VALUES (
        v_employee_id,
        decode(repeat('11', 17), 'hex'),
        decode(repeat('22', 12), 'hex'),
        'EMPLOYEE_FIXTURE',
        decode(repeat('55', 17), 'hex'),
        decode(repeat('66', 12), 'hex'),
        '***.***.***-**',
        decode(repeat('33', 17), 'hex'),
        decode(repeat('44', 12), 'hex'),
        'f***@example.test',
        1,
        'ENCRYPTED',
        CURRENT_TIMESTAMP
    );

    INSERT INTO app_user (
        employee_id, firebase_uid, password_hash, password_set, active
    ) VALUES (
        v_employee_id,
        NULL,
        crypt('reinstall-fixture-only', gen_salt('bf', 4)),
        FALSE,
        FALSE
    );

    RAISE NOTICE 'Protected reinstall fixture created';
END;
$$;
