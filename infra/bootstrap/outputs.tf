output "state_bucket" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Role GitHub Actions assumes for terraform plan."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role GitHub Actions assumes for terraform apply and destroy."
  value       = aws_iam_role.apply.arn
}

output "workload_boundary_arn" {
  description = "Permissions boundary every workload role must carry."
  value       = aws_iam_policy.workload_boundary.arn
}

output "workload_iam_path" {
  description = "IAM path for workload roles and policies."
  value       = local.workload_path
}

output "cost_alerts_topic_arn" {
  description = "SNS topic for budget and anomaly alerts."
  value       = aws_sns_topic.cost_alerts.arn
}

output "github_variables" {
  description = "Repository variables to set in GitHub (scripts/set_github_vars.sh does this)."
  value = {
    AWS_REGION         = var.region
    TF_STATE_BUCKET    = aws_s3_bucket.state.bucket
    AWS_PLAN_ROLE_ARN  = aws_iam_role.plan.arn
    AWS_APPLY_ROLE_ARN = aws_iam_role.apply.arn
  }
}
