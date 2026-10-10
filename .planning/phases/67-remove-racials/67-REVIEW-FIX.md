---
phase: 67-remove-racials
fixed_at: 2026-10-10T14:57:02Z
review_path: .planning/phases/67-remove-racials/67-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 67: Code Review Fix Report

**Fixed at:** 2026-10-10T14:57:02Z
**Source review:** .planning/phases/67-remove-racials/67-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (WR-01, IN-02, IN-03, IN-04, IN-05; IN-01 excluded by orchestrator decision, accepted edge case)
- Fixed: 5
- Skipped: 0

Gates after all fixes: `node scripts/migrate-dryrun.js --selftest` PASS (13 cases), `node scripts/aura-read-gate.js` PASS, `--selftest` PASS (30 cases), `stylua --check .` clean, and `git ls-files --eol` shows `w/crlf` on every touched file.

## Fixed Issues

### WR-01: v0.4.x racial cooldown tiles survive the upgrade as user cooldowns, breaking MIG-03

**Files modified:** `BuffEngine.lua`, `scripts/migrate-dryrun.js`
**Commit:** c5c7e2b
**Status:** fixed: requires human verification (migration logic change)
**Applied fix:** `ns:MigrateKindKeys` (v8) has a new function-local frozen literal, `LEGACY_RACIAL_CD`, holding 18 spellIDs: 20600, 1259718, 20572, 1299026, 20594, 20580, 1259799, 20577, 7744, 20549, 20552, 1259817, 20589, 20554, 1260270, 1259416, 1259705, 1259686. They were recovered from `git show 8d64c7e:Providers.lua` (`RACIAL_SPELLS`) and are every row that carries a `cooldown`. The v0.4.1, v0.5.0 and v0.5.1 tags hold the same set, and v0.4.0 holds a subset of it. 2481 (Find Treasure) and 1299038 (Plainsrunning) are left out because they never had a cooldown tile. A legacy cooldown whose id is in this list is now dropped silently in v8 (record deleted, `ns:ClearTrackerRuntimeState`), in both shapes: `"cd:<N>"` and the defensive numeric-key `trackerType == "cooldown"`. The pre-phase v8 classified both shapes as racial through `ns:CooldownKindFor`. Dropping in v8 avoids minting a `metaSkillCd` key that `ns:TrackerKey` no longer knows, and it skips the "could not migrate tracker" print. `migrateV8` in `migrate-dryrun.js` mirrors this with an identical `LEGACY_RACIAL_CD` Set. Fixture A now expects 7 surviving trackers, not 9: `cd:20572` and `cd:20554` are removed from `FIXTURE_A_MOVES`, and a new assertion checks that no `cd:`/`userCd:` 20572/20554 survives. Fixture R's `userCd:20572` (a schema-11 user cooldown) still survives v12 as before. The list applies only to pre-v8 keys.

### IN-02: Stale comment still describes the removed one-cast cooldown override

**Files modified:** `Display.lua`
**Commit:** a861b04
**Applied fix:** Reworded the `ApplyUserCooldown` comment to "Read through ns:CooldownDuration, the one entry point for a cooldown's length (Core.lua)". The removed override is no longer mentioned.

### IN-03: Stale v7 call-site comment says v7 still re-keys

**Files modified:** `BuffEngine.lua`
**Commit:** 6e7a13b
**Applied fix:** Replaced the three-line comment with `Schema v7 (49-03): drops the legacy "racial"/"racial2" slots (Phase 67). Runs before v8.`

### IN-04: v12 clears runtime state piecemeal instead of using the shared helper

**Files modified:** `BuffEngine.lua`
**Commit:** 014d5f5
**Applied fix:** `ns:MigrateDropRacials` now calls `ns:ClearTrackerRuntimeState(key)` in place of the hand-copied `ReleaseProc`/`activeTimers`/`cooldownStarts` clears. Every table the helper touches (`previewTimers`, `auraState`, and the others) is created at file load, ahead of ADDON_LOADED, and `MarkCooldownsDirty` is nil-guarded inside the helper.

### IN-05: Redundant disjunct in the case D field assertion

**Files modified:** `scripts/migrate-dryrun.js`
**Commit:** a7ba413
**Applied fix:** The assertion is now just `after.get(field) === before[field]`.

---

_Fixed: 2026-10-10T14:57:02Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
