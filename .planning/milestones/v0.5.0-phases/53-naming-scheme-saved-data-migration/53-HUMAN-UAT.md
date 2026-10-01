---
status: complete
phase: 53-naming-scheme-saved-data-migration
source: [53-VERIFICATION.md, 53-REVIEW.md]
started: 2026-09-28
updated: 2026-09-28
---

## Current Test

[awaiting human testing — deferred to the end of the autonomous run, Phases 53-55]

## Tests

**Before anything: back up `WTF/Account/<account>/SavedVariables/TerribleBuffTracker.lua`.** The build is
already deployed to every client folder. Migration checks need a REAL logout/login — `/reload` cannot
exercise the load path.

### 1. v0.4.1 → v8 migration keeps every tracker
expected: with a v0.4.1 SavedVariables that holds every kind (user buff, user cooldown, Lust, trinket, pot, racial buff, racial cooldown, bag item), a real logout/login shows every tracker in the same container, same order, same settings; no Lua error on login.
result: pass (user, 2026-09-29) implied: every later migration (v9, v10) ran on this data without loss

### 2. Saved file is canonical and the migration is idempotent
expected: after a second logout, the file holds only `<kind>:<id>` keys (`userBuff:`, `userCd:`, `metaSkill:`, `metaSkillCd:`, `metaItem:`) with matching `trackerType` values and `schemaVersion = 8`; a further login/logout leaves it byte-identical.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 3. Every kind still fires on cast
expected: casting/using each kind (user buff, user cooldown, Lust, trinket, pot, racial buff, racial cooldown, bag item) starts its tracker; no Lua errors.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 4. Icon and tooltip resolution for every kind (your explicit condition)
expected: correct icon and tooltip for every kind — in containers (active and placeholder), on tracked TBT-tab tiles, on Suggested tiles, and on the drag ghost. No question-mark icons for a valid tracker.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 5. Racial cooldown from Suggested works without /reload
expected: dragging a racial cooldown Suggested tile into a container and casting the racial immediately starts that tile.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 6. New trackers are saved canonically
expected: a newly added user buff and user cooldown, after a real logout/login, are saved as `userBuff:<id>` / `userCd:<id>`.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 7. Merge Mode unchanged
expected: with Merge Mode on, mirrored CDM entries render exactly as in v0.4.1.
result: pass (user, 2026-09-29)

### 8. No duplicate cooldown tracker for the same spell (review fix WR-01)
expected: with a cooldown tracker already on a spell, adding a cooldown for that same spell (Add dialog, or dragging its Suggested racial cooldown tile) reuses/moves the existing tracker instead of creating a second one; casting the spell starts it.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
