---
phase: 05-drag-and-drop
verified: 2026-03-29T00:00:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 05: Drag-and-Drop Verification Report

**Phase Goal:** Users can reassign a buff's display mode by dragging its icon from one section to another
**Verified:** 2026-03-29
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                   | Status     | Evidence                                                                                         |
|----|-----------------------------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------|
| 1  | User can drag a buff icon from one section and drop it in another to change display mode | ✓ VERIFIED | `EndDrag` calls `ns:SetBuffSection` + `ns:RefreshTBTSections` when `SectionHitTest` returns a valid key |
| 2  | A ghost copy of the buff icon follows the cursor at 50% alpha during the drag            | ✓ VERIFIED | `GetOrCreateGhostFrame` creates frame at `TOOLTIP` strata, `SetAlpha(0.5)`, OnUpdate uses `GetScaledCursorPositionForFrame` |
| 3  | Valid drop target sections visually highlight when cursor enters them during a drag      | ✓ VERIFIED | CDM-style `tbtReorderMarker` (UI-ChatFrame-DockHighlight, ADD blend) repositioned per-frame via `OnDragUpdate` |
| 4  | The delete zone highlights distinctly (red) when cursor hovers over it during a drag    | ✓ VERIFIED | `dragHighlight` texture (red, ADD blend) on `ns.tbtDeleteZone`, toggled by `SetDeleteZoneHighlight` |
| 5  | Dropping a buff on the delete zone removes it from the DB                               | ✓ VERIFIED | `EndDrag(true)` → `SectionHitTest` returns `"delete"` → `ns:RemoveTrackedBuff(spellID)` |
| 6  | Dropping outside all valid sections cancels the drag with no section change             | ✓ VERIFIED | `SectionHitTest` returns `nil` → `EndDrag` falls through to `wipe(tbtDragState)` with no DB write |
| 7  | Right-click context menu on icons still works after drag implementation                  | ✓ VERIFIED | `OnMouseDown` only fires for `LeftButton`; `OnMouseUp` `RightButton` handler untouched (lines 96–138) |
| 8  | No OnUpdate callback runs when no drag is in progress                                    | ✓ VERIFIED | `ns.tbtPanel:SetScript("OnUpdate", OnDragUpdate)` set in `BeginDrag`; `nil`'d in `EndDrag` — idle cost is zero |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact      | Expected                                              | Status     | Details                                                                     |
|---------------|-------------------------------------------------------|------------|-----------------------------------------------------------------------------|
| `CDMTab.lua`  | Drag state machine, ghost frame, hit-testing, markers | ✓ VERIFIED | 985 lines; contains all drag subsystems — see key counts below              |
| `BuffEngine.lua` | `SetBuffSection`, schema v2 migration, `layoutOrder` | ✓ VERIFIED | `SetBuffSection` at line 179; schema v2 backfill at lines 27–35; `layoutOrder` assigned on `AddTrackedBuff` |
| `Display.lua` | Sorts bars/buffs by `layoutOrder`                     | ✓ VERIFIED | `table.sort` by `layoutOrder` for both bar slots (line 381) and buff slots (line 493) |

**Key pattern counts in CDMTab.lua (acceptance criteria):**

| Pattern                   | Count | Threshold | Pass? |
|---------------------------|-------|-----------|-------|
| `tbtDragState`            | 15    | ≥1        | yes   |
| `BeginDrag`               | 6     | ≥2        | yes   |
| `EndDrag`                 | 9     | ≥4        | yes   |
| `GLOBAL_MOUSE_UP`         | 5     | ≥2        | yes   |
| `OnMouseDown`             | 1     | ≥1        | yes   |
| `GetOrCreateGhostFrame`   | 3     | ≥3        | yes   |
| `SOUNDKIT`                | 3     | ≥1        | yes   |
| `SectionHitTest`          | 3     | ≥2        | yes   |
| `RegionUtil.GetSides`     | 8     | ≥3        | yes   |
| `VALID_DROP_SECTIONS`     | 3     | ≥2        | yes   |
| `dragHighlight`           | 5     | ≥1        | yes   |
| `GetOrCreateReorderMarker`| 3     | ≥1        | yes   |
| `layoutOrder`             | 6     | ≥1        | yes   |
| `wipe(tbtDragState)`      | 3     | ≥1        | yes   |

---

### Key Link Verification

| From                              | To                              | Via                                       | Status     | Details                                                                              |
|-----------------------------------|---------------------------------|-------------------------------------------|------------|--------------------------------------------------------------------------------------|
| `CDMTab.lua (OnMouseDown)`        | `CDMTab.lua (BeginDrag)`        | `LeftButton` guard + `BeginDrag(self)` call | ✓ WIRED   | Lines 58–66: `if button == "LeftButton" and self.spellID and self.sectionName ~= "suggested"` then `BeginDrag(self)` |
| `CDMTab.lua (BeginDrag)`          | `CDMTab.lua (EndDrag)`          | `GLOBAL_MOUSE_UP` event on `ns.tbtPanel`  | ✓ WIRED    | `RegisterEvent("GLOBAL_MOUSE_UP")` in `BeginDrag`; `OnEvent` handler calls `EndDrag(true/false)` at lines 857–866 |
| `CDMTab.lua (EndDrag)`            | `BuffEngine.lua (ns:SetBuffSection)` | `SectionHitTest` result + `SetBuffSection` + `RefreshTBTSections` | ✓ WIRED | Lines 403–444: `SectionHitTest()` → `ns:SetBuffSection(spellID, targetSection)` → `ns:RefreshTBTSections()` |
| `CDMTab.lua (BeginDrag)`          | `CDMTab.lua (OnDragUpdate)`     | `ns.tbtPanel:SetScript("OnUpdate", OnDragUpdate)` | ✓ WIRED | Line 334: set in `BeginDrag`; line 393: nil'd in `EndDrag` |
| `CDMTab.lua (EndDrag → delete)`   | `BuffEngine.lua (ns:RemoveTrackedBuff)` | `result == "delete"` branch | ✓ WIRED | Lines 404–409: `ns:RemoveTrackedBuff(spellID)` + `ns:RefreshTBTSections()` + `PlaySound` |

---

### Data-Flow Trace (Level 4)

| Artifact     | Data Variable | Source                         | Produces Real Data | Status     |
|--------------|---------------|--------------------------------|--------------------|------------|
| `CDMTab.lua` | `tbtDragState.spellID` | Set in `BeginDrag` from `iconFrame.spellID`; `iconFrame.spellID` populated in `RefreshTBTSections` from `ns.db.trackedBuffs` | Yes — DB-backed | ✓ FLOWING |
| `Display.lua` (bars) | `barSlots` | `ns.db.trackedBuffs` filtered by `section == "bars"`, sorted by `layoutOrder` | Yes — DB-backed | ✓ FLOWING |
| `Display.lua` (buffs) | `buffSlots` | `ns.db.trackedBuffs` filtered by `section == "buffs"`, sorted by `layoutOrder` | Yes — DB-backed | ✓ FLOWING |
| `BuffEngine.lua` | `entry.layoutOrder` | Backfilled in schema v2 migration; assigned `maxOrder + 1` in `AddTrackedBuff`; renumbered in `EndDrag` after drop | Yes — DB-persisted | ✓ FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — code runs inside WoW game client; no runnable entry points outside the game. User performed all 12 in-game checks (documented in SUMMARY.md).

---

### Requirements Coverage

| Requirement | Source Plan | Description                                                   | Status       | Evidence                                                                                       |
|-------------|-------------|---------------------------------------------------------------|--------------|-----------------------------------------------------------------------------------------------|
| DND-01      | 05-01-PLAN  | User can drag a buff from one section to another to change its display mode | ✓ SATISFIED | `EndDrag` → `SectionHitTest` → `ns:SetBuffSection`; delete zone → `ns:RemoveTrackedBuff`; cancel on nil/suggested/right-click |
| DND-02      | 05-01-PLAN  | User sees a ghost frame following cursor during drag           | ✓ SATISFIED | `GetOrCreateGhostFrame`: TOOLTIP strata, 0.5 alpha, `GetScaledCursorPositionForFrame` OnUpdate |
| DND-03      | 05-01-PLAN  | User sees drop zone highlighting when dragging over valid targets | ✓ SATISFIED | CDM-style `tbtReorderMarker` for section insertion; red `dragHighlight` for delete zone; both cleared in `EndDrag` |

**Note:** REQUIREMENTS.md lists "Within-section reordering" as out of scope for v0.2.0, but the implementation includes it (via `layoutOrder` and `GetDropLayoutOrder`). This is a scope expansion beyond requirements — it satisfies all three DND requirements and adds bonus functionality. The REQUIREMENTS.md `Out of Scope` table is now stale for this item; it should be updated in Phase 6 cleanup.

**Orphaned requirements check:** TAB-06 ("User can drag a buff onto the delete drop zone in Not Displayed to remove it") is mapped to Phase 4 in REQUIREMENTS.md but is fully implemented in this phase's `EndDrag` delete-zone path. It is functionally satisfied here, though REQUIREMENTS.md still shows it as Phase 4 / pending.

---

### Anti-Patterns Found

| File        | Line | Pattern                                       | Severity | Impact                                                                               |
|-------------|------|-----------------------------------------------|----------|--------------------------------------------------------------------------------------|
| `CDMTab.lua` | 356–364 | `local items = {}` + `table.insert` in `GetDropLayoutOrder` | info | Called only in `EndDrag` on commit (not in hot path `OnDragUpdate`). No per-frame GC concern. |
| `CDMTab.lua` | 427–436 | `local sectionEntries = {}` + `table.insert` in `EndDrag` renumber pass | info | One-shot on drop commit. No idle cost. |
| `CDMTab.lua` | 848 | `scrollChild:SetWidth(1) -- placeholder until OnShow fires` | info | Comment uses word "placeholder" but the value is a legitimate initialization default, not a stub. Clarified by the comment. |

No blocker anti-patterns found. All allocations are in commit-path `EndDrag` or one-time setup, not in `OnDragUpdate` or other per-frame paths.

---

### Human Verification Required

All in-game behavioral checks were performed by the user. The following 12 checks were confirmed passing per SUMMARY.md:

1. Drag between all sections (bars, buffs, hidden) changes section in DB correctly
2. Cancel on drop outside sections — no section change
3. Cancel on drop over Suggested — no section change
4. Right-click cancels drag
5. Delete zone drag removes buff from DB
6. Ghost frame follows cursor at 50% alpha with correct spell icon
7. CDM-style ReorderMarker shows insertion position during drag
8. Within-section reorder changes `layoutOrder` and reflects in Display
9. Right-click context menu coexists with drag (no interference)
10. Escape key mid-drag cancels cleanly with no Lua errors
11. Collapsed sections reject drops
12. No Lua errors throughout all scenarios

---

### Gaps Summary

No gaps. All 8 must-have truths are verified at all four levels (exists, substantive, wired, data flowing). The three DND requirements are fully satisfied. In-game human verification passed all 12 checks.

The implementation exceeds the PLAN spec in two ways:
- Within-section reordering via `layoutOrder` (was out of scope per REQUIREMENTS.md, added per user request during checkpoint)
- CDM-style `tbtReorderMarker` insertion line instead of section-wide highlight overlays (design decision made during checkpoint review)

Both additions are coherent, do not break any requirements, and are documented in the SUMMARY.

---

_Verified: 2026-03-29_
_Verifier: Claude (gsd-verifier)_
