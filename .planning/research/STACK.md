# Stack Research

**Domain:** WoW Midnight addon — CDM tab integration, Edit Mode movable frames, drag-and-drop buff management
**Researched:** 2026-03-28
**Confidence:** HIGH (all findings verified directly from Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

---

## Recommended Stack

### Core Technologies

| Technology | Version/Source | Purpose | Why Recommended |
|------------|---------------|---------|-----------------|
| WoW Lua Frame API | Interface 120000 | All UI frames, event handling | Native; no alternative |
| `CooldownViewerSettingsTabTemplate` | `CooldownViewerSettings.xml:140` | TBT lateral tab button on the CDM window | Inherits `LargeSideTabButtonTemplate` with `parentArray="TabButtons"` — CDM's tab system iterates `self.TabButtons` so any frame with that parentArray and a `displayMode` KeyValue is picked up by `SetupTabs()` |
| `SidePanelTabButtonMixin` | `SharedUIPanelTemplates.lua:295` | Tab button behavior (SetChecked, tooltips, icon atlas) | CDM tab template uses this mixin; `SetChecked(bool)` swaps `activeAtlas`/`inactiveAtlas` and shows/hides `SelectedTexture`; tab click handled via `SetCustomOnMouseUpHandler` |
| `EventRegistry` | Blizzard global | CDM lifecycle hooks, reorder events | CDM fires `CooldownViewerSettings.OnShow`, `CooldownViewerSettings.OnHide`, and `CooldownViewerSettings.OnDataChanged` — the canonical hook points for a third-party tab to attach/detach its panel |
| `GridLayoutFrame` | `LayoutFrame.xml` / `GridLayoutUtil.lua` | Category item grid layout | CDM uses `GridLayoutFrame` with `childXPadding`, `childYPadding`, `stride`, `isHorizontal`, `layoutFramesGoingRight`, `layoutFramesGoingUp`, `alwaysUpdateLayout` as KeyValues — this is how icon grids and bar lists auto-layout |
| `ResizeLayoutFrame` | `LayoutFrame.xml` | Auto-sizing category container | CDM category template (`CooldownViewerSettingsCategoryTemplate`) inherits `ResizeLayoutFrame`; TBT sections should do the same so height adjusts as items are added/removed |
| `CreateFramePool` | WoW Frame API | Item pool for drag-drop grid cells | CDM category uses `CreateFramePool("Frame", self.Container, itemTemplate)` with `itemPool:Acquire()` / `itemPool:ReleaseAll()` — this is the pattern for pooling draggable buff icons |
| `StartMoving` / `StopMovingOrSizing` | WoW Frame API | TBT movable containers (bars + buffs) | Third-party addons cannot register with `Enum.EditModeSystem` (requires a server-side enum entry). The standard pattern is: `EventRegistry:RegisterCallback("EditMode.Enter", ...)` to show drag handles and `EventRegistry:RegisterCallback("EditMode.Exit", ...)` to persist positions in SavedVariables |
| `GLOBAL_MOUSE_UP` | WoW event | Drag-drop commit / cancel | CDM uses `self:RegisterEvent("GLOBAL_MOUSE_UP")` and `self:UnregisterEvent("GLOBAL_MOUSE_UP")` bracketed around a drag session; LeftButton = commit, RightButton = cancel |
| `GetScaledCursorPositionForFrame` | WoW API | Cursor position during drag | CDM uses this in `CooldownViewerSettingsDraggedItemMixin:OnUpdate()` to follow the cursor correctly across scale changes |
| `GetAppropriateTopLevelParent` | Blizzard global | Parent for drag cursor phantom | CDM creates the drag-following ghost frame with `CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")` |
| `MenuUtil.CreateContextMenu` | Blizzard SharedXML | Right-click context menu | CDM uses `MenuUtil.CreateContextMenu(self, function(owner, rootDescription) ... end)` for per-item context menus — the correct Midnight pattern replacing old `UIDropDownMenu` |
| `ScrollFrameTemplate` | Blizzard SharedXML | Scrollable category list | CDM uses `ScrollFrameTemplate` with `scrollBarHideIfUnscrollable=false`; TBT should use the same for the buff list in the settings panel |

### Supporting APIs

| API | Source | Purpose | When to Use |
|-----|--------|---------|-------------|
| `CreateAnchor` | `LayoutFrame.lua` | Layout-frame anchor helper | Used inside `GridLayoutFrame` children to chain SetPoint calls cleanly |
| `RegionUtil.GetSides` | Blizzard SharedXML | Get left/right/bottom/top of a region | CDM uses this in nearest-item hit-testing during drag; needed for drop-zone targeting |
| `AnchorUtil.CreateAnchor` | Blizzard SharedXML | Edit Mode settings dialog anchor | `EditModeSystemMixin:SetupSettingsDialogAnchor` uses this; not needed by TBT but documents where anchor helpers live |
| `StaticPopup_Show` | WoW global | "Add Buff" spell ID/duration dialog | CDM uses `StaticPopup_Show` for confirmation dialogs; for the Add button in Suggested section this is simpler than a custom dialog frame |
| `ListHeaderThreeSliceTemplate` | Blizzard SharedXML | Category header bar | CDM category uses this as `parentKey="Header"` — provides the collapse arrow, title text, and click registration |
| `GetCursorPosition` | WoW API | Cursor hit-testing during drag | CDM uses this in `UpdateReorderMarker`; divide by `GetAppropriateTopLevelParent():GetScale()` before comparing to frame coords |
| `PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)` | WoW API | Drag start audio feedback | CDM plays this in `OnDragStart`; also `SOUNDKIT.UI_CURSOR_DROP_OBJECT` on release |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `stylua` | Lua formatter | Run after every file edit; configured in `.stylua.toml` |
| `scripts/install.bat` | Deploy to WoW | Run after changes to test in-game |
| WoW UI source (`wow-ui-source`) | Pattern reference | Always consult before implementing any CDM or Edit Mode integration |

---

## Integration Patterns

### CDM Tab Integration

**How CDM's tab system works** (verified from `CooldownViewerSettings.xml` and `CooldownViewerSettings.lua`):

1. The CDM settings frame XML defines tabs as `parentArray="TabButtons"` — Lua sees them as `self.TabButtons[1]`, `self.TabButtons[2]`, etc.
2. `SetupTabs()` iterates `self.TabButtons` and calls `tabButton:SetCustomOnMouseUpHandler(TabHandler)`.
3. `TabHandler` calls `self:SetDisplayMode(tab.displayMode)` on click.
4. `SetDisplayMode(mode)` calls `SetChecked()` on each tab and `SetCurrentCategories()` with the category list for that mode.

**TBT cannot reuse CDM's `displayMode` routing** because `displayModeToCategories` is a local table. TBT must inject a tab button into `CooldownViewerSettings.TabButtons` after the frame exists, then listen to `CooldownViewerSettings.OnShow` to show/hide its own panel frame parented to `CooldownViewerSettings`.

**Recommended tab injection approach:**

```lua
-- After CooldownViewerSettings is loaded (use EventUtil.ContinueAfterAllEvents
-- with "VARIABLES_LOADED" and "PLAYER_ENTERING_WORLD"):
local tbtTab = CreateFrame("Frame", "TBTSettingsTab",
    CooldownViewerSettings, "CooldownViewerSettingsTabTemplate")
tbtTab.displayMode = "tbt_buffs"
tbtTab.activeAtlas = "icon_trackedbuffs"       -- reuse CDM atlas
tbtTab.inactiveAtlas = "icon_trackedbuffs"
tbtTab.tooltipText = "TBT Buffs"               -- or a localized string
-- Anchor below last existing tab
local lastTab = CooldownViewerSettings.TabButtons[#CooldownViewerSettings.TabButtons]
tbtTab:SetPoint("TOP", lastTab, "BOTTOM", 0, -3)
-- Register into TabButtons so SetupTabs-equivalent loop finds it
table.insert(CooldownViewerSettings.TabButtons, tbtTab)
```

Then intercept `OnMouseUp` via `SetCustomOnMouseUpHandler` on the new tab and show/hide TBT's own content frame (parented to `CooldownViewerSettings`, covering the `CooldownScroll` area). CDM's own categories are hidden by calling `CooldownViewerSettings:ClearDisplayCategories()` when TBT tab is active, and restored on tab change.

**Alternative approach (lower coupling):** Listen to `CooldownViewerSettings.OnShow` / `CooldownViewerSettings.OnHide` and overlay TBT's frame over CDM's window without injecting into its tab array. This avoids hooking Blizzard internals but requires TBT to manage its own tab button visibility manually.

### Drag-and-Drop within TBT Settings Panel

CDM implements drag as a **manual drag-follow pattern**, not WoW's native pickup/cursor system:

1. `OnDragStart` or `OnMouseUp(LeftButton)` — call `BeginOrderChange(item)` on the settings frame.
2. `BeginOrderChange` creates a ghost frame (`CooldownViewerSettingsDraggedItemTemplate`) parented to `GetAppropriateTopLevelParent()`, sets an `OnUpdate` on the main settings frame to reposition it each frame.
3. Ghost frame's `OnUpdate` calls `GetScaledCursorPositionForFrame(topLevel)` and `SetPoint("TOPLEFT", ...)`.
4. Main settings frame registers `GLOBAL_MOUSE_UP`. On `LeftButton` up: commits move. On `RightButton` up: cancels.
5. Commit logic: check cursor position against all drop targets, move item to the nearest, call `RefreshLayout()`.

**For TBT:** Buff icons are 38x38 frames (matching CDM's icon size). Each section (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) is a `GridLayoutFrame` container. Dragging a buff between sections changes its display mode in `TerribleBuffTrackerDB`.

**Drop zone for deletion (Not Displayed section):** CDM uses an "empty category" slot — a frame that is `SetAsEmptyCategory(categoryObj)` and shows a `cdm-empty` atlas. For TBT's delete zone, a fixed-size frame with a trash icon that responds to `OnEnter` during drag is the correct pattern.

### Edit Mode — Movable Containers

**Third-party addons cannot register with `Enum.EditModeSystem`** (verified: all `EditModeSystemTemplate` instances require a `system` KeyValue pointing to a server-backed `Enum.EditModeSystem` entry; `EditModeManagerFrame:RegisterSystemFrame(self)` is called from `EditModeSystemMixin:OnSystemLoad()` which itself is triggered by `OnLoad` on the XML template).

**What third-party addons CAN do:**

```lua
-- Listen to Edit Mode enter/exit via EventRegistry
EventRegistry:RegisterCallback("EditMode.Enter", function()
    -- Show drag handle overlay on TBT containers
    tbtBarsHandle:Show()
    tbtBuffsHandle:Show()
end, addonKey)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    -- Hide handles, persist final positions
    tbtBarsHandle:Hide()
    tbtBuffsHandle:Hide()
    -- Save to TerribleBuffTrackerDB
    ns.db.barsAnchor = { GetPoint(tbtBarsContainer) }
    ns.db.buffsAnchor = { GetPoint(tbtBuffsContainer) }
end, addonKey)
```

Each movable container needs:
- `frame:SetMovable(true)` during Edit Mode
- `frame:EnableMouse(true)` during Edit Mode
- `registerForDrag = "LeftButton"` in XML or `frame:RegisterForDrag("LeftButton")`
- `OnDragStart` → `frame:StartMoving()`
- `OnDragStop` → `frame:StopMovingOrSizing()` then save position

**Positioning persistence:** Store as `{point, relativeTo:GetName(), relativePoint, offsetX, offsetY}` in SavedVariables. Restore with `frame:SetPoint(...)` on `PLAYER_ENTERING_WORLD`. This is the standard third-party Edit Mode alternative.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Manual drag-follow ghost frame (CDM pattern) | WoW native `PickupSpell` / `CursorHasItem` drag | Never — native cursor drag only works for items/spells; not for custom data objects like TBT buffs |
| `EventRegistry:RegisterCallback("EditMode.Enter")` | Full `EditModeSystemMixin` registration | Only possible for Blizzard's own addons; enum entries are server-controlled and cannot be added by third-party addons |
| Inject tab into existing `CooldownViewerSettings` | Standalone config window | Standalone is simpler to implement but breaks the v0.2.0 design goal; CDM tab keeps settings co-located with the frame TBT is visually attached to |
| `GridLayoutFrame` with `ResizeLayoutFrame` wrapper | Manual `SetPoint` chaining for items | Manual chaining requires recalculating every position on each refresh; `GridLayoutFrame` handles stride, padding, and wrapping automatically |
| `GLOBAL_MOUSE_UP` for drag termination | `OnMouseUp` on each possible target | `GLOBAL_MOUSE_UP` fires regardless of what the mouse is over; `OnMouseUp` only fires if the button releases over the registered frame — CDM correctly uses `GLOBAL_MOUSE_UP` to always terminate drag sessions |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `UIDropDownMenu` / `UIDropDownMenuTemplate` | Deprecated since Dragonflight; removed or non-functional in Midnight | `MenuUtil.CreateContextMenu` with `rootDescription:CreateButton/CreateRadio/CreateCheckbox` |
| `EditModeManagerFrame:RegisterSystemFrame(self)` | Requires a valid `Enum.EditModeSystem` entry backed by C_EditMode server data; calling it with a fake system value crashes or produces broken behavior | `EventRegistry:RegisterCallback("EditMode.Enter/Exit")` + manual `StartMoving()` |
| `COMBAT_LOG_EVENT_UNFILTERED` | Disabled in Midnight — already excluded | `UNIT_SPELLCAST_SUCCEEDED` (already used by TBT) |
| Storing active timer state in SavedVariables | Active timers are runtime-only; persisting them creates stale state on reload | Runtime tables only; restore display from `TerribleBuffTrackerDB.trackedBuffs` config on load |
| Hooking `CooldownViewerSettings:SetDisplayMode` with a raw function replacement | Replaces the function globally; other code expecting original behavior breaks | Hook with `hooksecurefunc` or use `EventRegistry` callbacks and overlay your panel instead of replacing the function |
| `GetAppropriateTopLevelParent()` for drag ghost parent on non-fullscreen UI | Returns the correct root depending on whether the UI is fullscreen; skip-thinking this returns `UIParent` always | Always use `GetAppropriateTopLevelParent()` exactly as CDM does |
| Per-frame `GetPoint()`/`SetPoint()` calls in `OnUpdate` for non-drag-ghost work | Allocates per frame; causes GC pressure | Cache settings snapshot on `CooldownViewerSettings.OnShow`; only re-read on layout hooks and Edit Mode exit |

---

## Version Compatibility

| Component | Interface Version | Notes |
|-----------|------------------|-------|
| `LargeSideTabButtonTemplate` | 120000+ | Defined in `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`; uses `questlog-tab-side` atlas — available in Midnight |
| `CooldownViewerSettingsTabTemplate` | 120000+ | Lives in `Blizzard_CooldownViewer`; inherits `LargeSideTabButtonTemplate`; `parentArray="TabButtons"` is the hook point |
| `MenuUtil.CreateContextMenu` | 120000+ | Replaces UIDropDownMenu; confirmed present in CDM source |
| `GridLayoutFrame` | 120000+ | In `Blizzard_SharedXML`; `alwaysUpdateLayout = true` KeyValue is required to auto-refresh on item add/remove |
| `EventRegistry` callbacks for Edit Mode | 120000+ | `"EditMode.Enter"` and `"EditMode.Exit"` are triggered by `EditModeManagerFrameMixin:EnterEditMode()` and `ExitEditMode()`; these are the stable public hook points |
| `GLOBAL_MOUSE_UP` | All versions | Standard WoW event; safe to use |

---

## Key Architectural Facts (Verified from Source)

1. **CDM settings window is a UIPanel** (`RegisterUIPanel(self, { area = "left", pushable = 1, ... })`). TBT's tab panel must be parented to it and sized to match its content area — it does not push or replace CDM in the panel stack.

2. **CDM tab buttons are plain Frames**, not Buttons. They use `SidePanelTabButtonMixin` with custom `OnMouseUp` via `SetCustomOnMouseUpHandler`. The `SetChecked` method swaps `activeAtlas`/`inactiveAtlas` on the Icon texture and shows/hides `SelectedTexture`.

3. **CDM fires `CooldownViewerSettings.OnShow` and `CooldownViewerSettings.OnHide`** via `EventRegistry:TriggerEvent`. These are the canonical hook points for a TBT panel to appear/disappear without modifying Blizzard code.

4. **Drag-and-drop is entirely custom** in CDM — no WoW native drag API involved. The ghost frame has `frameStrata = "TOOLTIP"` so it renders above everything.

5. **Edit Mode system registration is closed to third-party addons.** `Enum.EditModeSystem` entries are backed by `C_EditMode` server data. Third-party movable elements must implement their own drag handle + `EventRegistry` pattern.

6. **`displayModeToCategories` in CDM is a file-local table** — TBT cannot extend it. TBT must intercept tab click and manage its own display panel visibility independently.

---

## Sources

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — CDM tab setup, drag-drop implementation, OnShow/OnHide events (HIGH confidence — source code)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — Frame templates: `CooldownViewerSettingsTabTemplate`, `CooldownViewerSettingsItemTemplate`, `CooldownViewerSettingsBarItemTemplate`, `CooldownViewerSettingsCategoryTemplate` (HIGH confidence — source code)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua` — `EditModeSystemMixin`, `EditModeCooldownViewerSystemMixin`, registration via `RegisterSystemFrame`, `OnEditModeEnter`/`OnEditModeExit` lifecycle (HIGH confidence — source code)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.xml` — `EditModeSystemTemplate` requiring `Enum.EditModeSystem` KeyValue; confirms third-party system registration is blocked (HIGH confidence — source code)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua` — `EnterEditMode`/`ExitEditMode` trigger `EventRegistry:TriggerEvent("EditMode.Enter/Exit")` (HIGH confidence — source code)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua` — `SidePanelTabButtonMixin` implementation (HIGH confidence — source code)

---
*Stack research for: WoW Midnight addon — CDM tab, Edit Mode, drag-drop*
*Researched: 2026-03-28*
