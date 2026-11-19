"""Check that this AWS identity can call every Bedrock model the project needs.

Run it from your machine with your Identity Center profile before the first
deploy, and again whenever you add a model:

    uv run python -m scripts.check_bedrock_access --profile rag-dev --region eu-west-2

It sends one tiny request to each model (fractions of a penny) and prints a table.
The exit code is non-zero if any model fails, so it also works in CI.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from services.hello import handler

DEFAULT_MODELS = [handler.DEFAULT_CHAT_MODEL_ID, handler.DEFAULT_EMBED_MODEL_ID]

HINTS = {
    "AccessDeniedException": "check model access in the Bedrock console, or your IAM permissions",
    "ValidationException": "model ID may be wrong or not offered in this Region",
    "ResourceNotFoundException": "model not found in this Region; try a cross-Region profile",
    "ThrottlingException": "throttled; wait a minute and retry",
}


@dataclass
class Result:
    model_id: str
    ok: bool
    detail: str


def check_model(model_id: str) -> Result:
    """Make one minimal call to the model and summarise the outcome."""
    try:
        if "embed" in model_id:
            out = handler.embed("hello world", model_id)
            return Result(model_id, True, f"{out['dimensions']}-dimension vector")
        out = handler.converse("Reply with the single word: pong", model_id)
        return Result(model_id, True, f"reply={out['reply']!r}, {out['model_latency_ms']} ms")
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        return Result(model_id, False, f"{code}: {HINTS.get(code, 'see the error message')}")
    except BotoCoreError as exc:
        return Result(model_id, False, f"{type(exc).__name__}: {exc}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("--profile", help="AWS CLI profile, e.g. rag-dev")
    parser.add_argument("--region", default="eu-west-2")
    parser.add_argument("--model", action="append", dest="models", help="repeatable model ID")
    args = parser.parse_args(argv)

    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    identity = session.client("sts").get_caller_identity()
    print(f"Account {identity['Account']} as {identity['Arn']} in {args.region}\n")

    # Point the shared handler at this session so local and Lambda code use the same calls.
    handler.bedrock_client.cache_clear()
    client = session.client("bedrock-runtime")
    handler.bedrock_client = lambda: client  # type: ignore[assignment]

    results = [check_model(model_id) for model_id in (args.models or DEFAULT_MODELS)]
    width = max(len(r.model_id) for r in results)
    for r in results:
        print(f"{'PASS' if r.ok else 'FAIL'}  {r.model_id:<{width}}  {r.detail}")
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
