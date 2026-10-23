---
status: complete
phase: 67-remove-racials
source: [67-VERIFICATION.md]
started: 2026-10-10
updated: 2026-10-10
---

## Current Test

[awaiting human testing — deferred to Phase 72 by user decision for the 67-71 autonomous run]

## Tests

### 1. No racial Suggested tile on any client
expected: Retail and Forever — the CDM settings window's TBT Buffs and Cooldowns tabs offer no racial tile (no Berserking, Blood Fury, Eureka!, Shadowmeld, ...). Lust, trinket, pot, class-buff reminder and bag-item tiles are still there.
result: pass — Forever (2026-10-10)

### 2. Saved racial trackers removed silently, everything else intact
expected: Log in on Forever with the current SavedVariables (which holds racial trackers; dry run drops 26, keeps 25). No Lua error, no chat message, no racial icon or bar in any container, and every other tracker keeps its container, order and settings. `/reload` is enough (no TOC change in Phase 67).
result: pass — Forever (2026-10-10)

### 3. No ghost icons or stale timers after the migration
expected: Casting a former racial spell starts nothing in TBT; no empty placeholder cell is left where a racial tracker used to be.
result: pass — Forever (2026-10-10)

### 4. `/tbt debug` still works without the racial collection tooling
expected: Toggles ON/OFF with no error; a spell cast prints one SPELL line, a potion or trinket use one ITEM line; no AURA GAINED / NO AURA / RACE line appears.
result: pass — Forever (2026-10-10)

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0

## Gaps

None yet.
