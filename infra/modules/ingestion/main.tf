terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Queues: an ingest queue fed by EventBridge, and a DLQ that keeps failures

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-ingest-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "ingest" {
  name                       = "${var.name_prefix}-ingest"
  visibility_timeout_seconds = var.function_timeout * 6
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

data "aws_iam_policy_document" "queue_from_events" {
  statement {
    sid       = "AllowEventBridge"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.ingest.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.documents.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "ingest" {
  queue_url = aws_sqs_queue.ingest.id
  policy    = data.aws_iam_policy_document.queue_from_events.json
}

# ---------------------------------------------------------------------------
# EventBridge rule: object events under raw/ only

resource "aws_cloudwatch_event_rule" "documents" {
  name        = "${var.name_prefix}-document-events"
  description = "S3 object created or deleted under raw/ in the documents bucket"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created", "Object Deleted"]
    detail = {
      bucket = { name = [var.bucket_name] }
      object = { key = [{ prefix = "raw/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "queue" {
  rule = aws_cloudwatch_event_rule.documents.name
  arn  = aws_sqs_queue.ingest.arn
}

# ---------------------------------------------------------------------------
# Document registry: one row per document, keyed by doc_id

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "registry_key" {
  #checkov:skip=CKV_AWS_109:The key policy must let the account root manage the key; it is the only principal.
  #checkov:skip=CKV_AWS_111:A KMS key policy must grant kms:* to the account root; the key only applies to this account.
  #checkov:skip=CKV_AWS_356:A KMS key policy statement must use "*" as its resource; it refers to this key only.
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "registry" {
  description             = "Encrypts the ${var.name_prefix} document registry"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.registry_key.json
}

resource "aws_dynamodb_table" "documents" {
  name         = "${var.name_prefix}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "doc_id"

  attribute {
    name = "doc_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.registry.arn
  }
}

# ---------------------------------------------------------------------------
# Ingest function: reads sidecars, writes registry rows, reports bad messages

data "aws_iam_policy_document" "ingest" {
  statement {
    sid       = "ReadQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [aws_sqs_queue.ingest.arn]
  }

  statement {
    sid       = "ReadRawDocuments"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${var.bucket_arn}/raw/*"]
  }

  # Without ListBucket, S3 answers a missing key with AccessDenied instead of NoSuchKey.
  statement {
    sid       = "ListForMissingSidecars"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  statement {
    sid       = "WriteProcessed"
    actions   = ["s3:PutObject"]
    resources = ["${var.bucket_arn}/processed/*"]
  }

  statement {
    sid       = "UpdateRegistry"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.documents.arn]
  }

  # DynamoDB calls KMS on the function's behalf when reading and writing the encrypted table.
  statement {
    sid       = "UseRegistryKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
    resources = [aws_kms_key.registry.arn]
  }
}

module "ingest_fn" {
  source = "../lambda_container"

  name                     = "${var.name_prefix}-ingest"
  description              = "Registers uploaded documents in the registry"
  image_uri                = var.image_uri
  timeout                  = var.function_timeout
  memory_size              = 3008
  ephemeral_storage_mb     = 2048
  policy_json              = data.aws_iam_policy_document.ingest.json
  attach_policy            = true
  iam_path                 = var.iam_path
  permissions_boundary_arn = var.permissions_boundary_arn
  log_retention_days       = var.log_retention_days

  environment = {
    DOCUMENTS_TABLE = aws_dynamodb_table.documents.name
  }
}

resource "aws_lambda_event_source_mapping" "ingest" {
  event_source_arn                   = aws_sqs_queue.ingest.arn
  function_name                      = module.ingest_fn.function_name
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 2
  }
}

# ---------------------------------------------------------------------------
# Alerts: a topic for operators, and an alarm when anything reaches the DLQ

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:Alerts carry only alarm names and counts, no document content; SNS SSE adds cost without a requirement.
  name = "${var.name_prefix}-ops-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-ingest-dlq-not-empty"
  alarm_description   = "A document failed ingestion three times and is in the dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
