from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from shrinkage_sentinel.config import DEFAULT_SEED
from shrinkage_sentinel.db import connect
from shrinkage_sentinel.evaluate import evaluate
from shrinkage_sentinel.generate import generate

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
STARTER_DB = ROOT / "data" / "starter" / "shrinkage.sqlite"
FULL_DB = ROOT / "data" / "full" / "shrinkage.sqlite"
GT_STARTER = ROOT / "data" / "starter" / "labels" / "ground_truth.csv"

app = FastAPI(title="Shrinkage Sentinel", version="1.0.0")


def db_path() -> Path:
    if STARTER_DB.exists():
        return STARTER_DB
    if FULL_DB.exists():
        return FULL_DB
    raise HTTPException(503, "No dataset yet. POST /api/generate?scale=starter")


def q(sql: str, params: tuple = ()):
    conn = connect(db_path())
    try:
        cur = conn.execute(sql, params)
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]
    finally:
        conn.close()


@app.get("/api/health")
def health():
    exists = STARTER_DB.exists() or FULL_DB.exists()
    return {"ok": True, "dataset": exists, "path": str(db_path()) if exists else None}


@app.post("/api/generate")
def api_generate(scale: str = "starter", seed: int = DEFAULT_SEED):
    if scale not in {"starter", "full"}:
        raise HTTPException(400, "scale must be starter or full")
    summary = generate(scale, seed, ROOT / "data" / scale)
    return {
        "seed": summary["seed"],
        "scale": summary["scale"],
        "row_counts": summary["row_counts"],
        "validation": summary["validation"]["status"],
        "sqlite": summary["sqlite"],
    }


@app.get("/api/summary")
def summary():
    stores = q("SELECT COUNT(*) n FROM store")[0]["n"]
    skus = q("SELECT COUNT(*) n FROM sku")[0]["n"]
    moves = q("SELECT COUNT(*) n FROM inventory_movement")[0]["n"]
    counts = q("SELECT COUNT(*) n FROM cycle_count")[0]["n"]
    alerts = q("SELECT COUNT(*) n FROM shrinkage_alert")[0]["n"]
    open_alerts = q("SELECT COUNT(*) n FROM shrinkage_alert WHERE status IN ('open','investigating')")[0]["n"]
    shrink = q(
        "SELECT COALESCE(SUM(CASE WHEN variance_qty < 0 THEN -variance_qty ELSE 0 END),0) units, "
        "COALESCE(SUM(CASE WHEN variance_qty < 0 THEN variance_value ELSE 0 END),0) value FROM cycle_count"
    )[0]
    by_type = q(
        "SELECT alert_type, COUNT(*) n, ROUND(AVG(score),1) avg_score FROM shrinkage_alert GROUP BY alert_type ORDER BY n DESC"
    )
    by_region = q(
        "SELECT s.region, COUNT(*) alerts FROM shrinkage_alert a JOIN store s ON s.store_id = a.store_id GROUP BY s.region"
    )
    recent = q(
        "SELECT alert_id, store_id, sku_id, alert_type, severity, score, status, created_at "
        "FROM shrinkage_alert ORDER BY score DESC LIMIT 8"
    )
    recon = q(
        """
        SELECT ROUND(100.0 * SUM(CASE WHEN variance_qty = counted_qty - expected_qty THEN 1 ELSE 0 END) / COUNT(*), 2) pct
        FROM cycle_count
        """
    )[0]["pct"]
    return {
        "kpis": {
            "stores": stores,
            "skus": skus,
            "movements": moves,
            "cycle_counts": counts,
            "alerts": alerts,
            "open_alerts": open_alerts,
            "shrink_units": shrink["units"],
            "shrink_value": round(float(shrink["value"]), 2),
            "stock_equation_pass_pct": recon,
        },
        "alerts_by_type": by_type,
        "alerts_by_region": by_region,
        "top_alerts": recent,
    }


@app.get("/api/stores")
def stores():
    return q(
        """
        SELECT s.*, 
          (SELECT COUNT(*) FROM shrinkage_alert a WHERE a.store_id = s.store_id) AS alert_count,
          (SELECT COALESCE(SUM(CASE WHEN variance_qty < 0 THEN variance_value ELSE 0 END),0) FROM cycle_count c WHERE c.store_id = s.store_id) AS shrink_value
        FROM store s ORDER BY alert_count DESC, s.store_id
        """
    )


@app.get("/api/skus")
def skus(limit: int = 80):
    return q(
        """
        SELECT k.*,
          (SELECT COUNT(*) FROM shrinkage_alert a WHERE a.sku_id = k.sku_id) AS alert_count
        FROM sku k ORDER BY k.high_theft_risk DESC, alert_count DESC LIMIT ?
        """,
        (limit,),
    )


@app.get("/api/movements")
def movements(store_id: str | None = None, sku_id: str | None = None, limit: int = 50):
    sql = "SELECT * FROM inventory_movement WHERE 1=1"
    params: list = []
    if store_id:
        sql += " AND store_id = ?"
        params.append(store_id)
    if sku_id:
        sql += " AND sku_id = ?"
        params.append(sku_id)
    sql += " ORDER BY occurred_at DESC LIMIT ?"
    params.append(limit)
    return q(sql, tuple(params))


@app.get("/api/counts")
def counts(limit: int = 50):
    return q(
        "SELECT * FROM cycle_count ORDER BY ABS(variance_qty) DESC, counted_at DESC LIMIT ?",
        (limit,),
    )


@app.get("/api/alerts")
def alerts(alert_type: str | None = None, severity: str | None = None):
    sql = "SELECT * FROM shrinkage_alert WHERE 1=1"
    params: list = []
    if alert_type:
        sql += " AND alert_type = ?"
        params.append(alert_type)
    if severity:
        sql += " AND severity = ?"
        params.append(severity)
    sql += " ORDER BY score DESC"
    return q(sql, tuple(params))


@app.get("/api/alerts/{alert_id}")
def alert_detail(alert_id: str):
    rows = q("SELECT * FROM shrinkage_alert WHERE alert_id = ?", (alert_id,))
    if not rows:
        raise HTTPException(404, "alert not found")
    rec = rows[0]
    rec["evidence"] = json.loads(rec["evidence_json"])
    rec["investigations"] = q(
        """
        SELECT i.* FROM investigation i
        JOIN investigation_alert ia ON ia.investigation_id = i.investigation_id
        WHERE ia.alert_id = ?
        """,
        (alert_id,),
    )
    rec["recent_movements"] = q(
        """
        SELECT * FROM inventory_movement
        WHERE store_id = ? AND (? IS NULL OR sku_id = ?)
        ORDER BY occurred_at DESC LIMIT 12
        """,
        (rec["store_id"], rec["sku_id"], rec["sku_id"]),
    )
    return rec


@app.get("/api/investigations")
def investigations():
    return q(
        """
        SELECT i.*, GROUP_CONCAT(ia.alert_id) AS alert_ids
        FROM investigation i
        LEFT JOIN investigation_alert ia ON ia.investigation_id = i.investigation_id
        GROUP BY i.investigation_id
        ORDER BY i.opened_at DESC
        """
    )


@app.get("/api/exceptions")
def exceptions():
    return {
        "wrong_store_movement": q(
            """
            SELECT m.movement_id, m.store_id AS movement_store, s.store_id AS shift_store, m.sku_id, m.occurred_at, m.qty
            FROM inventory_movement m
            JOIN shift s ON s.shift_id = m.shift_id
            WHERE m.store_id != s.store_id
            LIMIT 20
            """
        ),
        "adjustment_missing_reason": q(
            """
            SELECT movement_id, store_id, sku_id, qty, occurred_at
            FROM inventory_movement
            WHERE movement_type = 'adjustment' AND (reason_code IS NULL OR TRIM(reason_code) = '')
            LIMIT 20
            """
        ),
        "unpaired_transfers": q(
            """
            SELECT o.movement_id, o.store_id AS origin, o.counterpart_store_id AS destination, o.sku_id, o.qty, o.occurred_at
            FROM inventory_movement o
            WHERE o.movement_type = 'transfer_out'
              AND NOT EXISTS (
                SELECT 1 FROM inventory_movement i
                WHERE i.movement_type = 'transfer_in' AND i.reference_id = o.movement_id
              )
            LIMIT 20
            """
        ),
    }


@app.get("/api/reconciliation")
def reconciliation(store_id: str = Query(...), sku_id: str = Query(...)):
    moves = q(
        "SELECT movement_id, movement_type, qty, occurred_at, reason_code FROM inventory_movement WHERE store_id = ? AND sku_id = ? ORDER BY occurred_at, movement_id",
        (store_id, sku_id),
    )
    running = 0
    ledger = []
    for m in moves:
        running += int(m["qty"])
        ledger.append({**m, "on_hand_after": running})
    counts = q(
        "SELECT * FROM cycle_count WHERE store_id = ? AND sku_id = ? ORDER BY counted_at",
        (store_id, sku_id),
    )
    return {"store_id": store_id, "sku_id": sku_id, "closing_on_hand": running, "ledger": ledger, "counts": counts}


@app.get("/api/validation")
def validation():
    path = ROOT / "data" / "starter" / "validation_summary.json"
    alt = ROOT / "data" / "full" / "validation_summary.json"
    target = path if path.exists() else alt
    if not target.exists():
        raise HTTPException(404, "validation summary missing")
    return json.loads(target.read_text(encoding="utf-8"))


@app.get("/api/evaluation")
def evaluation():
    """Uses held-out labels. Never mixed into feature tables."""
    gt_path = GT_STARTER if GT_STARTER.exists() else ROOT / "data" / "full" / "labels" / "ground_truth.csv"
    if not gt_path.exists():
        raise HTTPException(404, "ground truth not generated")
    gt = pd.read_csv(gt_path)
    alerts = pd.DataFrame(q("SELECT * FROM shrinkage_alert"))
    return evaluate(alerts, gt)


app.mount("/assets", StaticFiles(directory=WEB / "assets"), name="assets")


@app.get("/")
def index():
    return FileResponse(WEB / "index.html")
