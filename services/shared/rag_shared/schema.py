"""Column layout of chunks.parquet. Ingestion writes it; the Phase 4 index reads it."""

from __future__ import annotations

import pyarrow as pa

from .embed import DIMENSIONS

CHUNK_SCHEMA = pa.schema(
    [
        ("chunk_id", pa.string()),
        ("doc_id", pa.string()),
        ("doc_version", pa.int64()),
        ("series_id", pa.string()),
        ("title", pa.string()),
        ("section", pa.string()),
        ("page", pa.int32()),
        ("text", pa.string()),
        ("department", pa.string()),
        ("allowed_groups", pa.list_(pa.string())),
        ("classification", pa.string()),
        ("source_key", pa.string()),
        ("embedding_model", pa.string()),
        ("vector", pa.list_(pa.float32(), DIMENSIONS)),
    ]
)
