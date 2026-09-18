---
phase: 18-trinketprovider-potprovider-buffengine-dispatch
plan: 01
subsystem: providers
tags: [lua, wow-addon, spellprovider, trinket, pot, dispatch, timers]

# Dependency graph
requires:
  - phase: 17-provider-skeleton-userspellprovider
    provides: SpellProviderBaseMixin, UserSpellProviderMixin, DispatchEventToProviders, eventToProviders map
provides:
  - TrinketProviderMixin with UNIT_SPELLCAST_SUCCEEDED handler, string key "trinket", castSpellID field
  - PotProviderMixin with UNIT_SPELLCAST_SUCCEEDED handler, string key "pot", castSpellID field
  - Static data (TRINKET_SPELLS, POT_SPELLS, *_ITEM_IDS, *_FALLBACK_ORDER) relocated to Providers.lua
  - ns.* exports preserved for BuffEngine.RefreshMetaIcons
  - ns.providers reordered to { TrinketProvider, PotProvider, UserSpellProvider }
  - castSpellID field added to UserSpellProvider proc shape (D-17)
affects:
  - 18-02-PLAN (BuffEngine branch removal uses these providers; ScanActiveTimersForCancellation reads castSpellID)
  - 18-03-PLAN (integration verification depends on providers existing)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Separate concrete mixins per meta-slot type (D-05/D-06) — TrinketProviderMixin and PotProviderMixin are independent, not parameterized"
    - "String slot key in proc.key, numeric cast spellID in proc.castSpellID — dual-field strategy (D-01, D-02)"
    - "Static data as module-locals in Providers.lua with ns.* exports for cross-file consumers (D-08, D-11)"
    - "No inventory APIs in provider OnTrigger — combat-safe (PITFALL-5)"

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "TrinketProviderMixin and PotProviderMixin are separate independent concrete mixins (D-05/D-06) — no shared parameterized base, preserving future divergence room"
  - "Proc key strategy: key='trinket'/'pot' (string slot key, D-01) + castSpellID=spellID (numeric, D-02) for cancellation scan"
  - "Static data relocated to Providers.lua via ns.* exports so BuffEngine.RefreshMetaIcons continues working unchanged (D-08, D-11)"
  - "castSpellID added to UserSpellProvider for single-path ScanActiveTimersForCancellation in Plan 18-02 (D-17)"
  - "ns.providers reordered: { TrinketProvider, PotProvider, UserSpellProvider } (D-20)"

patterns-established:
  - "Provider proc carries both key (slot string) and castSpellID (numeric cast spell) as distinct fields"
  - "Providers.lua owns static spell/item data; namespace exports make it accessible without tight coupling"

requirements-completed: [PROV-02, LIFE-01]

# Metrics
duration: 2min
completed: 2026-04-21
---

# Phase 18 Plan 01: TrinketProvider + PotProvider + Providers Registry Summary

**TrinketProviderMixin and PotProviderMixin added to Providers.lua with string slot keys, castSpellID fields, relocated static spell/item data tables, and ns.providers reordered to { TrinketProvider, PotProvider, UserSpellProvider }**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-21T04:07:18Z
- **Completed:** 2026-04-21T04:09:17Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- TrinketProviderMixin and PotProviderMixin added as independent concrete mixins (D-05), each handling UNIT_SPELLCAST_SUCCEEDED with procs keyed by string slot key ("trinket"/"pot") and castSpellID field
- Static data (TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS, TRINKET_FALLBACK_ORDER, POT_FALLBACK_ORDER) relocated from BuffEngine.lua to Providers.lua with all ns.* exports preserved for BuffEngine.RefreshMetaIcons (D-08, D-11)
- ns.providers reordered to { TrinketProvider, PotProvider, UserSpellProvider } per D-20; eventToProviders map rebuild loop unchanged, picks up new providers automatically
- castSpellID field added to UserSpellProviderMixin proc (D-17) so all three cast-triggered providers emit the same field — enables single-path ScanActiveTimersForCancellation in Plan 18-02

## Task Commits

Each task was committed atomically:

1. **Task 1: Add TrinketProviderMixin + PotProviderMixin, relocate static data, rebuild providers registry** - `1e1aed2` (feat)
2. **Task 2: Add castSpellID field to UserSpellProviderMixin proc (D-17)** - `644bb1e` (feat)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `Providers.lua` - Added TrinketProviderMixin, PotProviderMixin, static data block, ns.* exports, updated ns.providers registry and comment; added castSpellID to UserSpellProviderMixin proc

## Decisions Made

- Proc shape uses string slot key (`key = "trinket"/"pot"`) for activeTimers keying and numeric castSpellID as a separate field for aura cancellation lookup — deliberate dual-field strategy per D-01/D-02, not redundancy
- GetPreviewInfo/GetAtRestInfo on TrinketProviderMixin and PotProviderMixin left as inherited base no-ops — Phase 20 (PROV-04) adds them; current Display/CDMTab use ns:GetAtRestMetaIcon for at-rest icons
- ns.TRINKET_FALLBACK_ORDER and ns.POT_FALLBACK_ORDER exported on ns (NEW in this plan) to give BuffEngine a clean read site after Plan 18-02 removes the locals from BuffEngine.lua

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 18-01 is complete and committed. Providers.lua now has all three UNIT_SPELLCAST_SUCCEEDED providers registered.
- Plan 18-02 can now: remove BuffEngine.OnSpellCastSucceeded branches 1 and 2 (trinket and pot), update ScanActiveTimersForCancellation to read castSpellID from proc, and remove the local TRINKET_SPELLS/POT_SPELLS definitions from BuffEngine.lua (reading from ns.* exports instead).
- Double-trigger is the current intermediate state (both BuffEngine branches AND providers fire on trinket/pot casts) — acceptable because Plan 18-02 lands in the same phase and removes the branches.
- No blockers.

---
*Phase: 18-trinketprovider-potprovider-buffengine-dispatch*
*Completed: 2026-04-21*
