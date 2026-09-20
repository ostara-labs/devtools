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
- `.github/workflows/` — `ci.yml` (aggregate), `ai-review.yml`, `pr-pipeline.yml`, `docs-drift.yml`, `drift-scan.yml`, `release.yml`, `security.yml`, `trust-boundary-protect.yml`, per-stack `*-ci.yml`
- `.github/actions/` — composite actions: `org-gate`, `merge-gate-verdict`, `automerge-dispatch`
- `infra/rulesets/` — org ruleset definitions (Pulumi)
- `scripts/` — `install.sh`, `install.ps1`, `check-docs-drift.py`, `setup-org-rulesets.sh`, `sync-repo-secrets.sh`
- `docs/` — `TOOLCHAIN.md`, `ai-review.md`, `codeowners-trust-boundary.md`, `setup-guide.md`
- `default.json` — org Renovate preset

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
