"""Embedding model shared by ingestion (passages) and query time (questions)."""

from __future__ import annotations

import os
from functools import cache

from fastembed import TextEmbedding

MODEL = os.environ.get("EMBED_MODEL", "BAAI/bge-small-en-v1.5")
DIMENSIONS = 384


@cache
def _model() -> TextEmbedding:
    return TextEmbedding(model_name=MODEL, cache_dir=os.environ.get("MODEL_DIR", "/opt/models"))


def embed_passages(texts: list[str]) -> list[list[float]]:
    return [vector.tolist() for vector in _model().passage_embed(texts, batch_size=32)]


def embed_query(text: str) -> list[float]:
    vector: list[float] = next(iter(_model().query_embed(text))).tolist()
    return vector
