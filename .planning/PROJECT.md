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

### Active

- [ ] CDM Settings integration — TBT tab inside Cooldown Manager settings window
- [ ] Drag-and-drop buff management across 4 sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested)
- [ ] Add button in Suggested section (prompts Spell ID + Duration, lands in Not Displayed)
- [ ] Delete drop zone in Not Displayed section
- [ ] Edit Mode integration — two independent movable elements (bars container, buffs container)
- [ ] One-time CDM settings copy for fresh installs; TBT owns positioning after

### Out of Scope

- Buff tracking engine changes — not in this milestone
- Timer display rendering changes — not in this milestone
- Real buff suggestions in Suggested section — placeholder only for now
- Standalone config window — being replaced by CDM tab

## Current Milestone: v0.2.0 Config & Edit Mode Rework

**Goal:** Replace standalone config UI with a CDM-integrated tab and add Edit Mode support for independent buff/bar positioning.

**Target features:**
- CDM Settings tab ("TBT Buffs") with lateral tab button
- 4 sections: Tracked Buffs, Tracked Bars, Not Displayed, Suggested
- Drag buffs between sections to change display mode or disable
- Suggested section has Add button; new buffs land in Not Displayed
- Not Displayed has a delete drop zone square
- Edit Mode: two independent movable elements (bars, buffs)
- Fresh install copies CDM settings once; TBT owns them after
- Migration: existing tracked buffs preserved

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
*Last updated: 2026-03-29 after Phase 5 completion (drag-and-drop)*
