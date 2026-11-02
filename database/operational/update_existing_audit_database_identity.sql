\set ON_ERROR_STOP on

-- Use on an existing MOTTAINAI database after the audited schema is installed.
-- This migration adds identity columns and updates the existing audit trigger.
\ir 44_audit_database_identity.sql
