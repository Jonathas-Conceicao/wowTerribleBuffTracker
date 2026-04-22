---
phase: 18-trinketprovider-potprovider-buffengine-dispatch
plan: 02
subsystem: providers
tags: [lua, wow-addon, spellprovider, dispatch, buffengine, display, timers, cancellation]

# Dependency graph
requires:
  - phase: 18-trinketprovider-potprovider-buffengine-dispatch
    plan: 01
    provides: TrinketProviderMixin, PotProviderMixin with castSpellID field, static data on ns.*, ns.providers reordered
  - phase: 17-provider-skeleton-userspellprovider
    provides: SpellProviderBaseMixin, DispatchEventToProviders, UserSpellProviderMixin
provides:
  - BuffEngine.OnSpellCastSucceeded thinned to zero-branch single-line dispatcher (PROV-02, D-18/D-19)
  - ScanActiveTimersForCancellation reads timer.castSpellID with numeric type-guard and fallback to table key (D-15, D-16)
  - BuffEngine.lua free of TRINKET_SPELLS/POT_SPELLS local definitions (D-08)
  - Display.lua bar and icon layout loops index by timer.key or timer.spellID — no metaSlot dual-index (D-04)
  - Zero metaSlot references in any .lua file
affects:
  - 18-03-PLAN (integration verification — providers fully wired, Display reads new key shape)
  - 19-PLAN (LustProvider migration — OnUnitAura and StartLustTimer preserved intact)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Zero-branch OnSpellCastSucceeded — single ns:DispatchEventToProviders call routes all cast types (PROV-02)"
    - "castSpellID field on all cast procs; ScanActiveTimersForCancellation reads castSpellID with type-guard and fallback (D-15, D-16)"
    - "Display accumulator tables indexed by timer.key or timer.spellID — provider key is the lookup key (D-04)"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - Display.lua

key-decisions:
  - "OnSpellCastSucceeded branches 1 (trinket) and 2 (pot) plus eviction loops deleted — trivial overwrite in provider dispatcher replaces them (D-03, D-18, D-19)"
  - "ScanActiveTimersForCancellation now reads timer.castSpellID for source='cast' procs; type guard protects against string table keys ('trinket'/'pot') reaching GetPlayerAuraBySpellID (D-15, D-16)"
  - "Display accumulator uses timer.key or timer.spellID — covers user spells (key==numeric spellID), trinket/pot (key='trinket'/'pot'), and lust/preview procs (spellID fallback)"
  - "Static data locals (TRINKET_SPELLS, POT_SPELLS, *_ITEM_IDS, *_FALLBACK_ORDER) deleted from BuffEngine.lua; RefreshMetaIcons reads them via ns.* from Providers.lua (D-08)"

patterns-established:
  - "All cast-triggered buff types handled by provider dispatch — zero hardcoded if/elseif chains in BuffEngine event handlers"
  - "Proc carries both key (slot string/numeric) and castSpellID (numeric cast spell) as distinct fields for lookup vs cancellation"

requirements-completed: [PROV-02, LIFE-01]

# Metrics
duration: 4min
completed: 2026-04-21
---

# Phase 18 Plan 02: BuffEngine Dispatch Migration + Display Cleanup Summary

**BuffEngine.OnSpellCastSucceeded reduced to a single-line dispatcher, trinket/pot branches and eviction loops deleted, ScanActiveTimersForCancellation migrated to castSpellID read, and Display.lua metaSlot dual-index removed**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-21T04:11:31Z
- **Completed:** 2026-04-21T04:14:49Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Removed TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS, TRINKET_FALLBACK_ORDER, POT_FALLBACK_ORDER local definitions from BuffEngine.lua; RefreshMetaIcons updated to read all six via ns.* exports from Providers.lua (D-08)
- Deleted OnSpellCastSucceeded branches 1 (trinket fan-out + eviction loop) and 2 (pot fan-out + eviction loop); function body is now exactly 4 lines: 3 comment lines + 1 dispatch call (PROV-02, D-18, D-19)
- Updated ScanActiveTimersForCancellation source="cast" branch to read `timer.castSpellID or spellID` with a `type(lookupID) == "number"` guard — prevents GetPlayerAuraBySpellID being called with "trinket"/"pot" string keys (D-15, D-16)
- Removed metaSlot dual-index from both bar layout loop and icon layout loop in Display.lua; both now index by `timer.key or timer.spellID` — the fallback covers lust and preview procs which set spellID but not key (D-04)

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove static data locals from BuffEngine.lua; update RefreshMetaIcons to read from ns.*** - `4f79247` (refactor)
2. **Task 2: Remove OnSpellCastSucceeded branches 1 and 2; update ScanActiveTimersForCancellation** - `cc4dd43` (refactor)
3. **Task 3: Migrate Display.lua metaSlot dual-index reads** - `039a648` (refactor)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `BuffEngine.lua` - Static data locals deleted; RefreshMetaIcons reads ns.*; OnSpellCastSucceeded thinned to single dispatch; ScanActiveTimersForCancellation reads castSpellID with type-guard
- `Display.lua` - Bar and icon layout loops use timer.key or timer.spellID; metaSlot dual-index removed

## Decisions Made

- The `timer.key or timer.spellID` fallback in Display.lua accumulators is intentional: lust procs (StartLustTimer) and preview procs (StartAllPreviewTimers) set `spellID = "lust"` / `spellID = <dbKey>` respectively but do not set `key`. The fallback ensures these procs continue to index correctly without requiring changes to StartLustTimer or StartAllPreviewTimers (both deferred to Phase 19/21 per PITFALL-4/LUST-01 guard).
- The comment in the new bar layout loop comment was edited to avoid containing the word "metaSlot" (which would have caused the acceptance criterion grep to fail on a comment).

## Deviations from Plan

None - plan executed exactly as written. The one minor adaptation (comment wording) was cosmetic and within Claude's Discretion per CONTEXT.md.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 18-02 is complete. BuffEngine is now a thin dispatcher for all cast-triggered buff types. ns.activeTimers["trinket"] and ns.activeTimers["pot"] are written exclusively by TrinketProvider and PotProvider via the dispatch loop.
- Plan 18-03 (human-verify integration checkpoint) is ready: cast a trinket and pot in-game and verify timers appear. Double-trigger issue from Plan 18-01 is now fully resolved — BuffEngine branches deleted.
- Phase 19 (LustProvider migration) prerequisites intact: OnUnitAura, StartLustTimer, LUST-01 comment, SATED_DEBUFF_TO_LUST, CLASS_LUST_SPELL all preserved verbatim.
- No blockers.

---
*Phase: 18-trinketprovider-potprovider-buffengine-dispatch*
*Completed: 2026-04-21*
