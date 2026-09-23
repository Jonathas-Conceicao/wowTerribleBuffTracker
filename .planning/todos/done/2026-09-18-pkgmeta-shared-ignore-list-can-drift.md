---
created: 2026-09-18
title: The shared .pkgmeta-* ignore list can drift between flavors with no guard
area: packaging
resolves_phase: 32
files:
  - .pkgmeta-mainline
  - .pkgmeta-camelot
  - scripts/check-toc.ps1
---

## Problem

`.pkgmeta-mainline` and `.pkgmeta-camelot` share nine identical `ignore` lines (`.gitignore`,
`.pkgmeta-mainline`, `.pkgmeta-camelot`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, `LICENSE`,
`scripts`, `*.png`, `RELEASE_NOTES.md`, plus `stylua.toml` as of Phase 30 plan 30-04) and differ
only in the one cross-ignore line each (`.pkgmeta-mainline` ignores
`TerribleBuffTracker_Camelot.toc`; `.pkgmeta-camelot` ignores `TerribleBuffTracker_Mainline.toc`).

`scripts/check-toc.ps1`'s assertion 3 (added Phase 25, live since Phase 29) only checks that
each file ignores the *other* flavor's TOC and does not ignore its own — it says nothing about
the shared nine-line block. If someone edits the shared list in one file and not the other
(adds a new ignore entry, typos an existing one, reorders in a way that breaks something), no
gate catches it. `29-CONTEXT.md` itself names this "the same class of bug as TOC drift" that
assertions 1 and 2 exist to prevent for the TOC pair.

## Why Phase 30 did not fix it

The fix is a fourth `check-toc.ps1` assertion diffing the two files' `ignore` lists modulo the
one expected cross-ignore difference. That is new guard behaviour — it adds a capability the
script does not have today — and Phase 30's cleanup mandate covers duplication the milestone
introduced plus dead code removal, not new verification tooling. `30-CONTEXT.md`'s D-02 audit
found the shared content structurally irreducible (the BigWigs packager format has no
include/inherit/extends/merge directive — verified against the pinned `release.sh` source), so
unifying the *files* isn't an option either; only a new *guard* would close this gap, and that
needs its own phase with its own gates.
