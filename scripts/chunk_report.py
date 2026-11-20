"""Summarise chunk sizes across every processed document in the docs bucket.

usage: python -m scripts.chunk_report --bucket <docs-bucket> [--out eval/reports]
"""

from __future__ import annotations

import argparse
import io
import json
import math
from datetime import date
from pathlib import Path
from typing import Any

import boto3
import pyarrow.parquet as pq

from services.ingest.app.chunk import MAX_WORDS

SHORT_CHUNK_WORDS = 30


def _percentile(sorted_values: list[int], pct: float) -> int:
    rank = max(math.ceil(pct / 100 * len(sorted_values)) - 1, 0)
    return sorted_values[rank]


def _chunk_word_counts(bucket: str) -> dict[str, list[int]]:
    s3: Any = boto3.client("s3")
    counts: dict[str, list[int]] = {}
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix="processed/"):
        for obj in page.get("Contents", []):
            key: str = obj["Key"]
            if not key.endswith("/chunks.parquet"):
                continue
            body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
            texts = pq.read_table(io.BytesIO(body), columns=["text"]).column("text")
            counts[key] = [len(str(t).split()) for t in texts]
    return counts


def build_report(counts: dict[str, list[int]]) -> dict[str, Any]:
    all_counts = sorted(n for doc in counts.values() for n in doc)
    if not all_counts:
        return {"documents": 0, "chunks": 0}
    at_cap = sum(1 for n in all_counts if n >= MAX_WORDS)
    return {
        "documents": len(counts),
        "chunks": len(all_counts),
        "chunks_per_document": {key: len(doc) for key, doc in sorted(counts.items())},
        "words_p5": _percentile(all_counts, 5),
        "words_p50": _percentile(all_counts, 50),
        "words_p95": _percentile(all_counts, 95),
        "share_at_cap": round(at_cap / len(all_counts), 4),
        "cap_words": MAX_WORDS,
        "chunks_under_30_words": sum(1 for n in all_counts if n < SHORT_CHUNK_WORDS),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--out", type=Path, default=Path("eval/reports"))
    args = parser.parse_args()

    report = build_report(_chunk_word_counts(args.bucket))
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / f"chunks-{date.today().isoformat()}.json"
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "chunks_per_document"}, indent=2))
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
