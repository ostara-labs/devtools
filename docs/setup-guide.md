# Setup Guide — devtools repo + org rulesets deployment

> Step-by-step guide to publish the devtools repo, create the GitHub App,
> apply the org rulesets, and connect the bot repo.
>
> **Audience**: ostara-labs maintainers (human, one-time setup).
> **Prerequisites**: Windows or Linux machine with git and the GitHub CLI. Nothing
> else — the rulesets apply through a workflow, and Terraform runs in CI.

---

## Overview

This guide covers the one-time setup to make the cross-repo enforcement
architecture operational:

```
┌─────────────────────────────────────────────────────────────┐
│  1. Publish devtools repo to GitHub                         │
│  2. Create GitHub App (devtools-rulesets)                   │
│  3. Configure the repository settings (App + GCP)           │
│  4. Apply org rulesets (server-side enforcement)            │
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

# Verify
gh --version
```

```bash
# Linux/Mac (brew)
brew install gh

# Verify
gh --version
```

Terraform is not needed locally either: `terraform-rulesets.yml` runs it in CI,
and its state lives in GCS.

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

## Step 3 — Configure the repository settings

The rulesets apply themselves once four settings exist on the repository. Two
are for the GitHub App, and two are for the GCP authentication the Terraform
job needs.

### 3.1 — The App settings

From the App ID and Installation ID collected in Step 2.4:

```powershell
gh variable set RULESETS_APP_ID --repo ostara-labs/devtools --body "5175699"
gh variable set RULESETS_APP_INSTALLATION_ID --repo ostara-labs/devtools --body "167892034"
```

**Variables, not secrets.** An identifier is not a credential, and putting it
in a secret hides it from the run log — which is where a missing or wrong value
would otherwise be visible.

The private key is a secret:

```powershell
gh secret set RULESETS_APP_PRIVATE_KEY --repo ostara-labs/devtools --body (Get-Content .\devtools-rulesets.*.private-key.pem -Raw)
```

### 3.2 — The GCP settings

Only needed if the Terraform plan is to run. The Workload Identity provider and
the service account are created in Step 0 of
[`infrastructure-state.md`](infrastructure-state.md):

```powershell
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --repo ostara-labs/devtools --body "github-actions-deployer@ostara-labs-infra.iam.gserviceaccount.com"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo ostara-labs/devtools --body "projects/418359433373/locations/global/workloadIdentityPools/github-actions/providers/github"
```

**Secrets, unlike the two App identifiers above.** The distinction is not about
sensitivity — a Workload Identity provider resource name is public — but about
what the workflows read: they consume these through `${{ secrets.… }}`. Setting
them as variables leaves the reference empty, and an empty `service_account`
fails at authentication with a message that names neither.

### 3.3 — Verify

```powershell
gh variable list --repo ostara-labs/devtools
gh secret list --repo ostara-labs/devtools
```

The two `RULESETS_*` identifiers appear as variables; `RULESETS_APP_PRIVATE_KEY`
and the two `GCP_*` values appear as secrets with a name and a date, never a
value.

This is the check that catches a wrong kind: the workflow reads exactly one of
the two stores for each name, and the other returns empty rather than erroring.

---

## Step 4 — Apply the org rulesets

**Nothing to run by hand.** `apply-org-rulesets.yml` fires on any push to
`main` that changes `scripts/setup-org-rulesets.sh` or `infra/rulesets-tf/**`,
and on manual dispatch. It mints a short-lived App installation token, runs the
script, and prints the live rulesets at the end of the run.

```powershell
# To apply without a change to those files:
gh workflow run apply-org-rulesets.yml --repo ostara-labs/devtools --ref main
```

> **Why a script and not Pulumi.** `infra/rulesets/` used to hold a Pulumi
> program that declared the same rulesets. It never applied once — ten runs,
> ten failures — because its credentials sat in the stack state as `--secret`
> values, which needs a KMS at every decrypt, and that combination is broken
> upstream (pulumi/pulumi#11591, open since 2022-12-08, unassigned). The
> program was removed on 2026-10-04; the failure is recorded in
> [devtools#101](https://github.com/ostara-labs/devtools/issues/101).

### 4.1 — See what would change first

The script converges, but it cannot show a plan. Terraform can:

```powershell
gh workflow run terraform-rulesets.yml --repo ostara-labs/devtools --ref main
```

It plans and stops. `No changes. Your infrastructure matches the configuration.`
means the two declarations agree — the check that replaced comparing two files
by hand.

To make Terraform the applier instead, dispatch the same workflow with
`apply=true`. It does not do so by default: the script stays authoritative
until Terraform has applied in production at least once.

### 4.2 — Verify on GitHub

1. Go to https://github.com/organizations/ostara-labs/settings/rules
2. You should see:
   - `main-protection` (branch, all repos)
   - `required-ci-checks` (branch, all repos)
   - `block-secrets-and-binaries` (push, all repos)
   - `merge-queue` (branch) on `devtools` and `repo-template`
   - `trust-boundary-human-review` on `devtools`
   - `trust-boundary-codeowner-review` on `bot`

The App token can read this list; a user token needs `admin:org`:

```powershell
gh api /orgs/ostara-labs/rulesets --jq '.[] | .name + "  " + .target + "  " + .enforcement'
```

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
3. The job (`rust-ci`) should pass
4. Trust-boundary enforcement on the repo is path-based — CODEOWNERS plus a
   repository ruleset requiring code-owner review (see
   [the CODEOWNERS trust-boundary pattern](codeowners-trust-boundary.md)).
   A PR touching a protected path stays blocked until the owner approves.

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
- [ ] CI workflow runs on bot repo PRs (the `rust-ci` job)
- [ ] A PR touching `.github/trust-boundary.yml` is blocked by CODEOWNERS review requirement

---

## Troubleshooting

### The apply fails with `Resource not accessible by integration`

The App is missing the permission, or is not installed on the organisation.
A token minted from an App that was never installed has no rights and no
installation id.

1. Go to https://github.com/organizations/ostara-labs/settings/installations
   and confirm the App is listed. If it is not, install it — creating an App
   does not install it, and this was missed for a day.
2. On the app settings → **Organization permissions**, verify
   **Administration** is **Read and write**.
3. Confirm both settings exist, not just the secret:
   ```powershell
   gh variable list --repo ostara-labs/devtools | Select-String RULESETS
   ```
   `RULESETS_APP_INSTALLATION_ID` missing is the usual cause; a missing repo
   variable expands to the empty string, which is stored without complaint and
   only fails later with a message that names nothing.

### The apply fails with `cannot list rulesets on ostara-labs`

The token cannot read the org's rulesets. Either the App lost its
`Administration` permission, or a user token is being used without
`admin:org`. The script reports this explicitly rather than falling through to
a confusing `409 Conflict` on the create path.

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

1. Go to the app settings → Private keys → **Generate a private key**
2. Replace the repository secret:
   ```powershell
   gh secret set RULESETS_APP_PRIVATE_KEY --repo ostara-labs/devtools --body (Get-Content .\new-key.private-key.pem -Raw)
   ```
3. **Verify before deleting the old key.** Dispatch the apply and read its end:
   ```powershell
   gh workflow run apply-org-rulesets.yml --repo ostara-labs/devtools --ref main
   ```
   A passing run means the new key works.
4. Only then delete the old key in the App settings.

The order matters: deleting first leaves no way back if the new key is wrong.

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
