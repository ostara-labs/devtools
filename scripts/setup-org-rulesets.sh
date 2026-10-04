#!/usr/bin/env bash
#
# setup-org-rulesets.sh - provision the ORG-level rulesets every repository
# inherits, without per-repo setup.
#
#   gh auth refresh -h github.com -s admin:org     # one-time scope grant
#   bash scripts/setup-org-rulesets.sh ostara-labs
#
# Idempotent: an existing ruleset is updated through PUT, a missing one is
# created through POST. Running it twice converges, so it is safe to re-run
# after any edit here.
#
# THIS SCRIPT AND infra/rulesets/index.ts MUST DECLARE THE SAME THING.
# They did not until 2026-10-03, and the divergence was invisible for weeks:
# the Pulumi file named its ruleset "core-branch-protection", which has never
# existed on GitHub, so it governed nothing while this script created and
# re-created the ruleset that is actually live ("main-protection"). The two
# also disagreed on the approving-review count, the review-thread rule, the
# merge methods and the required checks. Change one, change the other.
#
# Scope notes:
#   - Requires admin:org (the repo-level equivalent needs no such scope,
#     which is why the per-repo rulesets use a different API).
#   - INCLUDES every repository, bot and devtools alike. The approving-review
#     count stays at 0 precisely so bot keeps its autonomy: its pr-classify
#     workflow merges an `evolvable` PR itself, and a workflow token cannot
#     supply a human approval, so a count of 1 would make the bot wait for a
#     review that never comes and block its own mutation path.
#
# NOT HERE, because the API does not allow it at the organization level:
#   - merge-queue: the provider exposes mergeQueue only for a repository
#     ruleset, so it is declared per repository.
#   - the two trust-boundary rulesets: they name a single repository each.
#
set -euo pipefail

ORG="${1:?usage: bash scripts/setup-org-rulesets.sh <org>}"

# An org ruleset is applied by name: PUT replaces the existing one, POST
# creates it. Keeping the whole thing in one function is what makes a re-run
# converge instead of accumulating duplicates.
apply_org_ruleset() {
  local name="$1" payload="$2" existing_id

  # The listing must fail LOUDLY. Swallowing its error would leave existing_id
  # empty, send the script down the create path, and surface a 409 Conflict
  # from POST — an error about a duplicate, when the real problem was that the
  # listing never ran (missing admin:org, expired token, no network). The
  # distinction between "no ruleset by that name" and "could not find out" is
  # the whole point of this guard.
  if ! listing="$(gh api "/orgs/$ORG/rulesets" --jq ".[] | select(.name == \"$name\") | .id")"; then
    echo "[org-rulesets] ERROR: cannot list rulesets on $ORG" >&2
    echo "[org-rulesets]   check that GH_TOKEN carries the Administration:write" >&2
    echo "[org-rulesets]   organization permission, or admin:org for a user token" >&2
    return 1
  fi
  existing_id="$listing"

  if [ -n "$existing_id" ]; then
    echo "[org-rulesets] $name exists (id=$existing_id) - updating"
    gh api -X PUT "/orgs/$ORG/rulesets/$existing_id" --input - <<<"$payload" >/dev/null
  else
    echo "[org-rulesets] $name absent - creating"
    gh api -X POST "/orgs/$ORG/rulesets" --input - <<<"$payload" --jq '"  created id=" + (.id|tostring)'
  fi
}

MAIN_PROTECTION="$(cat <<JSON
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] },
    "repository_name": { "include": ["~ALL"], "exclude": [] }
  },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "require_code_owner_review": true,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "gate" }
        ]
      }
    }
  ]
}
JSON
)"

# A second org ruleset, on top of main-protection rather than merged into it.
# The aggregate CI exposes `ci / gate` and the PR pipeline exposes the
# `merge-gate` job, and both must report before a default branch moves.
REQUIRED_CI_CHECKS="$(cat <<JSON
{
  "name": "required-ci-checks",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] },
    "repository_name": { "include": ["~ALL"], "exclude": [] }
  },
  "bypass_actors": [],
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "ci / gate" },
          { "context": "merge-gate" }
        ]
      }
    }
  ]
}
JSON
)"

# target "push", not "branch": this inspects what is being pushed rather than
# what a branch looks like afterwards. It is the server-side half of the
# gitleaks the hooks run locally, and unlike them it cannot be bypassed with
# --no-verify. It has never existed on GitHub — the Pulumi program declared it
# and never applied.
#
# max_file_size is in MEGABYTES despite the name, and the API's valid range is
# 1-100. A byte count such as 52428800 is out of range and blocks nothing.
BLOCK_SECRETS_AND_BINARIES="$(cat <<JSON
{
  "name": "block-secrets-and-binaries",
  "target": "push",
  "enforcement": "active",
  "conditions": {
    "repository_name": { "include": ["~ALL"], "exclude": [] }
  },
  "bypass_actors": [],
  "rules": [
    {
      "type": "file_path_restriction",
      "parameters": {
        "restricted_file_paths": [
          "**/.env",
          "**/*.pem",
          "**/*.key",
          "**/credentials*",
          "**/secrets/**"
        ]
      }
    },
    {
      "type": "file_extension_restriction",
      "parameters": {
        "restricted_file_extensions": [
          "*.exe",
          "*.dll",
          "*.so",
          "*.dylib"
        ]
      }
    },
    {
      "type": "max_file_size",
      "parameters": {
        "max_file_size": 50
      }
    }
  ]
}
JSON
)"

echo "[org-rulesets] applying the org-level policy on $ORG"
apply_org_ruleset "main-protection" "$MAIN_PROTECTION"
apply_org_ruleset "required-ci-checks" "$REQUIRED_CI_CHECKS"
apply_org_ruleset "block-secrets-and-binaries" "$BLOCK_SECRETS_AND_BINARIES"

echo "[org-rulesets] done."
echo "[org-rulesets] verify with:"
echo "[org-rulesets]   gh api /orgs/$ORG/rulesets --jq '.[] | .name + \" \" + .target'"
