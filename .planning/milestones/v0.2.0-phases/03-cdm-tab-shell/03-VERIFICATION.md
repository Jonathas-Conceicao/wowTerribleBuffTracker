---
phase: 03-cdm-tab-shell
verified: 2026-03-29T00:00:00Z
status: passed
score: 7/7 must-haves verified
---

# Phase 03: CDM Tab Shell Verification Report

**Phase Goal:** A working TBT tab button appears in CDM settings and switches to a TBT-owned content panel; old config UI is gone
**Verified:** 2026-03-29
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CDM settings window shows a TBT Buffs lateral tab button alongside Spells and Auras tabs | VERIFIED (human) | CDMTab.xml defines TBTSettingsTab with LargeSideTabButtonTemplate, anchored below AurasTab. User confirmed in-game (check 4). |
| 2 | Clicking TBT tab shows TBT content panel and hides CDM scroll frame | VERIFIED (human) | ns:ShowTBTPanel() hides CooldownViewerSettings.CooldownScroll and shows ns.tbtPanel. User confirmed in-game (check 6). |
| 3 | Clicking a CDM tab (Spells/Auras) hides TBT panel and restores CDM scroll frame | VERIFIED | hooksecurefunc on SetDisplayMode calls ns:HideTBTPanel() which hides tbtPanel and shows CooldownScroll. User confirmed in-game (checks 7-8). |
| 4 | /tbt opens CDM settings with TBT tab selected (never toggles closed) | VERIFIED | Core.lua slash command calls ns:SelectTBTTab(); that function calls ShowUIPanel only if not visible, then C_Timer.After(0, ShowTBTPanel). User confirmed checks 10-11. |
| 5 | ConfigUI.lua is gone from codebase, TOC, and install.bat | VERIFIED | File does not exist on disk. Not listed in TerribleBuffTracker.toc. Not in scripts/install.bat. No live code references found. |
| 6 | Opening CDM settings shows preview timers for all tracked buffs (D-15) | VERIFIED (human) | CooldownViewerSettings HookScript("OnShow") calls StartPreview() which sets ns.configOpen = true and calls ns:StartAllPreviewTimers(). Display.lua checks ns.configOpen in render paths. User confirmed check 5. |
| 7 | Closing CDM settings clears all preview timers (D-16) | VERIFIED (human) | CooldownViewerSettings HookScript("OnHide") calls StopPreview() which sets ns.configOpen = false and calls ns:ClearAllTimers(). User confirmed check 9. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `CDMTab.xml` | VERIFIED | Exists. Defines TBTSettingsTab with LargeSideTabButtonTemplate (taint-safe replacement for CooldownViewerSettingsTabTemplate per post-checkpoint fix). Anchored below AurasTab y=-3. References CDMTab.lua via Script element. No parentArray attribute (deliberate taint fix documented in SUMMARY). |
| `CDMTab.lua` | VERIFIED | Exists, 166 lines (exceeds min_lines: 60). Exports ns:InitCDMTab, ns:SelectTBTTab, ns:ShowTBTPanel, ns:HideTBTPanel. All functions substantive. |
| `Core.lua` | VERIFIED | Slash command calls ns:SelectTBTTab(). No ToggleConfigUI reference. |
| `TerribleBuffTracker.toc` | VERIFIED | Lists CDMTab.xml. ConfigUI.lua absent. |
| `scripts/install.bat` | VERIFIED | Copies CDMTab.xml and CDMTab.lua. No ConfigUI.lua copy line. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| CDMTab.xml | CooldownViewerSettings | parent="CooldownViewerSettings" attribute | WIRED | Line 8 of CDMTab.xml: `parent="CooldownViewerSettings"` |
| CDMTab.lua | CooldownViewerSettings.SetDisplayMode | hooksecurefunc | WIRED | CDMTab.lua line 91: `hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", ...)` |
| Core.lua | CDMTab.lua | ns:SelectTBTTab call in slash command | WIRED | Core.lua line 56: `ns:SelectTBTTab()` |
| CDMTab.lua | BuffEngine.lua | ns:StartAllPreviewTimers and ns:ClearAllTimers calls | WIRED | CDMTab.lua lines 15, 20. Both functions confirmed in BuffEngine.lua lines 161 and 182. |

Note: The PLAN specified key_link pattern `parent="CooldownViewerSettings"` for the CDMTab.xml → CooldownViewerSettings link and the parentArray route. The XML link is confirmed. The parentArray route was deliberately removed (taint fix) — not a gap.

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| CDMTab.lua (preview) | ns.configOpen | Set to true in StartPreview(), false in StopPreview() | Yes — flag read per-frame by Display.lua render paths (lines 234, 373, 550) | FLOWING |
| CDMTab.lua (panel) | ns.tbtPanel, ns.tbtScrollChild | CreateFrame in InitCDMTab() | Yes — live WoW frames; scroll child exposed for Phase 4 population | FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED for Lua/WoW addon — no runnable entry points outside the WoW client. All behavioral checks were performed as in-game human verification (Task 4, 10 checks). User approved all 10.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TAB-01 | 03-01-PLAN.md | User sees a "TBT Buffs" lateral tab button in CDM settings window | SATISFIED | TBTSettingsTab frame in CDMTab.xml, anchored below AurasTab; user confirmed in-game |
| TAB-02 | 03-01-PLAN.md | User sees a TBT content panel when clicking the TBT tab | SATISFIED | ns:ShowTBTPanel / ns:HideTBTPanel with hooksecurefunc hook; user confirmed bidirectional switching |
| TAB-07 | 03-01-PLAN.md | Old standalone config UI is removed; /tbt opens CDM settings to TBT tab | SATISFIED | ConfigUI.lua deleted; Core.lua calls ns:SelectTBTTab(); user confirmed /tbt behavior |

No orphaned requirements. REQUIREMENTS.md Traceability table assigns TAB-01, TAB-02, TAB-07 exclusively to Phase 3. No additional IDs are mapped to this phase.

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| CDMTab.lua line 73 | scrollChild:SetHeight(1) | Info | Intentional stub height — scroll child will be populated by Phase 4. Not a rendering stub; tbtScrollChild is exposed as ns.tbtScrollChild for downstream use. |

No TODO/FIXME comments. No placeholder returns. No dead ToggleConfigUI references. No SetDisplayMode("tbt_buffs") calls anywhere in Lua files.

### Plan Spec vs. Implementation Deviations

The following PLAN artifact specs were superseded by deliberate post-checkpoint fixes. All deviations are documented in the SUMMARY frontmatter under `key-decisions` and `tech-stack.patterns`. None are gaps.

| PLAN Spec | Actual Implementation | Reason |
|-----------|----------------------|--------|
| `inherits="CooldownViewerSettingsTabTemplate"` | `inherits="LargeSideTabButtonTemplate"` | CooldownViewerSettingsTabTemplate's parentArray causes CDM secure taint |
| `parentArray="TabButtons"` | Removed entirely | Same taint reason; tabs accessed by parentKey (SpellsTab/AurasTab) directly |
| `activeAtlas="hud-buff"` / `inactiveAtlas="hud-buff"` KeyValues | SetTexture with tbt_icon_64x64.blp + override SetChecked | hud-buff atlas does not exist in Midnight |
| Panel with BackdropTemplate + custom backdrop | Plain ScrollFrame (no backdrop) | CDM's CooldownScroll itself has no backdrop; BackdropTemplate would visually mismatched |
| Preview via C_Timer.NewTicker | ns.configOpen flag (existing) | Display.lua already gates rendering on ns.configOpen; no new timer needed |

### Human Verification Required

All human verification was completed by the user before this report. The user approved all 10 in-game checks from Task 4:

1. TBT tab visible below Auras tab with addon icon (TAB-01)
2. Preview timer bars/icons appear when CDM opens (D-15)
3. Clicking TBT tab shows empty TBT panel, CDM scroll hidden (TAB-02)
4. Clicking Spells tab restores CDM content, TBT panel hidden (TAB-02)
5. TBT tab then Auras tab — same switching behavior (TAB-02)
6. Closing CDM — preview timers disappear (D-16)
7. /tbt — CDM opens with TBT tab selected (TAB-07)
8. /tbt while CDM is on Spells tab — switches to TBT tab without closing (TAB-07)
9. No taint errors
10. CDM Spells/Auras tabs work normally after TBT injection

### Gaps Summary

No gaps. All 7 must-have truths are verified. All 5 required artifacts exist and are substantive and wired. All 4 key links are confirmed. The three requirements (TAB-01, TAB-02, TAB-07) are satisfied. The one implementation deviation from the PLAN (LargeSideTabButtonTemplate instead of CooldownViewerSettingsTabTemplate) is a documented improvement, not a defect.

---

_Verified: 2026-03-29_
_Verifier: Claude (gsd-verifier)_
