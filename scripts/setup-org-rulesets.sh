#!/usr/bin/env bash
#
# setup-org-rulesets.sh - provision the "main-protection" branch ruleset at
# the ORGANIZATION level, so every repository inherits identical branch
# protection without per-repo setup.
#
#   gh auth refresh -h github.com -s admin:org     # one-time scope grant
#   bash scripts/setup-org-rulesets.sh ostara-labs
#
# Scope notes:
#   - Requires admin:org (the repo-level equivalent needs no such scope,
#     which is why scripts/setup-rulesets.sh exists for single repos).
#   - EXCLUDES repos whose CI does not emit this org's standard check names
#     ("title", "workflow-lint", "rust / rust", ...). Today: "bot" (legacy
#     local hooks/checks) and "devtools" itself. New NON-template repos must
#     either adopt the standard checks or be added to EXCLUDED_REPOS below.
#
set -euo pipefail

# Windows (Git Bash): MSYS rewrites leading-slash arguments into Windows
# paths, which corrupts the gh api endpoints below ("/orgs/..." would
# arrive as a filesystem path). Disable conversion for this process.
export MSYS_NO_PATHCONV=1

ORG="${1:?usage: bash scripts/setup-org-rulesets.sh <org>}"

EXCLUDED_REPOS=("bot" "devtools")

excludes_json="$(printf '"%s",' "${EXCLUDED_REPOS[@]}")"
excludes_json="[${excludes_json%,}]"

PAYLOAD="$(cat <<JSON
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] },
    "repository_name": { "include": ["~ALL"], "exclude": ${excludes_json} }
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
        "required_review_thread_resolution": false
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

echo "[org-rulesets] ensuring main-protection on org $ORG"

EXISTING_ID="$(gh api "/orgs/$ORG/rulesets" --jq '.[] | select(.name == "main-protection") | .id' || true)"
if [ -n "$EXISTING_ID" ]; then
  echo "[org-rulesets] ruleset exists (id=$EXISTING_ID) - updating"
  gh api -X PUT "/orgs/$ORG/rulesets/$EXISTING_ID" --input - <<<"$PAYLOAD" >/dev/null
else
  gh api -X POST "/orgs/$ORG/rulesets" --input - <<<"$PAYLOAD" --jq '.id'
fi

echo "[org-rulesets] done."
echo "[org-rulesets] next: delete now-redundant repo-level rulesets"
echo "[org-rulesets] (e.g. id 21230269 on ostara-labs/repo-template) so only"
echo "[org-rulesets] the org-level policy remains authoritative."
