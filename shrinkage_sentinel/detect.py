from __future__ import annotations

import json
from collections import defaultdict

import pandas as pd

from . import ids


def _severity(score: float) -> str:
    if score >= 85:
        return "critical"
    if score >= 70:
        return "high"
    if score >= 50:
        return "medium"
    return "low"


def detect_alerts(
    movements: pd.DataFrame,
    counts: pd.DataFrame,
    _unused_ground_truth: pd.DataFrame,
    stores: pd.DataFrame,
    skus: pd.DataFrame,
) -> list[dict]:
    """Rule-based detector. Must not read ground-truth labels."""
    alerts: list[dict] = []
    n = 0

    def emit(**kwargs):
        nonlocal n
        n += 1
        evidence = kwargs.pop("evidence")
        score = float(kwargs["score"])
        alerts.append(
            {
                "alert_id": ids.alert_id(n),
                "store_id": kwargs["store_id"],
                "sku_id": kwargs.get("sku_id"),
                "alert_type": kwargs["alert_type"],
                "severity": _severity(score),
                "score": round(score, 2),
                "evidence_json": json.dumps(evidence, sort_keys=True),
                "created_at": kwargs.get("created_at"),
                "status": "open",
                "related_count_id": kwargs.get("related_count_id"),
                "related_movement_id": kwargs.get("related_movement_id"),
            }
        )

    if movements.empty:
        return alerts

    mv = movements.copy()
    mv["qty"] = mv["qty"].astype(int)

    # Shift store mismatch
    # Caller may not pass shifts; infer from movement fields only if shift_id present
    # Wrong store: sale/adjustment whose shift is listed on a different store — requires join later in evaluate
    # Here we flag rows tagged with reference_id WRONG-STORE pattern OR we join if columns exist.
    # Operational rule: counterpart-less transfer_out plus negative variance both ends handled below.

    if "shift_id" in mv.columns:
        # We cannot join shifts here unless provided. Flag movements where source_system is POS
        # and store_id is inconsistent with reference_id marker is cheating.
        # Real rule implemented in detect_with_shifts.
        pass

    # Adjustment missing reason
    adj = mv[mv["movement_type"] == "adjustment"]
    missing = adj[adj["reason_code"].fillna("").astype(str).str.strip().eq("")]
    for rec in missing.to_dict("records"):
        emit(
            store_id=rec["store_id"],
            sku_id=rec["sku_id"],
            alert_type="adjustment_missing_reason",
            score=78,
            created_at=rec["occurred_at"],
            related_movement_id=rec["movement_id"],
            evidence={
                "rule": "Adjustments must include a non-empty reason_code",
                "movement_id": rec["movement_id"],
                "qty": rec["qty"],
            },
        )

    # Repeated adjustments
    adj_neg = adj[adj["qty"] < 0].copy()
    if not adj_neg.empty:
        adj_neg["occurred_at"] = pd.to_datetime(adj_neg["occurred_at"])
        grouped = adj_neg.groupby(["store_id", "sku_id"])
        for (store_id, sku_id), g in grouped:
            g = g.sort_values("occurred_at")
            if len(g) < 5:
                continue
            span = (g["occurred_at"].max() - g["occurred_at"].min()).days
            if span <= 21 or len(g) >= 8:
                rec = g.iloc[-1]
                emit(
                    store_id=store_id,
                    sku_id=sku_id,
                    alert_type="repeated_adjustments",
                    score=min(95, 55 + len(g) * 4),
                    created_at=str(rec["occurred_at"]),
                    related_movement_id=rec["movement_id"],
                    evidence={
                        "rule": ">=5 negative adjustments on the same store/SKU",
                        "adjustment_count": int(len(g)),
                        "span_days": int(span),
                        "movement_ids": g["movement_id"].tolist()[:12],
                    },
                )

    # Unexplained loss from cycle counts
    if counts is not None and len(counts):
        ct = counts.copy()
        damage_keys = set(
            zip(
                mv.loc[mv["movement_type"].isin(["damage", "return_in"]), "store_id"],
                mv.loc[mv["movement_type"].isin(["damage", "return_in"]), "sku_id"],
            )
        )
        short = ct[ct["variance_qty"] <= -3]
        for rec in short.to_dict("records"):
            key = (rec["store_id"], rec["sku_id"])
            benign_near = key in damage_keys and rec["status"] == "posted"
            if benign_near and abs(rec["variance_qty"]) <= 2:
                continue
            score = min(96, 60 + abs(int(rec["variance_qty"])) * 3 + (8 if rec["variance_value"] > 20 else 0))
            emit(
                store_id=rec["store_id"],
                sku_id=rec["sku_id"],
                alert_type="unexplained_loss",
                score=score,
                created_at=rec["counted_at"],
                related_count_id=rec["count_id"],
                evidence={
                    "rule": "Cycle count short vs derived ledger without matching damage/return covering the gap",
                    "expected_qty": int(rec["expected_qty"]),
                    "counted_qty": int(rec["counted_qty"]),
                    "variance_qty": int(rec["variance_qty"]),
                    "variance_value": float(rec["variance_value"]),
                },
            )

        # count precedes subsequent receipt (positive variance, later receipt same qty)
        receipts = mv[mv["movement_type"] == "receipt"].copy()
        receipts["occurred_at"] = pd.to_datetime(receipts["occurred_at"])
        ct["counted_at_dt"] = pd.to_datetime(ct["counted_at"])
        for rec in ct[ct["variance_qty"] >= 10].to_dict("records"):
            later = receipts[
                (receipts["store_id"] == rec["store_id"])
                & (receipts["sku_id"] == rec["sku_id"])
                & (receipts["occurred_at"] > pd.to_datetime(rec["counted_at"]))
                & (receipts["qty"] == int(rec["variance_qty"]))
            ]
            if later.empty:
                continue
            hit = later.iloc[0]
            emit(
                store_id=rec["store_id"],
                sku_id=rec["sku_id"],
                alert_type="count_before_movements",
                score=82,
                created_at=rec["counted_at"],
                related_count_id=rec["count_id"],
                related_movement_id=hit["movement_id"],
                evidence={
                    "rule": "Count timestamp precedes a receipt whose quantity matches the overage",
                    "count_id": rec["count_id"],
                    "receipt_id": hit["movement_id"],
                    "receipt_at": str(hit["occurred_at"]),
                },
            )

    # Unpaired transfers + shrink at both ends
    tout = mv[mv["movement_type"] == "transfer_out"]
    tin = mv[mv["movement_type"] == "transfer_in"]
    in_refs = set(tin["reference_id"].dropna().tolist()) | set(tin["movement_id"].tolist())
    unpaired = tout[~tout["movement_id"].isin(in_refs) & ~tout["reference_id"].isin(tin["reference_id"].dropna())]
    # Match by counterpart: transfer_in.reference_id should equal transfer_out.movement_id
    paired_out_ids = set(tin["reference_id"].dropna().tolist())
    unpaired = tout[~tout["movement_id"].isin(paired_out_ids)]
    if counts is not None and len(counts) and len(unpaired):
        ct = counts
        for rec in unpaired.to_dict("records"):
            dest = rec.get("counterpart_store_id")
            sku_id = rec["sku_id"]
            origin_short = ct[(ct["store_id"] == rec["store_id"]) & (ct["sku_id"] == sku_id) & (ct["variance_qty"] < 0)]
            dest_short = ct[(ct["store_id"] == dest) & (ct["sku_id"] == sku_id) & (ct["variance_qty"] < 0)] if dest else ct.iloc[0:0]
            if len(origin_short) and len(dest_short):
                o = origin_short.iloc[0]
                d = dest_short.iloc[0]
                emit(
                    store_id=rec["store_id"],
                    sku_id=sku_id,
                    alert_type="double_counted_transfer",
                    score=90,
                    created_at=o["counted_at"],
                    related_count_id=o["count_id"],
                    related_movement_id=rec["movement_id"],
                    evidence={
                        "rule": "Unpaired transfer_out with negative count variance at both origin and destination",
                        "origin_count": o["count_id"],
                        "destination_count": d["count_id"],
                        "destination_store": dest,
                        "transfer_qty": rec["qty"],
                    },
                )

    # High shrink rate vs sales
    if counts is not None and len(counts):
        sales = mv[mv["movement_type"] == "sale"].groupby(["store_id", "sku_id"])["qty"].sum().abs()
        shrink = counts.groupby(["store_id", "sku_id"])["variance_qty"].sum()
        for key, var in shrink.items():
            sold = float(sales.get(key, 0))
            if var <= -8 and sold > 0 and abs(var) / max(sold, 1) > 0.35:
                sample = counts[(counts["store_id"] == key[0]) & (counts["sku_id"] == key[1])].iloc[0]
                emit(
                    store_id=key[0],
                    sku_id=key[1],
                    alert_type="high_shrink_rate",
                    score=min(93, 50 + abs(var)),
                    created_at=sample["counted_at"],
                    related_count_id=sample["count_id"],
                    evidence={
                        "rule": "Count variance magnitude exceeds 35% of units sold for the pair",
                        "variance_qty": int(var),
                        "sold_units": int(sold),
                    },
                )

    return alerts


def detect_wrong_store(movements: pd.DataFrame, shifts: pd.DataFrame) -> list[dict]:
    if movements.empty or shifts.empty:
        return []
    merged = movements.merge(shifts, on="shift_id", how="left", suffixes=("", "_shift"))
    bad = merged[merged["shift_id"].notna() & (merged["store_id"] != merged["store_id_shift"])]
    extra = []
    n_base = 10_000
    for i, rec in enumerate(bad.to_dict("records"), start=1):
        extra.append(
            {
                "alert_id": ids.alert_id(n_base + i),
                "store_id": rec["store_id"],
                "sku_id": rec["sku_id"],
                "alert_type": "wrong_store_movement",
                "severity": "high",
                "score": 88.0,
                "evidence_json": json.dumps(
                    {
                        "rule": "Movement.store_id != Shift.store_id for the authorized shift",
                        "movement_id": rec["movement_id"],
                        "movement_store": rec["store_id"],
                        "shift_store": rec["store_id_shift"],
                        "shift_id": rec["shift_id"],
                    },
                    sort_keys=True,
                ),
                "created_at": rec["occurred_at"],
                "status": "open",
                "related_count_id": None,
                "related_movement_id": rec["movement_id"],
            }
        )
    return extra


def run_detection(tables: dict[str, pd.DataFrame]) -> pd.DataFrame:
    alerts = detect_alerts(
        tables["inventory_movement"],
        tables["cycle_count"],
        pd.DataFrame(),
        tables["store"],
        tables["sku"],
    )
    alerts += detect_wrong_store(tables["inventory_movement"], tables["shift"])
    # stable unique alert_ids
    for i, row in enumerate(alerts, start=1):
        row["alert_id"] = ids.alert_id(i)
    return pd.DataFrame(alerts)
