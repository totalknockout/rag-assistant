"""Turns an uploaded document into ordered blocks of text with page numbers.

Digital PDF text comes from pypdf. A page with almost no text layer is rendered and
read by RapidOCR, which ships its models inside the pip package, so the Lambda image
needs no system packages (Tesseract is not packaged for Amazon Linux 2023).
"""

from __future__ import annotations

import io
import re
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from functools import cache
from pathlib import PurePosixPath
from typing import TYPE_CHECKING, Literal
from zipfile import BadZipFile

import numpy as np
from docx import Document
from docx.opc.exceptions import PackageNotFoundError
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from pypdfium2 import PdfDocument, PdfiumError  # type: ignore[import-untyped]
from rapidocr import RapidOCR
from rapidocr.utils.output import RapidOCROutput

if TYPE_CHECKING:
    from PIL.Image import Image

EXTRACTOR_VERSION = "1"
MIN_TEXT_CHARS = 40  # below this a page is treated as scanned and OCR'd
OCR_SCALE = 300 / 72  # render at 300 dpi
HEADING_MAX_CHARS = 80
HEADING_MAX_WORDS = 10
_NUMBERED = re.compile(r"^\d+(\.\d+)*\s+\S")
_MARKDOWN_HEADING = re.compile(r"^(#{1,6})\s+(.+)$")

Kind = Literal["heading", "paragraph", "table"]


class UnreadableFileError(Exception):
    """The file type is unsupported or the file cannot be parsed. Not retried."""


@dataclass(frozen=True)
class Block:
    kind: Kind
    text: str
    page: int
    level: int = 0
    section: str = ""


@dataclass(frozen=True)
class PageStat:
    page: int
    characters: int
    ocr: bool
    confidence: float


@dataclass
class Extraction:
    blocks: list[Block] = field(default_factory=list)
    pages: list[PageStat] = field(default_factory=list)

    @property
    def ocr_pages(self) -> int:
        return sum(1 for page in self.pages if page.ocr)

    @property
    def characters(self) -> int:
        return sum(page.characters for page in self.pages)


def is_heading(line: str) -> bool:
    text = line.strip()
    if not text or len(text) > HEADING_MAX_CHARS or text.endswith((".", ";", ",")):
        return False
    if _NUMBERED.match(text):
        return True
    return text.isupper() or (text.istitle() and len(text.split()) <= HEADING_MAX_WORDS)


def heading_level(line: str) -> int:
    match = _NUMBERED.match(line.strip())
    # "3.2 Leave" is level 2; anything unnumbered is level 1.
    return line.split()[0].count(".") + 1 if match else 1


def split_blocks(text: str) -> list[tuple[Kind, int, str]]:
    """Return (kind, level, text) tuples. Wrapped lines are joined into paragraphs."""
    out: list[tuple[Kind, int, str]] = []
    lines: list[str] = []

    def flush() -> None:
        if lines:
            out.append(("paragraph", 0, " ".join(lines)))
            lines.clear()

    for raw in text.splitlines():
        line = raw.strip()
        markdown = _MARKDOWN_HEADING.match(line)
        if markdown:
            flush()
            out.append(("heading", len(markdown.group(1)), markdown.group(2).strip()))
        elif is_heading(line):
            flush()
            out.append(("heading", heading_level(line), line))
        elif line:
            lines.append(line)
        else:
            flush()
    flush()
    return out


def _with_sections(blocks: list[Block]) -> list[Block]:
    """Stamp each block with its heading path, e.g. 'Leave > Sick pay'."""
    stack: list[tuple[int, str]] = []
    stamped: list[Block] = []
    for block in blocks:
        if block.kind == "heading":
            while stack and stack[-1][0] >= block.level:
                stack.pop()
            stack.append((block.level, block.text))
        stamped.append(replace(block, section=" > ".join(title for _, title in stack)))
    return stamped


def _text_blocks(text: str, page: int) -> list[Block]:
    return [Block(kind, body, page, level) for kind, level, body in split_blocks(text) if body]


@cache
def _ocr_engine() -> RapidOCR:
    return RapidOCR()


def _ocr_image(image: Image) -> tuple[str, float]:
    output = _ocr_engine()(np.asarray(image.convert("RGB")))
    if not isinstance(output, RapidOCROutput):
        raise TypeError("RapidOCR returned an unexpected result type")
    texts = list(output.txts or ())
    scores = list(output.scores or ())
    confidence = float(sum(scores) / len(scores)) if scores else 0.0
    return "\n".join(texts), confidence


def extract_pdf(data: bytes) -> Extraction:
    reader = PdfReader(io.BytesIO(data))
    rendered = PdfDocument(data)
    result = Extraction()
    for number, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        ocr, confidence = False, 1.0
        if len(text.strip()) < MIN_TEXT_CHARS:
            image = rendered[number - 1].render(scale=OCR_SCALE).to_pil()
            text, confidence = _ocr_image(image)
            ocr = True
        result.pages.append(PageStat(number, len(text.strip()), ocr, confidence))
        result.blocks.extend(_text_blocks(text, number))
    result.blocks = _with_sections(result.blocks)
    return result


def extract_docx(data: bytes) -> Extraction:
    doc = Document(io.BytesIO(data))
    blocks: list[Block] = []
    # Walk the body in order so tables stay where they sit between paragraphs.
    for child in doc.element.body.iterchildren():
        if child.tag == qn("w:p"):
            para = Paragraph(child, doc)
            text = para.text.strip()
            if not text:
                continue
            style = para.style.name if para.style else ""
            if style.startswith("Heading"):
                suffix = style.split()[-1]
                level = int(suffix) if suffix.isdigit() else 1
                blocks.append(Block("heading", text, 1, level))
            else:
                blocks.append(Block("paragraph", text, 1))
        elif child.tag == qn("w:tbl"):
            rows = [
                " | ".join(cell.text.strip() for cell in row.cells)
                for row in Table(child, doc).rows
            ]
            blocks.append(Block("table", "\n".join(rows), 1))
    total = sum(len(block.text) for block in blocks)
    return Extraction(
        blocks=_with_sections(blocks),
        pages=[PageStat(1, total, False, 1.0)],
    )


def extract_text(data: bytes) -> Extraction:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise UnreadableFileError("text file is not UTF-8") from exc
    blocks = _with_sections(_text_blocks(text, 1))
    return Extraction(blocks=blocks, pages=[PageStat(1, len(text.strip()), False, 1.0)])


_PARSERS: dict[str, Callable[[bytes], Extraction]] = {
    ".pdf": extract_pdf,
    ".docx": extract_docx,
    ".txt": extract_text,
    ".md": extract_text,
}
_PARSE_ERRORS = (
    PdfReadError,
    PdfiumError,
    PackageNotFoundError,
    BadZipFile,
    ValueError,
    KeyError,
    IndexError,
    SyntaxError,  # lxml's XML parse error subclasses SyntaxError
)


def extract(key: str, data: bytes) -> Extraction:
    suffix = PurePosixPath(key).suffix.lower()
    parser = _PARSERS.get(suffix)
    if parser is None:
        raise UnreadableFileError(f"unsupported file type '{suffix or 'none'}'")
    try:
        return parser(data)
    except UnreadableFileError:
        raise
    except _PARSE_ERRORS as exc:
        raise UnreadableFileError(f"could not parse {suffix}: {type(exc).__name__}") from exc
