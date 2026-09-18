---
created: 2026-09-18
title: install.bat copies but never prunes, so deleted files linger in deployed folders
area: tooling
files:
  - scripts/install.bat
---

## Problem

`scripts/install.bat` copies its explicit 10-file list into each client's AddOns folder but never
removes anything. Every file ever deleted from the repo survives indefinitely in a deployed folder.

Verified in the live retail install on 2026-09-18, after Phase 26's deploy:

```
_retail_\Interface\AddOns\TerribleBuffTracker\
  TerribleBuffTracker.toc     <- stale, pre-v0.3 rename. ACTIVELY DANGEROUS: the client can
                                 load from it, which would have silently invalidated the entire
                                 retail regression pass for v0.3.
  ConfigUI.lua                <- deleted from the repo in v0.2.0 Phase 3, still deployed
  tbt_icon_64x64.png          <- PNG source; only the .blp is needed at runtime
```

The Forever folder (`_classic_beta_`) is clean only because it was created fresh by Phase 26.

## Why it matters

The stale TOC case is not cosmetic. A leftover unsuffixed TOC lets the client load the addon from
the wrong file, so a verification pass can report PASS while proving nothing about the file under
test. v0.3's retail regression pass had to be hand-annotated with a "delete this first" warning
precisely because of this.

Stale Lua files are lower risk (they are not in either TOC's load list, so they never execute) but
they confuse anyone inspecting a deployed folder, and a future file with a name matching a TOC
entry could actually load.

## Solution

Options, cheapest first:

1. Delete only known-stale names before copying — a small explicit blocklist. Safe, but needs
   maintaining as files are removed.
2. Delete `*.toc` in the destination before copying the current TOCs. Narrowly targets the
   dangerous case with no blocklist to maintain.
3. Clear the whole destination folder before copying. Cleanest result, but a copy failure
   mid-run would leave the user with no addon, so it needs the source preflight to pass first
   (install.bat already has one).

Option 2 plus option 1 for known cruft is probably the right balance. Option 3 is tempting but
turns a broken deploy into a missing addon.

Out of scope for v0.3's `--to 28` run; INST-01..04 say nothing about pruning. Candidate for Phase 30
cleanup or a v0.3.1 tooling pass.
