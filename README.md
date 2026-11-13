# Shrinkage Sentinel

Shrinkage Sentinel is a small, explainable inventory-loss investigation app built for the YottaFlex.ai Associate AI Forward Deployed Engineer candidate challenge. It creates deterministic synthetic retail data, checks inventory records for integrity, applies transparent detection rules, and presents the evidence in a web dashboard.

> **Data notice:** All included stores, products, employees, and transactions are synthetic. The project does not use customer, employee, or other real-world personal data.

## What problem does it solve?

Retail inventory can differ from what the ledger predicts for many reasons: theft, damage, a missed receipt, a bad adjustment, a transfer recorded at only one location, or a counting mistake. A raw stock discrepancy is not proof of theft.

This project gives an operator a way to:

1. Compare physical cycle counts with expected stock reconstructed from movement history.
2. Find suspicious or inconsistent records using explicit rules.
3. Open an alert and inspect its source evidence and related inventory activity.
4. Compare planted challenge scenarios with held-out labels without feeding those labels to the detector.

## Explain it in an interview

### Short explanation

> “I built a small inventory-shrinkage investigation workflow. It generates reproducible synthetic retail operations data, reconstructs expected stock from an append-only movement ledger, and applies explainable rules to identify suspicious discrepancies and process exceptions. A FastAPI service exposes the data and evidence to a dashboard. I validate the generated data and evaluate planted challenge patterns against separate held-out labels. The rules help prioritize investigation; they do not claim that every discrepancy is theft.”

### Suggested walkthrough

1. **Start with the business problem:** A negative stock variance is an exception to investigate, not a theft verdict.
2. **Show the data model:** Stores and SKUs connect to shifts, movements, returns, counts, alerts, and investigations. The SQLite schema defines keys and relationships.
3. **Explain the stock equation:** For a store/SKU pair, expected stock at a count snapshot is the sum of non-voided movement quantities recorded up to that snapshot. Variance is `counted quantity - expected quantity`.
4. **Show the detector:** Walk through one alert and its evidence. For example, an unexplained-loss alert links the expected quantity, the physical count, the variance, and the count ID.
5. **Show the dashboard:** Use the overview for network-level indicators, then open an alert, inspect exceptions, and replay the ledger for one store/SKU.
6. **Explain validation:** The generator checks IDs, relationships, derived variances, and sample ledger reconciliation. Tests also cover deterministic generation and planted patterns.
7. **Be clear about limits:** These are synthetic data and rule-based signals. The evaluation is a challenge-oriented pattern-level measure, not a production model benchmark or proof of theft.

## How it works

```text
Seed + scale
    ↓
Synthetic master data and event history
    ↓
Derived cycle-count expectations and variances
    ↓
Integrity validation ──→ CSV, JSON, SQLite, validation report
    ↓
Rule-based detector ──→ alerts with source evidence
    ↓
FastAPI endpoints ──→ browser dashboard
    ↓
Held-out evaluation (separate from detection features)
```

### Data generation and integrity

The generator builds master data first (stores, SKUs, roles, employees, and assortment), then dependent operational records (shifts, promotions, movements, returns, counts, alerts, and investigations). A seeded NumPy random generator makes the output repeatable across runs.

Inventory movements are signed events: receipts increase stock, sales reduce it, and transfers are represented at their origin and destination. Expected quantities are derived by replaying the movement ledger through the count snapshot; they are not sampled independently. The validator checks primary-key formats and uniqueness, foreign-key references, movement types, count variances, shift date ordering, and sample stock-ledger reconciliation.

### Detection rules

The detector emits scored alerts with JSON evidence and source record IDs. Its rules include:

| Alert rule | What it looks for |
|---|---|
| Unexplained loss | A material negative cycle-count variance |
| Repeated adjustments | At least five negative adjustments for a store/SKU pair, subject to the time-span rule |
| Adjustment missing reason | An adjustment with a blank reason code |
| Wrong-store movement | A movement's store differs from the store on its associated shift |
| Count before movements | A positive count variance followed by a matching receipt |
| Double-counted transfer | An unpaired outbound transfer and negative variances at both locations |
| High shrink rate | Accumulated negative count variance exceeds the configured share of sold units |

These are prioritization rules, not proof of misconduct. Synthetic damage, returns, and promotions provide benign or non-theft context.

### Held-out evaluation

`ground_truth` labels are stored separately under `data/<scale>/labels/` and are not passed into the rule detector as features. The Evaluation screen compares planted issue types with alert types. Its recall and precision-like number are **pattern-level proxies**: they do not match every alert to an individual labeled event and should not be presented as standard production precision/recall.

## Run locally

Python 3.11 or newer is recommended.

```bash
python -m pip install -r requirements.txt
python -m shrinkage_sentinel --scale starter --seed 20261022 --out data/starter
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Then open [http://127.0.0.1:8000](http://127.0.0.1:8000).

The starter database and labels are included, but the generation command above rebuilds them. The app starts with the starter dataset when it is present.

### Run the tests

```bash
python -m pytest -q
```

The tests cover ID formats, starter data generation and validation, repeatability, detector evaluation against planted patterns, and the derived count-variance equation.

### Generate the full challenge dataset

```bash
python -m shrinkage_sentinel --scale full --seed 20261022 --out data/full
```

The full scale is configured for 100 stores, 5,000 SKUs, 1,000,000 base movements, and 20,000 cycle counts. Generation can take significantly longer and use substantially more memory than the starter scale. The full-scale run has not been independently benchmarked as part of this review; do not claim a measured runtime or successful full-scale benchmark unless you run it in your submission environment.

### Check reproducibility

```bash
python -m shrinkage_sentinel --scale starter --seed 20261022 --reproduce
```

This generates two starter datasets and compares CSV checksums. A successful run writes a report under `data/repro_starter/reproducibility.json`.

## Dashboard

The responsive dashboard includes:

- Overview KPIs and alert breakdowns.
- Alert lists and evidence detail, including linked investigations and recent movements.
- Cycle counts, movement history, store/SKU summaries, and operational exceptions.
- Stock-ledger replay for a selected store and SKU.
- Held-out evaluation and a data lab for starter/full generation.

The FastAPI application is in `app/main.py`; the static interface is in `web/`. Interactive API documentation is available at [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) while the app is running.

## Project map

| Path | Purpose |
|---|---|
| `app/main.py` | FastAPI routes and SQLite-backed API |
| `web/` | Dashboard HTML, JavaScript, and styles |
| `shrinkage_sentinel/generate.py` | Seeded synthetic data generator |
| `shrinkage_sentinel/detect.py` | Explainable rule-based detector |
| `shrinkage_sentinel/validate.py` | Data integrity and stock-reconciliation checks |
| `shrinkage_sentinel/evaluate.py` | Pattern-level comparison with held-out labels |
| `shrinkage_sentinel/db.py` | SQLite loading and connection helpers |
| `schema.sql` | Relational schema and constraints |
| `docs/DATA_DICTIONARY.md` | Table and field descriptions |
| `docs/SCHEMA.md` | Entity relationships and lifecycle notes |
| `tests/` | Automated tests |
| `data/starter/` | Included starter CSV, JSON, labels, and SQLite database |

## Challenge requirement check

The supplied guidelines call for runnable code, a public GitHub repository, transparent LLM use and prompt history, and visible reasoning about decisions and validation.

| Requirement | Project status |
|---|---|
| Runnable code and verification steps | Documented above; starter tests and API smoke checks have passed in this environment. |
| Public GitHub repository | Published at [github.com/Abhisheksgithubrit/shrinkage-sentinel](https://github.com/Abhisheksgithubrit/shrinkage-sentinel). |
| Prompt history and AI-use disclosure | This section records the prompts available in the current continuation session. The earlier Cursor prompt history was not present in the workspace; export and append it before treating the prompt-history requirement as complete. |
| Reasoning, assumptions, tests, and limitations | Described above, including the distinction between an alert and a theft finding and the limitations of pattern-level evaluation. |

### AI-use and prompt-history disclosure

The project owner reports that part of the original implementation was done in Cursor. The original Cursor transcript was not available during this review, so it is not reproduced or reconstructed here. Add the actual Cursor prompt/export history before final submission; do not treat the prompts below as a complete record of the earlier work.

In this continuation, an AI assistant reviewed the supplied challenge guidelines and project files, updated this documentation, corrected a source of cross-process nondeterminism in shift selection, and added a regression test. The tests and API smoke checks noted above were run in this environment. The project owner should review the changes, run the project in their own submission environment, and add an accurate account of which AI suggestions they accepted, changed, or rejected.

Prompts available from this continuation:

1. “Plse review all the filles & cointinue my prjct befror i did half in cursor now i am using this, ALso make continue as previous”
2. “continue & also if all prjct done pls do tell & how to explain this prjct tell me & explain neatly wrkng of this prjct in readme file. ALso chck once wht thy told we are used in our prjct. Thn everything is okay thn push to github This is my github - https://github.com/Abhisheksgithubrit , crte once repo & push.”

## Reproducibility and provenance

- Default seed: `20261022` (can be overridden with `--seed`).
- Source data: generated locally; no external or real-person dataset is used.
- Stable IDs include `STORE-000001`, `SKU-000001`, `MOV-2026-00000001`, `CNT-2026-000001`, `SHR-2026-000001`, and `INV-2026-000001`.
- Generator output includes CSV and JSON tables, a SQLite database, a source manifest, generation summary, validation summary, and separate ground-truth labels.

## Current limitations

- The detector is a fixed set of rules, not a trained model; scores prioritize review and are not calibrated theft probabilities.
- The challenge evaluation uses issue-type presence rather than event-level matching, so its precision-like metric is only a proxy.
- The data is synthetic, and the full-scale configuration has not been benchmarked in this review.
- The app is a local demonstration, not a production service: it has no authentication, role-based access enforcement for API users, or production deployment configuration.
- The original Cursor prompt history is still needed to meet the challenge's complete prompt-history requirement.
