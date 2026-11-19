# modules/search

Milestone 4: S3 bucket and prefix for LanceDB tables, plus IAM for the ingest (write) and query (read) roles.

Every IAM role created here must use `iam_path = "/rag-assistant/workload/"` and the workload permissions boundary (see ADR 0004).
