"""Ingest Lambda: registers each uploaded document in the DynamoDB registry.

Messages arrive from SQS. Each one is an EventBridge S3 event. A failed record
is reported back per message, so one bad file does not retry the whole batch.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
from dataclasses import asdict
from datetime import UTC, datetime
from functools import cache
from pathlib import PurePosixPath
from typing import TYPE_CHECKING, Any

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
from aws_lambda_powertools import Logger
from botocore.exceptions import ClientError
from rag_shared.embed import MODEL as EMBEDDING_MODEL
from rag_shared.embed import embed_passages
from rag_shared.models import DocumentAttributes, DocumentMetadata, MetadataError
from rag_shared.schema import CHUNK_SCHEMA

from .chunk import chunk_document
from .extract import EXTRACTOR_VERSION, Extraction, UnreadableFileError, extract

if TYPE_CHECKING:
    from aws_lambda_powertools.utilities.typing import LambdaContext
    from mypy_boto3_dynamodb.service_resource import Table
    from mypy_boto3_s3 import S3Client

LOG = Logger(service="ingest")
SIDECAR_SUFFIX = ".metadata.json"


@cache
def _s3() -> S3Client:
    return boto3.client("s3")


@cache
def _table() -> Table:
    return boto3.resource("dynamodb").Table(os.environ["DOCUMENTS_TABLE"])


def doc_id_for(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:20]


def _now() -> str:
    return datetime.now(UTC).isoformat()


def _summarise(exc: MetadataError) -> str:
    # Field paths and error types only: pydantic messages can contain the rejected value.
    return "; ".join(f"{'.'.join(str(p) for p in e['loc'])}: {e['type']}" for e in exc.errors())


def _mark_deleted(doc_id: str) -> str:
    try:
        _table().update_item(
            Key={"doc_id": doc_id},
            UpdateExpression="SET #s = :s, updated_at = :t",
            ConditionExpression="attribute_exists(doc_id)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "DELETED", ":t": _now()},
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "delete-unknown"
        raise
    return "deleted"


def _previous(doc_id: str) -> dict[str, Any]:
    item: dict[str, Any] = (
        _table()
        .get_item(
            Key={"doc_id": doc_id},
            ProjectionExpression="version_id, sha256, processed_key, chunks_key",
        )
        .get("Item", {})
    )
    return item


def _read_metadata(bucket: str, key: str) -> DocumentMetadata:
    body = _s3().get_object(Bucket=bucket, Key=key + SIDECAR_SUFFIX)["Body"].read()
    return DocumentMetadata.model_validate_json(body)


def _summary(extraction: Extraction) -> dict[str, int]:
    return {
        "pages": len(extraction.pages),
        "ocr_pages": extraction.ocr_pages,
        "characters": extraction.characters,
    }


def _write_chunks(
    bucket: str,
    key: str,
    doc_id: str,
    version: str,
    attributes: DocumentAttributes,
    extraction: Extraction,
) -> dict[str, Any]:
    title = PurePosixPath(key).stem
    chunks = chunk_document(doc_id, version, title, extraction.blocks)
    vectors = embed_passages([c.embed_text for c in chunks]) if chunks else []
    rows = [
        {
            "chunk_id": chunk.chunk_id,
            "doc_id": doc_id,
            "doc_version": attributes.version,
            "series_id": doc_id,
            "title": title,
            "section": chunk.section,
            "page": chunk.page,
            "text": chunk.text,
            "department": attributes.department,
            "allowed_groups": attributes.allowed_groups,
            "classification": attributes.classification.value,
            "source_key": key,
            "embedding_model": EMBEDDING_MODEL,
            "vector": vector,
        }
        for chunk, vector in zip(chunks, vectors, strict=True)
    ]
    buffer = io.BytesIO()
    pq.write_table(pa.Table.from_pylist(rows, schema=CHUNK_SCHEMA), buffer)
    chunks_key = f"processed/{doc_id}/{version}/chunks.parquet"
    _s3().put_object(
        Bucket=bucket,
        Key=chunks_key,
        Body=buffer.getvalue(),
        ContentType="application/vnd.apache.parquet",
    )
    return {"chunks_key": chunks_key, "chunk_count": len(chunks)}


def _process(
    bucket: str,
    key: str,
    doc_id: str,
    version: str,
    previous: dict[str, Any],
    attributes: DocumentAttributes,
) -> dict[str, Any]:
    """Extract and chunk a new version, or mark it UNCHANGED when its bytes match the last one."""
    data = _s3().get_object(Bucket=bucket, Key=key)["Body"].read()
    digest = hashlib.sha256(data).hexdigest()
    if previous.get("sha256") == digest and previous.get("chunks_key"):
        return {
            "status": "UNCHANGED",
            "sha256": digest,
            "processed_key": previous["processed_key"],
            "chunks_key": previous["chunks_key"],
        }
    try:
        extraction = extract(key, data)
    except UnreadableFileError as exc:
        return {"status": "REJECTED", "error": str(exc)}

    processed_key = f"processed/{doc_id}/{version}/extracted.json"
    document = {
        "source_key": key,
        "sha256": digest,
        "extractor_version": EXTRACTOR_VERSION,
        "pages": [asdict(page) for page in extraction.pages],
        "blocks": [asdict(block) for block in extraction.blocks],
    }
    _s3().put_object(
        Bucket=bucket,
        Key=processed_key,
        Body=json.dumps(document).encode(),
        ContentType="application/json",
    )
    return {
        "status": "CHUNKED",
        "sha256": digest,
        "processed_key": processed_key,
        "extractor_version": EXTRACTOR_VERSION,
        "embedding_model": EMBEDDING_MODEL,
        **_summary(extraction),
        **_write_chunks(bucket, key, doc_id, version, attributes, extraction),
    }


def handle(detail_type: str, detail: dict[str, Any]) -> str:
    bucket: str = detail["bucket"]["name"]
    key: str = detail["object"]["key"]
    if key.endswith(SIDECAR_SUFFIX):
        return "skipped-sidecar"
    doc_id = doc_id_for(key)
    if detail_type == "Object Deleted":
        return _mark_deleted(doc_id)

    version = str(detail["object"].get("version-id", "null"))
    previous = _previous(doc_id)
    if previous.get("version_id") == version:
        return "duplicate"

    item: dict[str, Any] = {
        "doc_id": doc_id,
        "s3_key": key,
        "version_id": version,
        "updated_at": _now(),
    }
    try:
        metadata = _read_metadata(bucket, key)
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "NoSuchKey":
            raise
        item |= {"status": "REJECTED", "error": "missing metadata sidecar"}
    except MetadataError as exc:
        item |= {"status": "REJECTED", "error": _summarise(exc)}  # fail closed, never retried
    else:
        item |= {
            "metadata": metadata.attributes.model_dump(mode="json"),
            **_process(bucket, key, doc_id, version, previous, metadata.attributes),
        }

    try:
        _table().put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(doc_id) OR version_id <> :v",
            ExpressionAttributeValues={":v": version},
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "duplicate"
        raise
    return str(item["status"]).lower()


@LOG.inject_lambda_context
def lambda_handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    failures: list[dict[str, str]] = []
    for record in event["Records"]:
        key = "unknown"
        try:
            message: dict[str, Any] = json.loads(record["body"])
            key = message["detail"]["object"]["key"]
            outcome = handle(message["detail-type"], message["detail"])
            LOG.info("processed", extra={"outcome": outcome, "key": key})
        except Exception:
            LOG.exception("failed", extra={"message_id": record["messageId"], "key": key})
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
