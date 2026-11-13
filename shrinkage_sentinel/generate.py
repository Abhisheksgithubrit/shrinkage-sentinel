from __future__ import annotations

import json
import hashlib
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

from .config import (
    ALERT_TYPES,
    CALENDAR_END,
    CALENDAR_START,
    CATEGORIES,
    DEFAULT_SEED,
    REGIONS,
    ROLE_NAMES,
    Scale,
)
from . import ids
from .detect import run_detection
from .validate import validate_dataset

CITIES = [
    ("Austin", "TX", "Southwest"),
    ("Denver", "CO", "West"),
    ("Columbus", "OH", "Midwest"),
    ("Atlanta", "GA", "Southeast"),
    ("Buffalo", "NY", "Northeast"),
    ("Boise", "ID", "West"),
    ("Tampa", "FL", "Southeast"),
    ("Omaha", "NE", "Midwest"),
    ("Raleigh", "NC", "Southeast"),
    ("Portland", "OR", "West"),
    ("Nashville", "TN", "Southeast"),
    ("Madison", "WI", "Midwest"),
]
FIRST = ["Avery", "Jordan", "Riley", "Cameron", "Quinn", "Morgan", "Sage", "Reese", "Drew", "Parker"]
LAST = ["Hale", "Nair", "Brooks", "Vega", "Singh", "Cole", "Diaz", "Shah", "Nguyen", "Patel"]
BRANDS = ["Northline", "Cedar&Co", "Voltara", "Harbor Home", "Lumen", "Peakform", "Nimbus"]
SUBCATS = {
    "Grocery": ["Snacks", "Beverages", "Dairy", "Pantry"],
    "Health": ["OTC", "Vitamins", "First Aid"],
    "Electronics": ["Accessories", "Audio", "Charging"],
    "Apparel": ["Basics", "Seasonal", "Footwear"],
    "Home": ["Kitchen", "Storage", "Decor"],
    "Beauty": ["Skin", "Hair", "Fragrance"],
    "Automotive": ["Care", "Interior", "Tools"],
    "Toys": ["Building", "Outdoor", "Games"],
}


def _dt_range(rng: np.random.Generator, start: datetime, end: datetime) -> datetime:
    delta = int((end - start).total_seconds())
    return start + timedelta(seconds=int(rng.integers(0, max(delta, 1))))


def _sign_qty(movement_type: str, qty: int) -> int:
    inbound = {
        "opening_balance",
        "receipt",
        "transfer_in",
        "return_in",
        "cycle_count_adjust",
    }
    if movement_type in inbound:
        return abs(qty)
    if movement_type in {"sale", "transfer_out", "damage"}:
        return -abs(qty)
    return qty  # adjustment already signed


class DatasetBuilder:
    def __init__(self, scale: Scale, seed: int, out_dir: Path):
        self.scale = scale
        self.seed = seed
        self.out_dir = out_dir
        self.rng = np.random.default_rng(seed)
        self.start = datetime.fromisoformat(CALENDAR_START)
        self.end = datetime.fromisoformat(CALENDAR_END)
        self.movements: list[dict] = []
        self.ground_truth: list[dict] = []
        self._mov_n = 0
        self._planted_ids: dict[str, list[str]] = defaultdict(list)

    def _next_mov(self) -> str:
        self._mov_n += 1
        return ids.movement_id(self._mov_n)

    def add_movement(self, **kwargs) -> dict:
        row = {
            "movement_id": kwargs.get("movement_id") or self._next_mov(),
            "store_id": kwargs["store_id"],
            "sku_id": kwargs["sku_id"],
            "movement_type": kwargs["movement_type"],
            "qty": _sign_qty(kwargs["movement_type"], int(kwargs["qty"])),
            "unit_cost": round(float(kwargs["unit_cost"]), 2),
            "occurred_at": kwargs["occurred_at"],
            "recorded_at": kwargs.get("recorded_at") or kwargs["occurred_at"],
            "shift_id": kwargs.get("shift_id"),
            "employee_id": kwargs.get("employee_id"),
            "role_id": kwargs.get("role_id"),
            "reason_code": kwargs.get("reason_code"),
            "reference_id": kwargs.get("reference_id"),
            "counterpart_store_id": kwargs.get("counterpart_store_id"),
            "source_system": kwargs.get("source_system", "WMS"),
            "is_voided": int(kwargs.get("is_voided", 0)),
        }
        if row["movement_type"] == "adjustment":
            row["qty"] = int(kwargs["qty"])  # preserve signed adjustment
        self.movements.append(row)
        return row

    def gt(self, entity_type: str, entity_id: str, issue_type: str, expected_decision: str, notes: str):
        self.ground_truth.append(
            {
                "entity_type": entity_type,
                "entity_id": entity_id,
                "issue_type": issue_type,
                "expected_decision": expected_decision,
                "notes": notes,
                "seed": self.seed,
            }
        )
        self._planted_ids[issue_type].append(entity_id)

    def build(self) -> dict[str, pd.DataFrame]:
        stores = self._stores()
        skus = self._skus()
        roles = self._roles()
        employees = self._employees(stores, roles)
        assortment = self._assortment(stores, skus)
        shifts = self._shifts(stores, employees)
        promotions, promo_sku, promo_store = self._promotions(stores, skus)
        self._opening_and_flow(stores, skus, assortment, employees, shifts, promotions, promo_sku, promo_store)
        returns = self._returns(employees)
        counts, balance_events = self._counts_and_balances(assortment, employees, shifts, skus)
        self._inject_edge_cases(stores, skus, assortment, employees, shifts, counts)
        movements = pd.DataFrame(self.movements)
        counts_df = pd.DataFrame(counts)
        alerts, investigations, inv_alerts = self._alerts_and_investigations(
            stores, skus, movements, counts_df, roles, shifts
        )
        tables = {
            "store": stores,
            "sku": skus,
            "employee_role": roles,
            "employee": employees,
            "store_sku_assortment": assortment,
            "shift": shifts,
            "promotion": promotions,
            "promotion_sku": promo_sku,
            "promotion_store": promo_store,
            "inventory_movement": movements,
            "return_event": returns,
            "cycle_count": pd.DataFrame(counts),
            "balance_event": pd.DataFrame(balance_events),
            "shrinkage_alert": alerts,
            "investigation": investigations,
            "investigation_alert": inv_alerts,
            "ground_truth": pd.DataFrame(self.ground_truth),
        }
        return tables

    def _stores(self) -> pd.DataFrame:
        rows = []
        banners = ["YottaMart", "FlexWarehouse", "HarborGo"]
        formats = ["supercenter", "neighborhood", "warehouse", "ecom_fc"]
        for i in range(1, self.scale.n_stores + 1):
            city, state, region = CITIES[(i - 1) % len(CITIES)]
            fmt = formats[(i - 1) % len(formats)]
            status = "active" if i % 37 else "seasonal"
            rows.append(
                {
                    "store_id": ids.store_id(i),
                    "store_code": f"S{i:04d}",
                    "name": f"{city} {fmt.replace('_', ' ').title()} {i:03d}",
                    "banner": banners[i % len(banners)],
                    "format": fmt,
                    "city": city,
                    "state": state,
                    "region": region if region in REGIONS else "West",
                    "timezone": "America/Chicago",
                    "opened_on": (self.start - timedelta(days=365 + i)).date().isoformat(),
                    "closed_on": None,
                    "status": status,
                    "sq_ft": int(18000 + (i * 137) % 90000),
                    "shrink_risk_tier": ["low", "medium", "high"][i % 3],
                }
            )
        return pd.DataFrame(rows)

    def _skus(self) -> pd.DataFrame:
        rows = []
        for i in range(1, self.scale.n_skus + 1):
            cat = CATEGORIES[(i - 1) % len(CATEGORIES)]
            sub = SUBCATS[cat][i % len(SUBCATS[cat])]
            cost = round(float(0.8 + (i % 97) * 0.37), 2)
            retail = round(cost * float(1.25 + (i % 5) * 0.15), 2)
            rows.append(
                {
                    "sku_id": ids.sku_id(i),
                    "upc": f"{700000000000 + i}",
                    "name": f"{cat} {sub} Item {i:04d}",
                    "category": cat,
                    "subcategory": sub,
                    "brand": BRANDS[i % len(BRANDS)],
                    "unit_cost": cost,
                    "unit_retail": retail,
                    "uom": "EA",
                    "perishable": int(cat in {"Grocery", "Beauty"} and i % 4 == 0),
                    "high_theft_risk": int(cat in {"Electronics", "Beauty", "Health"} and i % 3 == 0),
                    "status": "active" if i % 41 else "seasonal",
                    "introduced_on": (self.start - timedelta(days=i % 800)).date().isoformat(),
                }
            )
        return pd.DataFrame(rows)

    def _roles(self) -> pd.DataFrame:
        flags = {
            "cashier": (0, 0, 0, 1),
            "stocker": (1, 0, 1, 0),
            "store_manager": (1, 1, 1, 1),
            "loss_prevention": (1, 0, 1, 0),
            "merchandiser": (0, 0, 1, 0),
            "warehouse_picker": (0, 1, 0, 0),
            "cycle_counter": (0, 0, 1, 0),
        }
        rows = []
        for i, name in enumerate(ROLE_NAMES, start=1):
            a, t, c, r = flags[name]
            rows.append(
                {
                    "role_id": ids.role_id(i),
                    "role_name": name,
                    "can_adjust_inventory": a,
                    "can_approve_transfer": t,
                    "can_perform_count": c,
                    "can_process_return": r,
                    "effective_from": "2025-01-01",
                    "effective_to": None,
                }
            )
        return pd.DataFrame(rows)

    def _employees(self, stores: pd.DataFrame, roles: pd.DataFrame) -> pd.DataFrame:
        rows = []
        store_ids = stores["store_id"].tolist()
        role_ids = roles["role_id"].tolist()
        for i in range(1, self.scale.n_employees + 1):
            rows.append(
                {
                    "employee_id": ids.employee_id(i),
                    "home_store_id": store_ids[(i - 1) % len(store_ids)],
                    "role_id": role_ids[(i - 1) % len(role_ids)],
                    "display_name": f"{FIRST[i % len(FIRST)]} {LAST[i % len(LAST)]}",
                    "hire_date": (self.start - timedelta(days=30 + i % 1200)).date().isoformat(),
                    "status": "active" if i % 29 else "leave",
                }
            )
        return pd.DataFrame(rows)

    def _assortment(self, stores: pd.DataFrame, skus: pd.DataFrame) -> pd.DataFrame:
        rows = []
        sku_ids = skus["sku_id"].tolist()
        per = min(self.scale.skus_per_store, len(sku_ids))
        for s_i, store_id in enumerate(stores["store_id"].tolist(), start=1):
            start = (s_i * 7) % max(len(sku_ids) - per, 1)
            chosen = sku_ids[start : start + per]
            if len(chosen) < per:
                chosen = sku_ids[:per]
            for sku_id in chosen:
                rows.append(
                    {
                        "store_id": store_id,
                        "sku_id": sku_id,
                        "listed_from": "2025-06-01",
                        "listed_to": None,
                        "min_on_hand": 2,
                        "max_on_hand": 80,
                    }
                )
        return pd.DataFrame(rows)

    def _shifts(self, stores: pd.DataFrame, employees: pd.DataFrame) -> pd.DataFrame:
        rows = []
        emp_by_store = defaultdict(list)
        for rec in employees.to_dict("records"):
            emp_by_store[rec["home_store_id"]].append(rec)
        n = 0
        store_ids = stores["store_id"].tolist()
        while n < self.scale.n_shifts:
            sid = store_ids[n % len(store_ids)]
            emps = emp_by_store[sid]
            emp = emps[n % len(emps)]
            day = self.start + timedelta(days=n % 280)
            hour = 6 + (n % 3) * 8
            started = datetime(day.year, day.month, day.day, hour, 0, 0)
            ended = started + timedelta(hours=8)
            n += 1
            rows.append(
                {
                    "shift_id": ids.shift_id(n),
                    "store_id": sid,
                    "employee_id": emp["employee_id"],
                    "role_id": emp["role_id"],
                    "started_at": started.isoformat(sep=" "),
                    "ended_at": ended.isoformat(sep=" "),
                    "status": "closed",
                }
            )
        return pd.DataFrame(rows)

    def _promotions(self, stores, skus):
        promo_rows, ps, pst = [], [], []
        sku_ids = skus["sku_id"].tolist()
        store_ids = stores["store_id"].tolist()
        for i in range(1, self.scale.n_promotions + 1):
            start = self.start + timedelta(days=10 + i * 3)
            end = start + timedelta(days=14)
            pid = ids.promo_id(i)
            promo_rows.append(
                {
                    "promo_id": pid,
                    "name": f"Spring Flex Promo {i:03d}",
                    "promo_type": ["markdown", "bogo", "percent_off"][i % 3],
                    "start_on": start.date().isoformat(),
                    "end_on": end.date().isoformat(),
                    "status": "ended" if end < self.end else "active",
                }
            )
            for sku_id in sku_ids[i : i + 4]:
                ps.append({"promo_id": pid, "sku_id": sku_id, "discount_pct": 10 + (i % 4) * 5})
            for store_id in store_ids[i % len(store_ids) : i % len(store_ids) + 6]:
                pst.append({"promo_id": pid, "store_id": store_id})
        return pd.DataFrame(promo_rows), pd.DataFrame(ps), pd.DataFrame(pst)

    def _shift_lookup(self, shifts: pd.DataFrame) -> dict:
        by_store = defaultdict(list)
        for rec in shifts.to_dict("records"):
            by_store[rec["store_id"]].append(rec)
        return by_store

    def _pick_shift(self, by_store, store_id, when: datetime) -> dict | None:
        options = by_store.get(store_id) or []
        if not options:
            return None
        key = when.isoformat(sep=" ")
        for sh in options:
            if sh["started_at"] <= key <= sh["ended_at"]:
                return sh
        second_of_year = (
            when.timetuple().tm_yday * 86_400
            + when.hour * 3_600
            + when.minute * 60
            + when.second
        )
        return options[second_of_year % len(options)]

    def _opening_and_flow(self, stores, skus, assortment, employees, shifts, promotions, promo_sku, promo_store):
        sku_cost = dict(zip(skus["sku_id"], skus["unit_cost"]))
        by_store = self._shift_lookup(shifts)
        pairs = assortment[["store_id", "sku_id"]].drop_duplicates().to_dict("records")
        rng = self.rng

        for rec in pairs:
            open_qty = int(rng.integers(8, 40))
            occurred = (self.start + timedelta(hours=6)).isoformat(sep=" ")
            self.add_movement(
                store_id=rec["store_id"],
                sku_id=rec["sku_id"],
                movement_type="opening_balance",
                qty=open_qty,
                unit_cost=sku_cost[rec["sku_id"]],
                occurred_at=occurred,
                reason_code="OPENING",
                source_system="ERP",
            )

        remaining = max(self.scale.n_movements - len(self.movements), 100)
        promo_keys = set(zip(promo_store["store_id"], promo_sku["sku_id"])) if len(promo_sku) and len(promo_store) else set()
        promo_skus = set(promo_sku["sku_id"].tolist()) if len(promo_sku) else set()

        types = np.array(["sale", "receipt", "sale", "sale", "transfer_out", "damage", "adjustment", "sale"])
        n_pairs = len(pairs)
        for i in range(remaining):
            pair = pairs[int(rng.integers(0, n_pairs))]
            mtype = str(types[int(rng.integers(0, len(types)))])
            when = _dt_range(rng, self.start + timedelta(days=1), self.end)
            sh = self._pick_shift(by_store, pair["store_id"], when)
            qty = int(rng.integers(1, 6))
            reason = {
                "sale": "SALE_POS",
                "receipt": "RECEIPT_PO",
                "transfer_out": "TRANSFER",
                "damage": "DAMAGE_SHELF" if rng.random() > 0.3 else "EXPIRED",
                "adjustment": "SYSTEM_CORRECTION" if rng.random() > 0.2 else "SUPPLIER_SHORT",
            }[mtype]
            counterpart = None
            if mtype == "transfer_out":
                counterpart = stores.iloc[int(rng.integers(0, len(stores)))]["store_id"]
                if counterpart == pair["store_id"]:
                    counterpart = stores.iloc[(int(rng.integers(0, len(stores))))]["store_id"]
            if mtype == "adjustment":
                qty = int(qty if rng.random() > 0.5 else -qty)
            src = "POS" if mtype == "sale" else "WMS"
            if pair["sku_id"] in promo_skus and mtype == "sale":
                qty = int(qty + rng.integers(0, 3))
            mv = self.add_movement(
                store_id=pair["store_id"],
                sku_id=pair["sku_id"],
                movement_type=mtype,
                qty=qty,
                unit_cost=sku_cost[pair["sku_id"]],
                occurred_at=when.isoformat(sep=" "),
                shift_id=sh["shift_id"] if sh else None,
                employee_id=sh["employee_id"] if sh else None,
                role_id=sh["role_id"] if sh else None,
                reason_code=reason,
                counterpart_store_id=counterpart,
                source_system=src,
                reference_id=f"TX-{i:08d}",
            )
            if mtype == "transfer_out" and counterpart:
                in_time = (when + timedelta(hours=6)).isoformat(sep=" ")
                sh2 = self._pick_shift(by_store, counterpart, when + timedelta(hours=6))
                self.add_movement(
                    store_id=counterpart,
                    sku_id=pair["sku_id"],
                    movement_type="transfer_in",
                    qty=abs(mv["qty"]),
                    unit_cost=sku_cost[pair["sku_id"]],
                    occurred_at=in_time,
                    shift_id=sh2["shift_id"] if sh2 else None,
                    employee_id=sh2["employee_id"] if sh2 else None,
                    role_id=sh2["role_id"] if sh2 else None,
                    reason_code="TRANSFER",
                    counterpart_store_id=pair["store_id"],
                    source_system="WMS",
                    reference_id=mv["movement_id"],
                )
            if mtype == "damage":
                self.gt(
                    "inventory_movement",
                    mv["movement_id"],
                    "legitimate_damage",
                    "close_benign",
                    "Documented damage/expiry; not theft.",
                )

        # trim extra transfer_in so movement count stays near target
        if len(self.movements) > self.scale.n_movements * 1.15:
            # keep all openings; drop random sales only if wildly over — leave as-is for integrity
            pass

        if promo_keys:
            sample_sku = next(iter(promo_skus))
            self.gt(
                "sku",
                sample_sku,
                "promotion_sales_spike",
                "close_benign",
                "Sales lift during promotion should not be scored as shrinkage.",
            )

    def _returns(self, employees: pd.DataFrame) -> pd.DataFrame:
        sales = [m for m in self.movements if m["movement_type"] == "sale"]
        rng = self.rng
        n = min(self.scale.n_returns, len(sales))
        rows = []
        picks = rng.choice(len(sales), size=n, replace=False)
        emp_ids = employees["employee_id"].tolist()
        for j, idx in enumerate(picks, start=1):
            sale = sales[int(idx)]
            qty = min(1, abs(sale["qty"])) or 1
            when = datetime.fromisoformat(str(sale["occurred_at"]).replace(" ", "T")) + timedelta(days=int(rng.integers(1, 12)))
            if when > self.end:
                when = self.end
            mv = self.add_movement(
                store_id=sale["store_id"],
                sku_id=sale["sku_id"],
                movement_type="return_in",
                qty=qty,
                unit_cost=sale["unit_cost"],
                occurred_at=when.isoformat(sep=" "),
                employee_id=emp_ids[j % len(emp_ids)],
                reason_code="RETURN_CUSTOMER",
                reference_id=sale["movement_id"],
                source_system="POS",
            )
            rid = ids.return_id(j)
            rows.append(
                {
                    "return_id": rid,
                    "store_id": sale["store_id"],
                    "sku_id": sale["sku_id"],
                    "qty": qty,
                    "original_sale_movement_id": sale["movement_id"],
                    "return_movement_id": mv["movement_id"],
                    "reason": ["damaged", "unwanted", "wrong_item", "warranty"][j % 4],
                    "condition": ["sellable", "salvage", "destroy"][j % 3],
                    "returned_at": when.isoformat(sep=" "),
                    "employee_id": emp_ids[j % len(emp_ids)],
                }
            )
            self.gt("return_event", rid, "legitimate_return", "close_benign", "Customer return with matching sale.")
        return pd.DataFrame(rows)

    def _replay(self, until: str | None = None) -> dict[tuple[str, str], int]:
        bal: dict[tuple[str, str], int] = defaultdict(int)
        rows = sorted(self.movements, key=lambda r: (r["occurred_at"], r["movement_id"]))
        for m in rows:
            if until and m["occurred_at"] > until:
                continue
            if m["is_voided"]:
                continue
            bal[(m["store_id"], m["sku_id"])] += int(m["qty"])
        return bal

    def _counts_and_balances(self, assortment, employees, shifts, skus) -> tuple[list[dict], list[dict]]:
        rng = self.rng
        pairs = assortment[["store_id", "sku_id"]].to_dict("records")
        by_store = self._shift_lookup(shifts)
        sku_cost = dict(zip(skus["sku_id"], skus["unit_cost"]))
        n = self.scale.n_counts
        meta = []
        for i in range(n):
            pair = pairs[int(rng.integers(0, len(pairs)))]
            when = _dt_range(rng, self.start + timedelta(days=20), self.end)
            meta.append((pair, when, i + 1))
        meta.sort(key=lambda x: x[1])

        counts = []
        balance_events = []
        b_n = 0
        ordered = sorted(self.movements, key=lambda r: (r["occurred_at"], r["movement_id"]))
        bal: dict[tuple[str, str], int] = defaultdict(int)
        cursor = 0
        open_as_of = (self.start + timedelta(hours=6)).isoformat(sep=" ")
        while cursor < len(ordered) and ordered[cursor]["occurred_at"] <= open_as_of:
            m = ordered[cursor]
            if not m["is_voided"]:
                bal[(m["store_id"], m["sku_id"])] += int(m["qty"])
            cursor += 1
        for (store_id, sku_id), qty in list(bal.items()):
            b_n += 1
            balance_events.append(
                {
                    "balance_event_id": ids.balance_event_id(b_n),
                    "store_id": store_id,
                    "sku_id": sku_id,
                    "as_of": open_as_of,
                    "on_hand": qty,
                    "source": "opening",
                    "related_count_id": None,
                }
            )

        unexplained_budget = max(8, n // 30)
        pending_adjusts: list[dict] = []
        for pair, when, seq in meta:
            snapshot = when.isoformat(sep=" ")
            while cursor < len(ordered) and ordered[cursor]["occurred_at"] <= snapshot:
                m = ordered[cursor]
                if not m["is_voided"]:
                    bal[(m["store_id"], m["sku_id"])] += int(m["qty"])
                cursor += 1
            expected = bal.get((pair["store_id"], pair["sku_id"]), 0)
            noise = int(rng.integers(-1, 2))
            counted = max(0, expected + noise)
            issue = None
            if unexplained_budget and expected >= 6 and rng.random() < 0.08:
                counted = max(0, expected - int(rng.integers(3, 8)))
                unexplained_budget -= 1
                issue = "unexplained_loss"
            variance = counted - expected
            sh = self._pick_shift(by_store, pair["store_id"], when)
            cid = ids.count_id(seq)
            posted_mv = None
            status = "posted" if abs(variance) > 0 else "reviewed"
            if status == "posted" and issue != "unexplained_loss":
                adj_at = (when + timedelta(minutes=5)).isoformat(sep=" ")
                mv = self.add_movement(
                    store_id=pair["store_id"],
                    sku_id=pair["sku_id"],
                    movement_type="cycle_count_adjust",
                    qty=variance,
                    unit_cost=sku_cost[pair["sku_id"]],
                    occurred_at=adj_at,
                    shift_id=sh["shift_id"] if sh else None,
                    employee_id=sh["employee_id"] if sh else None,
                    role_id=sh["role_id"] if sh else None,
                    reason_code="COUNT_VARIANCE",
                    reference_id=cid,
                    source_system="COUNT",
                )
                mv["qty"] = variance
                posted_mv = mv["movement_id"]
                pending_adjusts.append(mv)
                bal[(pair["store_id"], pair["sku_id"])] = counted
            rec = {
                "count_id": cid,
                "store_id": pair["store_id"],
                "sku_id": pair["sku_id"],
                "counted_qty": int(counted),
                "expected_qty": int(expected),
                "variance_qty": int(variance),
                "variance_value": round(abs(variance) * float(sku_cost[pair["sku_id"]]), 2),
                "counted_at": snapshot,
                "snapshot_as_of": snapshot,
                "employee_id": sh["employee_id"] if sh else employees.iloc[0]["employee_id"],
                "role_id": sh["role_id"] if sh else employees.iloc[0]["role_id"],
                "shift_id": sh["shift_id"] if sh else None,
                "status": status,
                "posted_movement_id": posted_mv,
            }
            counts.append(rec)
            b_n += 1
            balance_events.append(
                {
                    "balance_event_id": ids.balance_event_id(b_n),
                    "store_id": pair["store_id"],
                    "sku_id": pair["sku_id"],
                    "as_of": snapshot,
                    "on_hand": int(counted),
                    "source": "count_post",
                    "related_count_id": cid,
                }
            )
            if issue == "unexplained_loss":
                self.gt(
                    "cycle_count",
                    cid,
                    "unexplained_loss",
                    "open_alert",
                    "Physical count short versus ledger without matching damage/return.",
                )
        return counts, balance_events

    def _inject_edge_cases(self, stores, skus, assortment, employees, shifts, counts: list[dict]):
        rng = self.rng
        pairs = assortment[["store_id", "sku_id"]].to_dict("records")
        by_store = self._shift_lookup(shifts)
        sku_cost = dict(zip(skus["sku_id"], skus["unit_cost"]))
        store_ids = stores["store_id"].tolist()

        # repeated adjustments
        pair = pairs[0]
        when0 = self.start + timedelta(days=40)
        for k in range(8):
            when = when0 + timedelta(days=k)
            sh = self._pick_shift(by_store, pair["store_id"], when)
            mv = self.add_movement(
                store_id=pair["store_id"],
                sku_id=pair["sku_id"],
                movement_type="adjustment",
                qty=-1,
                unit_cost=sku_cost[pair["sku_id"]],
                occurred_at=when.isoformat(sep=" "),
                shift_id=sh["shift_id"] if sh else None,
                employee_id=sh["employee_id"] if sh else None,
                role_id=sh["role_id"] if sh else None,
                reason_code="SYSTEM_CORRECTION",
                source_system="WMS",
                reference_id=f"REPEAT-{k}",
            )
            self.gt(
                "inventory_movement",
                mv["movement_id"],
                "repeated_adjustments",
                "open_alert",
                "Repeated negative adjustments on the same store/SKU.",
            )

        # adjustment lacks reason
        pair = pairs[min(1, len(pairs) - 1)]
        when = self.start + timedelta(days=55)
        sh = self._pick_shift(by_store, pair["store_id"], when)
        mv = self.add_movement(
            store_id=pair["store_id"],
            sku_id=pair["sku_id"],
            movement_type="adjustment",
            qty=-4,
            unit_cost=sku_cost[pair["sku_id"]],
            occurred_at=when.isoformat(sep=" "),
            shift_id=sh["shift_id"] if sh else None,
            employee_id=sh["employee_id"] if sh else None,
            role_id=sh["role_id"] if sh else None,
            reason_code="",
            source_system="WMS",
            reference_id="ADJ-NO-REASON",
        )
        self.gt(
            "inventory_movement",
            mv["movement_id"],
            "adjustment_missing_reason",
            "open_alert",
            "Inventory adjustment posted without a reason code.",
        )

        # movement refers to wrong store (shift store != movement store)
        pair = pairs[min(2, len(pairs) - 1)]
        other = store_ids[0] if pair["store_id"] != store_ids[0] else store_ids[1]
        when = self.start + timedelta(days=60, hours=10)
        sh = self._pick_shift(by_store, pair["store_id"], when)
        mv = self.add_movement(
            store_id=other,
            sku_id=pair["sku_id"],
            movement_type="sale",
            qty=-2,
            unit_cost=sku_cost[pair["sku_id"]],
            occurred_at=when.isoformat(sep=" "),
            shift_id=sh["shift_id"] if sh else None,
            employee_id=sh["employee_id"] if sh else None,
            role_id=sh["role_id"] if sh else None,
            reason_code="SALE_POS",
            source_system="POS",
            reference_id="WRONG-STORE",
        )
        self.gt(
            "inventory_movement",
            mv["movement_id"],
            "wrong_store_movement",
            "open_alert",
            "Movement store_id does not match the authorized shift store.",
        )

        # count timestamp precedes later receipt; counted includes unreceipted stock
        pair = pairs[min(3, len(pairs) - 1)]
        count_time = self.start + timedelta(days=70, hours=8)
        receipt_time = count_time + timedelta(days=2)
        sh = self._pick_shift(by_store, pair["store_id"], receipt_time)
        rec_mv = self.add_movement(
            store_id=pair["store_id"],
            sku_id=pair["sku_id"],
            movement_type="receipt",
            qty=25,
            unit_cost=sku_cost[pair["sku_id"]],
            occurred_at=receipt_time.isoformat(sep=" "),
            shift_id=sh["shift_id"] if sh else None,
            employee_id=sh["employee_id"] if sh else None,
            role_id=sh["role_id"] if sh else None,
            reason_code="RECEIPT_PO",
            source_system="WMS",
            reference_id="PRECOUNT-RECEIPT",
        )
        expected_map = self._replay(until=count_time.isoformat(sep=" "))
        expected = expected_map.get((pair["store_id"], pair["sku_id"]), 0)
        counted = expected + 25
        cid = ids.count_id(len(counts) + 1)
        shc = self._pick_shift(by_store, pair["store_id"], count_time)
        counts.append(
            {
                "count_id": cid,
                "store_id": pair["store_id"],
                "sku_id": pair["sku_id"],
                "counted_qty": int(counted),
                "expected_qty": int(expected),
                "variance_qty": int(counted - expected),
                "variance_value": round(25 * float(sku_cost[pair["sku_id"]]), 2),
                "counted_at": count_time.isoformat(sep=" "),
                "snapshot_as_of": count_time.isoformat(sep=" "),
                "employee_id": shc["employee_id"] if shc else employees.iloc[0]["employee_id"],
                "role_id": shc["role_id"] if shc else employees.iloc[0]["role_id"],
                "shift_id": shc["shift_id"] if shc else None,
                "status": "submitted",
                "posted_movement_id": None,
            }
        )
        self.gt(
            "cycle_count",
            cid,
            "count_before_movements",
            "open_alert",
            f"Count {cid} precedes receipt {rec_mv['movement_id']} but includes those units.",
        )

        # transfer counted as shrinkage at both ends
        pair = pairs[min(4, len(pairs) - 1)]
        a = pair["store_id"]
        b = store_ids[1] if store_ids[1] != a else store_ids[2 % len(store_ids)]
        t_when = self.start + timedelta(days=80, hours=9)
        sh = self._pick_shift(by_store, a, t_when)
        out_mv = self.add_movement(
            store_id=a,
            sku_id=pair["sku_id"],
            movement_type="transfer_out",
            qty=-6,
            unit_cost=sku_cost[pair["sku_id"]],
            occurred_at=t_when.isoformat(sep=" "),
            shift_id=sh["shift_id"] if sh else None,
            employee_id=sh["employee_id"] if sh else None,
            role_id=sh["role_id"] if sh else None,
            reason_code="TRANSFER",
            counterpart_store_id=b,
            source_system="WMS",
            reference_id="DOUBLE-SHRINK-XFER",
        )
        pre_b = t_when - timedelta(hours=12)
        shb = self._pick_shift(by_store, b, pre_b)
        self.add_movement(
            store_id=b,
            sku_id=pair["sku_id"],
            movement_type="receipt",
            qty=20,
            unit_cost=sku_cost[pair["sku_id"]],
            occurred_at=pre_b.isoformat(sep=" "),
            shift_id=shb["shift_id"] if shb else None,
            employee_id=shb["employee_id"] if shb else None,
            role_id=shb["role_id"] if shb else None,
            reason_code="RECEIPT_PO",
            source_system="WMS",
            reference_id="DOUBLE-SHRINK-DEST-STOCK",
        )
        # missing transfer_in on purpose
        for store_end, extra_notes in ((a, "origin"), (b, "destination")):
            ctime = t_when + timedelta(days=1)
            emap = self._replay(until=ctime.isoformat(sep=" "))
            expected = emap.get((store_end, pair["sku_id"]), 0)
            counted = max(0, expected - 6)
            cid = ids.count_id(len(counts) + 1)
            shx = self._pick_shift(by_store, store_end, ctime)
            counts.append(
                {
                    "count_id": cid,
                    "store_id": store_end,
                    "sku_id": pair["sku_id"],
                    "counted_qty": int(counted),
                    "expected_qty": int(expected),
                    "variance_qty": int(counted - expected),
                    "variance_value": round(6 * float(sku_cost[pair["sku_id"]]), 2),
                    "counted_at": ctime.isoformat(sep=" "),
                    "snapshot_as_of": ctime.isoformat(sep=" "),
                    "employee_id": shx["employee_id"] if shx else employees.iloc[0]["employee_id"],
                    "role_id": shx["role_id"] if shx else employees.iloc[0]["role_id"],
                    "shift_id": shx["shift_id"] if shx else None,
                    "status": "submitted",
                    "posted_movement_id": None,
                }
            )
            self.gt(
                "cycle_count",
                cid,
                "double_counted_transfer",
                "open_alert",
                f"Transfer {out_mv['movement_id']} treated as shrink at {extra_notes} store {store_end}.",
            )

    def _alerts_and_investigations(self, stores, skus, movements, counts, roles, shifts):
        detected = run_detection(
            {
                "inventory_movement": movements,
                "cycle_count": counts,
                "store": stores,
                "sku": skus,
                "shift": shifts,
            }
        )
        alerts = detected if isinstance(detected, pd.DataFrame) else pd.DataFrame(detected)
        if alerts.empty:
            alerts = pd.DataFrame(
                columns=[
                    "alert_id",
                    "store_id",
                    "sku_id",
                    "alert_type",
                    "severity",
                    "score",
                    "evidence_json",
                    "created_at",
                    "status",
                    "related_count_id",
                    "related_movement_id",
                ]
            )
        lp_role = roles.loc[roles["role_name"] == "loss_prevention", "role_id"].iloc[0]
        inv_rows, link_rows = [], []
        high = alerts[alerts["severity"].isin(["high", "critical"])] if len(alerts) else alerts
        for i, rec in enumerate(high.to_dict("records"), start=1):
            iid = ids.investigation_id(i)
            inv_rows.append(
                {
                    "investigation_id": iid,
                    "opened_at": rec["created_at"],
                    "closed_at": None,
                    "owner_role_id": lp_role,
                    "outcome": "pending",
                    "notes": f"Auto-opened from {rec['alert_id']} ({rec['alert_type']}). Evidence retained.",
                    "status": "open",
                }
            )
            link_rows.append({"investigation_id": iid, "alert_id": rec["alert_id"]})
            alerts.loc[alerts["alert_id"] == rec["alert_id"], "status"] = "investigating"
        inv_cols = ["investigation_id", "opened_at", "closed_at", "owner_role_id", "outcome", "notes", "status"]
        link_cols = ["investigation_id", "alert_id"]
        return alerts, pd.DataFrame(inv_rows, columns=inv_cols), pd.DataFrame(link_rows, columns=link_cols)


def write_outputs(tables: dict[str, pd.DataFrame], out_dir: Path, seed: int, scale: Scale) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_dir = out_dir / "csv"
    json_dir = out_dir / "json"
    csv_dir.mkdir(exist_ok=True)
    json_dir.mkdir(exist_ok=True)
    gt = tables.pop("ground_truth")
    checksums = {}
    manifest = []
    for name, df in tables.items():
        csv_path = csv_dir / f"{name}.csv"
        df.to_csv(csv_path, index=False)
        payload = df.head(50).to_dict(orient="records")
        (json_dir / f"{name}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
        digest = hashlib.sha256(csv_path.read_bytes()).hexdigest()
        checksums[name] = {"rows": int(len(df)), "sha256": digest}
        manifest.append({"file": str(csv_path.as_posix()), "rows": int(len(df)), "sha256": digest})
    gt_dir = out_dir / "labels"
    gt_dir.mkdir(exist_ok=True)
    gt_csv = gt_dir / "ground_truth.csv"
    gt.to_csv(gt_csv, index=False)
    (gt_dir / "ground_truth.json").write_text(gt.to_json(orient="records", indent=2), encoding="utf-8")
    checksums["ground_truth"] = {
        "rows": int(len(gt)),
        "sha256": hashlib.sha256(gt_csv.read_bytes()).hexdigest(),
        "note": "Held out from model features / API feature endpoints.",
    }
    summary = {
        "seed": seed,
        "scale": scale.name,
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "row_counts": {k: v["rows"] for k, v in checksums.items()},
        "checksums": checksums,
        "id_conventions": {
            "store": "STORE-000001",
            "sku": "SKU-000001",
            "movement": "MOV-2026-00000001",
            "cycle_count": "CNT-2026-000001",
            "alert": "SHR-2026-000001",
            "investigation": "INV-2026-000001",
        },
        "provenance": {
            "external_data": "none",
            "license": "synthetic-original",
            "retrieval_date": None,
            "notes": "All entities are fully synthetic. No personal data.",
        },
    }
    (out_dir / "source_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (out_dir / "generation_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    tables["ground_truth"] = gt
    _write_sql_seed(tables, out_dir)
    return summary


def _sql_literal(value) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return "NULL"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    text = str(value).replace("'", "''")
    return f"'{text}'"


def _write_sql_seed(tables: dict[str, pd.DataFrame], out_dir: Path) -> None:
    schema = Path(__file__).resolve().parents[1] / "schema.sql"
    sql_dir = out_dir / "sql"
    sql_dir.mkdir(exist_ok=True)
    parts = [schema.read_text(encoding="utf-8"), "\nBEGIN;\n"]
    master = [
        "store",
        "sku",
        "employee_role",
        "employee",
        "store_sku_assortment",
        "shift",
        "promotion",
        "promotion_sku",
        "promotion_store",
    ]
    for name in master:
        df = tables[name]
        cols = ", ".join(df.columns)
        for rec in df.itertuples(index=False, name=None):
            values = ", ".join(_sql_literal(v) for v in rec)
            parts.append(f"INSERT INTO {name} ({cols}) VALUES ({values});\n")
    parts.append("COMMIT;\n")
    (sql_dir / "seed_master.sql").write_text("".join(parts), encoding="utf-8")
    (sql_dir / "schema.sql").write_text(schema.read_text(encoding="utf-8"), encoding="utf-8")
    # Event tables stay in CSV/SQLite; a short comment file documents that.
    (sql_dir / "README.md").write_text(
        "schema.sql — DDL\nseed_master.sql — INSERT seed for parent/master tables.\n"
        "Full event history is in ../csv and ../shrinkage.sqlite (append-only movements/counts/alerts).\n",
        encoding="utf-8",
    )


def generate(scale_name: str = "starter", seed: int = DEFAULT_SEED, out_dir: str | Path = "data/starter") -> dict:
    scale = Scale.from_name(scale_name)
    out = Path(out_dir)
    builder = DatasetBuilder(scale, seed, out)
    tables = builder.build()
    summary = write_outputs(tables, out, seed, scale)
    report = validate_dataset(tables)
    (out / "validation_summary.json").write_text(
        json.dumps(report, indent=2, default=lambda o: bool(o) if hasattr(o, "item") else str(o)),
        encoding="utf-8",
    )
    summary["validation"] = report
    from .db import load_sqlite

    db_path = out / "shrinkage.sqlite"
    load_sqlite(tables, db_path, schema_path=Path(__file__).resolve().parents[1] / "schema.sql")
    summary["sqlite"] = str(db_path)
    return summary
