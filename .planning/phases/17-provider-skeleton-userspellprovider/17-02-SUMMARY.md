---
phase: 17-provider-skeleton-userspellprovider
plan: 02
subsystem: addon-core
tags: [lua, wow-addon, spellprovider, dispatch, buffengine, coexistence, human-verify]

# Dependency graph
requires:
  - phase: 17-provider-skeleton-userspellprovider (Plan 01)
    provides: Providers.lua with ns:DispatchEventToProviders and UserSpellProvider already wired

provides:
  - BuffEngine.OnSpellCastSucceeded: user-spell branch (branch 3) replaced by ns:DispatchEventToProviders call
  - Phase 17 end-to-end dispatch path verified in-game: UNIT_SPELLCAST_SUCCEEDED → BuffEngine → DispatchEventToProviders → UserSpellProvider:OnTrigger → ns.activeTimers

affects:
  - 18-trinket-provider (TrinketProvider will prepend to ns.providers; BuffEngine branch 1 will be removed)
  - 19-pot-lust-providers (PotProvider/LustProvider migration; BuffEngine branches 2 + OnUnitAura will be removed)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Branch replacement coexistence: only branch 3 of OnSpellCastSucceeded replaced; branches 1 (trinket) and 2 (pot) preserved for Phase 18 migration"
    - "Dispatch call synthesizes unit='player' and castGUID=nil — Core.lua already filtered to player before invoking OnSpellCastSucceeded"

key-files:
  created: []
  modified:
    - BuffEngine.lua

key-decisions:
  - "Only branch 3 (user-spell path) replaced in Phase 17; branches 1 and 2 remain until Phase 18 migrates TrinketProvider and PotProvider"
  - "Dispatch call passes unit='player' and castGUID=nil — Core.lua pre-filters events to player; UserSpellProvider ignores castGUID"
  - "Trinket/pot preview 0-second duration is a known pre-existing bug deferred to Phase 20/21 (PITFALL-4) — not a Phase 17 regression"

patterns-established:
  - "Surgical branch replacement: remove only the target code block; leave all other branches, functions, and tables intact until their dedicated migration phase"

requirements-completed:
  - PROV-03

# Metrics
duration: ~5min (Task 1 automated) + human-verify (approved same session)
completed: 2026-04-19
---

# Phase 17 Plan 02: BuffEngine Dispatch Wiring and In-Game Verification Summary

**BuffEngine.OnSpellCastSucceeded branch 3 (user-spell inline path) replaced by ns:DispatchEventToProviders call; Phase 17 end-to-end dispatch verified in-game with user-spell, hidden guard, trinket, pot, and preview all confirmed correct**

## Performance

- **Duration:** ~5 min (Task 1) + human-verify turnaround
- **Started:** 2026-04-19
- **Completed:** 2026-04-19
- **Tasks:** 2 (1 automated code change, 1 human-verify checkpoint)
- **Files modified:** 1 (BuffEngine.lua) + install.bat out-of-band fix (see Deviations)

## Accomplishments

- Replaced BuffEngine.OnSpellCastSucceeded branch 3 (lines ~391-415, the inline user-spell timer write) with a single `ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)` call
- Trinket branch (branch 1, TRINKET_SPELLS fan-out) and pot branch (branch 2, POT_SPELLS fan-out) preserved intact — no Phase 18 work started
- All preservation checks passed: OnUnitAura with LUST-01 pre-gate ordering, StartLustTimer, StartAllPreviewTimers (direct trackedBuffs iteration, PITFALL-4), ScanActiveTimersForCancellation, ClearAllTimers, CURRENT_SCHEMA_VERSION = 3
- User approved in-game: cast detection fires correctly via dispatch path, hidden guard works, trinket/pot timers unaffected, preview mode shows non-hidden entries

## Task Commits

1. **Task 1: Replace BuffEngine.OnSpellCastSucceeded branch 3 with dispatcher call** - `d2f21f2` (feat)
2. **Task 2: User in-game verification** - APPROVED (no code commit; human-verify checkpoint)

**Out-of-band:** `6fc0baa` — install.bat fix adding Providers.lua to deploy file list (see Deviations)

## Files Created/Modified

- `BuffEngine.lua` — OnSpellCastSucceeded branch 3 replaced; all other functions and tables unchanged

## Decisions Made

- Only branch 3 replaced in Phase 17; branches 1 and 2 preserved intact until Phase 18 when TrinketProvider and PotProvider are introduced and their corresponding BuffEngine branches are removed
- Dispatch call synthesizes `unit="player"` and `castGUID=nil` because Core.lua already pre-filters to `unit == "player"` before invoking OnSpellCastSucceeded, and UserSpellProvider ignores castGUID

## Deviations from Plan

### Out-of-Band Fix

**1. [Rule 3 - Blocking] install.bat was missing Providers.lua in deploy file list**

- **Found during:** Task 1 (deploy via ./scripts/install.bat after code change)
- **Issue:** Providers.lua (created in Plan 17-01) was not listed in install.bat's copy commands, so it was not being deployed to the WoW addons folder
- **Fix:** Added Providers.lua to install.bat deploy list
- **Files modified:** scripts/install.bat
- **Verification:** install.bat ran without error; WoW loaded Providers.lua successfully (confirmed by in-game test — no load error)
- **Committed in:** `6fc0baa` (separate out-of-band commit, not part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (blocking — missing deploy file)
**Impact on plan:** Required for in-game verification to pass. No scope creep.

## User Verification Outcome (Task 2)

**Status: APPROVED**

Steps verified by user in-game:

| Step | Description | Result |
|------|-------------|--------|
| Step 1 | Addon loads without Lua error | PASS |
| Step 2 | /tbt opens; Suggested section shows correct icons | PASS |
| Step 3 | Cast tracked user spell → timer bar appears; recast resets timer | PASS |
| Step 4 | section="hidden" guard: hidden spell produces no timer; re-enabling restores timer | PASS |
| Step 5 | Trinket cast → timer bar with correct icon and name | PASS |
| Step 6 | Pot cast → timer bar with correct icon and name | PASS |
| Step 7 | Lust detection | PASS (lust detection confirmed working) |
| Step 8 | Preview mode shows non-hidden tracked buffs | PASS — trinket/pot preview shows 0-second bars (known pre-existing bug, see below) |

**Phase 17 Success Criteria: all four satisfied.**

## Known Deferred Issues

**Trinket/pot preview 0-second duration** — Preview mode (StartAllPreviewTimers) shows 0-second bars for trinket and pot meta-buffs. This is a pre-existing bug from v0.2.3 (PITFALL-4 / LIFE-03). It is NOT a Phase 17 regression — the behavior matches v0.2.3 exactly. Fix is deferred to Phase 20 (GetPreviewInfo) and Phase 21 (Preview Mode Migration).

## Pitfalls Avoided

| Pitfall | Avoidance |
|---------|-----------|
| PITFALL-1 (Schema break) | CURRENT_SCHEMA_VERSION = 3 unchanged; no DB writes |
| PITFALL-2 (Timer identity) | proc.key == spellID for user spells — dual-key trivially satisfied; Display reads spellID field which is preserved |
| PITFALL-4 (Preview regression) | StartAllPreviewTimers not touched; still iterates ns.db.trackedBuffs directly |
| PITFALL-5 (Combat lockdown) | No inventory or item API calls added |
| PITFALL-6 (LUST-01 ordering) | OnUnitAura with LUST-01 pre-gate comment preserved intact |
| PITFALL-7 (Metatable GC pressure) | No metatable changes; no new table allocations on hot path |

## Issues Encountered

None beyond the install.bat deviation documented above.

## Next Phase Readiness

Phase 17 is complete. Phase 18 can proceed:

- `ns.providers` is populated with UserSpellProvider; the registry accepts prepend operations for TrinketProvider and PotProvider
- BuffEngine.OnSpellCastSucceeded branches 1 (trinket) and 2 (pot) remain intact — Phase 18 will remove them after their respective providers are wired
- `ns:DispatchEventToProviders` is proven to work end-to-end for user spells — confidence in dispatch loop is established before touching trinket/pot paths
- Preview migration (StartAllPreviewTimers → provider iteration) is deferred to Phase 21 (LIFE-03)
- Lust UNIT_AURA path migration is deferred to Phase 19 (LustProvider + UNIT_AURA Dispatch)

**Remaining concern:** LUST-01 pre-gate ordering can only be fully verified in Mythic+ where ShouldAurasBeSecret() returns true. Flagged in STATE.md blockers for real M+ testing post-Phase 19 deployment.

---

*Phase: 17-provider-skeleton-userspellprovider*
*Completed: 2026-04-19*
