# Session handoff — 2026-07-23

## Objective

Prepare NexGenVideo for a real 1.0 release without spending a macOS/DMG CI run only to discover the next avoidable blocker. Do not build, dispatch `release.yml`, merge, or release without the owner's explicit in-the-moment approval.

## Current state

- Branch: `docs/agents-hard-rules`
- Checkpoint: `8d9df05 checkpoint: harden the 1.0 release path`.
- The post-checkpoint #281/#286 batch is intentionally uncommitted and not a verified release
  candidate.
- No local build or test was run; repository rules require macOS 26 GitHub Actions.
- No CI, DMG, merge, push, or release was triggered during this audit.
- `git diff --check` passes for both the working batch and the complete branch diff.
- `release.yml` parses as YAML and all 22 `run:` blocks pass `bash -n`; `scripts/bundle.sh`,
  release JSON, Info.plist, and Python sources pass static syntax/format checks.

The batch currently includes the storage/recovery overhaul, working-copy routing for durable writes, atomic project and media mutations, fail-closed workflow artifact reads, stricter tool schemas, budget-stop groundwork, inline replacement of transient agent status messages, release preflight hardening, and plugin-pack notarization/quarantine checks.

The post-checkpoint work completes:

- #281: isolated signed preview catalogs, stable production projection, retry-safe stable publication
  with pending/transaction/complete assets, catalog and artifact hashes, and Linux-only resume after
  app publication.
- #286: one host-owned monetary ledger and pre-dispatch guard across video, image, audio, music,
  upscale, reruns, and provider workflow calls. It reads the live working copy, validates the Brief,
  reserves before dispatch, records submitted/provider IDs and verified charges, counts concurrent
  reservations, uses live account pricing for fal.ai, official Runway rates plus ECB conversion, and
  fails closed on unknown/corrupt monetary state when a hard stop is active.
- Regression coverage for blocked provider thunks, corrupt records, legacy credit rows, same-project
  reservations, append-only transitions, provider workflows, preview repetition, and stable pack
  immutability.

## Known release blockers

- #279: complete Recovery behavior
- #280: song replacement durability and success reporting
- #281: dry-run release must not mutate the stable plugin channel
- #282: import correctness, deduplication, undo, symlink cycles, and scope
- #283: import redirects and private targets
- #284: model revisions must be pinned
- #285: app-authored turns must not appear as user messages
- #286: enforce project budget stops at the central paid-generation boundary
- #287: notarize downloadable `.ngvpack` bundles and verify quarantined loading

All issues remain open intentionally. Do not close blockers merely because code exists; verify their
acceptance criteria in the one consolidated CI run.

## Resume here

1. Confirm the branch and post-checkpoint working batch with `git status --short --branch`.
2. Wait for the owner's explicit, in-the-moment `build now`.
3. Run one consolidated macOS 26 CI verification; do not dispatch `release.yml` while the
   `release-blocker` issues remain open.
4. Review the CI result against every blocker acceptance criterion. Only then close verified
   blockers and prepare the release commit/PR.
5. The source changelog, Info.plist, and pack minimum currently align on `0.7.8`. If the intended
   semantic release number is `1.0.0`, change all three together only after the owner confirms it.
6. A production release is a separate explicit action: never merge, dispatch `release.yml`, or
   publish from an earlier/general approval.

## Release workflow detail to revisit

Resolved in the working batch. Stable pack and badge bytes upload first, but only a final
`catalog.json` promotion makes them visible after the versioned app release and appcast commit.
Pending catalog, transaction metadata, catalog SHA-256, asset SHA-256 values, and a final complete
marker make post-release retries resumable on the Linux gate without allocating another macOS runner.
