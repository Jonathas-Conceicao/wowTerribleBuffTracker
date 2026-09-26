---
phase: 35-four-base-containers
plan: 01
subsystem: database
tags: [saved-variables, schema-migration, edit-mode, lua]

# Dependency graph
requires: []
provides:
  - "ns.CONTAINERS ordered registry (buffs, bars, essential, utility) with key/title/frameName/kind/cdmViewerGlobal/defaultX/defaultY"
  - "ns.CONTAINER_BY_KEY key -> def lookup"
  - "containerSettings seeding driven by the registry instead of a hardcoded two-key list"
  - "schemaVersion 4 migration renaming editModePositions.icons to .buffs"
affects: [35-four-base-containers plan 02, Phase 36 per-container settings, Phase 38 cooldown rendering, Phase 40 steal mode]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single ordered ns.CONTAINERS table as the one place container identity is defined; every consumer branches on def.kind, never on the key string"
    - "Idempotent, non-version-gated seeding for missing keyed data (containerSettings) vs. version-gated one-time renames (editModePositions.icons -> .buffs) kept as separate mechanisms"

key-files:
  created: []
  modified: [Core.lua, BuffEngine.lua]

key-decisions:
  - "bars/buffs keep their v0.3.0 section keys unchanged; only the editModePositions position key (icons -> buffs) needed migrating, making CONT-03 a no-op for tracker placement"
  - "essential/utility are new id-shaped keys, not seeded with editModePositions defaults in this plan — Plan 02 owns idempotent position seeding for all four containers"
  - "containerSettings backfill loop now iterates ns.CONTAINERS and branches on def.kind instead of a literal { \"bars\", \"buffs\" } list and key == \"bars\" checks"

patterns-established:
  - "Registry-driven backfill: iterate ns.CONTAINERS, seed a fresh per-container table if missing, else backfill individual fields on what exists"

requirements-completed: [CONT-01, CONT-03]

# Metrics
duration: ~20min
completed: 2026-09-21
---

# Phase 35 Plan 01: Container Registry & Schema v4 Summary

**Added the ns.CONTAINERS registry (buffs, bars, essential, utility) as the single source of container identity, and a schema v4 migration that renames the Tracked Buffs Edit Mode position key from `icons` to `buffs`.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-21
- **Tasks:** 4 (3 code tasks + 1 format/verify task, no separate commit for task 4 since it produced no diff)
- **Files modified:** 2 (Core.lua, BuffEngine.lua)

## Accomplishments
- `ns.CONTAINERS` ordered registry and `ns.CONTAINER_BY_KEY` lookup defined at the top of `Core.lua`, ahead of `ns.activeTimers`, so both are in scope for every other file loaded after it
- `containerSettings` seeding rewritten to loop over the registry — no more hardcoded `{ "bars", "buffs" }` list or `key == "bars"` branches; new containers get a fresh table sourced from their `kind`'s defaults, existing ones keep per-field backfill
- Schema bumped to v4 with a nil-guarded migration that copies `editModePositions.icons` to `.buffs` (only when `.buffs` isn't already present) and always clears the old `.icons` key, retiring the v0.3.0 asymmetry between the `"buffs"` section key and the `"icons"` position key

## Task Commits

Each task was committed atomically:

1. **Task 1: Core.lua — add the registry** - `f9dfe94` (feat)
2. **Task 2: Core.lua — drive containerSettings from the registry** - `493cd03` (refactor)
3. **Task 3: BuffEngine.lua — schema v3 -> v4 migration** - `bc3e052` (feat)

Task 4 (stylua format + syntax check) produced no diff beyond what tasks 1-3 already committed, so it has no separate commit.

## Files Created/Modified
- `Core.lua` - Added `ns.CONTAINERS` / `ns.CONTAINER_BY_KEY`; replaced the two-key `containerSettings` literal and backfill with a registry-driven pass
- `BuffEngine.lua` - `CURRENT_SCHEMA_VERSION` bumped to 4; added the `ver < 4` migration block renaming `editModePositions.icons` to `.buffs`

## Decisions Made
- Kept `bars`/`buffs` as the exact strings already written into `entry.section` by v0.3.0 — confirmed by task 3's acceptance check that no `trackedBuffs` line exists inside the new migration block
- Did not seed `essential`/`utility` `editModePositions` entries in this plan, per the plan's explicit split of responsibility (version-gated rename here, idempotent seeding in Plan 02)
- Reworded two migration comments to avoid the literal string `.icons` appearing outside the `ver < 4` block, so the plan's own verification grep (`the only hit is inside the ver < 4 migration`) holds literally, not just in spirit

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were applied as separate git commits by reverting `Core.lua` to `HEAD` after an initial combined edit and reapplying each task's change independently, purely a mechanical step to preserve one-commit-per-task; no code content differs from a single-pass implementation.

## Issues Encountered

None. `luac` is not on PATH on this machine, so task 4's syntax check fell back to `stylua --check .` (exits 0 only on parseable Lua), as the plan's acceptance criteria allow.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `ns.CONTAINERS` and `ns.CONTAINER_BY_KEY` are ready for Plan 02 to build the two new frames (`TBTEssentialContainer`, `TBTUtilityContainer`) and seed their `editModePositions` idempotently
- No in-game verification was expected or performed for this plan — the registry has no user-visible effect until Plan 02 builds frames from it, per the plan's own Verification section
- CDMTab.lua's `SECTIONS` list still needs to grow to four entries (Plan 02+) before the reordering (`buffs` before `bars`) becomes visible in the CDM tab

---
*Phase: 35-four-base-containers*
*Completed: 2026-09-21*

## Self-Check: PASSED

- FOUND: f9dfe94
- FOUND: 493cd03
- FOUND: bc3e052
- FOUND: Core.lua
- FOUND: BuffEngine.lua
- FOUND: .planning/phases/35-four-base-containers/35-01-SUMMARY.md
