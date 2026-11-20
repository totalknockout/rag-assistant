variable "bucket_name" {
  description = "Globally unique bucket name, starting with rag-assistant- for the workload boundary."
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. True in dev only."
  type        = bool
  default     = false
}
