"""Splits extracted blocks into retrieval-sized chunks. A chunk never crosses a heading."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, replace

from .extract import Block

TARGET_WORDS, MAX_WORDS, OVERLAP_WORDS = 250, 320, 40
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


@dataclass(frozen=True)
class Chunk:
    chunk_id: str
    ordinal: int
    section: str
    page: int
    text: str  # shown to users and read by the reranker
    embed_text: str  # title and section path prepended; used only for the embedding


def _words(text: str) -> int:
    return len(text.split())


def _block_words(blocks: list[Block]) -> int:
    return sum(_words(b.text) for b in blocks)


def _split_table(block: Block, max_words: int) -> list[Block]:
    header, *rows = block.text.split("\n")
    pieces: list[list[str]] = []
    current = [header]
    for row in rows:
        if len(current) > 1 and _words("\n".join([*current, row])) > max_words:
            pieces.append(current)
            current = [header]
        current.append(row)
    pieces.append(current)
    return [replace(block, text="\n".join(piece)) for piece in pieces]


def _split_text(block: Block, max_words: int) -> list[Block]:
    units: list[str] = []
    for sentence in _SENTENCE_END.split(block.text):
        words = sentence.split()
        units.extend(" ".join(words[i : i + max_words]) for i in range(0, len(words), max_words))
    pieces: list[str] = []
    current: list[str] = []
    for unit in units:
        if current and _words(" ".join([*current, unit])) > max_words:
            pieces.append(" ".join(current))
            current = []
        current.append(unit)
    if current:
        pieces.append(" ".join(current))
    return [replace(block, text=piece) for piece in pieces]


def split_long(block: Block, max_words: int) -> list[Block]:
    if _words(block.text) <= max_words:
        return [block]
    if block.kind == "table":
        return _split_table(block, max_words)
    return _split_text(block, max_words)


def _overlap_tail(blocks: list[Block]) -> list[Block]:
    """The last blocks, up to OVERLAP_WORDS, all on the same page as the chunk's end."""
    tail: list[Block] = []
    words = 0
    for block in reversed(blocks):
        if block.page != blocks[-1].page:
            break
        n = _words(block.text)
        if words + n > OVERLAP_WORDS:
            break
        tail.insert(0, block)
        words += n
    return tail


def chunk_document(doc_id: str, version: str, title: str, blocks: list[Block]) -> list[Chunk]:
    chunks: list[Chunk] = []
    path: list[str] = []
    tail: list[Block] = []  # carried over from the previous chunk in the same section
    body: list[Block] = []  # new content for the chunk being built

    def emit() -> None:
        nonlocal tail, body
        if not body:
            return
        members = tail + body
        section, n = " > ".join(path), len(chunks)
        text = "\n\n".join(b.text for b in members)
        chunks.append(
            Chunk(
                chunk_id=hashlib.sha256(f"{doc_id}:{version}:{n}".encode()).hexdigest()[:24],
                ordinal=n,
                section=section,
                page=members[0].page,
                text=text,
                embed_text=f"{title}\n{section}\n\n{text}",
            )
        )
        tail = _overlap_tail(members)
        body = []

    for block in blocks:
        if block.kind == "heading":
            emit()
            tail = []
            path[:] = [*path[: max(block.level - 1, 0)], block.text]
            continue
        for piece in split_long(block, MAX_WORDS):
            if body and _block_words(tail + body) + _words(piece.text) > TARGET_WORDS:
                emit()
            if not body and _block_words(tail) + _words(piece.text) > TARGET_WORDS:
                tail = []
            body.append(piece)
    emit()
    return chunks
