---
phase: 05-drag-and-drop
plan: 01
subsystem: ui
tags: [drag-drop, reorder, ghost-frame, cdm]

requires:
  - phase: 04-cdm-tab-sections
    provides: "Section framework, icon pools, SetBuffSection API, RefreshTBTSections"
provides:
  - "Full drag-and-drop between TBT tab sections"
  - "Within-section reordering via layoutOrder"
  - "CDM-style ReorderMarker insertion line"
  - "Delete zone functional via drag"
  - "Display order reflects layoutOrder"
affects: [06-cleanup]

tech-stack:
  added: []
  patterns:
    - "Ghost frame at TOOLTIP strata following cursor via GetScaledCursorPositionForFrame"
    - "GLOBAL_MOUSE_UP for drag commit/cancel"
    - "ReorderMarker (UI-ChatFrame-DockHighlight, ADD blend) for insertion position"
    - "layoutOrder field for persistent within-section ordering"

key-files:
  created: []
  modified: [CDMTab.lua, BuffEngine.lua, Display.lua]

key-decisions:
  - "CDM ReorderMarker pattern instead of section-wide highlights (user feedback)"
  - "Within-section reorder added to scope (was out of scope, user requested)"
  - "No source icon alpha dimming during drag (matches CDM behavior)"
  - "Category layout: fixed 344px width, 315px container, 13px indent, 18px gap (CDM exact values)"
  - "Schema v1→v2 migration for layoutOrder backfill"
  - "Collapsed sections reject drops"

patterns-established:
  - "Drag lifecycle: OnMouseDown → BeginDrag → ghost + OnUpdate → GLOBAL_MOUSE_UP → EndDrag"
  - "layoutOrder persisted in DB, sorted in both CDMTab.lua and Display.lua"

requirements-completed: [DND-01, DND-02, DND-03]

duration: 45min
completed: 2026-03-29
---

# Phase 05 Plan 01: Drag-and-Drop Summary

**Full drag-and-drop system with CDM-style reorder marker, within-section reordering, and exact CDM category layout**

## What Was Built

- Ghost frame at TOOLTIP strata, 50% alpha, follows cursor via OnUpdate
- GLOBAL_MOUSE_UP for commit/cancel, right-click cancels
- CDM-style ReorderMarker (UI-ChatFrame-DockHighlight, ADD blend) shows insertion position
- Section-to-section drag changes entry.section via SetBuffSection
- Within-section drag reorders via layoutOrder field
- Delete zone drag removes buff from DB
- Collapsed sections reject drops
- Display.lua sorts bars/buffs by layoutOrder (reflects CDM tab ordering)
- Schema v2 migration backfills layoutOrder on existing entries
- Category layout matches CDM exactly (344px width, 315px container, 13px indent, 18px gap)

## Post-Checkpoint Fixes

1. Highlight → CDM ReorderMarker (insertion line, not section overlay)
2. Within-section reorder added (layoutOrder field, schema v2)
3. Display order uses layoutOrder instead of spellID
4. Collapsed sections reject drops in both hit-test and highlight
5. No source icon alpha dimming (matches CDM)
6. Section width: exact CDM category dimensions (344/315/13/15/18)
7. Container indent removed then restored to match CDM exactly

## Verification Results

All 12 in-game checks passed:
- DND-01: Drag between all sections works ✓
- DND-01: Cancel on outside/Suggested/right-click ✓
- DND-01: Delete zone removes buff ✓
- DND-02: Ghost follows cursor at 50% alpha ✓
- DND-03: ReorderMarker shows insertion position ✓
- Within-section reorder works and reflects in display ✓
- Right-click context menu coexists with drag ✓
- Escape mid-drag cancels cleanly ✓
- No Lua errors ✓
