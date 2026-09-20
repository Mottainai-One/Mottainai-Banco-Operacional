SET search_path TO mottainai_analytics, public;

-- IDs abaixo preservam as chaves de origem. Nao ha FKs entre bancos fisicos.
CREATE TABLE IF NOT EXISTS fact_sales (
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    sale_timestamp      TIMESTAMPTZ NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    employee_id         BIGINT,
    customer_id         BIGINT,
    item_count          INTEGER NOT NULL DEFAULT 0,
    gross_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    net_amount          NUMERIC(15,2) NOT NULL,
    status              VARCHAR(30) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sale_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS fact_sales_default
    PARTITION OF fact_sales DEFAULT;

CREATE TABLE IF NOT EXISTS fact_sale_item (
    sale_item_id        BIGINT NOT NULL,
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    quantity            NUMERIC(15,3) NOT NULL,
    unit_price          NUMERIC(15,4) NOT NULL,
    discount_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    subtotal            NUMERIC(15,2) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sale_item_id, sale_date)
) PARTITION BY RANGE (sale_date);

CREATE TABLE IF NOT EXISTS fact_sale_item_default
    PARTITION OF fact_sale_item DEFAULT;

CREATE TABLE IF NOT EXISTS fact_sale_payment (
    payment_id          BIGINT PRIMARY KEY,
    sale_id             BIGINT NOT NULL,
    sale_date           DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    payment_method      VARCHAR(40) NOT NULL,
    amount              NUMERIC(15,2) NOT NULL,
    installments        SMALLINT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_inventory_movement (
    movement_id         BIGINT NOT NULL,
    movement_date       DATE NOT NULL,
    movement_timestamp  TIMESTAMPTZ NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    inventory_id        BIGINT,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    employee_id         BIGINT,
    movement_type       VARCHAR(40) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    unit_cost           NUMERIC(15,4),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (movement_id, movement_date)
) PARTITION BY RANGE (movement_date);

CREATE TABLE IF NOT EXISTS fact_inventory_movement_default
    PARTITION OF fact_inventory_movement DEFAULT;

CREATE TABLE IF NOT EXISTS fact_inventory_snapshot (
    snapshot_date       DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT NOT NULL,
    inventory_type      VARCHAR(30) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    reserved_quantity   NUMERIC(15,3) NOT NULL DEFAULT 0,
    average_cost        NUMERIC(15,4),
    expiration_date     DATE,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (snapshot_date, store_id, product_id, batch_id, inventory_type)
) PARTITION BY RANGE (snapshot_date);

CREATE TABLE IF NOT EXISTS fact_inventory_snapshot_default
    PARTITION OF fact_inventory_snapshot DEFAULT;

CREATE TABLE IF NOT EXISTS fact_purchase_order (
    purchase_order_id   BIGINT NOT NULL,
    order_date          DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    supplier_id         BIGINT,
    employee_id         BIGINT,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    total_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (purchase_order_id, order_date)
);

CREATE TABLE IF NOT EXISTS fact_receiving (
    receiving_id        BIGINT PRIMARY KEY,
    purchase_order_id   BIGINT,
    receiving_date      DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    supplier_id         BIGINT,
    employee_id         BIGINT,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_promotion_result (
    promotion_id        BIGINT NOT NULL,
    result_date         DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    units_sold          NUMERIC(15,3) NOT NULL DEFAULT 0,
    gross_revenue       NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_granted    NUMERIC(15,2) NOT NULL DEFAULT 0,
    avoided_loss        NUMERIC(15,2) NOT NULL DEFAULT 0,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (promotion_id, result_date, store_id, product_id)
);

CREATE TABLE IF NOT EXISTS fact_loss_destination (
    loss_id             BIGINT PRIMARY KEY,
    loss_date           DATE NOT NULL,
    company_id          BIGINT NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    batch_id            BIGINT,
    destination_type    VARCHAR(40) NOT NULL,
    quantity            NUMERIC(15,3) NOT NULL,
    estimated_value     NUMERIC(15,2),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_transfer (
    transfer_id         BIGINT PRIMARY KEY,
    transfer_date       DATE NOT NULL,
    source_store_id     BIGINT NOT NULL,
    destination_store_id BIGINT NOT NULL,
    status              VARCHAR(30) NOT NULL,
    item_count          INTEGER NOT NULL DEFAULT 0,
    total_cost          NUMERIC(15,2),
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE fact_transfer IS
    'Fato completo de transferencia entre lojas, no grao de uma transferencia.';

CREATE TABLE IF NOT EXISTS fact_replenishment (
    replenishment_id    BIGINT PRIMARY KEY,
    replenishment_date  DATE NOT NULL,
    store_id            BIGINT NOT NULL,
    product_id          BIGINT NOT NULL,
    requested_quantity  NUMERIC(15,3) NOT NULL,
    supplied_quantity   NUMERIC(15,3),
    status              VARCHAR(30) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fact_loyalty (
    loyalty_event_id    BIGINT PRIMARY KEY,
    event_date          DATE NOT NULL,
    customer_id         BIGINT NOT NULL,
    store_id            BIGINT,
    event_type          VARCHAR(30) NOT NULL,
    points_delta        INTEGER NOT NULL,
    balance_after       INTEGER,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
