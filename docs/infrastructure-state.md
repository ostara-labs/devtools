# Infrastructure state

Where the rulesets' state lives, what applies them, and what has to exist
before either tool can run.

## What this repository deploys

The org rulesets — server-side branch, push and merge-queue enforcement applied
across every `ostara-labs` repository. Nothing here touches a GCP resource: the
provider is `integrations/github`, and the only credential involved is a GitHub
App with `Organization → Administration: read and write`.

## Two tools apply the same policy

| | `scripts/setup-org-rulesets.sh` | `infra/rulesets-tf/` |
|---|---|---|
| Applies | ✅ on push to `main` | ✅ on dispatch only |
| Plan before applying | ❌ | ✅ |
| State | none | GCS, unencrypted |
| Detects hand-edits | ❌ | ✅ |
| Adopted the live rulesets | created them | `terraform import` |

**The script is authoritative.** It has run in production; Terraform was added
later and starts in plan-only mode so the two can be compared. **A plan against
the live org reports `No changes`,** which is the mechanical proof that both
declare the same policy — the rule carried since the #86 divergence, now
checked by a tool instead of by reading two files.

### Why there is no Pulumi program

`infra/rulesets/` held one and **it was removed on 2026-10-04**, after never
applying once — ten runs, ten failures. Its credentials lived in the stack
config as `--secret` values, which puts an encrypted blob in the state and
requires a KMS at every decrypt. On a GCS backend with a `gcpkms` secrets
provider that combination is broken upstream:

- **[pulumi/pulumi#11591](https://github.com/pulumi/pulumi/issues/11591)** —
  *"remote gcp bucket and gcp kms for state"*, the exact setup here. Open since
  **2022-12-08**, unassigned, last activity 2026-09-21.
- **[pulumi/pulumi#6597](https://github.com/pulumi/pulumi/issues/6597)** — the
  error is known to be misleading: *"it simply throws an error that Passphrase
  has not been set."*

Everything measurable was ruled out before concluding this: state corruption,
creation environment, credentials, permissions, key version, and the CLI
version — pinning to the version that works locally reproduced the failure
exactly. The failure is tracked in [#101](https://github.com/ostara-labs/devtools/issues/101),
and the whole episode is why the rule below is "check with a plan" rather than
"read both files carefully".

**The Terraform program has no such dependency.** The `github` provider reads
its App credentials from the **environment** (`GITHUB_APP_ID`,
`GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PEM_FILE`), so nothing secret enters
the state, there is no decryption step, and the state bucket needs no KMS.

## Where the state lives

```
gs://ostara-labs-rulesets-state   ← the org rulesets
gs://agent-pulumi-state           ← the bot project (bot-infra stack), untouched
```

The Terraform state lives in the same bucket under the prefix
`terraform/rulesets`, unencrypted.

**The two buckets are separate on purpose.** `agent-pulumi-state` belongs to
`ostara-labs-bot` and holds a single stack, `bot-infra`, which manages that
project's VPC, NAT, VMs, IAM, Artifact Registry, buckets and monitoring.

Sharing one bucket would mean the rulesets governing all eleven repositories
live inside the GCP project of one of them. A change to the bot project could
then affect the policy of every other repository.

The rule of thumb: **an object lives in the state of the thing it governs.**
The rulesets govern the organisation, so they get organisation-level state.

## What exists

Created on 2026-10-03.

| Resource | Value |
|---|---|
| Project | `ostara-labs-infra` (number `418359433373`, ACTIVE, billed to `017874-14B8A1-8EFD5D`) |
| State bucket | `gs://ostara-labs-rulesets-state`, `europe-west1`, uniform access |
| KMS key | `projects/ostara-labs-infra/locations/europe-west1/keyRings/pulumi/cryptoKeys/pulumi-stack-encryption` — **used by the Pulumi program only; Terraform's state needs no encryption** |
| Workload Identity pool | `github-actions` (global), provider `github` |
| Service account | `github-actions-deployer@ostara-labs-infra.iam.gserviceaccount.com` |

The service account holds `storage.admin`, `cloudkms.cryptoKeyEncrypterDecrypter`
and `iam.serviceAccountTokenCreator`, and the pool is bound to it through
`attribute.repository_owner/ostara-labs`.

### The repository settings

Two for GCP authentication:

```
GCP_SERVICE_ACCOUNT_EMAIL
  github-actions-deployer@ostara-labs-infra.iam.gserviceaccount.com

GCP_WORKLOAD_IDENTITY_PROVIDER
  projects/418359433373/locations/global/workloadIdentityPools/github-actions/providers/github
```

Two for the GitHub App, plus its installation:

```
Variable : RULESETS_APP_ID               = 5175699
Variable : RULESETS_APP_INSTALLATION_ID  = 167892034
Secret   : RULESETS_APP_PRIVATE_KEY      = the .pem contents
```

**An App that is not installed on the organisation has no installation and no
rights over its rulesets.** Installing it is step 2.3 of the setup guide and
was missed for a day: the provider's schema requires `installationId`, and
`pulumi config set` stores an empty value without complaining, so the failure
surfaces much later as a confusing one.

### Why a second app, and why different names

`DEVTOOLS_APP_ID` / `DEVTOOLS_APP_PRIVATE_KEY` belong to `devtools-drift-scan`,
which holds **Contents: read-only** and **Issues: read and write** for a weekly
audit that only reads.

The rulesets need **Organization → Administration: read and write**, which can
rewrite the branch protection of every repository in the org. Giving that to
the scanning app would let the app that *reports* on the protections *remove*
them — the opposite of a safety property.

The names are distinct because three workflows already read `DEVTOOLS_APP_ID`
(`drift-scan`, `health-check`, `renovate`); reusing it would silently repoint
all three at a different credential, with no diff to review and no error to see.

## How the automation authenticates

`apply-org-rulesets.yml` and `terraform-rulesets.yml` mint a **short-lived App
installation token** at run time with `actions/create-github-app-token`:

```yaml
- uses: actions/create-github-app-token@<digest> # v3.2.0
  with:
    app-id: ${{ vars.RULESETS_APP_ID }}
    private-key: ${{ secrets.RULESETS_APP_PRIVATE_KEY }}
    owner: ${{ github.repository_owner }}
```

**No `admin:org` scope is involved anywhere.** The rulesets API requires
"Administration organization permissions (write)", which the App carries
exactly; the token is minted per run and expires, and there is nothing to
rotate. A user PAT with `admin:org` also works, but only to run the script by
hand.

> `app-id` is deprecated in favour of `client-id` upstream. The three
> pre-existing workflows use the same input, so migrating them means one pass
> over four files.

## How the rulesets were applied

Not by Pulumi. Applied by `scripts/setup-org-rulesets.sh` on 2026-10-04, run by
`apply-org-rulesets.yml` under the App token above, then adopted by Terraform:

| Ruleset | Target | Live id |
|---|---|---|
| `main-protection` | branch | 21254080 |
| `required-ci-checks` | branch | 23150888 |
| `block-secrets-and-binaries` | push | 24470458 |

`block-secrets-and-binaries` had **never existed** before that run. Nothing
blocked secrets server-side: `gitleaks` runs in CI and in the hooks, but
`--no-verify` defeats the hooks and a direct push never runs CI.

## How it was created

There is **no GCP organization** on this account — `gcloud organizations list`
is empty, and the billing account holds only `ostara-labs-bot` and now
`ostara-labs-infra`.

### Step 0 — Create the infrastructure project

**PowerShell 5.1 does not accept `\` as a line continuation.** It passes the
backslash through as a literal argument and then parses the next line as
PowerShell code:

```
ERROR: (gcloud.projects.create) unrecognized arguments: \
```

Nothing is created when that happens. **Run each command on ONE line.** If a
command must wrap, PowerShell's continuation character is a backtick as the
LAST character of the line — never a backslash.

```powershell
gcloud projects create ostara-labs-infra --name="ostara-labs infrastructure"
```

**Then link billing, as a separate step.** `gcloud projects create` accepts no
billing option at all — `--billing-account` is rejected with "unrecognized
arguments", and the `--billing-project` it suggests is a different thing.

```powershell
gcloud billing projects link ostara-labs-infra --billing-account=017874-14B8A1-8EFD5D
```

Then the pieces the workflows expect:

```powershell
gcloud storage buckets create gs://ostara-labs-rulesets-state --project=ostara-labs-infra --location=europe-west1 --default-storage-class=STANDARD --uniform-bucket-level-access
```

```powershell
gcloud kms keyrings create pulumi --location=europe-west1 --project=ostara-labs-infra
```

```powershell
gcloud kms keys create pulumi-stack-encryption --keyring=pulumi --location=europe-west1 --project=ostara-labs-infra --purpose=encryption
```

A Workload Identity Federation pool lets CI authenticate without a key, the
same pattern the bot project uses for `infra-deploy.yml`.

## The two files that declare the same policy

**Change one, change the other — and check with a plan.**

- `scripts/setup-org-rulesets.sh` — applies it, and created the live rulesets
- `infra/rulesets-tf/main.tf` — declares it with a state, and detects hand-edits

They disagreed for weeks without anyone noticing, because nothing compared
them: the Pulumi file declared a ruleset named `core-branch-protection` that
has never existed, so it governed nothing while the script quietly owned the
live one.

**The check is now mechanical:**

```
Actions → Terraform Rulesets → Run workflow
```

A plan that reports `No changes` means the two agree. Anything else is drift.

## Verifying a Terraform change locally

```bash
cd infra/rulesets-tf
terraform fmt -check
terraform init -backend=false
terraform validate
```

`-backend=false` skips the GCS backend, so this needs no credentials. A real
`plan` requires the App key, which is a repository secret — that runs in CI.

## Verifying a shell change locally

The script needs a token that can read the org's rulesets, which a developer
token only has with `admin:org`. To check it without applying anything:

```bash
bash -n scripts/setup-org-rulesets.sh          # syntax
```

The workflow is the only place the real token exists, and it prints the live
rulesets at the end of every run.
