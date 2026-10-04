# Org rulesets as code, with a state.
#
# WHY THIS REPLACES THE PULUMI PROGRAM (infra/rulesets/).
# Pulumi declared these rulesets and never applied one: its credentials lived in
# the stack config as `--secret` values, which puts an encrypted blob in the
# state and requires a KMS at every decrypt. On a GCS backend with a gcpkms
# secrets provider, that combination is broken upstream — pulumi/pulumi#11591,
# open since 2022-12-08, unassigned — and pinning the CLI to the version that
# works locally reproduced the failure exactly.
#
# The github provider reads its App credentials from the ENVIRONMENT
# (GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PEM_FILE), so nothing
# secret ever enters the state and there is no decryption step to fail.
#
# What this buys over scripts/setup-org-rulesets.sh, which still works and stays
# as the fallback: a plan before the change, a state file, and drift detection.

terraform {
  required_version = ">= 1.9"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }

  # No encryption and no KMS: nothing in this state is secret, because the
  # credentials come from the environment.
  backend "gcs" {
    bucket = "ostara-labs-rulesets-state"
    prefix = "terraform/rulesets"
  }
}

provider "github" {
  owner = var.org
}

variable "org" {
  type    = string
  default = "ostara-labs"
}

# An existing ruleset is adopted with `terraform import <addr> <ruleset-id>`:
#   main-protection  21254080
#   required-ci-checks 23150888
# Importing rather than recreating is what keeps the live object authoritative
# and lets the first plan show a diff instead of a destruction.
resource "github_organization_ruleset" "main_protection" {
  name        = "main-protection"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    # The approving-review count stays at 0 so bot keeps its autonomy: its
    # pr-classify workflow merges an `evolvable` PR itself, and a workflow token
    # cannot supply a human approval, so a count of 1 would make the bot wait
    # for a review that never arrives and block its own mutation path.
    pull_request {
      required_approving_review_count   = 0
      require_code_owner_review         = true
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = false
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = false
      required_check {
        context = "gate"
      }
    }
  }
}

# The aggregate CI exposes `ci / gate` and the PR pipeline exposes the
# `merge-gate` job. Both must report before a default branch moves.
resource "github_organization_ruleset" "required_ci_checks" {
  name        = "required-ci-checks"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = false
      required_check {
        context = "ci / gate"
      }
      required_check {
        context = "merge-gate"
      }
    }
  }
}

# target "push", not "branch": this inspects what is being pushed rather than
# what a branch looks like afterwards. It is the server-side half of the
# gitleaks the hooks run, and unlike them it cannot be skipped with --no-verify.
#
# No ref_name in the conditions: push rulesets operate on file content, not on
# refs, and the provider rejects the combination.
resource "github_organization_ruleset" "block_secrets_and_binaries" {
  name        = "block-secrets-and-binaries"
  target      = "push"
  enforcement = "active"

  conditions {
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    file_path_restriction {
      restricted_file_paths = [
        ".env",
        "*.pem",
        "*.key",
        "credentials*",
        "**/secrets/**",
      ]
    }

    file_extension_restriction {
      restricted_file_extensions = [
        "*.exe",
        "*.dll",
        "*.so",
        "*.dylib",
      ]
    }

    max_file_size {
      max_file_size = 50
    }
  }
}
