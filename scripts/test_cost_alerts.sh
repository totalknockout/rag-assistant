#!/usr/bin/env bash
# Publish a test message to the cost-alert SNS topic. If the email arrives, the
# delivery path that Budgets and Cost Anomaly Detection use is working.
#
# Budgets cannot be forced to fire on demand. For an end-to-end test, see
# "Test a real budget alert" in docs/phase-0-foundations.md.
set -euo pipefail

boot_dir="$(dirname "$0")/../infra/bootstrap"
topic_arn="$(terraform -chdir="$boot_dir" output -raw cost_alerts_topic_arn)"

aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "rag-assistant: test cost alert" \
  --message "Test message from scripts/test_cost_alerts.sh at $(date -u +%FT%TZ). If you can read this, budget and anomaly alerts will reach you." \
  --query MessageId --output text

echo "Published. Check your inbox (and spam folder) within a minute."
echo "No email? Confirm the subscription: aws sns list-subscriptions-by-topic --topic-arn $topic_arn"
