# 0004. GitHub OIDC with split plan and apply roles and a workload permissions boundary

- **Status:** Accepted
- **Date:** 2026-11-17

## Context

The pipeline needs AWS access without long-lived keys. The deploy role must be
able to create IAM roles for Lambda functions, which is a privilege-escalation
path if unrestricted.

## Decision

- GitHub Actions authenticates through the OIDC provider; no access keys exist.
- **Plan role:** `ReadOnlyAccess`; trusted for this repository's pull requests and `main`.
- **Apply role:** `PowerUserAccess` plus scoped IAM; trusted only for jobs in the `dev` GitHub environment.
- The apply role may create roles only under `/rag-assistant/workload/` and only
  with the `rag-assistant-workload-boundary` permissions boundary attached. It
  cannot change the boundary or remove it from a role.
- The boundary denies all IAM and account actions and access to the state bucket,
  and limits data access to `rag-assistant-*` resources.

## Alternatives considered

| Option | Why not |
| --- | --- |
| One role for plan and apply | Every pull request could change infrastructure |
| `AdministratorAccess` on the apply role | A compromised workflow could take over the account |
| Access keys stored as GitHub secrets | Long-lived credentials that can leak |

## Consequences

Every workload role must set `path` and `permissions_boundary`; the
`lambda_function` module does this. New AWS services used by workloads must be
added to the boundary in the bootstrap stack, a deliberate, reviewed change.
