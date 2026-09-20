SET search_path TO mottainai_analytics, public;

DO $$ BEGIN
    CREATE TYPE ai_model_type AS ENUM (
        'DEMAND_FORECAST', 'EXPIRY_RISK', 'PRICE_OPTIMIZATION',
        'REPLENISHMENT', 'CUSTOMER_SEGMENTATION', 'FRAUD_DETECTION'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE suggested_action_type AS ENUM (
        'DISCOUNT', 'REPLENISH', 'TRANSFER', 'DONATE',
        'DISCARD', 'ADJUST_PRICE', 'CONTACT_SUPPLIER'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE suggested_action_status AS ENUM (
        'PENDING', 'ACCEPTED', 'REJECTED', 'EXECUTED', 'EXPIRED', 'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE ingestion_status AS ENUM ('RECEIVED', 'PROCESSED', 'FAILED', 'IGNORED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE job_status AS ENUM ('RUNNING', 'SUCCEEDED', 'FAILED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
