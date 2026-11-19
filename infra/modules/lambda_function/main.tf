# Reusable zip-packaged Lambda function with its own log group and a
# least-privilege execution role that always carries the workload boundary.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
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

data "archive_file" "package" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.root}/.build/${var.name}.zip"
  excludes    = ["**/__pycache__/**", "**/*.pyc", "tests/**", "README.md"]
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
  count = var.policy_json == null ? 0 : 1

  name   = "function"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_116:Synchronous smoke-test function; asynchronous functions add a DLQ in their own modules.
  #checkov:skip=CKV_AWS_117:Runs outside a VPC by design (ADR 0002); it calls only AWS APIs over TLS with IAM auth.
  #checkov:skip=CKV_AWS_173:Environment variables hold model IDs only, never secrets.
  #checkov:skip=CKV_AWS_272:Code signing is out of scope for Phase 0; artefacts are built and deployed only by the pipeline.
  #checkov:skip=CKV_AWS_115:Concurrency is set per function through reserved_concurrency where it matters.
  function_name    = var.name
  description      = var.description
  role             = aws_iam_role.this.arn
  handler          = var.handler
  runtime          = var.runtime
  architectures    = var.architectures
  memory_size      = var.memory_size
  timeout          = var.timeout
  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

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
