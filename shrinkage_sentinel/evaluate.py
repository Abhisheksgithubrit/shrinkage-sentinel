from __future__ import annotations

import pandas as pd


ISSUE_TO_ALERT = {
    "unexplained_loss": "unexplained_loss",
    "repeated_adjustments": "repeated_adjustments",
    "adjustment_missing_reason": "adjustment_missing_reason",
    "wrong_store_movement": "wrong_store_movement",
    "count_before_movements": "count_before_movements",
    "double_counted_transfer": "double_counted_transfer",
}


def evaluate(alerts: pd.DataFrame, ground_truth: pd.DataFrame) -> dict:
    """Compare detector output to held-out labels. Not used as a model feature."""
    pos = ground_truth[ground_truth["expected_decision"] == "open_alert"]
    benign = ground_truth[ground_truth["expected_decision"] == "close_benign"]
    alert_types = set(alerts["alert_type"].tolist()) if len(alerts) else set()

    tp = fp_types = 0
    caught_issues = []
    missed = []
    for issue, alert_type in ISSUE_TO_ALERT.items():
        planted = pos[pos["issue_type"] == issue]
        if planted.empty:
            continue
        hit = alert_type in alert_types
        if hit:
            tp += 1
            caught_issues.append(issue)
        else:
            missed.append(issue)

    precision_proxy = None
    if len(alerts):
        suspicious = alerts[alerts["alert_type"].isin(ISSUE_TO_ALERT.values())]
        precision_proxy = round(len(caught_issues) / max(len(set(suspicious["alert_type"])), 1), 3)

    recall = round(len(caught_issues) / max(len(ISSUE_TO_ALERT), 1), 3)
    return {
        "planted_positive_rows": int(len(pos)),
        "planted_benign_rows": int(len(benign)),
        "alert_rows": int(len(alerts)),
        "issue_types_caught": caught_issues,
        "issue_types_missed": missed,
        "pattern_recall": recall,
        "pattern_precision_proxy": precision_proxy,
        "benign_explanations_represented": sorted(set(benign["issue_type"])) if len(benign) else [],
    }
