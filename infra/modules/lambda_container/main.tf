# Container-image Lambda function with its own log group and a least-privilege
# execution role that always carries the workload boundary.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  log_group_name = "/aws/lambda/${var.name}"
  log_group_arn  = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Logs are encrypted by CloudWatch by default; a customer key adds cost for no gain at this stage.
  #checkov:skip=CKV_AWS_338:Short retention is deliberate for cost; raise log_retention_days for production.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  path                 = var.iam_path
  description          = "Execution role for ${var.name}"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_iam_role_policy_attachment" "xray" {
  count = var.tracing_mode == "Active" ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "extra" {
  count = var.attach_policy ? 1 : 0

  name   = "function"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_117:Runs outside a VPC by design (ADR 0002); it calls only AWS APIs over TLS with IAM auth.
  #checkov:skip=CKV_AWS_173:Environment variables hold resource names and model IDs only, never secrets.
  #checkov:skip=CKV_AWS_115:Concurrency is set per function through reserved_concurrency where it matters.
  #checkov:skip=CKV_AWS_116:The function is fed by an SQS queue whose redrive policy dead-letters failed messages; a function DLQ only covers async invocations.
  #checkov:skip=CKV_AWS_272:Code signing needs a signing profile and pipeline; out of scope for the dev MVP.
  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout

  ephemeral_storage {
    size = var.ephemeral_storage_mb
  }

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = var.environment
  }

  tracing_config {
    mode = var.tracing_mode
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.this.name
    application_log_level = var.log_level
    system_log_level      = "WARN"
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.logs,
  ]
}
