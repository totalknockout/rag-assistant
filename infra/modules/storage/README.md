# modules/storage

Milestone 1: documents bucket (raw/ and processed/), versioning, SSE, lifecycle rules, quarantine bucket.

Every IAM role created here must use `iam_path = "/rag-assistant/workload/"` and the workload permissions boundary (see ADR 0004).
