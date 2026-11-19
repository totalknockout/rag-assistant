from __future__ import annotations

import json
from pathlib import Path

from eval.runners import run


def test_summarise_counts_non_empty_lines(tmp_path: Path) -> None:
    (tmp_path / "golden.jsonl").write_text('{"id": 1}\n\n{"id": 2}\n', encoding="utf-8")
    (tmp_path / "notes.txt").write_text("ignored", encoding="utf-8")

    assert run.summarise(tmp_path) == {"golden.jsonl": 2}


def test_main_writes_a_report(tmp_path: Path) -> None:
    datasets, reports = tmp_path / "datasets", tmp_path / "reports"
    datasets.mkdir()
    (datasets / "golden.jsonl").write_text('{"id": 1}\n', encoding="utf-8")

    exit_code = run.main(["--datasets", str(datasets), "--reports", str(reports)])

    written = list(reports.glob("*.json"))
    assert exit_code == 0
    assert len(written) == 1
    assert json.loads(written[0].read_text(encoding="utf-8"))["total_questions"] == 1


def test_dry_run_writes_nothing(tmp_path: Path) -> None:
    reports = tmp_path / "reports"

    assert run.main(["--datasets", str(tmp_path), "--reports", str(reports), "--dry-run"]) == 0
    assert not reports.exists()
