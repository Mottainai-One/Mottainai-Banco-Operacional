\set ON_ERROR_STOP on

-- Atualiza um MOTTAINAI existente que já recebeu a migração 42.
-- Execute conectado ao banco operacional com a role administrativa de migração.
-- Esta correção não altera os dados dos clientes.
\ir 43_notification_customer_consent_policy.sql
