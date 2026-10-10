---
phase: 65-cleanup
plan: 02
subsystem: scripts
tags: [install, png2blp, release-chain, cleanup]
requires: []
provides:
  - install.ps1 empty-directory prune (D-06)
  - png2blp.js input checks (D-07)
  - deploy and release chain review (D-10)
affects: [62-REVIEW.md IN-02, IN-03 (Plan 03 cites the hashes below)]
tech-stack:
  added: []
  patterns: [non-recursive Directory.Delete confined under $dest]
key-files:
  modified:
    - scripts/install.ps1
    - scripts/png2blp.js
decisions:
  - release.bat, install.bat, .pkgmeta and release.yml left unchanged (nothing broken)
metrics:
  completed: 2026-10-01
  tasks: 2
  files: 2
---

# Phase 65 Plan 02: Script Cleanup Summary

install.ps1 now removes directories left empty after the file prune, and png2blp.js fails cleanly on a missing source, duplicate output names and a bad PNG signature. The deploy and release chain was reviewed against Media/Textures and needs no change.

## Commits

- `a860d0e` fix(65-02): install prunes empty directories left in the deployed addon (scripts/install.ps1)
- `956feb8` fix(65-02): png2blp fails cleanly on a missing source, duplicate outputs and a bad signature (scripts/png2blp.js)

## D-06 probe run (real install, 4 client folders: _retail_, _ptr_, _beta_, _classic_beta_)

First install, with `Media/Textures/zz_probe_dir/zz_prune_probe.blp` in the repo:

```
WARNING: Media\Textures\zz_probe_dir\zz_prune_probe.blp is not tracked by git - it will not be in a release
Deploying 23 files derived from TerribleBuffTracker.toc: ... Media\Textures\zz_probe_dir\zz_prune_probe.blp
Installed to ...\_retail_\Interface\AddOns\TerribleBuffTracker  (and _ptr_, _beta_, _classic_beta_)
```

Second install, probe removed from the repo (once per client):

```
  pruned stale file: Media\Textures\zz_probe_dir\zz_prune_probe.blp
  pruned empty directory: Media\Textures\zz_probe_dir
Installed to ...\TerribleBuffTracker (1 stale file(s) pruned)
```

The gate also confirmed: no empty directory under any deployed addon folder, each deployed Media/Textures holds the repo's 10 BLPs, `git status --short Media/` empty. The probe was removed from the repo and from every deployed folder (checked after the run).

The delete is `[System.IO.Directory]::Delete(path, $false)` only, strictly under `$dest + '\'`, deepest first; no `Remove-Item -Recurse` exists. install.ps1 stays CRLF.

## D-07

Fixture gate passed: missing Media/Source gives `ERROR:` exit 1 with no ENOENT; `icon_buff_ally.png` vs `ICON_Buff_Ally.png` is rejected before any BLP is written; a PNG with a zeroed first byte gives `is not a PNG`. `node scripts/png2blp.js` on the real sources leaves `git status --short Media/` empty (byte-identical). png2blp.js stays LF.

## D-10 review (per file)

- `scripts/install.bat`: forwards to install.ps1 with `%*`; knows nothing of Media. Not broken.
- `scripts/install.ps1`: file set = TOC + load list, CDMTab.lua via CDMTab.xml, the `## IconTexture:` BLP, and every .blp/.tga under Media\Textures (recursive). Warns on untracked textures. Prunes stale files and now empty folders. Deploys 22 files (23 during the probe). Not broken after the change.
- `scripts/release.bat`: branch guard, tags HEAD, pushes main and tag. No reference to Media; gate scripts not wired in. Unchanged (Phase 58 decision).
- `.pkgmeta`: ignores Media/Source, `"*.png"`, scripts, tools, .planning, .github and docs. The gate computed tracked files minus this ignore list and it equals the install file set exactly. `"*.png"` is assumed to match nested paths; Media/Source is also ignored by name, so the shipped set is right either way. Assets/*.png are likewise excluded. Not broken.
- `.github/workflows/release.yml`: extracts the first CHANGELOG section and runs the BigWigs packager; names no Media path. Not broken.

## Deviations from Plan

None. The plan's gates ran as written and both printed ok. Note: git warns "LF will be replaced by CRLF" for png2blp.js on commit (autocrlf with `text=auto`); the file is `i/lf w/lf`, as intended.

## Known Stubs

None.

## Self-Check: PASSED

Both commits exist (a860d0e, 956feb8); `git status --short` shows only the user's Assets/ changes; STATE.md, ROADMAP.md and CHANGELOG.md untouched.
