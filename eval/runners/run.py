"""Evaluation entry point (placeholder until Milestone 10).

Phase 0 only proves the wiring: the manual eval workflow can install the
project, find the datasets folder and write a report. Later this runner will
load the golden set, call the deployed API and compute retrieval and answer
metrics.

    uv run python -m eval.runners.run --datasets eval/datasets --reports eval/reports
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path


def summarise(datasets: Path) -> dict[str, int]:
    """Count questions in every JSON Lines file in the datasets folder."""
    counts: dict[str, int] = {}
    for path in sorted(datasets.glob("*.jsonl")):
        with path.open(encoding="utf-8") as handle:
            counts[path.name] = sum(1 for line in handle if line.strip())
    return counts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the evaluation suite")
    parser.add_argument("--datasets", type=Path, default=Path("eval/datasets"))
    parser.add_argument("--reports", type=Path, default=Path("eval/reports"))
    parser.add_argument("--dry-run", action="store_true", help="count datasets, write nothing")
    args = parser.parse_args(argv)

    counts = summarise(args.datasets)
    generated_at = datetime.now(UTC).isoformat(timespec="seconds")
    report = {
        "generated_at": generated_at,
        "datasets": counts,
        "total_questions": sum(counts.values()),
        "status": "placeholder: metrics arrive in Milestone 10",
    }
    print(json.dumps(report, indent=2))
    if not args.dry_run:
        args.reports.mkdir(parents=True, exist_ok=True)
        out = args.reports / f"{generated_at[:10]}-placeholder.json"
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
