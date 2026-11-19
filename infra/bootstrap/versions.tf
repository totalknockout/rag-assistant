terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # First apply uses local state. After the state bucket exists, copy
  # backend.tf.example to backend.tf and run `terraform init -migrate-state`.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = "shared"
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "bootstrap"
      Repo      = "${var.github_owner}/${var.github_repo}"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
