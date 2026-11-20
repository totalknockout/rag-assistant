output "hello_function_name" {
  description = "Smoke-test Lambda; invoke it with scripts/invoke_hello.sh."
  value       = module.hello.function_name
}

output "hello_log_group" {
  description = "Where the smoke test logs."
  value       = module.hello.log_group_name
}

output "ecr_repository_url" {
  description = "Registry for the ingest and query container images."
  value       = aws_ecr_repository.functions.repository_url
}

output "resource_group" {
  description = "Resource group listing everything in this environment."
  value       = aws_resourcegroups_group.env.name
}

output "docs_bucket" {
  description = "Upload documents under raw/ in this bucket."
  value       = module.storage.bucket_name
}

output "ingest_queue_url" {
  description = "Ingest queue; check its depth when debugging uploads."
  value       = module.ingestion.ingest_queue_url
}

output "dlq_url" {
  description = "Dead-letter queue for documents that failed three times."
  value       = module.ingestion.dlq_url
}

output "documents_table" {
  description = "Document registry table."
  value       = module.ingestion.documents_table_name
}

output "ingest_function_name" {
  description = "Ingest function; its logs are in /aws/lambda/<name>."
  value       = module.ingestion.ingest_function_name
}
