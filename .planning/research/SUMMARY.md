# Project Research Summary

**Project:** TerribleBuffTracker v0.2.4 -- SpellProvider/ActiveProc Refactor
**Domain:** WoW Midnight addon -- provider abstraction over a manual buff timer system
**Researched:** 2026-04-18
**Confidence:** HIGH

## Executive Summary

TerribleBuffTracker currently detects four buff types (user spells, trinkets, pots, lust) through three separate branches in OnSpellCastSucceeded and a distinct OnUnitAura lust path. Icon resolution is duplicated six or more times across BuffEngine.lua, Display.lua, and CDMTab.lua. The v0.2.4 milestone replaces this with a SpellProvider abstraction: each buff type becomes a self-contained mixin that declares its event interests, produces a normalized ActiveProc on trigger, and exposes GetPreviewInfo for at-rest display. All type-specific branching moves into providers; consumers become uniform.

The recommended implementation follows Blizzard own CreateFromMixins pattern used throughout CDM (CooldownViewerItemMixin, CooldownViewerSettingsDataProviderMixin). A new Providers.lua file houses all four provider implementations. BuffEngine.lua is reduced to a dispatch loop, proc lifecycle management, and cancellation sweep. Display.lua and CDMTab.lua each replace their divergent icon-resolution chains with a single ns.GetPreviewInfoForKey(key) call. Core.lua and EditModeFrames.lua are untouched.

The dominant risk is not technical complexity -- the patterns are well-understood -- but migration correctness: five load-bearing behaviors (SavedVariables key stability, timer identity for cancellation, lust pre-gate ordering, preview mode coverage, and combat-lockdown safety) must survive the refactor intact. Each has a clear regression test defined in the pitfalls research. Execute the migration in the 11-step incremental build order from ARCHITECTURE.md; test at each step before proceeding.

## Key Findings

### Recommended Stack

All technologies are WoW Midnight built-ins; no external dependencies are introduced. The refactor uses Blizzard own OOP convention (CreateFromMixins / CreateAndInitFromMixin) rather than Lua metatables. This matches CDM source patterns exactly and avoids per-instance metatable GC overhead. The dispatch table pattern (eventToProviders per event) is also taken directly from CDM alertsByEvent table.

**Core technologies:**
- CreateFromMixins / CreateAndInitFromMixin: provider construction -- matches Blizzard CDM convention; flat method copy, no metatable risk
- UNIT_SPELLCAST_SUCCEEDED: cast detection for UserSpell, Trinket, Pot providers -- spellID is never a secret value
- UNIT_AURA + C_Secrets.ShouldAurasBeSecret(): lust detection and aura cancellation -- LUST-01 pre-gate ordering is load-bearing
- C_UnitAuras.GetPlayerAuraBySpellID: aura cancellation check for cast-sourced timers -- returns nil when aura absent or secret; secret gate must run first
- GetInventoryItemID / GetInventoryItemTexture: trinket at-rest icon (no secret risk; Blizzard uses without guards) -- combat-gated via InCombatLockdown()
- C_Item.GetItemCount / C_Item.GetItemIconByID: pot at-rest icon -- no secret risk; combat-gated

### Expected Features

**Must have (table stakes -- preserving existing behavior):**
- GetEventInterests() on all four providers -- BuffEngine event routing depends on this
- OnTrigger() returning normalized ActiveProc or nil on all four providers -- zero type branches in consumers
- GetPreviewInfo() with non-zero duration on all four providers -- fixes current Trinket/Pot 0-second preview bug
- GetAtRestInfo() on all four providers -- Display and CDMTab drop all divergent icon chains
- BuffEngine: single activeProcs table keyed by stable slot key; replace-on-reproc by key overwrite
- Cancellation sweep: reads source and castSpellID/lustBuffID from ActiveProc to dispatch check
- Display: zero metaSlot double-index, zero ResolveSuggestedSpellID calls
- CDMTab: zero META_DESCRIPTIONS branch; all icon/tooltip from GetPreviewInfoForKey

**Should have (unlocked by unified interface):**
- OwnsKey(key) per provider -- enables the single GetPreviewInfoForKey dispatch helper in ns namespace
- Provider order encoding priority (TrinketProvider/PotProvider before UserSpellProvider) -- eliminates fallthrough guards
- ns.GetPreviewInfoForKey exported to namespace -- single call site for Display and CDMTab

**Defer (v0.3+):**
- GetTooltipInfo() consolidation -- tooltip logic duplicated between Display OnEnter and CDMTab OnEnter; defer if not needed for initial refactor
- Aura-based duration override (read actual remaining time from aura data if Blizzard unlocks)
- Dynamic buff discovery (auto-tracking without user adding spell IDs)

### Architecture Approach

A new Providers.lua file is added to the load order between BuffEngine.lua and Display.lua. ns.providers priority order: { TrinketProvider, PotProvider, LustProvider, UserSpellProvider }. BuffEngine.lua becomes a thin dispatch loop. Display.lua and CDMTab.lua each collapse their six icon-resolution sites to one ns.GetPreviewInfoForKey(key) call. ActiveProc is a plain table with no metatable.

**Major components:**
1. Providers.lua (NEW) -- all four SpellProvider mixin implementations; ns.providers registry; ns.GetPreviewInfoForKey dispatch helper
2. BuffEngine.lua (MODIFIED) -- provider dispatch loop in OnSpellCastSucceeded; ns.activeProcs lifecycle; expiry sweep; cancellation scan
3. Display.lua (MODIFIED) -- consumes ns:GetActiveProcs() and ns.GetPreviewInfoForKey only; zero type-specific branches
4. CDMTab.lua (MODIFIED) -- calls ns.GetPreviewInfoForKey for all icon/tooltip resolution; no other changes
5. Core.lua, EditModeFrames.lua, CDMTab.xml (UNMODIFIED)

### Critical Pitfalls

1. **SavedVariables schema break from key type change** -- providers must read trackedBuffs keys as-is and never rename or remap them. Do not bump CURRENT_SCHEMA_VERSION unless a concrete migration block is written.

2. **Timer identity loss during dual-key unification** -- ActiveProc must carry both a procKey (stable DB slot key) and a castSpellID (numeric, used by GetPlayerAuraBySpellID). Collapsing them breaks either Display lookup or aura cancellation.

3. **Lust pre-gate ordering broken** -- UNIT_AURA dispatch must check Sated debuffs BEFORE the ShouldAurasBeSecret() gate. In M+, Sated is never secret; reversing the order stops lust timers in Mythic+. LUST-01 comment marks this.

4. **Preview mode regression from provider-filtered iteration** -- StartAllPreviewTimers must iterate trackedBuffs directly, not route through provider dispatch. GetPreviewInfo() is for CDM tab at-rest display only.

5. **Combat lockdown violation in provider construction** -- provider constructors must not call GetInventoryItemID or C_Item.GetItemCount. RefreshMetaIcons is the sole entry point for these; called only from StartPreview (out of combat).

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Providers.lua Skeleton + UserSpellProvider

**Rationale:** Establishes the provider contract and validates load-order before any behavior is moved. UserSpellProvider is the simplest case (1:1 with existing trackedBuffs numeric entries) and proves the dispatch loop is wired correctly. All other providers remain stubbed.
**Delivers:** ns.providers registry; provider interface contract defined; UserSpell cast detection working through provider path; .toc updated
**Addresses:** Table stakes -- provider interface contract, GetEventInterests, OnTrigger
**Avoids:** Pitfall 1 (schema break) -- UserSpellProvider reads numeric trackedBuffs keys unchanged

### Phase 2: TrinketProvider + PotProvider + BuffEngine Dispatch Loop

**Rationale:** Trinket and Pot share the same event, same key-type change (numeric castSpellID to string slot key), and the same overwrite semantic. Implementing together eliminates the dual-key metaSlot bridge in one step.
**Delivers:** All three cast-triggered providers active; ns.activeProcs keyed by stable slot key; trinket/pot reproc via simple overwrite; metaSlot bridge removed
**Uses:** GetInventoryItemTexture / C_Item.GetItemIconByID for at-rest icons (combat-gated)
**Avoids:** Pitfall 2 (timer identity loss) -- castSpellID field on proc preserved; Pitfall 5 (combat lockdown) -- icon reads from ns.metaAtRest cache

### Phase 3: LustProvider + UNIT_AURA Dispatch

**Rationale:** Isolated to Phase 3 due to LUST-01 pre-gate ordering constraint. Cast-triggered providers must be stable first, then aura dispatch with explicit two-phase ordering.
**Delivers:** Lust detection via provider; UNIT_AURA dispatch with pre-gate/post-gate phases correctly ordered; lust no-restart guard in LustProvider
**Implements:** LustProvider mixin (STACK.md Concrete Provider: LustProvider pattern)
**Avoids:** Pitfall 6 (event handler ordering) -- pre-gate structure explicit and verified in M+ simulation

### Phase 4: GetPreviewInfo + ns.GetPreviewInfoForKey

**Rationale:** With all four providers producing correct procs, the at-rest display layer can be unified. Purely additive -- no existing behavior is removed yet.
**Delivers:** GetPreviewInfo on all four providers with non-zero durations; ns.GetPreviewInfoForKey exported; Trinket/Pot 0-second preview bug fixed
**Avoids:** Pitfall 3 (preview regression) -- StartAllPreviewTimers is untouched until verified; new path is additive

### Phase 5: StartAllPreviewTimers Migration

**Rationale:** Preview timer generation refactored to call provider:GetPreviewProcs() only after Phase 4 confirms GetPreviewInfo is correct for all types.
**Delivers:** Preview mode iterates providers; Trinket/Pot show correct non-zero duration preview bars
**Avoids:** Pitfall 3 (preview regression) -- entry count comparison before and after

### Phase 6: Display.lua Simplification

**Rationale:** Display simplified only after all upstream data contracts are stable. Must preserve the wipe() accumulator pattern and hideWhenInactive dirty-check.
**Delivers:** Zero metaSlot branches; zero ResolveSuggestedSpellID calls; single shared tooltip handler
**Avoids:** Pitfall 7 (GC pressure) -- wipe() accumulator pattern preserved; no setmetatable in hot path

### Phase 7: CDMTab.lua Simplification

**Rationale:** CDMTab is last because it has the most icon-resolution duplication but zero impact on timer correctness. Any regression is visually obvious.
**Delivers:** Six icon/tooltip resolution sites collapsed to ns.GetPreviewInfoForKey; META_DESCRIPTIONS branch removed; BeginDrag ghost icon unified

### Phase 8: Cleanup

**Rationale:** Dead code removal deferred until all consumers are migrated.
**Delivers:** No dead code; CURRENT_SCHEMA_VERSION unchanged; stylua pass; release scripts verified
**Avoids:** Pitfall 1 (schema break) -- no version bump unless migration block written

### Phase Ordering Rationale

- Provider skeleton before dispatch loop: establishes the contract and validates wiring before any existing behavior is removed.
- Cast providers before aura provider: isolates the LUST-01 ordering constraint to Phase 3, where it gets dedicated attention.
- All providers complete before Display/CDMTab simplification: ensures upstream data contracts are stable before consumers are rewritten.
- StartAllPreviewTimers migration between provider completion and Display simplification: preview correctness confirmed before Display stops using its own fallback paths.
- Cleanup last: dead code removal only after all migration phases pass their verification tests.

### Research Flags

All phases have standard, fully-documented patterns -- no phase requires a gsd:research-phase call:
- **Phase 1:** CreateFromMixins pattern fully documented in STACK.md with copy-paste starting point
- **Phase 2:** inventory APIs and key-unification documented in STACK.md and FEATURES.md
- **Phase 3:** LUST-01 ordering documented in PITFALLS.md and STACK.md; UNIT_AURA dispatch in STACK.md
- **Phases 4-8:** purely internal refactor; all patterns established in Phases 1-3

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified against local Blizzard source; CreateFromMixins confirmed as C-layer global; no inferred behavior |
| Features | HIGH | Direct code analysis of v0.2.3; all four buff types fully characterized across detection, duration, icon, label, key, reproc, and cancellation |
| Architecture | HIGH | Read directly from codebase; concrete file and line references; 11-step migration plan with per-step validation |
| Pitfalls | HIGH | Codebase analysis with load-bearing comments (LUST-01, D-07, D-11, AURA-02) as evidence; each pitfall has named recovery path and cost |

**Overall confidence:** HIGH

### Gaps to Address

- **Lust pre-gate simulation in M+:** LUST-01 ordering can only be fully verified in Mythic+ where ShouldAurasBeSecret() returns true. Use /tbt debug during development; flag for real M+ testing post-deployment.
- **metaIconsDirty flag in unified Display:** Exact clearing site confirmed during Phase 6 when unified UpdateDisplay structure is visible.
- **Provider RefreshCache() extraction:** Moving RefreshMetaIcons into TrinketProvider/PotProvider as provider-level methods is a Phase 8 cleanup concern; ns:RefreshMetaIcons() continues to work through Phase 7.

## Sources

### Primary (HIGH confidence)

- C:/Users/jonat/Repositories/wow-ui-source -- Blizzard CDM source (CooldownViewer.lua, CooldownViewerSettings.lua, CooldownViewerItemData.lua, Mixin.lua, AuraUtil.lua, API documentation generated files)
- TerribleBuffTracker/BuffEngine.lua (v0.2.3) -- baseline being refactored; all timer and detection logic
- TerribleBuffTracker/Display.lua (v0.2.3) -- icon resolution duplication sites; accumulator pattern
- TerribleBuffTracker/CDMTab.lua (v0.2.3) -- icon and tooltip branching sites; drag-drop state machine
- TerribleBuffTracker/Core.lua -- event registration and routing

### Secondary (HIGH confidence -- internal docs)

- .planning/PROJECT.md -- v0.2.4 milestone goals and active requirements
- CLAUDE.md -- architectural constraints (COMBAT_LOG_EVENT_UNFILTERED disabled, secret value guards, CDM dependency)

---
*Research completed: 2026-04-18*
*Ready for roadmap: yes*