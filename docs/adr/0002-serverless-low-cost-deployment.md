# 0002. Deploy a serverless, low-cost variant; keep the three-AZ design as the reference

- **Status:** Accepted
- **Date:** 2026-11-17

## Context

The reference architecture (`docs/architecture/enterprise-rag-well-architected.drawio`)
runs Lambda in a three-AZ VPC with NAT gateways, interface endpoints and
OpenSearch Serverless, plus Bedrock Rerank in Frankfurt. For a personal
portfolio, the always-on network pieces dominate the bill: three NAT gateways
and six interface endpoints across three AZs come to roughly $235 a month
before any traffic.

## Decision

Deploy a variant that keeps the same security model but has no idle cost:

- Lambda functions run **outside a VPC** and call AWS APIs over TLS with IAM authentication.
- The front end is hosted on **GitHub Pages**; CI/CD runs on **GitHub Actions** with OIDC.
- The answer model is an **open-weight model on Bedrock** (`openai.gpt-oss-20b-1:0`), in-Region in Oregon.
- From Milestone 1, vector and keyword search use **LanceDB on S3** inside Lambda, embeddings and
  reranking run on CPU in Lambda with open-source models, and OCR uses an open-source engine.

Document-level access control does not change: it is enforced in the retrieval
query from verified token claims, whatever the network design.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Full three-AZ VPC design | About $235 a month idle for NAT and endpoints alone |
| OpenSearch Serverless | Adds a managed search service the small corpus doesn't need |
| Self-hosting on a home lab | Zero cloud cost, but a weaker story for AWS roles and uptime depends on home hardware |

## Consequences

- Monthly cost at portfolio scale is expected to be a few pounds.
- Checkov flags Lambda outside a VPC (CKV_AWS_117); this is suppressed with a reference to this ADR.
- The three-AZ diagram stays in the repo as the documented production design,
  and the README explains which controls move into the VPC at production scale.
