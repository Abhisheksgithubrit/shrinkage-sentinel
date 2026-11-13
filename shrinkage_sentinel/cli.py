from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from .config import DEFAULT_SEED
from .generate import generate


def checksum_tree(path: Path) -> dict:
    files = {}
    for p in sorted(path.rglob("*")):
        if p.is_file() and p.suffix in {".csv", ".json"}:
            files[p.relative_to(path).as_posix()] = {
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                "bytes": p.stat().st_size,
            }
    return files


def reproduce(scale: str, seed: int, out_root: Path) -> dict:
    a = out_root / "run_a"
    b = out_root / "run_b"
    generate(scale, seed, a)
    generate(scale, seed, b)
    ca, cb = checksum_tree(a / "csv"), checksum_tree(b / "csv")
    match = ca == cb
    report = {"match": match, "run_a": ca, "run_b": cb}
    (out_root / "reproducibility.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate Shrinkage Sentinel datasets")
    parser.add_argument("--scale", choices=["starter", "full"], default="starter")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--out", default=None, help="Output directory")
    parser.add_argument("--reproduce", action="store_true", help="Generate twice and compare checksums")
    args = parser.parse_args(argv)
    out = Path(args.out or f"data/{args.scale}")
    if args.reproduce:
        report = reproduce(args.scale, args.seed, out.parent / f"repro_{args.scale}")
        print(json.dumps({"reproducible": report["match"]}, indent=2))
        return 0 if report["match"] else 1
    summary = generate(args.scale, args.seed, out)
    print(json.dumps({k: summary[k] for k in ("seed", "scale", "row_counts", "sqlite") if k in summary}, indent=2))
    print("validation:", summary.get("validation", {}).get("status"))
    return 0 if summary.get("validation", {}).get("status") == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
