# TerribleBuffTracker

## What This Is

A WoW Midnight addon for manually tracking buff and cooldown timers. Because `COMBAT_LOG_EVENT_UNFILTERED` is disabled in Midnight, TBT uses `UNIT_SPELLCAST_SUCCEEDED` plus known durations to create visual timer bars and icons anchored to Blizzard's Cooldown Manager (CDM).

## Core Value

Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.

## Requirements

### Validated

- Timer tracking via UNIT_SPELLCAST_SUCCEEDED + GetTime() + known duration — v0.1
- Timer bars and buff icons displayed anchored to CDM — v0.1
- Config UI for adding/removing tracked buffs (spell ID, duration, label) — v0.1
- Enable/disable individual buffs — v0.1
- Display mode toggle per buff (bar or icon) — v0.1
- Preview mode (starts all timers for testing) — v0.1
- SavedVariables persistence (account-wide) — v0.1
- `/tbt` slash command to open config — v0.1
- CI/CD with BigWigs Packager for CurseForge/Wago/GitHub releases — v0.1
- Schema migration v0→v1: section-based buff management model (bars/buffs/hidden) — v0.2 Phase 1
- Edit Mode: two independent movable containers (bars, buffs) with position persistence, floating checkbox panel, NineSlice overlay — v0.2 Phase 2
- CDM tab shell: TBT Buffs tab in CDM settings, content panel, /tbt opens CDM, ConfigUI.lua removed — v0.2 Phase 3
- CDM tab sections: 4 collapsible sections, icon grids, Add dialog, delete zone visual, right-click context menus — v0.2 Phase 4
- Drag-and-drop: section-to-section drag, within-section reorder, CDM-style reorder marker, delete zone drag — v0.2 Phase 5
- UNIT_AURA event registration (player-filtered), secret-value blocked flag, isFullUpdate suppression, preview guard, debug toggle — v0.2.1 Phase 7
- Aura scan cancellation: ScanActiveTimersForCancellation removes timers for absent buffs via GetPlayerAuraBySpellID — v0.2.1 Phase 8
- Lust meta-buff: Sated-family debuff detection auto-starts 40s timer, class-aware CDM icon, Suggested section activated as static catalog — v0.2.1 Phase 10
- Trinket meta-tracker: shared slot tracking all season on-use trinkets via cast detection, shared-slot overwrite (newest cast wins) — v0.2.3 Phases 12-13
- Damage pot meta-tracker: shared slot tracking all current-season damage potions via cast detection, shared-slot overwrite — v0.2.3 Phases 12-13
- Dynamic CDM icon resolution: trinket shows equipped trinket icon, pot shows bag consumable icon; refreshes on CDM settings open (out of combat); falls back to first CSV entry — v0.2.3 Phase 14
- Active timer icon switches to cast spell icon; reverts to at-rest resolved icon on expiry — v0.2.3 Phases 13-15
- SpellProvider skeleton: Providers.lua with SpellProviderBaseMixin + UserSpellProviderMixin (CreateFromMixins); ns:DispatchEventToProviders routes user-spell casts through provider OnTrigger — v0.2.4 Phase 17 (PROV-03)
- TrinketProvider + PotProvider (separate mixins per D-05); static data relocated to Providers.lua with ns.* exports preserved; BuffEngine.OnSpellCastSucceeded reduced to single dispatcher call (zero if/elseif branches); cast-triggered procs carry castSpellID for aura cancellation; Display.lua metaSlot dual-index replaced with timer.key lookup — v0.2.4 Phase 18 (PROV-02, LIFE-01)
- LustProvider (4th and final provider registered at position 3); lust data colocated (SATED_DEBUFF_TO_LUST, SHARED_LUST_BUFFS new export, CLASS_LUST_SPELL, GetHunterLustSpell) with ns.* exports; BuffEngine.OnUnitAura rewritten dispatch-first preserving LUST-01 by architecture (dispatcher is dumb and uniform — providers self-govern secret/preview safety); no-restart guard provider-internal; ScanActiveTimersForCancellation reads ns.SHARED_LUST_BUFFS; flag renamed secretGateLogged / ClearSecretGateLog for clarity — v0.2.4 Phase 19 (PROV-01, LIFE-02)
- GetDisplayInfo unified provider contract (collapsed GetPreviewInfo + GetAtRestInfo); ns:GetDisplayInfoForKey dispatch helper via local keyToProvider table; PROV-F3 pulled in — TrinketProvider/PotProvider own minimal atRest cache (spellID + duration; icon/label derived via GetSpellIcon + C_Spell.GetSpellInfo) and RefreshAtRest with combat gate; ns:RefreshMetaIcons reduced to thin wrapper iterating ns.providers; BuffEngine shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID) delegate through ns:GetDisplayInfoForKey — v0.2.4 Phase 20 (PROV-04, PROV-F3 absorbed)
- Additive-preview architecture: separate ns.previewTimers table; StartAllPreviewTimers skips running slots and uses ns:GetDisplayInfoForKey as sole data source; ClearAllTimers wipes only previews (no snapshot/restore); ns:GetActiveTimers merges both tables with real-priority override; ns.previewActive flag and OnUnitAura guard deleted; fixes trinket/pot 0-second preview bug AND mid-CDM real cast loss in one pass — v0.2.4 Phase 21 (LIFE-03)
- Display unification + proc shape cleanup: 9-field normalized proc shape (dropped icon/source/castSpellID/lustBuffID/string-coexistence); proc.spellID always numeric drives icon + tooltip + cancellation; unified ScanActiveTimersForCancellation via proc.aliveBuffs list (single-loop strategy, no source branching); ns:ShowBuffTooltip shared handler between Display bar/icon OnEnter; Display derives icon per-widget via cachedSpellID/cachedIcon cache (providers stay UI-agnostic); SHARED_LUST_BUFFS demoted to Providers.lua local; GetSuggestedAtRestIcon + metaIconsDirty flag fully deleted — v0.2.4 Phase 22 (DISP-01, DISP-03)
- Orphan removal and release prep: three backwards-compat shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID), ns.TRINKET_FALLBACK_ORDER / ns.POT_FALLBACK_ORDER namespace exports, and stale phase-lifecycle comments all deleted (grep-gated sweep); ns:RefreshMetaIcons renamed ns:RefreshProvidersAtRest to match post-refactor architecture; pots_info.csv and trinket_info.csv source files removed; hot-path audit confirmed no allocation regressions on Display render, OnUnitAura dispatch, or ScanActiveTimersForCancellation; v0.2.4 CHANGELOG entry added; stylua-clean — v0.2.4 Phase 24 (DISP-04)

### Active

*(none — v0.2.4 milestone complete; see Current State below)*

## Current State

**Last shipped:** v0.2.4 SpellProvider Refactor (2026-04-22) — 8 phases, 23 plans, interface bump to 120005

The v0.2.4 release was a pure internal architecture refactor with zero user-facing feature additions. All four buff types (user spells, trinkets, pots, lust) now share a single `SpellProvider` interface and a unified `ActiveProc` proc shape consumed by one Display codepath. The class of bugs where detection works but display diverges is now architecturally harder to introduce because there is only one identity (`proc.key`) flowing through one codepath.

**Next milestone:** Not yet defined. See `/gsd:new-milestone` to scope the next release.

**Open backlog:** Phase 999.1 (Edit Mode container selects on click-release instead of click-down) — captured during v0.2.4 verification, awaiting promotion.

### Out of Scope

- Updating timer durations from aura data — future enhancement
- Aura-based buff auto-discovery — only checks already-tracked buffs
- Preview preserving per-buff state on CDM open/close — works at timer level but could be more granular

## Context

- WoW Midnight (Interface 120000+), COMBAT_LOG_EVENT_UNFILTERED disabled
- CDM is Blizzard's Cooldown Manager — addon must integrate with its settings UI
- Blizzard UI source available at `C:\Users\jonat\Repositories\wow-ui-source`
- CDM templates: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml` and `.lua`
- Edit Mode: `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- Layout: `Interface/AddOns/Blizzard_SharedXML/LayoutFrame.lua` and `GridLayoutUtil.lua`
- Current display anchors bars/icons to CDM containers; Edit Mode will decouple this

## Constraints

- **API**: No COMBAT_LOG_EVENT_UNFILTERED — must use UNIT_SPELLCAST_SUCCEEDED
- **UI Framework**: Must use WoW's native frame/widget system (no external libs)
- **CDM Dependency**: Tab must integrate with existing CDM settings window, not replace it
- **Compatibility**: Interface 120000+ (Midnight)
- **Migration**: Must not break existing TerribleBuffTrackerDB data

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Integrate as CDM tab rather than standalone window | Matches Blizzard UI patterns, reduces addon footprint | ✓ Good — shipped v0.2.0 |
| Two independent Edit Mode elements (bars + buffs) | Users may want bars and buff icons in different positions | ✓ Good — shipped v0.2.0 |
| Copy CDM settings once on fresh install | Sensible defaults without ongoing coupling | ✓ Good — shipped v0.2.0 |
| New buffs land in Not Displayed | User explicitly chooses where to show, avoids clutter | ✓ Good — shipped v0.2.0 |
| Stateless providers; BuffEngine owns all lifecycle (Option A) | Keeps providers testable and side-effect-free; single place to reason about proc expiry and reproc | ✓ Good — shipped v0.2.4 |
| Plain-table ActiveProc (no metatable) | Avoids per-instance metatable GC overhead in hot paths | ✓ Good — shipped v0.2.4 |
| Dispatcher-first event flow; providers self-govern secret/preview safety | LUST-01 ordering preserved by architecture instead of by an explicit branch in BuffEngine | ✓ Good — shipped v0.2.4 |
| Additive preview with separate `ns.previewTimers` | Eliminates snapshot/restore and the mid-CDM real-cast-loss bug as an architectural side-effect | ✓ Good — shipped v0.2.4 |
| Key-driven display reads (`proc.key`, not `proc.spellID`) | `.key` is stable across meta-buff slot contents; `.spellID` is a derived numeric. Phase 22 regression proved this is load-bearing | ✓ Good — codified in v0.2.4 after `df48029` regression fix |
| No refactors during cleanup phases | Keeps release-prep phases narrow and predictable; prevents last-mile scope creep | ✓ Good — Phase 16 + Phase 24 honored this |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? Move to Out of Scope with reason
2. Requirements validated? Move to Validated with phase reference
3. New requirements emerged? Add to Active
4. Decisions to log? Add to Key Decisions
5. "What This Is" still accurate? Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-22 — v0.2.4 SpellProvider Refactor shipped*
