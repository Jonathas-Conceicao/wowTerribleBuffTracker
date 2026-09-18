---
phase: 22-display-lua-unification
plan: 03
subsystem: ui
tags: [cdmtab, metaIconsDirty, verification, cleanup, in-game]

# Dependency graph
requires:
  - phase: 22-02
    provides: "Display.lua with metaIconsDirty readers + clearer deleted; per-widget icon cache (cachedSpellID/cachedIcon) makes flag redundant"
provides:
  - "metaIconsDirty flag fully removed from the entire addon — zero references across all .lua files (D-25 complete)"
  - "Phase 22 refactor runtime-confirmed via 12-step in-game verification matrix — APPROVED"
  - "DISP-01 + DISP-03 runtime-confirmed correct behavior across all four buff types"
  - "PROV-F3 fully satisfied: Phase 20 provider-owned RefreshAtRest + Phase 22 unified Display codepath"
affects: [23-cdmtab-unification, 24-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "metaIconsDirty flag pattern RETIRED — invalidation now implicit via cachedSpellID change detection in Display.lua"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "metaIconsDirty writer deleted (D-25): with numeric proc.spellID always populated and per-widget icon cache keyed by spellID, the flag is redundant — cache invalidation fires naturally when bar.cachedSpellID ~= info.spellID"
  - "CDMTab Phase 23 shims left in place: ns:GetAtRestMetaInfo, ns:ResolveSuggestedSpellID, ns:GetAtRestMetaIcon call sites in CDMTab preserved (Phase 23 territory); ns.CLASS_LUST_SPELL and ns.GetHunterLustSpell exports preserved (Phase 23 demotion)"

patterns-established:
  - "Per-widget icon cache (cachedSpellID/cachedIcon) on bar/icon frames replaces any dirty-flag approach — spellID-keyed change detection is sufficient and simpler"

requirements-completed: [DISP-01]

# Metrics
duration: ~2min code + human verification
completed: 2026-04-21
---

# Phase 22 Plan 03: CDMTab metaIconsDirty Writer Deletion + Phase 22 In-Game Verification Summary

**Deleted the lone orphaned `ns.metaIconsDirty = true` setter from CDMTab.lua StartPreview — completing the Phase 22 flag removal — then confirmed zero visual regression across all four buff types via a 12-step in-game verification matrix (APPROVED)**

## Performance

- **Duration:** ~2 min (code) + human verification
- **Started:** 2026-04-21T21:46:58Z
- **Completed:** 2026-04-21 (verification APPROVED)
- **Tasks:** 3 (Task 1: CDMTab edit, Task 2: install.bat, Task 3: human-verify checkpoint — APPROVED)
- **Files modified:** 1

## Accomplishments

- Deleted 2 lines from CDMTab.lua StartPreview: the `-- Signal placeholder icons need a refresh...` comment and the `ns.metaIconsDirty = true` setter — completing D-25 (final writer deletion)
- Zero `metaIconsDirty` references remain across the entire addon (CDMTab.lua, Display.lua, BuffEngine.lua, Providers.lua, Core.lua, EditModeFrames.lua — all grep-clean)
- Deployed to WoW via install.bat; human verifier ran the full 12-step in-game matrix and reported APPROVED with zero regressions
- DISP-01 runtime-confirmed: zero type-discriminating branches; all four buff types (trinket, pot, user-spell, lust) render identically to Phase 21
- DISP-03 runtime-confirmed: single ns:ShowBuffTooltip handler supplies correct spell tooltips for both active timers and at-rest placeholders
- PROV-F3 fully satisfied by the combined Phase 20 (provider-owned RefreshAtRest + ns:GetDisplayInfoForKey) and Phase 22 (unified Display codepath) work
- Phase 21 architectural behavior preserved: mid-CDM real cast persists after CDM close (ns.previewTimers/ns.activeTimers separation intact through refactor)

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete ns.metaIconsDirty setter line in CDMTab.lua:20 (and preceding comment)** - `43f5410` (feat)
2. **Task 2: Deploy to WoW via install.bat** — no code commit (install-only step)
3. **Task 3: Human verification checkpoint** — APPROVED (captured in 22-VERIFICATION.md)

## Files Created/Modified

- `CDMTab.lua` — 2 lines removed: orphaned comment + `ns.metaIconsDirty = true` setter from StartPreview body (D-25); StartPreview sequence preserved: RefreshMetaIcons → RefreshTBTSections → ns.configOpen = true → StartAllPreviewTimers

## Decisions Made

- metaIconsDirty writer deleted without replacement (D-25 / D-26 rationale): per-widget `bar.cachedSpellID ~= info.spellID` detection in Display.lua already handles cache invalidation on trinket swap. The flag was the last remnant of an older eager-invalidation approach that became redundant when Plan 22-02 introduced spellID-keyed caching.
- CDMTab Phase 23 shims left untouched per plan scope: `ns:GetAtRestMetaInfo` (CDMTab.lua line ~86), `ns:ResolveSuggestedSpellID` (multiple CDMTab sites), `ns:GetAtRestMetaIcon` (multiple CDMTab sites) remain for Phase 23 migration. `ns.CLASS_LUST_SPELL` and `ns.GetHunterLustSpell` exports on the namespace remain for Phase 23 demotion.

## Deviations from Plan

None — plan executed exactly as written.

## In-Game Verification Outcome

**Status: APPROVED** — all 12 steps passed, zero visual regression vs Phase 21.

User report (verbatim):
> APPROVED — all 12 test steps passed:
> 1. Trinket cast: bar + icon + tooltip correct
> 2. Pot cast: bar + countdown + tooltip correct
> 3. User-spell: bar/icon + tooltip correct
> 4. Lust: 40s bar with class-aware icon + tooltip
> 5. Individual buff cancellation works (aliveBuffs path)
> 6. Lust group cancellation works (SHARED_LUST_BUFFS_LOCAL path)
> 7. Preview mode: all 4 types render correctly with real durations
> 8. Mid-CDM real cast persists after close (Phase 21 preserved)
> 9. At-rest tooltip on placeholders works
> 10. Trinket-swap icon cache refresh works
> 11. Zero Lua errors
> 12. Edit Mode regression clean
>
> Zero visual regression vs Phase 21. Phase 22 refactor successful.

Full 12-step test matrix documented in `.planning/phases/22-display-lua-unification/22-VERIFICATION.md`.

## Phase 22 Final Grep Sweep

All four Phase 22 ROADMAP success criteria confirmed at code level:

1. **DISP-01** — Zero `metaIconsDirty`, `metaSlot`, `ResolveSuggestedSpellID`, or type-discriminating branches in Display.lua — runtime-confirmed APPROVED
2. **All four buff types render correctly** — runtime-confirmed APPROVED (steps 1-4)
3. **DISP-03** — Single `ns:ShowBuffTooltip` handler for bar + icon OnEnter — runtime-confirmed APPROVED (steps 1-4, 9)
4. **wipe() accumulator pattern preserved** — verified in Plan 22-02 (not touched in this plan)

Phase-level grep sweep (run at Task 3 pre-checkpoint):
- `metaIconsDirty` across all .lua: zero hits
- `type(...) == "string"` discriminating branch in Display.lua: zero hits
- `ShowBuffTooltip` definition + call sites in Display.lua: present
- `aliveBuffs` in Providers.lua + BuffEngine.lua: present

## Phase 23 Todo (preserved, not scope of Phase 22)

The following CDMTab.lua sites are intentionally left for Phase 23:
- `ns:GetAtRestMetaInfo` call at CDMTab.lua line ~86 (tooltip resolution)
- `ns:ResolveSuggestedSpellID` calls at CDMTab.lua lines ~94, ~439, ~794 (Suggested section icon + tooltip)
- `ns:GetAtRestMetaIcon` calls at CDMTab.lua lines ~435, ~790 (icon resolution)
- `ns.CLASS_LUST_SPELL` / `ns.GetHunterLustSpell` exports — still used by CDMTab Suggested section; Phase 23 demotes them after CDMTab migration

## Next Phase Readiness

- Phase 22 is complete — all 3 plans executed and APPROVED in-game
- Phase 23 (CDMTab.lua Unification) is unblocked: `ns:ShowBuffTooltip` is live and ready for CDMTab migration; `ns:GetDisplayInfoForKey` already exported
- Phase 24 (Cleanup) depends on Phase 23

---
*Phase: 22-display-lua-unification*
*Completed: 2026-04-21*
