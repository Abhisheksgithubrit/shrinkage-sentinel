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

BEGIN;
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000001', 'S0001', 'Austin Supercenter 001', 'FlexWarehouse', 'supercenter', 'Austin', 'TX', 'Southwest', 'America/Chicago', '2024-12-31', NULL, 'active', 18137, 'medium');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000002', 'S0002', 'Denver Neighborhood 002', 'HarborGo', 'neighborhood', 'Denver', 'CO', 'West', 'America/Chicago', '2024-12-30', NULL, 'active', 18274, 'high');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000003', 'S0003', 'Columbus Warehouse 003', 'YottaMart', 'warehouse', 'Columbus', 'OH', 'Midwest', 'America/Chicago', '2024-12-29', NULL, 'active', 18411, 'low');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000004', 'S0004', 'Atlanta Ecom Fc 004', 'FlexWarehouse', 'ecom_fc', 'Atlanta', 'GA', 'Southeast', 'America/Chicago', '2024-12-28', NULL, 'active', 18548, 'medium');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000005', 'S0005', 'Buffalo Supercenter 005', 'HarborGo', 'supercenter', 'Buffalo', 'NY', 'Northeast', 'America/Chicago', '2024-12-27', NULL, 'active', 18685, 'high');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000006', 'S0006', 'Boise Neighborhood 006', 'YottaMart', 'neighborhood', 'Boise', 'ID', 'West', 'America/Chicago', '2024-12-26', NULL, 'active', 18822, 'low');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000007', 'S0007', 'Tampa Warehouse 007', 'FlexWarehouse', 'warehouse', 'Tampa', 'FL', 'Southeast', 'America/Chicago', '2024-12-25', NULL, 'active', 18959, 'medium');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000008', 'S0008', 'Omaha Ecom Fc 008', 'HarborGo', 'ecom_fc', 'Omaha', 'NE', 'Midwest', 'America/Chicago', '2024-12-24', NULL, 'active', 19096, 'high');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000009', 'S0009', 'Raleigh Supercenter 009', 'YottaMart', 'supercenter', 'Raleigh', 'NC', 'Southeast', 'America/Chicago', '2024-12-23', NULL, 'active', 19233, 'low');
INSERT INTO store (store_id, store_code, name, banner, format, city, state, region, timezone, opened_on, closed_on, status, sq_ft, shrink_risk_tier) VALUES ('STORE-000010', 'S0010', 'Portland Neighborhood 010', 'FlexWarehouse', 'neighborhood', 'Portland', 'OR', 'West', 'America/Chicago', '2024-12-22', NULL, 'active', 19370, 'medium');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000001', '700000000001', 'Grocery Beverages Item 0001', 'Grocery', 'Beverages', 'Cedar&Co', 1.17, 1.64, 'EA', 0, 0, 'active', '2025-12-31');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000002', '700000000002', 'Health First Aid Item 0002', 'Health', 'First Aid', 'Voltara', 1.54, 2.39, 'EA', 0, 0, 'active', '2025-12-30');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000003', '700000000003', 'Electronics Accessories Item 0003', 'Electronics', 'Accessories', 'Harbor Home', 1.91, 3.25, 'EA', 0, 1, 'active', '2025-12-29');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000004', '700000000004', 'Apparel Seasonal Item 0004', 'Apparel', 'Seasonal', 'Lumen', 2.28, 4.22, 'EA', 0, 0, 'active', '2025-12-28');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000005', '700000000005', 'Home Decor Item 0005', 'Home', 'Decor', 'Peakform', 2.65, 3.31, 'EA', 0, 0, 'active', '2025-12-27');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000006', '700000000006', 'Beauty Skin Item 0006', 'Beauty', 'Skin', 'Nimbus', 3.02, 4.23, 'EA', 0, 1, 'active', '2025-12-26');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000007', '700000000007', 'Automotive Interior Item 0007', 'Automotive', 'Interior', 'Northline', 3.39, 5.25, 'EA', 0, 0, 'active', '2025-12-25');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000008', '700000000008', 'Toys Games Item 0008', 'Toys', 'Games', 'Cedar&Co', 3.76, 6.39, 'EA', 0, 0, 'active', '2025-12-24');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000009', '700000000009', 'Grocery Beverages Item 0009', 'Grocery', 'Beverages', 'Voltara', 4.13, 7.64, 'EA', 0, 0, 'active', '2025-12-23');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000010', '700000000010', 'Health Vitamins Item 0010', 'Health', 'Vitamins', 'Harbor Home', 4.5, 5.62, 'EA', 0, 0, 'active', '2025-12-22');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000011', '700000000011', 'Electronics Charging Item 0011', 'Electronics', 'Charging', 'Lumen', 4.87, 6.82, 'EA', 0, 0, 'active', '2025-12-21');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000012', '700000000012', 'Apparel Basics Item 0012', 'Apparel', 'Basics', 'Peakform', 5.24, 8.12, 'EA', 0, 0, 'active', '2025-12-20');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000013', '700000000013', 'Home Storage Item 0013', 'Home', 'Storage', 'Nimbus', 5.61, 9.54, 'EA', 0, 0, 'active', '2025-12-19');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000014', '700000000014', 'Beauty Fragrance Item 0014', 'Beauty', 'Fragrance', 'Northline', 5.98, 11.06, 'EA', 0, 0, 'active', '2025-12-18');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000015', '700000000015', 'Automotive Care Item 0015', 'Automotive', 'Care', 'Cedar&Co', 6.35, 7.94, 'EA', 0, 0, 'active', '2025-12-17');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000016', '700000000016', 'Toys Outdoor Item 0016', 'Toys', 'Outdoor', 'Voltara', 6.72, 9.41, 'EA', 0, 0, 'active', '2025-12-16');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000017', '700000000017', 'Grocery Beverages Item 0017', 'Grocery', 'Beverages', 'Harbor Home', 7.09, 10.99, 'EA', 0, 0, 'active', '2025-12-15');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000018', '700000000018', 'Health OTC Item 0018', 'Health', 'OTC', 'Lumen', 7.46, 12.68, 'EA', 0, 1, 'active', '2025-12-14');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000019', '700000000019', 'Electronics Audio Item 0019', 'Electronics', 'Audio', 'Peakform', 7.83, 14.49, 'EA', 0, 0, 'active', '2025-12-13');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000020', '700000000020', 'Apparel Footwear Item 0020', 'Apparel', 'Footwear', 'Nimbus', 8.2, 10.25, 'EA', 0, 0, 'active', '2025-12-12');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000021', '700000000021', 'Home Kitchen Item 0021', 'Home', 'Kitchen', 'Northline', 8.57, 12.0, 'EA', 0, 0, 'active', '2025-12-11');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000022', '700000000022', 'Beauty Hair Item 0022', 'Beauty', 'Hair', 'Cedar&Co', 8.94, 13.86, 'EA', 0, 0, 'active', '2025-12-10');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000023', '700000000023', 'Automotive Tools Item 0023', 'Automotive', 'Tools', 'Voltara', 9.31, 15.83, 'EA', 0, 0, 'active', '2025-12-09');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000024', '700000000024', 'Toys Building Item 0024', 'Toys', 'Building', 'Harbor Home', 9.68, 17.91, 'EA', 0, 0, 'active', '2025-12-08');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000025', '700000000025', 'Grocery Beverages Item 0025', 'Grocery', 'Beverages', 'Lumen', 10.05, 12.56, 'EA', 0, 0, 'active', '2025-12-07');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000026', '700000000026', 'Health First Aid Item 0026', 'Health', 'First Aid', 'Peakform', 10.42, 14.59, 'EA', 0, 0, 'active', '2025-12-06');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000027', '700000000027', 'Electronics Accessories Item 0027', 'Electronics', 'Accessories', 'Nimbus', 10.79, 16.72, 'EA', 0, 1, 'active', '2025-12-05');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000028', '700000000028', 'Apparel Seasonal Item 0028', 'Apparel', 'Seasonal', 'Northline', 11.16, 18.97, 'EA', 0, 0, 'active', '2025-12-04');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000029', '700000000029', 'Home Decor Item 0029', 'Home', 'Decor', 'Cedar&Co', 11.53, 21.33, 'EA', 0, 0, 'active', '2025-12-03');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000030', '700000000030', 'Beauty Skin Item 0030', 'Beauty', 'Skin', 'Voltara', 11.9, 14.88, 'EA', 0, 1, 'active', '2025-12-02');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000031', '700000000031', 'Automotive Interior Item 0031', 'Automotive', 'Interior', 'Harbor Home', 12.27, 17.18, 'EA', 0, 0, 'active', '2025-12-01');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000032', '700000000032', 'Toys Games Item 0032', 'Toys', 'Games', 'Lumen', 12.64, 19.59, 'EA', 0, 0, 'active', '2025-11-30');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000033', '700000000033', 'Grocery Beverages Item 0033', 'Grocery', 'Beverages', 'Peakform', 13.01, 22.12, 'EA', 0, 0, 'active', '2025-11-29');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000034', '700000000034', 'Health Vitamins Item 0034', 'Health', 'Vitamins', 'Nimbus', 13.38, 24.75, 'EA', 0, 0, 'active', '2025-11-28');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000035', '700000000035', 'Electronics Charging Item 0035', 'Electronics', 'Charging', 'Northline', 13.75, 17.19, 'EA', 0, 0, 'active', '2025-11-27');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000036', '700000000036', 'Apparel Basics Item 0036', 'Apparel', 'Basics', 'Cedar&Co', 14.12, 19.77, 'EA', 0, 0, 'active', '2025-11-26');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000037', '700000000037', 'Home Storage Item 0037', 'Home', 'Storage', 'Voltara', 14.49, 22.46, 'EA', 0, 0, 'active', '2025-11-25');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000038', '700000000038', 'Beauty Fragrance Item 0038', 'Beauty', 'Fragrance', 'Harbor Home', 14.86, 25.26, 'EA', 0, 0, 'active', '2025-11-24');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000039', '700000000039', 'Automotive Care Item 0039', 'Automotive', 'Care', 'Lumen', 15.23, 28.18, 'EA', 0, 0, 'active', '2025-11-23');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000040', '700000000040', 'Toys Outdoor Item 0040', 'Toys', 'Outdoor', 'Peakform', 15.6, 19.5, 'EA', 0, 0, 'active', '2025-11-22');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000041', '700000000041', 'Grocery Beverages Item 0041', 'Grocery', 'Beverages', 'Nimbus', 15.97, 22.36, 'EA', 0, 0, 'seasonal', '2025-11-21');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000042', '700000000042', 'Health OTC Item 0042', 'Health', 'OTC', 'Northline', 16.34, 25.33, 'EA', 0, 1, 'active', '2025-11-20');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000043', '700000000043', 'Electronics Audio Item 0043', 'Electronics', 'Audio', 'Cedar&Co', 16.71, 28.41, 'EA', 0, 0, 'active', '2025-11-19');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000044', '700000000044', 'Apparel Footwear Item 0044', 'Apparel', 'Footwear', 'Voltara', 17.08, 31.6, 'EA', 0, 0, 'active', '2025-11-18');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000045', '700000000045', 'Home Kitchen Item 0045', 'Home', 'Kitchen', 'Harbor Home', 17.45, 21.81, 'EA', 0, 0, 'active', '2025-11-17');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000046', '700000000046', 'Beauty Hair Item 0046', 'Beauty', 'Hair', 'Lumen', 17.82, 24.95, 'EA', 0, 0, 'active', '2025-11-16');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000047', '700000000047', 'Automotive Tools Item 0047', 'Automotive', 'Tools', 'Peakform', 18.19, 28.19, 'EA', 0, 0, 'active', '2025-11-15');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000048', '700000000048', 'Toys Building Item 0048', 'Toys', 'Building', 'Nimbus', 18.56, 31.55, 'EA', 0, 0, 'active', '2025-11-14');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000049', '700000000049', 'Grocery Beverages Item 0049', 'Grocery', 'Beverages', 'Northline', 18.93, 35.02, 'EA', 0, 0, 'active', '2025-11-13');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000050', '700000000050', 'Health First Aid Item 0050', 'Health', 'First Aid', 'Cedar&Co', 19.3, 24.12, 'EA', 0, 0, 'active', '2025-11-12');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000051', '700000000051', 'Electronics Accessories Item 0051', 'Electronics', 'Accessories', 'Voltara', 19.67, 27.54, 'EA', 0, 1, 'active', '2025-11-11');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000052', '700000000052', 'Apparel Seasonal Item 0052', 'Apparel', 'Seasonal', 'Harbor Home', 20.04, 31.06, 'EA', 0, 0, 'active', '2025-11-10');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000053', '700000000053', 'Home Decor Item 0053', 'Home', 'Decor', 'Lumen', 20.41, 34.7, 'EA', 0, 0, 'active', '2025-11-09');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000054', '700000000054', 'Beauty Skin Item 0054', 'Beauty', 'Skin', 'Peakform', 20.78, 38.44, 'EA', 0, 1, 'active', '2025-11-08');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000055', '700000000055', 'Automotive Interior Item 0055', 'Automotive', 'Interior', 'Nimbus', 21.15, 26.44, 'EA', 0, 0, 'active', '2025-11-07');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000056', '700000000056', 'Toys Games Item 0056', 'Toys', 'Games', 'Northline', 21.52, 30.13, 'EA', 0, 0, 'active', '2025-11-06');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000057', '700000000057', 'Grocery Beverages Item 0057', 'Grocery', 'Beverages', 'Cedar&Co', 21.89, 33.93, 'EA', 0, 0, 'active', '2025-11-05');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000058', '700000000058', 'Health Vitamins Item 0058', 'Health', 'Vitamins', 'Voltara', 22.26, 37.84, 'EA', 0, 0, 'active', '2025-11-04');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000059', '700000000059', 'Electronics Charging Item 0059', 'Electronics', 'Charging', 'Harbor Home', 22.63, 41.87, 'EA', 0, 0, 'active', '2025-11-03');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000060', '700000000060', 'Apparel Basics Item 0060', 'Apparel', 'Basics', 'Lumen', 23.0, 28.75, 'EA', 0, 0, 'active', '2025-11-02');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000061', '700000000061', 'Home Storage Item 0061', 'Home', 'Storage', 'Peakform', 23.37, 32.72, 'EA', 0, 0, 'active', '2025-11-01');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000062', '700000000062', 'Beauty Fragrance Item 0062', 'Beauty', 'Fragrance', 'Nimbus', 23.74, 36.8, 'EA', 0, 0, 'active', '2025-10-31');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000063', '700000000063', 'Automotive Care Item 0063', 'Automotive', 'Care', 'Northline', 24.11, 40.99, 'EA', 0, 0, 'active', '2025-10-30');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000064', '700000000064', 'Toys Outdoor Item 0064', 'Toys', 'Outdoor', 'Cedar&Co', 24.48, 45.29, 'EA', 0, 0, 'active', '2025-10-29');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000065', '700000000065', 'Grocery Beverages Item 0065', 'Grocery', 'Beverages', 'Voltara', 24.85, 31.06, 'EA', 0, 0, 'active', '2025-10-28');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000066', '700000000066', 'Health OTC Item 0066', 'Health', 'OTC', 'Harbor Home', 25.22, 35.31, 'EA', 0, 1, 'active', '2025-10-27');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000067', '700000000067', 'Electronics Audio Item 0067', 'Electronics', 'Audio', 'Lumen', 25.59, 39.66, 'EA', 0, 0, 'active', '2025-10-26');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000068', '700000000068', 'Apparel Footwear Item 0068', 'Apparel', 'Footwear', 'Peakform', 25.96, 44.13, 'EA', 0, 0, 'active', '2025-10-25');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000069', '700000000069', 'Home Kitchen Item 0069', 'Home', 'Kitchen', 'Nimbus', 26.33, 48.71, 'EA', 0, 0, 'active', '2025-10-24');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000070', '700000000070', 'Beauty Hair Item 0070', 'Beauty', 'Hair', 'Northline', 26.7, 33.38, 'EA', 0, 0, 'active', '2025-10-23');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000071', '700000000071', 'Automotive Tools Item 0071', 'Automotive', 'Tools', 'Cedar&Co', 27.07, 37.9, 'EA', 0, 0, 'active', '2025-10-22');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000072', '700000000072', 'Toys Building Item 0072', 'Toys', 'Building', 'Voltara', 27.44, 42.53, 'EA', 0, 0, 'active', '2025-10-21');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000073', '700000000073', 'Grocery Beverages Item 0073', 'Grocery', 'Beverages', 'Harbor Home', 27.81, 47.28, 'EA', 0, 0, 'active', '2025-10-20');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000074', '700000000074', 'Health First Aid Item 0074', 'Health', 'First Aid', 'Lumen', 28.18, 52.13, 'EA', 0, 0, 'active', '2025-10-19');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000075', '700000000075', 'Electronics Accessories Item 0075', 'Electronics', 'Accessories', 'Peakform', 28.55, 35.69, 'EA', 0, 1, 'active', '2025-10-18');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000076', '700000000076', 'Apparel Seasonal Item 0076', 'Apparel', 'Seasonal', 'Nimbus', 28.92, 40.49, 'EA', 0, 0, 'active', '2025-10-17');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000077', '700000000077', 'Home Decor Item 0077', 'Home', 'Decor', 'Northline', 29.29, 45.4, 'EA', 0, 0, 'active', '2025-10-16');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000078', '700000000078', 'Beauty Skin Item 0078', 'Beauty', 'Skin', 'Cedar&Co', 29.66, 50.42, 'EA', 0, 1, 'active', '2025-10-15');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000079', '700000000079', 'Automotive Interior Item 0079', 'Automotive', 'Interior', 'Voltara', 30.03, 55.56, 'EA', 0, 0, 'active', '2025-10-14');
INSERT INTO sku (sku_id, upc, name, category, subcategory, brand, unit_cost, unit_retail, uom, perishable, high_theft_risk, status, introduced_on) VALUES ('SKU-000080', '700000000080', 'Toys Games Item 0080', 'Toys', 'Games', 'Harbor Home', 30.4, 38.0, 'EA', 0, 0, 'active', '2025-10-13');
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000001', 'cashier', 0, 0, 0, 1, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000002', 'stocker', 1, 0, 1, 0, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000003', 'store_manager', 1, 1, 1, 1, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000004', 'loss_prevention', 1, 0, 1, 0, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000005', 'merchandiser', 0, 0, 1, 0, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000006', 'warehouse_picker', 0, 1, 0, 0, '2025-01-01', NULL);
INSERT INTO employee_role (role_id, role_name, can_adjust_inventory, can_approve_transfer, can_perform_count, can_process_return, effective_from, effective_to) VALUES ('ROLE-000007', 'cycle_counter', 0, 0, 1, 0, '2025-01-01', NULL);
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000001', 'STORE-000001', 'ROLE-000001', 'Jordan Nair', '2025-12-01', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000002', 'STORE-000002', 'ROLE-000002', 'Riley Brooks', '2025-11-30', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000003', 'STORE-000003', 'ROLE-000003', 'Cameron Vega', '2025-11-29', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000004', 'STORE-000004', 'ROLE-000004', 'Quinn Singh', '2025-11-28', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000005', 'STORE-000005', 'ROLE-000005', 'Morgan Cole', '2025-11-27', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000006', 'STORE-000006', 'ROLE-000006', 'Sage Diaz', '2025-11-26', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000007', 'STORE-000007', 'ROLE-000007', 'Reese Shah', '2025-11-25', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000008', 'STORE-000008', 'ROLE-000001', 'Drew Nguyen', '2025-11-24', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000009', 'STORE-000009', 'ROLE-000002', 'Parker Patel', '2025-11-23', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000010', 'STORE-000010', 'ROLE-000003', 'Avery Hale', '2025-11-22', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000011', 'STORE-000001', 'ROLE-000004', 'Jordan Nair', '2025-11-21', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000012', 'STORE-000002', 'ROLE-000005', 'Riley Brooks', '2025-11-20', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000013', 'STORE-000003', 'ROLE-000006', 'Cameron Vega', '2025-11-19', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000014', 'STORE-000004', 'ROLE-000007', 'Quinn Singh', '2025-11-18', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000015', 'STORE-000005', 'ROLE-000001', 'Morgan Cole', '2025-11-17', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000016', 'STORE-000006', 'ROLE-000002', 'Sage Diaz', '2025-11-16', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000017', 'STORE-000007', 'ROLE-000003', 'Reese Shah', '2025-11-15', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000018', 'STORE-000008', 'ROLE-000004', 'Drew Nguyen', '2025-11-14', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000019', 'STORE-000009', 'ROLE-000005', 'Parker Patel', '2025-11-13', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000020', 'STORE-000010', 'ROLE-000006', 'Avery Hale', '2025-11-12', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000021', 'STORE-000001', 'ROLE-000007', 'Jordan Nair', '2025-11-11', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000022', 'STORE-000002', 'ROLE-000001', 'Riley Brooks', '2025-11-10', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000023', 'STORE-000003', 'ROLE-000002', 'Cameron Vega', '2025-11-09', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000024', 'STORE-000004', 'ROLE-000003', 'Quinn Singh', '2025-11-08', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000025', 'STORE-000005', 'ROLE-000004', 'Morgan Cole', '2025-11-07', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000026', 'STORE-000006', 'ROLE-000005', 'Sage Diaz', '2025-11-06', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000027', 'STORE-000007', 'ROLE-000006', 'Reese Shah', '2025-11-05', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000028', 'STORE-000008', 'ROLE-000007', 'Drew Nguyen', '2025-11-04', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000029', 'STORE-000009', 'ROLE-000001', 'Parker Patel', '2025-11-03', 'leave');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000030', 'STORE-000010', 'ROLE-000002', 'Avery Hale', '2025-11-02', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000031', 'STORE-000001', 'ROLE-000003', 'Jordan Nair', '2025-11-01', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000032', 'STORE-000002', 'ROLE-000004', 'Riley Brooks', '2025-10-31', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000033', 'STORE-000003', 'ROLE-000005', 'Cameron Vega', '2025-10-30', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000034', 'STORE-000004', 'ROLE-000006', 'Quinn Singh', '2025-10-29', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000035', 'STORE-000005', 'ROLE-000007', 'Morgan Cole', '2025-10-28', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000036', 'STORE-000006', 'ROLE-000001', 'Sage Diaz', '2025-10-27', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000037', 'STORE-000007', 'ROLE-000002', 'Reese Shah', '2025-10-26', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000038', 'STORE-000008', 'ROLE-000003', 'Drew Nguyen', '2025-10-25', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000039', 'STORE-000009', 'ROLE-000004', 'Parker Patel', '2025-10-24', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000040', 'STORE-000010', 'ROLE-000005', 'Avery Hale', '2025-10-23', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000041', 'STORE-000001', 'ROLE-000006', 'Jordan Nair', '2025-10-22', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000042', 'STORE-000002', 'ROLE-000007', 'Riley Brooks', '2025-10-21', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000043', 'STORE-000003', 'ROLE-000001', 'Cameron Vega', '2025-10-20', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000044', 'STORE-000004', 'ROLE-000002', 'Quinn Singh', '2025-10-19', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000045', 'STORE-000005', 'ROLE-000003', 'Morgan Cole', '2025-10-18', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000046', 'STORE-000006', 'ROLE-000004', 'Sage Diaz', '2025-10-17', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000047', 'STORE-000007', 'ROLE-000005', 'Reese Shah', '2025-10-16', 'active');
INSERT INTO employee (employee_id, home_store_id, role_id, display_name, hire_date, status) VALUES ('EMP-000048', 'STORE-000008', 'ROLE-000006', 'Drew Nguyen', '2025-10-15', 'active');
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000008', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000009', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000010', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000011', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000012', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000013', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000014', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000015', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000016', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000017', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000018', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000019', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000020', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000021', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000001', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000015', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000016', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000017', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000018', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000019', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000020', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000021', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000040', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000041', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000002', 'SKU-000042', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000040', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000041', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000042', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000043', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000044', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000045', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000046', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000047', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000048', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000003', 'SKU-000049', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000040', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000041', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000042', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000043', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000044', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000045', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000046', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000047', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000048', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000049', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000050', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000051', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000052', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000053', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000054', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000055', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000004', 'SKU-000056', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000040', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000041', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000042', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000043', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000044', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000045', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000046', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000047', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000048', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000049', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000050', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000051', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000052', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000053', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000054', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000055', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000056', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000057', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000058', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000059', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000060', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000061', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000062', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000005', 'SKU-000063', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000043', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000044', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000045', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000046', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000047', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000048', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000049', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000050', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000051', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000052', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000053', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000054', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000055', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000056', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000057', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000058', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000059', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000060', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000061', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000062', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000063', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000064', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000065', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000066', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000067', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000068', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000069', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000006', 'SKU-000070', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000050', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000051', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000052', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000053', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000054', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000055', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000056', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000057', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000058', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000059', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000060', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000061', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000062', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000063', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000064', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000065', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000066', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000067', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000068', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000069', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000070', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000071', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000072', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000073', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000074', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000075', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000076', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000007', 'SKU-000077', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000005', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000006', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000007', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000008', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000009', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000010', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000011', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000012', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000013', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000014', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000015', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000016', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000017', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000018', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000019', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000020', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000021', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000008', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000012', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000013', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000014', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000015', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000016', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000017', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000018', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000019', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000020', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000021', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000009', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000019', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000020', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000021', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000022', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000023', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000024', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000025', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000026', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000027', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000028', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000029', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000030', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000031', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000032', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000033', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000034', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000035', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000036', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000037', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000038', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000039', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000040', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000041', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000042', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000043', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000044', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000045', '2025-06-01', NULL, 2, 80);
INSERT INTO store_sku_assortment (store_id, sku_id, listed_from, listed_to, min_on_hand, max_on_hand) VALUES ('STORE-000010', 'SKU-000046', '2025-06-01', NULL, 2, 80);
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000001', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-01 06:00:00', '2026-01-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000002', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-02 14:00:00', '2026-01-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000003', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-03 22:00:00', '2026-01-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000004', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-04 06:00:00', '2026-01-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000005', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-05 14:00:00', '2026-01-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000006', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-06 22:00:00', '2026-01-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000007', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-07 06:00:00', '2026-01-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000008', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-08 14:00:00', '2026-01-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000009', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-09 22:00:00', '2026-01-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000010', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-10 06:00:00', '2026-01-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000011', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-11 14:00:00', '2026-01-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000012', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-12 22:00:00', '2026-01-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000013', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-13 06:00:00', '2026-01-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000014', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-14 14:00:00', '2026-01-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000015', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-15 22:00:00', '2026-01-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000016', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-16 06:00:00', '2026-01-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000017', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-17 14:00:00', '2026-01-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000018', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-18 22:00:00', '2026-01-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000019', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-01-19 06:00:00', '2026-01-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000020', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-01-20 14:00:00', '2026-01-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000021', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-21 22:00:00', '2026-01-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000022', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-22 06:00:00', '2026-01-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000023', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-23 14:00:00', '2026-01-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000024', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-24 22:00:00', '2026-01-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000025', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-25 06:00:00', '2026-01-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000026', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-26 14:00:00', '2026-01-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000027', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-27 22:00:00', '2026-01-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000028', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-28 06:00:00', '2026-01-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000029', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-29 14:00:00', '2026-01-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000030', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-30 22:00:00', '2026-01-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000031', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-31 06:00:00', '2026-01-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000032', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-01 14:00:00', '2026-02-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000033', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-02 22:00:00', '2026-02-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000034', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-03 06:00:00', '2026-02-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000035', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-04 14:00:00', '2026-02-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000036', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-05 22:00:00', '2026-02-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000037', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-06 06:00:00', '2026-02-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000038', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-07 14:00:00', '2026-02-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000039', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-08 22:00:00', '2026-02-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000040', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-02-09 06:00:00', '2026-02-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000041', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-10 14:00:00', '2026-02-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000042', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-11 22:00:00', '2026-02-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000043', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-12 06:00:00', '2026-02-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000044', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-13 14:00:00', '2026-02-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000045', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-14 22:00:00', '2026-02-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000046', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-15 06:00:00', '2026-02-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000047', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-16 14:00:00', '2026-02-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000048', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-17 22:00:00', '2026-02-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000049', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-02-18 06:00:00', '2026-02-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000050', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-02-19 14:00:00', '2026-02-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000051', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-20 22:00:00', '2026-02-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000052', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-21 06:00:00', '2026-02-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000053', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-22 14:00:00', '2026-02-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000054', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-23 22:00:00', '2026-02-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000055', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-24 06:00:00', '2026-02-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000056', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-25 14:00:00', '2026-02-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000057', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-26 22:00:00', '2026-02-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000058', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-27 06:00:00', '2026-02-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000059', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-28 14:00:00', '2026-02-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000060', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-01 22:00:00', '2026-03-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000061', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-02 06:00:00', '2026-03-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000062', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-03 14:00:00', '2026-03-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000063', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-04 22:00:00', '2026-03-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000064', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-05 06:00:00', '2026-03-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000065', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-06 14:00:00', '2026-03-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000066', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-07 22:00:00', '2026-03-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000067', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-08 06:00:00', '2026-03-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000068', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-09 14:00:00', '2026-03-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000069', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-10 22:00:00', '2026-03-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000070', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-11 06:00:00', '2026-03-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000071', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-12 14:00:00', '2026-03-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000072', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-13 22:00:00', '2026-03-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000073', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-14 06:00:00', '2026-03-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000074', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-15 14:00:00', '2026-03-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000075', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-16 22:00:00', '2026-03-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000076', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-17 06:00:00', '2026-03-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000077', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-18 14:00:00', '2026-03-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000078', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-19 22:00:00', '2026-03-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000079', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-03-20 06:00:00', '2026-03-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000080', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-21 14:00:00', '2026-03-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000081', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-22 22:00:00', '2026-03-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000082', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-23 06:00:00', '2026-03-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000083', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-24 14:00:00', '2026-03-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000084', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-25 22:00:00', '2026-03-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000085', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-26 06:00:00', '2026-03-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000086', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-27 14:00:00', '2026-03-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000087', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-28 22:00:00', '2026-03-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000088', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-29 06:00:00', '2026-03-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000089', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-30 14:00:00', '2026-03-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000090', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-31 22:00:00', '2026-04-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000091', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-01 06:00:00', '2026-04-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000092', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-02 14:00:00', '2026-04-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000093', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-03 22:00:00', '2026-04-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000094', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-04 06:00:00', '2026-04-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000095', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-05 14:00:00', '2026-04-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000096', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-06 22:00:00', '2026-04-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000097', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-07 06:00:00', '2026-04-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000098', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-08 14:00:00', '2026-04-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000099', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-09 22:00:00', '2026-04-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000100', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-10 06:00:00', '2026-04-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000101', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-11 14:00:00', '2026-04-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000102', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-12 22:00:00', '2026-04-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000103', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-13 06:00:00', '2026-04-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000104', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-14 14:00:00', '2026-04-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000105', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-15 22:00:00', '2026-04-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000106', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-16 06:00:00', '2026-04-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000107', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-17 14:00:00', '2026-04-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000108', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-18 22:00:00', '2026-04-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000109', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-04-19 06:00:00', '2026-04-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000110', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-04-20 14:00:00', '2026-04-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000111', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-21 22:00:00', '2026-04-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000112', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-22 06:00:00', '2026-04-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000113', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-23 14:00:00', '2026-04-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000114', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-24 22:00:00', '2026-04-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000115', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-25 06:00:00', '2026-04-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000116', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-26 14:00:00', '2026-04-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000117', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-27 22:00:00', '2026-04-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000118', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-28 06:00:00', '2026-04-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000119', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-29 14:00:00', '2026-04-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000120', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-30 22:00:00', '2026-05-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000121', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-01 06:00:00', '2026-05-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000122', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-02 14:00:00', '2026-05-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000123', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-03 22:00:00', '2026-05-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000124', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-04 06:00:00', '2026-05-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000125', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-05 14:00:00', '2026-05-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000126', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-06 22:00:00', '2026-05-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000127', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-07 06:00:00', '2026-05-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000128', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-08 14:00:00', '2026-05-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000129', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-09 22:00:00', '2026-05-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000130', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-10 06:00:00', '2026-05-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000131', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-11 14:00:00', '2026-05-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000132', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-12 22:00:00', '2026-05-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000133', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-13 06:00:00', '2026-05-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000134', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-14 14:00:00', '2026-05-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000135', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-15 22:00:00', '2026-05-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000136', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-16 06:00:00', '2026-05-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000137', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-17 14:00:00', '2026-05-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000138', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-18 22:00:00', '2026-05-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000139', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-05-19 06:00:00', '2026-05-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000140', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-05-20 14:00:00', '2026-05-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000141', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-21 22:00:00', '2026-05-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000142', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-22 06:00:00', '2026-05-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000143', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-23 14:00:00', '2026-05-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000144', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-24 22:00:00', '2026-05-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000145', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-25 06:00:00', '2026-05-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000146', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-26 14:00:00', '2026-05-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000147', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-27 22:00:00', '2026-05-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000148', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-28 06:00:00', '2026-05-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000149', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-29 14:00:00', '2026-05-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000150', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-30 22:00:00', '2026-05-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000151', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-31 06:00:00', '2026-05-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000152', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-01 14:00:00', '2026-06-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000153', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-02 22:00:00', '2026-06-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000154', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-03 06:00:00', '2026-06-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000155', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-04 14:00:00', '2026-06-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000156', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-05 22:00:00', '2026-06-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000157', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-06 06:00:00', '2026-06-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000158', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-07 14:00:00', '2026-06-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000159', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-08 22:00:00', '2026-06-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000160', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-09 06:00:00', '2026-06-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000161', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-10 14:00:00', '2026-06-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000162', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-11 22:00:00', '2026-06-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000163', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-12 06:00:00', '2026-06-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000164', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-13 14:00:00', '2026-06-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000165', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-14 22:00:00', '2026-06-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000166', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-15 06:00:00', '2026-06-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000167', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-16 14:00:00', '2026-06-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000168', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-17 22:00:00', '2026-06-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000169', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-06-18 06:00:00', '2026-06-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000170', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-06-19 14:00:00', '2026-06-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000171', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-20 22:00:00', '2026-06-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000172', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-21 06:00:00', '2026-06-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000173', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-22 14:00:00', '2026-06-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000174', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-23 22:00:00', '2026-06-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000175', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-24 06:00:00', '2026-06-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000176', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-25 14:00:00', '2026-06-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000177', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-26 22:00:00', '2026-06-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000178', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-27 06:00:00', '2026-06-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000179', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-28 14:00:00', '2026-06-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000180', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-29 22:00:00', '2026-06-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000181', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-30 06:00:00', '2026-06-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000182', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-01 14:00:00', '2026-07-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000183', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-02 22:00:00', '2026-07-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000184', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-03 06:00:00', '2026-07-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000185', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-04 14:00:00', '2026-07-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000186', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-05 22:00:00', '2026-07-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000187', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-06 06:00:00', '2026-07-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000188', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-07 14:00:00', '2026-07-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000189', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-08 22:00:00', '2026-07-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000190', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-09 06:00:00', '2026-07-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000191', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-10 14:00:00', '2026-07-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000192', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-11 22:00:00', '2026-07-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000193', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-12 06:00:00', '2026-07-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000194', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-13 14:00:00', '2026-07-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000195', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-14 22:00:00', '2026-07-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000196', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-15 06:00:00', '2026-07-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000197', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-16 14:00:00', '2026-07-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000198', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-17 22:00:00', '2026-07-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000199', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-07-18 06:00:00', '2026-07-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000200', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-07-19 14:00:00', '2026-07-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000201', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-20 22:00:00', '2026-07-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000202', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-21 06:00:00', '2026-07-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000203', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-22 14:00:00', '2026-07-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000204', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-23 22:00:00', '2026-07-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000205', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-24 06:00:00', '2026-07-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000206', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-25 14:00:00', '2026-07-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000207', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-26 22:00:00', '2026-07-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000208', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-27 06:00:00', '2026-07-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000209', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-28 14:00:00', '2026-07-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000210', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-29 22:00:00', '2026-07-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000211', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-30 06:00:00', '2026-07-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000212', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-31 14:00:00', '2026-07-31 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000213', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-01 22:00:00', '2026-08-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000214', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-02 06:00:00', '2026-08-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000215', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-03 14:00:00', '2026-08-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000216', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-04 22:00:00', '2026-08-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000217', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-05 06:00:00', '2026-08-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000218', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-06 14:00:00', '2026-08-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000219', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-07 22:00:00', '2026-08-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000220', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-08 06:00:00', '2026-08-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000221', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-09 14:00:00', '2026-08-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000222', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-10 22:00:00', '2026-08-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000223', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-11 06:00:00', '2026-08-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000224', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-12 14:00:00', '2026-08-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000225', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-13 22:00:00', '2026-08-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000226', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-14 06:00:00', '2026-08-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000227', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-15 14:00:00', '2026-08-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000228', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-16 22:00:00', '2026-08-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000229', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-08-17 06:00:00', '2026-08-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000230', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-08-18 14:00:00', '2026-08-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000231', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-19 22:00:00', '2026-08-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000232', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-20 06:00:00', '2026-08-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000233', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-21 14:00:00', '2026-08-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000234', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-22 22:00:00', '2026-08-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000235', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-23 06:00:00', '2026-08-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000236', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-24 14:00:00', '2026-08-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000237', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-25 22:00:00', '2026-08-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000238', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-26 06:00:00', '2026-08-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000239', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-27 14:00:00', '2026-08-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000240', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-28 22:00:00', '2026-08-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000241', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-29 06:00:00', '2026-08-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000242', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-30 14:00:00', '2026-08-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000243', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-31 22:00:00', '2026-09-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000244', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-01 06:00:00', '2026-09-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000245', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-02 14:00:00', '2026-09-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000246', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-03 22:00:00', '2026-09-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000247', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-04 06:00:00', '2026-09-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000248', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-05 14:00:00', '2026-09-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000249', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-06 22:00:00', '2026-09-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000250', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-07 06:00:00', '2026-09-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000251', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-08 14:00:00', '2026-09-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000252', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-09 22:00:00', '2026-09-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000253', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-10 06:00:00', '2026-09-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000254', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-11 14:00:00', '2026-09-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000255', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-12 22:00:00', '2026-09-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000256', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-13 06:00:00', '2026-09-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000257', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-14 14:00:00', '2026-09-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000258', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-15 22:00:00', '2026-09-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000259', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-09-16 06:00:00', '2026-09-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000260', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-09-17 14:00:00', '2026-09-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000261', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-18 22:00:00', '2026-09-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000262', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-19 06:00:00', '2026-09-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000263', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-20 14:00:00', '2026-09-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000264', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-21 22:00:00', '2026-09-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000265', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-22 06:00:00', '2026-09-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000266', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-23 14:00:00', '2026-09-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000267', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-24 22:00:00', '2026-09-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000268', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-25 06:00:00', '2026-09-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000269', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-26 14:00:00', '2026-09-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000270', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-27 22:00:00', '2026-09-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000271', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-28 06:00:00', '2026-09-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000272', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-29 14:00:00', '2026-09-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000273', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-30 22:00:00', '2026-10-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000274', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-10-01 06:00:00', '2026-10-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000275', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-10-02 14:00:00', '2026-10-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000276', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-10-03 22:00:00', '2026-10-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000277', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-10-04 06:00:00', '2026-10-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000278', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-10-05 14:00:00', '2026-10-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000279', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-10-06 22:00:00', '2026-10-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000280', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-10-07 06:00:00', '2026-10-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000281', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-01 14:00:00', '2026-01-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000282', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-02 22:00:00', '2026-01-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000283', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-03 06:00:00', '2026-01-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000284', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-04 14:00:00', '2026-01-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000285', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-05 22:00:00', '2026-01-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000286', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-06 06:00:00', '2026-01-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000287', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-07 14:00:00', '2026-01-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000288', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-08 22:00:00', '2026-01-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000289', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-09 06:00:00', '2026-01-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000290', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-10 14:00:00', '2026-01-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000291', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-11 22:00:00', '2026-01-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000292', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-12 06:00:00', '2026-01-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000293', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-13 14:00:00', '2026-01-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000294', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-14 22:00:00', '2026-01-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000295', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-15 06:00:00', '2026-01-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000296', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-16 14:00:00', '2026-01-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000297', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-17 22:00:00', '2026-01-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000298', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-18 06:00:00', '2026-01-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000299', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-01-19 14:00:00', '2026-01-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000300', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-01-20 22:00:00', '2026-01-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000301', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-21 06:00:00', '2026-01-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000302', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-22 14:00:00', '2026-01-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000303', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-23 22:00:00', '2026-01-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000304', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-24 06:00:00', '2026-01-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000305', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-25 14:00:00', '2026-01-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000306', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-26 22:00:00', '2026-01-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000307', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-27 06:00:00', '2026-01-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000308', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-28 14:00:00', '2026-01-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000309', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-29 22:00:00', '2026-01-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000310', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-30 06:00:00', '2026-01-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000311', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-31 14:00:00', '2026-01-31 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000312', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-01 22:00:00', '2026-02-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000313', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-02 06:00:00', '2026-02-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000314', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-03 14:00:00', '2026-02-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000315', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-04 22:00:00', '2026-02-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000316', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-05 06:00:00', '2026-02-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000317', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-06 14:00:00', '2026-02-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000318', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-07 22:00:00', '2026-02-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000319', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-08 06:00:00', '2026-02-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000320', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-02-09 14:00:00', '2026-02-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000321', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-10 22:00:00', '2026-02-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000322', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-11 06:00:00', '2026-02-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000323', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-12 14:00:00', '2026-02-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000324', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-13 22:00:00', '2026-02-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000325', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-14 06:00:00', '2026-02-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000326', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-15 14:00:00', '2026-02-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000327', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-16 22:00:00', '2026-02-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000328', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-17 06:00:00', '2026-02-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000329', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-02-18 14:00:00', '2026-02-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000330', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-02-19 22:00:00', '2026-02-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000331', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-20 06:00:00', '2026-02-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000332', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-21 14:00:00', '2026-02-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000333', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-22 22:00:00', '2026-02-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000334', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-23 06:00:00', '2026-02-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000335', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-24 14:00:00', '2026-02-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000336', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-25 22:00:00', '2026-02-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000337', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-26 06:00:00', '2026-02-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000338', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-27 14:00:00', '2026-02-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000339', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-28 22:00:00', '2026-03-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000340', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-01 06:00:00', '2026-03-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000341', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-02 14:00:00', '2026-03-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000342', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-03 22:00:00', '2026-03-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000343', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-04 06:00:00', '2026-03-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000344', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-05 14:00:00', '2026-03-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000345', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-06 22:00:00', '2026-03-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000346', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-07 06:00:00', '2026-03-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000347', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-08 14:00:00', '2026-03-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000348', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-09 22:00:00', '2026-03-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000349', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-10 06:00:00', '2026-03-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000350', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-11 14:00:00', '2026-03-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000351', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-12 22:00:00', '2026-03-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000352', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-13 06:00:00', '2026-03-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000353', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-14 14:00:00', '2026-03-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000354', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-15 22:00:00', '2026-03-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000355', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-16 06:00:00', '2026-03-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000356', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-17 14:00:00', '2026-03-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000357', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-18 22:00:00', '2026-03-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000358', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-19 06:00:00', '2026-03-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000359', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-03-20 14:00:00', '2026-03-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000360', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-21 22:00:00', '2026-03-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000361', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-22 06:00:00', '2026-03-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000362', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-23 14:00:00', '2026-03-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000363', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-24 22:00:00', '2026-03-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000364', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-25 06:00:00', '2026-03-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000365', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-26 14:00:00', '2026-03-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000366', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-27 22:00:00', '2026-03-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000367', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-28 06:00:00', '2026-03-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000368', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-29 14:00:00', '2026-03-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000369', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-30 22:00:00', '2026-03-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000370', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-31 06:00:00', '2026-03-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000371', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-01 14:00:00', '2026-04-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000372', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-02 22:00:00', '2026-04-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000373', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-03 06:00:00', '2026-04-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000374', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-04 14:00:00', '2026-04-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000375', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-05 22:00:00', '2026-04-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000376', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-06 06:00:00', '2026-04-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000377', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-07 14:00:00', '2026-04-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000378', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-08 22:00:00', '2026-04-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000379', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-09 06:00:00', '2026-04-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000380', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-10 14:00:00', '2026-04-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000381', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-11 22:00:00', '2026-04-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000382', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-12 06:00:00', '2026-04-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000383', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-13 14:00:00', '2026-04-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000384', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-14 22:00:00', '2026-04-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000385', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-15 06:00:00', '2026-04-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000386', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-16 14:00:00', '2026-04-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000387', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-17 22:00:00', '2026-04-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000388', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-18 06:00:00', '2026-04-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000389', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-04-19 14:00:00', '2026-04-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000390', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-04-20 22:00:00', '2026-04-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000391', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-21 06:00:00', '2026-04-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000392', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-22 14:00:00', '2026-04-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000393', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-23 22:00:00', '2026-04-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000394', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-24 06:00:00', '2026-04-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000395', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-25 14:00:00', '2026-04-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000396', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-26 22:00:00', '2026-04-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000397', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-27 06:00:00', '2026-04-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000398', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-28 14:00:00', '2026-04-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000399', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-29 22:00:00', '2026-04-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000400', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-30 06:00:00', '2026-04-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000401', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-01 14:00:00', '2026-05-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000402', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-02 22:00:00', '2026-05-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000403', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-03 06:00:00', '2026-05-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000404', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-04 14:00:00', '2026-05-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000405', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-05 22:00:00', '2026-05-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000406', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-06 06:00:00', '2026-05-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000407', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-07 14:00:00', '2026-05-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000408', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-08 22:00:00', '2026-05-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000409', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-09 06:00:00', '2026-05-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000410', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-10 14:00:00', '2026-05-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000411', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-11 22:00:00', '2026-05-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000412', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-12 06:00:00', '2026-05-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000413', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-13 14:00:00', '2026-05-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000414', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-14 22:00:00', '2026-05-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000415', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-15 06:00:00', '2026-05-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000416', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-16 14:00:00', '2026-05-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000417', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-17 22:00:00', '2026-05-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000418', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-18 06:00:00', '2026-05-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000419', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-05-19 14:00:00', '2026-05-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000420', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-05-20 22:00:00', '2026-05-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000421', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-21 06:00:00', '2026-05-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000422', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-22 14:00:00', '2026-05-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000423', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-23 22:00:00', '2026-05-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000424', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-24 06:00:00', '2026-05-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000425', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-25 14:00:00', '2026-05-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000426', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-26 22:00:00', '2026-05-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000427', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-27 06:00:00', '2026-05-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000428', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-28 14:00:00', '2026-05-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000429', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-29 22:00:00', '2026-05-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000430', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-30 06:00:00', '2026-05-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000431', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-31 14:00:00', '2026-05-31 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000432', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-01 22:00:00', '2026-06-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000433', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-02 06:00:00', '2026-06-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000434', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-03 14:00:00', '2026-06-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000435', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-04 22:00:00', '2026-06-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000436', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-05 06:00:00', '2026-06-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000437', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-06 14:00:00', '2026-06-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000438', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-07 22:00:00', '2026-06-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000439', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-08 06:00:00', '2026-06-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000440', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-09 14:00:00', '2026-06-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000441', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-10 22:00:00', '2026-06-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000442', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-11 06:00:00', '2026-06-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000443', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-12 14:00:00', '2026-06-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000444', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-13 22:00:00', '2026-06-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000445', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-14 06:00:00', '2026-06-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000446', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-15 14:00:00', '2026-06-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000447', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-16 22:00:00', '2026-06-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000448', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-17 06:00:00', '2026-06-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000449', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-06-18 14:00:00', '2026-06-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000450', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-06-19 22:00:00', '2026-06-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000451', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-20 06:00:00', '2026-06-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000452', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-21 14:00:00', '2026-06-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000453', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-22 22:00:00', '2026-06-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000454', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-23 06:00:00', '2026-06-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000455', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-24 14:00:00', '2026-06-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000456', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-25 22:00:00', '2026-06-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000457', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-26 06:00:00', '2026-06-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000458', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-27 14:00:00', '2026-06-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000459', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-28 22:00:00', '2026-06-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000460', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-29 06:00:00', '2026-06-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000461', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-30 14:00:00', '2026-06-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000462', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-01 22:00:00', '2026-07-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000463', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-02 06:00:00', '2026-07-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000464', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-03 14:00:00', '2026-07-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000465', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-04 22:00:00', '2026-07-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000466', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-05 06:00:00', '2026-07-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000467', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-06 14:00:00', '2026-07-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000468', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-07 22:00:00', '2026-07-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000469', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-08 06:00:00', '2026-07-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000470', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-09 14:00:00', '2026-07-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000471', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-10 22:00:00', '2026-07-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000472', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-11 06:00:00', '2026-07-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000473', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-12 14:00:00', '2026-07-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000474', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-13 22:00:00', '2026-07-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000475', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-14 06:00:00', '2026-07-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000476', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-15 14:00:00', '2026-07-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000477', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-16 22:00:00', '2026-07-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000478', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-17 06:00:00', '2026-07-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000479', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-07-18 14:00:00', '2026-07-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000480', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-07-19 22:00:00', '2026-07-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000481', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-20 06:00:00', '2026-07-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000482', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-21 14:00:00', '2026-07-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000483', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-22 22:00:00', '2026-07-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000484', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-23 06:00:00', '2026-07-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000485', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-24 14:00:00', '2026-07-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000486', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-25 22:00:00', '2026-07-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000487', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-26 06:00:00', '2026-07-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000488', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-27 14:00:00', '2026-07-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000489', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-28 22:00:00', '2026-07-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000490', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-29 06:00:00', '2026-07-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000491', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-30 14:00:00', '2026-07-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000492', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-31 22:00:00', '2026-08-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000493', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-01 06:00:00', '2026-08-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000494', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-02 14:00:00', '2026-08-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000495', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-03 22:00:00', '2026-08-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000496', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-04 06:00:00', '2026-08-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000497', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-05 14:00:00', '2026-08-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000498', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-06 22:00:00', '2026-08-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000499', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-07 06:00:00', '2026-08-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000500', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-08 14:00:00', '2026-08-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000501', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-09 22:00:00', '2026-08-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000502', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-10 06:00:00', '2026-08-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000503', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-11 14:00:00', '2026-08-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000504', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-12 22:00:00', '2026-08-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000505', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-13 06:00:00', '2026-08-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000506', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-14 14:00:00', '2026-08-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000507', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-15 22:00:00', '2026-08-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000508', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-16 06:00:00', '2026-08-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000509', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-08-17 14:00:00', '2026-08-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000510', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-08-18 22:00:00', '2026-08-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000511', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-19 06:00:00', '2026-08-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000512', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-20 14:00:00', '2026-08-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000513', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-21 22:00:00', '2026-08-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000514', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-22 06:00:00', '2026-08-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000515', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-23 14:00:00', '2026-08-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000516', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-24 22:00:00', '2026-08-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000517', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-25 06:00:00', '2026-08-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000518', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-26 14:00:00', '2026-08-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000519', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-27 22:00:00', '2026-08-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000520', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-28 06:00:00', '2026-08-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000521', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-29 14:00:00', '2026-08-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000522', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-30 22:00:00', '2026-08-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000523', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-31 06:00:00', '2026-08-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000524', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-01 14:00:00', '2026-09-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000525', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-02 22:00:00', '2026-09-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000526', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-03 06:00:00', '2026-09-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000527', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-04 14:00:00', '2026-09-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000528', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-05 22:00:00', '2026-09-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000529', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-06 06:00:00', '2026-09-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000530', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-07 14:00:00', '2026-09-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000531', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-08 22:00:00', '2026-09-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000532', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-09 06:00:00', '2026-09-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000533', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-10 14:00:00', '2026-09-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000534', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-11 22:00:00', '2026-09-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000535', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-12 06:00:00', '2026-09-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000536', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-13 14:00:00', '2026-09-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000537', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-14 22:00:00', '2026-09-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000538', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-15 06:00:00', '2026-09-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000539', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-09-16 14:00:00', '2026-09-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000540', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-09-17 22:00:00', '2026-09-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000541', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-18 06:00:00', '2026-09-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000542', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-19 14:00:00', '2026-09-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000543', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-20 22:00:00', '2026-09-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000544', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-21 06:00:00', '2026-09-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000545', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-22 14:00:00', '2026-09-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000546', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-23 22:00:00', '2026-09-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000547', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-24 06:00:00', '2026-09-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000548', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-25 14:00:00', '2026-09-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000549', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-26 22:00:00', '2026-09-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000550', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-27 06:00:00', '2026-09-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000551', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-28 14:00:00', '2026-09-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000552', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-29 22:00:00', '2026-09-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000553', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-30 06:00:00', '2026-09-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000554', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-10-01 14:00:00', '2026-10-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000555', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-10-02 22:00:00', '2026-10-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000556', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-10-03 06:00:00', '2026-10-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000557', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-10-04 14:00:00', '2026-10-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000558', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-10-05 22:00:00', '2026-10-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000559', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-10-06 06:00:00', '2026-10-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000560', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-10-07 14:00:00', '2026-10-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000561', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-01 22:00:00', '2026-01-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000562', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-02 06:00:00', '2026-01-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000563', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-03 14:00:00', '2026-01-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000564', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-04 22:00:00', '2026-01-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000565', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-05 06:00:00', '2026-01-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000566', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-06 14:00:00', '2026-01-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000567', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-07 22:00:00', '2026-01-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000568', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-08 06:00:00', '2026-01-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000569', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-09 14:00:00', '2026-01-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000570', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-10 22:00:00', '2026-01-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000571', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-11 06:00:00', '2026-01-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000572', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-12 14:00:00', '2026-01-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000573', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-13 22:00:00', '2026-01-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000574', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-14 06:00:00', '2026-01-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000575', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-15 14:00:00', '2026-01-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000576', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-16 22:00:00', '2026-01-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000577', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-17 06:00:00', '2026-01-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000578', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-18 14:00:00', '2026-01-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000579', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-01-19 22:00:00', '2026-01-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000580', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-01-20 06:00:00', '2026-01-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000581', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-21 14:00:00', '2026-01-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000582', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-22 22:00:00', '2026-01-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000583', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-23 06:00:00', '2026-01-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000584', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-24 14:00:00', '2026-01-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000585', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-25 22:00:00', '2026-01-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000586', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-26 06:00:00', '2026-01-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000587', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-27 14:00:00', '2026-01-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000588', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-28 22:00:00', '2026-01-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000589', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-29 06:00:00', '2026-01-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000590', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-30 14:00:00', '2026-01-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000591', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-31 22:00:00', '2026-02-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000592', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-01 06:00:00', '2026-02-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000593', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-02 14:00:00', '2026-02-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000594', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-03 22:00:00', '2026-02-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000595', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-04 06:00:00', '2026-02-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000596', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-05 14:00:00', '2026-02-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000597', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-06 22:00:00', '2026-02-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000598', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-07 06:00:00', '2026-02-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000599', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-08 14:00:00', '2026-02-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000600', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-02-09 22:00:00', '2026-02-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000601', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-10 06:00:00', '2026-02-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000602', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-11 14:00:00', '2026-02-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000603', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-12 22:00:00', '2026-02-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000604', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-13 06:00:00', '2026-02-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000605', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-14 14:00:00', '2026-02-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000606', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-15 22:00:00', '2026-02-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000607', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-16 06:00:00', '2026-02-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000608', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-17 14:00:00', '2026-02-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000609', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-02-18 22:00:00', '2026-02-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000610', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-02-19 06:00:00', '2026-02-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000611', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-20 14:00:00', '2026-02-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000612', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-21 22:00:00', '2026-02-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000613', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-22 06:00:00', '2026-02-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000614', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-23 14:00:00', '2026-02-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000615', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-24 22:00:00', '2026-02-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000616', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-25 06:00:00', '2026-02-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000617', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-26 14:00:00', '2026-02-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000618', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-27 22:00:00', '2026-02-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000619', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-28 06:00:00', '2026-02-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000620', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-01 14:00:00', '2026-03-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000621', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-02 22:00:00', '2026-03-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000622', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-03 06:00:00', '2026-03-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000623', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-04 14:00:00', '2026-03-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000624', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-05 22:00:00', '2026-03-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000625', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-06 06:00:00', '2026-03-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000626', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-07 14:00:00', '2026-03-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000627', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-08 22:00:00', '2026-03-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000628', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-09 06:00:00', '2026-03-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000629', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-10 14:00:00', '2026-03-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000630', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-11 22:00:00', '2026-03-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000631', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-12 06:00:00', '2026-03-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000632', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-13 14:00:00', '2026-03-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000633', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-14 22:00:00', '2026-03-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000634', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-15 06:00:00', '2026-03-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000635', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-16 14:00:00', '2026-03-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000636', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-17 22:00:00', '2026-03-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000637', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-18 06:00:00', '2026-03-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000638', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-19 14:00:00', '2026-03-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000639', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-03-20 22:00:00', '2026-03-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000640', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-21 06:00:00', '2026-03-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000641', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-03-22 14:00:00', '2026-03-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000642', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-03-23 22:00:00', '2026-03-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000643', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-03-24 06:00:00', '2026-03-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000644', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-03-25 14:00:00', '2026-03-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000645', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-03-26 22:00:00', '2026-03-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000646', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-03-27 06:00:00', '2026-03-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000647', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-03-28 14:00:00', '2026-03-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000648', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-03-29 22:00:00', '2026-03-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000649', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-03-30 06:00:00', '2026-03-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000650', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-03-31 14:00:00', '2026-03-31 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000651', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-01 22:00:00', '2026-04-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000652', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-02 06:00:00', '2026-04-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000653', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-03 14:00:00', '2026-04-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000654', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-04 22:00:00', '2026-04-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000655', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-05 06:00:00', '2026-04-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000656', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-06 14:00:00', '2026-04-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000657', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-07 22:00:00', '2026-04-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000658', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-08 06:00:00', '2026-04-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000659', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-09 14:00:00', '2026-04-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000660', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-10 22:00:00', '2026-04-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000661', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-11 06:00:00', '2026-04-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000662', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-12 14:00:00', '2026-04-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000663', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-13 22:00:00', '2026-04-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000664', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-14 06:00:00', '2026-04-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000665', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-15 14:00:00', '2026-04-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000666', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-16 22:00:00', '2026-04-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000667', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-17 06:00:00', '2026-04-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000668', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-18 14:00:00', '2026-04-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000669', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-04-19 22:00:00', '2026-04-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000670', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-04-20 06:00:00', '2026-04-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000671', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-04-21 14:00:00', '2026-04-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000672', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-04-22 22:00:00', '2026-04-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000673', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-04-23 06:00:00', '2026-04-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000674', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-04-24 14:00:00', '2026-04-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000675', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-04-25 22:00:00', '2026-04-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000676', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-04-26 06:00:00', '2026-04-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000677', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-04-27 14:00:00', '2026-04-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000678', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-04-28 22:00:00', '2026-04-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000679', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-04-29 06:00:00', '2026-04-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000680', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-04-30 14:00:00', '2026-04-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000681', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-01 22:00:00', '2026-05-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000682', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-02 06:00:00', '2026-05-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000683', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-03 14:00:00', '2026-05-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000684', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-04 22:00:00', '2026-05-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000685', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-05 06:00:00', '2026-05-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000686', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-06 14:00:00', '2026-05-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000687', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-07 22:00:00', '2026-05-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000688', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-08 06:00:00', '2026-05-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000689', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-09 14:00:00', '2026-05-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000690', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-10 22:00:00', '2026-05-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000691', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-11 06:00:00', '2026-05-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000692', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-12 14:00:00', '2026-05-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000693', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-13 22:00:00', '2026-05-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000694', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-14 06:00:00', '2026-05-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000695', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-15 14:00:00', '2026-05-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000696', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-16 22:00:00', '2026-05-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000697', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-17 06:00:00', '2026-05-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000698', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-18 14:00:00', '2026-05-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000699', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-05-19 22:00:00', '2026-05-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000700', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-05-20 06:00:00', '2026-05-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000701', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-21 14:00:00', '2026-05-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000702', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-05-22 22:00:00', '2026-05-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000703', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-05-23 06:00:00', '2026-05-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000704', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-05-24 14:00:00', '2026-05-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000705', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-05-25 22:00:00', '2026-05-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000706', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-05-26 06:00:00', '2026-05-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000707', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-05-27 14:00:00', '2026-05-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000708', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-05-28 22:00:00', '2026-05-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000709', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-05-29 06:00:00', '2026-05-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000710', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-05-30 14:00:00', '2026-05-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000711', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-05-31 22:00:00', '2026-06-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000712', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-01 06:00:00', '2026-06-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000713', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-02 14:00:00', '2026-06-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000714', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-03 22:00:00', '2026-06-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000715', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-04 06:00:00', '2026-06-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000716', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-05 14:00:00', '2026-06-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000717', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-06 22:00:00', '2026-06-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000718', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-07 06:00:00', '2026-06-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000719', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-08 14:00:00', '2026-06-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000720', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-09 22:00:00', '2026-06-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000721', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-10 06:00:00', '2026-06-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000722', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-11 14:00:00', '2026-06-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000723', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-12 22:00:00', '2026-06-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000724', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-13 06:00:00', '2026-06-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000725', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-14 14:00:00', '2026-06-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000726', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-15 22:00:00', '2026-06-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000727', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-16 06:00:00', '2026-06-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000728', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-17 14:00:00', '2026-06-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000729', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-06-18 22:00:00', '2026-06-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000730', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-06-19 06:00:00', '2026-06-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000731', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-20 14:00:00', '2026-06-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000732', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-06-21 22:00:00', '2026-06-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000733', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-06-22 06:00:00', '2026-06-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000734', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-06-23 14:00:00', '2026-06-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000735', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-06-24 22:00:00', '2026-06-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000736', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-06-25 06:00:00', '2026-06-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000737', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-06-26 14:00:00', '2026-06-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000738', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-06-27 22:00:00', '2026-06-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000739', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-06-28 06:00:00', '2026-06-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000740', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-06-29 14:00:00', '2026-06-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000741', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-06-30 22:00:00', '2026-07-01 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000742', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-01 06:00:00', '2026-07-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000743', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-02 14:00:00', '2026-07-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000744', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-03 22:00:00', '2026-07-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000745', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-04 06:00:00', '2026-07-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000746', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-05 14:00:00', '2026-07-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000747', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-06 22:00:00', '2026-07-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000748', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-07 06:00:00', '2026-07-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000749', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-08 14:00:00', '2026-07-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000750', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-09 22:00:00', '2026-07-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000751', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-10 06:00:00', '2026-07-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000752', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-11 14:00:00', '2026-07-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000753', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-12 22:00:00', '2026-07-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000754', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-13 06:00:00', '2026-07-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000755', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-14 14:00:00', '2026-07-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000756', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-15 22:00:00', '2026-07-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000757', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-16 06:00:00', '2026-07-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000758', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-17 14:00:00', '2026-07-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000759', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-07-18 22:00:00', '2026-07-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000760', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-07-19 06:00:00', '2026-07-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000761', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-20 14:00:00', '2026-07-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000762', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-21 22:00:00', '2026-07-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000763', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-07-22 06:00:00', '2026-07-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000764', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-07-23 14:00:00', '2026-07-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000765', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-07-24 22:00:00', '2026-07-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000766', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-07-25 06:00:00', '2026-07-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000767', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-07-26 14:00:00', '2026-07-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000768', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-07-27 22:00:00', '2026-07-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000769', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-07-28 06:00:00', '2026-07-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000770', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-07-29 14:00:00', '2026-07-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000771', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-07-30 22:00:00', '2026-07-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000772', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-07-31 06:00:00', '2026-07-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000773', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-01 14:00:00', '2026-08-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000774', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-02 22:00:00', '2026-08-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000775', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-03 06:00:00', '2026-08-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000776', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-04 14:00:00', '2026-08-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000777', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-05 22:00:00', '2026-08-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000778', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-06 06:00:00', '2026-08-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000779', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-07 14:00:00', '2026-08-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000780', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-08 22:00:00', '2026-08-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000781', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-09 06:00:00', '2026-08-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000782', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-10 14:00:00', '2026-08-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000783', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-11 22:00:00', '2026-08-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000784', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-12 06:00:00', '2026-08-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000785', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-13 14:00:00', '2026-08-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000786', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-14 22:00:00', '2026-08-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000787', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-15 06:00:00', '2026-08-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000788', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-16 14:00:00', '2026-08-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000789', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-08-17 22:00:00', '2026-08-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000790', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-08-18 06:00:00', '2026-08-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000791', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-19 14:00:00', '2026-08-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000792', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-20 22:00:00', '2026-08-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000793', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-21 06:00:00', '2026-08-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000794', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-08-22 14:00:00', '2026-08-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000795', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-08-23 22:00:00', '2026-08-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000796', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-08-24 06:00:00', '2026-08-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000797', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-08-25 14:00:00', '2026-08-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000798', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-08-26 22:00:00', '2026-08-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000799', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-08-27 06:00:00', '2026-08-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000800', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-08-28 14:00:00', '2026-08-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000801', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-08-29 22:00:00', '2026-08-30 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000802', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-08-30 06:00:00', '2026-08-30 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000803', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-08-31 14:00:00', '2026-08-31 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000804', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-01 22:00:00', '2026-09-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000805', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-02 06:00:00', '2026-09-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000806', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-03 14:00:00', '2026-09-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000807', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-04 22:00:00', '2026-09-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000808', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-05 06:00:00', '2026-09-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000809', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-06 14:00:00', '2026-09-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000810', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-07 22:00:00', '2026-09-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000811', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-08 06:00:00', '2026-09-08 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000812', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-09 14:00:00', '2026-09-09 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000813', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-10 22:00:00', '2026-09-11 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000814', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-11 06:00:00', '2026-09-11 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000815', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-12 14:00:00', '2026-09-12 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000816', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-13 22:00:00', '2026-09-14 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000817', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-14 06:00:00', '2026-09-14 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000818', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-15 14:00:00', '2026-09-15 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000819', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-09-16 22:00:00', '2026-09-17 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000820', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-09-17 06:00:00', '2026-09-17 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000821', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-18 14:00:00', '2026-09-18 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000822', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-19 22:00:00', '2026-09-20 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000823', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-20 06:00:00', '2026-09-20 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000824', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-09-21 14:00:00', '2026-09-21 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000825', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-09-22 22:00:00', '2026-09-23 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000826', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-09-23 06:00:00', '2026-09-23 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000827', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-09-24 14:00:00', '2026-09-24 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000828', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-09-25 22:00:00', '2026-09-26 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000829', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-09-26 06:00:00', '2026-09-26 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000830', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-09-27 14:00:00', '2026-09-27 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000831', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-09-28 22:00:00', '2026-09-29 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000832', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-09-29 06:00:00', '2026-09-29 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000833', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-09-30 14:00:00', '2026-09-30 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000834', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-10-01 22:00:00', '2026-10-02 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000835', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-10-02 06:00:00', '2026-10-02 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000836', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-10-03 14:00:00', '2026-10-03 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000837', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-10-04 22:00:00', '2026-10-05 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000838', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-10-05 06:00:00', '2026-10-05 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000839', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-10-06 14:00:00', '2026-10-06 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000840', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-10-07 22:00:00', '2026-10-08 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000841', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-01 06:00:00', '2026-01-01 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000842', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-02 14:00:00', '2026-01-02 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000843', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-03 22:00:00', '2026-01-04 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000844', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-04 06:00:00', '2026-01-04 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000845', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-05 14:00:00', '2026-01-05 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000846', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-06 22:00:00', '2026-01-07 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000847', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-07 06:00:00', '2026-01-07 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000848', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-08 14:00:00', '2026-01-08 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000849', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-09 22:00:00', '2026-01-10 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000850', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-10 06:00:00', '2026-01-10 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000851', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-11 14:00:00', '2026-01-11 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000852', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-12 22:00:00', '2026-01-13 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000853', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-13 06:00:00', '2026-01-13 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000854', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-14 14:00:00', '2026-01-14 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000855', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-15 22:00:00', '2026-01-16 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000856', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-16 06:00:00', '2026-01-16 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000857', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-17 14:00:00', '2026-01-17 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000858', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-18 22:00:00', '2026-01-19 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000859', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-01-19 06:00:00', '2026-01-19 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000860', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-01-20 14:00:00', '2026-01-20 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000861', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-21 22:00:00', '2026-01-22 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000862', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-01-22 06:00:00', '2026-01-22 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000863', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-01-23 14:00:00', '2026-01-23 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000864', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-01-24 22:00:00', '2026-01-25 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000865', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-01-25 06:00:00', '2026-01-25 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000866', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-01-26 14:00:00', '2026-01-26 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000867', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-01-27 22:00:00', '2026-01-28 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000868', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-01-28 06:00:00', '2026-01-28 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000869', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-01-29 14:00:00', '2026-01-29 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000870', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-01-30 22:00:00', '2026-01-31 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000871', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-01-31 06:00:00', '2026-01-31 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000872', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-01 14:00:00', '2026-02-01 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000873', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-02 22:00:00', '2026-02-03 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000874', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-03 06:00:00', '2026-02-03 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000875', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-04 14:00:00', '2026-02-04 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000876', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-05 22:00:00', '2026-02-06 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000877', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-06 06:00:00', '2026-02-06 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000878', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-07 14:00:00', '2026-02-07 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000879', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-08 22:00:00', '2026-02-09 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000880', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-02-09 06:00:00', '2026-02-09 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000881', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-10 14:00:00', '2026-02-10 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000882', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-11 22:00:00', '2026-02-12 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000883', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-12 06:00:00', '2026-02-12 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000884', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-13 14:00:00', '2026-02-13 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000885', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-14 22:00:00', '2026-02-15 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000886', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-15 06:00:00', '2026-02-15 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000887', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-16 14:00:00', '2026-02-16 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000888', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-17 22:00:00', '2026-02-18 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000889', 'STORE-000009', 'EMP-000009', 'ROLE-000002', '2026-02-18 06:00:00', '2026-02-18 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000890', 'STORE-000010', 'EMP-000020', 'ROLE-000006', '2026-02-19 14:00:00', '2026-02-19 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000891', 'STORE-000001', 'EMP-000001', 'ROLE-000001', '2026-02-20 22:00:00', '2026-02-21 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000892', 'STORE-000002', 'EMP-000012', 'ROLE-000005', '2026-02-21 06:00:00', '2026-02-21 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000893', 'STORE-000003', 'EMP-000023', 'ROLE-000002', '2026-02-22 14:00:00', '2026-02-22 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000894', 'STORE-000004', 'EMP-000034', 'ROLE-000006', '2026-02-23 22:00:00', '2026-02-24 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000895', 'STORE-000005', 'EMP-000045', 'ROLE-000003', '2026-02-24 06:00:00', '2026-02-24 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000896', 'STORE-000006', 'EMP-000006', 'ROLE-000006', '2026-02-25 14:00:00', '2026-02-25 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000897', 'STORE-000007', 'EMP-000017', 'ROLE-000003', '2026-02-26 22:00:00', '2026-02-27 06:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000898', 'STORE-000008', 'EMP-000028', 'ROLE-000007', '2026-02-27 06:00:00', '2026-02-27 14:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000899', 'STORE-000009', 'EMP-000029', 'ROLE-000001', '2026-02-28 14:00:00', '2026-02-28 22:00:00', 'closed');
INSERT INTO shift (shift_id, store_id, employee_id, role_id, started_at, ended_at, status) VALUES ('SHF-2026-000900', 'STORE-000010', 'EMP-000040', 'ROLE-000005', '2026-03-01 22:00:00', '2026-03-02 06:00:00', 'closed');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000001', 'Spring Flex Promo 001', 'bogo', '2026-01-14', '2026-01-28', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000002', 'Spring Flex Promo 002', 'percent_off', '2026-01-17', '2026-01-31', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000003', 'Spring Flex Promo 003', 'markdown', '2026-01-20', '2026-02-03', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000004', 'Spring Flex Promo 004', 'bogo', '2026-01-23', '2026-02-06', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000005', 'Spring Flex Promo 005', 'percent_off', '2026-01-26', '2026-02-09', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000006', 'Spring Flex Promo 006', 'markdown', '2026-01-29', '2026-02-12', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000007', 'Spring Flex Promo 007', 'bogo', '2026-02-01', '2026-02-15', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000008', 'Spring Flex Promo 008', 'percent_off', '2026-02-04', '2026-02-18', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000009', 'Spring Flex Promo 009', 'markdown', '2026-02-07', '2026-02-21', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000010', 'Spring Flex Promo 010', 'bogo', '2026-02-10', '2026-02-24', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000011', 'Spring Flex Promo 011', 'percent_off', '2026-02-13', '2026-02-27', 'ended');
INSERT INTO promotion (promo_id, name, promo_type, start_on, end_on, status) VALUES ('PRM-2026-000012', 'Spring Flex Promo 012', 'markdown', '2026-02-16', '2026-03-02', 'ended');
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000001', 'SKU-000002', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000001', 'SKU-000003', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000001', 'SKU-000004', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000001', 'SKU-000005', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000002', 'SKU-000003', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000002', 'SKU-000004', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000002', 'SKU-000005', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000002', 'SKU-000006', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000003', 'SKU-000004', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000003', 'SKU-000005', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000003', 'SKU-000006', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000003', 'SKU-000007', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000004', 'SKU-000005', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000004', 'SKU-000006', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000004', 'SKU-000007', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000004', 'SKU-000008', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000005', 'SKU-000006', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000005', 'SKU-000007', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000005', 'SKU-000008', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000005', 'SKU-000009', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000006', 'SKU-000007', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000006', 'SKU-000008', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000006', 'SKU-000009', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000006', 'SKU-000010', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000007', 'SKU-000008', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000007', 'SKU-000009', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000007', 'SKU-000010', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000007', 'SKU-000011', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000008', 'SKU-000009', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000008', 'SKU-000010', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000008', 'SKU-000011', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000008', 'SKU-000012', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000009', 'SKU-000010', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000009', 'SKU-000011', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000009', 'SKU-000012', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000009', 'SKU-000013', 15);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000010', 'SKU-000011', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000010', 'SKU-000012', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000010', 'SKU-000013', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000010', 'SKU-000014', 20);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000011', 'SKU-000012', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000011', 'SKU-000013', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000011', 'SKU-000014', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000011', 'SKU-000015', 25);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000012', 'SKU-000013', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000012', 'SKU-000014', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000012', 'SKU-000015', 10);
INSERT INTO promotion_sku (promo_id, sku_id, discount_pct) VALUES ('PRM-2026-000012', 'SKU-000016', 10);
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000002');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000003');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000001', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000003');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000002', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000003', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000004', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000005', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000005', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000005', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000005', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000005', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000006', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000006', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000006', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000006', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000007', 'STORE-000008');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000007', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000007', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000008', 'STORE-000009');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000008', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000009', 'STORE-000010');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000001');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000002');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000003');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000010', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000002');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000003');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000011', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000003');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000004');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000005');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000006');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000007');
INSERT INTO promotion_store (promo_id, store_id) VALUES ('PRM-2026-000012', 'STORE-000008');
COMMIT;
