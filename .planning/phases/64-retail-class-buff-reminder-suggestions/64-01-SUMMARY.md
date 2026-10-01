---
phase: 64-retail-class-buff-reminder-suggestions
plan: 01
subsystem: reminders
tags: [metaReminder, retail, class-buffs, providers]
requires: []
provides:
  - per-row client tag (forever/retail/both) on MetaReminderRow
  - nine retail class-buff rows plus Arcane Familiar, Devotion Aura alternatives
  - ns:ReminderCastUnit (ally-cast rows answer nil)
affects: [ReminderClick.lua (plan 64-02), Phase 66 in-game checks]
key-files:
  modified: [Providers.lua, Core.lua, CDMTab.lua]
key-decisions:
  - "Client tag reads ns.CLIENT_IS_FOREVER only; off-client rows are never registered (one point), so they are not offered and a placed one is an orphan"
  - "Arcane Familiar has no alternative 1459; it hides through aura 210126"
requirements-completed: [MREM-04, MREM-05]
duration: short
completed: 2026-09-30
---

# Phase 64 Plan 01: Retail class-buff reminder rows Summary

Retail class-buff reminders as built-in metaReminder rows with a per-row client tag read from ns.CLIENT_IS_FOREVER, per-row aura IDs, an ally-cast flag and Devotion Aura alternatives; Forever's registered rows are unchanged.

## Tasks

1. Row schema (client, auraID, allyCast), per-row offer, ns:ReminderCastUnit - commit 20b2c83
2. Retail rows, Devotion group, Arcane Intellect tagged both, comment updates in Core.lua and CDMTab.lua - see git log (second feat(64-01) commit)

## Verification

Both task automated gates printed PASS; `node scripts/aura-read-gate.js` PASS (10 reads, 3 readers); `node scripts/migrate-dryrun.js --selftest` PASS (12 cases); `stylua .` clean; `git ls-files --eol` shows w/crlf on all three files.

## Deviations from Plan

None - plan executed as written. (Header comment in Providers.lua was edited in Task 2 as specified; one stale-comment tweak to the ApplyMetaReminderDef comment was folded into Task 1.)

## Known Stubs

None.

## Self-Check: PASSED
