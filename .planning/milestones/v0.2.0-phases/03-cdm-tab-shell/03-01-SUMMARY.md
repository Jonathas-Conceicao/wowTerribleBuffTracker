---
phase: 03-cdm-tab-shell
plan: 01
subsystem: ui
tags: [cdm, tab-injection, wow-api, xml, preview]

requires:
  - phase: 02-edit-mode-containers
    provides: "Independent UIParent containers, EditModeFrames.lua"
provides:
  - "TBT tab button in CDM settings (LargeSideTabButtonTemplate)"
  - "TBT content panel (empty ScrollFrame) overlaying CDM scroll area"
  - "Tab switching logic (show/hide TBT panel vs CDM CooldownScroll)"
  - "/tbt command opens CDM settings with TBT tab selected"
  - "Preview timers on CDM open via ns.configOpen flag"
  - "ConfigUI.lua deleted from codebase"
affects: [04-cdm-tab-sections, 05-drag-and-drop]

tech-stack:
  added: [CDMTab.xml, CDMTab.lua]
  patterns:
    - "LargeSideTabButtonTemplate for tab injection (NOT CooldownViewerSettingsTabTemplate — avoids parentArray taint)"
    - "hooksecurefunc on SetDisplayMode for tab-away detection"
    - "ns.configOpen flag for preview timer persistence"
    - "C_Timer.After(0) for post-OnShow tab selection"
    - "Access CDM tabs by parentKey (SpellsTab/AurasTab), never iterate TabButtons array"

key-files:
  created: [CDMTab.xml, CDMTab.lua]
  modified: [Core.lua, TerribleBuffTracker.toc, scripts/install.bat]
  deleted: [ConfigUI.lua]

key-decisions:
  - "parentArray='TabButtons' causes CDM secure taint — removed, use LargeSideTabButtonTemplate directly"
  - "SetTexture with addon icon instead of SetAtlas with nonexistent atlas"
  - "Panel has no backdrop — matches CDM's own CooldownScroll (plain ScrollFrame)"
  - "Preview uses existing ns.configOpen flag, not C_Timer.NewTicker"
  - "Override tab:SetChecked to use SetTexture instead of SetAtlas"

patterns-established:
  - "CDM integration: never touch TabButtons array, never call SetDisplayMode with TBT strings"
  - "Tab-away detection via hooksecurefunc on SetDisplayMode"
  - "Preview control via ns.configOpen = true/false"

requirements-completed: [TAB-01, TAB-02, TAB-07]

duration: 30min
completed: 2026-03-29
---

# Phase 03 Plan 01: CDM Tab Injection Summary

**TBT tab injected into CDM settings with taint-safe approach, preview persistence, and ConfigUI.lua removal**

## What Was Built

- `CDMTab.xml`: Tab frame inheriting `LargeSideTabButtonTemplate`, anchored below AurasTab. Does NOT use `parentArray="TabButtons"` to avoid CDM secure taint.
- `CDMTab.lua`: Tab click handler, content panel (plain ScrollFrame matching CDM style), hooksecurefunc on SetDisplayMode for tab-away, preview hooks via ns.configOpen, SelectTBTTab for /tbt command.
- Core.lua: Slash command calls `ns:SelectTBTTab()` instead of `ns:ToggleConfigUI()`.
- ConfigUI.lua deleted from codebase, TOC, and install.bat.

## Post-Checkpoint Fixes

1. **Taint fix**: Removed `parentArray="TabButtons"` and `CooldownViewerSettingsTabTemplate` — accessing CDM's secure TabButtons array tainted all CDM code. Now uses `LargeSideTabButtonTemplate` directly and accesses tabs by parentKey.
2. **Icon fix**: `hud-buff` atlas doesn't exist in Midnight. Switched to `SetTexture` with `tbt_icon_64x64.blp`.
3. **Panel style fix**: Removed `BackdropTemplate` with custom backdrop — CDM's own CooldownScroll has no backdrop. Now a plain ScrollFrame.
4. **Preview fix**: Replaced `C_Timer.NewTicker` with existing `ns.configOpen` flag that Display.lua already checks.

## Verification Results

All 10 in-game checks passed:
- TAB-01: TBT tab visible below Auras tab with addon icon ✓
- TAB-02: Tab switching works both ways (TBT ↔ Spells/Auras) ✓
- TAB-07: /tbt opens CDM with TBT tab, switches if already open ✓
- D-15: Preview timers persist while CDM is open ✓
- D-16: Preview timers clear on CDM close ✓
- No taint errors ✓
- CDM Spells/Auras tabs work normally ✓
