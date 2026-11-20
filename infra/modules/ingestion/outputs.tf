output "documents_table_name" {
  description = "Registry table name."
  value       = aws_dynamodb_table.documents.name
}

output "ingest_queue_url" {
  description = "Ingest queue URL."
  value       = aws_sqs_queue.ingest.url
}

output "dlq_url" {
  description = "Dead-letter queue URL."
  value       = aws_sqs_queue.dlq.url
}

output "alerts_topic_arn" {
  description = "Ops alert topic ARN."
  value       = aws_sns_topic.alerts.arn
}

output "ingest_function_name" {
  description = "Ingest function name."
  value       = module.ingest_fn.function_name
}
