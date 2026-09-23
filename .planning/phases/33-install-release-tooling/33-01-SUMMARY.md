# Phase 33 — Summary 01: Install & Release Tooling

**Completed:** 2026-09-20
**Requirements:** INST-05, INST-06, INST-07, INST-08, INST-09, REL-01

## What changed

| File | Change |
|---|---|
| `scripts/install.ps1` | **new** — derives the file set from the TOC, substitutes a dev version into the deployed TOC, prunes stale files |
| `scripts/install.bat` | reduced to a wrapper forwarding to `install.ps1`; still the documented entry point |
| `scripts/release.bat` | refuses to tag unless `HEAD` is on `main`, overridable with `TBT_ALLOW_BRANCH=1` |

## Observed run

```
Deploying 9 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua,
BuffEngine.lua, Providers.lua, EditModeFrames.lua, Display.lua, CDMTab.xml, CDMTab.lua,
tbt_icon_64x64.blp
Deployed version: v0.3.0-8-ge16acbc-dirty-dev
  pruned stale file: ConfigUI.lua
  pruned stale file: tbt_icon_64x64.png
Installed to ...\_retail_\...\TerribleBuffTracker (2 stale file(s) pruned)
  pruned stale file: ConfigUI.lua
  pruned stale file: tbt_icon_64x64.png
Installed to ...\_ptr_\...\TerribleBuffTracker (2 stale file(s) pruned)
  pruned stale file: ConfigUI.lua
Installed to ...\_beta_\...\TerribleBuffTracker (1 stale file(s) pruned)
Installed to ...\_classic_beta_\...\TerribleBuffTracker
```

The nine files are exactly what the old hardcoded `FILES` list held — derived rather than duplicated.

**`ConfigUI.lua` was pruned from three client folders.** It was deleted from the repo in v0.2.0 and had
been sitting in deployed folders ever since; the `install.bat` todo predicted precisely this.

Deployed TOC on both clients under test:

```
## Interface: 120100, 16001
## Version: v0.3.0-8-ge16acbc-dirty-dev
```

Repo TOC, unchanged:

```
## Version: @project-version@
```

`_classic_beta_` and `_retail_` each hold exactly nine files and exactly one TOC.

## Branch guard

Run from the milestone branch:

```
=== Releasing TerribleBuffTracker 9.9.9 ===
ERROR: on branch "milestone/v0.4.0-cooldown-tracking-cdm-view", but release.bat tags HEAD and pushes origin main.
Squash-merge into main first, then release from main.
Set TBT_ALLOW_BRANCH=1 to override.
```

`git tag -l v9.9.9` is empty afterwards — it refused before tagging, rather than tagging and failing at
the push.

## Todos resolved

| Todo | Resolution |
|---|---|
| `2026-09-18-install-bat-does-not-prune-stale-files.md` | `install.ps1` prunes; `ConfigUI.lua` gone from three folders |
| `2026-09-18-runtime-file-set-enumerated-three-places.md` | one place — the TOC. Two of the three sites (the second TOC, the `FILES` list) no longer exist |
| `2026-09-18-release-bat-pushes-main-with-no-branch-guard.md` | guarded, with a deliberate override |
| `2026-09-18-pkgmeta-shared-ignore-list-can-drift.md` | moot — Phase 32 left a single `.pkgmeta` |

## Deviations from plan

The logic moved from batch to PowerShell. The plan assumed `install.bat` could be extended in place;
TOC parsing, XML include-following and version substitution together are not readable as batch. The
`.bat` remains the entry point so nothing the user or `CLAUDE.md` refers to changed.

## Follow-ups

None. Retail is confirmed in Phase 44 like everything else.
