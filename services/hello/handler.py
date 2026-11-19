"""Phase 0 smoke-test Lambda.

Proves the full path works before any real feature is built: the deployment
pipeline, the execution role and its permissions boundary, the Region, and
access to the Bedrock models the project will use.

Event shapes (all fields optional):

    {"action": "converse", "prompt": "Reply with the single word: pong"}
    {"action": "embed", "text": "hello world"}
    {"action": "all"}

The function returns ``{"ok": true, ...}`` on success and ``{"ok": false, ...}``
on a model or permission error, so the deploy workflow can assert on ``ok``.
"""

from __future__ import annotations

import json
import logging
import os
import time
from functools import cache
from typing import TYPE_CHECKING, Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

if TYPE_CHECKING:
    from mypy_boto3_bedrock_runtime import BedrockRuntimeClient

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

DEFAULT_CHAT_MODEL_ID = "openai.gpt-oss-20b-1:0"
DEFAULT_EMBED_MODEL_ID = "amazon.titan-embed-text-v2:0"
DEFAULT_PROMPT = "Reply with the single word: pong"


@cache
def bedrock_client() -> BedrockRuntimeClient:
    """Create the Bedrock runtime client once per execution environment."""
    return boto3.client(
        "bedrock-runtime",
        config=Config(
            retries={"mode": "adaptive", "max_attempts": 5},
            connect_timeout=5,
            read_timeout=60,
        ),
    )


def converse(prompt: str, model_id: str, max_tokens: int = 512) -> dict[str, Any]:
    """Send one user turn through the Converse API and return a compact summary.

    Reasoning models such as gpt-oss return a ``reasoningContent`` block before
    the answer, so only plain ``text`` blocks are joined into the reply.
    ``max_tokens`` leaves room for that reasoning.
    """
    started = time.perf_counter()
    response = bedrock_client().converse(
        modelId=model_id,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": max_tokens, "temperature": 0.0},
    )
    blocks = response["output"]["message"]["content"]
    text = "".join(block["text"] for block in blocks if "text" in block).strip()
    usage = response["usage"]
    return {
        "model_id": model_id,
        "reply": text,
        "stop_reason": response["stopReason"],
        "input_tokens": usage["inputTokens"],
        "output_tokens": usage["outputTokens"],
        "model_latency_ms": response["metrics"]["latencyMs"],
        "round_trip_ms": round((time.perf_counter() - started) * 1000),
    }


def embed(text: str, model_id: str, dimensions: int = 1024) -> dict[str, Any]:
    """Embed one string with Titan Text Embeddings V2 and report the vector size."""
    response = bedrock_client().invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({"inputText": text, "dimensions": dimensions, "normalize": True}),
    )
    payload = json.loads(response["body"].read())
    vector: list[float] = payload["embedding"]
    return {
        "model_id": model_id,
        "dimensions": len(vector),
        "input_tokens": payload.get("inputTextTokenCount"),
        "first_values": [round(v, 4) for v in vector[:3]],
    }


def _run(action: str, event: dict[str, Any]) -> dict[str, Any]:
    chat_model = os.environ.get("CHAT_MODEL_ID", DEFAULT_CHAT_MODEL_ID)
    embed_model = os.environ.get("EMBED_MODEL_ID", DEFAULT_EMBED_MODEL_ID)
    if action == "converse":
        return {"converse": converse(str(event.get("prompt", DEFAULT_PROMPT)), chat_model)}
    if action == "embed":
        return {"embed": embed(str(event.get("text", "hello world")), embed_model)}
    if action == "all":
        return {
            "converse": converse(DEFAULT_PROMPT, chat_model),
            "embed": embed("hello world", embed_model),
        }
    raise ValueError(f"Unknown action {action!r}; use converse, embed or all")


def lambda_handler(event: dict[str, Any] | None, context: object) -> dict[str, Any]:
    """Lambda entry point."""
    event = event or {}
    action = str(event.get("action", "converse"))
    try:
        result = _run(action, event)
    except ValueError as exc:
        LOG.warning("bad request", extra={"action": action, "error": str(exc)})
        return {"ok": False, "action": action, "error_code": "BadRequest", "message": str(exc)}
    except ClientError as exc:
        error = exc.response.get("Error", {})
        code = error.get("Code", "ClientError")
        LOG.error("bedrock call failed", extra={"action": action, "error_code": code})
        return {"ok": False, "action": action, "error_code": code, "message": error.get("Message")}
    except BotoCoreError as exc:
        LOG.error("sdk error", extra={"action": action, "error": str(exc)})
        code = type(exc).__name__
        return {"ok": False, "action": action, "error_code": code, "message": str(exc)}

    LOG.info("smoke test passed", extra={"action": action, "result": result})
    return {"ok": True, "action": action, **result}
