from __future__ import annotations

import re
from collections import defaultdict

import pandas as pd

ID_PATTERNS = {
    "store": re.compile(r"^STORE-\d{6}$"),
    "sku": re.compile(r"^SKU-\d{6}$"),
    "movement": re.compile(r"^MOV-2026-\d{8}$"),
    "count": re.compile(r"^CNT-2026-\d{6}$"),
    "alert": re.compile(r"^SHR-2026-\d{6}$"),
    "investigation": re.compile(r"^INV-2026-\d{6}$"),
}


def _unique(df: pd.DataFrame, col: str) -> bool:
    return df[col].is_unique and df[col].notna().all()


def validate_dataset(tables: dict[str, pd.DataFrame]) -> dict:
    errors: list[str] = []
    warnings: list[str] = []
    checks: dict[str, bool] = {}

    store = tables["store"]
    sku = tables["sku"]
    mv = tables["inventory_movement"]
    counts = tables["cycle_count"]
    roles = tables["employee_role"]
    employees = tables["employee"]
    shifts = tables["shift"]
    alerts = tables["shrinkage_alert"]
    gt = tables.get("ground_truth", pd.DataFrame())

    checks["pk_store"] = bool(_unique(store, "store_id"))
    checks["pk_sku"] = bool(_unique(sku, "sku_id"))
    checks["pk_movement"] = bool(_unique(mv, "movement_id"))
    checks["pk_count"] = bool(_unique(counts, "count_id"))
    checks["pk_alert"] = True if alerts.empty else bool(_unique(alerts, "alert_id"))
    checks["id_store_format"] = bool(store["store_id"].map(lambda x: bool(ID_PATTERNS["store"].match(str(x)))).all())
    checks["id_sku_format"] = bool(sku["sku_id"].map(lambda x: bool(ID_PATTERNS["sku"].match(str(x)))).all())
    checks["id_movement_format"] = bool(mv["movement_id"].map(lambda x: bool(ID_PATTERNS["movement"].match(str(x)))).all())
    checks["id_count_format"] = bool(counts["count_id"].map(lambda x: bool(ID_PATTERNS["count"].match(str(x)))).all())

    store_ids = set(store["store_id"])
    sku_ids = set(sku["sku_id"])
    emp_ids = set(employees["employee_id"])
    shift_ids = set(shifts["shift_id"])

    checks["fk_movement_store"] = bool(mv["store_id"].isin(store_ids).all())
    checks["fk_movement_sku"] = bool(mv["sku_id"].isin(sku_ids).all())
    checks["fk_count_store"] = bool(counts["store_id"].isin(store_ids).all())
    checks["fk_count_sku"] = bool(counts["sku_id"].isin(sku_ids).all())
    shift_ok = mv["shift_id"].dropna()
    checks["fk_movement_shift"] = bool(shift_ok.isin(shift_ids).all()) if len(shift_ok) else True

    # Stock equation on openings: opening qty >= 0
    openings = mv[mv["movement_type"] == "opening_balance"]
    checks["opening_non_negative"] = bool((openings["qty"] >= 0).all()) if len(openings) else False

    # Derived count variance
    derived_ok = (
        (counts["variance_qty"] == counts["counted_qty"] - counts["expected_qty"]).all()
        if len(counts)
        else False
    )
    checks["count_variance_derived"] = bool(derived_ok)

    # Replay reconciliation for a sample of count rows
    bal = defaultdict(int)
    ordered = mv.sort_values(["occurred_at", "movement_id"])
    sample = counts.head(min(25, len(counts)))
    recon_fail = 0
    for _, c in sample.iterrows():
        bal.clear()
        cutoff = c["snapshot_as_of"]
        sub = ordered[ordered["occurred_at"] <= cutoff]
        for rec in sub.itertuples(index=False):
            if rec.is_voided:
                continue
            bal[(rec.store_id, rec.sku_id)] += int(rec.qty)
        expected = bal.get((c["store_id"], c["sku_id"]), 0)
        if int(expected) != int(c["expected_qty"]):
            recon_fail += 1
    checks["stock_equation_sample"] = recon_fail == 0
    if recon_fail:
        errors.append(f"{recon_fail} sampled counts did not match replayed ledger expected_qty")

    # Enumerations
    allowed_mv = {
        "opening_balance",
        "receipt",
        "sale",
        "transfer_in",
        "transfer_out",
        "adjustment",
        "damage",
        "return_in",
        "cycle_count_adjust",
    }
    checks["movement_enums"] = bool(mv["movement_type"].isin(allowed_mv).all())

    # Date ordering: recorded_at >= occurred_at typically
    checks["shift_date_order"] = bool((shifts["ended_at"] >= shifts["started_at"]).all())

    # Ground truth not leaking into movement columns
    if "issue_type" in mv.columns or "expected_decision" in mv.columns:
        errors.append("ground truth columns leaked into inventory_movement")
        checks["gt_not_in_features"] = False
    else:
        checks["gt_not_in_features"] = True

    required_issues = {
        "unexplained_loss",
        "repeated_adjustments",
        "adjustment_missing_reason",
        "wrong_store_movement",
        "count_before_movements",
        "double_counted_transfer",
        "legitimate_damage",
        "legitimate_return",
    }
    if gt is not None and len(gt):
        present = set(gt["issue_type"])
        missing = required_issues - present
        checks["edge_cases_present"] = not missing
        if missing:
            errors.append(f"Missing planted issue types: {sorted(missing)}")
    else:
        checks["edge_cases_present"] = False
        errors.append("ground_truth is empty")

    # Duplicate movement ids already in pk
    for name, ok in checks.items():
        if not ok:
            errors.append(f"check failed: {name}")

    if not errors:
        status = "passed"
    elif checks.get("pk_movement") and checks.get("fk_movement_store"):
        status = "failed"
    else:
        status = "failed"

    checks = {k: bool(v) for k, v in checks.items()}
    return {
        "status": status if not errors else "failed",
        "passed": {k: v for k, v in checks.items() if v},
        "failed": {k: v for k, v in checks.items() if not v},
        "errors": errors,
        "warnings": warnings,
        "n_checks": len(checks),
        "n_passed": sum(1 for v in checks.values() if v),
    }
