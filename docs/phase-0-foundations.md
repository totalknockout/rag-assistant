# Phase 0: Foundations, step by step

By the end of this phase you have a dedicated AWS account with cost alarms, a
GitHub repository whose pipeline plans every pull request and deploys every
merge, and a smoke-test Lambda proving that the deployed code can call Bedrock.
Nothing here is specific to RAG yet. It is the ground every later milestone
stands on, and it is what separates a portfolio project from a tutorial follow-along.

**Time:** two to four evenings. **Cost:** pennies; your budget alert will tell you otherwise.

## What you will have at the end

| Area | Result | Where in the repo |
| --- | --- | --- |
| AWS account | A dedicated member account, reached only through IAM Identity Center | Console setup (Step 1) |
| Cost safety | Monthly budget with alerts at 50/80/100% plus a forecast alert, and a cost anomaly monitor, all emailing you | `infra/bootstrap/cost_guardrails.tf` |
| Remote state | Versioned, encrypted, TLS-only S3 bucket with native state locking | `infra/bootstrap/state.tf` |
| Pipeline identity | GitHub OIDC with a read-only **plan** role and an **apply** role usable only from the protected `dev` environment | `infra/bootstrap/github_oidc.tf` |
| Guardrail on the pipeline | A permissions boundary that every workload role must carry | `infra/bootstrap/github_oidc.tf` |
| CI | Ruff, strict mypy, pytest, `terraform fmt`/`validate`, TFLint, Checkov, and a plan summary on every PR | `.github/workflows/ci.yml` |
| CD | Apply to dev on merge, then an automatic smoke test | `.github/workflows/deploy.yml` |
| Smoke test | A Lambda that calls an open-weight chat model and Titan Embeddings V2 on Bedrock | `services/hello/`, `infra/envs/dev/` |
| Front end | A placeholder React site on GitHub Pages | `frontend/`, `.github/workflows/pages.yml` |
| Decisions | ADRs for the first architectural choices | `docs/adr/` |

## Before you start

You need an AWS account you control, a GitHub account (Pro is assumed), and an
email inbox for alerts.

**Use a Linux shell.** The Makefile and scripts are Bash. On Windows, use one of:

- **GitHub Codespaces (easiest).** Open the repo in a codespace; `.devcontainer/devcontainer.json` installs Python 3.13, uv, Terraform, TFLint, the AWS CLI, the GitHub CLI and Node 22. GitHub Pro includes 180 core-hours a month, which is about 90 hours on a 2-core machine.
- **WSL2 with Ubuntu,** then install the same tools: `uv`, Terraform 1.11 or later, TFLint, AWS CLI v2, `gh`, Node 22 and `jq`.

Check your toolchain:

```bash
uv --version && terraform version && tflint --version && aws --version && gh --version && node --version && jq --version
```

---

## Step 1: Set up the AWS account (0.1)

### 1.1 Create a dedicated member account

Keep this project in its own account so its bill, permissions and clean-up are isolated.

1. In your existing (management) account, open **AWS Organizations** and create an organisation if you don't have one.
2. **Add an AWS account** → **Create an AWS account**. Name it `rag-assistant-dev` and use an email alias such as `you+rag-dev@example.com`.
3. In the management account, open **Billing and Cost Management → Cost Management preferences** and allow linked accounts to use Cost Explorer. The member account needs this for its anomaly monitor.

### 1.2 Sign in through IAM Identity Center, never with access keys

1. Open **IAM Identity Center** in the management account and enable it in `us-west-2`.
2. Create a user for yourself and turn on MFA.
3. Under **Multi-account permissions → AWS accounts**, assign your user to `rag-assistant-dev` with the `AdministratorAccess` permission set. You use this only for the one-off bootstrap and for local experiments; the pipeline gets its own, narrower roles.
4. Configure the CLI profile used throughout this guide:

```bash
aws configure sso --profile rag-dev
#   SSO session name:      rag
#   SSO start URL:         https://<your-id>.awsapps.com/start
#   SSO region:            us-west-2
#   Account:               rag-assistant-dev
#   Role:                  AdministratorAccess
#   Default client region: us-west-2
#   Output format:         json
# In a codespace, add --use-device-code to `aws sso login` if the browser hand-off fails.

aws sso login --profile rag-dev
export AWS_PROFILE=rag-dev AWS_REGION=us-west-2
aws sts get-caller-identity   # should show the rag-assistant-dev account
```

> **Check:** there are no IAM users with access keys anywhere in this account. `aws iam list-users` should return an empty list.

### 1.3 Check for an existing cost anomaly monitor

Some accounts already have an AWS-managed services monitor, and an account can hold only one of that type.

```bash
aws ce get-anomaly-monitors --query 'AnomalyMonitors[].{Name:MonitorName,Type:MonitorType,Arn:MonitorArn}' --output table
```

If you see a `DIMENSIONAL` monitor, copy its ARN; you will pass it as `existing_anomaly_monitor_arn` in Step 3.

---

## Step 2: Create the GitHub repository (0.2)

### 2.1 Public or private?

**Make the repository public** unless you have a reason not to. On GitHub Pro:

| | Public repo | Private repo |
| --- | --- | --- |
| Required reviewer before each deploy | Yes | No (Enterprise only) |
| Actions minutes on standard runners | Unlimited | 3,000 a month |
| Pages site | Public | Public (the site, not the code) |
| Employers can read the code | Yes | Only if you invite them |

The workflows work either way. In a private repo, deployments are still limited to `main`; they just don't pause for approval.

Two rules for a public repo, both already built into the templates:

- The plan job never runs for pull requests from forks, and its PR comment lists only resource addresses and actions, never attribute values.
- Nothing secret is ever committed. `terraform.tfvars` and `backend.hcl` are git-ignored, and pre-commit runs gitleaks.

### 2.2 Push the starter repository

```bash
unzip rag-assistant.zip && cd rag-assistant
git init -b main
git add . && git commit -m "Phase 0: repository scaffold"
gh repo create rag-assistant --public --source . --push
```

### 2.3 Protect `main`

In **Settings → Rules → Rulesets**, create a branch ruleset for the default branch that:

- requires a pull request before merging;
- requires these status checks to pass: `Python lint, types, tests` and `Terraform fmt, validate, lint, security scan`;
- blocks force pushes.

The checks only appear in the picker after CI has run once, so add them after your first PR.

In **Settings → Actions → General**, set "Fork pull request workflows from outside collaborators" to require approval for all outside collaborators.

### 2.4 Install the local toolchain

```bash
make setup     # uv sync, pre-commit install, npm ci
make check     # everything CI runs: lint, types, tests, fmt, validate, tflint, checkov
uv run pre-commit autoupdate   # bump hook versions to the latest releases
```

### 2.5 What lives where

```text
rag-assistant/
├── .devcontainer/            # Codespaces / Dev Containers toolchain
├── .github/
│   ├── workflows/            # ci, deploy, destroy, eval, pages
│   └── dependabot.yml        # weekly grouped dependency updates
├── infra/
│   ├── bootstrap/            # state bucket, OIDC roles, boundary, budget (applied once, by hand)
│   ├── envs/dev/             # wires modules together; backend config; dev.tfvars
│   └── modules/
│       ├── lambda_function/  # reusable: zip, log group, bounded role, JSON logs, X-Ray
│       └── storage/ ingestion/ search/ auth/ api/ observability/   # filled in later milestones
├── services/
│   ├── hello/                # Phase 0 smoke-test Lambda
│   ├── ingest/ query/ shared/
├── frontend/                 # React + Vite, deployed to GitHub Pages
├── eval/                     # datasets, runners, reports
├── corpus/                   # sample documents and metadata sidecars
├── scripts/                  # bedrock check, GitHub setup, alert test, smoke test
├── docs/                     # this guide, ADRs, architecture, security
├── tests/unit/
├── Makefile
└── pyproject.toml            # uv-managed; ruff, mypy, pytest config
```

---

## Step 3: Bootstrap the account (0.1 and 0.3)

The bootstrap stack is the only one you apply from your own machine. It creates
the things the pipeline needs before the pipeline can run.

### 3.1 What it creates and why

| Resource | Why it exists |
| --- | --- |
| S3 state bucket (versioned, SSE, public access blocked, TLS-only policy, old versions expire after 90 days) | Remote state that survives your laptop, can be rolled back, and is never public |
| GitHub OIDC provider | Lets GitHub Actions swap a short-lived token for AWS credentials, with no stored keys |
| `rag-assistant-gha-plan` role (`ReadOnlyAccess`) | Trusted only for this repo's pull requests and `main`; can read but never change anything |
| `rag-assistant-gha-apply` role (`PowerUserAccess` plus scoped IAM) | Trusted only for jobs in the `dev` environment. It can create IAM roles only under `/rag-assistant/workload/` and only with the boundary attached |
| `rag-assistant-workload-boundary` policy | The ceiling for every workload role: no IAM, no access to Terraform state, S3/SQS/DynamoDB only on `rag-assistant-*` resources |
| SNS topic, email subscription, budget, anomaly monitor and subscription | Cost alerts before anything costs money |

The boundary is the detail reviewers notice. Without it, an apply role that can
create IAM roles can create an administrator role and escalate. With it, even a
compromised pipeline can only create roles that are boxed in.

### 3.2 Apply it

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
#  set owner, github_owner, github_repo, alert_email
#  and existing_anomaly_monitor_arn if Step 1.3 found one

terraform init
terraform plan -out=tfplan        # read it: about 20 resources, all new
terraform apply tfplan
terraform output
```

Then open the email from AWS Notifications and **confirm the SNS subscription**. Until you do, no alert reaches you.

### 3.3 Move the bootstrap state into the bucket

```bash
cp backend.tf.example backend.tf
sed -i "s/rag-assistant-tfstate-123456789012-us-west-2/$(terraform output -raw state_bucket)/" backend.tf
terraform init -migrate-state      # answer "yes"
rm -f terraform.tfstate terraform.tfstate.backup tfplan
```

`backend.tf` is git-ignored because it contains your account ID; keep a copy somewhere safe.

### 3.4 Lock provider versions for every platform

Commit the lock files so your machine and CI resolve identical provider builds:

```bash
for dir in infra/bootstrap infra/envs/dev; do
  terraform -chdir=$dir init -backend=false
  terraform -chdir=$dir providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64
done
git add infra/*/.terraform.lock.hcl infra/envs/dev/.terraform.lock.hcl
```

### 3.5 Remote state settings, explained

`infra/envs/dev/versions.tf` uses a partial backend configuration:

```hcl
backend "s3" {
  key          = "envs/dev/terraform.tfstate"
  region       = "us-west-2"
  encrypt      = true
  use_lockfile = true    # S3-native locking; the DynamoDB lock table is deprecated
}
```

The bucket name is supplied at `init` time, so no account ID is committed:
CI passes `-backend-config="bucket=..."` from a repository variable, and locally
you copy `backend.hcl.example` to `backend.hcl`.

---

## Step 4: Test the cost alerts

### 4.1 Test the delivery path (minutes)

```bash
make test-alerts
```

This publishes a message to the alert topic. If it reaches your inbox, budget
and anomaly alerts will too.

### 4.2 Test a real budget alert (optional, takes hours)

Budgets cannot be fired on demand. For a true end-to-end test, set
`monthly_budget_usd = 0.01` in `terraform.tfvars` and apply. Once any spend
appears in billing data (usually within a day of the smoke test), the 50%, 80%
and 100% alerts fire. Then set it back to your real figure and apply again.

### 4.3 Cost allocation tags (a day later)

Every resource carries `Project`, `Env`, `Owner`, `ManagedBy` and `Repo` tags
through the provider's `default_tags`. About a day after the first deploy, set
`activate_cost_allocation_tags = true` in the bootstrap `terraform.tfvars` and
apply. From then on, Cost Explorer can group spend by tag, which you will use
for the cost section of the README.

---

## Step 5: Confirm Bedrock model access (0.1)

The project uses two models in `us-west-2`, both available in-Region:

| Purpose | Model ID | Why |
| --- | --- | --- |
| Chat (smoke test, later answers) | `openai.gpt-oss-20b-1:0` | Open-weight, low per-token price, no GPU to run |
| Embeddings (smoke test) | `amazon.titan-embed-text-v2:0` | 1024-dimension vectors, in-Region in Oregon |

```bash
make bedrock-check
# Account 123456789012 as arn:aws:sts::...:assumed-role/AWSReservedSSO_AdministratorAccess_.../you in us-west-2
#
# PASS  openai.gpt-oss-20b-1:0         reply='pong', 850 ms
# PASS  amazon.titan-embed-text-v2:0   1024-dimension vector
```

If a model fails with `AccessDeniedException`, open the Bedrock console in
`us-west-2`, find the model in the catalogue and enable access (some providers
ask for a one-time use-case form), then run the check again. Swap models by
passing `--model <id>`, and record any change in an ADR.

gpt-oss is a reasoning model, so its response contains a reasoning block before
the answer. `services/hello/handler.py` keeps only the text blocks, and allows
512 output tokens so the reasoning doesn't crowd out the reply.

---

## Step 6: Connect GitHub to AWS (0.4)

### 6.1 Repository variables and the `dev` environment

```bash
gh auth login        # if you haven't already
make github-setup    # runs scripts/set_github_vars.sh
```

The script reads the bootstrap outputs and:

1. sets four repository **variables** (not secrets; none of them are sensitive): `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`;
2. creates the `dev` environment, limited to protected branches, with you as required reviewer when the repository is public.

### 6.2 How the trust works

| Workflow event | OIDC subject GitHub presents | Role it can assume |
| --- | --- | --- |
| Pull request | `repo:<owner>/rag-assistant:pull_request` | plan |
| Push to `main` (CI) | `repo:<owner>/rag-assistant:ref:refs/heads/main` | plan |
| Job with `environment: dev` | `repo:<owner>/rag-assistant:environment:dev` | apply |

A pull request can therefore never apply, and a workflow only gets the apply
role after the environment's rules (branch, and reviewer if public) are met.

### 6.3 Turn on GitHub Pages

**Settings → Pages → Build and deployment → Source: GitHub Actions.**

---

## Step 7: First pull request, first deploy (0.4)

### 7.1 Set your values and open a PR

Edit `infra/envs/dev/dev.tfvars`:

```hcl
owner      = "tk"
repository = "<your-github-username>/rag-assistant"
```

```bash
git switch -c phase-0/first-deploy
git add -A && git commit -m "Phase 0: dev settings and provider locks"
git push -u origin phase-0/first-deploy
gh pr create --fill
```

CI runs three jobs:

1. **Python lint, types, tests:** ruff, strict mypy, pytest with coverage.
2. **Terraform fmt, validate, lint, security scan:** `terraform fmt -check`, `validate` for each stack, TFLint with the AWS ruleset, Checkov.
3. **Terraform plan (dev):** assumes the plan role and posts a summary like this on the PR:

```text
Terraform plan: dev
9 to add, 0 to change, 0 to destroy
CREATE  aws_ecr_lifecycle_policy.functions
CREATE  aws_ecr_repository.functions
CREATE  aws_resourcegroups_group.env
CREATE  module.hello.aws_cloudwatch_log_group.this
...
```

Now add the two required status checks to the ruleset from Step 2.3.

### 7.2 Merge and deploy

Merge the PR. **Deploy dev** starts, waits for your approval (public repo), then:

1. assumes the apply role through OIDC;
2. runs `terraform plan` and `terraform apply` for `infra/envs/dev`;
3. invokes the hello Lambda with `{"action": "all"}` and fails the run unless `ok` is true and the embedding has 1024 dimensions.

The run summary shows the model's reply and the vector size. You can repeat the test from your machine:

```bash
cp infra/envs/dev/backend.hcl.example infra/envs/dev/backend.hcl   # set the bucket name
make dev-init
make invoke-hello
```

### 7.3 Check the tags and the boundary

```bash
aws resource-groups list-group-resources --group rag-assistant-dev --query 'ResourceIdentifiers[].ResourceArn'
aws iam get-role --role-name rag-assistant-dev-hello --query 'Role.{Path:Path,Boundary:PermissionsBoundary.PermissionsBoundaryArn}'
```

The role should sit under `/rag-assistant/workload/` with the boundary attached.

### 7.4 Publish the front end

The **Deploy front end to GitHub Pages** workflow runs on changes under
`frontend/` or manually from the Actions tab. Your site appears at
`https://<your-github-username>.github.io/rag-assistant/`. Everything in the
bundle is public, so it only ever holds public settings such as the API URL.

---

## Step 8: A fast local loop (0.5)

There is no search cluster to run locally any more (see ADR 0002), which makes the loop simple:

- **Unit tests and types** run in seconds: `make test typecheck`.
- **Real Bedrock calls from your machine** use the same functions the Lambda uses: `make bedrock-check`, or `uv run python -c "from services.hello.handler import converse; print(converse('hi', 'openai.gpt-oss-20b-1:0'))"` with `AWS_PROFILE` set.
- **Infrastructure** changes go through `make dev-plan` locally before you open a PR.
- **Front end:** `make frontend-dev` serves the site at `http://localhost:5173`.

From Milestone 1, the vector store (LanceDB) runs on a local folder in tests
and on S3 in AWS, through the same code.

---

## Step 9: Record your decisions

Read and adjust the ADRs in `docs/adr/`:

- `0001` record architecture decisions
- `0002` serverless, low-cost deployment (no VPC, GitHub Pages, open-weight model)
- `0003` Terraform state in S3 with native locking
- `0004` GitHub OIDC with split roles and a permissions boundary
- `0005` public repository and deployment approvals

Copy `0000-template.md` for each new decision.

---

## Done when

- [ ] You sign in only through IAM Identity Center; the account has no IAM users with access keys.
- [ ] The budget and anomaly alerts exist, and `make test-alerts` reached your inbox.
- [ ] Terraform state for both stacks lives in the S3 bucket, with native locking.
- [ ] A PR shows green CI checks and a plan summary comment.
- [ ] Merging to `main` applied dev through the pipeline, and the smoke test returned a model reply and a 1024-dimension vector.
- [ ] The hello Lambda's role has the workload boundary attached.
- [ ] The placeholder site is live on GitHub Pages.
- [ ] ADRs 0001-0005 reflect what you actually decided.

## Tearing down

- **Dev only:** run the **Destroy dev** workflow and type `destroy dev`. ECR images are deleted with the repository.
- **Everything:** destroy dev first, then `terraform -chdir=infra/bootstrap destroy`. The state bucket has `prevent_destroy`; remove that block and empty the bucket first, deliberately.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The OIDC subject doesn't match the trust policy: wrong `github_owner`/`github_repo` (they are case-sensitive), a job without `environment: dev`, or a fork PR | Compare `terraform -chdir=infra/bootstrap output` with the repo name; re-apply bootstrap after fixing `terraform.tfvars` |
| Plan job is skipped | `AWS_PLAN_ROLE_ARN` variable not set, or the PR comes from a fork | Run `make github-setup` |
| `AccessDenied ... iam:CreateRole` during apply | A role is being created without the boundary or outside `/rag-assistant/workload/` | Create roles through `modules/lambda_function`, or pass `iam_path` and `permissions_boundary_arn` yourself |
| `Error acquiring the state lock` | A cancelled run left a `.tflock` object | Make sure no run is active, then `terraform force-unlock <ID>` |
| Smoke test: `AccessDeniedException` from Bedrock | Model access not enabled, or the model ID isn't in the function's policy | Run `make bedrock-check` locally; the model must be in `chat_model_id`/`embed_model_id` |
| Smoke test: `ValidationException` | Model ID not offered in this Region | Check the model's Regional availability; change the ID in `dev.tfvars` |
| Anomaly monitor fails with a limit error | The account already has a services monitor | Set `existing_anomaly_monitor_arn` (Step 1.3) and apply |
| Anomaly monitor fails with `AccessDenied` in a member account | Linked accounts can't use Cost Explorer | Enable it in the management account (Step 1.1, item 3) |
| No alert emails | SNS subscription not confirmed | `aws sns list-subscriptions-by-topic --topic-arn <arn>`; confirm or re-subscribe |
| TFLint can't download the AWS ruleset | GitHub API rate limit | CI passes `GITHUB_TOKEN`; locally `export GITHUB_TOKEN=$(gh auth token)` |
| Pages shows 404 | Source not set to GitHub Actions | Step 6.3, then re-run the Pages workflow |
| `npm ci` reports high-severity `picomatch` advisories | A ReDoS advisory in Vite's build-time glob matcher with no fixed release yet; nothing reaches the shipped site | `npm audit --omit=dev` should show 0. Don't run `npm audit fix --force`: it downgrades Vite. Dependabot will raise the fix when one ships |
| An action version doesn't resolve | A newer major replaced it | Accept the Dependabot PR, or update the `uses:` line to the current major |

## What comes next

Milestone 1 builds the ingestion pipeline on these foundations: a documents
bucket, EventBridge and SQS, and the first container-image Lambda pushed to the
ECR repository you just created.
