from __future__ import annotations


def store_id(n: int) -> str:
    return f"STORE-{n:06d}"


def sku_id(n: int) -> str:
    return f"SKU-{n:06d}"


def movement_id(n: int, year: int = 2026) -> str:
    return f"MOV-{year}-{n:08d}"


def count_id(n: int, year: int = 2026) -> str:
    return f"CNT-{year}-{n:06d}"


def alert_id(n: int, year: int = 2026) -> str:
    return f"SHR-{year}-{n:06d}"


def investigation_id(n: int, year: int = 2026) -> str:
    return f"INV-{year}-{n:06d}"


def role_id(n: int) -> str:
    return f"ROLE-{n:06d}"


def employee_id(n: int) -> str:
    return f"EMP-{n:06d}"


def shift_id(n: int, year: int = 2026) -> str:
    return f"SHF-{year}-{n:06d}"


def promo_id(n: int, year: int = 2026) -> str:
    return f"PRM-{year}-{n:06d}"


def return_id(n: int, year: int = 2026) -> str:
    return f"RET-{year}-{n:06d}"


def balance_event_id(n: int, year: int = 2026) -> str:
    return f"BAL-{year}-{n:08d}"
