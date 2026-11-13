-- Shrinkage Sentinel relational schema
-- Event/history tables never overwrite prior rows.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store (
    store_id TEXT PRIMARY KEY,
    store_code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    banner TEXT NOT NULL,
    format TEXT NOT NULL CHECK (format IN ('supercenter','neighborhood','warehouse','ecom_fc')),
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    region TEXT NOT NULL,
    timezone TEXT NOT NULL,
    opened_on TEXT NOT NULL,
    closed_on TEXT,
    status TEXT NOT NULL CHECK (status IN ('active','seasonal','closed')),
    sq_ft INTEGER NOT NULL CHECK (sq_ft > 0),
    shrink_risk_tier TEXT NOT NULL CHECK (shrink_risk_tier IN ('low','medium','high'))
);

CREATE TABLE IF NOT EXISTS sku (
    sku_id TEXT PRIMARY KEY,
    upc TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    subcategory TEXT NOT NULL,
    brand TEXT NOT NULL,
    unit_cost REAL NOT NULL CHECK (unit_cost >= 0),
    unit_retail REAL NOT NULL CHECK (unit_retail >= 0),
    uom TEXT NOT NULL,
    perishable INTEGER NOT NULL CHECK (perishable IN (0,1)),
    high_theft_risk INTEGER NOT NULL CHECK (high_theft_risk IN (0,1)),
    status TEXT NOT NULL CHECK (status IN ('active','seasonal','discontinued')),
    introduced_on TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS employee_role (
    role_id TEXT PRIMARY KEY,
    role_name TEXT NOT NULL UNIQUE,
    can_adjust_inventory INTEGER NOT NULL CHECK (can_adjust_inventory IN (0,1)),
    can_approve_transfer INTEGER NOT NULL CHECK (can_approve_transfer IN (0,1)),
    can_perform_count INTEGER NOT NULL CHECK (can_perform_count IN (0,1)),
    can_process_return INTEGER NOT NULL CHECK (can_process_return IN (0,1)),
    effective_from TEXT NOT NULL,
    effective_to TEXT
);

CREATE TABLE IF NOT EXISTS employee (
    employee_id TEXT PRIMARY KEY,
    home_store_id TEXT NOT NULL REFERENCES store(store_id),
    role_id TEXT NOT NULL REFERENCES employee_role(role_id),
    display_name TEXT NOT NULL,
    hire_date TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active','leave','terminated'))
);

CREATE TABLE IF NOT EXISTS store_sku_assortment (
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    listed_from TEXT NOT NULL,
    listed_to TEXT,
    min_on_hand INTEGER NOT NULL CHECK (min_on_hand >= 0),
    max_on_hand INTEGER NOT NULL CHECK (max_on_hand >= min_on_hand),
    PRIMARY KEY (store_id, sku_id)
);

CREATE TABLE IF NOT EXISTS shift (
    shift_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    employee_id TEXT NOT NULL REFERENCES employee(employee_id),
    role_id TEXT NOT NULL REFERENCES employee_role(role_id),
    started_at TEXT NOT NULL,
    ended_at TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('scheduled','open','closed')),
    CHECK (ended_at >= started_at)
);

CREATE TABLE IF NOT EXISTS promotion (
    promo_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    promo_type TEXT NOT NULL CHECK (promo_type IN ('markdown','bogo','percent_off')),
    start_on TEXT NOT NULL,
    end_on TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('planned','active','ended')),
    CHECK (end_on >= start_on)
);

CREATE TABLE IF NOT EXISTS promotion_sku (
    promo_id TEXT NOT NULL REFERENCES promotion(promo_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    discount_pct REAL NOT NULL CHECK (discount_pct >= 0 AND discount_pct <= 90),
    PRIMARY KEY (promo_id, sku_id)
);

CREATE TABLE IF NOT EXISTS promotion_store (
    promo_id TEXT NOT NULL REFERENCES promotion(promo_id),
    store_id TEXT NOT NULL REFERENCES store(store_id),
    PRIMARY KEY (promo_id, store_id)
);

CREATE TABLE IF NOT EXISTS inventory_movement (
    movement_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    movement_type TEXT NOT NULL,
    qty INTEGER NOT NULL,
    unit_cost REAL NOT NULL,
    occurred_at TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    shift_id TEXT REFERENCES shift(shift_id),
    employee_id TEXT REFERENCES employee(employee_id),
    role_id TEXT REFERENCES employee_role(role_id),
    reason_code TEXT,
    reference_id TEXT,
    counterpart_store_id TEXT REFERENCES store(store_id),
    source_system TEXT NOT NULL,
    is_voided INTEGER NOT NULL DEFAULT 0 CHECK (is_voided IN (0,1))
);

CREATE TABLE IF NOT EXISTS return_event (
    return_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    qty INTEGER NOT NULL CHECK (qty > 0),
    original_sale_movement_id TEXT REFERENCES inventory_movement(movement_id),
    return_movement_id TEXT NOT NULL REFERENCES inventory_movement(movement_id),
    reason TEXT NOT NULL CHECK (reason IN ('damaged','unwanted','wrong_item','warranty')),
    condition TEXT NOT NULL CHECK (condition IN ('sellable','salvage','destroy')),
    returned_at TEXT NOT NULL,
    employee_id TEXT NOT NULL REFERENCES employee(employee_id)
);

CREATE TABLE IF NOT EXISTS cycle_count (
    count_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    counted_qty INTEGER NOT NULL CHECK (counted_qty >= 0),
    expected_qty INTEGER NOT NULL,
    variance_qty INTEGER NOT NULL,
    variance_value REAL NOT NULL,
    counted_at TEXT NOT NULL,
    snapshot_as_of TEXT NOT NULL,
    employee_id TEXT NOT NULL REFERENCES employee(employee_id),
    role_id TEXT NOT NULL REFERENCES employee_role(role_id),
    shift_id TEXT REFERENCES shift(shift_id),
    status TEXT NOT NULL CHECK (status IN ('draft','submitted','reviewed','posted')),
    posted_movement_id TEXT REFERENCES inventory_movement(movement_id)
);

CREATE TABLE IF NOT EXISTS balance_event (
    balance_event_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT NOT NULL REFERENCES sku(sku_id),
    as_of TEXT NOT NULL,
    on_hand INTEGER NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('opening','count_post','daily_close')),
    related_count_id TEXT REFERENCES cycle_count(count_id)
);

CREATE TABLE IF NOT EXISTS shrinkage_alert (
    alert_id TEXT PRIMARY KEY,
    store_id TEXT NOT NULL REFERENCES store(store_id),
    sku_id TEXT REFERENCES sku(sku_id),
    alert_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('low','medium','high','critical')),
    score REAL NOT NULL,
    evidence_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('open','investigating','closed_benign','closed_confirmed')),
    related_count_id TEXT REFERENCES cycle_count(count_id),
    related_movement_id TEXT REFERENCES inventory_movement(movement_id)
);

CREATE TABLE IF NOT EXISTS investigation (
    investigation_id TEXT PRIMARY KEY,
    opened_at TEXT NOT NULL,
    closed_at TEXT,
    owner_role_id TEXT NOT NULL REFERENCES employee_role(role_id),
    outcome TEXT NOT NULL,
    notes TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('open','closed'))
);

CREATE TABLE IF NOT EXISTS investigation_alert (
    investigation_id TEXT NOT NULL REFERENCES investigation(investigation_id),
    alert_id TEXT NOT NULL REFERENCES shrinkage_alert(alert_id),
    PRIMARY KEY (investigation_id, alert_id)
);
