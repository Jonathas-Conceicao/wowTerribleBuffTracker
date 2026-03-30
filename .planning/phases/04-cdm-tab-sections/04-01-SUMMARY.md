---
phase: 04-cdm-tab-sections
plan: "01"
subsystem: CDMTab + BuffEngine
tags: [sections, icon-grid, context-menu, pool, collapse, tooltip]
dependency_graph:
  requires: [03-01-SUMMARY.md]
  provides: [ns:SetBuffSection, ns:RefreshTBTSections, section icon grids, right-click context menus]
  affects: [CDMTab.lua, BuffEngine.lua]
tech_stack:
  added: [CreateObjectPool, MenuUtil.CreateContextMenu, ListHeaderThreeSliceTemplate, GridLayoutFrame]
  patterns: [frame pool with custom factory, section stacking via TOPLEFT anchors, scroll child height management]
key_files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
decisions:
  - "Used CreateObjectPool (not CreateFramePool with template) to avoid CDM's CooldownViewerSettingsItemTemplate data provider tie-in"
  - "RefreshTBTSections iterates ns.db.trackedBuffs once per section (O(N*4)) — acceptable at N<100 buffs; no hot-path concern"
  - "break instead of continue in RefreshTBTSections when section missing — all 4 sections are always present after BuildAllSections so this is safe"
metrics:
  duration: "~2 minutes"
  completed: "2026-03-29"
  tasks: 2
  files: 2
---

# Phase 04 Plan 01: TBT Tab Section Framework Summary

**One-liner:** Four collapsible buff sections (Tracked Bars/Buffs/Not Displayed/Suggested) with pooled icon grids, tooltips, and section-specific right-click context menus wired to ns:SetBuffSection.

## What Was Built

### Task 1 — ns:SetBuffSection API (BuffEngine.lua)

Added `ns:SetBuffSection(spellID, section)` between `ns:SetBuffEnabled` and `ns:StartAllPreviewTimers`. The function:
- Updates `ns.db.trackedBuffs[spellID].section` directly
- Syncs `ns.activeTimers[spellID].section` if a timer is running
- Clears `ns.activeTimers[spellID]` when section is set to `"hidden"`
- Calls `ns:UpdateDisplay()` if available

### Task 2 — Section Framework (CDMTab.lua)

Added ~216 lines above `ns:InitCDMTab()`:

**SECTION_DEFS** — module-level table defining the four section keys and titles in D-01 order: bars, buffs, hidden, suggested.

**CreateIconFrame(parent)** — factory creating 38x38 frames with:
- ARTWORK icon texture (SetAllPoints)
- HIGHLIGHT texture using `Interface\\Buttons\\ButtonHilight-Square` with ADD blend mode
- OnEnter: GameTooltip with spell label (line 1), "Spell ID: N" (line 2), "Duration: Ns" (line 3)
- OnLeave: GameTooltip:Hide()
- OnMouseUp (right-click): `MenuUtil.CreateContextMenu` with section-specific options per D-15:
  - bars: "Move to Buffs", "Hide", divider, "Remove"
  - buffs: "Move to Bars", "Hide", divider, "Remove"
  - hidden: "Move to Bars", "Move to Buffs", divider, "Remove"
  - suggested: no-op

**BuildTBTSection(parent, def)** — builds three-level hierarchy:
- `section.frame`: plain 300px-wide Frame parented to ns.tbtScrollChild
- `section.header`: Button with ListHeaderThreeSliceTemplate (22px height, full-width, TOPLEFT+TOPRIGHT anchored)
- `section.container`: GridLayoutFrame with stride=7, 8px padding, alwaysUpdateLayout=true
- `section.itemPool`: CreateObjectPool with CreateIconFrame factory and reset function

**ns:UpdateSectionHeight(section)** — sets frame height to 22 (collapsed) or 22+8+container:GetHeight() (expanded).

**ns:UpdateScrollChildHeight()** — sums all 4 section frame heights + 3×12px gaps, calls tbtScrollChild:SetHeight().

**ns:RefreshTBTSections()** — single refresh entry point: ReleaseAll pools, iterate DB, Acquire+configure items, Layout(), UpdateSectionHeight() per section, UpdateScrollChildHeight().

**ns:BuildAllSections()** — creates all 4 sections, stacks them vertically with TOPLEFT to prevFrame BOTTOMLEFT (0, -12) anchors, stores in ns.tbtSections keyed by section key.

**InitCDMTab() hooks** — `ns:BuildAllSections()` called after panel/scrollChild creation, `ns.tbtPanel:HookScript("OnShow", ...)` calls `ns:RefreshTBTSections()`.

## Deviations from Plan

None — plan executed exactly as written.

The only design choice not explicitly specified: used `CreateObjectPool` (the WoW API for pools with custom creator functions) rather than `CreateFramePool` since the plan required a custom creation function and `CreateFramePool` only supports template-string creation.

## Known Stubs

- **Suggested section** — `def.key ~= "suggested"` skips DB iteration for suggested section. The section renders as a header with an empty container. This is intentional per plan: "placeholder section for now". Future plan (Plan 02) adds the "Add Buff" button and population logic.
- **Delete drop zone** — Not Displayed section has no visual delete zone frame yet. This is intentional per UI-SPEC "Out of Scope (Deferred to Later Phases)": delete zone is a Phase 5 feature. The section functions correctly as a display section.

Both stubs are explicitly out-of-scope for this plan. Neither prevents the plan's goal (section display with icon grids and context menus) from being achieved.

## Self-Check: PASSED

Files verified:
- `BuffEngine.lua` — modified, contains `function ns:SetBuffSection`
- `CDMTab.lua` — modified, contains `function ns:RefreshTBTSections`, `BuildTBTSection`, `CreateIconFrame`, `MenuUtil.CreateContextMenu`, `ListHeaderThreeSliceTemplate`, `GridLayoutFrame`, `ns:BuildAllSections`

Commits verified:
- `40bc9c2` — feat(04-01): add ns:SetBuffSection API to BuffEngine.lua
- `35e5b88` — feat(04-01): build TBT tab section framework in CDMTab.lua
