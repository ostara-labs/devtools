# AGENTS.md

## Project

`ostara-labs/devtools` is the shared development tooling for every
`ostara-labs` repository: git hooks, standard Makefiles, ONE aggregate CI
workflow, shared lint configs, a weekly drift-scan, and the org Renovate
preset. It ensures consistent code-quality enforcement regardless of which
repo the agent (or a human) is working in.

> **Trust-boundary repository.** Any PR here requires human review (HITL).
> Changes affect enforcement across ALL org repos. The agent MUST NOT
> auto-merge PRs to this repo.

## Context Loading

The repository is mostly documentation and configuration, so the work is not
"which file do I edit" but "what does this file's contract actually say". Each
area below has one document that owns its truth. Read it before changing the
area, and before making a claim about it.

### For any change

| Document | What it owns |
|---|---|
| This file | Repo structure, consumption model, CI contract, trust boundary |
| `docs/ai-review.md` | How a PR is reviewed and what blocks a merge |
| `docs/setup-guide.md` | The one-time setup: repo publication, GitHub App, Pulumi backend, ruleset deployment |

### By area

| If you are changing | Read first | Because it defines |
|---|---|---|
| `hooks/**` | This file, `## Boundaries` | What is enforcement surface, and the Ask-first rule |
| `makefiles/**` | This file, `## Consumption model` | The targets consumers are promised |
| `.github/workflows/ci.yml` | `docs/ai-review.md` | The seven required contexts and how `merge-gate` decides |
| `.github/workflows/ai-review.yml` | `docs/ai-review.md` | Reviewer behaviour, failure visibility, why a skipped review passes and a failed one does not |
| `.github/workflows/drift-scan.yml` | `docs/dependency-updates.md` | That its failure is informational: it exits non-zero when it *finds* drift |
| `.github/workflows/health-check.yml` | `docs/health-check.md` | The four states (BROKEN / ACTION / INFO / GAP) and why an absence is not a failure |
| `.github/workflows/renovate.yml` | `docs/dependency-updates.md` | The three update layers, and why `.devtools` and the `uses:` refs move together |
| `default.json` | `docs/dependency-updates.md` | What may automerge and what may not |
| `infra/rulesets/**` | `docs/infrastructure-state.md` | Where the state lives, why it is separate from the bot project, and that `infra/rulesets/index.ts` and `scripts/setup-org-rulesets.sh` must declare the same thing |
| `scripts/setup-org-rulesets.sh` | `docs/infrastructure-state.md` | The same rule, seen from the other file |
| `docs/**` | `README.md` | Which documents are indexed and how they are linked |

### Verifying before claiming

Most of what this repository touches is defined by an external tool — `gh`,
`pulumi`, `gcloud`, GitHub's ruleset API, Renovate's configuration schema. A
plausible-sounding option is not evidence that it exists.

Before reporting that an option is wrong, name the source you checked: the
tool's `--help`, the provider's schema, the API documentation. If the claim
cannot be traced to one of those, it is a guess and should not be reported.

Past changes here were reverted because a field was assumed
(`github:appAuth.pem` does not exist), a value was assumed to be available on
this org's plan (`enforcement: evaluate` is Enterprise-only), and a flag was
assumed to be safe (`--detailed-exitcode` turns ordinary changes into a
non-zero exit the pipeline would have to reinterpret).

### When the check fails

`ci / core` runs `actionlint` over every workflow, `shellcheck` over every
shell script, and `gitleaks`. Those catch syntax and secrets, not semantics: a
`gh` invocation can be valid YAML and impossible to run, and a `Pulumi.yaml`
can parse until Pulumi actually reads it. Some failures only appear on the
first real execution, which is why `docs/infrastructure-state.md` records the
ones already hit rather than leaving them to be rediscovered.

## What this repo provides

| Component | What it enforces | Consumed via |
|---|---|---|
| `hooks/` | `pre-commit` (secrets, file size, lint patterns, hygiene), `pre-push` (clippy, tests, miri, no-commit-to-branch), `commit-msg` (format) — language-aware | `git config core.hooksPath .devtools/hooks` |
| `makefiles/` | Standard targets `make lint\|test\|build\|ci\|format\|hooks\|devtools-update\|help` | `include .devtools/makefiles/Makefile.<lang>` |
| `.github/workflows/ci.yml` | THE org aggregate CI: seven required contexts; language jobs auto-detect and succeed vacuously when a stack is absent | one-line caller pinned by digest |
| `.github/workflows/drift-scan.yml` | Weekly conformance audit of every org repo (submodule gitlink + workflow refs vs latest release) | org-level scheduled workflow |
| `configs/` | Shared lint configs: `clippy.toml`, `rustfmt.toml`, `biome.json`, `.gitleaks.toml`, `.coderabbit.yaml` | symlink or copy into repo root |
| `default.json` | Org Renovate preset: git-submodules + github-actions managers, automerge scoped to `.devtools` and `ostara-labs/devtools/*` refs | `extends ["github>ostara-labs/devtools"]` |

## Structure

- `hooks/` — `pre-commit`, `pre-push`, `commit-msg`
- `makefiles/` — `Makefile.common`, `.rust`, `.elixir`, `.typescript`, `.python`
- `configs/` — shared lint configs (see table)
- `.github/workflows/` — `ci.yml` (aggregate), `ai-review.yml`, `pr-pipeline.yml`, `docs-drift.yml`, `drift-scan.yml`, `health-check.yml`, `renovate.yml`, `release.yml`, `security.yml`, `trust-boundary-protect.yml`, `deploy-rulesets.yml`, per-stack `*-ci.yml` (`rust`, `elixir`, `typescript`, `python`)
- `.github/actions/` — composite actions: `org-gate`, `merge-gate-verdict`, `automerge-dispatch`
- `infra/rulesets/` — org ruleset definitions (Pulumi)
- `scripts/` — `install.sh`, `install.ps1`, `check-docs-drift.py`, `setup-org-rulesets.sh`, `sync-repo-secrets.sh`
- `docs/` — `TOOLCHAIN.md`, `ai-review.md`, `codeowners-trust-boundary.md`, `dependency-updates.md`, `health-check.md`, `infrastructure-state.md`, `setup-guide.md`
- `default.json` — org Renovate preset

> The lists above are part of the contract: a workflow or a document that is
> not named here is a workflow or a document consumers will not find. Adding or
> renaming one means updating this section in the same commit.

## Consumption model

Consumers add devtools as a git submodule at `.devtools/`, set
`core.hooksPath`, and carry a thin CI caller pinned to an immutable digest:

```bash
git submodule add https://github.com/ostara-labs/devtools .devtools
git config core.hooksPath .devtools/hooks   # or: make hooks
```

Bump the caller digest via `make devtools-update` + the matching tag commit,
or let Renovate automerge (every devtools change is human-reviewed at the
source).

## CI contract

There is **no top-level Makefile** in devtools. Consumers get the shared
targets above; devtools validates itself through its own aggregate CI
(workflow lint via actionlint + shellcheck + gitleaks in `ci / core`),
release-please, and the self-adopted PR pipeline.

The aggregate exposes seven required contexts: `ci / core`,
`ci / rust / rust`, `ci / elixir / elixir`, `ci / typescript / typescript`,
`ci / python / python`, `ci / docs-drift / Docs drift (DOC_MAP)`, `ci / gate`.
Absent stacks succeed vacuously, so one ruleset fits every repo.

The PR pipeline (`pr-pipeline.yml`) chains `ci` → `ai-review` → `merge-gate`.
`merge-gate` is the merge gate: it fails unless CI succeeded, AI review
succeeded, and no blocking label is present. Blocking labels:
`Possible security concern` and `size: too-big`. Removing a blocking label is
the audited override.

### Cutting a release

`release.yml` runs release-please (`release-type: simple`, default config):
only `feat` / `fix` / `perf` commits are "user facing" and bump a version.
A `ci:` / `chore:` / `docs:` commit passes the commit hooks but **cuts no
release** — it strands on `main`, and no consumer can bump its pinned digest
to it. Type any change a consumer must receive as `feat(<scope>):`,
`fix(<scope>):` or `perf(<scope>):`.

## Trust boundary

This repo is the org's trust-boundary hub: the hooks and CI workflows here
constrain every other repo. If the agent could modify it without human
review, it could weaken the hooks that enforce its own code quality.

- Any PR to `ostara-labs/devtools` requires human review (HITL).
- The agent MUST NOT auto-merge PRs to this repo.
- `CODEOWNERS` (`* @Oloompa`) + the `trust-boundary-human-review` ruleset
  enforce code-owner approval; `trust-boundary-protect.yml` applies the
  `requires-human-review` label.

## AI review

PR-Agent runs on every non-draft PR with green CI (zero model spend on
drafts and red CI). It auto-loads this `AGENTS.md` from the default branch
as the repo's conventions. It posts one persistent review comment, adds
labels (`Review effort x/5`, `Possible security concern`) and a merge
recommendation. Green checks mean the review **ran** — never that its
findings were addressed: triage every thread (fix, or reply with a
justification and resolve) before merging.

## Boundaries

### Always

- Keep changes minimal and scoped; this repo's blast radius is the whole org.
- Run the relevant checks locally before declaring work done.
- Update `docs/` when behavior changes.
- Update the lists in `## Structure` and `README.md` when a workflow or a
  document is added, renamed or removed — they are how consumers and agents
  find things, and they drift silently otherwise.

### Ask first

- Edit `.github/workflows/**`, `hooks/**`, `makefiles/**`, `configs/**`, or
  `infra/**` — these are the enforcement surface.
- Change the Makefile contract or the git-hook wiring.
- Add dependencies.

### Never

- Auto-merge or merge a PR to this repo.
- Commit real secrets or `.env` files.
- Force-push `main`.
- Bypass or disable hooks or CI gates.
- Weaken lint configs to pass.
- Commit directly to `main`.
