---
phase: 07-safety-infrastructure
plan: 01
subsystem: aura-tracking
tags: [lua, wow-addon, unit-aura, c_secrets, event-handling, debug-logging]

# Dependency graph
requires: []
provides:
  - UNIT_AURA event registered via RegisterUnitEvent (player-only filter)
  - ns.auraCheckBlocked flag: set when C_Secrets.ShouldAurasBeSecret() returns true, cleared on PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA
  - ns.previewActive flag: set in StartAllPreviewTimers, cleared in ClearAllTimers
  - ns.debugLogging flag: runtime-only toggle via /tbt debug
  - ns:OnUnitAura stub with full guard ordering (secret -> isFullUpdate -> previewActive)
  - ns:ClearAuraBlock resets blocked flag with debug logging
  - PLAYER_ENTERING_WORLD stays persistently registered (no more one-shot unregister)
affects: [08-aura-scan, 09-zone-transition]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RegisterUnitEvent instead of RegisterEvent for UNIT_AURA (kernel-level player filter)"
    - "Guard ordering in OnUnitAura: secret check first, then isFullUpdate, then previewActive"
    - "Runtime-only flags on ns namespace (not persisted to TerribleBuffTrackerDB)"
    - "Subcommand parsing via msg:lower():match() for extensible /tbt slash command"

key-files:
  created: []
  modified:
    - Core.lua
    - BuffEngine.lua

key-decisions:
  - "Extended existing eventFrame (D-03 choice) rather than creating a separate frame — keeps event routing as a thin dispatcher to ns: methods"
  - "PLAYER_REGEN_ENABLED included as unblock trigger per D-04 — re-blocks immediately on next UNIT_AURA if M+ auras still secret; no spurious cancellations possible"
  - "Guard order in OnUnitAura is critical contract for Phase 8: secret -> isFullUpdate -> previewActive -> [scan]"
  - "ns.previewActive initialized at module scope because StartAllPreviewTimers existed without this flag"

patterns-established:
  - "Pattern: OnUnitAura guard ordering — always: (1) ShouldAurasBeSecret, (2) isFullUpdate, (3) previewActive, (4) scan logic"
  - "Pattern: Runtime-only flags initialized at module scope in BuffEngine.lua, not in InitBuffEngine or DB"

requirements-completed: [AURA-01, AURA-02, AURA-03, ZONE-02]

# Metrics
duration: 2min
completed: 2026-04-04
---

# Phase 07 Plan 01: Safety Infrastructure Summary

**UNIT_AURA event infrastructure with C_Secrets blocking, isFullUpdate suppression, preview guard, and /tbt debug toggle — all safety gates wired before Phase 8 scan logic**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-04T04:22:28Z
- **Completed:** 2026-04-04T04:22:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Wired UNIT_AURA registration (player-filtered via RegisterUnitEvent), PLAYER_REGEN_ENABLED, and ZONE_CHANGED_NEW_AREA events into Core.lua
- Added ns:OnUnitAura stub with the correct guard ordering (secret check -> isFullUpdate -> previewActive) that Phase 8 inherits
- Added ns:ClearAuraBlock with debug logging; added ns.previewActive wiring to StartAllPreviewTimers and ClearAllTimers
- Removed PLAYER_ENTERING_WORLD one-shot unregister so the event persists across loading screens

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire event registration, routing, and debug slash command in Core.lua** - `fc41a95` (feat)
2. **Task 2: Add guard flags, OnUnitAura stub, ClearAuraBlock, and preview wiring in BuffEngine.lua** - `f604fd1` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `Core.lua` - Added RegisterUnitEvent for UNIT_AURA, PLAYER_REGEN_ENABLED, ZONE_CHANGED_NEW_AREA event handlers; removed PLAYER_ENTERING_WORLD unregister; extended /tbt slash command with debug subcommand
- `BuffEngine.lua` - Added ns.auraCheckBlocked/previewActive/debugLogging flags at module scope; added ns:OnUnitAura stub with full guard chain; added ns:ClearAuraBlock; wired previewActive in StartAllPreviewTimers and ClearAllTimers

## Decisions Made

- Extended existing eventFrame (D-03) — consistent with established routing pattern, no complexity cost
- Included PLAYER_REGEN_ENABLED as an unblock trigger per D-04 — re-block on next UNIT_AURA handles M+ re-restriction safely
- Guard ordering in OnUnitAura established as the contract for Phase 8: secret check first (prevents Lua errors on secret value access), isFullUpdate second (prevents zone-boundary false cancellations), previewActive third (prevents preview timer disruption)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All guard infrastructure is in place for Phase 8 (aura scan logic)
- Phase 8 adds ns:ScanActiveTimersForCancellation() call inside the existing stub after the previewActive guard
- PLAYER_ENTERING_WORLD now persistent — ready for Phase 9 zone-transition scan (ZONE-01)
- Blocker in STATE.md resolved: ns.previewActive confirmed absent in source and added in this plan

---
*Phase: 07-safety-infrastructure*
*Completed: 2026-04-04*
