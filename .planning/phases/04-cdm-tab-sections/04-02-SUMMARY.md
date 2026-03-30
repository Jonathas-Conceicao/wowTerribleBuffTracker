---
phase: 04-cdm-tab-sections
plan: 02
subsystem: ui
tags: [cdm-tab, dialog, delete-zone, context-menu]

requires:
  - phase: 04-01
    provides: "SetBuffSection API, section framework, RefreshTBTSections, icon grid with context menus"
provides:
  - "Add Buff dialog (two-field modal, DIALOG strata)"
  - "Delete drop zone visual in Not Displayed section"
  - "Skill-like Add square in Suggested section"
affects: [05-drag-and-drop]

tech-stack:
  added: []
  patterns:
    - "DIALOG strata modal with BackdropTemplate (not ButtonFrameTemplate)"
    - "Skill-square Add button with communities-chat-icon-plus atlas"
    - "SetSpellByID tooltip with appended TBT info lines"

key-files:
  created: []
  modified: [CDMTab.lua]

key-decisions:
  - "Replaced ButtonFrameTemplate dialog with plain BackdropTemplate at DIALOG strata — ButtonFrameTemplate too complex for small dialog"
  - "Add button is 38x38 skill square, not text button"
  - "Tooltip uses SetSpellByID for real spell tooltip, appends Spell ID and TBT Duration in gray"
  - "Delete zone visual only — functional deletion via drag in Phase 5"
  - "Double-refresh on panel OnShow fixes first-open GridLayoutFrame height issue"
  - "CDM taint fix: OnUpdate watcher instead of HookScript on CooldownViewerSettings; CooldownScroll Hide/Show safe from addon code context"

patterns-established:
  - "Add dialog: UIParent-parented DIALOG strata, movable, ESC-close, Tab between fields, Enter confirms"

requirements-completed: [TAB-04, TAB-05, TAB-06]

duration: 30min
completed: 2026-03-29
---

# Phase 04 Plan 02: Add Dialog + Delete Zone Summary

**Add Buff dialog rebuilt as clean DIALOG-strata modal, skill-square Add button, spell tooltips with TBT info, delete zone visual, taint fixes**

## Post-Checkpoint Fixes

1. **CDM taint vectors removed**: Replaced HookScript on CooldownViewerSettings with OnUpdate watcher; restored CooldownScroll Hide/Show in addon code context (safe)
2. **First-open layout**: Double-refresh with C_Timer.After(0) for GridLayoutFrame height settling
3. **Add button → skill square**: 38x38 green-tinted frame with plus icon
4. **Tooltip**: SetSpellByID for real spell tooltip + Spell ID and TBT Duration in gray
5. **Add dialog rebuilt**: Plain BackdropTemplate at DIALOG strata, explicit vertical layout (no more ButtonFrameTemplate clipping)

## Verification Results

All checks passed in-game:
- TAB-03: 4 sections with collapse/expand, icons in correct sections ✓
- TAB-04: Add skill square opens dialog, validation works ✓
- TAB-05: New buff appears in Not Displayed ✓
- TAB-06: Delete zone visible (red X, first slot) ✓
- Context menus: Move/Hide/Remove all work ✓
- Tooltip: Real spell tooltip + TBT info ✓
- No Lua errors ✓
