# Common tasks. Run `make help` for the list.
# Works in Codespaces, WSL2, Linux and macOS (not plain Windows PowerShell).

AWS_PROFILE ?= rag-dev
AWS_REGION  ?= eu-west-2
DEV_DIR     := infra/envs/dev
BOOT_DIR    := infra/bootstrap

export AWS_PROFILE AWS_REGION

.DEFAULT_GOAL := help
.PHONY: help setup lint fmt typecheck test check tf-fmt tf-validate tflint checkov \
        bootstrap-init bootstrap-plan bootstrap-apply github-setup bedrock-check \
        dev-init dev-plan dev-apply dev-destroy invoke-hello test-alerts frontend-dev eval

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Local quality gates (same as CI) -----------------------------------------

setup: ## Install Python and Node dependencies and the git hooks
	uv sync
	uv run pre-commit install
	cd frontend && npm ci

lint: ## Ruff lint and format check
	uv run ruff check .
	uv run ruff format --check .

fmt: ## Auto-format Python and Terraform
	uv run ruff format .
	uv run ruff check --fix .
	terraform fmt -recursive infra

typecheck: ## mypy in strict mode
	uv run mypy

test: ## Unit tests with coverage
	uv run pytest

tf-fmt: ## Terraform format check
	terraform fmt -check -recursive -diff infra

tf-validate: ## Terraform validate every stack (no backend needed)
	@for dir in $(BOOT_DIR) $(DEV_DIR) infra/modules/lambda_function; do \
	  echo "== $$dir"; \
	  terraform -chdir=$$dir init -backend=false -input=false > /dev/null && terraform -chdir=$$dir validate || exit 1; \
	done

tflint: ## TFLint with the AWS ruleset
	tflint --init --config $(CURDIR)/.tflint.hcl
	tflint --recursive --config $(CURDIR)/.tflint.hcl --chdir infra

checkov: ## IaC security scan
	uvx checkov --directory infra --framework terraform --compact --quiet --skip-download

check: lint typecheck test tf-fmt tf-validate tflint checkov ## Everything CI runs, locally

# --- Bootstrap (once, from your machine, with your admin SSO profile) ---------

bootstrap-init: ## terraform init for the bootstrap stack
	terraform -chdir=$(BOOT_DIR) init

bootstrap-plan: ## Plan the bootstrap stack
	terraform -chdir=$(BOOT_DIR) plan

bootstrap-apply: ## Create the state bucket, GitHub OIDC roles and cost alerts
	terraform -chdir=$(BOOT_DIR) apply

github-setup: ## Copy bootstrap outputs into GitHub repository variables
	./scripts/set_github_vars.sh

bedrock-check: ## Confirm this identity can call every Bedrock model the project uses
	uv run python -m scripts.check_bedrock_access --profile $(AWS_PROFILE) --region $(AWS_REGION)

test-alerts: ## Send a test message through the cost-alert topic
	./scripts/test_cost_alerts.sh

# --- Dev environment from your machine (CI normally does this) ----------------

dev-init: ## terraform init for dev using backend.hcl
	terraform -chdir=$(DEV_DIR) init -backend-config=backend.hcl

dev-plan: ## Plan dev
	terraform -chdir=$(DEV_DIR) plan -var-file=dev.tfvars

dev-apply: ## Apply dev from your machine (prefer the Deploy workflow)
	terraform -chdir=$(DEV_DIR) apply -var-file=dev.tfvars

dev-destroy: ## Destroy dev from your machine
	terraform -chdir=$(DEV_DIR) destroy -var-file=dev.tfvars

invoke-hello: ## Invoke the deployed smoke-test Lambda
	./scripts/invoke_hello.sh

# --- Other ---------------------------------------------------------------------

frontend-dev: ## Run the front end locally
	cd frontend && npm run dev

eval: ## Evaluation runner (placeholder until Milestone 10)
	uv run python -m eval.runners.run --dry-run
