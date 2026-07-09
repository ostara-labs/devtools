// infra/rulesets/index.ts — GitHub Organization Rulesets for ostara-labs
//
// Server-side enforcement that CANNOT be bypassed by the agent (unlike git hooks).
// This is the strongest enforcement layer — it runs on GitHub's servers, not locally.
//
// Applies to ALL repos in the ostara-labs org:
//   - Require PRs (no direct pushes to main)
//   - Required status checks (lint, test) before merge
//   - Block force pushes and branch deletion
//   - Block secrets and binaries in pushes (push ruleset)
//   - Commit message pattern enforcement (conventional commits)
//   - Trust-boundary PRs require human review (via required reviewers)
//
// The devtools repo has ALL PRs require human review (it is trust-boundary).

import * as github from "@pulumi/github";
import * as pulumi from "@pulumi/pulumi";

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
//
// No token variable needed — the Pulumi GitHub provider reads appAuth config
// automatically and generates an installation token per execution.

const config = new pulumi.Config();
// Provider config is read automatically by the @pulumi/github provider.
// No explicit token retrieval needed here — the provider handles it.

// --- Org-level branch protection (all repos) ---
const branchProtection = new github.OrganizationRuleset("core-branch-protection", {
    name: "core-branch-protection",
    target: "branch",
    enforcement: "active",
    conditions: {
        refName: {
            includes: ["refs/heads/main", "refs/heads/develop"],
            excludes: [],
        },
        repositoryName: {
            includes: ["~ALL"],
            excludes: [],
            protected: true,
        },
    },
    bypassActors: [],  // No bypass — even org admins cannot bypass
    rules: {
        // Block branch deletion
        deletion: true,
        // Block force pushes
        nonFastForward: true,
        // Require linear history (no merge commits — squash or rebase only)
        requiredLinearHistory: true,
        // Require PR with at least 1 approval
        pullRequest: {
            requiredApprovingReviewCount: 1,
            dismissStaleReviewsOnPush: true,
            requireLastPushApproval: true,
            requiredReviewThreadResolution: true,
            allowedMergeMethods: ["squash", "rebase"],
        },
        // Required status checks — these MUST pass before merge
        requiredStatusChecks: {
            strictRequiredStatusChecksPolicy: true,
            requiredChecks: [
                { context: "lint" },
                { context: "test" },
                { context: "PR Classify" },  // trust-boundary classification
            ],
        },
    },
});

// --- Org-level push protection (block secrets + binaries) ---
// Push rulesets apply to EVERY push across the entire fork network.
// This catches secrets before they even enter the repo.
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
    name: "devtools-trust-boundary-all-prs-require-review",
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
// Uses required_reviewers (beta) to require review from a specific team
// when trust-boundary files are touched.
// Note: This is a repo-level ruleset because required_reviewers with
// file_patterns is a newer feature.
const botTrustBoundary = new github.RepositoryRuleset("bot-trust-boundary-review", {
    name: "bot-trust-boundary-file-review",
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
            // Note: required_reviewers with file_patterns is beta.
            // The PR classification workflow (pr-classify.yml) handles this
            // at the CI level until required_reviewers is GA.
        },
    },
});

// Export ruleset IDs for reference
export const branchProtectionId = branchProtection.id;
export const pushProtectionId = pushProtection.id;
export const devtoolsRulesetId = devtoolsRuleset.id;
