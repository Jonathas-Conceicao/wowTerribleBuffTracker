---
phase: 82-other-class-rows
plan: 01
subsystem: reminders
tags: [forever, metaReminder, class-buffs, alternatives]
requires:
  - phase: 80 (Forever group block, MetaReminderGroup one-way alternatives)
  - phase: 81 (mage armor and familiar rows and groups, baseline 7451564)
provides:
  - Thirteen Forever reminder rows (MREM-08..16)
  - Seven Forever-block group calls (exclusive groups and rank alternatives, RALT-07)
affects: [Providers.lua reminder table, Suggested offers on Forever]
tech-stack:
  added: []
  patterns: [data-only MetaReminderRow / MetaReminderGroup rows, one-way alternatives for IDs without a row]
key-files:
  created: []
  modified: [Providers.lua]
key-decisions:
  - "Rows grouped by class with a column-0 class comment line above each run; Demonic Sacrifice last"
  - "Long paladin aura call written on one line and split by stylua, no comment inside it"
requirements-completed: [MREM-08, MREM-09, MREM-10, MREM-11, MREM-12, MREM-13, MREM-14, MREM-15, MREM-16]
metrics:
  duration: ~10 min
  completed: 2026-11-09
  tasks: 2
  files: 1
---

# Phase 82 Plan 01: Other Class Rows Summary

Forever warlock armors, shaman shields, priest Inner Fire/Shadowform/Shadowguard/Shadow Protection,
one "any aura" paladin row (10293), one "any aspect" hunter row (25296), the mage Amplify/Dampen
pair and Demonic Sacrifice (aura 18789) as reminder rows, with seven group calls inside the
`if ns.CLIENT_IS_FOREVER` block. Retail unchanged.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Thirteen Forever rows and the header note (MREM-17, Soul Link, Sanctity Aura left out) | f2d9416 | Providers.lua |
| 2 | Seven group calls appended to the Forever block; stylua, gates, deploy | eed9197 | Providers.lua |

## Verification

- `node .planning/phases/82-other-class-rows/82-check-rows.js` (baseline 7451564): all checks passed, exit 0
- `node scripts/aura-read-gate.js`: AURA-READ GATE PASS (1 reads in 1 allowlisted readers)
- `stylua .` then `stylua --check .`: clean
- `git ls-files --eol Providers.lua`: `i/lf w/crlf attr/text eol=crlf`, no CRCRLF (gate check)
- `git diff --name-only f2d9416~1 HEAD` outside `.planning`: Providers.lua only; CHANGELOG.md untouched
- `./scripts/install.bat`: deployed to _retail_, _ptr_, _beta_, _forever_, _classic_era_

## Code Trace

- **Retail:** every new row uses the default forever client, so `MetaReminderRow` returns before
  registering it (`client == "forever" and isForever` is false). The Forever block is skipped. The
  gate shows every other row, the outside group call `MetaReminderGroup(465, 317920, 32223)` and the
  baseline block calls byte-identical, and 465 in code outside the block only on the two retail
  lines that already had it (2 vs 2).
- **Forever:** the rows register before the block runs (the block sits after every
  `MetaReminderRow` call), so each new group call finds its rows in `metaReminderDefsBySpellID`.
  IDs with no row (465 on Forever, the rank IDs, Pack/Wild/Beast/Monkey/Cheetah, 976/10957/27683,
  18790-18792) are one-way alternatives. `ns:ApplyMetaReminderDef` applies them at every
  `ns:RebuildCastIndex`; no migration. No Forever row ID is in two calls (gate check).
- **Demonic Sacrifice:** a `UNIT_SPELLCAST_SUCCEEDED` of 18788 starts the row through the cast index
  (castID defaults to 18788); the aura watch uses `def.auraID` 18789, copied onto the entry by
  `ns:ApplyMetaReminderDef` (Providers.lua `entry.auraID = def.auraID`).
- **Shadowguard:** no knownID argument, so knownID is 19312 and `ns:ResolveSpellKnown(def.knownID)`
  offers and loads it only for a priest who knows a rank.
- **Permanent rows** 15473, 10293, 25296: `minutes = 0` gives `duration = nil`, the same shape as
  the retail Devotion row.
- In-game checks are Phase 85's; every new row keeps "(unverified in game)".

## Deviations from Plan

None - plan executed exactly as written.

## Post-commit Review

Data-only change in load-time table code; no hot path, allocation or dead code introduced. The
22-ID paladin watch list is the accepted T-82-05 cost (read only while the buff is absent).

## Known Stubs

None.

## Self-Check: PASSED

- Providers.lua contains `MetaReminderRow(18788, 120, nil, nil, nil, { auraID = 18789 })` and `MetaReminderGroup(18788, 18790, 18791, 18792)`
- Commits f2d9416 and eed9197 exist on `milestone/v0.5.6-more-forever-reminders`
