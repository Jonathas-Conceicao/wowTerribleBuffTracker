---
status: complete
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
source: [70-VERIFICATION.md, 70-MERGE-PATH-REVIEW.md]
started: 2026-10-10
updated: 2026-10-10
---

## Current Test

[awaiting human testing — deferred to Phase 72 by user decision for the 67-71 autonomous run.
The full list of 12 in-game checks is in 70-MERGE-PATH-REVIEW.md; the essentials are below.]

## Tests

### 1. Merge Mode still works with the old path gone
expected: Merge Mode places and previews every merged entry; target changes and spec changes raise no Lua error; `/tbt reanchor` just opens settings; `/tbt merge` prints shown / visible / cell without errors.
result: pass — retail (2026-10-10): `/tbt merge` prints Visibility and shown/visible/cell per entry without error; the `/tbt reanchor` check was dropped — its leftover load-time cleanup was removed instead (prototype-only, never released)

### 2. 999.21 — charges after a spec change
expected: Arcane → Frost (or any spec swap): a merged charge spell such as Frost Orb shows Blizzard's own, correct charge count without `/reload`.
result: pass — retail (2026-10-10): Frost Orb charges correct after Arcane → Frost and a loadout change

### 3. 999.22 / 999.23 — another player's debuff
expected: With another Frost Mage in the group, Freezing never overlaps other cells; another mage's Touch of the Magi on your target never lights your entry.
result: pass — retail raid and M+ (2026-10-10): other casters' debuffs no longer appear on the player's CDM entries.

### 4. 999.24 — mind control
expected: While mind-controlled, no merged cell turns into a debuff it does not own; nothing paints over every cell.
result: pass — retail (2026-10-10): mind-controlled during a fight, no cell changed.

### 5. 999.25 — Centered
expected: A Centered container holding only merged buffs re-centres as buffs come and go.
result: pass — retail (2026-10-10)

### 6. Merged bars (review IN-03)
expected: Merged bars sit on their rows during play; the Edit Mode placeholder for a bar still shows its icon and name.
result: pass — retail (2026-10-10)

### 7. Merge Mode off / on without /reload
expected: Turning Merge Mode off returns every frame to Blizzard's viewers; turning it back on re-places them.
result: pass — retail (2026-10-10)

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0

## Gaps

None yet.
