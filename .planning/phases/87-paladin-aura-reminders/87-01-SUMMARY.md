---
phase: 87
plan: 01
requirements: [PAURA-01, PAURA-02, PAURA-03, PAURA-04, DOC-08]
commits: [5dbc64a]
mode: inline (data-only phase; the orchestrator planned and executed it directly from 87-CONTEXT.md)
---

# Phase 87 Plan 01: Paladin Aura Reminders — Summary

## What changed

- **Providers.lua, Forever rows (PAURA-01):** `MetaReminderRow(10301, 0)` Retribution,
  `(19746, 0)` Concentration, `(19896, 0)` Shadow Resistance, `(19898, 0)` Frost Resistance,
  `(19900, 0)` Fire Resistance, beside the existing Devotion 10293 (key unchanged; its comment no
  longer says "any aura satisfies it, one-way"). Each ends "(unverified in game)".
- **Forever group (PAURA-02):** the existing 22-ID `MetaReminderGroup(10293, 465, ...)` call is
  unchanged in IDs; with six of its IDs now rows, each row gets the other 21 as alternatives, so any
  aura of any rank hides every aura reminder. Comment updated.
- **Retail (PAURA-03):** `MetaReminderRow(317920, 0, nil, nil, nil, { client = "retail" })` and
  `(32223, ...)` declared before the existing top-level `MetaReminderGroup(465, 317920, 32223)`,
  which now makes the three mutual. Retribution 183435 not added.
- **PAURA-04:** a scan of every `MetaReminderRow` call finds only 1459 (the existing `both` row) in
  both client sets; no aura ID is shared. Keys `metaReminder:10293` / `metaReminder:465` unchanged.
- **docs/REMINDERS.md (DOC-08):** five Forever paladin rows and two retail rows, each "Paladin auras
  group, below"; the Forever group paragraph now links 10293 and says it hides every aura reminder;
  a retail "Paladin auras group" paragraph added. "(stands for any paladin aura)" removed.
- **REMINDERS-NOT-INCLUDED.md:** retail Retribution Aura 183435 added (Sanctity Aura was already
  listed); verification status lists the v0.5.7 rows as unverified until Phase 89.

## Gates

- `node scripts/reminders-doc-check.js`: PASS (133 Forever IDs, 15 retail IDs, 46 rows; 46 code
  rows: forever 33, retail 12, both 1; 19 groups).
- `--selftest`: PASS (46 cases). `node scripts/aura-read-gate.js`: PASS.
- `stylua .`: no diff. `git ls-files --eol`: Providers.lua, docs/REMINDERS.md and the research file
  still `w/crlf`.

## Post-commit performance review

Data only: rows and a comment, built once at load. No runtime code path changed.
