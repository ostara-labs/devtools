# devtools — Shared development tooling for ostara-labs repos

> **Trust-boundary repo.** Any PR to this repository requires human review (HITL).
> Changes here affect enforcement across ALL repos in the organization.
> The agent MUST NOT auto-merge PRs to this repo.

Shared git hooks, Makefiles, CI workflows, and lint configs for all
`ostara-labs` repositories. Ensures consistent code quality enforcement
regardless of which repo the agent (or a human) is working in.

---

## What this repo provides

| Component | What it enforces | Used via |
|---|---|---|
| `hooks/` | Git hooks: pre-commit (secrets, file size, lint patterns), pre-push (clippy, tests, miri), commit-msg (format) | `git config core.hooksPath .devtools/hooks` |
| `makefiles/` | Standard targets: `make lint`, `make test`, `make build`, `make ci`, `make format` | `include .devtools/makefiles/Makefile.<lang>` |
| `workflows/` | Reusable GitHub Actions workflows: rust-ci, elixir-ci, ts-ci, pr-classify | `uses: ostara-labs/devtools/.github/workflows/<name>.yml@v1` |
| `configs/` | Shared lint configs: clippy.toml, rustfmt.toml, biome.json | Symlink or copy into repo root |
| `scripts/install.sh` | Bootstrap: sets hooksPath, creates Makefile stub | `curl -sSL .../install.sh \| bash` or run from submodule |

---

## How a repo consumes devtools

### Option A: Git submodule (recommended — versioned, explicit)

```bash
# In the consuming repo:
git submodule add https://github.com/ostara-labs/devtools .devtools
git commit -m "chore: add devtools submodule for cross-repo enforcement"

# Configure git hooks
git config core.hooksPath .devtools/hooks

# Create a minimal Makefile (see makefiles/README.md for templates)
# Or use the install script:
bash .devtools/scripts/install.sh
```

Updates are explicit and visible in diffs:
```bash
cd .devtools
git checkout v1.2  # pin to a specific version
cd ..
git add .devtools
git commit -m "chore: bump devtools to v1.2"
```

### Option B: Bootstrap script (no submodule)

```bash
# From the consuming repo root:
curl -sSL https://raw.githubusercontent.com/ostara-labs/devtools/v1/scripts/install.sh | bash
```

This downloads hooks, Makefile templates, and configs into `.devtools/`
(non-versioned, re-run to update). Simpler but less explicit than a submodule.

---

## Supported languages

| Language | Detected by | Hook checks | Makefile | CI workflow |
|---|---|---|---|---|
| Rust | `Cargo.toml` | unwrap/expect, println, unsafe, 250 LOC, cargo fmt | `Makefile.rust` | `rust-ci.yml` |
| Elixir | `mix.exs` | IO.puts in production, mix format --check, 250 LOC | `Makefile.elixir` | `elixir-ci.yml` |
| TypeScript | `package.json` | console.log in production, biome check, 250 LOC | `Makefile.typescript` | `ts-ci.yml` |

Hooks auto-detect the language — no configuration needed. A repo with both
`Cargo.toml` and `package.json` runs checks for both.

---

## Standard Makefile targets

Every repo that uses devtools gets the same target names:

| Target | What it does | Rust | Elixir | TypeScript |
|---|---|---|---|---|
| `make lint` | Lint + format check | `cargo fmt --check` + `cargo clippy -D warnings` | `mix format --check-formatted` + `mix credo` | `biome check` |
| `make test` | Run tests | `cargo nextest run` | `mix test` | `bun test` |
| `make build` | Build the project | `cargo build --release` | `mix release` | `bun run build` |
| `make ci` | Full CI locally (lint + test) | `make lint && make test` | same | same |
| `make format` | Auto-format code | `cargo fmt --all` | `mix format` | `biome format --write` |
| `make clean` | Clean build artifacts | `cargo clean` | `mix clean` | `rm -rf dist node_modules/.cache` |
| `make help` | List available targets | auto-generated | auto-generated | auto-generated |

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
