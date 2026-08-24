# Setup Guide — devtools repo + org rulesets deployment

> Step-by-step guide to publish the devtools repo, create the GitHub App,
> deploy the org rulesets via Pulumi, and connect the bot repo.
>
> **Audience**: ostara-labs maintainers (human, one-time setup).
> **Prerequisites**: Windows or Linux machine with git, GitHub CLI, Pulumi installed.

---

## Overview

This guide covers the one-time setup to make the cross-repo enforcement
architecture operational:

```
┌─────────────────────────────────────────────────────────────┐
│  1. Publish devtools repo to GitHub                         │
│  2. Create GitHub App (ostara-labs-pulumi)                  │
│  3. Configure Pulumi with App credentials                   │
│  4. Deploy org rulesets (server-side enforcement)           │
│  5. Connect bot repo (submodule + hooks + CI workflow)      │
└─────────────────────────────────────────────────────────────┘
```

After this guide, the full enforcement stack is active:

| Layer | Where | Bypassable? |
|---|---|---|
| Git hooks (pre-commit, pre-push, commit-msg) | Local | `--no-verify` (visible in reflog) |
| CI pipeline (reusable workflows) | GitHub Actions | No |
| PR classification (trust-boundary) | CI job | No (config is self-protecting) |
| **Org rulesets (this guide)** | **GitHub server-side** | **No — even org admins cannot bypass** |

---

## Prerequisites

Install the tools below if not already present:

```powershell
# Windows (winget)
winget install GitHub.cli
winget install Pulumi.Pulumi

# Verify
gh --version
pulumi version
```

```bash
# Linux/Mac (brew)
brew install gh pulumi

# Verify
gh --version
pulumi version
```

Authenticate with GitHub CLI:

```powershell
gh auth login
# Choose: GitHub.com → HTTPS → Login with web browser
```

---

## Step 1 — Publish the devtools repo

The devtools repo is currently a local git repo with one commit. Push it to
GitHub as a **private** repo (it is trust-boundary — it contains enforcement
mechanisms).

```powershell
cd C:\Users\Robert\repositories\devtools

# Create the repo on GitHub and push
gh repo create ostara-labs/devtools --private --source=. --remote=origin --push

# Verify
gh repo view ostara-labs/devtools
```

If you prefer to create the repo manually:
1. Go to https://github.com/organizations/ostara-labs/repositories/new
2. Name: `devtools`, Visibility: **Private**
3. Do NOT initialize with README (the local commit already exists)
4. Then:
   ```powershell
   cd C:\Users\Robert\repositories\devtools
   git remote add origin git@github.com:ostara-labs/devtools.git
   git push -u origin main
   ```

---

## Step 2 — Create the GitHub App

The GitHub App authenticates Pulumi to manage org rulesets. It is more secure
than a PAT: no expiration, scoped permissions, auditable in GitHub logs.

### 2.1 — Create the app

Go to: **https://github.com/organizations/ostara-labs/settings/apps** → **New GitHub App**

Fill in:

| Field | Value |
|---|---|
| **GitHub App name** | `ostara-labs-pulumi` |
| **Homepage URL** | `https://github.com/ostara-labs/devtools` |
| **Webhook → Active** | Uncheck (not needed for this use case) |
| **Repository permissions** | Leave all on "No access" (we use org permissions) |
| **Organization permissions → Administration** | **Read and write** (required for org rulesets) |
| **Where can this GitHub App be installed?** | "Only on this account" |

→ Click **Create GitHub App**

### 2.2 — Generate the private key

On the app's settings page (you should be redirected there after creation):

1. Scroll down to **Private keys**
2. Click **Generate a private key**
3. A `.pem` file downloads automatically (e.g. `ostara-labs-pulumi.private-key.pem`)

> ⚠️ This key is generated **only once**. Store it securely. If lost, you must
> regenerate it (which invalidates the previous key).

### 2.3 — Install the app on the org

After creating the app, GitHub prompts you to install it:

1. Click **Install App** on the app's settings page
2. Select **ostara-labs** (your org)
3. Choose **All repositories** (the rulesets apply to all repos)
4. Click **Install**

### 2.4 — Collect the App ID and Installation ID

You need two numbers for Pulumi configuration:

**App ID**:
- On the app's settings page → "General" section → **App ID** (e.g. `123456`)

**Installation ID**:
- Go to: https://github.com/organizations/ostara-labs/settings/installations
- Click **Configure** next to `ostara-labs-pulumi`
- Look at the URL in your browser: `github.com/organizations/ostara-labs/settings/installations/XXXXX`
- **XXXXX is the Installation ID** (e.g. `78910`)

Write down both numbers — you need them in Step 3.

---

## Step 3 — Configure Pulumi

### 3.1 — Install npm dependencies

```powershell
cd C:\Users\Robert\repositories\devtools\infra\rulesets
npm install
```

### 3.2 — Log in to Pulumi backend

If you use Pulumi Cloud:
```powershell
pulumi login
```

If you use GCS backend (recommended for ostara-labs):
```powershell
pulumi login gs://ostara-labs-pulumi-state
```

### 3.3 — Create the stack

```powershell
pulumi stack init ostara-labs/devtools-rulesets
```

### 3.4 — Set the GitHub App credentials as secrets

Replace the placeholder values with your actual numbers and PEM file path:

```powershell
# App ID (from Step 2.4)
pulumi config set github:appAuth.id 123456 --secret

# Installation ID (from Step 2.4)
pulumi config set github:appAuth.installationId 78910 --secret

# Private key PEM content
pulumi config set github:appAuth.pemFile "$(Get-Content ostara-labs-pulumi.private-key.pem -Raw)" --secret

# Org owner (mandatory with appAuth)
pulumi config set github:owner ostara-labs
```

On Linux/Mac:
```bash
pulumi config set github:appAuth.pemFile "$(cat ostara-labs-pulumi.private-key.pem)" --secret
```

> All three values are stored encrypted in Pulumi state via `--secret`.
> They never appear in plaintext in the code or in `pulumi config` output.

### 3.5 — Verify the configuration

```powershell
# Should show the keys (but NOT the secret values)
pulumi config

# Expected output:
# github:appAuth.id               [secret]
# github:appAuth.installationId   [secret]
# github:appAuth.pemFile          [secret]
# github:owner                    ostara-labs
```

---

## Step 4 — Deploy the org rulesets

### 4.1 — Preview

```powershell
pulumi preview
```

This shows what Pulumi will create without making changes. You should see:
- 3 resources to create: `core-branch-protection`, `block-secrets-and-binaries`, `devtools-trust-boundary`
- No resources to delete or replace

Review the plan. If it looks correct, proceed.

### 4.2 — Deploy

```powershell
pulumi up
```

Pulumi asks for confirmation. Type `yes` to deploy.

Expected result:
```
Resources:
    + 3 created

Duration: 15s
```

### 4.3 — Verify on GitHub

1. Go to: https://github.com/organizations/ostara-labs/settings/rules
2. You should see 3 rulesets:
   - `core-branch-protection` (branch, all repos)
   - `block-secrets-and-binaries` (push, all repos)
   - `devtools-trust-boundary` (branch, devtools repo only)

3. Click each one to verify the rules match the code in `index.ts`.

### 4.4 — Test the rulesets

Test that push protection works:
```powershell
# In any ostara-labs repo, try to commit a .env file
echo "SECRET=abc" > .env
git add .env
git commit -m "test: should be blocked by push ruleset"
git push
# Expected: push REJECTED by GitHub with "blocked by push protection ruleset"
```

Test that direct pushes to main are blocked:
```powershell
# In any ostara-labs repo, try to push directly to main (without a PR)
git checkout main
echo "test" > test.txt
git add test.txt
git commit -m "test: should require a PR"
git push origin main
# Expected: push REJECTED — "Changes must be made through a pull request"
```

Clean up the test files:
```powershell
git reset --hard HEAD~1
rm .env test.txt
```

---

## Step 5 — Connect the bot repo

### 5.1 — Push the bot repo (if not already done)

```powershell
cd C:\Users\Robert\repositories\bot
git push origin main
```

### 5.2 — Add devtools as a submodule

```powershell
cd C:\Users\Robert\repositories\bot

# Add the submodule
git submodule add https://github.com/ostara-labs/devtools .devtools

# Switch hooks from local copy to shared submodule
git config core.hooksPath .devtools/hooks

# Run the install script (creates Makefile stub, copies lint configs)
powershell -ExecutionPolicy Bypass -File .devtools\scripts\install.ps1
```

On Linux/Mac:
```bash
bash .devtools/scripts/install.sh
```

### 5.3 — Commit the submodule

```powershell
git add .devtools
git add Makefile        # if install script created/updated it
git add clippy.toml     # if copied
git add rustfmt.toml    # if copied

git commit -m "chore: add devtools submodule for cross-repo enforcement"
git push
```

### 5.4 — Create the CI workflow in the bot repo

Create `.github/workflows/ci.yml` in the bot repo:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  # Rust CI — lint + test + miri
  rust-ci:
    uses: ostara-labs/devtools/.github/workflows/rust-ci.yml@main
    secrets: inherit

  # PR classification — trust-boundary check
  pr-classify:
    uses: ostara-labs/devtools/.github/workflows/pr-classify.yml@main
    secrets: inherit
```

> Once the setup is stable, pin the workflow to a commit SHA instead of `@main`:
> ```yaml
> uses: ostara-labs/devtools/.github/workflows/rust-ci.yml@<commit-sha>
> ```
> This prevents breaking changes in devtools/main from affecting CI without
> an explicit submodule bump.

```powershell
git add .github/workflows/ci.yml
git commit -m "ci: consume reusable workflows from devtools repo"
git push
```

### 5.5 — Verify the CI runs

1. Go to: https://github.com/ostara-labs/bot/actions
2. The latest push should trigger the `CI` workflow
3. Both jobs (`rust-ci`, `pr-classify`) should pass
4. Open a test PR that touches a non-trust-boundary file → `pr-classify` should
   classify it as evolvable (no `requires-human-review` label)
5. Open a test PR that touches `src/core/laws.rs` (create the file first with
   a placeholder) → `pr-classify` should apply the `requires-human-review` label

---

## Verification checklist

After completing all steps, verify:

- [ ] devtools repo is on GitHub: https://github.com/ostara-labs/devtools (private)
- [ ] GitHub App `ostara-labs-pulumi` exists and is installed on the org
- [ ] 3 org rulesets visible at https://github.com/organizations/ostara-labs/settings/rules
- [ ] Direct pushes to main are blocked on all repos
- [ ] Pushing a `.env` file is blocked by push protection
- [ ] bot repo has `.devtools` submodule
- [ ] `git config core.hooksPath` in bot repo returns `.devtools/hooks`
- [ ] `make help` in bot repo lists standard targets
- [ ] CI workflow runs on bot repo PRs (both `rust-ci` and `pr-classify`)
- [ ] A PR touching `.github/trust-boundary.yml` gets `requires-human-review` label

---

## Troubleshooting

### `pulumi preview` fails with `403 Resource not accessible by integration`

The GitHub App does not have the right permissions, or the `owner` config is
missing.

Fix:
```powershell
# Verify owner is set
pulumi config get github:owner
# Should print: ostara-labs

# If empty:
pulumi config set github:owner ostara-labs
```

If owner is correct, check the app's org permissions:
1. Go to the app settings → Organization permissions
2. Verify **Administration** is set to **Read and write**

### `pulumi config set github:appAuth.pemFile` fails on Windows

The PEM file content may have encoding issues. Try:

```powershell
# Read with explicit UTF-8
$content = [System.IO.File]::ReadAllText("ostara-labs-pulumi.private-key.pem", [System.Text.Encoding]::UTF8)
pulumi config set github:appAuth.pemFile $content --secret
```

### Git hooks not running after submodule setup

```powershell
# Verify hooksPath
git config core.hooksPath
# Should print: .devtools/hooks

# If empty, set it manually
git config core.hooksPath .devtools/hooks

# Test with a dry-run commit
git commit --dry-run
```

### CI workflow fails with `uses: ostara-labs/devtools/.github/workflows/rust-ci.yml@main — not found`

The devtools repo must be pushed to GitHub before the bot repo can reference
its workflows. Verify Step 1 is complete.

### `make` not found on Windows

Install make:
```powershell
winget install GnuWin32.Make
# Or via chocolatey:
choco install make
```

Or use the targets directly without make:
```powershell
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo nextest run
```

---

## Maintenance

### Renewing the GitHub App private key

The private key does not expire, but if it is compromised:

1. Go to the app settings → Private keys → **Generate a private key** (this
   invalidates the old key)
2. Update Pulumi config:
   ```powershell
   pulumi config set github:appAuth.pemFile "$(Get-Content new-key.pem -Raw)" --secret
   ```
3. Run `pulumi up` to verify the new key works

### Adding a new repo to the org

New repos automatically get the org-level rulesets (branch protection + push
protection) — no action needed.

To add devtools enforcement (hooks, Makefile, configs):
```powershell
# In the new repo:
git submodule add https://github.com/ostara-labs/devtools .devtools
git config core.hooksPath .devtools/hooks
powershell -ExecutionPolicy Bypass -File .devtools\scripts\install.ps1
git add .devtools Makefile clippy.toml rustfmt.toml
git commit -m "chore: add devtools submodule"
```

To add CI, create `.github/workflows/ci.yml` referencing the reusable workflows
(see Step 5.4).

---

## Flat-layout repositories

The language CI workflows assume code lives in a stack subdirectory
(`rust/`, `typescript/`, `elixir/`, `python/`). Repositories with code at the
repository root can pass an optional `stack-dir` input instead:

```yaml
rust-ci:
  uses: ostara-labs/devtools/.github/workflows/rust-ci.yml@v1.2.0
  with:
    stack-dir: "."
```

The input defaults to each workflow's conventional directory (`rust`,
`typescript`, `elixir`, `python`), so existing callers that pass no inputs
keep their current behavior unchanged.

---

## Dispatch after automerge

GitHub never triggers workflows from pushes made with `GITHUB_TOKEN` (the
anti-recursion rule). A PR auto-merged by automation therefore starts **no**
build or deploy on the target branch — the merge succeeds while nothing runs.
Place this composite action immediately **after** the merge step in whatever
workflow performs automerges:

```yaml
- uses: ostara-labs/devtools/.github/actions/automerge-dispatch@<full-sha> # v1.2.x
  with:
    workflow: deploy.yml   # target workflow FILE name
    ref: main              # default: main
  env:
    GH_TOKEN: ${{ secrets.AUTOMERGE_TOKEN }}   # needs actions:write
```

It retries the dispatch (default 3 attempts, hard-fails on exhaustion) and
verifies a `workflow_dispatch` run appeared for the ref (warn-only). Extracted
from bot's pr-classify.yml fix for missed deploys (bot#38).
