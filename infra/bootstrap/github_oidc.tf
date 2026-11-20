# GitHub Actions authenticates to AWS with short-lived OIDC tokens; there are no
# stored access keys. Two roles separate reading from changing:
#
#   plan role  - pull requests and main; read-only; used for `terraform plan`
#   apply role - only jobs in the protected GitHub environment; used for apply/destroy
#
# The apply role can create IAM roles only under the workload path and only with
# the workload permissions boundary attached, so a compromised pipeline cannot
# mint an administrator role.

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Repos with immutable OIDC subjects send repo:OWNER@ID/REPO@ID:... instead of repo:OWNER/REPO:...
  github_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
  oidc_host             = "token.actions.githubusercontent.com"
  oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )

  cicd_path     = "/${var.project}/cicd/"
  workload_path = "/${var.project}/workload/"
  boundary_path = "/${var.project}/guardrails/"
  boundary_name = "${var.project}-workload-boundary"
  boundary_arn  = "arn:${local.partition}:iam::${local.account_id}:policy${local.boundary_path}${local.boundary_name}"

  workload_roles    = "arn:${local.partition}:iam::${local.account_id}:role${local.workload_path}*"
  workload_policies = "arn:${local.partition}:iam::${local.account_id}:policy${local.workload_path}*"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate itself; these well-known thumbprints are
  # kept for compatibility with tools that still expect the field.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_host}"
}

# ---------------------------------------------------------------------------
# Plan role: read-only, for pull requests and the main branch

data "aws_iam_policy_document" "plan_trust" {
  statement {
    sid     = "GitHubActionsPlan"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "${local.github_subject_prefix}:pull_request",
        "${local.github_subject_prefix}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  path                 = local.cicd_path
  description          = "GitHub Actions: terraform plan (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# Apply role: only jobs running in the protected GitHub environment

data "aws_iam_policy_document" "apply_trust" {
  statement {
    sid     = "GitHubActionsApply"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.github_subject_prefix}:environment:${var.deploy_environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-gha-apply"
  path                 = local.cicd_path
  description          = "GitHub Actions: terraform apply and destroy (protected environment only)"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_iam" {
  #checkov:skip=CKV_AWS_356:iam:Get*/List* are read-only and IAM has no narrower resource for account-wide reads.
  #checkov:skip=CKV_AWS_111:Write actions are limited to the workload path and gated by the permissions boundary condition.
  statement {
    sid       = "CreateBoundedWorkloadRoles"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = [local.workload_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid = "ManageBoundedWorkloadRolePolicies"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [local.workload_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid = "ManageWorkloadRoles"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.workload_roles]
  }

  statement {
    sid = "ManageWorkloadPolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [local.workload_policies]
  }

  statement {
    sid       = "PassWorkloadRolesToServices"
    actions   = ["iam:PassRole"]
    resources = [local.workload_roles]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "lambda.amazonaws.com",
        "apigateway.amazonaws.com",
        "states.amazonaws.com",
        "events.amazonaws.com",
        "scheduler.amazonaws.com",
        "pipes.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectTheBoundary"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.boundary_arn]
  }

  statement {
    sid       = "NeverRemoveBoundaries"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "${var.project}-scoped-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}

# ---------------------------------------------------------------------------
# Workload permissions boundary: the most any Lambda or other workload role in
# this project can ever do, whatever its own policy says.

data "aws_iam_policy_document" "workload_boundary" {
  #checkov:skip=CKV_AWS_111:A boundary sets the ceiling; each role's own policy scopes resources further.
  #checkov:skip=CKV_AWS_356:X-Ray and CloudWatch metrics do not support resource-level permissions.
  #checkov:skip=CKV_AWS_109:KMS keys have no name-based ARNs; key policies and role policies narrow access.
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project}-*",
      "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project}-*:*",
    ]
  }

  statement {
    sid = "TracingAndMetrics"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }

  statement {
    sid = "BedrockInference"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:ApplyGuardrail",
    ]
    resources = [
      "arn:${local.partition}:bedrock:*::foundation-model/*",
      "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*",
      "arn:${local.partition}:bedrock:*:${local.account_id}:guardrail/*",
    ]
  }

  statement {
    sid = "ProjectObjects"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
    ]
    resources = ["arn:${local.partition}:s3:::${var.project}-*/*"]
  }

  statement {
    sid       = "ProjectBuckets"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:${local.partition}:s3:::${var.project}-*"]
  }

  statement {
    sid = "ProjectQueues"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage",
    ]
    resources = ["arn:${local.partition}:sqs:${var.region}:${local.account_id}:${var.project}-*"]
  }

  statement {
    sid = "ProjectTables"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:${local.partition}:dynamodb:${var.region}:${local.account_id}:table/${var.project}-*",
      "arn:${local.partition}:dynamodb:${var.region}:${local.account_id}:table/${var.project}-*/index/*",
    ]
  }

  statement {
    sid       = "Encryption"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["arn:${local.partition}:kms:${var.region}:${local.account_id}:key/*"]
  }

  statement {
    sid       = "InvokeProjectFunctions"
    actions   = ["lambda:InvokeFunction"]
    resources = ["arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:${var.project}-*"]
  }

  statement {
    sid       = "NoIdentityOrAccountChanges"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "account:*"]
    resources = ["*"]
  }

  statement {
    sid       = "NoAccessToTerraformState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = local.boundary_name
  path        = local.boundary_path
  description = "Permissions boundary for every workload role in ${var.project}"
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
