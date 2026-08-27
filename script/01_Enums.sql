-- ====================================================================
-- MOTTAINAI DATABASE v6.0 - ENTERPRISE FINAL EDITION - CORRIGIDO v6 FINAL
-- PostgreSQL 15+
-- ====================================================================

-- 02_ENUMS.SQL
-- ====================================================================

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_order_status') THEN
        CREATE TYPE purchase_order_status AS ENUM ('PENDING', 'APPROVED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'receiving_status') THEN
        CREATE TYPE receiving_status AS ENUM ('PENDING', 'CONFIRMED', 'DIVERGENT');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_status') THEN
        CREATE TYPE sale_status AS ENUM ('COMPLETED', 'CANCELED', 'RETURNED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_cancel_status') THEN
        CREATE TYPE pos_cancel_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_cancel_target') THEN
        CREATE TYPE pos_cancel_target AS ENUM ('ITEM', 'SALE');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_item_status') THEN
        CREATE TYPE sale_item_status AS ENUM ('SOLD', 'CANCELED', 'RETURNED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'promotion_status') THEN
        CREATE TYPE promotion_status AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'EXPIRED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'movement_type') THEN
        CREATE TYPE movement_type AS ENUM ('IN', 'OUT', 'ADJUSTMENT', 'TRANSFER', 'DONATION', 'DISPOSAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_type') THEN
        CREATE TYPE inventory_type AS ENUM ('NORMAL', 'CONSIGNED', 'QUARANTINE');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN
        CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        CREATE TYPE payment_method AS ENUM ('CASH', 'CARD', 'PIX', 'BOLETO');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_status') THEN
        CREATE TYPE inventory_status AS ENUM ('IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_status') THEN
        CREATE TYPE alert_status AS ENUM ('ACTIVE', 'ANALYZING', 'RESOLVED', 'IGNORED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type') THEN
        CREATE TYPE alert_type AS ENUM ('EXPIRATION', 'CRITICAL_STOCK', 'RUPTURE', 'SLOW_MOVING', 'OVERSTOCK');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_status') THEN
        CREATE TYPE suggested_action_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'suggested_action_type') THEN
        CREATE TYPE suggested_action_type AS ENUM ('PROMOTION', 'TRANSFER', 'DONATION', 'DISPOSAL', 'REORDER');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pre_list_status') THEN
        CREATE TYPE pre_list_status AS ENUM ('GENERATED', 'IN_PROGRESS', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transfer_status') THEN
        CREATE TYPE transfer_status AS ENUM ('REQUESTED', 'IN_TRANSIT', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'donation_status') THEN
        CREATE TYPE donation_status AS ENUM ('REGISTERED', 'COMPLETED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_operation') THEN
        CREATE TYPE audit_operation AS ENUM ('INSERT', 'UPDATE', 'DELETE');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_model_type') THEN
        CREATE TYPE ai_model_type AS ENUM ('FORECAST', 'RECOMMENDATION', 'CLASSIFICATION', 'OPTIMIZATION');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
        CREATE TYPE event_status AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELED');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'log_level') THEN
        CREATE TYPE log_level AS ENUM ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'migration_type') THEN
        CREATE TYPE migration_type AS ENUM ('SQL', 'JAVA', 'GROOVY', 'SCRIPT');
    END IF;
END $$;
