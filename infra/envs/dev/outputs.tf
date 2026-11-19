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
