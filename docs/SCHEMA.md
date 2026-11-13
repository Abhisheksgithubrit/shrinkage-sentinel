# Entities, keys and cardinality

```mermaid
erDiagram
  STORE ||--o{ EMPLOYEE : staffs
  STORE ||--o{ SHIFT : hosts
  STORE ||--o{ ASSORTMENT : carries
  SKU ||--o{ ASSORTMENT : listed_in
  EMPLOYEE_ROLE ||--o{ EMPLOYEE : assigned
  EMPLOYEE_ROLE ||--o{ SHIFT : works_as
  STORE ||--o{ INVENTORY_MOVEMENT : books
  SKU ||--o{ INVENTORY_MOVEMENT : affected
  SHIFT ||--o{ INVENTORY_MOVEMENT : authorizes
  STORE ||--o{ CYCLE_COUNT : counts
  CYCLE_COUNT ||--o| INVENTORY_MOVEMENT : may_post
  STORE ||--o{ SHRINKAGE_ALERT : raises
  INVESTIGATION }o--o{ SHRINKAGE_ALERT : investigates
  PROMOTION }o--o{ SKU : discounts
  PROMOTION }o--o{ STORE : applies
  INVENTORY_MOVEMENT ||--o{ RETURN_EVENT : customer_return
```

| Relationship | Cardinality | Optional | Notes |
|---|---|---|---|
| Store → Movement | 1:N | no | every movement has a store |
| SKU → Movement | 1:N | no | |
| Store ↔ SKU assortment | N:M | listed_to nullable | bridge `store_sku_assortment` |
| Promotion ↔ SKU | N:M | | bridge `promotion_sku` |
| Promotion ↔ Store | N:M | | bridge `promotion_store` |
| Shift → Movement | 1:N | yes | some ERP openings have no shift |
| Count → posted movement | 1:1 | yes | only posted variances |
| Investigation ↔ Alert | N:M | | bridge `investigation_alert` |
| Transfer out ↔ transfer in | 1:1 | yes | unpaired inbound is an exception |

Lifecycle: count `draft → submitted → reviewed → posted`; alert `open → investigating → closed_*`; shift `scheduled → open → closed`. Transitions are recorded as the current row's status at insert time plus later event rows (balance_event, investigation updates as new notes), not by silently rewriting history of movements.
