from services.ingest.app.chunk import MAX_WORDS, chunk_document
from services.ingest.app.extract import Block


def _sentences(prefix: str, count: int) -> str:
    return " ".join(f"{prefix} sentence number {i} says something useful." for i in range(count))


def test_chunk_ids_are_stable_for_the_same_version() -> None:
    blocks = [Block("paragraph", _sentences("Leave", 40), page=1, section="Leave")]

    first = chunk_document("doc", "v1", "Policy", blocks)
    second = chunk_document("doc", "v1", "Policy", blocks)
    other_version = chunk_document("doc", "v2", "Policy", blocks)

    assert [c.chunk_id for c in first] == [c.chunk_id for c in second]
    assert not {c.chunk_id for c in first} & {c.chunk_id for c in other_version}


def test_no_chunk_crosses_a_heading() -> None:
    blocks = [
        Block("heading", "Leave", page=1, level=1),
        Block("paragraph", _sentences("Holiday", 3), page=1),
        Block("heading", "Sick pay", page=1, level=2),
        Block("paragraph", _sentences("Sick", 3), page=1),
    ]

    chunks = chunk_document("doc", "v1", "Policy", blocks)

    assert [c.section for c in chunks] == ["Leave", "Leave > Sick pay"]
    assert "Sick sentence" not in chunks[0].text
    assert "Holiday sentence" not in chunks[1].text


def test_long_table_is_split_by_rows_with_header_repeated() -> None:
    header = "Year | Days"
    rows = [f"{year} | {25 + year % 3}" for year in range(2000, 2200)]
    blocks = [Block("table", "\n".join([header, *rows]), page=2, section="Holidays")]

    chunks = chunk_document("doc", "v1", "Policy", blocks)

    assert len(chunks) > 1
    for chunk in chunks:
        lines = chunk.text.split("\n")
        assert lines[0] == header
        assert len(lines) > 1
        assert all(line in rows for line in lines[1:])
    assert sum(len(c.text.split("\n")) - 1 for c in chunks) == len(rows)


def test_chunks_never_exceed_the_hard_cap() -> None:
    blocks = [Block("paragraph", _sentences("Benefit", 120), page=1)]

    chunks = chunk_document("doc", "v1", "Policy", blocks)

    assert len(chunks) > 1
    assert all(len(c.text.split()) <= MAX_WORDS for c in chunks)
