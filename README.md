# devtools — Shared development tooling for ostara-labs repos

> **Trust-boundary repo.** Any PR to this repository requires human review (HITL).
> Changes here affect enforcement across ALL repos in the organization.
> The agent MUST NOT auto-merge PRs to this repo.

Shared git hooks, Makefiles, ONE aggregate CI workflow, lint configs, drift-scan, and a Renovate preset for all `ostara-labs` repositories. Ensures consistent code quality enforcement regardless of which repo the agent (or a human) is working in.

---

## What this repo provides

| Component | What it enforces | Used via |
|---|---|---|
| `hooks/` | Git hooks: pre-commit (secrets, file size, lint patterns, hygiene), pre-push (clippy, tests, miri, no-commit-to-branch), commit-msg (format) | `git config core.hooksPath .devtools/hooks` (relative path — set by `make hooks` or `install.sh`) |
| `makefiles/` | Standard targets: `make lint`, `make test`, `make build`, `make ci`, `make format`, `make hooks`, `make devtools-update` | `include .devtools/makefiles/Makefile.<lang>` |
| `workflows/ci.yml` | THE org aggregate CI: one caller line per repo, seven required contexts, language jobs auto-detect + succeed vacuously when a stack is absent. Pinned by digest, bumped per release. | `uses: ostara-labs/devtools/.github/workflows/ci.yml@<digest> # vX.Y.Z` |
| `workflows/drift-scan.yml` | Weekly conformance audit of every org repo (submodule gitlink + workflow refs vs latest release); red run + rolling tracking issue on drift. GitHub App auth (preferred) or `ORG_AUDIT_TOKEN` PAT — see [Drift-scan setup](#drift-scan-setup). | Org-level scheduled workflow |
| `default.json` | Org Renovate preset: git-submodules + github-actions managers, automerge scoped to `.devtools` submodule and `ostara-labs/devtools/*` refs. | `extends ["github>ostara-labs/devtools"]` in `renovate.json` |
| `workflows/health-check.yml` | One issue in this repo says whether the shared tooling works: closed while everything is nominal, reopened with an `@`-mention when something breaks. Reads the last run of each monitored workflow per repo, never a failure count. | Org-level scheduled workflow (daily) — see [Health check](docs/health-check.md) |
| `workflows/renovate.yml` | Self-hosted Renovate: the org's single dependency-update engine, covering the devtools pins and the language ecosystems. | Org-level scheduled workflow (weekly) — see [Dependency updates](docs/dependency-updates.md) |
| `workflows/deploy-rulesets.yml` | Applies `infra/rulesets/` through Pulumi: the branch, push and merge-queue rulesets that govern every repo. | Runs on push to `main` under `infra/rulesets/**` — see [Infrastructure state](docs/infrastructure-state.md) |
| `workflows/pr-pipeline.yml` | The PR chain every consumer calls: `ci` → `ai-review` → `merge-gate`. `merge-gate` is what actually blocks a merge. | One-line caller per repo, same as `ci.yml` |
| `workflows/security.yml` | Secret and vulnerability scanning at the org level. | Org-level scheduled workflow |
| `workflows/apply-org-rulesets.yml` | Applies the org rulesets through the script, under a short-lived App installation token. Ran on the script or `infra/rulesets/**` changing. See [Infrastructure state](docs/infrastructure-state.md). | Push to `main`, manual dispatch |
| `workflows/terraform-rulesets.yml` | Plans `infra/rulesets-tf/` on every change and applies only on dispatch, so a plan can be compared before anything switches. State in GCS, unencrypted — the App credentials come from the environment. | Push / PR on `infra/rulesets-tf/**`, manual dispatch |
| `configs/` | Shared lint configs: clippy.toml, rustfmt.toml, biome.json, plus seeded `.gitleaks.toml` and `.coderabbit.yaml` via `install.sh` | Symlink or copy into repo root |
| `scripts/install.sh` | Bootstrap: sets the RELATIVE hooksPath, creates the Makefile stub, seeds configs | `bash .devtools/scripts/install.sh` from submodule |

---

## How a repo consumes devtools

The canonical model is a git submodule plus a 3-line CI caller:

```bash
# In the consuming repo:
git submodule add https://github.com/ostara-labs/devtools .devtools
git config core.hooksPath .devtools/hooks   # or: make hooks
```

Create `.github/workflows/ci.yml` in the consuming repo:

```yaml
jobs:
  gate:
    uses: ostara-labs/devtools/.github/workflows/ci.yml@8f2b8125d7eb67565474e50f8bb3bb67053a488d # v1.4.3
    with:
      stack-dir: ""  # empty = language defaults (rust/, typescript/, elixir/, python/); "." = root manifests; custom dir for other layouts
```

Updates: `make devtools-update` + move the caller `@SHA` to the matching tag commit — or let Renovate do it (automerge; every devtools change is human-reviewed at the source).

> **Deprecated:** The old curl bootstrap without submodule (`curl -sSL .../install.sh | bash`) remains supported during the migration window but is non-versioned and harder to audit. Migrate existing repos to the submodule model.

---

## Required status contexts

Every repo using the aggregate CI MUST expose exactly these seven status contexts to branch rulesets. Absent language stacks succeed vacuously, so a repo with only Rust still passes all seven.

| Context | Purpose |
|---|---|
| `ci / core` | Shared checks (secrets scan, file size, commit-msg format) |
| `ci / rust / rust` | Rust stack: fmt, clippy, test, build |
| `ci / elixir / elixir` | Elixir stack: format, credo, test, build |
| `ci / typescript / typescript` | TypeScript stack: biome, test, build |
| `ci / python / python` | Python stack: ruff, pytest, build |
| `ci / docs-drift / Docs drift (DOC_MAP)` | Docs-drift gate: mapped code must ship with its docs |
| `ci / gate` | Final aggregation + artifact gate |

Renaming the caller job blocks merges loudly. ONE ruleset per repo requires exactly these contexts.

---

## Drift-scan setup

The weekly scan enumerates every org repo and compares its devtools consumption against the latest release. It needs org-wide read access; the built-in `GITHUB_TOKEN` cannot list private org repos. Auth chain (first available wins):

1. **GitHub App (preferred)** — no manual expiry, independently revocable.
2. **`ORG_AUDIT_TOKEN`** — a fine-grained PAT (legacy fallback).
3. Built-in `GITHUB_TOKEN` — the run fails with a clear message; a config error, not drift.

### GitHub App (preferred)

1. Create the App: org **Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Repository permissions: **Contents: Read-only**, **Issues: Read and write**, **Metadata: Read-only** (mandatory).
   - "Where can this app be installed": **Only on this account**.
2. Install it on the `ostara-labs` org (**All repositories**).
3. In the App settings, **Generate a private key** (downloads a `.pem`).
4. On `devtools`: **Settings → Secrets and variables → Actions**:
   - **Variables**: `DEVTOOLS_APP_ID` = the App ID (from the App settings page).
   - **Secrets**: `DEVTOOLS_APP_PRIVATE_KEY` = the full contents of the `.pem`.

The scan mints a short-lived installation token at runtime via `actions/create-github-app-token`. No expiration to manage — rotate only if the key is compromised.

### PAT fallback (legacy)

Create a fine-grained PAT with **read access to all org repos**, store it as the `ORG_AUDIT_TOKEN` secret on devtools. Watch the expiry — a lapsed PAT silently breaks the weekly scan.

---

## Supported languages

| Language | Detected by | Hook checks | Makefile | CI stack |
|---|---|---|---|---|
| Rust | `Cargo.toml` | unwrap/expect, println, unsafe, 250 LOC, cargo fmt | `Makefile.rust` | `rust` |
| Elixir | `mix.exs` | IO.puts in production, mix format --check, 250 LOC | `Makefile.elixir` | `elixir` |
| TypeScript | `package.json` | console.log in production, biome check, 250 LOC | `Makefile.typescript` | `typescript` |
| Python | `pyproject.toml` | ruff check, pytest, 250 LOC | `Makefile.python` | `python` |

Hooks auto-detect the language — no configuration needed. A repo with both `Cargo.toml` and `package.json` runs checks for both.

The TypeScript CI auto-detects the package manager: `pnpm` for repos with `pnpm-lock.yaml` (the template convention), `npm ci` for repos with `package-lock.json` — npm repos predating the template are supported in CI. The shared `Makefile.typescript` targets stay pnpm-based; npm-native repos run their npm scripts directly (Makefile alignment is a tracked follow-up).

---

## Org adoption status

As of 2026-09-05 — **7 repos on v1.4.3 pins**, bb-league pending its code-owner approval:

| Repo | Pin | Notes |
|---|---|---|
| repo-template | v1.4.3 | Aggregate CI |
| plot | v1.4.3 | Aggregate CI |
| pia | v1.4.3 | Aggregate CI |
| home | v1.4.3 | Aggregate CI |
| world-monitor-tui | v1.4.3 | Aggregate CI |
| messenger-assistant | v1.4.3 | npm stack |
| mapscii-rust | v1.4.3 | First CI |
| bb-league | v1.3.3 | Pilot; bump pending code-owner approval |
| bot | custom | Custom CI stack stays; documented exception |
| agents | docs-only | No CI (excluded) |
| guidelines | docs-only | No CI (excluded) |
| opencode-headroom-plugin | docs-only | No CI (excluded) |
| test | docs-only | No CI (excluded) |
| spec-forge | docs-only | No CI (excluded) |

The drift-scan flags any repo whose pin lags the latest release. Open PRs across migrated repos can also diverge — see the [stale-PR audit](https://github.com/ostara-labs/devtools/issues/29).

---

## Standard Makefile targets

Every repo that uses devtools gets the same target names:

| Target | What it does | Rust | Elixir | TypeScript | Python |
|---|---|---|---|---|---|
| `make lint` | Lint + format check | `cargo fmt --check` + `cargo clippy -D warnings` | `mix format --check-formatted` + `mix credo` | `biome check` | `ruff check` |
| `make test` | Run tests | `cargo nextest run` | `mix test` | `pnpm run test` | `pytest` |
| `make build` | Build the project | `cargo build --release` | `mix release` | `pnpm run build` | `python -m build` |
| `make ci` | Full CI locally (lint + test) | `make lint && make test` | same | same | same |
| `make format` | Auto-format code | `cargo fmt --all` | `mix format` | `biome format --write` | `ruff format` |
| `make clean` | Clean build artifacts | `cargo clean` | `mix clean` | `rm -rf dist node_modules/.cache` | `rm -rf build dist .pytest_cache` |
| `make hooks` | Set git hooksPath to `.devtools/hooks` | `git config core.hooksPath .devtools/hooks` | same | same | same |
| `make devtools-update` | Bump submodule to latest release tag and stage it | `git -C .devtools fetch --tags && git -C .devtools checkout $(git -C .devtools tag --sort=-v:refname \| head -n1) && git add .devtools` | same | same | same |
| `make help` | List available targets | auto-generated | auto-generated | auto-generated | auto-generated |

The agent (and humans) always know that `make lint` works in any ostara-labs repo.

---

## Trust boundary

This repo is a **trust-boundary repository**. The enforcement mechanisms it
provides (hooks, CI workflows) constrain the agent's behavior. If the agent
could modify this repo without human review, it could weaken the hooks that
enforce its own code quality — a circular dependency that defeats the purpose.

Therefore:
- Any PR to `ostara-labs/devtools` MUST be labeled `requires-human-review`.
- The GitHub org ruleset MUST enforce this (see `workflows/trust-boundary-protect.yml`).
- The agent MUST NOT auto-merge PRs to this repo.
- The path-based enforcement pattern (CODEOWNERS + ruleset) is documented in [`docs/codeowners-trust-boundary.md`](docs/codeowners-trust-boundary.md).

## Dependency updates

The devtools pins, the language ecosystems, what merges without a human, and
what to check when a bump does not arrive: [`docs/dependency-updates.md`](docs/dependency-updates.md).

## Infrastructure state

Where this repository's Pulumi state lives, and why it is not in the bot
project: [`docs/infrastructure-state.md`](docs/infrastructure-state.md).

`infra/rulesets/` creates the GitHub rulesets that govern every repository
here. Its state is separate from the bot project's because an object belongs
in the state of the thing it governs — the rulesets govern the organisation,
not one of its consumers.

## Health check

One issue in this repository says whether the shared tooling works. It is
closed while everything is nominal and reopened with an `@`-mention when
something breaks, so silence means healthy: [`docs/health-check.md`](docs/health-check.md).

It reads the **last run of each monitored workflow, per repository** — never a
failure count, because one dead cron repeating every fifteen minutes reads as
166 problems where the real number is one. Four outcomes are distinguished:
BROKEN, ACTION (awaiting your approval), INFO (an expected failure), and GAP
(the repo does not carry that capability).

## Documentation index

| Document | Owns |
|---|---|
| [`docs/ai-review.md`](docs/ai-review.md) | How a PR is reviewed, and what blocks a merge |
| [`docs/codeowners-trust-boundary.md`](docs/codeowners-trust-boundary.md) | The path-based human-review pattern |
| [`docs/dependency-updates.md`](docs/dependency-updates.md) | How dependency updates reach consumers |
| [`docs/health-check.md`](docs/health-check.md) | The org status marker and its four states |
| [`docs/infrastructure-state.md`](docs/infrastructure-state.md) | Where the rulesets' state lives, what applies them, and why Pulumi does not |
| [`docs/setup-guide.md`](docs/setup-guide.md) | The one-time setup, start to finish |
| [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md) | The Rust toolchain pin and its escape hatch |
