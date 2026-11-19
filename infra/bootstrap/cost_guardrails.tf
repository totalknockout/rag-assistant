# Budget and anomaly alerts, delivered through one SNS topic to your email.
# Phase 0 creates these before anything that costs money.

resource "aws_sns_topic" "cost_alerts" {
  #checkov:skip=CKV_AWS_26:Budgets cannot publish to topics encrypted with the AWS-managed SNS key, and alerts carry no sensitive data.
  name = "${var.project}-cost-alerts"
}

data "aws_iam_policy_document" "cost_alerts" {
  statement {
    sid       = "AllowBudgets"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cost_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowCostAnomalyDetection"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cost_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["costalerts.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "cost_alerts" {
  arn    = aws_sns_topic.cost_alerts.arn
  policy = data.aws_iam_policy_document.cost_alerts.json
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
    }
  }

  # Early warning: the month is on track to exceed the budget.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

resource "aws_ce_anomaly_monitor" "services" {
  count = var.existing_anomaly_monitor_arn == null ? 1 : 0

  name              = "${var.project}-aws-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name      = "${var.project}-anomalies"
  frequency = "IMMEDIATE"
  monitor_arn_list = [
    var.existing_anomaly_monitor_arn != null ? var.existing_anomaly_monitor_arn : aws_ce_anomaly_monitor.services[0].arn,
  ]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

# Tags only appear in Billing after tagged resources have existed for a while.
# Set activate_cost_allocation_tags = true about a day after the first deploy.
resource "aws_ce_cost_allocation_tag" "project_tags" {
  for_each = var.activate_cost_allocation_tags ? toset(["Project", "Env", "Owner"]) : toset([])

  tag_key = each.value
  status  = "Active"
}
