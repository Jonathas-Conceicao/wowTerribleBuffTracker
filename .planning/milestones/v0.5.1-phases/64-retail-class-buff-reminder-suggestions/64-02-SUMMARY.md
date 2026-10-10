---
phase: 64-retail-class-buff-reminder-suggestions
plan: 02
subsystem: reminders
tags: [reminder-click, secure-button, ally-cast]
requires: [64-01]
provides:
  - per-overlay unit attribute from ns:ReminderCastUnit
key-files:
  modified: [ReminderClick.lua]
key-decisions:
  - "Ally-cast rows (Symbiotic Relationship, Source of Magic) leave the overlay unit unset; every other reminder keeps unit = player"
requirements-completed: [MREM-05]
duration: short
completed: 2026-09-30
---

# Phase 64 Plan 02: Ally-cast click target Summary

ReminderClick overlays take their unit attribute from ns:ReminderCastUnit(entry), written on change only inside Place (out of combat), so the two ally-cast rows use the game's default targeting while all other reminders self-cast as in Phase 63.

## Tasks

1. Per-overlay unit attribute - commit 4942a6a (CreateOverlay no longer writes unit; Place(overlay, icon, castName, unit) writes it when overlay._unit ~= unit; Flush passes ns:ReminderCastUnit(entry); header comment updated)
2. Whole-phase gates and deploy - no file changes, so no commit

## Verification

Task 1 gate printed PASS. Task 2 gate printed PASS: `stylua --check .` clean, AURA-READ GATE PASS (10 reads, 3 readers), migrate-dryrun SELFTEST PASS (12 cases), no new flavour comparison (Core.lua buildInterfaceVersion count 3), all four touched files w/crlf. `./scripts/install.bat` deployed v0.5.0-71-g4942a6a-dev to retail, ptr, beta and classic_beta. No TOC change, so /reload suffices.

## Performance / cleanup review

Phase diff: one extra change-only attribute compare per icon per flush, no allocation, no per-frame work, no new API call. No dead code introduced.

## Phase 66 checks

- Symbiotic Relationship and Source of Magic click with a friendly target selected: cast lands on that target.
- Every other reminder (including Arcane Familiar and Arcane Intellect) still casts on the player with a friendly target selected.
- No ADDON_ACTION_BLOCKED.
- Forever offer and clicks unchanged: no 6673/465/21562 rows appear, each paladin blessing casts its own buff on the player, Blood Pact has no click.
- Retail rows (from 64-01): Devotion Aura satisfied by Concentration or Crusader Aura; Arcane Familiar and Arcane Intellect rows do not collide.

## Deviations from Plan

None - plan executed as written.

## Known Stubs

None.

## Self-Check: PASSED
