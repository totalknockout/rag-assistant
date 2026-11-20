from __future__ import annotations

import io
import json
from collections.abc import Iterator
from types import SimpleNamespace
from typing import Any

import boto3
import pyarrow.parquet as pq
import pytest
from moto import mock_aws

from services.ingest.app import handler

BUCKET = "rag-assistant-test-docs"
TABLE = "rag-assistant-test-documents"
KEY = "raw/hr/leave-policy.txt"
DOCUMENT = b"Leave Policy\n\n3.2 Sick pay\nStaff are paid for up to ten days of sick leave.\n"


def _fake_embed(texts: list[str]) -> list[list[float]]:
    return [[0.0] * 384 for _ in texts]


def _sidecar(**overrides: Any) -> bytes:
    attributes: dict[str, Any] = {
        "department": "hr",
        "allowed_groups": ["all-staff"],
        "version": 1,
        "effective_date": "2025-01-01",
        "classification": "internal",
    } | overrides
    return json.dumps({"metadataAttributes": attributes}).encode()


def _event(
    key: str = KEY, version: str = "v1", deleted: bool = False
) -> tuple[str, dict[str, Any]]:
    detail_type = "Object Deleted" if deleted else "Object Created"
    detail: dict[str, Any] = {"bucket": {"name": BUCKET}, "object": {"key": key}}
    if not deleted:
        detail["object"]["version-id"] = version
    return detail_type, detail


@pytest.fixture
def aws(monkeypatch: pytest.MonkeyPatch) -> Iterator[Any]:
    monkeypatch.setenv("DOCUMENTS_TABLE", TABLE)
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-west-2")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    with mock_aws():
        handler._s3.cache_clear()
        handler._table.cache_clear()
        s3 = boto3.client("s3", region_name="us-west-2")
        s3.create_bucket(
            Bucket=BUCKET,
            CreateBucketConfiguration={"LocationConstraint": "us-west-2"},
            ObjectOwnership="BucketOwnerEnforced",
        )
        s3.put_bucket_versioning(Bucket=BUCKET, VersioningConfiguration={"Status": "Enabled"})
        s3.put_object(Bucket=BUCKET, Key=KEY, Body=DOCUMENT)
        monkeypatch.setattr(handler, "embed_passages", _fake_embed)
        boto3.client("dynamodb", region_name="us-west-2").create_table(
            TableName=TABLE,
            AttributeDefinitions=[{"AttributeName": "doc_id", "AttributeType": "S"}],
            KeySchema=[{"AttributeName": "doc_id", "KeyType": "HASH"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield s3
        handler._s3.cache_clear()
        handler._table.cache_clear()


def _row(key: str = KEY) -> dict[str, Any]:
    table = boto3.resource("dynamodb", region_name="us-west-2").Table(TABLE)
    item: dict[str, Any] = table.get_item(Key={"doc_id": handler.doc_id_for(key)})["Item"]
    return item


def _context() -> SimpleNamespace:
    return SimpleNamespace(
        function_name="ingest",
        memory_limit_in_mb=512,
        invoked_function_arn="arn:aws:lambda:us-west-2:000000000000:function:ingest",
        aws_request_id="test-request",
    )


def test_valid_upload_is_extracted_with_section_paths(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())

    assert handler.handle(*_event()) == "chunked"
    row = _row()
    assert row["status"] == "CHUNKED"
    assert row["metadata"]["department"] == "hr"
    processed = json.loads(aws.get_object(Bucket=BUCKET, Key=row["processed_key"])["Body"].read())
    sick_pay = [
        b
        for b in processed["blocks"]
        if b["text"] == "Staff are paid for up to ten days of sick leave."
    ]
    assert sick_pay[0]["section"] == "Leave Policy > 3.2 Sick pay"


def test_chunks_parquet_carries_permissions_and_model(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())

    handler.handle(*_event())
    row = _row()
    body = aws.get_object(Bucket=BUCKET, Key=row["chunks_key"])["Body"].read()
    table = pq.read_table(io.BytesIO(body)).to_pylist()
    assert row["chunk_count"] == len(table) == 1
    assert table[0]["allowed_groups"] == ["all-staff"]
    assert table[0]["department"] == "hr"
    assert table[0]["embedding_model"] == "BAAI/bge-small-en-v1.5"
    assert len(table[0]["vector"]) == 384


def test_same_version_twice_is_a_duplicate(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())
    kind, detail = _event()
    handler.handle(kind, detail)

    assert handler.handle(kind, detail) == "duplicate"


def test_identical_bytes_in_a_new_version_are_unchanged(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())
    handler.handle(*_event(version="v1"))
    processed_key = _row()["processed_key"]

    assert handler.handle(*_event(version="v2")) == "unchanged"
    row = _row()
    assert row["version_id"] == "v2"
    assert row["processed_key"] == processed_key


def test_unsupported_file_type_is_rejected(aws: Any) -> None:
    key = "raw/hr/leave-policy.xlsx"
    aws.put_object(Bucket=BUCKET, Key=key, Body=b"PK")
    aws.put_object(Bucket=BUCKET, Key=key + handler.SIDECAR_SUFFIX, Body=_sidecar())

    assert handler.handle(*_event(key=key)) == "rejected"
    assert _row(key)["error"] == "unsupported file type '.xlsx'"


def test_missing_sidecar_is_rejected(aws: Any) -> None:
    assert handler.handle(*_event()) == "rejected"
    assert _row()["status"] == "REJECTED"


def test_invalid_sidecar_is_rejected_without_echoing_values(aws: Any) -> None:
    aws.put_object(
        Bucket=BUCKET,
        Key=KEY + handler.SIDECAR_SUFFIX,
        Body=_sidecar(allowed_groups=["secret-team"]),
    )

    assert handler.handle(*_event()) == "rejected"
    row = _row()
    assert row["status"] == "REJECTED"
    assert "secret-team" not in row["error"]


def test_delete_marks_the_row_deleted(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())
    handler.handle(*_event())

    assert handler.handle(*_event(deleted=True)) == "deleted"
    assert _row()["status"] == "DELETED"


def test_delete_of_unknown_document_is_reported(aws: Any) -> None:
    assert handler.handle(*_event(key="raw/unknown.pdf", deleted=True)) == "delete-unknown"


def test_sidecar_events_are_skipped(aws: Any) -> None:
    assert handler.handle(*_event(key=KEY + handler.SIDECAR_SUFFIX)) == "skipped-sidecar"


def test_failed_record_is_reported_back_to_sqs_without_failing_the_batch(aws: Any) -> None:
    aws.put_object(Bucket=BUCKET, Key=KEY + handler.SIDECAR_SUFFIX, Body=_sidecar())
    good_kind, good_detail = _event()
    event = {
        "Records": [
            {"messageId": "bad", "body": "not json"},
            {
                "messageId": "good",
                "body": json.dumps({"detail-type": good_kind, "detail": good_detail}),
            },
        ]
    }

    result = handler.lambda_handler(event, _context())  # type: ignore[arg-type]

    assert result == {"batchItemFailures": [{"itemIdentifier": "bad"}]}
    assert _row()["status"] == "CHUNKED"
