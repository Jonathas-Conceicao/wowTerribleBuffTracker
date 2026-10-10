---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
plan: 05
subsystem: merge-mode
tags: [merge-mode, review, verification]
requires: ["70-04"]
provides: ["70-MERGE-PATH-REVIEW.md"]
affects: ["Phase 72 testing (deferred in-game checks)"]
key-files:
  created: [.planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-MERGE-PATH-REVIEW.md]
  modified: []
decisions:
  - "No fan-out route is open: cellByID/idByCell stay one-to-one at every instant (AttachMergedItem eviction), and PlaceItem places a frame only on cellByID[its own id] within its own container's viewer, so no source change was needed"
metrics:
  completed: 2026-10-10
  tasks: 2
  files: 1
---

# Phase 70 Plan 05: Merge Mode Whole-Path Review Summary

Wrote the STEAL-22 review: 18 cited fan-out candidates, all CLOSED, resting on a proved invariant that `cellByID` and `idByCell` are inverse one-to-one maps. The 999.21-999.25 closures are argued on the re-anchor path (STEAL-20..23), and 12 in-game checks are deferred to Phase 72. No route was open, so no source changed.

## Commits
- 2fe595e: docs(70-05): write the Merge Mode whole-path review (Task 1)
- Task 2: no commit. No candidate was OPEN, so no source file changed. Gates ran and the build was deployed.

## Review findings
- **Pixel sources left:** Blizzard's item frames, moved by `PlaceItem`; TBT's preview placeholder, which uses the entry's own spellID and label and appears only while previewing; TBT's own non-merged trackers. The merged path reads no aura. The only aura read in the tree is `ns:ReadPlayerAura`, a player-only read by spellID that the merged path never calls.
- **Key invariant:** every `cellByID[id] = cell` write is paired with `idByCell[cell] = id`. The write also evicts the cell's previous id from every per-id table. The prune and the off path keep the pair consistent. The invariant holds whatever order renders, flushes and hooks run in.
- **C7, found by reading Blizzard's source:** with the same item count, `OnCooldownDataChanged` re-assigns ids in place without calling Layout. Until TBT's next pass, a frame shows its new id on its old cell. That is a permutation of whole frames, one frame per cell. It lasts two C_Timer(0) hops and is fixed by the `placedID` stamp, so it is CLOSED, with an in-game check added.
- **999.21 (STEAL-20):** merged entries never reach `ApplyCooldownSlot`/`ApplyChargeCount`, and the pooled cell is hidden. The count on screen is Blizzard's own. A spec change rebuilds the mirror, renders, then places.
- **999.22/23 (STEAL-21):** the merged path reads no aura. Each cell holds one id, positions are unique, and only frames from the container's own viewer can sit on a cell.
- **999.24 (STEAL-22):** the merged path reads no unit reaction or charm state, so no filter is left to bypass.
- **999.25 (STEAL-23):** `SlotDraws` uses `cdmShown`. `seen` counts active frames, not shown ones. The shown pass runs on UNIT_AURA and the render runs at 20 Hz. `publishWhole` keeps each entry on a stable cell.

## Gates (Task 2)
- `stylua --check .`: exit 0
- `node scripts/aura-read-gate.js`: `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`
- `node scripts/aura-read-gate.js --selftest`: `AURA-READ SELFTEST PASS (30 cases)`
- `node scripts/migrate-dryrun.js --selftest`: `SELFTEST PASS (14 cases)`
- 70-04 whole-tree sweep for deleted names: `0`
- `git ls-files --eol Core.lua Display.lua MergeMode.lua MergeReanchor.lua`: all `w/crlf`
- `git diff --stat 58deaba~1 HEAD | grep -c Bin`: `0`. The same diff for CHANGELOG.md and README.md is empty, `git log -- CHANGELOG.md README.md | grep -c "(70"` gives 0, and `git status --short` on both prints nothing.
- `./scripts/install.bat` deployed `v0.5.1-90-g2fe595e-dev` to `_retail_`, `_ptr_`, `_beta_` and `_classic_beta_`

## Deviations from Plan
None. The plan executed as written. No OPEN row, so Task 2 made no source change and has no commit.

## Observations (not changed)
- Custom cooldown trackers still use the sticky `chargeCapable` cache. This is the same shape as 999.21 but outside the merged path, so it goes to the backlog.
- A viewer TBT refused to park stays on-screen, so frames TBT releases show in Blizzard's own CDM grid. They duplicate there; they never appear over a TBT cell.
- `ns.SPELL_CATEGORY_COMBAT_POTION` is still read by `Providers.lua:783` (the Pot meta-tracker's unresolved icon). Keep it; it is not a cleanup-phase candidate. (Corrected after the 70 code review, WR-01; this line and 70-04 used to say it had no reader.)

## Deferred to Phase 72 (in-game)
The review's `## Deferred in-game checks` lists 12 items: Frost Orb charges after Arcane to Frost; another Frost Mage's Freezing; another mage's Touch of the Magi; mind control; Centered with only merged buffs and with a custom tracker added; latency when a buff lands; `/tbt merge` with Merge Mode on and off; the old slash word and the SavedVariables flag; Blizzard's visuals on moved frames; a same-count CDM reorder (C7); Merge Mode off. The TOC is unchanged, so `/reload` is enough.

## Self-Check: PASSED
- FOUND: .planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-MERGE-PATH-REVIEW.md
- FOUND: 2fe595e
