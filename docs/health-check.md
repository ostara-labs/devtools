# Org health check

One issue in this repository says whether the shared tooling works. It is
closed while everything is nominal and reopened with a mention when something
breaks.

## The problem this solves

Detection was never the gap. `drift-scan` has been reporting devtools drift
every week since 2026-09-14, and its tracking issue (devtools#33) was accurate
the entire time — it listed all ten repos, their submodule sha, and why each
was behind. It went unread for 26 days.

The reason is mechanical, not human: **GitHub notifies on issue creation,
assignment, @-mention and third-party comments — and on nothing else.** An
issue that stays open while a bot rewrites its body through the API produces
no notification at all. It was a noticeboard in a room nobody walks through.

So this check adds no reporting. It produces the **transition**: the issue
closes when everything recovers and reopens when something breaks, and a
reopening notifies.

## The four states

A workflow can be red for reasons that are not failures, so four outcomes are
distinguished. Collapsing them into "red or not" is what makes an alerting
system get ignored.

| State | Meaning | Effect |
|---|---|---|
| **BROKEN** | a workflow that should work did not | reopens the issue, mentions you |
| **ACTION** | GitHub awaits a human approval (`action_required`) | reopens the issue, mentions you |
| **INFO** | an expected failure — `drift-scan` exits 1 when it *finds* drift | listed, never alerts |
| **GAP** | the repo does not carry that capability at all | declared, never alerts |

**GAP matters as much as BROKEN.** Seven of the eleven repos carry no
`security.yml`. Reporting that as seven failures would train you to ignore the
report; reporting it as nothing would hide a real hole. It is named.

## What is monitored

The capability table lives in `scripts/health-check.sh` as `CAPABILITIES`. Each
line is `workflow file | expected | meaning`.

| Workflow | Expected | Why |
|---|---|---|
| `deploy-catchup.yml` | green | catches deploys lost to dropped push triggers |
| `build-and-push.yml` | green | builds and deploys the agent image |
| `security.yml` | green | secret and vulnerability scanning |
| `drift-scan.yml` | drift | fails *on* drift — a failure is the job working |
| `pr-pipeline.yml`, `pr-meta.yml`, `pr-classify.yml` | any | PR gates; `action_required` is reported, not failed |

### Why the last run, not a count

Counting failed runs is useless here. `ostara-labs/bot` shows 166 failures
because one dead cron repeats every fifteen minutes — a count that says
"166 problems" where there is one. The check reads the **last run of each
workflow that exists**, per repo, which is the question actually being asked.

## Runtime

Daily at 06:00 UTC, plus `workflow_dispatch`.

The job needs `issues: write` on this repository and the ability to read
workflow runs across the org. It reuses the auth chain `drift-scan` documents
— a GitHub App installation token (`DEVTOOLS_APP_ID` +
`DEVTOOLS_APP_PRIVATE_KEY`), or the `ORG_AUDIT_TOKEN` PAT fallback. Issue
writes use the built-in token, which carries `issues: write` on this repo.

## Adding a workflow

Add a line to `CAPABILITIES`. Choose `expected` deliberately:

- `green` only if every non-success conclusion is genuinely a defect.
- `drift` only if a failure **is** the workflow doing its job.
- `any` if the workflow should exist and report, but its failures are not
  yours to act on.

A workflow added as `green` whose normal operation is to exit non-zero will
produce a permanent false alarm, and a permanent alarm is worse than none: it
teaches everyone to skip the report.
