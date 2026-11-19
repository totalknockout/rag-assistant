# TFLint configuration shared by CI and pre-commit.
# Bump the ruleset version with Dependabot or `tflint --init` release notes.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
