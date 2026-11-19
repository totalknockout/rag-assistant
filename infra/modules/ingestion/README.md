# modules/ingestion

Milestones 1-3: EventBridge rule, SQS queue and DLQ, ingest Lambda as a container image from ECR (extraction, OCR, chunking, FastEmbed embeddings), DynamoDB document registry.

Every IAM role created here must use `iam_path = "/rag-assistant/workload/"` and the workload permissions boundary (see ADR 0004).
