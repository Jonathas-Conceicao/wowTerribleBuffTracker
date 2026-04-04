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

### Active

- [ ] Register UNIT_AURA to detect buff removal when aura data is readable
- [ ] Cache secret-value detection — block aura checks until combat drop or zone change, re-check on next event
- [ ] Silently cancel active timers for tracked buffs no longer present in aura list
- [ ] Zone-transition scan to catch buffs stripped during loading screens
- [ ] Lust meta-buff: detect Sated-family debuffs to auto-start lust timer, single CDM tab icon with class-aware icon

### Out of Scope

- Display rendering changes — not in this milestone
- New buff tracking sources beyond UNIT_AURA_UPDATE — not in this milestone
- Updating timer durations from aura data — only cancellation for now
- Aura-based buff auto-discovery — only checks already-tracked buffs

## Current Milestone: v0.2.1 Aura-Based Timer Cancellation

**Goal:** Use UNIT_AURA_UPDATE to detect and cancel tracked buff timers when buffs are no longer present, with smart secret-value caching.

**Target features:**
- Register UNIT_AURA_UPDATE event for "player" unit
- On first event with secret values, set a "blocked" flag and skip future events
- Clear blocked flag on PLAYER_REGEN_ENABLED (combat drop) or ZONE_CHANGED_NEW_AREA (zone change)
- When not blocked: scan aura list for tracked buffs, silently remove timers for missing buffs
- Handles lust on wipe, trinket procs ending early, buff cancellations

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
| Integrate as CDM tab rather than standalone window | Matches Blizzard UI patterns, reduces addon footprint | — Pending |
| Two independent Edit Mode elements (bars + buffs) | Users may want bars and buff icons in different positions | — Pending |
| Copy CDM settings once on fresh install | Sensible defaults without ongoing coupling | — Pending |
| New buffs land in Not Displayed | User explicitly chooses where to show, avoids clutter | — Pending |

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
*Last updated: 2026-04-04 after Phase 10 completion (lust tracking)*
