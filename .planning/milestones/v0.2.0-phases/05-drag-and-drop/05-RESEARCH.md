# Phase 5: Drag-and-Drop - Research

**Researched:** 2026-03-29
**Domain:** WoW Lua frame drag-and-drop — manual ghost-frame pattern, GLOBAL_MOUSE_UP lifecycle, point-in-rect hit-testing
**Confidence:** HIGH (all findings verified from Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Left click and hold on a buff icon starts the drag immediately. Match CDM's own drag pattern from Blizzard source.
- **D-02:** Ghost frame appears at TOOLTIP strata following cursor via OnUpdate. Uses `GetScaledCursorPosition()` or `GetCursorPosition()` with scale compensation.
- **D-03:** Valid drop targets: Tracked Bars (→ section="bars"), Tracked Buffs (→ section="buffs"), Not Displayed (→ section="hidden"), and the delete zone (→ remove from DB).
- **D-04:** Suggested section is NOT a valid drop target — drops on Suggested are treated as cancel.
- **D-05:** Dropping outside all sections cancels the drag — buff returns to its original section. No section change.
- **D-06:** Ghost frame: copy of the buff icon at TOOLTIP strata, 50% alpha. Follows cursor via OnUpdate during drag.
- **D-07:** Section highlight: when cursor enters a valid drop target section, that section gets a visual highlight matching CDM's style. Highlight clears on cursor leave.
- **D-08:** Delete zone highlight: when cursor hovers over the delete zone, it highlights distinctly (red glow or brighter red) to signal destructive action.
- **D-09:** Drag commits on `GLOBAL_MOUSE_UP` event (not per-frame mouse button check). This is CDM's own pattern — reliable across all frame strata.
- **D-10:** On commit: determine which section/zone the cursor is over, call `ns:SetBuffSection()` or `ns:RemoveTrackedBuff()`, then `ns:RefreshTBTSections()`.
- **D-11:** On cancel (drop outside valid targets or right-click during drag): hide ghost, clear highlights, no section change.
- **D-12:** OnUpdate callback for cursor tracking is only active during a drag — unregistered when drag ends to avoid per-frame cost when idle.

### Claude's Discretion

- Exact hit-test implementation (point-in-rect vs GetBestTarget proximity)
- Ghost frame size (same as icon 38x38, or slightly larger)
- Whether to dim the source icon during drag
- Highlight texture choice for sections

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DND-01 | User can drag a buff from one section to another to change its display mode | Ghost frame pattern + GLOBAL_MOUSE_UP lifecycle + hit-test on section containers → calls `ns:SetBuffSection()` |
| DND-02 | User sees a ghost frame following cursor during drag | `CooldownViewerSettingsDraggedItemMixin:OnUpdate` pattern — `GetScaledCursorPositionForFrame(topLevel)` → `SetPoint("TOPLEFT", topLevel, "BOTTOMLEFT", x, y)` |
| DND-03 | User sees drop zone highlighting when dragging over valid targets | `OnEnter` on section containers and delete zone during drag; highlight texture shown/hidden per section |
</phase_requirements>

---

## Summary

Phase 5 wires drag-and-drop interactivity onto the section framework built in Phase 4. All implementation decisions are locked — the CDM Blizzard source provides exact patterns for each component. The key insight is that CDM's drag system is entirely manual (no WoW native cursor drag): a ghost frame at TOOLTIP strata follows the cursor via `OnUpdate`, `GLOBAL_MOUSE_UP` terminates the drag session, and drop targets are found via hit-testing.

TBT's implementation differs from CDM in one important way: CDM drags items *within* a single settings panel (reordering within a category list), while TBT drags items *between* sections (changing `section` field in `TerribleBuffTrackerDB`). The ghost frame and lifecycle machinery is identical; only the commit logic differs — TBT calls `ns:SetBuffSection()` or `ns:RemoveTrackedBuff()` instead of CDM's `ChangeOrderIndex`/`SetCooldownToCategory`.

Hit-testing for TBT is simpler than CDM's nearest-item-weighted approach because TBT only needs to know *which section* the cursor is over (not which item within the section). A point-in-rect test against `ns.tbtSections[key].container` (using `RegionUtil.GetSides` or `frame:GetLeft/Right/Top/Bottom`) is sufficient and correct.

**Primary recommendation:** Implement in CDMTab.lua as a drag state machine (idle → dragging → commit/cancel) with a module-level drag state table. Reuse `ns.tbtPanel` as the GLOBAL_MOUSE_UP handler frame. All section hit-testing happens at commit time, not per-frame.

---

## Standard Stack

### Core APIs

| API | Source | Purpose | Why Standard |
|-----|--------|---------|--------------|
| `CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")` | CooldownViewerSettings.lua:44-46 | Ghost cursor frame creation | CDM's exact pattern; lazy-creates once, reuses across drags |
| `GetScaledCursorPositionForFrame(topLevel)` | CooldownViewerSettings.lua:38 | Cursor position in ghost OnUpdate | Handles UI scale correctly across all display configurations |
| `GetCursorPosition()` + divide by `GetAppropriateTopLevelParent():GetScale()` | CooldownViewerSettings.lua:1339-1341 | Hit-test cursor position in OnUpdate | CDM uses this in `UpdateReorderMarker`; needed when comparing to frame coordinates |
| `self:RegisterEvent("GLOBAL_MOUSE_UP")` / `self:UnregisterEvent("GLOBAL_MOUSE_UP")` | CooldownViewerSettings.lua:1255, 1284 | Drag session lifecycle | Fires on mouse release regardless of cursor position; CDM's authoritative pattern |
| `self:SetScript("OnUpdate", self.OnUpdate)` / `self:SetScript("OnUpdate", nil)` | CooldownViewerSettings.lua:1253, 1282 | OnUpdate active only during drag | Nil-ing the script eliminates per-frame cost when idle |
| `RegionUtil.GetSides(frame)` | CooldownViewerSettings.lua:728 | Returns `left, right, bottom, top` for hit-testing | CDM uses this in `GetNearestItemToCursorWeighted`; correct way to get frame bounds |
| `PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)` | CooldownViewerSettings.lua:273 | Drag start audio | CDM plays this on drag start |
| `PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)` | CooldownViewerSettings.lua:1369 | Drag end audio (commit only) | CDM plays this on successful drop |

### Ghost Frame XML Template (from Blizzard source)

```xml
<!-- CooldownViewerSettings.xml:4-10 — exact template TBT ghost mimics -->
<Frame name="CooldownViewerSettingsDraggedItemTemplate"
       mixin="CooldownViewerSettingsDraggedItemMixin"
       frameStrata="TOOLTIP" virtual="true">
    <Size x="38" y="38"/>
    <Layers>
        <Layer level="OVERLAY" textureSubLevel="6">
            <Texture parentKey="Icon" setAllPoints="true"/>
        </Layer>
    </Layers>
</Frame>
```

TBT should NOT inherit this template (it belongs to CDM's spell data system). Create an equivalent plain frame at TOOLTIP strata with a texture child.

---

## Architecture Patterns

### Recommended Project Structure

No new files. All drag code lives in `CDMTab.lua`, within the existing section/tab framework.

```
CDMTab.lua
├── module-level drag state table  (tbtDragState)
├── CreateGhostFrame()             (lazy init, once per session)
├── BeginDrag(iconFrame)           (start: ghost show, OnUpdate on, GLOBAL_MOUSE_UP register)
├── EndDrag(commit)                (end: hit-test, apply change, ghost hide, cleanup)
├── OnDragUpdate()                 (ghost follows cursor — active only during drag)
├── OnDragEvent(event, button)     (GLOBAL_MOUSE_UP handler — routed from ns.tbtPanel OnEvent)
├── SectionHitTest(cursorX, cursorY) (returns section key or nil)
└── SetSectionHighlight(key, active) (show/hide highlight overlay per section)
```

### Pattern 1: Ghost Frame Creation (Lazy Init)

**What:** Ghost frame is created once on first drag, reused for all subsequent drags. Parented to `GetAppropriateTopLevelParent()` at TOOLTIP strata.

**When to use:** On `BeginDrag()`.

```lua
-- Source: CooldownViewerSettings.lua:42-49
local tbtGhostFrame
local function GetOrCreateGhostFrame()
    if not tbtGhostFrame then
        local topLevel = GetAppropriateTopLevelParent()
        tbtGhostFrame = CreateFrame("Frame", nil, topLevel)
        tbtGhostFrame:SetSize(38, 38)
        tbtGhostFrame:SetFrameStrata("TOOLTIP")
        tbtGhostFrame:SetAlpha(0.5)
        local icon = tbtGhostFrame:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints(tbtGhostFrame)
        tbtGhostFrame.Icon = icon
        tbtGhostFrame:SetScript("OnUpdate", function(self)
            local x, y = GetScaledCursorPositionForFrame(topLevel)
            self:SetPoint("TOPLEFT", topLevel, "BOTTOMLEFT", x, y)
        end)
    end
    return tbtGhostFrame
end
```

**Critical:** The `topLevel` reference captured at creation time must stay valid. `GetAppropriateTopLevelParent()` returns `UIParent` for non-fullscreen UI — safe to capture once.

### Pattern 2: Drag Lifecycle (BeginDrag / EndDrag)

**What:** State machine with a module-level table tracking drag source. GLOBAL_MOUSE_UP registered on `ns.tbtPanel` (a frame that's already active when the CDM panel is open).

```lua
-- Source: CooldownViewerSettings.lua:1240-1285 (adapted for TBT)
local tbtDragState = {}  -- module-level, wiped on EndDrag

local function BeginDrag(iconFrame)
    if tbtDragState.active then return end

    tbtDragState.active = true
    tbtDragState.spellID = iconFrame.spellID
    tbtDragState.originalSection = iconFrame.sectionName

    -- Dim source icon (Claude's discretion)
    iconFrame:SetAlpha(0.4)
    tbtDragState.sourceFrame = iconFrame

    -- Ghost follows cursor
    local ghost = GetOrCreateGhostFrame()
    ghost.Icon:SetTexture(ns:GetSpellIcon(iconFrame.spellID))
    ghost:Show()

    -- OnUpdate active only during drag
    ns.tbtPanel:SetScript("OnUpdate", OnDragUpdate)

    -- GLOBAL_MOUSE_UP for session termination
    ns.tbtPanel:RegisterEvent("GLOBAL_MOUSE_UP")

    PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
end

local function EndDrag(commit)
    if not tbtDragState.active then return end

    -- Cleanup first (matches CDM's CancelOrderChange pattern)
    local ghost = GetOrCreateGhostFrame()
    ghost:Hide()

    ns.tbtPanel:SetScript("OnUpdate", nil)
    ns.tbtPanel:UnregisterEvent("GLOBAL_MOUSE_UP")

    -- Clear section highlights
    SetAllSectionHighlights(false)

    -- Restore source icon alpha
    if tbtDragState.sourceFrame then
        tbtDragState.sourceFrame:SetAlpha(1.0)
    end

    if commit then
        PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
        local targetSection = SectionHitTest()
        if targetSection == "delete" then
            ns:RemoveTrackedBuff(tbtDragState.spellID)
            ns:RefreshTBTSections()
        elseif targetSection and targetSection ~= "suggested"
               and targetSection ~= tbtDragState.originalSection then
            ns:SetBuffSection(tbtDragState.spellID, targetSection)
            ns:RefreshTBTSections()
        end
        -- If targetSection == nil or == "suggested": cancel silently (D-04, D-05)
    end

    wipe(tbtDragState)
end
```

### Pattern 3: GLOBAL_MOUSE_UP Routing

**What:** `ns.tbtPanel` (the ScrollFrame) handles the event. `OnEvent` must be set on the frame before registering the event.

```lua
-- Source: CooldownViewerSettings.lua:1358-1376
ns.tbtPanel:SetScript("OnEvent", function(self, event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        local button = ...
        if button == "LeftButton" then
            EndDrag(true)   -- commit
        elseif button == "RightButton" then
            EndDrag(false)  -- cancel
        end
    end
end)
```

**Note:** CDM has an `eatNextGlobalMouseUp` mechanism (lines 1248, 1366-1368) to ignore the GLOBAL_MOUSE_UP that fires from the same click that initiated the drag via `OnMouseUp`. TBT triggers drag from `OnMouseDown` instead — so the mouse up that ends the drag is a *separate* subsequent event, not the same button release. No eat-next logic needed when using `OnMouseDown`.

### Pattern 4: Hit-Testing at Commit Time

**What:** At `EndDrag(commit=true)`, read cursor position once and test it against section container bounds. TBT does not need per-frame hit-testing (unlike CDM's reorder marker, which moves continuously) — the section destination only matters at the moment of release.

```lua
-- Source: CooldownViewerSettings.lua:1339-1341, 727-744
local function SectionHitTest()
    local scale = GetAppropriateTopLevelParent():GetScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    -- Check delete zone first (highest priority)
    if ns.tbtDeleteZone and ns.tbtDeleteZone:IsShown() then
        local left, right, bottom, top = RegionUtil.GetSides(ns.tbtDeleteZone)
        if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
            return "delete"
        end
    end

    -- Check each valid section container
    local validSections = { "bars", "buffs", "hidden" }
    for _, key in ipairs(validSections) do
        local section = ns.tbtSections and ns.tbtSections[key]
        if section and section.container and section.container:IsShown() then
            local left, right, bottom, top = RegionUtil.GetSides(section.container)
            if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
                return key
            end
        end
    end

    return nil  -- miss → cancel (D-05)
end
```

**Alternative considered:** Check `section.frame` (header + container combined) instead of just `section.container`. Using the full frame is more forgiving for users who release the mouse slightly above the grid. Discretion: use `section.frame` bounds for drop targeting to match CDM's approachable UX.

### Pattern 5: Section Highlight During Drag

**What:** Each valid section container gets a highlight overlay frame (created once, shown/hidden during drag via `OnEnter`/`OnLeave`-equivalent tracking). Since the ghost frame consumes mouse events at TOOLTIP strata, standard frame `OnEnter` won't fire on section containers during drag. Use per-frame cursor hit-testing in `OnDragUpdate` to drive section highlights.

```lua
-- Highlight overlay created once per section in BuildAllSections()
local function CreateSectionHighlight(container)
    local highlight = container:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints(container)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    highlight:Hide()
    return highlight
end

-- In OnDragUpdate: update which section is highlighted
local function OnDragUpdate()
    local scale = GetAppropriateTopLevelParent():GetScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local hoveredSection = nil
    for _, key in ipairs({ "bars", "buffs", "hidden" }) do
        local section = ns.tbtSections and ns.tbtSections[key]
        if section and section.container:IsShown() then
            local left, right, bottom, top = RegionUtil.GetSides(section.container)
            if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
                hoveredSection = key
                break
            end
        end
    end

    -- Also check delete zone
    local overDelete = false
    if ns.tbtDeleteZone then
        local left, right, bottom, top = RegionUtil.GetSides(ns.tbtDeleteZone)
        if cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top then
            overDelete = true
        end
    end

    SetAllSectionHighlights(false)
    if overDelete then
        SetDeleteZoneHighlight(true)
    elseif hoveredSection then
        SetSectionHighlight(hoveredSection, true)
    end
end
```

### Pattern 6: Icon OnMouseDown — Drag Start

**What:** Icon frames in `CreateIconFrame()` need an `OnMouseDown` handler for LeftButton to call `BeginDrag`. The existing `OnMouseUp` handler for RightButton context menu must remain untouched.

```lua
-- In CreateIconFrame(), alongside existing OnMouseUp:
f:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and self.spellID and self.sectionName ~= "suggested" then
        BeginDrag(self)
    end
end)
-- Existing OnMouseUp stays for right-click context menu
```

**Why OnMouseDown, not OnDragStart:** WoW's `OnDragStart` requires the frame to call `RegisterForDrag("LeftButton")` and uses WoW's native drag cursor system. CDM's item mixin uses `OnMouseUp(LeftButton, upInside)` which triggers `BeginOrderChange`. For TBT, `OnMouseDown` gives immediate feedback (drag starts the instant you click, not on a 0.1s threshold). CDM's `OnMouseUp` approach includes an `eatNextGlobalMouseUp` guard — using `OnMouseDown` avoids the need for that guard entirely.

### Anti-Patterns to Avoid

- **OnEnter/OnLeave for highlight during drag:** The ghost frame at TOOLTIP strata captures mouse events. Section containers will NOT receive `OnEnter` while the ghost is active and visible. Use cursor-position math in `OnDragUpdate` instead.
- **Registering GLOBAL_MOUSE_UP permanently:** Causes spurious drag completion on any mouse release anywhere in the UI. Register only inside `BeginDrag`, unregister in `EndDrag`.
- **Modifying CDM's drag system:** Never call `CooldownViewerSettings:BeginOrderChange` or interact with CDM's `reorderSourceItem`. TBT runs its own parallel drag state.
- **Setting OnUpdate on individual icon frames:** CDM sets OnUpdate on the *settings frame*, not the dragged item. TBT follows the same pattern — `ns.tbtPanel:SetScript("OnUpdate", ...)`.
- **Using `GetCursorPosition()` without scale division for ghost positioning:** Ghost uses `GetScaledCursorPositionForFrame(topLevel)` which handles scale internally. Hit-testing uses `GetCursorPosition() / scale`. These are two different functions for two different purposes.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scale-correct cursor coords for ghost | Manual pixel math | `GetScaledCursorPositionForFrame(topLevel)` | CDM's exact API; handles fullscreen vs. windowed mode |
| Scale-correct cursor for hit-test | Manual pixel math | `GetCursorPosition()` then divide by `GetAppropriateTopLevelParent():GetScale()` | CDM's exact pattern (lines 1339-1341) |
| Frame boundary detection | GetLeft/Right/Top/Bottom manually | `RegionUtil.GetSides(frame)` | Returns all four in one call; CDM uses it |
| Drag audio | Custom sound selection | `SOUNDKIT.UI_CURSOR_PICKUP_OBJECT` / `UI_CURSOR_DROP_OBJECT` | Matches Blizzard UX; users already know what these mean |
| Ghost frame parent | UIParent directly | `GetAppropriateTopLevelParent()` | Returns correct root for fullscreen vs. windowed; UIParent is not always correct |

**Key insight:** CDM's drag system fits TBT's needs almost exactly. Every API choice in the CDM source solves a real edge case — don't substitute equivalents.

---

## Common Pitfalls

### Pitfall 1: OnEnter Doesn't Fire on Frames Beneath TOOLTIP Strata Ghost

**What goes wrong:** Section container frames have `OnEnter` scripts for highlighting. Once the ghost frame at TOOLTIP strata is visible and the cursor is over it, WoW routes `OnEnter`/`OnLeave` to the ghost frame, not to frames underneath. Section highlights never activate during drag.

**Why it happens:** WoW's mouse input routing is strata-based. TOOLTIP > DIALOG > HIGH means the ghost eats all mouse enter/leave events.

**How to avoid:** Drive section highlighting from `OnDragUpdate` using `RegionUtil.GetSides` hit-testing on cursor position — the same math used in `SectionHitTest()` at commit time. Do NOT rely on `OnEnter` for highlighting during an active drag.

**Warning signs:** Section containers never highlight when cursor passes over them, but hit-test at commit time works correctly.

### Pitfall 2: GLOBAL_MOUSE_UP Fires for the Same Click That Started the Drag

**What goes wrong:** If drag is started from `OnMouseUp(LeftButton)` (CDM's approach), the GLOBAL_MOUSE_UP for that same click fires after `BeginDrag` — immediately ending the drag.

**Why it happens:** `OnMouseUp` fires first; the frame registers GLOBAL_MOUSE_UP; GLOBAL_MOUSE_UP fires for the same button release (because button was still being held when OnMouseUp fired? No — this is the "eat" mechanism for click-to-grab patterns).

**How to avoid:** TBT uses `OnMouseDown` instead of `OnMouseUp`. By the time the user releases the mouse, GLOBAL_MOUSE_UP fires as the drag-end. No eat mechanism needed.

**Warning signs:** Drag appears to start and immediately commit on the source icon.

### Pitfall 3: Ghost Frame Invisible or Behind Settings Panel

**What goes wrong:** Ghost frame created with wrong parent or strata is clipped by or rendered behind the CDM settings panel.

**Why it happens:** Parenting to CDM settings frame or using HIGH/DIALOG strata.

**How to avoid:** Parent to `GetAppropriateTopLevelParent()`, set `frameStrata = "TOOLTIP"`. This is exactly `CooldownViewerSettings.xml` line 4.

**Warning signs:** Ghost is invisible when dragging; visible only outside the settings panel.

### Pitfall 4: ns.tbtPanel OnEvent Conflicts With Panel-Level Event Handling

**What goes wrong:** Setting `ns.tbtPanel:SetScript("OnEvent", ...)` inside `BeginDrag` overwrites any existing OnEvent handler on the panel. If another feature later registers events on `tbtPanel`, the drag's `SetScript` will silently remove it.

**Why it happens:** `SetScript` replaces; it does not append.

**How to avoid:** Set the OnEvent script **once** during `ns:InitCDMTab()`, not inside `BeginDrag`. The handler checks `tbtDragState.active` and ignores events when not dragging. Only GLOBAL_MOUSE_UP is registered/unregistered dynamically; the handler script itself is permanent.

```lua
-- In InitCDMTab(), once:
ns.tbtPanel:SetScript("OnEvent", function(self, event, ...)
    if event == "GLOBAL_MOUSE_UP" and tbtDragState.active then
        local button = ...
        if button == "LeftButton" then
            EndDrag(true)
        elseif button == "RightButton" then
            EndDrag(false)
        end
    end
end)
```

**Warning signs:** Other panel events stop working after first drag.

### Pitfall 5: RefreshTBTSections During Active Drag Invalidates Source Frame Reference

**What goes wrong:** `EndDrag(commit=true)` calls `ns:SetBuffSection()` then `ns:RefreshTBTSections()`. `RefreshTBTSections` calls `section.itemPool:ReleaseAll()` which hides and resets `tbtDragState.sourceFrame`. If `EndDrag` tries to restore alpha on `tbtDragState.sourceFrame` *after* calling `RefreshTBTSections`, it is touching a released frame.

**Why it happens:** Frame pool releases do not nil out references in external tables.

**How to avoid:** In `EndDrag`, restore source frame alpha (and clear `tbtDragState.sourceFrame`) *before* calling `ns:SetBuffSection()` and `ns:RefreshTBTSections()`. The `wipe(tbtDragState)` call must also happen before refresh.

**Warning signs:** Frame alpha is stuck at 0.4 on the pooled frame after drag; next buff in that slot appears dimmed.

### Pitfall 6: OnDragUpdate Running After EndDrag (Script Not Nil'd)

**What goes wrong:** `EndDrag` calls `ns.tbtPanel:SetScript("OnUpdate", nil)` but if EndDrag is called re-entrantly (e.g., from inside a GLOBAL_MOUSE_UP during a RefreshTBTSections `C_Timer.After`) the OnUpdate continues running.

**Why it happens:** Re-entrant frame events in WoW can fire during Layout() or Show() calls inside refresh.

**How to avoid:** Nil the OnUpdate script as the very first line of EndDrag, before any other logic. Guard `EndDrag` with `if not tbtDragState.active then return end` at the top to prevent double-execution.

---

## Code Examples

Verified patterns from Blizzard source:

### Ghost Frame OnUpdate (from Blizzard source)

```lua
-- Source: CooldownViewerSettings.lua:36-40
function CooldownViewerSettingsDraggedItemMixin:OnUpdate()
    local topLevel = GetAppropriateTopLevelParent()
    local x, y = GetScaledCursorPositionForFrame(topLevel)
    self:SetPoint("TOPLEFT", topLevel, "BOTTOMLEFT", x, y)
end
```

### BeginOrderChange Core (from Blizzard source)

```lua
-- Source: CooldownViewerSettings.lua:1240-1256
function CooldownViewerSettingsMixin:BeginOrderChange(cooldownItem, eatNextGlobalMouseUp)
    if self:IsReordering() then return end

    self:SetReorderSourceItem(cooldownItem)
    self:SetReorderTarget(cooldownItem)
    self.reorderOffset = 0
    self.eatNextGlobalMouseUp = eatNextGlobalMouseUp

    cooldownItem:SetReorderLocked(true)
    PickupCooldownItemCursor(cooldownItem)       -- shows ghost

    self:SetScript("OnUpdate", self.OnUpdate)   -- cursor tracking active
    self:RegisterEvent("GLOBAL_MOUSE_UP")       -- session termination
end
```

### CancelOrderChange Core (from Blizzard source)

```lua
-- Source: CooldownViewerSettings.lua:1275-1285
function CooldownViewerSettingsMixin:CancelOrderChange(cooldownItem, ...)
    self:GetReorderSourceItem():SetReorderLocked(false)
    self.ReorderMarker:Hide()
    self:ClearReorderTargets()

    ClearCooldownItemCursor()                   -- hides ghost

    self:SetScript("OnUpdate", nil)             -- stop cursor tracking
    self:UnregisterEvent("GLOBAL_MOUSE_UP")     -- end session
end
```

### Cursor Scale Compensation for Hit-Testing (from Blizzard source)

```lua
-- Source: CooldownViewerSettings.lua:1339-1341
local cursorX, cursorY = GetCursorPosition()
local scale = GetAppropriateTopLevelParent():GetScale()
cursorX, cursorY = cursorX / scale, cursorY / scale
```

### Weighted Nearest-Item Hit-Test (from Blizzard source — for reference, TBT uses simpler point-in-rect)

```lua
-- Source: CooldownViewerSettings.lua:722-744
function CooldownViewerSettingsCategoryMixin:GetNearestItemToCursorWeighted(cursorX, cursorY)
    local nearestItem = nil
    local nearestVertical = math.huge
    local nearestHorizontal = math.huge

    for item in self.itemPool:EnumerateActive() do
        local itemLeft, itemRight, itemBottom, itemTop = RegionUtil.GetSides(item)
        local itemCenterX = (itemLeft + itemRight) / 2
        local itemCenterY = (itemBottom + itemTop) / 2
        local horizontalDistance = math.abs(itemCenterX - cursorX)
        local verticalDistance = math.abs(itemCenterY - cursorY)
        if cursorY > itemBottom and cursorY < itemTop then
            verticalDistance = 0
        end

        if verticalDistance < nearestVertical
           or (nearestVertical == verticalDistance and horizontalDistance < nearestHorizontal) then
            nearestItem = item
            nearestVertical = verticalDistance
            nearestHorizontal = horizontalDistance
        end
    end

    return nearestItem
end
```

TBT uses point-in-rect on `section.frame` (not nearest-weighted), which is appropriate since sections don't overlap and the user only needs to place the cursor inside the target section.

### GLOBAL_MOUSE_UP Handler (from Blizzard source)

```lua
-- Source: CooldownViewerSettings.lua:1358-1377
function CooldownViewerSettingsMixin:OnEvent(event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        local button = ...
        self:OnGlobalMouseUp(button)
    end
end

function CooldownViewerSettingsMixin:OnGlobalMouseUp(button)
    if self.eatNextGlobalMouseUp == button then
        self.eatNextGlobalMouseUp = nil
    else
        PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
        if button == "LeftButton" then
            self:EndOrderChange()
        elseif button == "RightButton" then
            self:CancelOrderChange()
        end
    end
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UIDropDownMenu` for context menus | `MenuUtil.CreateContextMenu` | Dragonflight/Midnight | Already used in CDMTab.lua; not relevant to drag |
| Native WoW drag (`PickupSpell`, `CursorHasItem`) | Manual ghost-frame drag | Always been separate | Native drag is for item/spell data; custom data objects must use manual pattern |
| `OnEnter`/`OnLeave` for drop target detection | Per-frame cursor hit-test during drag | — | OnEnter blocked by TOOLTIP-strata ghost; hit-test is the only reliable method |

---

## Environment Availability

Step 2.6: SKIPPED (no external tool dependencies — phase is pure Lua code changes within CDMTab.lua)

---

## Validation Architecture

> nyquist_validation key is absent from config.json — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None — WoW addon; no automated test framework available |
| Config file | none |
| Quick run command | Deploy with `./scripts/install.bat` then test in-game with `/tbt` |
| Full suite command | Manual in-game verification checklist (see below) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DND-01 | Drag a buff from Bars → Buffs, confirm section change persists | manual | n/a | n/a |
| DND-01 | Drag to delete zone, confirm buff removed from DB | manual | n/a | n/a |
| DND-01 | Drop on Suggested, confirm no section change (cancel) | manual | n/a | n/a |
| DND-01 | Drop outside all sections, confirm no section change | manual | n/a | n/a |
| DND-02 | Ghost icon visible at TOOLTIP strata, follows cursor across full screen | manual | n/a | n/a |
| DND-02 | Ghost icon at 50% alpha, shows correct spell icon | manual | n/a | n/a |
| DND-03 | Valid section highlights when cursor enters during drag | manual | n/a | n/a |
| DND-03 | Delete zone highlights distinctly (red) when cursor enters | manual | n/a | n/a |
| DND-03 | All highlights clear when drag ends (commit or cancel) | manual | n/a | n/a |

### Sampling Rate

- **Per task commit:** Deploy with `./scripts/install.bat`, log in, open `/tbt`, perform one drag
- **Per wave merge:** Full manual checklist (all DND-01/02/03 scenarios above)
- **Phase gate:** Full manual checklist green before `/gsd:verify-work`

### Wave 0 Gaps

None — no automated test infrastructure applicable to WoW addon Lua. All validation is manual in-game.

---

## Open Questions

1. **Should drop target use `section.frame` or `section.container` bounds?**
   - What we know: `section.frame` is the full section area (header + grid); `section.container` is only the grid area
   - What's unclear: whether users dropping near the header area expect the section to accept the drop
   - Recommendation: Use `section.frame` (wider hit area) for better UX; the section header is visually labeled so users naturally drag toward the full section, not just the icon grid

2. **Does the delete zone need to be hidden when no drag is active?**
   - What we know: `ns.tbtDeleteZone` is always visible in Phase 4 (present as a permanent first slot in Not Displayed)
   - What's unclear: Phase 4 created it as "visual only" — the Context.md says it's already created but interaction wiring is Phase 5's job
   - Recommendation: Keep delete zone always visible (already established in Phase 4). Dragging on it is the new behavior; no visibility toggle needed.

3. **What if `ns.tbtPanel` is hidden when GLOBAL_MOUSE_UP fires (e.g., CDM closed via Escape)?**
   - What we know: If CDM closes during a drag, `ns.tbtPanel` is hidden. GLOBAL_MOUSE_UP will still fire on the frame since events are not strata-gated.
   - Recommendation: Add `HookScript("OnHide", function() if tbtDragState.active then EndDrag(false) end end)` on `ns.tbtPanel` to cancel drag if the panel hides mid-drag.

---

## Project Constraints (from CLAUDE.md)

Directives the planner must verify compliance with:

- `stylua` must be run on all Lua files after finishing the task
- `COMBAT_LOG_EVENT_UNFILTERED` must not be used (not relevant to drag, but noted)
- Spell IDs from `UNIT_SPELLCAST_SUCCEEDED` are safe; `ns:GetSpellIcon(spellID)` is the approved icon lookup
- Requires Blizzard's CDM — no standalone fallback (drag only available when CDM panel is open, which is the natural constraint)
- No new files unless necessary — drag implementation lives in `CDMTab.lua`
- Reusable module-level tables wiped with `wipe()` — `tbtDragState` must use `wipe(tbtDragState)` in `EndDrag`, not reassignment
- After every commit: performance and code cleanup review — check OnUpdate for hot-path allocations (the drag OnUpdate must not allocate: no table creation, no string concatenation)
- Deploy to WoW with `./scripts/install.bat` after changes

---

## Sources

### Primary (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — All drag lifecycle functions: `BeginOrderChange` (line 1240), `EndOrderChange` (1258), `CancelOrderChange` (1275), `OnUpdate` (1326), `UpdateReorderMarker` (1331), `OnGlobalMouseUp` (1365), `GetNearestItemToCursorWeighted` (722), `CooldownViewerSettingsDraggedItemMixin:OnUpdate` (36), `PickupCooldownItemCursor` (43)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — `CooldownViewerSettingsDraggedItemTemplate` frame definition (line 4): `frameStrata="TOOLTIP"`, size 38x38
- `C:\Users\jonat\Repositories\TerribleBuffTracker\CDMTab.lua` — Existing section framework: `ns.tbtSections`, `ns.tbtDeleteZone`, `CreateIconFrame` with `OnMouseUp` right-click handler, `ns:RefreshTBTSections`, `ns.tbtPanel`
- `.planning/research/STACK.md` — CDM drag pattern summary (verified against source above)
- `.planning/research/PITFALLS.md` — Pitfalls 6 and 7 (drag strata, GLOBAL_MOUSE_UP scope)
- `.planning/phases/05-drag-and-drop/05-CONTEXT.md` — All locked decisions D-01 through D-12

### Secondary (MEDIUM confidence)
- None required — all needed patterns found in Blizzard source directly

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified from Blizzard source line citations
- Architecture: HIGH — patterns extracted directly from CDM implementation, adapted to TBT's simpler use case
- Pitfalls: HIGH — Pitfalls 1-3 verified from source; Pitfalls 4-6 are TBT-specific logic deductions from known frame API behavior

**Research date:** 2026-03-29
**Valid until:** 2026-04-29 (stable WoW internal APIs; unlikely to change in a patch cycle)
