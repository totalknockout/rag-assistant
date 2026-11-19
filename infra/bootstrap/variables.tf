variable "project" {
  description = "Short project name used as a prefix for every resource."
  type        = string
  default     = "rag-assistant"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "Use 3-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Primary AWS Region."
  type        = string
  default     = "eu-west-2"
}

variable "owner" {
  description = "Value for the Owner tag, for example your name or handle."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name, without the owner."
  type        = string
}

variable "deploy_environment" {
  description = "GitHub environment whose jobs may assume the apply role."
  type        = string
  default     = "dev"
}

variable "create_github_oidc_provider" {
  description = "Set to false if this account already has the GitHub Actions OIDC provider."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address that receives budget and cost anomaly alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the whole account, in US dollars."
  type        = number
  default     = 20
}

variable "budget_alert_thresholds" {
  description = "Percentages of the budget at which an alert is sent, based on actual spend."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "anomaly_threshold_usd" {
  description = "Alert when a cost anomaly's total impact reaches this many US dollars."
  type        = number
  default     = 5
}

variable "existing_anomaly_monitor_arn" {
  description = "ARN of an existing AWS services anomaly monitor to reuse. Leave null to create one."
  type        = string
  default     = null
}

variable "activate_cost_allocation_tags" {
  description = "Activate Project/Env/Owner as cost allocation tags. Enable about a day after the first tagged resources exist."
  type        = bool
  default     = false
}
