# 0005. Make the repository public and require approval for deployments

- **Status:** Accepted
- **Date:** 2026-11-17

## Context

On GitHub Pro, required reviewers on environments are only available for public
repositories. Public repositories also get unlimited Actions minutes on
standard runners, and a portfolio is meant to be read.

## Decision

The repository is public. The `dev` environment requires the owner's approval
and accepts deployments only from protected branches.

To keep a public repository safe:

- the plan job never runs for pull requests from forks;
- the plan comment lists resource addresses and actions, never attribute values;
- workflows from outside collaborators need approval to run;
- secrets are never committed (gitleaks in pre-commit), and repository settings
  that are not secret are stored as variables.

## Consequences

Account IDs are kept out of committed files, though AWS does not treat them as
secret. If the repository is made private later, deployments still require
`main` but no longer pause for approval.
