#!/usr/bin/env bash
# Invoke the deployed smoke-test Lambda and check the result.
# Usage: ./scripts/invoke_hello.sh [converse|embed|all]
set -euo pipefail

action="${1:-all}"
dev_dir="$(dirname "$0")/../infra/envs/dev"
fn="$(terraform -chdir="$dev_dir" output -raw hello_function_name)"
out="$(mktemp)"

aws lambda invoke \
  --function-name "$fn" \
  --cli-binary-format raw-in-base64-out \
  --payload "{\"action\":\"$action\"}" \
  "$out" > /dev/null

jq . "$out"
if jq -e '.ok == true' "$out" > /dev/null; then
  echo "PASS: $fn ($action)"
else
  echo "FAIL: see the error above and docs/phase-0-foundations.md#troubleshooting" >&2
  exit 1
fi
