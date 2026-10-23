---
phase: 67-remove-racials
plan: 01
subsystem: migration
tags: [savedvariables, schema-migration, racials, lua, node]
requires: []
provides:
  - "Schema v12 (ns:MigrateDropRacials) dropping saved racial trackers by key shape"
  - "Catalogue-free v7 and v8 migrations"
  - "scripts/migrate-dryrun.js v12 mirror with 13 selftest cases"
affects: [67-02, 67-03, 67-04, 67-05]
tech-stack:
  added: []
  patterns: ["collect-then-delete migration", "frozen literal key patterns instead of ns.KIND"]
key-files:
  created: []
  modified:
    - scripts/migrate-dryrun.js
    - BuffEngine.lua
    - Core.lua
key-decisions:
  - "Racials identified by key shape only: metaSkill:<digits>, metaSkillCd:<digits>, racial, racial2; metaSkill:lust kept"
  - "v7 drops legacy slots; v8 classifies every legacy cooldown as userCd; removal is silent"
  - "ns:MigrateReminderAlternatives pinned to literal 11"
requirements-completed: [MIG-03]
duration: 25min
completed: 2026-10-10
---

# Phase 67 Plan 01: Schema v12 racial removal Summary

Schema v12 drops saved racial trackers by key shape (`metaSkill:<id>`, `metaSkillCd:<id>`, `racial`, `racial2`) while keeping `metaSkill:lust` and every other tracker. v7 and v8 no longer read the racial catalogue or the player's race.

## Tasks

| Task | Commit | Notes |
| ---- | ------ | ----- |
| 1. Dry-run spec: catalogue-free v7/v8, v12 | 20c100a | `extractRacialSpells`, `--race`, `META_SKILL_CD` removed; `migrateV12`, Fixture R and M added; selftest at 13 cases |
| 2. Lua migration v12, catalogue-free v7/v8, no retry | cca3cca | `CURRENT_SCHEMA_VERSION = 12`; `ns:MigrateDropRacials` last migration function; `ns:CooldownKindFor` and the PLAYER_ENTERING_WORLD migration retry removed from Core.lua |

## Acceptance criteria

All checked and met: `SELFTEST PASS (13 cases)`; zero hits for `extractRacialSpells|RACIAL_SPELLS|--race|raceID|META_SKILL_CD` in the JS; `CURRENT_SCHEMA_VERSION = 12` (1); `function ns:MigrateDropRacials()` (1); `ns:MigrateDropRacials()` count 2; `RacialDefsRaw|CooldownKindFor|UnitRace` in BuffEngine.lua 0; `PLAYER_ENTERING_WORLD` in BuffEngine.lua 2; `CooldownKindFor` in Core.lua 0; `ns:Migrate*()` calls in Core.lua 0; `"^metaSkillCd:%d+$"` 1; `stylua` exit 0; `.lua` and `.js` CRLF in the working tree (`w/crlf`).

## Dry-run against the real Forever file (`_classic_beta_`, read-only)

```
schemaVersion in  : 11
v12: <26 lines, one per racial key> dropped (racial)
schemaVersion out : 12
trackers dropped  : 26 -> metaSkillCd:20552, metaSkill:20594, metaSkillCd:7744, metaSkillCd:1299026,
  metaSkillCd:20572, metaSkill:20580, metaSkillCd:20594, metaSkill:1259799, metaSkill:1259705,
  metaSkillCd:20600, metaSkillCd:20549, metaSkillCd:1259799, metaSkill:20577, metaSkill:1299038,
  metaSkill:20600, metaSkill:1299026, metaSkillCd:20589, metaSkill:20589, metaSkillCd:1259705,
  metaSkillCd:20580, metaSkill:2481, metaSkillCd:1259718, metaSkillCd:20577, metaSkill:20572,
  metaSkillCd:1259817, metaSkill:1259817
trackers kept     : 25 -> userBuff:774, metaItem:5512, metaReminder:25291, metaItem:929, metaItem:2455,
  metaItem:3827, userReminder:1244, metaItem:4358, metaReminder:9885, metaItem:2459, metaReminder:1459,
  metaReminder:25780, userBuff:12824, metaItem:217495, metaItem:2456, metaReminder:25290,
  metaReminder:9910, metaItem:3385, userCd:12051, metaItem:858, metaReminder:11767,
  metaReminder:20217, metaItem:118, userReminder:1302285, userReminder:7302
positions kept    : essential, utility, buffs, bars, user1, reminders
```

The `_retail_` files: account `76116961#1` is v11 with no racial trackers (`v12: no racial trackers`, 25 kept including `metaSkill:lust`); account `76116961#2` is v3 and runs the whole chain to 12 with nothing dropped.

## Deliberate consequence

A pre-v8 (v0.4.x) racial cooldown tile (`cd:<n>`) now migrates to a user cooldown (`userCd:<n>`), because no catalogue exists to identify it as racial. It carries no racial kind for v12 to recognise.

## Deviations from Plan

None. The TDD red step for Task 1 was not run separately: the spec and its selftest were written in one pass and went green together.

## Deferred to Phase 72 (human, in-game)

- On Forever, log in with the current SavedVariables: no Lua error, racial tiles gone from every container, every other tracker keeps its container, order and settings.
- `/reload` is enough after `./scripts/install.bat` (no TOC change); install happens in Plan 05.

## Known Stubs

None.

## Self-Check: PASSED

Commits 20c100a and cca3cca exist; modified files present; STATE.md and ROADMAP.md untouched.
