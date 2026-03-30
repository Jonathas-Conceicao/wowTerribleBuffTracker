# Phase 5: Drag-and-Drop - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement drag-and-drop for buff icons between TBT tab sections. Users can drag a buff from one section and drop it in another to change its display mode. Ghost frame follows cursor, sections highlight on hover, delete zone in Not Displayed removes the buff. No new sections or UI elements — this phase wires interactivity onto the existing Phase 4 section framework.

</domain>

<decisions>
## Implementation Decisions

### Drag initiation
- **D-01:** Left click and hold on a buff icon starts the drag immediately. Match CDM's own drag pattern from Blizzard source.
- **D-02:** Ghost frame appears at TOOLTIP strata following cursor via OnUpdate. Uses `GetScaledCursorPosition()` or `GetCursorPosition()` with scale compensation.

### Drop zone behavior
- **D-03:** Valid drop targets: Tracked Bars (→ section="bars"), Tracked Buffs (→ section="buffs"), Not Displayed (→ section="hidden"), and the delete zone (→ remove from DB).
- **D-04:** Suggested section is NOT a valid drop target — drops on Suggested are treated as cancel.
- **D-05:** Dropping outside all sections cancels the drag — buff returns to its original section. No section change.

### Visual feedback
- **D-06:** Ghost frame: copy of the buff icon at TOOLTIP strata, 50% alpha. Follows cursor via OnUpdate during drag.
- **D-07:** Section highlight: when cursor enters a valid drop target section, that section gets a visual highlight matching CDM's style. Highlight clears on cursor leave.
- **D-08:** Delete zone highlight: when cursor hovers over the delete zone, it highlights distinctly (red glow or brighter red) to signal destructive action.

### Drag lifecycle
- **D-09:** Drag commits on `GLOBAL_MOUSE_UP` event (not per-frame mouse button check). This is CDM's own pattern — reliable across all frame strata.
- **D-10:** On commit: determine which section/zone the cursor is over, call `ns:SetBuffSection()` or `ns:RemoveTrackedBuff()`, then `ns:RefreshTBTSections()`.
- **D-11:** On cancel (drop outside valid targets or right-click during drag): hide ghost, clear highlights, no section change.
- **D-12:** OnUpdate callback for cursor tracking is only active during a drag — unregistered when drag ends to avoid per-frame cost when idle.

### Claude's Discretion
- Exact hit-test implementation (point-in-rect vs GetBestTarget proximity)
- Ghost frame size (same as icon 38x38, or slightly larger)
- Whether to dim the source icon during drag
- Highlight texture choice for sections

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing code
- `CDMTab.lua` — Section framework (`ns.tbtSections`), icon pool, `RefreshTBTSections()`, `ns.tbtDeleteZone`, icon OnMouseUp handler (right-click context menu — must coexist with left-click drag)
- `BuffEngine.lua` — `ns:SetBuffSection()`, `ns:RemoveTrackedBuff()`, `ns:GetSpellIcon()`

### Blizzard UI source
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — CDM drag implementation: ghost frame, OnUpdate cursor tracking, GLOBAL_MOUSE_UP commit, GetBestCooldownItemTarget hit-test

### Research
- `.planning/research/STACK.md` — CDM drag pattern details (ghost frame at TOOLTIP strata, GLOBAL_MOUSE_UP, GetScaledCursorPositionForFrame)
- `.planning/research/PITFALLS.md` — Drag strata issues, GLOBAL_MOUSE_UP session scoping

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:SetBuffSection(spellID, section)` — changes section and updates display
- `ns:RemoveTrackedBuff(spellID)` — removes from DB and active timers
- `ns:RefreshTBTSections()` — rebuilds all section icon grids
- `ns:GetSpellIcon(spellID)` — returns icon texture ID
- `ns.tbtDeleteZone` — the red X frame in Not Displayed, already created
- `ns.tbtSections[key].container` — GridLayoutFrame containers for hit-testing

### Established Patterns
- Icon frames have `spellID` and `sectionName` fields set during RefreshTBTSections
- OnMouseUp on icons handles right-click context menu — left-click drag must coexist
- OnUpdate watcher pattern (used for CDM visibility in Phase 3) — same pattern for cursor tracking

### Integration Points
- Icon `OnMouseDown` — start drag (left button)
- Icon `OnMouseUp` — keep right-click context menu (from Phase 4)
- `GLOBAL_MOUSE_UP` event — commit/cancel drag
- `ns.tbtSections[key].container` frames — drop target hit-testing
- `ns.tbtDeleteZone` — delete drop target

</code_context>

<specifics>
## Specific Ideas

- Drag should feel identical to CDM's own drag behavior — reference Blizzard source
- Ghost frame should be a simple texture copy, not a full interactive frame

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-drag-and-drop*
*Context gathered: 2026-03-29*
