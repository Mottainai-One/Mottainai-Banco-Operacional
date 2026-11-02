-- Customer offer notifications: consent, temporary location, daily campaigns,
-- device registration, and a server-side retry queue.
-- Apply after 38_client_mobile_api.sql and the preceding operational migrations.
-- The push worker must use a dedicated server-side login granted only to
-- mottainai_notification_worker. Never grant that role to mobile/API logins.
-- Per store and Sao Paulo calendar day, select at most three distinct products.
-- Among nearby, opted-in customers with active devices, the highest loyalty
-- balances are queued first for immediate delivery; the remainder are due
-- 30 minutes after campaign creation. The 20% group rounds up to a whole
-- customer, with at least one immediate recipient when eligible customers exist.
-- Delivery is at-least-once: use delivery_id
-- as an idempotency key in the worker/provider when supported.
-- This migration stores no FCM credentials and does not itself call Firebase.
BEGIN;

DO $preflight$
DECLARE
    v_name TEXT;
    v_super BOOLEAN;
    v_createdb BOOLEAN;
    v_createrole BOOLEAN;
    v_replication BOOLEAN;
    v_bypass BOOLEAN;
    v_login BOOLEAN;
    v_owner_members TEXT;
    v_owner_oid OID;
BEGIN
    IF to_regclass('mottainai.api_customer_transaction_context') IS NULL
       OR to_regclass('mottainai.api_client_catalog_stores') IS NULL
       OR to_regclass('mottainai.api_client_catalog_promotions') IS NULL
       OR to_regclass('mottainai.api_client_catalog_promotion_items') IS NULL THEN
        RAISE EXCEPTION 'Apply 38_client_mobile_api.sql before migration 42';
    END IF;

    FOREACH v_name IN ARRAY ARRAY[
        'mottainai_notification_owner',
        'mottainai_notification_worker'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = v_name) THEN
            EXECUTE format(
                'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT',
                v_name
            );
        END IF;

        SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication,
               rolbypassrls, rolcanlogin
        INTO v_super, v_createdb, v_createrole, v_replication, v_bypass, v_login
        FROM pg_catalog.pg_roles
        WHERE rolname = v_name;

        IF v_super OR v_createdb OR v_createrole OR v_replication OR v_bypass OR v_login THEN
            RAISE EXCEPTION 'Role % must remain NOLOGIN and unprivileged', v_name;
        END IF;
    END LOOP;

    SELECT oid INTO v_owner_oid FROM pg_catalog.pg_roles
    WHERE rolname = 'mottainai_notification_owner';

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_auth_members
        WHERE member = v_owner_oid
    ) THEN
        RAISE EXCEPTION 'mottainai_notification_owner must not inherit another role';
    END IF;

    SELECT string_agg(member_role.rolname, ', ' ORDER BY member_role.rolname)
    INTO v_owner_members
    FROM pg_catalog.pg_auth_members membership
    JOIN pg_catalog.pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'mottainai_notification_owner'
      AND member_role.rolname <> 'avnadmin';

    IF v_owner_members IS NOT NULL THEN
        RAISE EXCEPTION 'Unexpected members of mottainai_notification_owner: %', v_owner_members;
    END IF;

    IF pg_catalog.pg_has_role(
        'mottainai_client_api', 'mottainai_notification_worker', 'MEMBER'
    ) THEN
        RAISE EXCEPTION 'The mobile-facing API role must not inherit notification worker access';
    END IF;
END;
$preflight$;

GRANT mottainai_notification_owner, mottainai_notification_worker TO CURRENT_USER;
GRANT USAGE, CREATE ON SCHEMA mottainai TO mottainai_notification_owner;
-- fn_get_current_customer_id is owned by the profile owner role from migration
-- 38. Temporarily act as that owner to grant only this context lookup to the
-- notification SECURITY DEFINER role.
GRANT mottainai_client_profile_owner TO CURRENT_USER;
SET ROLE mottainai_client_profile_owner;
GRANT EXECUTE ON FUNCTION mottainai.fn_get_current_customer_id()
    TO mottainai_notification_owner;
RESET ROLE;
GRANT SELECT (customer_id, active, deleted_at, marketing_consent)
    ON mottainai.customer TO mottainai_notification_owner;
GRANT SELECT (customer_id, active, points_balance)
    ON mottainai.loyalty_account TO mottainai_notification_owner;
-- The catalog views are owned by a separate restricted role. Grant from that
-- owner so managed migration principals do not need ownership escalation.
GRANT mottainai_client_catalog_owner TO CURRENT_USER;
SET ROLE mottainai_client_catalog_owner;
GRANT SELECT ON mottainai.api_client_catalog_stores,
    mottainai.api_client_catalog_promotions,
    mottainai.api_client_catalog_promotion_items
    TO mottainai_notification_owner;
RESET ROLE;

-- The catalog view owner must see only currently eligible offers and items.
-- RLS is enabled (not forced) so the separately owned catalog views are
-- filtered while the table owner retains normal migration/maintenance access.
ALTER TABLE mottainai.promotion ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.promotion_item ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS client_catalog_promotion_select ON mottainai.promotion;
CREATE POLICY client_catalog_promotion_select ON mottainai.promotion
    FOR SELECT TO mottainai_client_catalog_owner
    USING (
        status::TEXT = 'APPROVED'
        AND active IS TRUE
        AND deleted_at IS NULL
        AND starts_at <= CURRENT_TIMESTAMP
        AND ends_at > CURRENT_TIMESTAMP
        AND EXISTS (
            SELECT 1 FROM mottainai.retail_store store
            WHERE store.store_id = promotion.store_id
              AND store.active IS TRUE AND store.deleted_at IS NULL
        )
    );

DROP POLICY IF EXISTS client_catalog_promotion_item_select ON mottainai.promotion_item;
CREATE POLICY client_catalog_promotion_item_select ON mottainai.promotion_item
    FOR SELECT TO mottainai_client_catalog_owner
    USING (
        deleted_at IS NULL
        AND quantity_available > 0
        AND EXISTS (
            SELECT 1 FROM mottainai.product product
            WHERE product.product_id = promotion_item.product_id
              AND product.active IS TRUE
              AND product.deleted_at IS NULL
        )
        AND EXISTS (
            SELECT 1
            FROM mottainai.promotion promotion
            JOIN mottainai.retail_store store ON store.store_id = promotion.store_id
            WHERE promotion.promotion_id = promotion_item.promotion_id
              AND promotion.status::TEXT = 'APPROVED'
              AND promotion.active IS TRUE
              AND promotion.deleted_at IS NULL
              AND promotion.starts_at <= CURRENT_TIMESTAMP
              AND promotion.ends_at > CURRENT_TIMESTAMP
              AND store.active IS TRUE
              AND store.deleted_at IS NULL
        )
    );

CREATE TABLE IF NOT EXISTS mottainai.customer_notification_preference (
    customer_id INTEGER PRIMARY KEY
        REFERENCES mottainai.customer(customer_id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    radius_km SMALLINT NOT NULL DEFAULT 5 CHECK (radius_km IN (5, 10)),
    latitude DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180),
    accuracy_meters DOUBLE PRECISION CHECK (accuracy_meters BETWEEN 0 AND 10000),
    location_observed_at TIMESTAMPTZ,
    location_expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp(),
    CHECK (
        (latitude IS NULL AND longitude IS NULL
            AND location_observed_at IS NULL AND location_expires_at IS NULL)
        OR (latitude IS NOT NULL AND longitude IS NOT NULL
            AND location_observed_at IS NOT NULL
            AND location_expires_at = location_observed_at + INTERVAL '30 minutes')
    )
);

CREATE TABLE IF NOT EXISTS mottainai.customer_push_device (
    device_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL
        REFERENCES mottainai.customer(customer_id) ON DELETE CASCADE,
    fcm_token VARCHAR(4096) NOT NULL UNIQUE CHECK (btrim(fcm_token) <> ''),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp()
);

CREATE TABLE IF NOT EXISTS mottainai.customer_notification_campaign (
    campaign_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_day DATE NOT NULL,
    store_id INTEGER NOT NULL
        REFERENCES mottainai.retail_store(store_id) ON DELETE RESTRICT,
    product_id INTEGER NOT NULL
        REFERENCES mottainai.product(product_id) ON DELETE RESTRICT,
    promotion_id INTEGER NOT NULL
        REFERENCES mottainai.promotion(promotion_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp(),
    priority_until TIMESTAMPTZ NOT NULL
        DEFAULT statement_timestamp() + INTERVAL '30 minutes',
    UNIQUE (store_id, campaign_day, product_id)
);

CREATE TABLE IF NOT EXISTS mottainai.customer_notification_delivery (
    delivery_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id BIGINT NOT NULL
        REFERENCES mottainai.customer_notification_campaign(campaign_id) ON DELETE CASCADE,
    customer_id INTEGER NOT NULL
        REFERENCES mottainai.customer(customer_id) ON DELETE CASCADE,
    priority_recipient BOOLEAN NOT NULL,
    due_at TIMESTAMPTZ NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 100),
    lease_owner UUID,
    lease_until TIMESTAMPTZ,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT statement_timestamp(),
    published_at TIMESTAMPTZ,
    last_error VARCHAR(80),
    UNIQUE (campaign_id, customer_id),
    CHECK ((lease_owner IS NULL) = (lease_until IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_notification_location_fresh
    ON mottainai.customer_notification_preference(location_expires_at)
    WHERE enabled IS TRUE;
CREATE INDEX IF NOT EXISTS ix_customer_push_device_active
    ON mottainai.customer_push_device(customer_id, device_id)
    WHERE active IS TRUE;
CREATE INDEX IF NOT EXISTS ix_notification_delivery_pending
    ON mottainai.customer_notification_delivery(due_at, next_attempt_at)
    WHERE published_at IS NULL AND attempts < 100;

ALTER TABLE mottainai.customer_notification_preference
    OWNER TO mottainai_notification_owner;
ALTER TABLE mottainai.customer_push_device
    OWNER TO mottainai_notification_owner;
ALTER TABLE mottainai.customer_notification_campaign
    OWNER TO mottainai_notification_owner;
ALTER TABLE mottainai.customer_notification_delivery
    OWNER TO mottainai_notification_owner;

ALTER TABLE mottainai.customer_notification_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_notification_preference FORCE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_push_device ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_push_device FORCE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_notification_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_notification_campaign FORCE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_notification_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE mottainai.customer_notification_delivery FORCE ROW LEVEL SECURITY;

REVOKE ALL ON mottainai.customer_notification_preference,
    mottainai.customer_push_device,
    mottainai.customer_notification_campaign,
    mottainai.customer_notification_delivery FROM PUBLIC;
DROP POLICY IF EXISTS notification_preference_self
    ON mottainai.customer_notification_preference;
CREATE POLICY notification_preference_self
    ON mottainai.customer_notification_preference
    FOR ALL TO mottainai_client_api
    USING (customer_id = mottainai.fn_get_current_customer_id())
    WITH CHECK (customer_id = mottainai.fn_get_current_customer_id());
DROP POLICY IF EXISTS notification_preference_owner
    ON mottainai.customer_notification_preference;
CREATE POLICY notification_preference_owner
    ON mottainai.customer_notification_preference
    FOR ALL TO mottainai_notification_owner USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS notification_device_owner
    ON mottainai.customer_push_device;
CREATE POLICY notification_device_owner
    ON mottainai.customer_push_device
    FOR ALL TO mottainai_notification_owner USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS notification_campaign_owner
    ON mottainai.customer_notification_campaign;
CREATE POLICY notification_campaign_owner
    ON mottainai.customer_notification_campaign
    FOR ALL TO mottainai_notification_owner USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS notification_delivery_owner
    ON mottainai.customer_notification_delivery;
CREATE POLICY notification_delivery_owner
    ON mottainai.customer_notification_delivery
    FOR ALL TO mottainai_notification_owner USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS notification_customer_read ON mottainai.customer;
CREATE POLICY notification_customer_read ON mottainai.customer
    FOR SELECT TO mottainai_notification_owner
    USING (active IS TRUE AND deleted_at IS NULL AND marketing_consent IS TRUE);
DROP POLICY IF EXISTS notification_loyalty_read ON mottainai.loyalty_account;
CREATE POLICY notification_loyalty_read ON mottainai.loyalty_account
    FOR SELECT TO mottainai_notification_owner USING (active IS TRUE);

GRANT SELECT, INSERT, UPDATE
    ON mottainai.customer_notification_preference TO mottainai_client_api;
GRANT EXECUTE ON FUNCTION mottainai.fn_get_current_customer_id()
    TO mottainai_client_api;

SET ROLE mottainai_notification_owner;

-- Tokens are enrolled and revoked through the customer's transaction context;
-- token values are never directly readable by the mobile-facing database role.
CREATE OR REPLACE FUNCTION mottainai.fn_api_register_customer_push_device(
    p_fcm_token TEXT
) RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_customer_id INTEGER;
    v_device_id BIGINT;
BEGIN
    v_customer_id := mottainai.fn_get_current_customer_id();
    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Customer context is required'
            USING ERRCODE = '42501';
    END IF;
    IF p_fcm_token IS NULL OR length(btrim(p_fcm_token)) NOT BETWEEN 20 AND 4096 THEN
        RAISE EXCEPTION 'Invalid push token' USING ERRCODE = '22023';
    END IF;

    INSERT INTO mottainai.customer_push_device AS device (
        customer_id, fcm_token, active, last_seen_at, updated_at
    ) VALUES (
        v_customer_id, btrim(p_fcm_token), TRUE, statement_timestamp(), statement_timestamp()
    )
    ON CONFLICT (fcm_token) DO UPDATE
    SET customer_id = EXCLUDED.customer_id,
        active = TRUE,
        last_seen_at = statement_timestamp(),
        updated_at = statement_timestamp()
    WHERE device.customer_id = EXCLUDED.customer_id
    RETURNING device.device_id INTO v_device_id;

    IF v_device_id IS NULL THEN
        RAISE EXCEPTION 'Push token is already registered to another customer'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_device_id;
END;
$function$;

CREATE OR REPLACE FUNCTION mottainai.fn_api_revoke_customer_push_device(
    p_device_id BIGINT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
BEGIN
    IF p_device_id IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE mottainai.customer_push_device
    SET active = FALSE, updated_at = statement_timestamp()
    WHERE device_id = p_device_id
      AND customer_id = mottainai.fn_get_current_customer_id()
      AND active IS TRUE;

    RETURN FOUND;
END;
$function$;

-- Distance is computed from the customer's temporary position and the store's
-- published coordinates. A home address is never used as a substitute.
CREATE OR REPLACE FUNCTION mottainai.fn_notification_distance_km(
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_store_lat DOUBLE PRECISION,
    p_store_lon DOUBLE PRECISION
) RETURNS DOUBLE PRECISION
LANGUAGE SQL IMMUTABLE STRICT
SET search_path = pg_catalog, mottainai, pg_temp
AS $sql$
    SELECT 6371.0088 * acos(least(1.0, greatest(-1.0,
        sin(radians(p_lat)) * sin(radians(p_store_lat))
        + cos(radians(p_lat)) * cos(radians(p_store_lat))
        * cos(radians(p_store_lon - p_lon)))))
$sql$;

CREATE OR REPLACE FUNCTION mottainai.fn_notification_eligible_customers(
    p_store_id INTEGER
) RETURNS TABLE(customer_id INTEGER, points_balance INTEGER)
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $sql$
    SELECT customer.customer_id, coalesce(loyalty.points_balance, 0)
    FROM mottainai.customer_notification_preference preference
    JOIN mottainai.customer customer
      ON customer.customer_id = preference.customer_id
     AND customer.active IS TRUE
     AND customer.deleted_at IS NULL
     AND customer.marketing_consent IS TRUE
    JOIN mottainai.api_client_catalog_stores store
      ON store.id = p_store_id
    LEFT JOIN mottainai.loyalty_account loyalty
      ON loyalty.customer_id = customer.customer_id
     AND loyalty.active IS TRUE
    WHERE preference.enabled IS TRUE
      AND preference.location_expires_at > statement_timestamp()
      AND preference.location_observed_at <= statement_timestamp() + INTERVAL '30 seconds'
      AND mottainai.fn_notification_distance_km(
            preference.latitude, preference.longitude, store.latitude, store.longitude
          ) <= preference.radius_km
      AND EXISTS (
          SELECT 1 FROM mottainai.customer_push_device device
          WHERE device.customer_id = customer.customer_id AND device.active IS TRUE
      );
$sql$;

-- A trusted server-side worker claims deliveries. The mobile API role cannot
-- claim global work, view other customer IDs, or read FCM tokens. The worker
-- must poll this function; this migration does not send messages to Firebase.
CREATE OR REPLACE FUNCTION mottainai.fn_claim_customer_promotion_notifications(
    p_worker UUID,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE(
    delivery_id BIGINT,
    device_tokens TEXT[],
    promotion_id INTEGER,
    store_id INTEGER,
    product_id INTEGER,
    title TEXT,
    body TEXT,
    priority INTEGER,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
DECLARE
    v_day DATE := (statement_timestamp() AT TIME ZONE 'America/Sao_Paulo')::DATE;
    v_candidate RECORD;
    v_campaign RECORD;
BEGIN
    IF p_worker IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Invalid notification claim' USING ERRCODE = '22023';
    END IF;
    IF NOT pg_try_advisory_xact_lock(
        hashtextextended('mottainai.customer_promotion_notifications', 0)
    ) THEN
        RETURN;
    END IF;

    UPDATE mottainai.customer_notification_preference preference
    SET latitude = NULL,
        longitude = NULL,
        accuracy_meters = NULL,
        location_observed_at = NULL,
        location_expires_at = NULL,
        updated_at = statement_timestamp()
    WHERE preference.location_expires_at <= statement_timestamp();

    DELETE FROM mottainai.customer_notification_campaign
    WHERE campaign_day < v_day - 8;

    FOR v_candidate IN
        WITH best_product_offer AS (
            SELECT DISTINCT ON (promotion.store_id, item.product_id)
                promotion.store_id,
                promotion.id AS promotion_id,
                item.product_id,
                (item.original_price - item.promotional_price)
                    / NULLIF(item.original_price, 0) AS discount
            FROM mottainai.api_client_catalog_promotions promotion
            JOIN mottainai.api_client_catalog_promotion_items item
              ON item.promotion_id = promotion.id
            WHERE item.original_price > item.promotional_price
              AND EXISTS (
                  SELECT 1
                  FROM mottainai.fn_notification_eligible_customers(promotion.store_id)
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM mottainai.customer_notification_campaign campaign
                  WHERE campaign.store_id = promotion.store_id
                    AND campaign.product_id = item.product_id
                    AND campaign.campaign_day = v_day
              )
              AND (
                  SELECT count(*)
                  FROM mottainai.customer_notification_campaign campaign
                  WHERE campaign.store_id = promotion.store_id
                    AND campaign.campaign_day = v_day
              ) < 3
            ORDER BY promotion.store_id, item.product_id,
                (item.original_price - item.promotional_price)
                    / NULLIF(item.original_price, 0) DESC,
                promotion.id
        ), ranked_offer AS (
            SELECT offer.*,
                row_number() OVER (
                    PARTITION BY offer.store_id
                    ORDER BY offer.discount DESC, offer.product_id
                ) AS position
            FROM best_product_offer offer
        )
        SELECT offer.*
        FROM ranked_offer offer
        WHERE offer.position <= 3 - (
            SELECT count(*)
            FROM mottainai.customer_notification_campaign campaign
            WHERE campaign.store_id = offer.store_id
              AND campaign.campaign_day = v_day
        )
        ORDER BY offer.store_id, offer.position
        LIMIT 300
    LOOP
        INSERT INTO mottainai.customer_notification_campaign (
            campaign_day, store_id, product_id, promotion_id
        )
        SELECT v_day, v_candidate.store_id, v_candidate.product_id, v_candidate.promotion_id
        WHERE (
            SELECT count(*)
            FROM mottainai.customer_notification_campaign campaign
            WHERE campaign.store_id = v_candidate.store_id
              AND campaign.campaign_day = v_day
        ) < 3
        ON CONFLICT (store_id, campaign_day, product_id) DO NOTHING;
    END LOOP;

    FOR v_campaign IN
        SELECT campaign.*
        FROM mottainai.customer_notification_campaign campaign
        JOIN mottainai.api_client_catalog_promotions promotion
          ON promotion.id = campaign.promotion_id
        JOIN mottainai.api_client_catalog_promotion_items item
          ON item.promotion_id = promotion.id
         AND item.product_id = campaign.product_id
        WHERE campaign.campaign_day = v_day
    LOOP
        INSERT INTO mottainai.customer_notification_delivery (
            campaign_id, customer_id, priority_recipient, due_at
        )
        SELECT v_campaign.campaign_id,
            eligible.customer_id,
            eligible.position <= ceil(eligible.total_customers * 0.20),
            CASE
                WHEN eligible.position <= ceil(eligible.total_customers * 0.20)
                    THEN statement_timestamp()
                ELSE v_campaign.priority_until
            END
        FROM (
            SELECT customer.customer_id,
                row_number() OVER (
                    ORDER BY customer.points_balance DESC, customer.customer_id
                ) AS position,
                count(*) OVER () AS total_customers
            FROM mottainai.fn_notification_eligible_customers(v_campaign.store_id) customer
        ) eligible
        ON CONFLICT (campaign_id, customer_id) DO NOTHING;
    END LOOP;

    RETURN QUERY
    WITH candidates AS (
        SELECT delivery.delivery_id,
            ARRAY(
                SELECT device.fcm_token
                FROM mottainai.customer_push_device device
                WHERE device.customer_id = delivery.customer_id
                  AND device.active IS TRUE
                ORDER BY device.device_id
            ) AS device_tokens,
            promotion.id AS promotion_id,
            promotion.store_id,
            campaign.product_id,
            left(item.name, 120)::TEXT AS title,
            ('Confira esta oferta em ' || promotion.store_name || '.')::TEXT AS body,
            CASE WHEN delivery.priority_recipient THEN 3 ELSE 2 END AS priority,
            promotion.ends_at::TIMESTAMPTZ AS expires_at
        FROM mottainai.customer_notification_delivery delivery
        JOIN mottainai.customer_notification_campaign campaign
          ON campaign.campaign_id = delivery.campaign_id
         AND campaign.campaign_day = v_day
        JOIN mottainai.api_client_catalog_promotions promotion
          ON promotion.id = campaign.promotion_id
        JOIN mottainai.api_client_catalog_promotion_items item
          ON item.promotion_id = promotion.id
         AND item.product_id = campaign.product_id
        WHERE delivery.published_at IS NULL
          AND delivery.attempts < 100
          AND delivery.due_at <= statement_timestamp()
          AND delivery.next_attempt_at <= statement_timestamp()
          AND (delivery.lease_until IS NULL OR delivery.lease_until < statement_timestamp())
          AND EXISTS (
              SELECT 1
              FROM mottainai.fn_notification_eligible_customers(campaign.store_id) customer
              WHERE customer.customer_id = delivery.customer_id
          )
        ORDER BY delivery.due_at, delivery.delivery_id
        LIMIT p_limit
        FOR UPDATE OF delivery SKIP LOCKED
    ), leased AS (
        UPDATE mottainai.customer_notification_delivery delivery
        SET lease_owner = p_worker,
            lease_until = statement_timestamp() + INTERVAL '90 seconds',
            attempts = delivery.attempts + 1
        FROM candidates candidate
        WHERE delivery.delivery_id = candidate.delivery_id
        RETURNING delivery.delivery_id
    )
    SELECT leased.delivery_id,
        candidate.device_tokens,
        candidate.promotion_id,
        candidate.store_id,
        candidate.product_id,
        candidate.title,
        candidate.body,
        candidate.priority,
        candidate.expires_at
    FROM leased
    JOIN candidates candidate USING (delivery_id);
END;
$function$;

CREATE OR REPLACE FUNCTION mottainai.fn_complete_customer_promotion_notification(
    p_delivery_id BIGINT,
    p_worker UUID,
    p_published BOOLEAN,
    p_error TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, mottainai, pg_temp
AS $function$
BEGIN
    IF p_delivery_id IS NULL OR p_worker IS NULL OR p_published IS NULL THEN
        RAISE EXCEPTION 'Invalid notification completion' USING ERRCODE = '22023';
    END IF;

    UPDATE mottainai.customer_notification_delivery delivery
    SET published_at = CASE WHEN p_published THEN statement_timestamp() ELSE NULL END,
        lease_owner = NULL,
        lease_until = NULL,
        next_attempt_at = CASE
            WHEN p_published THEN delivery.next_attempt_at
            ELSE statement_timestamp() + make_interval(secs => least(
                1800,
                30 * (1 << least(greatest(delivery.attempts - 1, 0), 6))
            ))
        END,
        last_error = CASE
            WHEN p_published THEN NULL
            ELSE left(coalesce(NULLIF(btrim(p_error), ''), 'publish_failed'), 80)
        END
    WHERE delivery.delivery_id = p_delivery_id
      AND delivery.lease_owner = p_worker
      AND delivery.lease_until >= statement_timestamp()
      AND delivery.published_at IS NULL;

    RETURN FOUND;
END;
$function$;

ALTER FUNCTION mottainai.fn_api_register_customer_push_device(TEXT)
    OWNER TO mottainai_notification_owner;
ALTER FUNCTION mottainai.fn_api_revoke_customer_push_device(BIGINT)
    OWNER TO mottainai_notification_owner;
ALTER FUNCTION mottainai.fn_notification_distance_km(
    DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) OWNER TO mottainai_notification_owner;
ALTER FUNCTION mottainai.fn_notification_eligible_customers(INTEGER)
    OWNER TO mottainai_notification_owner;
ALTER FUNCTION mottainai.fn_claim_customer_promotion_notifications(UUID, INTEGER)
    OWNER TO mottainai_notification_owner;
ALTER FUNCTION mottainai.fn_complete_customer_promotion_notification(
    BIGINT, UUID, BOOLEAN, TEXT
) OWNER TO mottainai_notification_owner;

RESET ROLE;

REVOKE ALL ON FUNCTION mottainai.fn_api_register_customer_push_device(TEXT),
    mottainai.fn_api_revoke_customer_push_device(BIGINT),
    mottainai.fn_notification_distance_km(
        DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
    ),
    mottainai.fn_notification_eligible_customers(INTEGER),
    mottainai.fn_claim_customer_promotion_notifications(UUID, INTEGER),
    mottainai.fn_complete_customer_promotion_notification(BIGINT, UUID, BOOLEAN, TEXT)
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mottainai.fn_api_register_customer_push_device(TEXT),
    mottainai.fn_api_revoke_customer_push_device(BIGINT)
    TO mottainai_client_api;
GRANT EXECUTE ON FUNCTION mottainai.fn_claim_customer_promotion_notifications(UUID, INTEGER),
    mottainai.fn_complete_customer_promotion_notification(BIGINT, UUID, BOOLEAN, TEXT)
    TO mottainai_notification_worker;

REVOKE CREATE ON SCHEMA mottainai FROM mottainai_notification_owner;

DO $revoke_migration_memberships$
DECLARE
    v_role_name TEXT;
BEGIN
    FOR v_role_name IN
        SELECT granted_role.rolname
        FROM pg_catalog.pg_auth_members membership
        JOIN pg_catalog.pg_roles granted_role ON granted_role.oid = membership.roleid
        WHERE membership.member = (
                SELECT oid FROM pg_catalog.pg_roles WHERE rolname = CURRENT_USER
            )
          AND membership.grantor = (
                SELECT oid FROM pg_catalog.pg_roles WHERE rolname = CURRENT_USER
            )
          AND granted_role.rolname IN (
              'mottainai_notification_owner', 'mottainai_notification_worker',
              'mottainai_client_profile_owner',
              'mottainai_client_catalog_owner'
          )
    LOOP
        EXECUTE format('REVOKE %I FROM CURRENT_USER', v_role_name);
    END LOOP;
END;
$revoke_migration_memberships$;

INSERT INTO mottainai.schema_version(version, description, type, script, installed_by)
VALUES (
    '42',
    'Add customer offer notification preferences, campaigns, devices, and queue',
    'SQL',
    '42_customer_promotion_notifications.sql',
    CURRENT_USER
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
