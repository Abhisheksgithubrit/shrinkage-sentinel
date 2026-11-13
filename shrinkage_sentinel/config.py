from __future__ import annotations

from dataclasses import dataclass

DEFAULT_SEED = 20261022
CALENDAR_START = "2026-01-01"
CALENDAR_END = "2026-10-22"

SCALES = {
    "starter": {
        "n_stores": 10,
        "n_skus": 80,
        "n_employees": 48,
        "n_movements": 12_000,
        "n_counts": 240,
        "n_promotions": 12,
        "skus_per_store": 28,
        "n_shifts": 900,
        "n_returns": 180,
    },
    "full": {
        "n_stores": 100,
        "n_skus": 5_000,
        "n_employees": 1_200,
        "n_movements": 1_000_000,
        "n_counts": 20_000,
        "n_promotions": 80,
        "skus_per_store": 800,
        "n_shifts": 24_000,
        "n_returns": 8_000,
    },
}

MOVEMENT_TYPES = (
    "opening_balance",
    "receipt",
    "sale",
    "transfer_in",
    "transfer_out",
    "adjustment",
    "damage",
    "return_in",
    "cycle_count_adjust",
)

REASON_CODES = (
    "RECEIPT_PO",
    "SALE_POS",
    "TRANSFER",
    "DAMAGE_SHELF",
    "DAMAGE_RECEIVING",
    "EXPIRED",
    "COUNT_VARIANCE",
    "SYSTEM_CORRECTION",
    "THEFT_SUSPECTED",
    "SUPPLIER_SHORT",
    "RETURN_CUSTOMER",
    "OPENING",
    "",  # allowed only for non-adjustment types; planted missing-reason uses this on adjustments
)

STORE_FORMATS = ("supercenter", "neighborhood", "warehouse", "ecom_fc")
STORE_STATUSES = ("active", "seasonal", "closed")
SKU_STATUSES = ("active", "seasonal", "discontinued")
ROLE_NAMES = (
    "cashier",
    "stocker",
    "store_manager",
    "loss_prevention",
    "merchandiser",
    "warehouse_picker",
    "cycle_counter",
)
SHIFT_STATUSES = ("scheduled", "open", "closed")
COUNT_STATUSES = ("draft", "submitted", "reviewed", "posted")
ALERT_TYPES = (
    "unexplained_loss",
    "repeated_adjustments",
    "adjustment_missing_reason",
    "wrong_store_movement",
    "count_before_movements",
    "double_counted_transfer",
    "high_shrink_rate",
)
ALERT_STATUSES = ("open", "investigating", "closed_benign", "closed_confirmed")
INVESTIGATION_OUTCOMES = (
    "pending",
    "confirmed_theft",
    "process_error",
    "supplier_issue",
    "damage",
    "counting_error",
    "transfer_mismatch",
    "unknown",
)
ISSUE_TYPES = (
    "unexplained_loss",
    "repeated_adjustments",
    "adjustment_missing_reason",
    "wrong_store_movement",
    "count_before_movements",
    "double_counted_transfer",
    "legitimate_damage",
    "legitimate_return",
    "promotion_sales_spike",
)
REGIONS = ("Northeast", "Southeast", "Midwest", "Southwest", "West")
CATEGORIES = (
    "Grocery",
    "Health",
    "Electronics",
    "Apparel",
    "Home",
    "Beauty",
    "Automotive",
    "Toys",
)


@dataclass(frozen=True)
class Scale:
    name: str
    n_stores: int
    n_skus: int
    n_employees: int
    n_movements: int
    n_counts: int
    n_promotions: int
    skus_per_store: int
    n_shifts: int
    n_returns: int

    @classmethod
    def from_name(cls, name: str) -> "Scale":
        if name not in SCALES:
            raise ValueError(f"Unknown scale {name!r}. Choose from {list(SCALES)}")
        return cls(name=name, **SCALES[name])
