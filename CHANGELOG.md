# Changelog

## [2.0.0](https://github.com/ostara-labs/devtools/compare/devtools-v1.2.0...devtools-v2.0.0) (2026-09-03)


### ⚠ BREAKING CHANGES

* rewrite makefiles to monorepo paradigm, port proven workflows from repo-template

### Features

* **ci:** gate workflow (actionlint+shellcheck) and legacy file cleanups ([a330f34](https://github.com/ostara-labs/devtools/commit/a330f34543429e84b2795d20902eac61833fae1f))
* devtools repo — shared hooks, makefiles, CI workflows, lint configs, Pulumi rulesets for cross-repo enforcement ([6918ca4](https://github.com/ostara-labs/devtools/commit/6918ca42b33835a26203cde2b02747e59a91a8c7))
* **devtools:** automerge-dispatch composite action — defeat GITHUB_TOKEN anti-recursion ([#5](https://github.com/ostara-labs/devtools/issues/5)) ([4e6b4ee](https://github.com/ostara-labs/devtools/commit/4e6b4ee61ee51b86f16d5f2739ce6bb7ae89d3dc))
* **devtools:** merge back child-repo improvements and consolidate enforcement ([#10](https://github.com/ostara-labs/devtools/issues/10)) ([177bc3e](https://github.com/ostara-labs/devtools/commit/177bc3e64355841e968eca4751bfaf1e01c5fd90))
* **devtools:** optional stack-dir input on language CI workflows + MIT license ([#4](https://github.com/ostara-labs/devtools/issues/4)) ([dac4c6c](https://github.com/ostara-labs/devtools/commit/dac4c6c8a7c84acdfbd0b124ded2ab06b1e1081e))
* org-gate composite action — digest-pinned, centralized gate logic ([b5120da](https://github.com/ostara-labs/devtools/commit/b5120da9fed9813a787662091af04eb63cfedf39))
* rewrite makefiles to monorepo paradigm, port proven workflows from repo-template ([58dabf3](https://github.com/ostara-labs/devtools/commit/58dabf3d74b4ff569e4aa3586032d14291addf64))
* **scripts:** org-level main-protection ruleset provisioning ([f89d19a](https://github.com/ostara-labs/devtools/commit/f89d19a32444f0e9999760764add0145fd468c71))


### Bug Fixes

* **make:** SHELL ?= is a no-op in GNU make - use := ([cea4b3a](https://github.com/ostara-labs/devtools/commit/cea4b3a7b686815548c81a08473059fef14de401))
* org-gate — preserve shellcheck status through mapfile, curl timeouts ([4364455](https://github.com/ostara-labs/devtools/commit/4364455c3e2e74ebab2d0c113673d9e75e111f7f))
* pre-commit — keep line numbers on multi-line unwrap/expect checks ([bc33f4c](https://github.com/ostara-labs/devtools/commit/bc33f4c3107ce145dcb04376712b7e980e4d3735))
* pre-commit — keep line numbers on multi-line unwrap/expect checks ([695db33](https://github.com/ostara-labs/devtools/commit/695db33190b0ea073a3b704342b96fef0756de04))
* pre-commit — recognize *_tests.rs as test files (secrets + unwrap/expect checks) ([9412c76](https://github.com/ostara-labs/devtools/commit/9412c76098ba76f830d21ba8d762d106bf22788c))
* pre-commit — recognize *_tests.rs as test files (secrets + unwrap/expect checks) ([de5569f](https://github.com/ostara-labs/devtools/commit/de5569f8654835d7ae3be9a59f218001b302f831))
* pre-commit — replace awk with grep for LOC count (Windows + Rust // comments) ([b81f847](https://github.com/ostara-labs/devtools/commit/b81f847d83f2f16177fd187517fde7c88b62728a))
* pre-commit awk crash on Windows with Rust // comments ([35ea0f3](https://github.com/ostara-labs/devtools/commit/35ea0f328f42d8b9e6d26bf389bfda9020cad352))
* **scripts:** drop protected flag - incompatible with ~ALL include ([05e77a4](https://github.com/ostara-labs/devtools/commit/05e77a47b07fc45ebf0a669dc80c26d0b49f5efb))
