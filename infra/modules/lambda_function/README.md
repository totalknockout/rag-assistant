# modules/lambda_function

Zip-packaged Lambda function with:

- its own CloudWatch log group, JSON log format and retention;
- an execution role under the workload IAM path, carrying the workload permissions boundary;
- a least-privilege logs policy scoped to its own log group;
- optional X-Ray tracing and an optional extra inline policy (`policy_json`).

```hcl
module "hello" {
  source = "../../modules/lambda_function"

  name                     = "rag-assistant-dev-hello"
  source_dir               = "${path.root}/../../../services/hello"
  handler                  = "handler.lambda_handler"
  iam_path                 = "/rag-assistant/workload/"
  permissions_boundary_arn = local.boundary_arn
  policy_json              = data.aws_iam_policy_document.hello.json
}
```

Container-image functions (from Milestone 1) get a sibling module that accepts
an ECR image URI instead of `source_dir`.
