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

## What must exist first

There is **no GCP organization** on this account — `gcloud organizations list`
is empty, and the `ostara-labs` billing account has exactly one project,
`ostara-labs-bot`. The state bucket therefore cannot be created until a project
exists to hold it.

### Step 0 — Create the infrastructure project

Run these from **PowerShell on Windows**. One command per line: the `\`
continuation is bash-only, and PowerShell rejects it with
"Expression manquante après l'opérateur unaire".

```powershell
gcloud projects create ostara-labs-infra --name="ostara-labs infrastructure" --billing-account=017874-14B8A1-8EFD5D
```

Then the three pieces the deployment workflow expects:

```powershell
gcloud storage buckets create gs://ostara-labs-rulesets-state --project=ostara-labs-infra --location=europe-west1 --default-storage-class=STANDARD --uniform-bucket-level-access

gcloud kms keyrings create pulumi --location=europe-west1 --project=ostara-labs-infra

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
