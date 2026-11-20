variable "name" {
  description = "Function name and execution role name."
  type        = string
}

variable "description" {
  description = "Human-readable function description."
  type        = string
}

variable "image_uri" {
  description = "ECR image URI including the tag."
  type        = string
}

variable "architectures" {
  description = "Instruction set; x86_64 matches the images built on the x86_64 Windows host without emulation."
  type        = list(string)
  default     = ["x86_64"]
}

variable "memory_size" {
  description = "Memory in MB."
  type        = number
  default     = 512
}

variable "ephemeral_storage_mb" {
  description = "Scratch space in MB (512 to 10240)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions, or -1 for unreserved."
  type        = number
  default     = -1
}

variable "environment" {
  description = "Environment variables. Names and model IDs only, never secrets."
  type        = map(string)
  default     = {}
}

variable "policy_json" {
  description = "Function-specific IAM policy document. Used only when attach_policy is true."
  type        = string
  default     = null
}

variable "attach_policy" {
  description = "Whether to attach policy_json. A plan-time boolean, because policy_json can depend on values unknown until apply."
  type        = bool
  default     = false
}

variable "iam_path" {
  description = "IAM path for the execution role, for example /rag-assistant/workload/."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN every execution role must carry."
  type        = string
}

variable "log_level" {
  description = "Application log level."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "tracing_mode" {
  description = "X-Ray tracing mode: Active or PassThrough."
  type        = string
  default     = "Active"
}
