---
created: 2026-09-18
title: The shared runtime file set is enumerated in three places with nothing asserting they agree
area: tooling
files:
  - scripts/install.bat
  - TerribleBuffTracker_Mainline.toc
  - TerribleBuffTracker_Camelot.toc
---

## Problem

The set of files that make up a working TBT install is listed independently in three places:
`scripts/install.bat`'s `FILES` variable, `TerribleBuffTracker_Mainline.toc`'s file list, and
`TerribleBuffTracker_Camelot.toc`'s file list. `scripts/check-toc.ps1` assertion 2 already
guards the two TOCs against each other (body parity, excluding `## Interface:`/`## Notes:`),
but nothing guards `install.bat`'s copy list against either TOC. Add a file to both TOCs
without adding it to `install.bat`'s `FILES`, and every fresh deploy silently ships an addon
missing a Lua file — with no error until the game tries to load the missing global.

## Why Phase 30 did not fix it

`scripts/install.bat` is already unified as far as its own duplication goes (Phase 26 built it
as a single data-driven `FILES` × `FLAVORS` double loop with no per-client branch — confirmed by
Phase 30 plan 30-04's audit). Making it parse a TOC file at runtime to derive its own file list,
or adding a fourth `check-toc.ps1` assertion cross-checking `install.bat` against the TOCs, is
new behaviour beyond `INST-01…04`'s scope. Phase 30's mandate is unifying duplication the
milestone introduced and removing dead code, not adding new drift-detection capability — that's
a tooling improvement for its own phase.
