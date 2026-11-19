# Enterprise RAG Knowledge Assistant

Permission-aware question answering over internal documents, with citations.
Serverless on AWS, front end on GitHub Pages, infrastructure in Terraform, and
every change planned and deployed by GitHub Actions through OIDC.

> **Status:** Phase 0 (foundations). See [the Phase 0 guide](docs/phase-0-foundations.md).

## Architecture

| Layer | Deployed (low-cost variant, [ADR 0002](docs/adr/0002-serverless-low-cost-deployment.md)) |
| --- | --- |
| Front end | React + Vite on GitHub Pages |
| Identity | Amazon Cognito user pool with groups |
| API and compute | AWS Lambda (outside a VPC), Lambda Function URL |
| Retrieval | LanceDB on Amazon S3: vector, keyword and hybrid search inside Lambda |
| Models | Open-weight chat model on Amazon Bedrock; open-source embedding and reranking models in Lambda |
| Ingestion | S3, EventBridge, SQS with a dead-letter queue, DynamoDB document registry |
| Delivery | Terraform, GitHub Actions with OIDC, Dependabot, pre-commit |

The full three-AZ production design, reviewed against the AWS Well-Architected
Framework, is in [docs/architecture](docs/architecture/).

## Repository map

| Path | Contents |
| --- | --- |
| `infra/bootstrap/` | State bucket, GitHub OIDC roles, permissions boundary, budget and anomaly alerts (applied once by hand) |
| `infra/envs/dev/` | The dev environment, deployed by the pipeline |
| `infra/modules/` | Reusable modules (`lambda_function` now; more per milestone) |
| `services/` | Lambda function code |
| `frontend/` | React app for GitHub Pages |
| `eval/` | Evaluation datasets, runners and reports |
| `corpus/` | Sample documents and metadata |
| `docs/` | Guides, ADRs, architecture, security |
| `scripts/` | Setup and smoke-test helpers |

## Getting started

Follow [docs/phase-0-foundations.md](docs/phase-0-foundations.md). In short:

```bash
make setup             # dependencies and git hooks
make check             # everything CI runs
make bootstrap-apply   # once: state bucket, OIDC roles, cost alerts
make bedrock-check     # confirm model access
make github-setup      # repository variables and the dev environment
# open a PR, merge it, approve the deploy
make invoke-hello      # smoke test from your machine
```

Run `make help` for every target.

## Roadmap

- [ ] **Phase 0:** foundations (account, cost alerts, state, CI/CD, smoke test)
- [ ] **Milestones 1-4:** ingestion pipeline, extraction, chunking, embeddings, indexing
- [ ] **Milestones 5-7:** retrieval, grounded answers, citations, streaming, front end
- [ ] **Milestone 8:** Cognito authentication and document-level access control
- [ ] **Milestone 9:** guardrails and prompt-injection defences
- [ ] **Milestone 10:** evaluation with a golden dataset and CI gates

## Cost

Phase 0 is designed to cost pennies a month. A results table with cost per
1,000 queries will be added once the query path exists.

## Security

- No long-lived AWS keys: humans use IAM Identity Center, the pipeline uses OIDC.
- Pull requests get a read-only role; only the approved `dev` environment can apply.
- Every workload role carries a permissions boundary that forbids IAM changes and access to Terraform state.
- Pre-commit runs gitleaks; Checkov and TFLint run on every pull request.

## Licence

[MIT](LICENSE)
