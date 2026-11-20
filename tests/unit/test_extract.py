from __future__ import annotations

import io

import pytest
from docx import Document

from services.ingest.app.extract import UnreadableFileError, extract


def test_text_blocks_carry_their_heading_path() -> None:
    text = b"# Leave\n\n3.2 Sick pay\nStaff are paid for ten days.\n\nKeep records\nof absence.\n"

    blocks = extract("raw/hr/policy.md", text).blocks

    assert [(b.kind, b.level, b.section) for b in blocks] == [
        ("heading", 1, "Leave"),
        ("heading", 2, "Leave > 3.2 Sick pay"),
        ("paragraph", 0, "Leave > 3.2 Sick pay"),
        ("paragraph", 0, "Leave > 3.2 Sick pay"),
    ]
    assert blocks[-1].text == "Keep records of absence."


def test_docx_tables_stay_in_body_order() -> None:
    document = Document()
    document.add_heading("Benefits", level=1)
    document.add_paragraph("Before the table.")
    table = document.add_table(rows=1, cols=2)
    table.rows[0].cells[0].text = "Plan"
    table.rows[0].cells[1].text = "Days"
    document.add_paragraph("After the table.")
    buffer = io.BytesIO()
    document.save(buffer)

    blocks = extract("raw/hr/benefits.docx", buffer.getvalue()).blocks

    assert [b.kind for b in blocks] == ["heading", "paragraph", "table", "paragraph"]
    assert blocks[2].text == "Plan | Days"


def test_unsupported_type_is_unreadable() -> None:
    with pytest.raises(UnreadableFileError, match=r"unsupported file type '\.xlsx'"):
        extract("raw/hr/sheet.xlsx", b"PK")


def test_corrupt_pdf_is_unreadable_not_a_crash() -> None:
    with pytest.raises(UnreadableFileError, match=r"could not parse \.pdf"):
        extract("raw/hr/broken.pdf", b"not a pdf")
