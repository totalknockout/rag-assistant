variable "project" {
  description = "Project prefix; must match the bootstrap stack."
  type        = string
  default     = "rag-assistant"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS Region."
  type        = string
  default     = "us-west-2"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
}

variable "repository" {
  description = "owner/repo of the GitHub repository, for the Repo tag."
  type        = string
}

variable "chat_model_id" {
  description = "Bedrock model for the converse smoke test (an open-weight model, in-Region in Oregon)."
  type        = string
  default     = "openai.gpt-oss-20b-1:0"
}

variable "embed_model_id" {
  description = "Bedrock embedding model for the embed smoke test."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for dev."
  type        = number
  default     = 14
}
