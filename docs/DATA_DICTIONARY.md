# Data dictionary

All fields below are synthetic. IDs are immutable once assigned.

## Store (`store`) — 1:N employees, shifts, movements, counts, alerts

| Field | Type | Required | Allowed values / units | Unique | Validation |
|---|---|---|---|---|---|
| store_id | text | yes | `STORE-000001` | PK | `^STORE-\d{6}$` |
| store_code | text | yes | `S0001` | yes | non-empty |
| name | text | yes | store display name | no | non-empty |
| banner | text | yes | YottaMart, FlexWarehouse, HarborGo | no | enum |
| format | text | yes | supercenter, neighborhood, warehouse, ecom_fc | no | enum |
| city, state, region | text | yes | US-like synthetic geography | no | region in Northeast/Southeast/Midwest/Southwest/West |
| timezone | text | yes | IANA tz | no | non-empty |
| opened_on | date | yes | ISO date | no | <= today |
| closed_on | date | no | ISO date | no | >= opened_on when present |
| status | text | yes | active, seasonal, closed | no | enum |
| sq_ft | int | yes | square feet | no | > 0 |
| shrink_risk_tier | text | yes | low, medium, high | no | enum |

## SKU (`sku`) — 1:N movements, counts; N:M stores via assortment; N:M promotions

| Field | Type | Required | Notes |
|---|---|---|---|
| sku_id | text PK | yes | `SKU-000001` |
| upc | text | yes | unique 12-digit synthetic |
| name, category, subcategory, brand | text | yes | category from controlled list |
| unit_cost, unit_retail | number USD | yes | >= 0, retail typically >= cost |
| uom | text | yes | EA |
| perishable, high_theft_risk | bool 0/1 | yes | |
| status | text | yes | active, seasonal, discontinued |
| introduced_on | date | yes | ISO date |

## EmployeeRole (`employee_role`)

| Field | Type | Required | Notes |
|---|---|---|---|
| role_id | text PK | yes | `ROLE-000001` |
| role_name | text unique | yes | cashier, stocker, store_manager, loss_prevention, merchandiser, warehouse_picker, cycle_counter |
| can_adjust_inventory / can_approve_transfer / can_perform_count / can_process_return | 0/1 | yes | authorization flags |
| effective_from / effective_to | date | from required | role lifecycle, history kept by new rows not updates |

## Employee (`employee`) — N:1 store, N:1 role

Synthetic operators only. No real PII.

## StoreSkuAssortment — N:M bridge Store↔SKU

PK `(store_id, sku_id)`. `listed_from`/`listed_to` are effective dates.

## Shift (`shift`) — N:1 store, employee, role

`SHF-2026-000001`. `ended_at >= started_at`. Status scheduled/open/closed.

## Promotion + `promotion_sku` + `promotion_store`

N:M bridges. `PRM-2026-000001`. Discount 0–90%.

## InventoryMovement (`inventory_movement`) — event history, append-only

| Field | Type | Required | Notes |
|---|---|---|---|
| movement_id | text PK | yes | `MOV-2026-00000001` |
| store_id, sku_id | FK | yes | must exist |
| movement_type | enum | yes | opening_balance, receipt, sale, transfer_in, transfer_out, adjustment, damage, return_in, cycle_count_adjust |
| qty | int | yes | signed; inbound +, outbound −; adjustments keep sign |
| unit_cost | number | yes | copied from SKU at event time |
| occurred_at / recorded_at | datetime | yes | business vs system clock |
| shift_id, employee_id, role_id | FK | optional | authorization context |
| reason_code | text | conditional | required for adjustment/damage in valid ops; planted missing-reason leaves blank |
| reference_id | text | optional | PO, sale, transfer pair |
| counterpart_store_id | FK | transfers | other node of the transfer |
| source_system | text | yes | ERP, POS, WMS, COUNT |
| is_voided | 0/1 | yes | voids are new state, not deletes |

Cardinality: Store 1:N Movement; SKU 1:N Movement; Shift 1:N Movement (optional).

## Return (`return_event`)

`RET-2026-000001`. FK to original sale movement and return_in movement.

## CycleCount (`cycle_count`)

`CNT-2026-000001`. `expected_qty` is **derived** by replaying movements with `occurred_at <= snapshot_as_of`. `variance_qty = counted_qty - expected_qty`. Status draft→submitted→reviewed→posted. Posted counts may emit a `cycle_count_adjust` movement (new row).

## BalanceEvent (`balance_event`)

Append-only snapshots (`opening`, `count_post`, `daily_close`). Never overwrite on-hand in place.

## ShrinkageAlert (`shrinkage_alert`)

`SHR-2026-000001`. `evidence_json` must cite source movement/count IDs and the rule fired. Status open/investigating/closed_benign/closed_confirmed.

## Investigation (`investigation`) + `investigation_alert` (N:M)

`INV-2026-000001`. Outcomes: pending, confirmed_theft, process_error, supplier_issue, damage, counting_error, transfer_mismatch, unknown.

## Ground truth (`labels/ground_truth.csv`) — **not a feature table**

| Field | Notes |
|---|---|
| entity_type / entity_id | cycle_count, inventory_movement, return_event, sku |
| issue_type | planted pattern name |
| expected_decision | open_alert or close_benign |
| notes | human-readable rule |
| seed | generator seed |

Do not join this file into training features or the detector.
