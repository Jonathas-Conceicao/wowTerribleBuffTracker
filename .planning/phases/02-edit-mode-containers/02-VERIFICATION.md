---
phase: 02-edit-mode-containers
verified: 2026-03-28T00:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "EDM-01 — Two independent movable containers in Edit Mode"
    expected: "Both containers show Blizzard NineSlice highlight overlays; each drags independently"
    why_human: "WoW client required; frame dragging behavior cannot be tested headlessly"
  - test: "EDM-02 — Floating panel checkbox toggles TBT visibility"
    expected: "TBTEditModePanel appears adjacent to EditModeManagerFrame; unchecking hides containers and disables Edit Mode drag; rechecking restores"
    why_human: "WoW client required; panel anchoring and checkbox state verified visually"
  - test: "EDM-03 — Fresh install applies hardcoded position defaults"
    expected: "Containers appear at CENTER+300,0 and CENTER+300,-80 when editModePositions is nil"
    why_human: "WoW client required; position defaults apply at runtime, not readable from files alone"
  - test: "EDM-04 — Positions persist across /reload"
    expected: "After dragging a container and exiting Edit Mode, /reload restores saved position"
    why_human: "WoW client required; SavedVariables write/read requires live client"
  - test: "EDM-05 — CDM layout refresh does not move TBT containers"
    expected: "Changing CDM bar width or scale does not reanchor TBT containers"
    why_human: "WoW client required; CDM interaction cannot be simulated offline"
---

# Phase 2: Edit Mode Containers Verification Report

**Phase Goal:** Users can independently reposition the bars container and buffs container via Edit Mode
**Verified:** 2026-03-28
**Status:** passed
**Re-verification:** No — initial verification
**Note:** User confirmed all 5 EDM scenarios pass in-game. Several post-checkpoint fixes were applied and committed before this verification ran.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Two named container frames TBTBarContainer and TBTBuffContainer exist parented to UIParent | VERIFIED | `EditModeFrames.lua:348-355` — `CreateFrame("Frame", "TBTBarContainer", UIParent)` and `CreateFrame("Frame", "TBTBuffContainer", UIParent)` |
| 2 | Entering Edit Mode makes both containers draggable with visible Blizzard-style overlays | VERIFIED | `ns:OnEditModeEnter()` sets `SetMovable(true)` on both containers and wires `OnMouseDown`/`OnMouseUp` to the NineSlice overlay frames; `ns:ShowEditModeHandles()` shows both overlays |
| 3 | Exiting Edit Mode saves positions to ns.db.editModePositions and locks containers | VERIFIED | `ns:OnEditModeExit()` calls `ns:SaveEditModePositions()` then `SetMovable(false)` on both containers; `SaveEditModePositions` reads `GetPoint(1)` and writes both `bars` and `icons` sub-tables |
| 4 | A TBT visibility control appears in Edit Mode as a floating panel adjacent to EditModeManagerFrame | VERIFIED | `CreateEditModePanel()` creates `TBTEditModePanel` with `DialogBorderTranslucentTemplate` and `UICheckButtonTemplate`, anchored via `OnUpdate` tracking to `EditModeManagerFrame:BOTTOMLEFT`; plan deviated from sidebar injection (which failed in Midnight) to this pattern — user approved |
| 5 | Fresh install (editModePositions==nil) applies hardcoded CENTER+300,0 and CENTER+300,-80 defaults | VERIFIED | `ApplyEditModePositions()` lines 11-28: nil-guard writes bars `{point="CENTER", x=300, y=0}` and icons `{point="CENTER", x=300, y=-80}` to `ns.db.editModePositions` before reading it |
| 6 | tbtVisible toggle hides/shows both containers (or controls Edit Mode active state) | VERIFIED | Checkbox `OnClick` handler: checked path sets `ns.editModeActive=true` and calls `ShowEditModeHandles()`; unchecked path sets `ns.editModeActive=false` and calls `HideEditModeHandles()` + `UpdateDisplay()`; `ns.db.tbtVisible` written on each toggle |
| 7 | Display.lua no longer creates its own containers — uses ns.barContainer and ns.iconContainer | VERIFIED | No `local barContainer` or `local iconContainer` in Display.lua; pool getters use `CreateTimerBar(ns.barContainer)` and `CreateTimerIcon(ns.iconContainer)`; all UpdateDisplay references use namespace |
| 8 | All CDM layout hooks and settings snapshot functions are deleted from Display.lua | VERIFIED | `grep "SnapshotSettings\|ReadBarSettings\|ReadIconSettings\|HookViewerLayout\|GetCDMBarWidth"` returns 0 matches in Display.lua |
| 9 | TBT container positioning is independent of CDM viewer frames | VERIFIED | No `HookViewerLayout` calls remain; no CDM `EditMode.Exit` callback in Display.lua; icon SetPoint calls anchor to `ns.iconContainer` not `ns.cdmIconViewer`; CDM viewers only checked for existence in `InitDisplay()` |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `EditModeFrames.lua` | Container creation, drag handles, Edit Mode enter/exit, sidebar checkbox, position persistence | VERIFIED | 373 lines (exceeds min 120); all required functions present and substantive |
| `Core.lua` | DB init for editModePositions and tbtVisible, InitEditModeFrames call before InitDisplay | VERIFIED | `tbtVisible` nil-guard at line 28-30; `ns:InitEditModeFrames()` at line 41 before `ns:InitDisplay()` at line 42 |
| `TerribleBuffTracker.toc` | EditModeFrames.lua listed before Display.lua | VERIFIED | Load order: Core.lua, BuffEngine.lua, EditModeFrames.lua, Display.lua, ConfigUI.lua |
| `Display.lua` | CDM-decoupled display rendering using Edit Mode containers | VERIFIED | All CDM hooks removed; hardcoded `cachedBarSettings` and `cachedIconSettings` at module level; icon container auto-resized after each render cycle |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| EditModeFrames.lua | Core.lua | `ns:InitEditModeFrames()` called in PLAYER_ENTERING_WORLD before `ns:InitDisplay()` | WIRED | Core.lua lines 41-42 — order confirmed |
| EditModeFrames.lua | ns.barContainer / ns.iconContainer | namespace exports consumed by Display.lua | WIRED | Display.lua uses `ns.barContainer` (7 refs) and `ns.iconContainer` (12 refs) throughout pool getters and UpdateDisplay |
| EditModeFrames.lua | ns.db.editModePositions | SaveEditModePositions writes, ApplyEditModePositions reads | WIRED | Write path: lines 157-158; Read path: lines 30-37; Fresh install write: lines 12-27 |
| Display.lua | EditModeFrames.lua | ns.barContainer / ns.iconContainer namespace references | WIRED | Confirmed above |
| Display.lua | ns.editModeActive | barEditing and iconEditing local aliases assigned from ns.editModeActive | WIRED | Display.lua lines 356 and 476 — both assign `ns.editModeActive` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| Display.lua UpdateDisplay (bars) | ns.barContainer | EditModeFrames.lua `ns:InitEditModeFrames()` → `CreateFrame(...)` | Yes — live WoW frame object | FLOWING |
| Display.lua UpdateDisplay (icons) | ns.iconContainer | EditModeFrames.lua `ns:InitEditModeFrames()` → `CreateFrame(...)` | Yes — live WoW frame object | FLOWING |
| EditModeFrames.lua ApplyEditModePositions | ns.db.editModePositions | SavedVariables (TerribleBuffTrackerDB) or hardcoded defaults on nil | Yes — DB read or hardcoded non-empty defaults | FLOWING |
| EditModeFrames.lua floating panel checkbox | ns.db.tbtVisible | Core.lua ADDON_LOADED nil-guard initializes to `true`; checkbox OnClick writes on toggle | Yes — boolean DB value | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED (no runnable entry points — WoW addon requires live client)

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EDM-01 | 02-01, 02-02 | User sees two independent movable elements (bars container, buffs container) in Edit Mode | SATISFIED | TBTBarContainer and TBTBuffContainer created as UIParent frames; NineSlice overlays act as drag targets; user confirmed in-game |
| EDM-02 | 02-01 | User can toggle bar/buff container visibility via Edit Mode sidebar checkboxes | SATISFIED | TBTEditModePanel floating checkbox replaces sidebar injection (which was inaccessible in Midnight); same functional contract satisfied; user confirmed in-game |
| EDM-03 | 02-01, 02-02 | Fresh install copies CDM position/scale settings once as initial values | SATISFIED | Note: spec was updated to hardcoded defaults (not CDM copy — per D-06/D-07 decisions). ApplyEditModePositions writes CENTER+300,0 / CENTER+300,-80 on nil. User confirmed in-game |
| EDM-04 | 02-01, 02-02 | After initial copy, TBT position/scale is set exclusively via Edit Mode | SATISFIED | SaveEditModePositions called only on OnEditModeExit; no CDM hooks reanchor containers; user confirmed in-game |
| EDM-05 | 02-01, 02-02 | Display does not re-anchor to CDM when CDM layout refreshes | SATISFIED | All HookViewerLayout / SnapshotSettings / CDM EditMode.Exit snapshot code removed from Display.lua; user confirmed in-game |

**Orphaned requirements check:** REQUIREMENTS.md traceability table maps EDM-01 through EDM-05 exclusively to Phase 2. All 5 are accounted for in plans 02-01 and 02-02. No orphaned IDs.

**Requirements not covered by this phase:** MIG-01, MIG-02 (Phase 1 — already complete); TAB-*, DND-* (Phases 3-5 — pending). All correctly excluded from Phase 2 plans.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| EditModeFrames.lua | 248-258 | `OnUpdate` polling every 0.25s to reanchor TBTEditModePanel to EditModeManagerFrame | Info | Negligible cost at 4 polls/second; panel is only shown during Edit Mode sessions |

No blocker or warning anti-patterns found. The `OnUpdate` position tracker is a known pattern from Plumber addon and is acceptable. No TODO/FIXME/placeholder comments. No empty return stubs. All hardcoded defaults (`cachedBarSettings`, `cachedIconSettings`) are complete value tables, not nil placeholders.

---

### Human Verification Required

All 5 items were verified in-game by the user prior to this report. The items below are documented for completeness and traceability.

**1. EDM-01 — Two independent movable containers**
**Test:** Enter Edit Mode; verify both containers show NineSlice highlight overlays; drag each container to a different position independently.
**Expected:** Both containers are draggable; each moves without affecting the other.
**Why human:** WoW client required; frame dragging cannot be simulated offline.
**Status:** PASSED (user confirmed)

**2. EDM-02 — Floating panel checkbox**
**Test:** Enter Edit Mode; locate TBTEditModePanel below the Edit Mode manager dialog; uncheck TerribleBuffTracker; re-check it.
**Expected:** Unchecking hides overlays and disables drag behavior, showing only active buff timers; rechecking re-enables Edit Mode dragging.
**Why human:** WoW client required; panel anchoring and checkbox state are visual.
**Status:** PASSED (user confirmed)

**3. EDM-03 — Fresh install defaults**
**Test:** Run `/run TerribleBuffTrackerDB.editModePositions = nil` then `/reload`; enter Edit Mode.
**Expected:** Containers appear at center-right of screen (CENTER+300,0 and CENTER+300,-80).
**Why human:** WoW client required; position defaults apply at runtime.
**Status:** PASSED (user confirmed)

**4. EDM-04 — Position persistence**
**Test:** Drag a container in Edit Mode; exit Edit Mode; `/reload`; enter Edit Mode.
**Expected:** Container is in the same saved position.
**Why human:** WoW client required; SavedVariables write/read requires live client.
**Status:** PASSED (user confirmed)

**5. EDM-05 — CDM independence**
**Test:** Set TBT container position in Edit Mode; exit; open CDM settings and change bar width or scale.
**Expected:** TBT containers do not move.
**Why human:** WoW client required; CDM interaction cannot be simulated offline.
**Status:** PASSED (user confirmed)

---

### Gaps Summary

No gaps found. All must-haves are verified at all applicable levels (exists, substantive, wired, data-flowing). The plan deviated from two implementation details — `BasicOptionsContainer` sidebar injection was replaced by a floating panel, and 24px drag handles were replaced by full-container NineSlice overlays — but both deviations were driven by Midnight API limitations and user feedback, and both satisfy the same EDM-02 and EDM-01 requirements respectively. The user confirmed all 5 EDM scenarios pass in-game.

---

_Verified: 2026-03-28_
_Verifier: Claude (gsd-verifier)_
