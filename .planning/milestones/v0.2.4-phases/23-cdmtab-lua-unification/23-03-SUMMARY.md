---
phase: 23-cdmtab-lua-unification
plan: "03"
subsystem: providers
tags: [lua, providers, refactor, lust, cleanup]

requires:
  - phase: 23-cdmtab-lua-unification
    plan: "02"
    provides: CDMTab migrated to ns:GetDisplayInfoForKey("lust") — no external CLASS_LUST_SPELL/GetHunterLustSpell readers remain

provides:
  - Providers.lua: CLASS_LUST_SPELL and GetHunterLustSpell fully module-local (no ns.* export)
  - Pending todo 2026-04-21-demote-remaining-lust-constants-to-provider-local.md moved to done/

affects:
  - 23-04-deploy-verify (runtime validation of class-aware lust icon resolution)

tech-stack:
  added: []
  patterns:
    - "Provider data is provider-internal: exported ns.* constants reduced to zero for lust internals"

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "D-18: ns.CLASS_LUST_SPELL demoted to local CLASS_LUST_SPELL in Providers.lua"
  - "D-19: ns.GetHunterLustSpell demoted to local function GetHunterLustSpell; LustProviderMixin:GetDisplayInfo reads bare locals"
  - "D-20: Pre-demotion repo-wide grep confirmed zero external readers (excluding agent worktrees)"
  - "D-21: Pending todo moved from .planning/todos/pending/ to .planning/todos/done/"

patterns-established:
  - "Grep-gate before ns.* demotion: always verify zero external readers before removing export"

requirements-completed: [DISP-02]

duration: 10min
completed: 2026-04-21
---

# Phase 23 Plan 03: Lust Constants Demotion Summary

**CLASS_LUST_SPELL and GetHunterLustSpell demoted from ns.* exports to Providers.lua module-locals after D-20 grep gate confirmed zero external readers**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-21T00:00:00Z
- **Completed:** 2026-04-21T00:10:00Z
- **Tasks:** 2
- **Files modified:** 1 (Providers.lua) + 1 todo file relocated

## Accomplishments

- D-20 grep gate passed: zero external readers of ns.CLASS_LUST_SPELL / ns.GetHunterLustSpell outside Providers.lua in project source files
- D-18: ns.CLASS_LUST_SPELL → local CLASS_LUST_SPELL with updated comment explaining Phase 23 rationale
- D-19: function ns.GetHunterLustSpell → local function GetHunterLustSpell; LustProviderMixin:GetDisplayInfo now reads bare local names without ns. prefix
- D-21: todo file moved from .planning/todos/pending/ to .planning/todos/done/
- stylua clean; no behavioral change

## Task Commits

1. **Task 1: Pre-demotion grep verification gate (D-20)** — verification only, no commit (no files changed)
2. **Task 2: Demote CLASS_LUST_SPELL and GetHunterLustSpell; move todo** — `14fd931` (refactor)

## Files Created/Modified

- `Providers.lua` — Lines 215-234: ns.CLASS_LUST_SPELL → local CLASS_LUST_SPELL; ns.GetHunterLustSpell → local function GetHunterLustSpell; lines 517-520: LustProviderMixin:GetDisplayInfo reads updated to use bare local names
- `.planning/todos/done/2026-04-21-demote-remaining-lust-constants-to-provider-local.md` — relocated from pending/

## Decisions Made

- D-20 grep returned hits only in `.claude/worktrees/` (agent sandbox copies) — confirmed these are not project source; gate passed
- SATED_DEBUFF_TO_LUST and SHARED_LUST_BUFFS_LOCAL left untouched per D-25/D-26
- Display.lua, BuffEngine.lua, CDMTab.lua, Core.lua all untouched

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The D-20 grep returned results only from `.claude/worktrees/` (agent sandbox), not from project source files. Gate correctly passed.

## Known Stubs

None — all lust resolution wired through LustProviderMixin:GetDisplayInfo with the now-local helpers.

## Next Phase Readiness

- Plan 23-04 (deploy + in-game verification) is the final gate for Phase 23
- Class-aware lust icon (Bloodlust / Time Warp / Fury of the Aspects / Primal Rage / Harrier's Cry) requires runtime verification per D-24
- All providers unchanged externally; no API surface modifications

---
*Phase: 23-cdmtab-lua-unification*
*Completed: 2026-04-21*
