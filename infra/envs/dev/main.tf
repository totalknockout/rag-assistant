# Dev environment. Phase 0 deploys only the foundations every later milestone
# builds on: the smoke-test Lambda, a container registry for the heavier
# functions to come, and a resource group that shows everything tagged for dev.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix   = "${var.project}-${var.environment}"
  account_id    = data.aws_caller_identity.current.account_id
  partition     = data.aws_partition.current.partition
  workload_path = "/${var.project}/workload/"
  boundary_arn  = "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}/guardrails/${var.project}-workload-boundary"

  bedrock_model_arns = [
    for id in [var.chat_model_id, var.embed_model_id] :
    "arn:${local.partition}:bedrock:${var.region}::foundation-model/${id}"
  ]
}

# ---------------------------------------------------------------------------
# Smoke-test Lambda: proves IAM, the boundary, the Region and model access

data "aws_iam_policy_document" "hello" {
  statement {
    sid       = "InvokeApprovedModels"
    actions   = ["bedrock:InvokeModel"]
    resources = local.bedrock_model_arns
  }
}

module "hello" {
  source = "../../modules/lambda_function"

  name        = "${local.name_prefix}-hello"
  description = "Phase 0 smoke test: Bedrock converse and embed"
  source_dir  = "${path.root}/../../../services/hello"
  handler     = "handler.lambda_handler"
  timeout     = 60

  environment = {
    CHAT_MODEL_ID  = var.chat_model_id
    EMBED_MODEL_ID = var.embed_model_id
  }

  log_retention_days       = var.log_retention_days
  iam_path                 = local.workload_path
  permissions_boundary_arn = local.boundary_arn
  policy_json              = data.aws_iam_policy_document.hello.json
}

# ---------------------------------------------------------------------------
# Container registry for the ingest and query images (FastEmbed, LanceDB, OCR)

resource "aws_ecr_repository" "functions" {
  #checkov:skip=CKV_AWS_136:AES256 encryption at rest is sufficient; a KMS key adds cost without a requirement for it.
  name                 = "${local.name_prefix}-functions"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "functions" {
  repository = aws_ecr_repository.functions.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# One console view of everything in this environment

resource "aws_resourcegroups_group" "env" {
  name        = local.name_prefix
  description = "Everything tagged Project=${var.project}, Env=${var.environment}"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        { Key = "Project", Values = [var.project] },
        { Key = "Env", Values = [var.environment] },
      ]
    })
  }
}
