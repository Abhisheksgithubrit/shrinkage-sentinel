import os
import subprocess
import sys

from shrinkage_sentinel.config import DEFAULT_SEED, Scale
from shrinkage_sentinel.ids import alert_id, count_id, investigation_id, movement_id, sku_id, store_id
from shrinkage_sentinel.evaluate import evaluate
from shrinkage_sentinel.generate import generate, DatasetBuilder
from shrinkage_sentinel.validate import validate_dataset
import pandas as pd


def test_id_formats():
    assert store_id(1) == "STORE-000001"
    assert sku_id(1) == "SKU-000001"
    assert movement_id(1) == "MOV-2026-00000001"
    assert count_id(1) == "CNT-2026-000001"
    assert alert_id(1) == "SHR-2026-000001"
    assert investigation_id(1) == "INV-2026-000001"


def test_starter_generation_and_validation(tmp_path):
    summary = generate("starter", DEFAULT_SEED, tmp_path)
    assert summary["seed"] == DEFAULT_SEED
    assert summary["validation"]["status"] == "passed"
    assert summary["row_counts"]["store"] == 10
    assert summary["row_counts"]["sku"] == 80
    assert summary["row_counts"]["inventory_movement"] >= 1000
    assert summary["row_counts"]["cycle_count"] >= 240
    gt = pd.read_csv(tmp_path / "labels" / "ground_truth.csv")
    needed = {
        "unexplained_loss",
        "repeated_adjustments",
        "adjustment_missing_reason",
        "wrong_store_movement",
        "count_before_movements",
        "double_counted_transfer",
        "legitimate_damage",
        "legitimate_return",
    }
    assert needed.issubset(set(gt["issue_type"]))
    moves = pd.read_csv(tmp_path / "csv" / "inventory_movement.csv")
    assert "issue_type" not in moves.columns
    assert "expected_decision" not in moves.columns


def test_same_seed_matches(tmp_path):
    a = generate("starter", DEFAULT_SEED, tmp_path / "a")
    b = generate("starter", DEFAULT_SEED, tmp_path / "b")
    assert a["row_counts"] == b["row_counts"]
    assert a["checksums"]["inventory_movement"]["sha256"] == b["checksums"]["inventory_movement"]["sha256"]
    assert a["checksums"]["ground_truth"]["sha256"] == b["checksums"]["ground_truth"]["sha256"]


def test_shift_selection_is_reproducible_across_processes():
    script = """
from datetime import datetime
from pathlib import Path
from shrinkage_sentinel.config import DEFAULT_SEED, Scale
from shrinkage_sentinel.generate import DatasetBuilder

builder = DatasetBuilder(Scale.from_name("starter"), DEFAULT_SEED, Path("."))
shifts = {"STORE-000001": [{"shift_id": str(i), "started_at": "2026-01-01 08:00:00", "ended_at": "2026-01-01 16:00:00"} for i in range(257)]}
print(builder._pick_shift(shifts, "STORE-000001", datetime(2026, 2, 1)))
"""
    results = []
    for hash_seed in ("1", "2"):
        env = os.environ.copy()
        env["PYTHONHASHSEED"] = hash_seed
        result = subprocess.run(
            [sys.executable, "-c", script],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )
        results.append(result.stdout.strip())
    assert results[0] == results[1]


def test_count_variance_is_derived():
    scale = Scale.from_name("starter")
    tables = DatasetBuilder(scale, DEFAULT_SEED, None).build()
    counts = tables["cycle_count"]
    assert (counts["variance_qty"] == counts["counted_qty"] - counts["expected_qty"]).all()
    report = validate_dataset(tables)
    assert report["passed"].get("gt_not_in_features")


def test_evaluate_catches_planted_patterns(tmp_path):
    generate("starter", DEFAULT_SEED, tmp_path)
    alerts = pd.read_csv(tmp_path / "csv" / "shrinkage_alert.csv")
    gt = pd.read_csv(tmp_path / "labels" / "ground_truth.csv")
    metrics = evaluate(alerts, gt)
    for issue in (
        "unexplained_loss",
        "repeated_adjustments",
        "adjustment_missing_reason",
        "wrong_store_movement",
        "count_before_movements",
        "double_counted_transfer",
    ):
        assert issue in metrics["issue_types_caught"], metrics
    assert "legitimate_damage" in metrics["benign_explanations_represented"]
