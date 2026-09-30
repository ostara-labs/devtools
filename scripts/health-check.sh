#!/usr/bin/env bash
# Org health check — one marker that says whether the shared tooling works.
#
# See docs/health-check.md for the full rationale. The problem it solves is not
# detection: drift-scan has been reporting devtools drift every week since
# 2026-09-14, and its tracking issue (devtools#33) was accurate the whole time.
# Nobody read it. An open issue whose body a bot rewrites through the API
# notifies nothing — GitHub notifies on creation, assignment, @-mention and
# third-party comments only.
#
# So this script does not add more reporting. It produces the TRANSITION:
# the issue is CLOSED while everything is nominal, and REOPENED with a mention
# when something breaks. Silence means healthy.
#
# STATE MODEL — four outcomes, because a workflow can be red for good reasons:
#
#   BROKEN  a critical workflow's last run is a real failure        -> alert
#   ACTION  a workflow awaits human approval (action_required)      -> asks you
#   INFO    a failure that is the workflow doing its job (drift)    -> listed
#   GAP     the repo does not carry the capability at all           -> declared
#
# Counting failed runs would be useless here: bot alone shows 166, because one
# dead cron repeats every 15 minutes. What matters is the last run of the
# workflows that exist, per repo.

set -euo pipefail

ORG="${ORG:-ostara-labs}"
SELF_REPO="${GITHUB_REPOSITORY:-$ORG/devtools}"
ISSUE_TITLE="Org health report"
BODY_FILE="$(mktemp)"
SUMMARY_FILE="$(mktemp)"

gh_api() { gh api "$@"; }

# capability|workflow file|expected|scope|meaning
#
# `expected` is one of:
#   green   the last run must be `success`; anything else is BROKEN
#   any     monitored for presence only (never alerts)
#   drift   a failure is normal — this workflow exits 1 when it FINDS drift
#
# `scope` decides what an ABSENCE means, and this is the difference between a
# useful report and noise:
#   all      every repo must carry it — absent is a real hole (GAP)
#   single   only SELF_CARRIER carries it — absent elsewhere is simply not its
#            job, and reporting it would bury the real holes under 10 rows of
#            "bot does not build the agent image", which is not a finding
#   none     optional everywhere — absent is never reported
#
# Measured before this distinction existed: 43 GAP rows, of which only the 7
# repos missing security.yml were actionable.
SELF_CARRIER="${SELF_CARRIER:-bot}"

CAPABILITIES="
deploy-catchup.yml|deploy-catchup.yml|green|single|catches deploys lost to dropped push triggers
build-and-push.yml|build-and-push.yml|green|single|builds and deploys the agent image
security.yml|security.yml|green|all|secret and vulnerability scanning
drift-scan.yml|drift-scan.yml|drift|none|devtools conformance audit (fails ON drift)
pr-pipeline.yml|pr-pipeline.yml|any|none|PR gate chain
pr-meta.yml|pr-meta.yml|any|none|PR labelling and metadata
pr-classify.yml|pr-classify.yml|any|none|trust-boundary classification
"

broken=0
action_needed=0
infos=0
gaps=0

{
  echo "| Repo | Workflow | Last run | State |"
  echo "|---|---|---|---|"
} > "$SUMMARY_FILE"

row() {
  local repo="$1" cap="$2" created="$3" url="$4" state="$5"
  if [ -n "$url" ] && [ "$url" != "-" ]; then
    echo "| $repo | [$cap]($url) | $created | $state |" >> "$SUMMARY_FILE"
  else
    echo "| $repo | $cap | $created | $state |" >> "$SUMMARY_FILE"
  fi
}

list_repos() {
  gh_api "/orgs/$ORG/repos?per_page=100" --paginate --jq '.[].name' | sort
}

last_run_of() {
  local repo="$1" wf="$2"
  gh_api "repos/$ORG/$repo/actions/workflows/$wf/runs?per_page=1" \
    --jq '.workflow_runs[0] | "\(.conclusion // .status // "none")|\(.created_at // "-")|\(.html_url // "-")"' 2>/dev/null || echo "none|-|-"
}

wf_exists() {
  local repo="$1" wf="$2"
  gh_api "repos/$ORG/$repo/actions/workflows/$wf" >/dev/null 2>&1
}

for repo in $(list_repos); do
  [ "$repo" = "devtools" ] && { [ "$SELF_REPO" = "$ORG/$repo" ] && repo="devtools"; }

  while IFS='|' read -r cap wf expect scope meaning; do
    [ -z "${cap:-}" ] && continue

    if ! wf_exists "$repo" "$wf"; then
      case "$scope" in
        all)
          gaps=$((gaps + 1))
          row "$repo" "$cap" "—" "-" "**GAP** — every repo should carry this: $meaning"
          ;;
        single)
          [ "$repo" = "$SELF_CARRIER" ] && { gaps=$((gaps + 1)); row "$repo" "$cap" "—" "-" "**GAP** — $meaning"; }
          ;;
        none) : ;;
      esac
      continue
    fi

    IFS='|' read -r conclusion created url <<<"$(last_run_of "$repo" "$wf")"

    case "$expect" in
      drift)
        if [ "$conclusion" = "success" ] || [ "$conclusion" = "failure" ]; then
          infos=$((infos + 1))
          row "$repo" "$cap" "$conclusion ($created)" "$url" "INFO — $meaning"
        else
          broken=$((broken + 1))
          row "$repo" "$cap" "$conclusion ($created)" "$url" "**BROKEN** — could not run: $meaning"
        fi
        ;;
      green)
        case "$conclusion" in
          success)
            row "$repo" "$cap" "success ($created)" "$url" "ok" ;;
          action_required)
            action_needed=$((action_needed + 1))
            row "$repo" "$cap" "action_required ($created)" "$url" "**ACTION** — awaiting approval" ;;
          none|"")
            broken=$((broken + 1))
            row "$repo" "$cap" "none" "-" "**BROKEN** — never ran: $meaning" ;;
          *)
            broken=$((broken + 1))
            row "$repo" "$cap" "$conclusion ($created)" "$url" "**BROKEN** — $meaning" ;;
        esac
        ;;
      any)
        if [ "$conclusion" = "action_required" ]; then
          action_needed=$((action_needed + 1))
          row "$repo" "$cap" "action_required ($created)" "$url" "**ACTION** — awaiting approval"
        else
          row "$repo" "$cap" "$conclusion ($created)" "$url" "ok"
        fi
        ;;
    esac
  done <<< "$CAPABILITIES"
done

{
  echo "Org health check — reference: \`$(date -u +%Y-%m-%d)\`"
  echo ""
  echo "**\`$broken\` broken · \`$action_needed\` awaiting you · \`$infos\` informational · \`$gaps\` capability gaps**"
  echo ""
  cat "$SUMMARY_FILE"
  echo ""
  echo "---"
  echo ""
  echo "**BROKEN** means a workflow that should work did not. **ACTION** means GitHub"
  echo "is waiting for a human approval, not that anything failed. **INFO** is an"
  echo "expected failure (drift-scan exits 1 when it finds drift). **GAP** means the"
  echo "repo does not carry that capability — declared, not counted as a failure."
  echo ""
  echo "This issue is closed automatically when the counts reach 0 broken and 0"
  echo "awaiting. Its reopening is what notifies, so silence here means healthy."
} > "$BODY_FILE"

cat "$BODY_FILE"

search_issue() {
  gh api "search/issues?q=repo:$SELF_REPO+is:issue+in:title+%22Org+health+report%22" \
    --jq '.items[0].number // empty' 2>/dev/null || echo ""
}

issue_number="$(search_issue)"
needs_attention=$((broken + action_needed))

# `-F body=@file` reads the file's CONTENT; `-F body=file` sends the path
# string itself. The first draft used the latter and opened an issue whose
# entire body was a temp path — visible only by running it against the real
# API, which is why this script is exercised before it ships.
body_arg() { printf '%s' "@$BODY_FILE"; }

if [ "$issue_number" = "" ]; then
  if [ "$needs_attention" -gt 0 ]; then
    printf '\n@Oloompa — %s workflow(s) broken, %s awaiting your approval.\n' "$broken" "$action_needed" >> "$BODY_FILE"
    gh api "repos/$SELF_REPO/issues" \
      -f title="$ISSUE_TITLE" \
      -F body="$(body_arg)" >/dev/null
    echo "opened health report (attention needed)"
  else
    echo "healthy: no report issue exists and none is needed"
  fi
  exit 0
fi

current_state="$(gh api "repos/$SELF_REPO/issues/$issue_number" --jq '.state')"

if [ "$needs_attention" -gt 0 ]; then
  gh api -X PATCH "repos/$SELF_REPO/issues/$issue_number" -F body="$(body_arg)" >/dev/null
  if [ "$current_state" = "closed" ]; then
    gh api -X PATCH "repos/$SELF_REPO/issues/$issue_number" -f state="open" >/dev/null
    gh api "repos/$SELF_REPO/issues/$issue_number/comments" \
      -f body="@Oloompa — $broken workflow(s) broken, $action_needed awaiting your approval. Reopening this report." >/dev/null
    echo "reopened health report and notified"
  else
    echo "health report updated (still open, still broken)"
  fi
else
  gh api -X PATCH "repos/$SELF_REPO/issues/$issue_number" -F body="$(body_arg)" >/dev/null
  if [ "$current_state" = "open" ]; then
    gh api -X PATCH "repos/$SELF_REPO/issues/$issue_number" -f state="closed" >/dev/null
    echo "closed health report — everything nominal"
  else
    echo "healthy (report already closed)"
  fi
fi

exit 0
