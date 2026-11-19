# Security

The full security assessment is written during Milestones 8-9. It will cover:

1. Scope and data flow, with trust boundaries.
2. Assets: documents by classification, embeddings, logs, tokens.
3. Threat model: STRIDE per component, mapped to the OWASP Top 10 for LLM Applications 2026.
4. AWS controls and how each is verified.
5. Automated checks: Checkov, TFLint, gitleaks, pip-audit, npm audit.
6. Privacy and data residency (UK GDPR).
7. Accepted residual risks.

## Phase 0 controls already in place

| Control | Where |
| --- | --- |
| No long-lived keys; Identity Center for people, OIDC for CI | docs/phase-0-foundations.md, infra/bootstrap/github_oidc.tf |
| Read-only plan role; apply only from the protected `dev` environment | infra/bootstrap/github_oidc.tf |
| Permissions boundary on every workload role | infra/bootstrap/github_oidc.tf, infra/modules/lambda_function |
| Encrypted, versioned, TLS-only state bucket | infra/bootstrap/state.tf |
| Budget and anomaly alerts | infra/bootstrap/cost_guardrails.tf |
| Secret scanning before every commit | .pre-commit-config.yaml (gitleaks) |
| IaC security scan on every PR | .github/workflows/ci.yml (Checkov) |
