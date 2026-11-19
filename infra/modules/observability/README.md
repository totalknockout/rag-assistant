# modules/observability

From Milestone 5: CloudWatch dashboard, alarms (DLQ depth, errors, p95 latency, cost), log retention, X-Ray groups.

Every IAM role created here must use `iam_path = "/rag-assistant/workload/"` and the workload permissions boundary (see ADR 0004).
