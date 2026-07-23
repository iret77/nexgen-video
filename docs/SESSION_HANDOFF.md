# Session handoff — 2026-07-23

## Objective

Ship one consolidated NexGenVideo 1.0 release candidate. Never build locally. Do not merge, open a
release PR, dispatch CI or `release.yml`, or publish without the owner's explicit in-the-moment
approval.

## Prepared state

- Branch: `codex/release-1.0-rc`
- Base: `origin/main`
- App/changelog version: `1.0.0`
- Musicvideo pack candidate: `0.0.5` (stable catalog currently `0.0.4`)
- No local build or test was run; macOS 26 GitHub Actions is the only verification surface.
- No PR, CI run, DMG build, merge, tag, issue closure, or release was triggered.

The release-blocker implementations for #279–#287 are present:

- #279: complete working-copy recovery and recovery regression coverage.
- #280: persistent project-song identity, awaited/idempotent attach and atomic replacement.
- #281: isolated preview publication and retry-safe stable release transaction.
- #282: off-main content-addressed bulk import, cancellation, rollback, undo and redo.
- #283: fail-closed remote import policy for URLs, redirects, DNS/peer addresses, limits and payloads.
- #284: immutable model revisions plus mandatory SHA-256 verification and cache repair.
- #285: typed control turns that never render app-authored commands as user messages.
- #286: central pre-dispatch monetary ledger and hard budget guard.
- #287: notarized downloadable packs plus quarantined runtime load verification.

The issues stay open until the consolidated macOS CI run proves their acceptance criteria.

## Review and static verification

- Independent reviews found and the batch fixes:
  - import undo deleting bytes without redo;
  - remote temp-file installation assuming a same-volume move;
  - `URLSession` download files not being retained from the delegate callback;
  - cross-thread model-download error state.
- `git diff --check` passes.
- All workflow YAML parses.
- All 31 workflow `run:` blocks and release shell scripts pass `bash -n`.
- Changelog JSON, app Info.plist and Python sources pass static parsing/syntax checks.
- Branch pushes do not trigger CI; repository workflows run on pull requests or manual dispatch.

## Remaining gates

1. Run `spec-check --base origin/main` with explicit permission for its external reviewer. The
   sandboxed reviewer cannot initialize, and the managed host policy rejected an unsandboxed reviewer
   without a separate informed approval. The spec gate is therefore not yet passed.
2. Obtain the owner's explicit in-the-moment `build now`.
3. Run one consolidated macOS 26 CI verification and review every #279–#287 acceptance criterion.
4. Only after green CI: close verified blockers and prepare the release PR.
5. Production merge, `release.yml` dispatch and publication each remain separate explicit actions.

## Release workflow

The stable pack and badge bytes upload before the final catalog promotion. Pending catalog,
transaction metadata, catalog/artifact hashes and a completion marker make publication resumable
without another macOS allocation. Resume now fetches the release branch and checks out its head
detached before committing the appcast, preventing stale Linux-gate state from causing a
non-fast-forward publication failure.
