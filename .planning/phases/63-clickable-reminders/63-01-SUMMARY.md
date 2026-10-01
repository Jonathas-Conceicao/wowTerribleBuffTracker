---
phase: 63-clickable-reminders
plan: 01
subsystem: reminders
tags: [reminders, cast-spell, tracker-fields]
requires: []
provides:
  - "ns:ReminderCastID(entry) -> number | nil"
  - "def.castID on META_REMINDER_DEFS rows (Blood Pact false)"
  - "TRACKER_FIELDS castID Advanced field (reminders only)"
affects: [63-02]
key-files:
  modified: [Providers.lua, CDMTab.lua]
requirements-completed: [CLICK-06]
completed: 2026-09-30
---

# Phase 63 Plan 01: Reminder Cast Spell Summary

Every reminder now has a resolvable cast spell: table-driven `castID` for built-ins (Blood Pact opts out with `false`), an editable "Cast spell ID" Advanced field for user reminders, and one resolver `ns:ReminderCastID`.

## Tasks

1. Built-in cast spells and resolver (Providers.lua) - commit 89e44e7
2. "Cast spell ID" Advanced field (CDMTab.lua) - commit see git log (feat(63-01) second commit)

## Deviations from Plan

None - plan executed as written. The castID field omits the secrecy badge as specified, and duplicates auraID's preview row (left for Phase 65 cleanup).

## Verification

stylua clean; both files remain CRLF in the working tree; aura-read-gate PASS; migrate-dryrun selftest PASS (12 cases); BuffEngine.lua untouched.

## Known Stubs

None.

## Self-Check: PASSED
