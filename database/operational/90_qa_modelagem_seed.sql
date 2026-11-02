-- Carga sintética de QA para a instalação operacional canônica.
-- Não faz parte de install.sql e não deve ser executada em banco compartilhado.
-- Cria 500 produtos sem PII, com categorias e perfil fiscal existentes.
-- Reexecução é idempotente: linhas com o prefixo QA-MODEL- não são duplicadas.

BEGIN;
SET LOCAL search_path TO mottainai, public;

-- The canonical model assigns every product to one company. This fixed,
-- valid synthetic CNPJ and protected placeholder email are QA-only fixtures.
INSERT INTO company (plan_id, official_name, trade_name, cnpj, email)
SELECT plan_id,
       'Empresa QA Modelagem',
       'QA Modelagem',
       '73828777326069',
       'EMAIL_COMPANY_1'
FROM subscription_plan
WHERE name = 'Professional'
ON CONFLICT (cnpj) DO NOTHING;

WITH categories AS (
    SELECT category_id,
           name,
           row_number() OVER (ORDER BY category_id) AS position,
           count(*) OVER () AS total
    FROM product_category
    WHERE active IS TRUE
      AND deleted_at IS NULL
),
seed_rows AS (
    SELECT g AS sequence_no,
           company.company_id,
           category.category_id,
           category.name AS category_name,
           tax.tax_profile_id
    FROM generate_series(1, 500) AS g
    JOIN categories AS category
      ON category.position = ((g - 1) % category.total) + 1
    CROSS JOIN (
        SELECT company_id
        FROM company
        WHERE cnpj = '73828777326069'
          AND active IS TRUE
          AND deleted_at IS NULL
        ORDER BY company_id
        LIMIT 1
    ) AS company
    CROSS JOIN (
        SELECT tax_profile_id
        FROM tax_profile
        WHERE code = 'DEFAULT'
        ORDER BY tax_profile_id
        LIMIT 1
    ) AS tax
),
product_rows AS (
    SELECT sequence_no,
           company_id,
           category_id,
           tax_profile_id,
           'QA-MODEL-' || lpad(sequence_no::text, 4, '0') AS sku,
           (2000000000000::bigint + sequence_no)::text AS barcode,
           CASE category_name
               WHEN 'Food' THEN '10063021'
               WHEN 'Beverages' THEN '22021000'
               WHEN 'Cleaning' THEN '34025000'
               WHEN 'Personal Care' THEN '33061000'
               ELSE '10063021'
           END AS ncm,
           CASE category_name
               WHEN 'Food' THEN (ARRAY[
                   'Arroz integral', 'Feijão carioca', 'Farinha de trigo',
                   'Macarrão parafuso', 'Café torrado', 'Açúcar refinado',
                   'Leite integral', 'Óleo de soja', 'Molho de tomate',
                   'Biscoito de aveia'
               ])[((sequence_no - 1) % 10) + 1]
               WHEN 'Beverages' THEN (ARRAY[
                   'Água mineral', 'Suco de uva', 'Chá mate', 'Café pronto',
                   'Água de coco', 'Néctar de laranja', 'Refrigerante de guaraná',
                   'Bebida de soja', 'Isotônico de limão', 'Suco de maçã'
               ])[((sequence_no - 1) % 10) + 1]
               WHEN 'Cleaning' THEN (ARRAY[
                   'Detergente neutro', 'Sabão em pó', 'Desinfetante floral',
                   'Água sanitária', 'Limpador multiuso', 'Esponja dupla face',
                   'Amaciante concentrado', 'Saco para lixo', 'Lustra-móveis',
                   'Sabão em barra'
               ])[((sequence_no - 1) % 10) + 1]
               WHEN 'Personal Care' THEN (ARRAY[
                   'Sabonete neutro', 'Shampoo hidratante', 'Creme dental',
                   'Escova dental macia', 'Desodorante aerosol', 'Papel higiênico',
                   'Condicionador diário', 'Fio dental', 'Hidratante corporal',
                   'Lenço umedecido'
               ])[((sequence_no - 1) % 10) + 1]
               ELSE 'Produto de mercearia'
           END || ' ' || lpad(sequence_no::text, 4, '0') AS name,
           (ARRAY['Serra Clara', 'Casa do Vale', 'Viva Bem', 'Campo Dourado', 'Sol Nascente'])[
               ((sequence_no - 1) % 5) + 1
           ] AS brand,
           CASE category_name
               WHEN 'Food' THEN CASE WHEN sequence_no % 3 = 0 THEN 'KG' ELSE 'UN' END
               WHEN 'Beverages' THEN 'L'
               ELSE 'UN'
           END AS unit_measure,
           round(((sequence_no % 10) + 1)::numeric * 0.25, 3) AS weight,
           round((2 + (sequence_no % 50))::numeric, 2) AS avg_cost,
           round((2 + (sequence_no % 50))::numeric * 1.30, 2) AS suggested_price
    FROM seed_rows
)
INSERT INTO product (
    company_id, category_id, tax_profile_id, sku, barcode, ncm, name, brand,
    unit_measure, weight, avg_cost, suggested_price
)
SELECT product_rows.company_id,
       product_rows.category_id,
       product_rows.tax_profile_id,
       product_rows.sku,
       product_rows.barcode,
       product_rows.ncm,
       product_rows.name,
       product_rows.brand,
       product_rows.unit_measure,
       product_rows.weight,
       product_rows.avg_cost,
       product_rows.suggested_price
FROM product_rows
WHERE NOT EXISTS (
    SELECT 1
    FROM product AS existing
    WHERE existing.sku = product_rows.sku
);

DO $$
DECLARE
    v_rows integer;
BEGIN
    SELECT count(*)
      INTO v_rows
      FROM product
     WHERE sku LIKE 'QA-MODEL-%';

    IF v_rows <> 500 THEN
        RAISE EXCEPTION 'Esperados 500 produtos do seed de QA, encontrados %', v_rows;
    END IF;
END;
$$;

COMMIT;

