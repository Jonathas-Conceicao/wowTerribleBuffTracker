# Phase 31 — Summary 01: Single TOC

**Completed:** 2026-09-20
**Requirements:** TOC-06, TOC-07, TOC-08, TOC-09

## What changed

| File | Change |
|---|---|
| `TerribleBuffTracker_Mainline.toc` | `## Interface: 120100` → `## Interface: 120100, 16001`; `## Notes:` widened to name both clients |
| `TerribleBuffTracker_Camelot.toc` | **deleted** |
| `scripts/check-toc.ps1` | **deleted** |
| `scripts/release.bat` | dropped the `check-toc.ps1` pre-tag gate |
| `scripts/install.bat` | `FILES` no longer lists the Camelot TOC |
| `.pkgmeta-mainline` → `.pkgmeta` | `git mv`, cross-ignore lines stripped (Phase 32 owns the rest) |
| `.pkgmeta-camelot` | **deleted** |
| `.gitattributes` | `.pkgmeta-* text eol=lf` → `.pkgmeta text eol=lf` |
| `CLAUDE.md` | two-TOC constraint replaced with the one-TOC rule; `check-toc.ps1` and `.pkgmeta-*` lines removed from Architecture |

No Lua or XML file was touched. No forked source file exists.

## Deployment state

The orphaned `TerribleBuffTracker_Camelot.toc` was removed from `_classic_beta_`, `_ptr_` and `_beta_`
(`_retail_` never had one), then `install.bat` was run. `_classic_beta_` and `_retail_` now hold exactly
one TOC each, reading `## Interface: 120100, 16001`.

`_beta_` and `_ptr_` still hold a stale unsuffixed `TerribleBuffTracker.toc` — pre-existing, out of
deployment scope, and owned by `INST-07`/`INST-08` in Phase 33.

## Findings

**The `TOC-02` ambiguity from backlog item 999.3 is closed, and not in the direction that was feared.**
Before this phase, `_classic_beta_` held **only** `TerribleBuffTracker_Camelot.toc`. There was never a
`_Mainline.toc` in that folder for the client to prefer, so v0.3's Forever verification pass
unambiguously ran against the Camelot TOC. The worry recorded in `999.3` — that the whole pass might
have run against the retail TOC — was unfounded. Settled from disk; no in-game read was needed.

**The comma form has two independent precedents.** Platynator ships
`## Interface: 120100, 16001, 50504, 38001, 20506, 11509` in a single TOC on Forever, and TBT's own
throwaway `tools/TBTProbe/TBTProbe.toc` used `## Interface: 120100, 16001` and loaded on both
`_retail_` and `_classic_beta_` during the 2026-09-20 experiment session.

**`## AllowLoadGameType:` was deliberately omitted.** TBTProbe declared it and Blizzard's own
`Blizzard_CooldownViewer.toc` declares it, but Platynator — a shipping third-party addon on Forever —
does not, and that is the pattern the user chose to follow.

## Deviations from plan

None.

## Amended by Phase 32 (2026-09-20)

The TOC was renamed again, from `TerribleBuffTracker_Mainline.toc` to the unsuffixed
`TerribleBuffTracker.toc`. Reading the BigWigs packager source before trusting CI showed a `_Mainline`
suffix forces `game_type=retail` from the filename and then hard-fails against a multi-game-type
`## Interface:` line. The unsuffixed name is also what Platynator uses. Details in
`32-01-SUMMARY.md`.

## Follow-ups

- `.pkgmeta` content, `release.yml` and the observed single-zip run → Phase 32.
- Version substitution, pruning, one shared file list, branch guard → Phase 33.
- Retail confirmation of the single TOC → `VER-10`, Phase 44. No retail check happens before then.

---

## ⚠ Correction — 2026-09-20, after in-game testing

The Phase 32 rename to an unsuffixed `TerribleBuffTracker.toc` has been **reverted**. The Forever client
does not load that name; renaming the deployed file back to `TerribleBuffTracker_Mainline.toc` made it
load immediately, with the same `## Interface: 120100, 16001` line.

`TOC-06` therefore **passes**: TBT loads and works on Forever from a single multi-interface TOC. The
migration itself is sound — only the filename was wrong, and the user had said to keep `_Mainline` from
the start.

The cost is that packaging is now blocked; see the correction in `32-01-SUMMARY.md`.

---

## Resolution — 2026-09-20

The TOC is **`TerribleBuffTracker.toc`, unsuffixed**, declaring `## Interface: 120100, 16001`.

The earlier "Forever does not load the unsuffixed TOC" result was wrong: it was tested without fully
restarting the client, and WoW only scans the AddOns folder at launch. Re-tested with a full exit and
relaunch, it loads. `TOC-06` passes on the unsuffixed name.

The suffix had to go regardless — see `32-01-SUMMARY.md` for why the BigWigs packager cannot accept a
`_Mainline` TOC that declares a non-retail interface.
