from __future__ import annotations

import sqlite3
from pathlib import Path

import pandas as pd

TABLE_ORDER = [
    "store",
    "sku",
    "employee_role",
    "employee",
    "store_sku_assortment",
    "shift",
    "promotion",
    "promotion_sku",
    "promotion_store",
    "inventory_movement",
    "return_event",
    "cycle_count",
    "balance_event",
    "shrinkage_alert",
    "investigation",
    "investigation_alert",
]


def load_sqlite(tables: dict[str, pd.DataFrame], db_path: Path, schema_path: Path) -> None:
    if db_path.exists():
        db_path.unlink()
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA foreign_keys = OFF")
        conn.executescript(schema_path.read_text(encoding="utf-8"))
        for name in TABLE_ORDER:
            df = tables[name].copy()
            df = df.where(pd.notnull(df), None)
            df.to_sql(name, conn, if_exists="append", index=False)
        conn.commit()
    finally:
        conn.close()


def connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn
