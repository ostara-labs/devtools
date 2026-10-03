#!/usr/bin/env bash
#
# setup-org-rulesets.sh - provision the "main-protection" branch ruleset at
# the ORGANIZATION level, so every repository inherits identical branch
# protection without per-repo setup.
#
#   gh auth refresh -h github.com -s admin:org     # one-time scope grant
#   bash scripts/setup-org-rulesets.sh ostara-labs
#
# THIS SCRIPT AND infra/rulesets/index.ts MUST DECLARE THE SAME THING.
# They did not until 2026-10-03, and the divergence was invisible for weeks:
# the Pulumi file names its ruleset "core-branch-protection", which has never
# existed on GitHub, so it governed nothing while this script created and
# re-created the ruleset that is actually live ("main-protection"). The two
# also disagreed on the approving-review count, the review-thread rule, the
# merge methods and the required checks. Change one, change the other.
#
# Scope notes:
#   - Requires admin:org (the repo-level equivalent needs no such scope,
#     which is why a Pulumi RepositoryRuleset exists for the per-repo cases).
#   - INCLUDES every repository, bot and devtools alike. The approving-review
#     count stays at 0 precisely so bot keeps its autonomy: its pr-classify
#     workflow merges an `evolvable` PR itself, and a workflow token cannot
#     supply a human approval, so a count of 1 would make the bot wait for a
#     review that never comes and block its own mutation path.
#
set -euo pipefail

ORG="${1:?usage: bash scripts/setup-org-rulesets.sh <org>}"

PAYLOAD="$(cat <<JSON
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
