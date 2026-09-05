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
| `workflows/ci.yml` | THE org aggregate CI: one caller line per repo, six required contexts, language jobs auto-detect + succeed vacuously when a stack is absent. Pinned by digest, bumped per release. | `uses: ostara-labs/devtools/.github/workflows/ci.yml@<digest> # vX.Y.Z` |
| `workflows/drift-scan.yml` | Weekly conformance audit of every org repo (submodule gitlink + workflow refs vs latest release); red run + rolling tracking issue on drift. GitHub App auth (preferred) or `ORG_AUDIT_TOKEN` PAT — see [Drift-scan setup](#drift-scan-setup). | Org-level scheduled workflow |
| `default.json` | Org Renovate preset: git-submodules + github-actions managers, automerge scoped to `.devtools` submodule and `ostara-labs/devtools/*` refs. | `extends ["github>ostara-labs/devtools"]` in `renovate.json` |
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

Every repo using the aggregate CI MUST expose exactly these six status contexts to branch rulesets. Absent language stacks succeed vacuously, so a repo with only Rust still passes all six.

| Context | Purpose |
|---|---|
| `gate / core` | Shared checks (secrets scan, file size, commit-msg format) |
| `gate / rust / rust` | Rust stack: fmt, clippy, test, build |
| `gate / elixir / elixir` | Elixir stack: format, credo, test, build |
| `gate / typescript / typescript` | TypeScript stack: biome, test, build |
| `gate / python / python` | Python stack: ruff, pytest, build |
| `gate / gate` | Final aggregation + artifact gate |

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
| `make devtools-update` | Bump submodule to latest release tag | `cd .devtools && git fetch && git checkout $(git describe --tags --abbrev=0)` | same | same | same |
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
