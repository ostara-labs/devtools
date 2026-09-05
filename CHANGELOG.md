# Changelog

## [1.7.0](https://github.com/ostara-labs/devtools/compare/v1.6.0...v1.7.0) (2026-09-05)


### Features

* **ci:** opt-in PostGIS test job in python-ci ([#9](https://github.com/ostara-labs/devtools/issues/9)) ([9319eee](https://github.com/ostara-labs/devtools/commit/9319eee80415e10260173b0a24d6e7459e4febf8))

## [1.6.0](https://github.com/ostara-labs/devtools/compare/v1.5.0...v1.6.0) (2026-09-05)


### Features

* **ci:** make pr-meta a reusable workflow, dependabot-safe and lockfile-safe ([#8](https://github.com/ostara-labs/devtools/issues/8)) ([ae25b1f](https://github.com/ostara-labs/devtools/commit/ae25b1fd38862b2ad1ea7a2b8d05b5de5e5dc4b4))

## [1.5.0](https://github.com/ostara-labs/devtools/compare/v1.4.3...v1.5.0) (2026-09-05)


### Features

* **ci:** docs-drift gate (DOC_MAP + reusable workflow) ([#6](https://github.com/ostara-labs/devtools/issues/6)) ([e5aa8df](https://github.com/ostara-labs/devtools/commit/e5aa8dfad8cd830d4920fc201c0cfc56ce12886c))
* **ci:** wire docs-drift into the org aggregate ([#34](https://github.com/ostara-labs/devtools/issues/34)) ([217d4fd](https://github.com/ostara-labs/devtools/commit/217d4fda8a6af03a615f126beaeb8d2fcafe78ab))


### Bug Fixes

* **drift-scan:** GitHub App auth preferred + adoption table refresh ([#30](https://github.com/ostara-labs/devtools/issues/30)) ([2e8e11c](https://github.com/ostara-labs/devtools/commit/2e8e11c7d6b1a3d6aa240161c9f09ce9d7004b0a))

## [1.4.3](https://github.com/ostara-labs/devtools/compare/v1.4.2...v1.4.3) (2026-09-04)


### Bug Fixes

* **hooks:** harden the pre-commit hook (NUL-delimited iteration, index snapshots, CR-safe) ([#27](https://github.com/ostara-labs/devtools/issues/27)) ([caa02b9](https://github.com/ostara-labs/devtools/commit/caa02b9da409f9d10ef4f1877b7c1d5305e9835f))

## [1.4.2](https://github.com/ostara-labs/devtools/compare/v1.4.1...v1.4.2) (2026-09-04)


### Bug Fixes

* **makefile:** detect npm vs pnpm in the typescript stack ([#25](https://github.com/ostara-labs/devtools/issues/25)) ([063b98a](https://github.com/ostara-labs/devtools/commit/063b98a8c335d32eb06637bfd36477aff9d89869))

## [1.4.1](https://github.com/ostara-labs/devtools/compare/v1.4.0...v1.4.1) (2026-09-04)


### Bug Fixes

* **ci:** detect npm vs pnpm in the typescript stack ([#22](https://github.com/ostara-labs/devtools/issues/22)) ([1a41a0e](https://github.com/ostara-labs/devtools/commit/1a41a0ebddc7677bdc8dd47c6b7e60089e447b81))

## [1.4.0](https://github.com/ostara-labs/devtools/compare/v1.3.3...v1.4.0) (2026-09-04)


### Features

* **automation:** weekly conformance drift-scan + Renovate org preset ([#20](https://github.com/ostara-labs/devtools/issues/20)) ([4f3e9ce](https://github.com/ostara-labs/devtools/commit/4f3e9ce695ce3d11dea964b02fd1ec8d63d1f163))

## [1.3.3](https://github.com/ostara-labs/devtools/compare/v1.3.2...v1.3.3) (2026-09-03)


### Bug Fixes

* **ci:** guard the extensionless-hooks shellcheck step ([#18](https://github.com/ostara-labs/devtools/issues/18)) ([4d120df](https://github.com/ostara-labs/devtools/commit/4d120df14be6b98da161625e6b45a57e9c5ae725))

## [1.3.2](https://github.com/ostara-labs/devtools/compare/v1.3.1...v1.3.2) (2026-09-03)


### Bug Fixes

* **ci:** pin org-gate by digest in the aggregate (cross-repo callers) ([#16](https://github.com/ostara-labs/devtools/issues/16)) ([7ee02c3](https://github.com/ostara-labs/devtools/commit/7ee02c3cd70577ef1ea4cbf7c74f6c40ffe04dc9))

## [1.3.1](https://github.com/ostara-labs/devtools/compare/v1.3.0...v1.3.1) (2026-09-03)


### Bug Fixes

* **hooks:** use [[:blank:]] for the trailing-whitespace check ([#14](https://github.com/ostara-labs/devtools/issues/14)) ([e7ba2d4](https://github.com/ostara-labs/devtools/commit/e7ba2d4d10f301d8b70359b5c9709816b7ae55d8))

## [1.3.0](https://github.com/ostara-labs/devtools/compare/v1.2.0...v1.3.0) (2026-09-03)


### Features

* **devtools:** automerge-dispatch composite action — defeat GITHUB_TOKEN anti-recursion ([#5](https://github.com/ostara-labs/devtools/issues/5)) ([4e6b4ee](https://github.com/ostara-labs/devtools/commit/4e6b4ee61ee51b86f16d5f2739ce6bb7ae89d3dc))
* **devtools:** merge back child-repo improvements and consolidate enforcement ([#10](https://github.com/ostara-labs/devtools/issues/10)) ([177bc3e](https://github.com/ostara-labs/devtools/commit/177bc3e64355841e968eca4751bfaf1e01c5fd90))


### Bug Fixes

* **release:** match existing v* tag format so history scopes to the last release ([#12](https://github.com/ostara-labs/devtools/issues/12)) ([b4f37ce](https://github.com/ostara-labs/devtools/commit/b4f37cec54fa7268fc51211cf6e3657f1b04d7e5))
