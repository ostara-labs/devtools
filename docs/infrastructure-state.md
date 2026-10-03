# Infrastructure state

Where the Pulumi state for this repository lives, why it is not in the bot
project, and what has to exist before the deployment workflow can run.

## What this repository deploys

`infra/rulesets/` is a Pulumi program that creates **GitHub rulesets** — the
server-side branch, push and merge-queue enforcement applied across every
`ostara-labs` repository.

It touches **no GCP resource**. Its provider is `@pulumi/github`, and the only
credential it needs is a GitHub App with `Organization → Administration:
read and write`.

That matters for the state question below: the program is about organisation
policy, not about any one project's infrastructure.

## Where the state lives

```
gs://ostara-labs-rulesets-state   ← this repository's rulesets
gs://agent-pulumi-state           ← the bot project (bot-infra stack), untouched
```

**The two are separate on purpose.** `agent-pulumi-state` belongs to
`ostara-labs-bot` and holds a single stack, `bot-infra`, which manages that
project's VPC, NAT, VMs, IAM, Artifact Registry, buckets and monitoring.

Sharing one bucket would mean the rulesets governing all eleven repositories
live inside the GCP project of one of them. A change to the bot project would
then be able to affect the policy of every other repository, and a Pulumi
operation on the rulesets would appear in the bot project's state history.
Neither is a property anyone asked for.

The rule of thumb: **an object lives in the state of the thing it governs.**
The rulesets govern the organisation, so they get organisation-level state.

## What exists

Created on 2026-10-03. This is the state the deployment workflow expects:

| Resource | Value |
|---|---|
| Project | `ostara-labs-infra` (number `418359433373`, ACTIVE, billed to `017874-14B8A1-8EFD5D`) |
| State bucket | `gs://ostara-labs-rulesets-state`, `europe-west1`, uniform access |
| KMS key | `projects/ostara-labs-infra/locations/europe-west1/keyRings/pulumi/cryptoKeys/pulumi-stack-encryption` |
| Workload Identity pool | `github-actions` (global), provider `github` |
| Service account | `github-actions-deployer@ostara-labs-infra.iam.gserviceaccount.com` |

The service account holds `storage.admin`, `cloudkms.cryptoKeyEncrypterDecrypter`
and `iam.serviceAccountTokenCreator`, and the pool is bound to it through
`attribute.repository_owner/ostara-labs` — the same rule the bot project uses,
so any repository in the org can assume it from Actions.

### The four repository settings

Two for GCP authentication:

```
GCP_SERVICE_ACCOUNT_EMAIL
  github-actions-deployer@ostara-labs-infra.iam.gserviceaccount.com

GCP_WORKLOAD_IDENTITY_PROVIDER
  projects/418359433373/locations/global/workloadIdentityPools/github-actions/providers/github
```

Two for the GitHub App that creates the rulesets:

```
Variable : RULESETS_APP_ID            = the app's ID
Secret   : RULESETS_APP_PRIVATE_KEY   = the .pem contents
```

### Why a second app, and why different names

`DEVTOOLS_APP_ID` / `DEVTOOLS_APP_PRIVATE_KEY` belong to `devtools-drift-scan`,
which holds **Contents: read-only** and **Issues: read and write** for a weekly
audit that only reads.

The rulesets need **Organization → Administration: read and write**, which can
rewrite the branch protection of every repository in the org. Giving that to
the scanning app would let the app that *reports* on the protections *remove*
them, which is the opposite of a safety property.

So it is a separate app — and its settings are named differently on purpose.
Three workflows already read `DEVTOOLS_APP_ID` (`drift-scan`, `health-check`,
`renovate`); reusing that name for the new app's ID would silently repoint all
three at a different credential, with no diff to review and no error to see.
A distinct name means each app's key is unambiguous and the existing three keep
the app they were written against.

## How it was created

There is **no GCP organization** on this account — `gcloud organizations list`
is empty, and the `ostara-labs` billing account holds only `ostara-labs-bot`
and now `ostara-labs-infra`.

### Step 0 — Create the infrastructure project

**PowerShell 5.1 does not accept `\` as a line continuation.** It passes the
backslash through as a literal argument and then parses the next line as
PowerShell code, so a multi-line command fails like this:

```
ERROR: (gcloud.projects.create) unrecognized arguments: \
Au caractère Ligne:1 : 8
+      --name="ostara-labs infrastructure" \
+        ~
Expression manquante après l'opérateur unaire « -- ».
```

Nothing is created when that happens — the argument never reaches gcloud.

**Run each command on ONE line**, which is the form below. If a command must
wrap, PowerShell's continuation character is a backtick `` ` `` as the LAST
character of the line, with nothing after it — never a backslash.

```powershell
gcloud projects create ostara-labs-infra --name="ostara-labs infrastructure"
```

**Then link billing, as a separate step.** `gcloud projects create` does not
accept a billing option at all — `--billing-account` is rejected with
"unrecognized arguments", and the `--billing-project` it suggests is a
different thing entirely. The account is attached with its own command:

```powershell
gcloud billing projects link ostara-labs-infra --billing-account=017874-14B8A1-8EFD5D
```

Verify the project exists before continuing:

```powershell
gcloud projects describe ostara-labs-infra
```

Then the three pieces the deployment workflow expects:

```powershell
gcloud storage buckets create gs://ostara-labs-rulesets-state --project=ostara-labs-infra --location=europe-west1 --default-storage-class=STANDARD --uniform-bucket-level-access
```

```powershell
gcloud kms keyrings create pulumi --location=europe-west1 --project=ostara-labs-infra
```

```powershell
gcloud kms keys create pulumi-stack-encryption --keyring=pulumi --location=europe-west1 --project=ostara-labs-infra --purpose=encryption
```

The same commands in bash, if you are on Linux or macOS:

```bash
gcloud projects create ostara-labs-infra \
  --name="ostara-labs infrastructure" \
  --billing-account=017874-14B8A1-8EFD5D
```

And a Workload Identity Federation pool so CI authenticates without a key —
the same pattern the bot project uses for `infra-deploy.yml`. The pool's
provider and a service account with `roles/storage.admin` on the bucket go
into the repo secrets `GCP_WORKLOAD_IDENTITY_PROVIDER` and
`GCP_SERVICE_ACCOUNT_EMAIL`.

### Why this is not optional

`.github/workflows/deploy-rulesets.yml` fails if the backend is unreachable,
and it should: a deployment that silently wrote its state somewhere unexpected
is worse than one that did not run. The workflow is the only thing that
applies `infra/rulesets/`, so the failure is visible on the first push that
touches it.

## One rule, two files

Two files describe the org ruleset policy and **must declare the same thing**:

- `infra/rulesets/index.ts` — what this workflow applies
- `scripts/setup-org-rulesets.sh` — what actually created the live rulesets,
  by hand, and still updates `main-protection`

They disagreed for weeks without anyone noticing, because nothing compared
them: the Pulumi file declared a ruleset named `core-branch-protection` that
has never existed, so it governed nothing while the script quietly owned the
live one. **Change one, change the other.**

## Verifying a change locally

The provider types catch option names that do not exist, which is the usual
mistake in this file:

```bash
cd infra/rulesets
npm install
node node_modules/typescript/bin/tsc --noEmit --skipLibCheck \
  --target es2020 --moduleResolution node --module commonjs index.ts
```

`npx typescript@5 tsc` does not work on every machine; the path above uses the
copy npm installed.

Delete `package-lock.json` before committing if the install created one —
`.gitignore` covers `node_modules/` but not the lockfile, and this project has
never had one.
