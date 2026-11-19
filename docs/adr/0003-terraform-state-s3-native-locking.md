# 0003. Store Terraform state in S3 with native locking

- **Status:** Accepted
- **Date:** 2026-11-17

## Context

Terraform state must be shared between a laptop and CI, survive mistakes, and
never be public. Terraform 1.11 made S3-native state locking generally
available and deprecated the DynamoDB lock table arguments.

## Decision

One S3 bucket per account, created by `infra/bootstrap`: versioned, SSE-S3,
public access blocked, TLS-only bucket policy, noncurrent versions expire after
90 days, `prevent_destroy` on. Each stack uses its own key and `use_lockfile = true`.
The bucket name is passed at init time (partial backend configuration) so no
account ID is committed.

## Alternatives considered

| Option | Why not |
| --- | --- |
| DynamoDB lock table | Deprecated in Terraform's S3 backend; one more resource to pay for and manage |
| HCP Terraform | Another account and service to manage; the S3 backend is enough for one person |
| Local state | Not shareable with CI; easy to lose |

## Consequences

Terraform 1.11 or later is required. The plan role runs with `-lock=false`
because it is read-only and cannot write the lock file.
