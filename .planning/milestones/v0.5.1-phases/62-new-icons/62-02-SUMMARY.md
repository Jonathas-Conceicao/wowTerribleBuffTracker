---
phase: 62-new-icons
plan: 02
subsystem: install-release
tags: [install, pkgmeta, textures, blp]
requires: ["62-01"]
provides:
  - "Media/Textures BLPs, Media/Source PNGs and png2blp.js committed"
  - "install.ps1 deploys and prunes Media/Textures"
  - "Release zip drops Media/Source, keeps Media/Textures"
key-files:
  modified: [.pkgmeta, scripts/install.ps1]
  created: [scripts/png2blp.js, Media/Source/*.png, Media/Textures/*.blp]
requirements: [INST-10, DIST-13]
metrics:
  tasks: 2
  completed: 2026-09-30
---

# Phase 62 Plan 02: Ship the textures Summary

Textures now reach every client folder and the release zip: `install.ps1` gained a fourth file-set source (every `.blp`/`.tga` under `Media\Textures`, backslash paths built like the prune loop's `$rel`), and `.pkgmeta` ignores `Media/Source`.

## Task 1 (DIST-13)
- Committed the five BLPs, five PNGs and `scripts/png2blp.js` (index `i/-text` for media, `i/lf` for the script).
- `.pkgmeta`: added `  - Media/Source` after `  - tools` (`w/lf`). Nothing ignores Media, Media/Textures or *.blp.
- `node scripts/png2blp.js` rebuilt every BLP with no change in git status (byte-identical).
- `.github/workflows/release.yml` names no Media/.blp/.png path; unchanged.

## Task 2 (INST-10)
- `install.ps1`: header point 1 extended; `$texDir`/`$texRel` block between the `## IconTexture:` block and the existence-check loop. `w/crlf` preserved.
- Real installs to `_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`: "Deploying 16 files" listing all five `Media\Textures\icon_*.blp`; second run pruned nothing; every BLP byte-identical to the repo in all four folders; no deployed `Media/Source`.
- Probe `zz_prune_probe.blp` was deployed to all four, then after removal from the repo produced four `pruned stale file: Media\Textures\zz_prune_probe.blp` lines and is gone everywhere. Never staged; not in the repo.
- Final install left all four clients with the phase's code and textures (full client restart needed for new textures; in-game check is Phase 66).

## Deviations from Plan
None. (One shell redirect to a bad path failed harmlessly before the gate was run; the gate was then run directly.)

## Commits
- c2e6d07 feat(62-02): ship TBT's tab textures and png2blp.js; keep Media/Source out of the release
- a1edb05 feat(62-02): install.ps1 deploys and prunes Media/Textures

## Self-Check: PASSED
