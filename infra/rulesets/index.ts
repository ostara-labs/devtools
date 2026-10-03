// infra/rulesets/index.ts — GitHub Organization Rulesets for ostara-labs
//
// Server-side enforcement that CANNOT be bypassed by the agent (unlike git hooks).
// This is the strongest enforcement layer — it runs on GitHub's servers, not locally.
//
// Applies to ALL repos in the ostara-labs org:
//   - Require PRs (no direct pushes to main)
//   - Required status checks before merge
//   - Block force pushes and branch deletion
//   - Block secrets and binaries in pushes (push ruleset)
//   - Commit message pattern enforcement (conventional commits)
//   - Trust-boundary PRs require human review (via required reviewers)
//
// TWO FILES DECLARE THE SAME ORG POLICY, AND THEY MUST AGREE:
//   - this file
//   - scripts/setup-org-rulesets.sh, which is what actually created and still
//     updates `main-protection` on GitHub
//
// They disagreed for weeks without anyone noticing, because nothing compared
// them: this file declared a ruleset named "core-branch-protection" that has
// never existed, so it governed nothing while the script quietly owned the
// live one. Change one, change the other.
//
// Authentication via GitHub App (not PAT).
// The App ID, Installation ID, and PEM private key are stored as Pulumi secrets:
//   pulumi config set github:appAuth.id <APP_ID> --secret
//   pulumi config set github:appAuth.installationId <INSTALLATION_ID> --secret
//   pulumi config set github:appAuth.pemFile <PEM_CONTENT> --secret
//   pulumi config set github:owner ostara-labs
//
// Why GitHub App instead of PAT:
//   - No expiration (PAT expires every 90 days)
//   - Scoped permissions (only org:administration write)
//   - Auditable in GitHub audit logs (actions appear as "ostara-labs-pulumi", not "ostara-labs")
//   - The agent cannot steal the token (installation token is generated per-execution)
//
// The GitHub App must be installed on the ostara-labs org with:
//   Organization permissions → Administration → Read and write

import * as github from "@pulumi/github";
import * as pulumi from "@pulumi/pulumi";

const config = new pulumi.Config();
// Provider config is read automatically by the @pulumi/github provider.
// No explicit token retrieval needed here — the provider handles it.

// --- Org-level branch protection (all repos) ---
const branchProtection = new github.OrganizationRuleset("main-protection", {
    name: "main-protection",
    target: "branch",
    enforcement: "active",
    conditions: {
        refName: {
            includes: ["~DEFAULT_BRANCH"],
            excludes: [],
        },
        repositoryName: {
            includes: ["~ALL"],
            excludes: [],
        },
    },
    bypassActors: [],  // No bypass — even org admins cannot bypass
    rules: {
        deletion: true,
        nonFastForward: true,
        // The approving-review count stays at 0 so bot keeps its autonomy:
        // its pr-classify workflow merges an `evolvable` PR itself, and a
        // workflow token cannot supply a human approval, so a count of 1
        // would make the bot wait for a review that never arrives and block
        // its own mutation path.
        pullRequest: {
            requiredApprovingReviewCount: 0,
            requireCodeOwnerReview: true,
            dismissStaleReviewsOnPush: true,
            requireLastPushApproval: false,
            // An unresolved review thread blocks the merge, on every repo.
            requiredReviewThreadResolution: true,
        },
        // `gate` is the context the aggregate CI actually emits. An earlier
        // version of this file required `lint`, `test` and `PR Classify`;
        // none of those exist here, and `PR Classify` was deleted from bot as
        // dead config, so they would have blocked every merge in the org.
        requiredStatusChecks: {
            strictRequiredStatusChecksPolicy: false,
            requiredChecks: [
                { context: "gate" },
            ],
        },
    },
});

// --- Org-level required status checks ---
// Declared here because it was LIVE and declared nowhere: it was created by
// hand in the GitHub UI, so no file described the checks every repository
// enforces. Same conditions as main-protection.
//
// Both contexts are emitted by the org's pipeline: `ci / gate` is the
// aggregate gate, `merge-gate` the PR-pipeline verdict. A context no workflow
// reports blocks every merge, so these are checked against the workflows
// rather than assumed.
const requiredCiChecks = new github.OrganizationRuleset("required-ci-checks", {
    name: "required-ci-checks",
    target: "branch",
    enforcement: "active",
    conditions: {
        refName: {
            includes: ["~DEFAULT_BRANCH"],
            excludes: [],
        },
        repositoryName: {
            includes: ["~ALL"],
            excludes: [],
        },
    },
    rules: {
        requiredStatusChecks: {
            strictRequiredStatusChecksPolicy: false,
            requiredChecks: [
                { context: "ci / gate" },
                { context: "merge-gate" },
            ],
        },
    },
});

// --- Merge queue, per repository ---
// A merge queue cannot be declared at the organization level: the provider
// exposes `mergeQueue` only on RepositoryRulesetRules. It is declared per
// repository, which is also how it exists today — devtools and repo-template,
// created by hand. Adding a third repository means adding a third entry here,
// deliberately, rather than widening a condition that would switch it on
// everywhere at once.
const mergeQueueRepos = ["devtools", "repo-template"];

const mergeQueues = mergeQueueRepos.map(
    (repo) =>
        new github.RepositoryRuleset(`merge-queue-${repo}`, {
            name: "merge-queue",
            repository: repo,
            target: "branch",
            enforcement: "active",
            conditions: {
                refName: {
                    includes: ["~DEFAULT_BRANCH"],
                    excludes: [],
                },
            },
            rules: {
                // ALLGREEN requires every PR in a group to pass all required
                // checks, not only the head of the group — the stricter of the
                // two strategies, which is what a shared tooling repo wants.
                mergeQueue: {
                    mergeMethod: "SQUASH",
                    maxEntriesToBuild: 5,
                    maxEntriesToMerge: 5,
                    groupingStrategy: "ALLGREEN",
                    // The aggregate CI includes an ai-review job that runs for
                    // minutes; this is the ceiling before an unanswered check
                    // is treated as failed.
                    checkResponseTimeoutMinutes: 60,
                },
            },
        }),
);

// --- Org-level push protection (block secrets + binaries) ---
// Push rulesets apply to EVERY push across the entire fork network, catching
// secrets before they enter the repo.
//
// NOT ACTIVE ANYWHERE TODAY: every live ruleset in this org is target=branch,
// so this one does not exist on GitHub. It is declared, and applying it is a
// deliberate step — see docs/setup-guide.md.
const pushProtection = new github.OrganizationRuleset("block-secrets-and-binaries", {
    name: "block-secrets-and-binaries",
    target: "push",
    enforcement: "active",
    conditions: {
        repositoryName: {
            includes: ["~ALL"],
            excludes: [],
        },
    },
    rules: {
        // Block pushes containing these file paths
        filePathRestriction: {
            restrictedFilePaths: [
                ".env",
                "*.pem",
                "*.key",
                "credentials*",
                "**/secrets/**",
            ],
        },
        // Block pushes containing these file extensions (binaries)
        fileExtensionRestriction: {
            restrictedFileExtensions: [
                "*.exe",
                "*.dll",
                "*.so",
                "*.dylib",
            ],
        },
        // Block files larger than 50 MB
        maxFileSize: {
            maxFileSize: 50,
        },
    },
});

// --- Devtools repo: ALL PRs require human review ---
// The devtools repo is trust-boundary by definition — it contains the enforcement
// mechanisms for all other repos. Any change to it must be human-reviewed.
const devtoolsRuleset = new github.RepositoryRuleset("devtools-trust-boundary", {
    name: "trust-boundary-human-review",
    repository: "devtools",
    target: "branch",
    enforcement: "active",
    conditions: {
        refName: {
            includes: ["~ALL"],
            excludes: [],
        },
    },
    bypassActors: [],  // No bypass — even org admins cannot bypass
    rules: {
        deletion: true,
        nonFastForward: true,
        pullRequest: {
            requiredApprovingReviewCount: 1,
            requireLastPushApproval: true,
        },
        requiredStatusChecks: {
            strictRequiredStatusChecksPolicy: true,
            requiredChecks: [
                { context: "Trust Boundary Protection" },
            ],
        },
    },
});

// --- Bot repo: trust-boundary files require specific team review ---
// Repo-level rather than org-level because `requiredReviewers` with file
// patterns is a newer provider feature; the code-owner review below is what
// enforces the boundary, and the path-based pattern is documented in
// docs/codeowners-trust-boundary.md.
const botTrustBoundary = new github.RepositoryRuleset("bot-trust-boundary-review", {
    name: "trust-boundary-codeowner-review",
    repository: "bot",
    target: "branch",
    enforcement: "active",
    conditions: {
        refName: {
            includes: ["refs/heads/main"],
            excludes: [],
        },
    },
    rules: {
        pullRequest: {
            requiredApprovingReviewCount: 1,
        },
    },
});

// Export ruleset IDs for reference
export const branchProtectionId = branchProtection.id;
export const requiredCiChecksId = requiredCiChecks.id;
export const mergeQueueIds = mergeQueues.map((r) => r.id);
export const pushProtectionId = pushProtection.id;
export const devtoolsRulesetId = devtoolsRuleset.id;
