# Roadmap: TerribleBuffTracker v0.2.0

## Overview

Config & Edit Mode Rework. Replace the standalone config window with a native-feeling tab inside Blizzard's Cooldown Manager settings window, add independently movable Edit Mode containers, and implement drag-and-drop buff management across four sections. The work proceeds in strict dependency order: data migration first (everything reads the section field), Edit Mode containers second (resolves the Display.lua anchor conflict before CDM injection), CDM tab shell third (highest-risk integration step verified in isolation), static sections fourth, drag-and-drop fifth, and cleanup last per GSD workflow convention.

## Milestones

- **v0.2.0 Config & Edit Mode Rework** - Phases 1-6 (in progress)

## Phases

- [x] **Phase 1: Data Migration** - Expand SavedVariables schema and backfill existing entries (completed 2026-03-28)
- [ ] **Phase 2: Edit Mode Containers** - Two independently movable containers registered with Edit Mode
- [ ] **Phase 3: CDM Tab Shell** - Tab button injection and content panel frame; old config UI removed
- [ ] **Phase 4: CDM Tab Sections** - Four sections rendered from DB state with Add button and delete drop zone (static)
- [ ] **Phase 5: Drag-and-Drop** - Buff drag between sections with ghost frame, drop zone highlighting, and delete zone
- [x] **Phase 6: Cleanup** - Dead code removal, hot-path audit, stylua, release prep (completed 2026-03-30)

## Phase Details

### Phase 1: Data Migration
**Goal**: Existing user data is safely expanded to support the section model without loss
**Depends on**: Nothing (first phase)
**Requirements**: MIG-01, MIG-02
**Success Criteria** (what must be TRUE):
  1. User's previously tracked buffs still appear after upgrading — no entries are lost
  2. Each existing buff entry has a section value (bars, buffs, or hidden) derived from its old displayMode/enabled values
  3. New buffs added via BuffEngine default to section = "hidden"
  4. Upgrading a second time does not overwrite a section value the user has already set
**Plans:** 1/1 plans complete
Plans:
- [x] 01-01-PLAN.md — Schema migration v0->v1 and read/write path updates in BuffEngine.lua + Display.lua

### Phase 2: Edit Mode Containers
**Goal**: Users can independently reposition the bars container and buffs container via Edit Mode
**Depends on**: Phase 1
**Requirements**: EDM-01, EDM-02, EDM-03, EDM-04, EDM-05
**Success Criteria** (what must be TRUE):
  1. Entering Edit Mode reveals drag handles on both the bars container and the buffs container independently
  2. Each container can be moved to a different screen position and that position persists across /reload
  3. Both containers appear as toggleable checkboxes in the Edit Mode sidebar dialog
  4. On a fresh install (no saved positions), containers start at hardcoded default positions (center-right of screen)
  5. After a user has set Edit Mode positions, CDM layout refreshes do not move the containers
**Plans:** 2/2 plans complete
Plans:
- [x] 02-01-PLAN.md — Create EditModeFrames.lua with containers, drag handles, Edit Mode lifecycle, sidebar checkbox, position persistence; update Core.lua and TOC
- [x] 02-02-PLAN.md — Restructure Display.lua to decouple from CDM, use Edit Mode containers with hardcoded settings; in-game verification
**UI hint**: yes

### Phase 3: CDM Tab Shell
**Goal**: A working TBT tab button appears in CDM settings and switches to a TBT-owned content panel; old config UI is gone
**Depends on**: Phase 2
**Requirements**: TAB-01, TAB-02, TAB-07
**Success Criteria** (what must be TRUE):
  1. Opening CDM settings shows a "TBT Buffs" lateral tab button alongside the built-in CDM tabs
  2. Clicking the TBT tab shows a TBT-owned content panel and hides the CDM scroll frame
  3. Clicking any other CDM tab restores the CDM scroll frame and hides the TBT content panel
  4. /tbt opens CDM settings with the TBT tab selected instead of the old standalone window
  5. The old standalone config window is completely absent from the codebase
**Plans:** 1 plan
Plans:
- [ ] 03-01-PLAN.md — CDMTab.xml/CDMTab.lua tab injection, content panel, /tbt rework, ConfigUI.lua removal
**UI hint**: yes

### Phase 4: CDM Tab Sections
**Goal**: Users can see all four buff sections populated from their saved data and add or delete buffs through the tab UI
**Depends on**: Phase 3
**Requirements**: TAB-03, TAB-04, TAB-05, TAB-06
**Success Criteria** (what must be TRUE):
  1. Opening the TBT tab shows four labeled sections: Tracked Buffs, Tracked Bars, Not Displayed, Suggested
  2. Each buff appears as an icon in the section that matches its current section value
  3. Clicking Add in the Suggested section prompts for Spell ID and Duration, and the new buff appears in Not Displayed after confirming
  4. The Not Displayed section contains a visible delete drop zone that accepts a buff and removes it from the DB
**Plans:** 1/2 plans executed
Plans:
- [x] 04-01-PLAN.md — SetBuffSection API, section framework with icon grids, tooltips, context menus, and refresh
- [ ] 04-02-PLAN.md — Add Buff dialog, delete zone visual, in-game verification
**UI hint**: yes

### Phase 5: Drag-and-Drop
**Goal**: Users can reassign a buff's display mode by dragging its icon from one section to another
**Depends on**: Phase 4
**Requirements**: DND-01, DND-02, DND-03
**Success Criteria** (what must be TRUE):
  1. A buff icon can be dragged out of any section and dropped into any other section, changing its section value immediately
  2. While dragging, a ghost copy of the buff icon follows the cursor across the entire screen
  3. When the cursor enters a valid drop target, that section visually highlights; the highlight clears when the cursor leaves
  4. Dropping a buff onto the delete zone in Not Displayed removes it from the DB
**Plans:** 1 plan
Plans:
- [ ] 05-01-PLAN.md — Ghost frame, drag lifecycle (BeginDrag/EndDrag/GLOBAL_MOUSE_UP), section highlights, hit-testing, in-game verification
**UI hint**: yes

### Phase 05.1: Edit Mode Settings Popup (INSERTED)

**Goal:** Clicking a TBT container in Edit Mode selects it with a yellow highlight and opens a CDM-style settings popup for orientation, growth direction, scale, padding, visibility, and bar width; settings persist and replace hardcoded display defaults
**Requirements**: D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11
**Depends on:** Phase 5
**Plans:** 2/2 plans complete

Plans:
- [x] 05.1-01-PLAN.md — DB schema init for containerSettings + Display.lua refactor to read from DB
- [ ] 05.1-02-PLAN.md — Selection system with yellow NineSlice, click-vs-drag detection, CDM-style settings popup with Blizzard template controls

### Phase 6: Cleanup
**Goal**: Codebase is lean, correct, and ready for release
**Depends on**: Phase 5
**Requirements**: none (GSD workflow cleanup phase per CLAUDE.md)
**Success Criteria** (what must be TRUE):
  1. No OnUpdate callbacks run when no drag is in progress
  2. All modified Lua files pass stylua with no changes
  3. Release script produces a clean package with no leftover ConfigUI references
**Plans:** 1/1 plans complete
Plans:
- [x] 06-01-PLAN.md — Dead code removal, cdmWatcher hot-path fix, documentation cleanup, stylua

## Progress

**Execution Order:** 1 -> 2 -> 3 -> 4 -> 5 -> 5.1 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Migration | 1/1 | Complete   | 2026-03-28 |
| 2. Edit Mode Containers | 2/2 | Complete |  |
| 3. CDM Tab Shell | 0/1 | Not started | - |
| 4. CDM Tab Sections | 1/2 | In Progress|  |
| 5. Drag-and-Drop | 0/1 | Not started | - |
| 5.1. Edit Mode Settings Popup | 0/2 | Not started | - |
| 6. Cleanup | 1/1 | Complete   | 2026-03-30 |
