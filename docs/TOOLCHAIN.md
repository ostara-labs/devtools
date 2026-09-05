# Rust toolchain policy

## Decision

`rust-ci.yml` pins `dtolnay/rust-toolchain@stable` — a trusted moving ref, the one deliberate exception to the org-wide digest-pinning convention (the same exception class as `@stable`-family actions reviewed on the pilot).

## Rationale

- `rust-ci.yml` lives **here**. A new clippy lint or a toolchain regression affects every consumer repo, but the fix is also central: **one PR on devtools repairs all consumers at once**, absorbed on their next bump.
  Proven 2026-09-04: clippy 1.98 introduced `chunks_exact_to_as_chunks`; every repo's CI went red on code nobody touched; one central commit fixed all of them.
- Pinning a fixed version would freeze the org on an aging toolchain and still require a manual rollout for every upgrade.
- A per-repo `rust-toolchain.toml` would reintroduce the per-repo divergence this repository exists to remove.

## Known cost (accepted)

A new stable release can break CI on repos nobody touched, until the central fix lands. The breakage is loud (red runs across the org), the fix is one central commit, and consumers absorb it on bump. The drift-scan makes the lag visible.

## Escape hatch

If a stable release ever breaks a repo that cannot wait for the central fix, the repo can pin `rust-toolchain.toml` locally **temporarily**, with a comment pointing at the central follow-up. Local pins are the exception and must not outlive the central fix.
