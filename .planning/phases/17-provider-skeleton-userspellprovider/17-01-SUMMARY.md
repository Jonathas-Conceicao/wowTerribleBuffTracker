---
phase: 17-provider-skeleton-userspellprovider
plan: 01
subsystem: addon-core
tags: [lua, wow-addon, spellprovider, mixins, dispatch, coexistence]

# Dependency graph
requires:
  - phase: 16-research-v0.2.4
    provides: SpellProvider interface contract, ActiveProc shape, dispatch table pattern, pitfall documentation

provides:
  - Providers.lua: SpellProviderBaseMixin (4-method interface), UserSpellProviderMixin (concrete impl), ns.providers registry, ns:DispatchEventToProviders dispatch helper
  - eventToProviders: static dispatch map built once at file load, O(1) lookup per event
  - ns.SpellProviderBaseMixin and ns.UserSpellProviderMixin exported for future extension

affects:
  - 17-02 (BuffEngine wiring — will call ns:DispatchEventToProviders for user-spell casts)
  - 18-trinket-provider (will prepend TrinketProvider to ns.providers)
  - 19-pot-lust-providers (will prepend PotProvider and LustProvider to ns.providers)
  - 22-display-unification (will consume normalized proc shape from providers)
  - 23-cdmtab-unification (will call GetPreviewInfo/GetAtRestInfo via ns.providers)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CreateFromMixins flat copy for provider instances — no metatable, no shared state between instances"
    - "Static dispatch map (eventToProviders) built once at file load — O(1) per-event lookup"
    - "Provider interface contract: GetEventInterests, OnTrigger, GetPreviewInfo, GetAtRestInfo"
    - "Coexistence pattern: Providers.lua adds NEW code only; BuffEngine.lua untouched until Plan 17-02"

key-files:
  created:
    - Providers.lua
  modified:
    - TerribleBuffTracker.toc

key-decisions:
  - "UserSpellProvider handles only numeric-keyed trackedBuffs entries; string keys (trinket/pot/lust) reserved for Phase 18-19 meta providers"
  - "OnTrigger returns extended timer shape (startedAt, section, layoutOrder, spellID) for coexistence with existing Display.lua consumers"
  - "Dispatch map built once at module load — never rebuilt per-event (PITFALL-7 performance trap avoided)"
  - "ns:DispatchEventToProviders writes directly to ns.activeTimers and calls ns:UpdateDisplay inline (same pattern as BuffEngine.OnSpellCastSucceeded)"

patterns-established:
  - "SpellProvider base mixin: SpellProviderBaseMixin = {} with stub GetEventInterests/OnTrigger/GetPreviewInfo/GetAtRestInfo"
  - "Concrete provider construction: CreateFromMixins(SpellProviderBaseMixin, ConcreteMixin) — flat copy, PITFALL-7 safe"
  - "Event dispatch: eventToProviders local table maps event string to provider list, built once after ns.providers is populated"
  - "ActiveProc includes both key (proc table key) and spellID (aura lookup) fields per PITFALL-2 dual-key design"

requirements-completed:
  - PROV-03

# Metrics
duration: 2min
completed: 2026-04-19
---

# Phase 17 Plan 01: Provider Skeleton and UserSpellProvider Summary

**SpellProviderBaseMixin interface + UserSpellProviderMixin concrete implementation registered in ns.providers, with static eventToProviders dispatch map and ns:DispatchEventToProviders export — coexists with BuffEngine without modifying it**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-19T21:01:32Z
- **Completed:** 2026-04-19T21:04:44Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created Providers.lua with the full 4-method SpellProvider interface contract on both the base and concrete mixins
- Implemented UserSpellProviderMixin to handle numeric-keyed trackedBuffs entries with section="hidden" guard, v0.2.3 timer shape compatibility, and proper UNIT_SPELLCAST_SUCCEEDED filtering
- Wired the static eventToProviders dispatch map and exported ns:DispatchEventToProviders — the entry point Plan 17-02 will call from BuffEngine's user-spell branch
- Added Providers.lua to TerribleBuffTracker.toc immediately after BuffEngine.lua and before EditModeFrames.lua, establishing correct load order for all future consumers

## Task Commits

1. **Task 1: Create Providers.lua with SpellProviderBaseMixin and UserSpellProviderMixin** - `3288380` (feat)
2. **Task 2: Add Providers.lua to TerribleBuffTracker.toc load order** - `c13d746` (chore)

## Files Created/Modified

- `Providers.lua` — SpellProviderBaseMixin (stub interface), UserSpellProviderMixin (user-spell concrete impl), ns.providers registry (`{ UserSpellProvider }`), eventToProviders local dispatch table, ns:DispatchEventToProviders export
- `TerribleBuffTracker.toc` — Providers.lua inserted between BuffEngine.lua and EditModeFrames.lua

## Decisions Made

- **UserSpellProvider returns extended ActiveProc shape** (startedAt, section, layoutOrder, spellID fields) in addition to the normalized shape. This preserves coexistence with Display.lua which reads these fields directly from ns.activeTimers. The extra fields are harmless and will be cleaned up when Display is unified in Phase 22.
- **ns:DispatchEventToProviders calls ns:UpdateDisplay inline** after each proc write, matching the existing pattern in BuffEngine.OnSpellCastSucceeded. This avoids a separate UpdateDisplay call site in Plan 17-02.
- **eventToProviders is a module-local table** (not on ns) — it is implementation detail of the dispatch helper and does not need to be exposed. Only ns:DispatchEventToProviders is exported.

## Deviations from Plan

None — plan executed exactly as written. All code from the plan's `<action>` blocks was used verbatim. The only stylua formatting pass was required per CLAUDE.md workflow.

## Issues Encountered

None.

## Pitfalls Avoided

| Pitfall | Avoidance |
|---------|-----------|
| PITFALL-1 (Schema break) | No writes to ns.db.trackedBuffs; no CURRENT_SCHEMA_VERSION change; providers read existing keys as-is |
| PITFALL-5 (Combat lockdown) | No GetInventoryItemID, C_Item.GetItemCount, or InCombatLockdown in constructors or OnTrigger |
| PITFALL-7 (Metatable GC pressure) | CreateFromMixins flat copy only; no setmetatable anywhere in file |

## Interface Methods Defined on SpellProviderBaseMixin

1. `SpellProviderBaseMixin:GetEventInterests()` — returns `{}` stub; override in concrete provider
2. `SpellProviderBaseMixin:OnTrigger(event, ...)` — returns `nil` stub; override in concrete provider
3. `SpellProviderBaseMixin:GetPreviewInfo(key)` — returns `nil` stub; override in concrete provider
4. `SpellProviderBaseMixin:GetAtRestInfo(key)` — returns `nil` stub; override in concrete provider

## ns.providers Registry Contents

```lua
ns.providers = { UserSpellProvider }  -- exactly one entry in Phase 17
```

`UserSpellProvider = CreateFromMixins(SpellProviderBaseMixin, UserSpellProviderMixin)` — flat mixin copy, no shared state.

## ns:DispatchEventToProviders Export

Entry point for Plan 17-02. Signature:

```lua
function ns:DispatchEventToProviders(event, ...)
-- Returns: number of procs handled (0 if no provider interested in event)
```

BuffEngine Plan 17-02 will call this from the user-spell branch of OnSpellCastSucceeded, replacing the direct timer write.

## Next Phase Readiness

- Plan 17-02 can proceed: `ns:DispatchEventToProviders` is defined, `ns.providers` is populated, load order is correct
- BuffEngine.lua is unmodified — existing v0.2.3 behavior is 100% intact
- No user testing required for this plan; Plan 17-02's human-verify checkpoint will validate the dispatch wiring end-to-end

## Known Stubs

None. All methods are either fully implemented (UserSpellProviderMixin) or intentionally return nil/empty (SpellProviderBaseMixin base stubs — these are the interface contract, not display-path stubs). The base stubs will be overridden by concrete providers in Phases 18-19; no data flows to UI from the base stubs.

---

*Phase: 17-provider-skeleton-userspellprovider*
*Completed: 2026-04-19*
