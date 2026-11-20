"""Document metadata contract shared by every service.

Each uploaded document has a sidecar ``<file>.metadata.json`` whose attributes
sit under a ``metadataAttributes`` key (see corpus/README.md). Validation is
fail-closed: anything that does not match is rejected, never defaulted.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Annotated

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
)

# Callers catch this instead of importing Pydantic directly.
MetadataError = ValidationError

KNOWN_GROUPS: frozenset[str] = frozenset(
    {"all-staff", "hr", "finance", "engineering", "legal", "leadership"}
)


class Classification(StrEnum):
    PUBLIC = "public"
    INTERNAL = "internal"
    CONFIDENTIAL = "confidential"


def _known_groups(groups: list[str]) -> list[str]:
    unknown = sorted(set(groups) - KNOWN_GROUPS)
    if unknown:
        raise ValueError(f"unknown groups: {', '.join(unknown)}")
    return sorted(set(groups))


Groups = Annotated[
    list[str],
    Field(min_length=1),
    AfterValidator(_known_groups),
]


class DocumentAttributes(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    department: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9-]+$")
    allowed_groups: Groups
    version: int = Field(gt=0)
    effective_date: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    classification: Classification


class DocumentMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)

    attributes: DocumentAttributes = Field(alias="metadataAttributes")
