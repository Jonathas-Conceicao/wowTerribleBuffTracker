---
phase: 67-remove-racials
plan: 03
subsystem: debug-and-engine
tags: [racials, debug, aura-gate, lua]
requires: ["67-01"]
provides:
  - "Debug cast log with SPELL and ITEM lines only"
  - "Aura-read gate with two allowlisted readers"
  - "BuffEngine.lua with no proc.stacks or proc.indefinite readers"
affects: [67-04, 67-05]
key-files:
  modified:
    - Core.lua
    - scripts/aura-read-gate.js
    - BuffEngine.lua
key-decisions:
  - "ns.INDEFINITE_DURATION and ns.cooldownOverrides left in place for Plan 04"
requirements-completed: [RACE-12]
duration: 15min
completed: 2026-10-10
---

# Phase 67 Plan 03: Racial debug tooling and engine readers Summary

The Phase 49 racial collection tooling is gone from Core.lua, the aura-read gate passes with ns:ReadPlayerAura and TryResolveFromSpellID as its only readers, and BuffEngine.lua no longer reads proc.stacks or proc.indefinite.

## Tasks

| Task | Commit | Notes |
| ---- | ------ | ----- |
| 1. Debug collection tooling and allowlist row | ce161f1 | Core.lua, scripts/aura-read-gate.js |
| 2. Engine stacks and indefinite readers | bd217b6 | BuffEngine.lua |

## What changed

- Core.lua: deleted the buff-scan block (CollectPlayerBuffs, ReadCastCooldown, LogNewPlayerAuras and their state tables), ns:LogPlayerRace, ns:BaselinePlayerAuras, the 0.35s timer in ns:LogPlayerCast, and the race/baseline calls in the `/tbt debug` branch. SafeNumber, SafeString, SpellName, ItemName, ItemEffectSpellID, LogItemUse and the four hooks all keep readers.
- scripts/aura-read-gate.js: CollectPlayerBuffs allowlist row and its header wording removed ("two" readers).
- BuffEngine.lua: dropped the RACE-10 comment, the preview `stacks` copy, `proc.indefinite` in the expiry sweep, `timer.indefinite` in ns:ReminderInLead, and racial wording in AcquireProc and preview comments.

## Acceptance criteria

All met: no racial-collection identifiers in Core.lua (0); ITEM, SPELL and ns:LogPlayerCast present; CollectPlayerBuffs in the gate 0; `aura-read-gate.js` PASS (4 reads in 2 readers) and `--selftest` PASS (30 cases); BuffEngine.lua `stacks` 0, indefinite readers 0, racial offer names 0, Shadowmeld/Find Treasure/Plainsrunning 0, `ns.INDEFINITE_DURATION = 86400` still 1; `migrate-dryrun.js --selftest` PASS (13 cases); stylua exit 0; all three files `w/crlf`.

## Deviations from Plan

None - plan executed as written. A first scripted edit of the gate file failed on quoting and was redone with the Edit tool; no file was affected.

## Deferred to Phase 72 (human, in-game)

`/tbt debug` toggles ON/OFF with no error; casting prints one SPELL line, using a potion or trinket one ITEM line, and no AURA GAINED, NO AURA or RACE line appears.

## Known Stubs

None.

## Self-Check: PASSED

Both commits exist; STATE.md and ROADMAP.md untouched.
