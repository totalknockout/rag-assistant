"""Unit tests for the Phase 0 smoke-test Lambda.

botocore's Stubber validates every request and response against the real
Bedrock API model, so these tests catch wrong parameter names without calling AWS.
"""

from __future__ import annotations

import io
import json
from collections.abc import Iterator
from typing import TYPE_CHECKING

import boto3
import pytest
from botocore.response import StreamingBody
from botocore.stub import Stubber

from services.hello import handler

if TYPE_CHECKING:
    from mypy_boto3_bedrock_runtime import BedrockRuntimeClient


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> BedrockRuntimeClient:
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("CHAT_MODEL_ID", handler.DEFAULT_CHAT_MODEL_ID)
    monkeypatch.setenv("EMBED_MODEL_ID", handler.DEFAULT_EMBED_MODEL_ID)
    real = boto3.client("bedrock-runtime", region_name="us-west-2")
    monkeypatch.setattr(handler, "bedrock_client", lambda: real)
    return real


@pytest.fixture
def stubber(client: BedrockRuntimeClient) -> Iterator[Stubber]:
    with Stubber(client) as stub:
        yield stub
        stub.assert_no_pending_responses()


def _converse_response(reply: str) -> dict[str, object]:
    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [
                    {"reasoningContent": {"reasoningText": {"text": "The user wants pong."}}},
                    {"text": reply},
                ],
            }
        },
        "stopReason": "end_turn",
        "usage": {"inputTokens": 12, "outputTokens": 30, "totalTokens": 42},
        "metrics": {"latencyMs": 250},
    }


def _embed_response(dimensions: int) -> dict[str, object]:
    body = json.dumps({"embedding": [0.01] * dimensions, "inputTextTokenCount": 2}).encode()
    return {
        "body": StreamingBody(io.BytesIO(body), len(body)),
        "contentType": "application/json",
    }


def test_converse_returns_text_and_skips_reasoning(stubber: Stubber) -> None:
    stubber.add_response(
        "converse",
        _converse_response("pong"),
        {
            "modelId": handler.DEFAULT_CHAT_MODEL_ID,
            "messages": [{"role": "user", "content": [{"text": handler.DEFAULT_PROMPT}]}],
            "inferenceConfig": {"maxTokens": 512, "temperature": 0.0},
        },
    )

    result = handler.lambda_handler({"action": "converse"}, None)

    assert result["ok"] is True
    assert result["converse"]["reply"] == "pong"
    assert result["converse"]["output_tokens"] == 30


def test_embed_reports_1024_dimensions(stubber: Stubber) -> None:
    stubber.add_response("invoke_model", _embed_response(1024))

    result = handler.lambda_handler({"action": "embed", "text": "hello"}, None)

    assert result["ok"] is True
    assert result["embed"]["dimensions"] == 1024


def test_all_runs_both_checks(stubber: Stubber) -> None:
    stubber.add_response("converse", _converse_response("pong"))
    stubber.add_response("invoke_model", _embed_response(1024))

    result = handler.lambda_handler({"action": "all"}, None)

    assert result["ok"] is True
    assert set(result) >= {"converse", "embed"}


def test_access_denied_is_reported_not_raised(stubber: Stubber) -> None:
    stubber.add_client_error(
        "converse",
        service_error_code="AccessDeniedException",
        service_message="You don't have access to the model with the specified model ID.",
        http_status_code=403,
    )

    result = handler.lambda_handler({"action": "converse"}, None)

    assert result["ok"] is False
    assert result["error_code"] == "AccessDeniedException"


def test_unknown_action_is_a_bad_request(client: BedrockRuntimeClient) -> None:
    result = handler.lambda_handler({"action": "dance"}, None)

    assert result == {
        "ok": False,
        "action": "dance",
        "error_code": "BadRequest",
        "message": "Unknown action 'dance'; use converse, embed or all",
    }


def test_missing_event_defaults_to_converse(stubber: Stubber) -> None:
    stubber.add_response("converse", _converse_response("pong"))

    result = handler.lambda_handler(None, None)

    assert result["action"] == "converse"
    assert result["ok"] is True
