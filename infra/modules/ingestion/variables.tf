variable "name_prefix" {
  description = "Resource name prefix, for example rag-assistant-dev."
  type        = string
}

variable "bucket_name" {
  description = "Documents bucket name, used in the EventBridge rule."
  type        = string
}

variable "bucket_arn" {
  description = "Documents bucket ARN, used in the function's IAM policy."
  type        = string
}

variable "image_uri" {
  description = "ECR image URI for the ingest function."
  type        = string
}

variable "function_timeout" {
  description = "Ingest function timeout in seconds. The queue's visibility timeout is six times this."
  type        = number
  default     = 600
}

variable "iam_path" {
  description = "IAM path for the function's execution role."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN for the function's execution role."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "alert_email" {
  description = "Email for ops alerts. Empty string creates no subscription. The recipient must confirm it."
  type        = string
  default     = ""
}
