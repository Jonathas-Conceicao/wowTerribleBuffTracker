---
phase: 53-naming-scheme-saved-data-migration
plan: 01
subsystem: testing
tags: [migration, schema-versioning, node, saved-variables, wow-addon]

# Dependency graph
requires: []
provides:
  - "scripts/migrate-dryrun.js --selftest: a node-runnable, exit-code-gated spec for schema v7 (legacy racial re-key) and v8 (canonical kind + <kind>:<id> re-key)"
  - "KIND / META_KEY constant tables (userBuff, userCd, metaSkill, metaSkillCd, metaItem, userItem; metaSkill:lust, metaItem:trinket, metaItem:pot) that plan 53-02 must reproduce byte-identically in Core.lua"
  - "extractRacialSpells(): a brace-depth reader of Providers.lua's RACIAL_SPELLS, proving the v8 classification table never needs a hardcoded copy of the racial spell list"
affects: [53-02, 53-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Node mirror of a Lua schema migration, read live off the Lua source it classifies against (fs.readFileSync + brace-depth scan) instead of a hand-copied constant table"
    - "Move-not-rebuild fixture assertions: object identity (===) between pre- and post-migration Map entries is the primary correctness signal, not just field equality"
    - "Self-verifying test harness: one case (case E) exists solely to prove the comparator used by the other cases can report a failure, so a PASS cannot come from a vacuous assertion"

key-files:
  created: []
  modified:
    - "scripts/migrate-dryrun.js - extended from a v4/v5/v6-only dry-run to a v4-v8 mirror with embedded fixtures and a --selftest mode"

key-decisions:
  - "Meta ids for this phase (Claude's discretion per 53-CONTEXT): metaSkill:lust, metaItem:trinket, metaItem:pot -- must stay byte-identical in Core.lua (plan 53-02)"
  - "migrateV7 keeps the legacy literal prefix 'racial:' (not a shared constant), matching the 53-CONTEXT rule that old migration blocks freeze their own literals so a later helper rename cannot change what an old step produces"
  - "migrateV8's cd:N -> metaSkillCd vs userCd classification checks ANY race's RACIAL_SPELLS membership, never the current character's race, per 53-CONTEXT 'Migration shape'"
  - "A numeric key with trackerType 'cooldown' (defensive-only; v6 should already have re-keyed it to cd:<id>) is classified identically to a cd:N key in v8, rather than left untouched, per the plan's interfaces block"

requirements-completed: [NAME-02]

# Metrics
duration: 11min
completed: 2026-09-28
---

# Phase 53 Plan 01: Schema v7 + v8 Dry-Run Selftest Summary

**Node mirror of BuffEngine.lua's schema v7 (legacy racial re-key) and new v8 (canonical `<kind>:<id>` re-key), reading the racial spell catalogue live off Providers.lua, with a 5-case `--selftest` proving move-not-rebuild, gating, idempotency, and that the comparator itself can fail.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-09-28T10:51:18Z (previous commit, plan creation)
- **Completed:** 2026-09-28T11:01:53Z
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments
- `extractRacialSpells()` reads `RACIAL_SPELLS` straight out of `Providers.lua` via a brace-depth scan (skipping strings and `--` comments), so the classification table this script uses to tell a racial cooldown from a user cooldown can never drift from the Lua data — and throws loudly if the table is ever renamed or moved, rather than silently classifying everything as `userCd`.
- `migrateV7` mirrors `ns:MigrateRacialKeys` exactly: literal `>= 7` gate, defers entirely on an unreadable race, moves (never rebuilds) the `racial`/`racial2` slot tables onto `racial:<spellID>`.
- `migrateV8` implements the full classification table from the plan's interfaces block, including the defensive "numeric key with trackerType cooldown" case, backfilling `spellID`/`itemID` only when absent, and dropping (never clobbering) on a key collision.
- `node scripts/migrate-dryrun.js --selftest` runs five hard-assertion cases against two embedded fixtures (a ten-tracker v0.4.1-shaped database and a pre-v7 legacy two-slot database) and exits 0 only when every tracker lands on its canonical key with object identity preserved.

## Task Commits

Each task was committed atomically:

1. **Task 1: Mirror schema v7 and v8 in the dry-run, with RACIAL_SPELLS read live from Providers.lua** - `6c4008f` (test)
2. **Task 2: Embedded v0.4.1 / pre-v7 fixtures and the --selftest assertion runner** - `cb91a7b` (test)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `scripts/migrate-dryrun.js` - extended with `KIND`/`META_KEY` constants, `extractRacialSpells()`, `migrateV7()`, `migrateV8()`, a `migrate()` wrapper shared by both CLI and selftest modes, two embedded SavedVariables fixtures, and a five-case `--selftest` runner

## Decisions Made
- Meta ids `metaSkill:lust`, `metaItem:trinket`, `metaItem:pot` chosen at Claude's discretion (53-CONTEXT explicitly delegates exact spelling), kept exactly as the plan's interfaces block specifies so plan 53-02's Lua constants can match byte-for-byte.
- `assertMoved`'s per-field comparison also asserts no field appears on the post-migration entry that wasn't present before (except the one documented backfill), catching an accidental extra write as a failure rather than letting it pass silently.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria were run verbatim and all passed on the first implementation; no auto-fixes were needed.

## TDD Gate Compliance

Both tasks are `tdd="true"` and the plan frontmatter is `type: tdd`, but this plan's sole deliverable **is** the test/spec itself — there is no separate production code in this plan for the test to drive. The plan's own objective states it is "written FIRST, from the locked decisions in 53-CONTEXT.md, so it is the specification the Lua migration in plan 53-02 is reconciled against in plan 53-05 — not a transcription of whatever the Lua ends up doing." Both commits are therefore `test(53-01): ...` and no `feat(53-01): ...` commit exists in this plan; the GREEN gate (the Lua implementation this selftest specifies) belongs to plan 53-02, and the RED/GREEN reconciliation between the two happens in plan 53-05. This is expected, not a gap.

## Issues Encountered

None. `node scripts/migrate-dryrun.js --selftest` passed all 5 cases on first run after Task 2; `extractRacialSpells()` was sanity-checked against the live `Providers.lua` (12 races, race 2 correctly yielding Blood Fury / Shatter Curse in source order) before the fixtures were written.

## Human Verification Needed

None for this plan — it is a node script with no WoW client dependency, fully verified by its own `--selftest` exit code. The dry-run itself is only a prediction; the real in-game logout/login verification is plan 53-05's responsibility (NAME-02), not this plan's.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`scripts/migrate-dryrun.js --selftest` is the executable spec plan 53-02's Lua migration (`ns:MigrateRacialKeys` v7 pin + new v8 block, `ns.KIND`/`ns.META_KEY` constants in Core.lua) must reconcile against in plan 53-05. The `KIND`/`META_KEY` string values in this file are the literal strings plan 53-02 must reproduce byte-identically. No blockers.

---
*Phase: 53-naming-scheme-saved-data-migration*
*Completed: 2026-09-28*
