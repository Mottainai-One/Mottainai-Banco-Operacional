\set ON_ERROR_STOP on

-- Execute conectado ao banco analítico existente.
-- O contrato não possui updated_at; somente as colunas abaixo são alteradas.
BEGIN;

UPDATE mottainai_analytics.etl_source_contract
SET extraction_mode = 'INCREMENTAL',
    watermark_column = 'recorded_at'
WHERE source_table = 'customer_consent';

UPDATE mottainai_analytics.etl_source_contract
SET extraction_mode = 'INCREMENTAL',
    watermark_column = 'redeemed_at'
WHERE source_table = 'loyalty_redemption';

COMMIT;

SELECT source_table, extraction_mode, watermark_column, required
FROM mottainai_analytics.etl_source_contract
WHERE source_table IN ('customer_consent', 'loyalty_redemption')
ORDER BY source_table;
