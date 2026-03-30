# Phase 2: Edit Mode Containers - Research

**Researched:** 2026-03-28
**Domain:** WoW Lua addon — Edit Mode EventRegistry, movable frames, position persistence, CDM decoupling
**Confidence:** HIGH (sourced directly from Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Create `TBTBarContainer` and `TBTBuffContainer` as globally named frames parented to UIParent. Fully independent of CDM frame hierarchy.
- **D-02:** Containers become draggable during Edit Mode via `SetMovable(true)` / `EnableMouse(true)` — no separate overlay drag handle frames.
- **D-03:** Remove all existing CDM layout hooks entirely — `SnapshotSettings()`, `HookViewerLayout()`, and the `EditMode.Exit` snapshot callback. TBT containers use saved positions from DB exclusively.
- **D-04:** `SnapshotSettings()` function and related CDM-reading code can be deleted. Display.lua restructured around independent containers.
- **D-05:** Register a single checkbox labeled "TerribleBuffTracker" in the Edit Mode sidebar dialog. One toggle controls visibility of both containers together.
- **D-06:** Do NOT copy from CDM at all on fresh install. Use hardcoded default positions (center-right of screen).
- **D-07:** "Fresh install" detected by checking if `ns.db.editModePositions` is nil.

### Claude's Discretion

- Exact default position coordinates for fresh installs
- Whether to show a visual border/highlight on containers during Edit Mode
- How to handle containers when no tracked buffs exist (empty state)
- DB schema for `editModePositions` structure (point, xOfs, yOfs, scale per container)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EDM-01 | User sees two independent movable elements (bars container, buffs container) in Edit Mode | EventRegistry EditMode.Enter/Exit pattern; SetMovable + drag handle overlay |
| EDM-02 | User can toggle bar/buff container visibility via Edit Mode sidebar checkboxes | Custom checkbox injection into BasicOptionsContainer GridLayoutFrame |
| EDM-03 | Fresh install copies CDM position/scale settings once as initial values | OVERRIDDEN by D-06: hardcoded defaults instead; `editModePositions == nil` guard |
| EDM-04 | After initial copy, TBT position/scale is set exclusively via Edit Mode | DB-exclusive anchor apply; all CDM anchor calls guarded/removed |
| EDM-05 | Display does not re-anchor to CDM when CDM layout refreshes | Remove HookViewerLayout entirely (D-03); no CDM hooks remain |

Note on EDM-03: CONTEXT.md D-06 supersedes this requirement — no CDM copy happens; hardcoded defaults are used instead. The requirement is satisfied by the existence of default positions, not by copying CDM.

</phase_requirements>

---

## Summary

Phase 2 creates two UIParent-parented named frames (`TBTBarContainer`, `TBTBuffContainer`), wires them to WoW's Edit Mode via `EventRegistry` callbacks, and restructures `Display.lua` to anchor from `TerribleBuffTrackerDB.editModePositions` instead of CDM viewer frames. The existing CDM layout hooks (`HookViewerLayout`, `SnapshotSettings`, `EditMode.Exit` snapshot) are deleted entirely.

The single most important research finding is the sidebar checkbox situation. The CONTEXT.md D-05 decision to "register in the Edit Mode sidebar dialog" is not achievable through Blizzard's native checkbox system — all sidebar checkboxes are XML-defined frames within `EditModeManagerFrame.AccountSettings.SettingsContainer`. However, it IS achievable by injecting a custom frame inheriting `EditModeManagerSettingCheckButtonTemplate` into the `BasicOptionsContainer` GridLayoutFrame at runtime. This is the viable path for EDM-02.

The second key finding is that `EditModeSystemMixin` is off-limits for third-party addons (requires a valid `Enum.EditModeSystem` value). TBT must implement its own lightweight Edit Mode toggle using `EventRegistry:RegisterCallback("EditMode.Enter", ...)` and `"EditMode.Exit"` — this pattern already exists in `Display.lua` line 391 and is safe to extend.

**Primary recommendation:** Create `EditModeFrames.lua` as a new file. Wire EventRegistry for Enter/Exit. Inject a sidebar checkbox into `BasicOptionsContainer`. Restructure `Display.lua` to apply positions from `ns.db.editModePositions`.

---

## Standard Stack

No new libraries needed. This phase uses exclusively Blizzard APIs.

### Core APIs

| API | Purpose | Notes |
|-----|---------|-------|
| `EventRegistry:RegisterCallback("EditMode.Enter", fn, owner)` | Detect Edit Mode activation | Already used in Display.lua line 391 |
| `EventRegistry:RegisterCallback("EditMode.Exit", fn, owner)` | Detect Edit Mode deactivation + save positions | Already used in Display.lua line 391 |
| `frame:SetMovable(true/false)` | Enable/disable drag movement | Set true on Enter, false on Exit |
| `frame:EnableMouse(true/false)` | Allow mouse interaction for dragging | Set true on Enter, false (or only for tooltips) on Exit |
| `frame:StartMoving()` | Begin drag on `OnMouseDown "LeftButton"` | Called from drag handle's `OnMouseDown` script |
| `frame:StopMovingOrSizing()` | End drag on `OnMouseUp` | Called from `OnMouseUp`; position is NOT saved here |
| `frame:GetPoint(1)` | Read first anchor point for position serialization | Returns point, relativeTo, relativePoint, x, y |
| `frame:SetPoint(point, relativeTo, relativePoint, x, y)` | Apply saved position from DB | Called in `ApplyEditModePositions()` |
| `CreateFrame("Frame", "TBTBarContainer", UIParent)` | Named frame creation | Global name is required (Pitfall 5) |

### Sidebar Checkbox Injection

| API | Purpose | Notes |
|-----|---------|-------|
| `CreateFrame("Frame", nil, BasicOptionsContainer, "EditModeManagerSettingCheckButtonTemplate")` | Create TBT visibility checkbox | Must be parented to `BasicOptionsContainer` |
| `checkButton.Label:SetText("TerribleBuffTracker")` | Set checkbox label | `Label` is a `parentKey` on the template |
| `checkButton:SetCallback(fn)` | Wire click handler | Inherited from `EditModeCheckButtonMixin` |
| `BasicOptionsContainer:Layout()` | Force GridLayoutFrame to reflow after injection | Required — runtime children are not auto-laid out |
| `checkButton:SetControlChecked(bool)` | Set checkbox state programmatically | Inherited from `ResizeCheckButtonBehaviorTemplate` |

**Installation:** No `npm install`. All Blizzard global APIs.

---

## Architecture Patterns

### Recommended File Structure

```
TerribleBuffTracker/
├── Core.lua               -- Add editModePositions + tbtVisible DB init
├── BuffEngine.lua         -- Unchanged in this phase
├── Display.lua            -- Remove CDM hooks; apply positions from DB; remove SnapshotSettings
├── EditModeFrames.lua     -- NEW: containers, drag handles, EventRegistry hooks, sidebar checkbox
├── ConfigUI.lua           -- Unchanged in this phase
└── TerribleBuffTracker.toc -- Add EditModeFrames.lua entry
```

### Pattern 1: Named Container Frame Creation

**What:** Containers must have global names so position serialization works correctly. Unnamed frames (`nil` name) cause `GetPoint()` anchor serialization to resolve `relativeTo` as `"UIParent"`, which silently discards positional identity across reloads.

**When to use:** Any frame that participates in Edit Mode position persistence.

**Source:** `wow-ui-source/Blizzard_EditMode/Shared/EditModeManager.lua` — `ConvertToAnchorInfo` uses `relativeTo:GetName()`.

```lua
-- In EditModeFrames.lua, called from ns:InitEditModeFrames()
local barContainer = CreateFrame("Frame", "TBTBarContainer", UIParent)
barContainer:SetSize(220, 1)   -- width matches BAR_WIDTH; height dynamically set in UpdateDisplay
barContainer:SetFrameStrata("MEDIUM")

local iconContainer = CreateFrame("Frame", "TBTBuffContainer", UIParent)
iconContainer:SetSize(40, 40)  -- BUFF_ICON_SIZE; resizes in UpdateDisplay
iconContainer:SetFrameStrata("MEDIUM")

-- Expose to namespace so Display.lua can use them
ns.barContainer = barContainer
ns.iconContainer = iconContainer
```

### Pattern 2: Default Position Apply (Fresh Install)

**What:** When `ns.db.editModePositions` is nil on first load, apply hardcoded defaults and write them to DB immediately. Subsequent loads find a non-nil `editModePositions` and use those saved values.

**Source:** CONTEXT.md D-06, D-07; UI-SPEC.md Default Positions table.

```lua
-- In EditModeFrames.lua: ns:ApplyEditModePositions()
local function ApplyEditModePositions()
    if not ns.db.editModePositions then
        -- Fresh install: write hardcoded defaults immediately
        ns.db.editModePositions = {
            bars = {
                point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
                x = 300, y = 0,
            },
            icons = {
                point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
                x = 300, y = -80,
            },
        }
    end

    local barsPos = ns.db.editModePositions.bars
    local iconsPos = ns.db.editModePositions.icons

    local barContainer = _G["TBTBarContainer"]
    barContainer:ClearAllPoints()
    barContainer:SetPoint(barsPos.point, barsPos.relativeTo, barsPos.relativePoint, barsPos.x, barsPos.y)

    local iconContainer = _G["TBTBuffContainer"]
    iconContainer:ClearAllPoints()
    iconContainer:SetPoint(iconsPos.point, iconsPos.relativeTo, iconsPos.relativePoint, iconsPos.x, iconsPos.y)
end
```

### Pattern 3: Edit Mode Enter/Exit via EventRegistry

**What:** EventRegistry fires `"EditMode.Enter"` when `EditModeManagerFrame:EnterEditMode()` is called (confirmed: line 89 of `EditModeManager.lua`). Fires `"EditMode.Exit"` when `ExitEditMode()` is called (line 108). TBT hooks both to show/hide drag handles and save positions.

**Source:** `wow-ui-source/Blizzard_EditMode/Shared/EditModeManager.lua` lines 89, 108 — `EventRegistry:TriggerEvent("EditMode.Enter")` and `EventRegistry:TriggerEvent("EditMode.Exit")`.

```lua
-- In EditModeFrames.lua: ns:InitEditModeFrames()
EventRegistry:RegisterCallback("EditMode.Enter", function()
    ns:OnEditModeEnter()
end, ns)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    ns:OnEditModeExit()
end, ns)

function ns:OnEditModeEnter()
    local barContainer = _G["TBTBarContainer"]
    local iconContainer = _G["TBTBuffContainer"]

    barContainer:SetMovable(true)
    barContainer:EnableMouse(true)
    barContainer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    barContainer:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        -- Note: position is NOT written to DB here (UI-SPEC.md: save on EditMode.Exit)
    end)

    iconContainer:SetMovable(true)
    iconContainer:EnableMouse(true)
    iconContainer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    iconContainer:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
    end)

    -- Show drag handle overlays
    ns:ShowEditModeHandles()
end

function ns:OnEditModeExit()
    local barContainer = _G["TBTBarContainer"]
    local iconContainer = _G["TBTBuffContainer"]

    barContainer:SetMovable(false)
    barContainer:EnableMouse(false)
    barContainer:SetScript("OnMouseDown", nil)
    barContainer:SetScript("OnMouseUp", nil)

    iconContainer:SetMovable(false)
    iconContainer:EnableMouse(false)
    iconContainer:SetScript("OnMouseDown", nil)
    iconContainer:SetScript("OnMouseUp", nil)

    -- Save positions FIRST (UI-SPEC.md: save on EditMode.Exit, not on OnMouseUp)
    ns:SaveEditModePositions()
    ns:HideEditModeHandles()
    ns:UpdateDisplay()
end
```

### Pattern 4: Position Save on EditMode.Exit

**What:** Read `GetPoint(1)` from each container after Edit Mode exits. The first anchor point is always the TBT-set position since we `ClearAllPoints()` before `SetPoint()`.

**Source:** UI-SPEC.md "Position Save Trigger" section; `GetPoint()` returns `point, relativeTo, relativePoint, x, y`.

```lua
function ns:SaveEditModePositions()
    local barContainer = _G["TBTBarContainer"]
    local iconContainer = _G["TBTBuffContainer"]

    local point, relativeTo, relativePoint, x, y = barContainer:GetPoint(1)
    ns.db.editModePositions.bars = {
        point = point or "CENTER",
        relativeTo = (relativeTo and relativeTo:GetName()) or "UIParent",
        relativePoint = relativePoint or "CENTER",
        x = x or 300,
        y = y or 0,
    }

    point, relativeTo, relativePoint, x, y = iconContainer:GetPoint(1)
    ns.db.editModePositions.icons = {
        point = point or "CENTER",
        relativeTo = (relativeTo and relativeTo:GetName()) or "UIParent",
        relativePoint = relativePoint or "CENTER",
        x = x or 300,
        y = y or -80,
    }
end
```

### Pattern 5: Drag Handle Overlay

**What:** A semi-transparent overlay frame shown at the top of each container during Edit Mode. Per UI-SPEC.md: 24px height (lg spacing token), `0,0,0,0.5` background, `0.2,0.6,1.0,0.8` border, "TerribleBuffTracker" label in `GameFontNormal`.

**Source:** UI-SPEC.md "Edit Mode Interaction Contract" and color/spacing tables.

```lua
local function CreateDragHandle(container, labelText)
    local handle = CreateFrame("Frame", nil, container)
    handle:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    handle:SetHeight(24)  -- lg spacing token
    handle:SetFrameLevel(container:GetFrameLevel() + 5)

    -- Background
    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints()
    handle.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Border (1px solid CDM blue)
    handle.border = CreateFrame("Frame", nil, handle, "BackdropTemplate")
    handle.border:SetAllPoints()
    handle.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })
    handle.border:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.8)

    -- Label
    handle.label = handle:CreateFontString(nil, "OVERLAY")
    handle.label:SetFontObject(GameFontNormal)
    handle.label:SetText(labelText)
    handle.label:SetTextColor(1, 1, 1, 1)
    handle.label:SetPoint("CENTER")

    handle:Hide()
    return handle
end
```

### Pattern 6: Sidebar Checkbox Injection (EDM-02)

**Critical finding:** The `EditModeManagerFrame.AccountSettings.SettingsContainer` checkboxes are ALL defined in XML (`EditModeManager.xml`). Third-party addons cannot add to `checkBoxSetupData` — it is a local table. However, the container frames (`BasicOptionsContainer`, `MiscContainer`, `FramesContainer`) are `GridLayoutFrame` instances that dynamically reflow children. TBT can create a frame inheriting `EditModeManagerSettingCheckButtonTemplate`, parent it to `BasicOptionsContainer`, and call `BasicOptionsContainer:Layout()` to force reflow.

**Timing:** Must be done after `EditModeManagerFrame` has been initialized and its `AccountSettings.SettingsContainer` is fully loaded. The safest gate is `EventRegistry:RegisterCallback("EditMode.Enter", ...)` — by the time Edit Mode can be entered, the manager is fully initialized.

**Source:** `wow-ui-source/Blizzard_EditMode/Shared/EditModeManager.xml` — `BasicOptionsContainer` inherits `EditModeManagerSettingsOptionsContainerTemplate` which inherits `GridLayoutFrame` with `alwaysUpdateLayout=true`. `EditModeManager.lua` `LayoutSettings()` re-parents existing checkboxes dynamically — same mechanism TBT can use.

```lua
-- In EditModeFrames.lua ns:InitEditModeFrames(), called once on first EditMode.Enter
local function InjectSidebarCheckbox()
    -- Guard: EditModeManagerFrame must exist and be initialized
    if not EditModeManagerFrame or not EditModeManagerFrame.AccountSettings then
        return
    end
    local container = EditModeManagerFrame.AccountSettings.SettingsContainer.ScrollChild.BasicOptionsContainer
    if not container then
        return
    end

    local checkButton = CreateFrame("Frame", nil, container, "EditModeManagerSettingCheckButtonTemplate")
    checkButton.Label:SetText("TerribleBuffTracker")

    -- Set layoutIndex so GridLayoutFrame positions it (needs to be after existing items)
    -- GridLayoutFrame orders by layoutIndex if present; otherwise by child order
    checkButton.isBasicOption = true

    local function onCheck(isChecked, isUserInput)
        if isUserInput then
            ns.db.tbtVisible = isChecked
            if isChecked then
                _G["TBTBarContainer"]:Show()
                _G["TBTBuffContainer"]:Show()
            else
                _G["TBTBarContainer"]:Hide()
                _G["TBTBuffContainer"]:Hide()
            end
        else
            checkButton:SetControlChecked(isChecked)
        end
    end
    checkButton:SetCallback(onCheck)

    -- Sync initial state
    checkButton:SetControlChecked(ns.db.tbtVisible ~= false)

    -- Force GridLayoutFrame reflow
    container:Layout()

    ns.tbtSidebarCheckbox = checkButton
end
```

**Warning:** The `EditModeManagerSettingCheckButtonTemplate` `OnLoad` script runs immediately on `CreateFrame`. It calls `EditModeManagerSettingCheckButton_OnLoad` which sets `self.Label:SetWidth(...)` — this requires `self.Button` and `self.Label` to exist (they do, they're on the template). This is safe.

### Pattern 7: Display.lua Restructuring

**What changes in Display.lua:**

1. `barContainer` and `iconContainer` local variables → replaced by references to `_G["TBTBarContainer"]` and `_G["TBTBuffContainer"]` (set via `ns.barContainer` / `ns.iconContainer` from `EditModeFrames.lua`)
2. Container creation block (lines 358–371) → deleted; containers are created in `EditModeFrames.lua`
3. `SnapshotSettings()` function → deleted (D-04)
4. `ReadBarSettings()` and `ReadIconSettings()` → deleted (D-04)
5. `HookViewerLayout()` helper → deleted (D-03)
6. CDM viewer layout hooks (lines 377–394) → deleted (D-03, D-05)
7. `EventRegistry:RegisterCallback("EditMode.Exit", ...)` at line 391 → deleted (replaced by EditModeFrames.lua)
8. `cachedBarSettings` / `cachedIconSettings` → these still exist BUT now read from a different source

**Critical: cachedBarSettings after D-04.** The `UpdateDisplay()` function references `cachedBarSettings` extensively (bar width, icon scale, alpha, visibleSetting, barContent, etc.). With `SnapshotSettings()` deleted, these values must come from somewhere. Two options:

- **Option A (clean):** Remove all CDM settings reading. Replace `cachedBarSettings` with a simple hardcoded-or-DB-stored display config struct. The bar width, scale, etc. become fixed values or TBT-owned DB settings.
- **Option B (minimal change):** Keep `SnapshotSettings()` but call it once on `PLAYER_ENTERING_WORLD` (not on CDM layout hooks). Remove only the `HookViewerLayout` hooks and the `EditMode.Exit` snapshot re-trigger.

CONTEXT.md D-03 says "remove all existing CDM layout hooks entirely" and D-04 says "`SnapshotSettings()` function and related CDM-reading code can be deleted." This implies Option A. However, `UpdateDisplay()` uses many settings from CDM (alpha, barContent, timerShown, etc.) that currently have no alternative source. The planner must decide: are those settings becoming hardcoded, or is a new `ns.db.displaySettings` needed?

**Research verdict:** This is a MEDIUM-confidence gap. The decisions explicitly delete the CDM settings reading code, but UpdateDisplay() depends on it. The planner should either (a) replace `cachedBarSettings` with hardcoded defaults matching CDM defaults, or (b) add a new `ns.db.displaySettings` sub-object. Given Phase 3/4 will add a CDM tab for TBT settings, option (a) with hardcoded defaults for now is likely correct — settings will be wired properly in Phase 3.

### Anti-Patterns to Avoid

- **Using `EditModeSystemMixin` directly:** Requires `self.system` to be a valid `Enum.EditModeSystem` value — only Blizzard can define these. The mixin's `OnSystemLoad()` silently returns if `self.system` is nil. Do not use this mixin.
- **Parenting containers to CDM viewer frames:** Reintroduces CDM coupling. Containers must be parented to `UIParent` only.
- **Saving position on `OnMouseUp`:** UI-SPEC.md explicitly requires saving on `EditMode.Exit`, not `OnMouseUp`. The user may drag multiple times before exiting.
- **Calling `SetControlChecked` with `isUserInput=true` semantics on init:** On init, call the callback with `isUserInput=false` (or call `SetControlChecked` directly) to avoid triggering Show/Hide during initial sync.
- **Leaving `EnableMouse(true)` after Edit Mode exits:** The containers have tooltips on child bars/icons that use `EnableMouse`. The container itself should not capture mouse outside Edit Mode.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Drag handle border | Custom texture border frame | `BackdropTemplate` with `edgeFile` | Blizzard standard; handles edge sizing automatically |
| GridLayoutFrame reflowing | Manual child repositioning | Call `container:Layout()` after child injection | GridLayoutFrame is designed for dynamic children |
| EventRegistry callbacks | Custom event frame with `RegisterEvent` | `EventRegistry:RegisterCallback("EditMode.Enter/Exit", ...)` | Already correct pattern used in Display.lua; EventRegistry is the official channel for Edit Mode notifications |

---

## Common Pitfalls

### Pitfall 1: Sidebar Checkbox — XML-Only Native System

**What goes wrong:** Developer assumes `checkBoxSetupData` (a local table in `EditModeManager.lua`) can be modified, or that `EditModeManagerFrame.AccountSettings:PrepareSettingsCheckButtons()` can be hooked to add new checkboxes. Neither is possible — the table is a Lua `local`, and the checkbox frames are XML-defined named children of `SettingsContainer`.

**Why it happens:** The Lua code `self.settingsCheckButtons[keyName] = self.SettingsContainer[keyName]` implies the checkbox key names map to frame names, suggesting runtime extensibility. In reality, `self.SettingsContainer[keyName]` only works for XML-defined `parentKey` children.

**How to avoid:** Inject a runtime-created frame inheriting `EditModeManagerSettingCheckButtonTemplate` directly into `BasicOptionsContainer` (a `GridLayoutFrame`). Call `BasicOptionsContainer:Layout()` after injection. This is unsupported/unofficial but observably correct given how `GridLayoutFrame` works.

**Warning signs:** Lua error "attempt to index nil value" if you try `EditModeManagerFrame.AccountSettings.SettingsContainer["TerribleBuffTracker"]`.

**Confidence:** HIGH (verified by reading `EditModeManager.xml` and `EditModeManager.lua` directly).

---

### Pitfall 2: `SnapshotSettings()` Deletion Breaks `UpdateDisplay()`

**What goes wrong:** Deleting `SnapshotSettings()`, `ReadBarSettings()`, `ReadIconSettings()`, and the CDM layout hooks leaves `cachedBarSettings` and `cachedIconSettings` as nil. `UpdateDisplay()` checks `if not settings then barContainer:Hide()` — both containers immediately hide permanently.

**Why it happens:** The deletion decisions (D-03, D-04) were made in isolation. `UpdateDisplay()` has 60+ lines that read `settings.iconScale`, `settings.barWidth`, `settings.alpha`, `settings.barContent`, etc.

**How to avoid:** Before deleting `SnapshotSettings()`, replace `cachedBarSettings` and `cachedIconSettings` with a hardcoded-defaults table that mirrors CDM defaults. The planner must include a task to create this replacement config source. Suggested defaults:

```lua
-- Replacement for cachedBarSettings (hardcoded CDM defaults)
cachedBarSettings = {
    iconScale = 1,
    iconPadding = 5,
    barWidth = 220,
    alpha = 1,
    visibleSetting = 0,       -- Always show
    barContent = 0,           -- Both icon + text
    hideWhenInactive = true,
    timerShown = true,
    tooltipsShown = true,
}
-- Same shape for cachedIconSettings
cachedIconSettings = {
    orientationSetting = 0,   -- Horizontal
    iconDirection = 0,        -- Right/Down
    iconScale = 1,
    iconPadding = 5,
    alpha = 1,
    visibleSetting = 0,
    hideWhenInactive = true,
    timerShown = true,
    tooltipsShown = true,
}
```

**Warning signs:** Both containers hidden immediately after `InitDisplay()`. No Lua error (the nil-check silently hides the container).

---

### Pitfall 3: `isEditing` Check Fails After CDM Decoupling

**What goes wrong:** `UpdateDisplay()` lines 448 and 569 read `ns.cdmBarViewer.isEditing` and `ns.cdmIconViewer.isEditing` to determine whether to show placeholder bars during CDM's own edit mode. After containers decouple from CDM, the `ns.cdmBarViewer` references may be nil (if CDM viewer detection is also cleaned up), or the `isEditing` check is irrelevant to TBT's own Edit Mode state.

**How to avoid:** Replace `barEditing` / `iconEditing` references with `ns.editModeActive` (a boolean set true on `EditMode.Enter`, false on `EditMode.Exit`). This correctly shows placeholders when TBT's own Edit Mode is active.

**Warning signs:** Placeholder bars never shown during TBT Edit Mode (containers appear empty/non-draggable-looking).

---

### Pitfall 4: CDM Viewer Still Needed for Bar Width / Icon Size

**What goes wrong:** After removing `SnapshotSettings()` and CDM hooks, the addon loses its source for `settings.barWidth`. The bar width in CDM is not a fixed value — it reflects the CDM viewer's current width which scales with the CDM bar width setting.

**Why it matters:** With CDM decoupling, TBT no longer reads CDM's bar width setting. `BAR_WIDTH = 220` (the hardcoded constant in Display.lua) becomes the authoritative value. This is acceptable for Phase 2 — CDM tab integration in Phase 3/4 will restore user-configurable widths via TBT's own settings.

**How to avoid:** Use `BAR_WIDTH` (the local constant, already 220) directly. Remove the `settings.barWidth` reference from `UpdateDisplay()` and replace with `BAR_WIDTH`. This is a temporary simplification acceptable for Phase 2 scope.

---

### Pitfall 5: EditMode Checkbox Injection Timing

**What goes wrong:** TBT tries to inject the sidebar checkbox at `PLAYER_ENTERING_WORLD` or `ADDON_LOADED`, but `EditModeManagerFrame.AccountSettings.SettingsContainer` may not yet be fully initialized (its `OnLoad` runs after all XML is parsed, but the scroll child layout may not be settled).

**How to avoid:** Inject the checkbox on the FIRST `EditMode.Enter` event (use a `tbtCheckboxInjected` flag to inject only once). By the time the player can open Edit Mode, the frame is guaranteed to be fully initialized.

---

### Pitfall 6: Container Frame Pool Still References Old Parent

**What goes wrong:** `barPool` and `iconPool` in Display.lua are populated lazily: `barPool[index] = CreateTimerBar(barContainer)`. After `InitDisplay()` runs and creates bars, the pool entries are parented to whatever `barContainer` was at creation time. If the restructuring creates `barContainer = _G["TBTBarContainer"]` late (in `InitEditModeFrames()` rather than `InitDisplay()`), any early call to `UpdateDisplay()` will see `barContainer = nil` and skip rendering, silently leaving the pool unpopulated.

**How to avoid:** Ensure `InitEditModeFrames()` runs BEFORE `InitDisplay()` in `Core.lua`, OR ensure `InitDisplay()` reads `ns.barContainer` (set by `EditModeFrames.lua`) rather than the old local variable.

---

## Code Examples

### EventRegistry Confirmed Pattern (HIGH confidence)

```lua
-- Source: wow-ui-source/Blizzard_EditMode/Shared/EditModeManager.lua line 89
-- EditModeManagerFrameMixin:EnterEditMode() calls:
EventRegistry:TriggerEvent("EditMode.Enter");

-- Line 108:
EventRegistry:TriggerEvent("EditMode.Exit");

-- Therefore TBT registration is:
EventRegistry:RegisterCallback("EditMode.Enter", function()
    ns:OnEditModeEnter()
end, ns)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    ns:OnEditModeExit()
end, ns)
```

### Sidebar Container Access Path (HIGH confidence)

```lua
-- Source: wow-ui-source/Blizzard_EditMode/Shared/EditModeManager.xml
-- Full path verified:
EditModeManagerFrame
    .AccountSettings           -- parentKey in XML (line ~136)
        .SettingsContainer     -- parentKey (ScrollFrame, line 142)
            .ScrollChild       -- ScrollChild frame (line 152)
                .BasicOptionsContainer   -- parentKey, GridLayoutFrame (line 154)
                .AdvancedOptionsContainer
                    .FramesContainer    -- parentKey, GridLayoutFrame (line 176)
                    .CombatContainer    -- parentKey, GridLayoutFrame (line 198)
                    .MiscContainer      -- parentKey, GridLayoutFrame (line 220)
```

### GridLayoutFrame Injection Pattern (MEDIUM confidence)

```lua
-- Source: wow-ui-source/Blizzard_SharedXML/LayoutFrame.lua GridLayoutFrameMixin:Layout()
-- GridLayoutFrame calls GetLayoutChildren() which returns all visible non-ignoreInLayout children
-- Children added at runtime are included on next Layout() call

-- Runtime injection (verified by LayoutSettings() in EditModeManager.lua which re-parents
-- existing checkboxes into different containers and triggers EditModeManagerFrame:Layout()):
local container = EditModeManagerFrame.AccountSettings.SettingsContainer.ScrollChild.BasicOptionsContainer
local cb = CreateFrame("Frame", nil, container, "EditModeManagerSettingCheckButtonTemplate")
cb.Label:SetText("TerribleBuffTracker")
cb.isBasicOption = true
-- ... wire callback ...
container:Layout()
```

### DB Init Pattern (existing, extend in Core.lua)

```lua
-- Source: Core.lua ADDON_LOADED handler (existing pattern)
-- Add after existing ns.db.trackedBuffs init:
if ns.db.editModePositions == nil then
    -- Intentionally left nil — ApplyEditModePositions() writes defaults on first call
end
if ns.db.tbtVisible == nil then
    ns.db.tbtVisible = true
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CDM-parented containers anchored to viewers | UIParent-parented named containers with persisted positions | Phase 2 | Containers no longer move when CDM layout refreshes |
| `SnapshotSettings()` on every CDM layout event | Hardcoded display defaults (Phase 2); TBT DB settings (Phase 3+) | Phase 2 | Per-frame CDM reads eliminated |
| `EventRegistry "EditMode.Exit"` used only for SnapshotSettings | `EditMode.Enter` and `EditMode.Exit` used for full Edit Mode container behavior | Phase 2 | Proper movable container lifecycle |

**Deprecated/outdated after this phase:**
- `HookViewerLayout()` helper function: deleted
- `SnapshotSettings()` function: deleted
- `ReadBarSettings()` / `ReadIconSettings()`: deleted
- `barEditing = ns.cdmBarViewer.isEditing` pattern: replaced by `ns.editModeActive`
- `barContainer = CreateFrame("Frame", nil, ns.cdmBarViewer)` pattern: replaced by named UIParent frame

---

## Open Questions

1. **What replaces `cachedBarSettings` for Phase 2?**
   - What we know: UpdateDisplay() uses ~10 fields from `cachedBarSettings`. Deleting SnapshotSettings() leaves these nil.
   - What's unclear: Does the planner want a new `ns.db.displaySettings` DB sub-object for Phase 2, or hardcoded CDM-matching defaults?
   - Recommendation: Use hardcoded CDM-matching defaults for Phase 2 (as listed in Pitfall 2 above). Phase 3's CDM tab will introduce TBT-owned settings. The hardcoded defaults match CDM's factory defaults, so behavior is unchanged from the user's perspective.

2. **Checkbox injection — is `EditModeManagerSettingCheckButtonTemplate` safe to use for third-party frames?**
   - What we know: It's a `virtual="true"` XML template, available to all addons. The `EditModeManagerSettingCheckButton_OnLoad` function in `EditModeTemplates.lua` only calls `self.Label:SetWidth(...)` — no registered state, no global callbacks.
   - What's unclear: Whether `LayoutSettings()` in `EditModeAccountSettingsMixin` (which re-parents existing checkboxes) will accidentally move TBT's injected checkbox on `EditMode.Enter`.
   - Recommendation: TBT's injected checkbox will be re-parented if `LayoutSettings()` iterates `self.settingsCheckButtons` and TBT's button is NOT in that table. Since TBT doesn't call `SetupEditModeCheckBox()` (which adds to `settingsCheckButtons`), TBT's button will NOT be touched by `LayoutSettings()`. It stays in `BasicOptionsContainer` permanently. Confidence: HIGH.

3. **Should `ns.cdmBarViewer` and `ns.cdmIconViewer` references be removed entirely?**
   - What we know: After CDM hook removal, these references are only used for `isEditing` in UpdateDisplay(). They are set in `InitDisplay()`.
   - What's unclear: Whether CDM viewers will be needed in later phases (Phase 3 CDM tab injection may need them for viewer existence checks).
   - Recommendation: Keep `ns.cdmBarViewer` and `ns.cdmIconViewer` assignment but remove all reads except a nil-guard on init. The failure message `"Cooldown Manager not found. Addon disabled."` still needs the existence check.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely Lua code changes with no external tool dependencies beyond the existing WoW installation. No CLI tools, databases, or services required.

---

## Validation Architecture

No automated test framework exists or is applicable for WoW addons. All validation is in-game manual testing.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None (WoW addon — no unit test infrastructure) |
| Config file | None |
| Quick run command | `/reload` in-game |
| Full suite command | Manual scenario checklist below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| EDM-01 | Two movable containers appear in Edit Mode | manual | — | Enter Edit Mode; verify drag handles on both containers; drag each to new position |
| EDM-02 | Sidebar checkbox toggles both containers | manual | — | Open Edit Mode; find TBT checkbox in sidebar; uncheck → both hide; re-check → both show |
| EDM-03 | Fresh install uses hardcoded defaults (D-06 override) | manual | — | Delete DB (`/run TerribleBuffTrackerDB = nil`); `/reload`; containers appear at CENTER+300,0 and CENTER+300,-80 |
| EDM-04 | User-set positions persist across `/reload` | manual | — | Move container in Edit Mode; exit Edit Mode; `/reload`; container in same position |
| EDM-05 | CDM layout refresh does not move containers | manual | — | Set TBT position in Edit Mode; change CDM bar width in CDM settings; verify TBT container does not move |

### Wave 0 Gaps

None — WoW addon testing is entirely manual. No test files to create.

---

## Project Constraints (from CLAUDE.md)

All directives that constrain this phase:

- `COMBAT_LOG_EVENT_UNFILTERED` is disabled — not relevant to this phase
- Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection — not relevant to this phase
- Requires Blizzard's Cooldown Manager (CDM) — containers decouple from CDM hierarchy but CDM must still exist (checked in `InitDisplay()`)
- Always run `stylua` on Lua files after finishing a task — planner must include stylua task after each file edit
- After every commit, run performance and code cleanup review — planner must include cleanup review task
- No standalone fallback for CDM — addon still gates on CDM existence; Edit Mode containers simply don't require CDM for positioning

---

## Sources

### Primary (HIGH confidence)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua` — `EnterEditMode()` line 89, `ExitEditMode()` line 108 confirm `EventRegistry:TriggerEvent` patterns; `RegisterSystemFrame` is append-only; `InitializeAccountSettings()` and `checkBoxSetupData` confirm sidebar is XML-backed; `LayoutSettings()` confirms GridLayoutFrame reparenting pattern
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.xml` — `SettingsContainer`, `BasicOptionsContainer` frame hierarchy verified; all sidebar checkboxes are XML-defined `parentKey` children
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeTemplates.xml` — `EditModeManagerSettingCheckButtonTemplate` (inherits `EditModeCheckButtonTemplate`) with `fixedWidth=225`, `fixedHeight=32`; `EditModeManagerSettingsOptionsContainerTemplate` is `GridLayoutFrame` with `alwaysUpdateLayout=true`, `stride=2`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeTemplates.lua` — `EditModeManagerSettingCheckButtonMixin`, `EditModeCheckButtonMixin` confirming `SetCallback`, `SetControlChecked`, `Label` parentKey APIs
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\LayoutFrame.lua` — `GridLayoutFrameMixin:Layout()` iterates `GetLayoutChildren()` confirming dynamic children are picked up

### Secondary (MEDIUM confidence)

- `C:\Users\jonat\Repositories\TerribleBuffTracker\Display.lua` — Existing `InitDisplay()`, `SnapshotSettings()`, `HookViewerLayout()`, `UpdateDisplay()` implementations; lines 357–394 are the main restructuring target
- `C:\Users\jonat\Repositories\TerribleBuffTracker\Core.lua` — Existing DB init pattern in `ADDON_LOADED`; `InitDisplay()` call in `PLAYER_ENTERING_WORLD`
- `.planning/research/ARCHITECTURE.md` — Edit Mode integration pattern (Pattern 4), position persistence DB schema
- `.planning/research/PITFALLS.md` — Pitfall 4 (Edit Mode registration timing), Pitfall 5 (unnamed frame anchor serialization), Pitfall 9 (CDM hooks vs. Edit Mode)
- `.planning/phases/02-edit-mode-containers/02-UI-SPEC.md` — Drag handle dimensions, colors, default positions, DB schema, interaction contract

---

## Metadata

**Confidence breakdown:**
- EventRegistry patterns: HIGH — directly read from Blizzard source
- Container creation + position persistence: HIGH — established WoW patterns; confirmed by ARCHITECTURE.md
- Sidebar checkbox injection: MEDIUM-HIGH — GridLayoutFrame injection is viable but unofficial; `LayoutSettings()` non-interference confirmed by code review
- cachedBarSettings replacement: MEDIUM — logic is sound but depends on planner's discretion about display config source

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (WoW Midnight patches may change EditModeManager internals; re-verify sidebar injection if game patches)
