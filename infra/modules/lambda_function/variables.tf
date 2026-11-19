variable "name" {
  description = "Function name. Must start with the project prefix so the boundary allows its logs."
  type        = string
}

variable "description" {
  description = "What the function does."
  type        = string
  default     = ""
}

variable "source_dir" {
  description = "Directory to zip as the deployment package."
  type        = string
}

variable "handler" {
  description = "Handler in module.function form, for example handler.lambda_handler."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime identifier."
  type        = string
  default     = "python3.13"
}

variable "architectures" {
  description = "Instruction set. arm64 (Graviton) is cheaper per GB-second."
  type        = list(string)
  default     = ["arm64"]
}

variable "memory_size" {
  description = "Memory in MB; CPU scales with it."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Reserved concurrency; -1 means unreserved."
  type        = number
  default     = -1
}

variable "environment" {
  description = "Environment variables. Never put secrets here."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "log_level" {
  description = "Application log level for JSON logging."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.log_level)
    error_message = "Use TRACE, DEBUG, INFO, WARN, ERROR or FATAL."
  }
}

variable "tracing_mode" {
  description = "X-Ray tracing mode: Active or PassThrough."
  type        = string
  default     = "Active"
}

variable "iam_path" {
  description = "IAM path for the execution role; must match the path the apply role may manage."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Workload permissions boundary from the bootstrap stack."
  type        = string
}

variable "policy_json" {
  description = "Optional extra inline policy for the function's own permissions."
  type        = string
  default     = null
}
