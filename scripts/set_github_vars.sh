#!/usr/bin/env bash
# Copy the bootstrap stack's outputs into GitHub repository variables, then
# create the `dev` environment that guards the apply role.
#
# Needs: terraform (with bootstrap state available), gh (logged in), jq.
# Usage: ./scripts/set_github_vars.sh [owner/repo]
set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
boot_dir="$(dirname "$0")/../infra/bootstrap"

echo "Reading bootstrap outputs..."
vars_json="$(terraform -chdir="$boot_dir" output -json github_variables)"

for name in AWS_REGION TF_STATE_BUCKET AWS_PLAN_ROLE_ARN AWS_APPLY_ROLE_ARN; do
  value="$(jq -r --arg n "$name" '.[$n]' <<<"$vars_json")"
  gh variable set "$name" --repo "$repo" --body "$value"
  echo "  set $name"
done

echo "Creating the dev environment (deployments from main only)..."
visibility="$(gh repo view "$repo" --json visibility --jq .visibility)"
if [[ "$visibility" == "PUBLIC" ]]; then
  # Required reviewers are available for public repositories on every plan.
  user_id="$(gh api user --jq .id)"
  body="$(jq -n --argjson id "$user_id" '{
    reviewers: [{type: "User", id: $id}],
    deployment_branch_policy: {protected_branches: true, custom_branch_policies: false}
  }')"
else
  # Private repositories on GitHub Pro get branch restrictions but not reviewers.
  body='{"deployment_branch_policy": {"protected_branches": true, "custom_branch_policies": false}}'
  echo "  note: private repo, so no required reviewer; deploys are limited to protected branches"
fi
gh api --method PUT "repos/$repo/environments/dev" --input - <<<"$body" > /dev/null
echo "  environment dev ready"

echo "Done. Check: gh variable list --repo $repo"
