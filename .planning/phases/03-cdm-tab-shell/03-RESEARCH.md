# Phase 3: CDM Tab Shell - Research

**Researched:** 2026-03-28
**Domain:** WoW Midnight addon — CDM settings tab injection, content panel overlay, ConfigUI removal, /tbt rework
**Confidence:** HIGH (all findings verified from Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use `LargeSideTabButtonTemplate` for the tab button (43x55px), matching existing CDM tabs.
- **D-02:** Tab icon uses `hud-buff` atlas via SetAtlas. Can be changed during in-game verification if a better atlas is found.
- **D-03:** Tab label: "TBT Buffs" — short, clear, fits the tab width.
- **D-04:** Define the tab in an XML file with `parentArray="TabButtons"` so it registers at XML load time (research confirmed runtime CreateFrame does not auto-register into the TabButtons array).
- **D-05:** Never call `SetDisplayMode` with TBT strings — will crash with assertsafe. TBT manages its own tab checked state and content panel visibility independently.
- **D-06:** Hook `SetDisplayMode` via `hooksecurefunc` to detect when user clicks a CDM tab — use this to uncheck TBT tab and hide TBT panel.
- **D-07:** Content panel matches CDM's own scroll area style — same background, border, inset frame pattern. Include a scroll frame ready for Phase 4 sections.
- **D-08:** Panel is parented to CooldownViewerSettings and occupies the same area as CDM's category scroll frame.
- **D-09:** /tbt always opens CDM settings with the TBT tab selected. Never closes/toggles. If CDM is already open on another tab, switch to TBT tab.
- **D-10:** Implementation: open CDM settings (if not open), then programmatically select the TBT tab.
- **D-11:** Delete ConfigUI.lua entirely. All buff management functionality moves to CDM tab in Phase 4.
- **D-12:** Remove ConfigUI.lua from TerribleBuffTracker.toc.
- **D-13:** Remove `ns:ToggleConfigUI()` call from Core.lua slash command handler. Replace with the new /tbt behavior (D-09).
- **D-14:** `StartAllPreviewTimers()` and `ClearAllTimers()` stay in BuffEngine.lua (they already live there). No preview trigger from the shell — Phase 4 can add one.

### Claude's Discretion

- Exact XML file name and structure for the tab button
- How to open CDM settings programmatically (may need to find the CDM settings toggle function)
- Content panel scroll frame implementation details
- Whether a new CDMTab.lua file is needed or if the tab logic goes in an existing file

### Deferred Ideas (OUT OF SCOPE)

- Edit Mode selection highlighting (yellow) + per-element config panel
- Tab icon may change during verification — user wants to preview in-game first
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TAB-01 | User sees a "TBT Buffs" lateral tab button in CDM settings window | XML tab definition with `parentArray="TabButtons"` on `CooldownViewerSettingsTabTemplate` child; `SetupTabs()` wires OnMouseUp at load time |
| TAB-02 | User sees a TBT content panel when clicking the TBT tab | TBT-owned Frame parented to CooldownViewerSettings, covering CooldownScroll area; shown on tab click, hidden on `hooksecurefunc SetDisplayMode` |
| TAB-07 | Old standalone config UI is removed; /tbt opens CDM settings to TBT tab | Delete ConfigUI.lua + TOC entry; Core.lua slash command replaced with `CooldownViewerSettings:ShowUIPanel()` + programmatic TBT tab selection |
</phase_requirements>

---

## Summary

Phase 3 injects a "TBT Buffs" lateral tab into Blizzard's CDM settings window, shows a TBT-owned empty content panel when selected, removes the old standalone ConfigUI.lua, and reworks /tbt to open CDM settings directly to the TBT tab.

The CDM tab system works via `parentArray="TabButtons"` in XML — frames defined with this attribute are automatically indexed into `CooldownViewerSettings.TabButtons[]` at XML load time. `SetupTabs()` runs once during `CooldownViewerSettings:OnLoad()` and wires `SetCustomOnMouseUpHandler` on every frame in that array. TBT must define its tab in an XML file loaded before `CooldownViewerSettings` initializes (which completes after `COOLDOWN_VIEWER_DATA_LOADED`). The tab's click handler shows a TBT-owned content frame and manually manages `SetChecked` state — it must never call `CooldownViewerSettings:SetDisplayMode()` with a TBT-owned string because that function asserts on the `displayModeToCategories` local table which TBT cannot extend.

ConfigUI.lua has two integration points beyond the file itself: `ns:ToggleConfigUI()` in Core.lua's slash command, and `UISpecialFrames` registration of `"TerribleBuffTrackerConfig"`. Since ConfigUI.lua is being removed from the .toc, the frame never gets created, so `UISpecialFrames` is never populated — no explicit cleanup needed. The slash command handler in Core.lua must be fully replaced.

**Primary recommendation:** Define the TBT tab in a new `CDMTab.xml` file using `CooldownViewerSettingsTabTemplate` with `parentArray="TabButtons"`. Create `CDMTab.lua` for all Lua logic. Gate all CDM interaction behind `COOLDOWN_VIEWER_DATA_LOADED` event. The content panel is a plain Frame parented to `CooldownViewerSettings`, anchored to cover `CooldownScroll`, containing an empty `ScrollFrameTemplate` ready for Phase 4.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `CooldownViewerSettingsTabTemplate` | Interface 120000 | TBT tab button inheriting `LargeSideTabButtonTemplate` with `parentArray="TabButtons"` | CDM's own tab template; automatically indexed into `TabButtons` array at XML load time |
| `LargeSideTabButtonTemplate` | Interface 120000 | 43x55px side tab with `SidePanelTabButtonMixin`, `questlog-tab-side` background, Icon texture, SelectedTexture | Blizzard's tab template for the CDM settings side column; `SetChecked` swaps `activeAtlas`/`inactiveAtlas` |
| `SidePanelTabButtonMixin` | `SharedUIPanelTemplates.lua:295` | Tab behavior: `SetCustomOnMouseUpHandler`, `SetChecked`, `OnEnter`/`OnLeave` tooltips | Automatically mixed in via `LargeSideTabButtonTemplate`; `SetChecked(bool)` shows/hides `SelectedTexture` |
| `hooksecurefunc` | WoW global | Hook `CooldownViewerSettings.SetDisplayMode` to detect tab-away | Secure; does not replace the function; fires after original runs |
| `ScrollFrameTemplate` | Blizzard SharedXML | Scrollable content area in TBT panel | CDM uses same template; `scrollBarHideIfUnscrollable=false` KeyValue needed |
| `EventUtil.ContinueAfterAllEvents` | Blizzard global | Gate CDM interaction behind all three required events | Mirrors CDM's own initialization pattern exactly |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `EventRegistry` | Blizzard global | Listen to `CooldownViewerSettings.OnShow` / `OnHide` for future phase hooks | Phase 3 shell needs these as integration points for Phase 4 preview timers |
| `ShowUIPanel` / `HideUIPanel` | WoW global | Open CDM settings frame as a managed UI panel | Called via `CooldownViewerSettings:ShowUIPanel()` — already a method on the CDM frame |
| `ButtonFrameTemplate` | Blizzard SharedXML | CDM settings inherits this — provides `Inset` frame | TBT panel must be anchored inside `Inset`, not the outer frame |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| XML `parentArray="TabButtons"` | Runtime `table.insert(CooldownViewerSettings.TabButtons, tab)` | Runtime insertion after `SetupTabs()` has already run means `SetCustomOnMouseUpHandler` is not called automatically — requires manual handler wiring; also the tab is missed in `SetDisplayMode`'s `SetChecked` loop unless you insert before that event fires. XML is simpler and guaranteed correct. |
| `CooldownViewerSettings:ShowUIPanel()` | `ShowUIPanel(CooldownViewerSettings)` directly | Both work; `ShowUIPanel(self)` is what `ShowUIPanel` method calls internally — calling the method is cleaner as it also calls `EditModeManagerFrame:CheckHideAndLockEditMode()` |

---

## Architecture Patterns

### Recommended File Structure

```
TerribleBuffTracker/
├── Core.lua              -- MODIFIED: slash command rework
├── BuffEngine.lua        -- unchanged in this phase
├── EditModeFrames.lua    -- unchanged in this phase
├── Display.lua           -- unchanged in this phase
├── CDMTab.xml            -- NEW: tab frame definition
├── CDMTab.lua            -- NEW: tab injection logic and content panel
├── tbt_icon_64x64.blp
└── TerribleBuffTracker.toc  -- MODIFIED: add CDMTab.xml, CDMTab.lua; remove ConfigUI.lua
```

ConfigUI.lua is deleted; not kept as dead code.

### Pattern 1: XML Tab Definition with parentArray

**What:** Define the TBT tab as an XML child of `CooldownViewerSettings` using `CooldownViewerSettingsTabTemplate`. The `parentArray="TabButtons"` attribute on the template causes it to be indexed into `CooldownViewerSettings.TabButtons` at XML load time, before any Lua runs.

**When to use:** Any time a third-party addon needs to appear as a native CDM tab.

**Example:**
```xml
<!-- CDMTab.xml -->
<Ui xmlns="http://www.blizzard.com/wow/ui/" ...>
    <Frame name="TBTSettingsTab" parent="CooldownViewerSettings"
           inherits="CooldownViewerSettingsTabTemplate">
        <KeyValues>
            <KeyValue key="displayMode" value="tbt_buffs" type="string"/>
            <KeyValue key="activeAtlas" value="hud-buff" type="string"/>
            <KeyValue key="inactiveAtlas" value="hud-buff" type="string"/>
            <KeyValue key="tooltipText" value="TBT Buffs" type="string"/>
        </KeyValues>
        <Anchors>
            <Anchor point="TOP" relativeKey="$parent.AurasTab"
                    relativePoint="BOTTOM" x="0" y="-3"/>
        </Anchors>
    </Frame>
</Ui>
```

**Critical:** `parent="CooldownViewerSettings"` in the XML means `CooldownViewerSettingsTabTemplate` (which has `parentArray="TabButtons"`) auto-registers TBTSettingsTab into `CooldownViewerSettings.TabButtons` at XML load time — before `SetupTabs()` runs.

**Verified from:** `CooldownViewerSettings.xml:140` — `CooldownViewerSettingsTabTemplate` is defined as `inherits="LargeSideTabButtonTemplate" parentArray="TabButtons" virtual="true"`. The SpellsTab and AurasTab children both use this template and are accessed as `self.TabButtons[1]` and `self.TabButtons[2]` by index.

### Pattern 2: Tab Click Handler (no SetDisplayMode)

**What:** Wire `SetCustomOnMouseUpHandler` on TBTSettingsTab in `CDMTab.lua` after `COOLDOWN_VIEWER_DATA_LOADED`. The handler shows TBT's panel, hides CDM's scroll frame, and manually sets checked state for all tabs.

**Why:** `SetDisplayMode("tbt_buffs")` would assertsafe because `displayModeToCategories` (a file-local table in `CooldownViewerSettings.lua`) contains only `"spells"` and `"auras"`. TBT cannot extend it. The tab must manage its own visibility independently.

```lua
-- Source: CooldownViewerSettings.lua:1443-1457 (SetDisplayMode logic)
-- Source: SharedUIPanelTemplates.lua:303-316 (SidePanelTabButtonMixin.OnMouseUp + SetCustomOnMouseUpHandler)

local function OnTBTTabClick(tab, button, upInside)
    if button == "LeftButton" and upInside then
        -- Show TBT panel, hide CDM scroll
        ns:ShowTBTPanel()
        -- Manually check TBT tab, uncheck others
        -- (SetDisplayMode does this for CDM tabs; we must replicate it)
        for _, t in ipairs(CooldownViewerSettings.TabButtons) do
            t:SetChecked(t == tab)
        end
    end
end

TBTSettingsTab:SetCustomOnMouseUpHandler(OnTBTTabClick)
```

### Pattern 3: Hook SetDisplayMode to Detect Tab-Away

**What:** When the user clicks a CDM tab (Spells or Auras), `SetDisplayMode` is called. TBT hooks this to hide its panel and restore `CooldownScroll`.

```lua
-- Source: Architecture.md Pattern 2; PITFALLS.md Pitfall 3
hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", function(self, mode)
    -- SetDisplayMode only fires for CDM's own modes ("spells"/"auras")
    -- TBT's tab click bypasses SetDisplayMode entirely
    ns:HideTBTPanel()
end)
```

**Important:** `SetDisplayMode` early-returns if `mode == self.displayMode` (line 1444). When the CDM settings window opens and the mode is already set, it does not fire again. TBT must also handle `CooldownViewerSettings.OnShow` to correctly hide/show its panel based on whether TBT tab was previously selected.

### Pattern 4: TBT Content Panel Geometry

**What:** TBT's content panel overlays exactly where `CooldownScroll` sits. `CooldownScroll` is anchored `TOPLEFT x=17 y=-72` to `BOTTOMRIGHT x=-30 y=29` relative to `CooldownViewerSettings`. The TBT panel uses the same anchors so it occupies the same region.

```lua
-- Source: CooldownViewerSettings.xml:201-220 (CooldownScroll anchors)
local tbtPanel = CreateFrame("Frame", "TBTSettingsPanel", CooldownViewerSettings,
    "BackdropTemplate")
tbtPanel:SetPoint("TOPLEFT", CooldownViewerSettings, "TOPLEFT", 17, -72)
tbtPanel:SetPoint("BOTTOMRIGHT", CooldownViewerSettings, "BOTTOMRIGHT", -30, 29)
tbtPanel:Hide()

-- Inside it, a ScrollFrame ready for Phase 4:
local scrollFrame = CreateFrame("ScrollFrame", nil, tbtPanel, "ScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 0, 0)
scrollFrame:SetPoint("BOTTOMRIGHT", -17, 0)
-- scrollBarHideIfUnscrollable=false matches CDM's pattern (but set via KeyValue in XML
-- or after creation via scrollFrame.ScrollBar:SetHideIfUnscrollable(false))

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(tbtPanel:GetWidth() - 17, 1)
scrollFrame:SetScrollChild(scrollChild)
```

### Pattern 5: Show CDM Settings + Select TBT Tab (/tbt command)

**What:** `CooldownViewerSettings` has a `ShowUIPanel()` method (line 1587) and a `TogglePanel()` method (line 1595). For /tbt, D-09 says "always open, never toggle" and "select TBT tab."

```lua
-- Source: CooldownViewerSettings.lua:1587-1601
SlashCmdList["TERRIBLEBUFFTRACKER"] = function()
    -- Open if not visible (do not toggle closed)
    if not CooldownViewerSettings:IsVisible() then
        CooldownViewerSettings:ShowUIPanel()
    end
    -- Select TBT tab regardless of current state
    ns:SelectTBTTab()
end

-- ns:SelectTBTTab() in CDMTab.lua:
function ns:SelectTBTTab()
    ns:ShowTBTPanel()
    for _, t in ipairs(CooldownViewerSettings.TabButtons) do
        t:SetChecked(t == TBTSettingsTab)
    end
end
```

**Timing:** `CooldownViewerSettings:ShowUIPanel()` calls `ShowUIPanel(self)` which triggers `OnShow`, which calls `SetDisplayMode("spells")` if no mode was set. This fires the `hooksecurefunc` hook which calls `ns:HideTBTPanel()`. Therefore `ns:SelectTBTTab()` must be called after `ShowUIPanel` completes — in the same Lua frame this is fine since `ShowUIPanel` is synchronous, but `SetDisplayMode` fires after, hiding TBT panel. Order of operations:

1. `CooldownViewerSettings:ShowUIPanel()` — triggers OnShow
2. OnShow calls `SetDisplayMode("spells")` if `.displayMode` is nil (first open only)
3. `hooksecurefunc` fires → `ns:HideTBTPanel()`
4. Then call `ns:SelectTBTTab()` to show TBT panel and update checked states

The slash command should call `SelectTBTTab()` after the frame is shown. Since both happen synchronously before the frame renders, the final state is TBT tab selected.

**Alternative for when CDM is already open:** If `CooldownViewerSettings:IsVisible()` is true, skip `ShowUIPanel` and call `SelectTBTTab()` directly. This matches D-09: "If CDM is already open on another tab, switch to TBT tab."

### Pattern 6: Initialization Gate

**What:** CDM's own `LoadCooldownSettings` runs after all three of `VARIABLES_LOADED`, `PLAYER_ENTERING_WORLD`, and `COOLDOWN_VIEWER_DATA_LOADED`. TBT must wait for the same.

```lua
-- Source: CooldownViewerSettings.lua:821
-- Mirror CDM's own pattern:
EventUtil.ContinueAfterAllEvents(function()
    ns:InitCDMTab()
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED")
```

`InitCDMTab()` wires the tab click handler, the `hooksecurefunc` hook, and creates the TBT content panel.

**Note:** TBTSettingsTab already exists (defined in XML, parented to CooldownViewerSettings) at this point. InitCDMTab only needs to call `SetCustomOnMouseUpHandler` and create the content panel — it does not create the tab frame.

### Anti-Patterns to Avoid

- **Calling `SetDisplayMode("tbt_buffs")`:** Triggers `assertsafe` on `displayModeToCategories[displayMode]`. CDM settings window goes blank. Never call this with a non-CDM mode string.
- **Runtime `CreateFrame` expecting auto-registration:** `parentArray` is XML-only. A runtime-created frame is NOT added to `TabButtons` unless you also call `table.insert()` manually — and then you also must manually call `SetCustomOnMouseUpHandler` since `SetupTabs()` has already run.
- **Parenting TBT panel to `CooldownScroll.Content`:** CDM's `ClearDisplayCategories()` calls `self.categoryPool:ReleaseAll()` which releases content frames; any non-pooled frames parented there will have anchors broken.
- **Reading CDM frame properties before `COOLDOWN_VIEWER_DATA_LOADED`:** `CooldownViewerSettings.layoutManager` and `.dataProvider` are nil until `LoadCooldownSettings` runs.
- **Leaving `UISpecialFrames` + `ns:ToggleConfigUI` in Core.lua:** ConfigUI.lua is removed from TOC so its frame is never created; `UISpecialFrames` is not populated. But `ns:ToggleConfigUI` in the slash handler would throw "attempt to call nil value". Core.lua slash command MUST be replaced.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tab checked state visual | Custom texture swapping code | `SidePanelTabButtonMixin:SetChecked(bool)` | Already swaps `activeAtlas`/`inactiveAtlas` and shows/hides `SelectedTexture`; hand-rolling duplicates this |
| Tab tooltip | Custom OnEnter/OnLeave scripts | `SidePanelTabButtonMixin:OnEnter/OnLeave` + `tooltipText` KeyValue | Mixin already uses `GetAppropriateTooltip()` correctly |
| Tab click dispatch | Custom OnMouseDown/Up logic | `SetCustomOnMouseUpHandler` | This is the sanctioned extension point for tab-click behavior; the mixin still handles sound and icon press effect |
| Opening CDM settings | Direct `CooldownViewerSettings:Show()` | `CooldownViewerSettings:ShowUIPanel()` | `ShowUIPanel` method also calls `EditModeManagerFrame:CheckHideAndLockEditMode()`; direct `:Show()` skips this |

**Key insight:** `SidePanelTabButtonMixin` handles all visual behavior. TBT only needs to provide KeyValues (`activeAtlas`, `inactiveAtlas`, `tooltipText`, `displayMode`) and one `SetCustomOnMouseUpHandler` call.

---

## Common Pitfalls

### Pitfall 1: SetDisplayMode assertsafe crash
**What goes wrong:** Calling `CooldownViewerSettings:SetDisplayMode("tbt_buffs")` causes `assertsafe` to fire: "Add missing category data for displayMode: tbt_buffs". CDM settings goes blank.
**Why it happens:** `displayModeToCategories` is a file-local Lua table containing only `"spells"` and `"auras"`. Third-party addons cannot add entries to it.
**How to avoid:** TBT's tab click never calls `SetDisplayMode`. TBT manages its own checked state with a `for _, t in ipairs(CooldownViewerSettings.TabButtons) do t:SetChecked(t == tab) end` loop.
**Warning signs:** Lua error "Add missing category data for displayMode" in chat; settings panel goes blank.

### Pitfall 2: SetupTabs runs once at OnLoad — late handler wiring is required
**What goes wrong:** `SetupTabs()` is called from `CooldownViewerSettingsMixin:OnLoad()` (line 798). It iterates `self.TabButtons` and calls `SetCustomOnMouseUpHandler` on each. A tab defined in XML with `parentArray="TabButtons"` IS in the array at that point, so its handler IS wired automatically... to the default CDM `TabHandler` which calls `SetDisplayMode(tab.displayMode)`. TBT must replace this handler.
**How to avoid:** After `COOLDOWN_VIEWER_DATA_LOADED`, call `TBTSettingsTab:SetCustomOnMouseUpHandler(OnTBTTabClick)` to override the default handler that `SetupTabs` installed.
**Consequence of not doing this:** Clicking TBT tab calls `SetDisplayMode("tbt_buffs")` → assertsafe crash.

### Pitfall 3: OnShow SetDisplayMode fires before SelectTBTTab
**What goes wrong:** When /tbt opens CDM for the first time (no `self.displayMode` set), `OnShow` calls `SetDisplayMode("spells")`. The `hooksecurefunc` hook fires `ns:HideTBTPanel()`. If TBT then calls `SelectTBTTab()` it re-shows the panel — but the CDM scroll was also just shown by `SetDisplayMode`. TBT must explicitly hide `CooldownViewerSettings.CooldownScroll` as part of `ShowTBTPanel()`.
**How to avoid:** In `ns:ShowTBTPanel()`: show TBT panel AND hide `CooldownViewerSettings.CooldownScroll`. In `ns:HideTBTPanel()`: hide TBT panel AND show `CooldownViewerSettings.CooldownScroll` (only if scroll was hidden).

### Pitfall 4: COOLDOWN_VIEWER_DATA_LOADED timing
**What goes wrong:** `CDMTab.lua` init code that calls `TBTSettingsTab:SetCustomOnMouseUpHandler` runs before `LoadCooldownSettings` has run — CDM internals not yet ready.
**Why it happens:** `CooldownViewerSettings` exists in the global namespace (created in XML), but internal initialization is deferred.
**How to avoid:** All CDM interaction in `CDMTab.lua` must happen inside a callback registered via `EventUtil.ContinueAfterAllEvents(..., "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED")`.
**Note:** The XML tab frame definition is fine to exist before that event — it just sits in `TabButtons` array with its KeyValues until TBT's Lua wires the custom handler.

### Pitfall 5: Slash command broken after ConfigUI removal
**What goes wrong:** Core.lua line 56 calls `ns:ToggleConfigUI()`. ConfigUI.lua defines that function. After removing ConfigUI.lua from TOC, the function is nil → Lua error on `/tbt`.
**How to avoid:** Replace the slash command body before removing ConfigUI.lua. Both changes go in the same phase.
**Additional note:** ConfigUI.lua adds `"TerribleBuffTrackerConfig"` to `UISpecialFrames` (line 45). Since the file is removed from TOC, `CreateConfigFrame()` never runs, so `UISpecialFrames` is never populated — no cleanup needed. Verified by reviewing ConfigUI.lua: `UISpecialFrames` insertion is inside `CreateConfigFrame()`, which is only called from `ns:ToggleConfigUI()`.

---

## Code Examples

Verified patterns from Blizzard source:

### SetupTabs loop (what TBT's tab is inserted into)
```lua
-- Source: CooldownViewerSettings.lua:848-857
function CooldownViewerSettingsMixin:SetupTabs()
    local function TabHandler(tab, button, upInside)
        if button == "LeftButton" and upInside then
            self:SetDisplayMode(tab.displayMode)  -- TBT must NOT let this fire
        end
    end
    for i, tabButton in ipairs(self.TabButtons) do
        tabButton:SetCustomOnMouseUpHandler(TabHandler)
    end
end
```

### SetChecked implementation (visual swap)
```lua
-- Source: SharedUIPanelTemplates.lua:318-327
function SidePanelTabButtonMixin:SetChecked(checked)
    if checked then
        self.Icon:SetAtlas(self.activeAtlas, TextureKitConstants.UseAtlasSize)
    else
        self.Icon:SetAtlas(self.inactiveAtlas, TextureKitConstants.UseAtlasSize)
    end
    if self.SelectedTexture then
        self.SelectedTexture:SetShown(checked)
    end
end
```

### SetDisplayMode (the assertsafe TBT must avoid)
```lua
-- Source: CooldownViewerSettings.lua:1443-1457
function CooldownViewerSettingsMixin:SetDisplayMode(displayMode)
    if displayMode == self.displayMode then return end
    self.displayMode = displayMode
    for i, frame in ipairs(self.TabButtons) do
        frame:SetChecked(frame.displayMode == displayMode)
    end
    local categories = displayModeToCategories[displayMode]
    assertsafe(type(categories) == "table",  -- CRASHES if "tbt_buffs" passed
        "Add missing category data for displayMode: " .. tostring(displayMode))
    self:SetCurrentCategories(categories)
end
```

### CooldownScroll exact anchors
```xml
<!-- Source: CooldownViewerSettings.xml:201-220 -->
<ScrollFrame parentKey="CooldownScroll" inherits="ScrollFrameTemplate">
    <Anchors>
        <Anchor point="TOPLEFT" x="17" y="-72"/>
        <Anchor point="BOTTOMRIGHT" x="-30" y="29"/>
    </Anchors>
```

### How CDM settings is opened externally
```lua
-- Source: CooldownViewerSettings.lua:1587-1601
function CooldownViewerSettingsMixin:ShowUIPanel(fromEditMode)
    if fromEditMode then
        EditModeManagerFrame:CheckHideAndLockEditMode()
    end
    ShowUIPanel(self)
end

function CooldownViewerSettingsMixin:TogglePanel()
    if self:IsVisible() then HideUIPanel(self)
    else self:ShowUIPanel() end
end
-- Also exposed as keybinding: CooldownViewerSettings:TogglePanel() in Bindings_Standard.xml:1251
```

### LargeSideTabButtonTemplate size and structure
```xml
<!-- Source: SharedUIPanelTemplates.xml:981-1011 -->
<Frame name="LargeSideTabButtonTemplate" mixin="SidePanelTabButtonMixin" virtual="true">
    <Size x="43" y="55"/>
    <!-- Background: "questlog-tab-side" atlas -->
    <!-- Icon texture: set via activeAtlas/inactiveAtlas KeyValues -->
    <!-- SelectedTexture: "QuestLog-Tab-side-Glow-select" atlas, hidden when unchecked -->
    <!-- Highlight: "QuestLog-Tab-side-Glow-hover" atlas -->
```

### AurasTab anchor (model for TBT tab anchor)
```xml
<!-- Source: CooldownViewerSettings.xml:169-179 -->
<Frame parentKey="AurasTab" inherits="CooldownViewerSettingsTabTemplate">
    <KeyValues>
        <KeyValue key="displayMode" value="auras" type="string"/>
        <KeyValue key="activeAtlas" value="icon_trackedbuffs" type="string"/>
        <KeyValue key="inactiveAtlas" value="icon_trackedbuffs" type="string"/>
        <KeyValue key="tooltipText" value="COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS" type="global"/>
    </KeyValues>
    <Anchors>
        <Anchor point="TOP" relativeKey="$parent.SpellsTab" relativePoint="BOTTOM" x="0" y="-3"/>
    </Anchors>
</Frame>
```
TBT tab anchor follows the same pattern: `point="TOP"` on `$parent.AurasTab` `relativePoint="BOTTOM"` `y="-3"`.

---

## Project Constraints (from CLAUDE.md)

| Directive | Applies To |
|-----------|-----------|
| Run `stylua` on all Lua files after task completion | CDMTab.lua, Core.lua |
| `COMBAT_LOG_EVENT_UNFILTERED` is disabled — do not use | N/A this phase |
| Secret Values — guard behind fail-safe calls | N/A this phase |
| Use `UNIT_SPELLCAST_SUCCEEDED` for cast detection | N/A this phase |
| No standalone fallback for CDM — addon requires CDM | Confirmed; CDMTab.lua may assume `CooldownViewerSettings` exists |
| Run `scripts/install.bat` after changes to test | install.bat must be updated: remove ConfigUI.lua copy, add CDMTab.xml and CDMTab.lua |
| New files added to TOC between existing entries | CDMTab.xml and CDMTab.lua added before/after EditModeFrames.lua in TOC |
| Namespace: `local _, ns = ...` shared across files | CDMTab.lua uses this pattern |
| Performance review after commits — check hot-path allocations | CDMTab.lua OnShow/OnHide hooks must not allocate per-frame |

---

## File Audit: ConfigUI.lua (safe to delete)

Reviewing ConfigUI.lua for functionality that must survive:

| Function | Status | Disposition |
|----------|--------|-------------|
| `ns:ToggleConfigUI()` | Slash command target | REPLACED by new /tbt logic in Core.lua |
| `ns:RefreshConfigList()` | Called from ToggleConfigUI and add/remove handlers | DELETED — Phase 4 rebuilds equivalent in CDMTab.lua |
| `CreateConfigFrame()` | Internal | DELETED |
| `CreateListRow()` | Internal | DELETED |
| `configFrame OnShow` — calls `ns:UpdateDisplay()` | Side effect: preview timers via `StartAllPreviewTimers()` | Phase 4 responsibility — D-14 confirms no preview in Phase 3 shell |
| `configFrame OnHide` — calls `ns:ClearAllTimers()`, `ns:UpdateDisplay()` | Side effect: clears preview | Phase 4 responsibility |
| `UISpecialFrames` — `"TerribleBuffTrackerConfig"` | Registered inside `CreateConfigFrame()` | Never called if file removed from TOC; no cleanup needed |
| `ns:SetBuffEnabled()` calls | Called from checkbox handlers | Already in BuffEngine.lua; unaffected |
| `ns:SetBuffDisplayMode()` calls | Called from mode toggle button | Already in BuffEngine.lua; unaffected |
| `ns:RemoveTrackedBuff()` calls | Called from remove button | Already in BuffEngine.lua; unaffected |
| `ns:AddTrackedBuff()` calls | Called from add button | Already in BuffEngine.lua; unaffected |

**Conclusion:** ConfigUI.lua is safe to delete. All called BuffEngine functions stay in BuffEngine.lua. The only integration point requiring a Core.lua change is `ns:ToggleConfigUI()` in the slash handler.

---

## TOC Changes Required

Current TOC order:
```
Core.lua
BuffEngine.lua
EditModeFrames.lua
Display.lua
ConfigUI.lua        ← REMOVE
```

New TOC order:
```
Core.lua
BuffEngine.lua
EditModeFrames.lua
Display.lua
CDMTab.xml          ← ADD (XML before Lua for same module)
CDMTab.lua          ← ADD
```

CDMTab.xml must be listed before CDMTab.lua in the TOC so the frame exists when the Lua loads.

---

## install.bat Changes Required

```bat
REM Remove:
copy /Y "%SOURCE%ConfigUI.lua" "%DEST%\"

REM Add:
copy /Y "%SOURCE%CDMTab.xml" "%DEST%\"
copy /Y "%SOURCE%CDMTab.lua" "%DEST%\"
```

---

## Environment Availability

Step 2.6: SKIPPED — this phase is code/config changes only. No external CLI tools, databases, or services beyond WoW itself are required.

---

## Validation Architecture

`workflow.nyquist_validation` not present in `.planning/config.json` — treating as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | In-game WoW addon testing (no automated test runner) |
| Config file | none |
| Quick run command | `/reload` in WoW, then `/tbt` |
| Full suite command | Manual in-game verification checklist |

WoW addon testing is entirely manual — no unit test framework exists for this project. All verification is in-game.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Verification Steps |
|--------|----------|-----------|-------------------|
| TAB-01 | TBT tab button appears in CDM settings | manual | Open CDM settings; verify "TBT Buffs" tab appears below Auras tab with correct icon and tooltip |
| TAB-01 | Tab checked state updates correctly | manual | Click Spells tab → TBT unchecked; click Auras tab → TBT unchecked; click TBT tab → TBT checked, Spells+Auras unchecked |
| TAB-02 | TBT content panel shown on tab click | manual | Click TBT tab; verify CDM scroll frame hidden and TBT panel visible in same region |
| TAB-02 | CDM content restored when switching away | manual | Click TBT tab then click Spells tab; verify CDM scroll content reappears correctly |
| TAB-07 | /tbt opens CDM settings to TBT tab | manual | Type `/tbt`; verify CDM settings opens with TBT tab selected |
| TAB-07 | /tbt when CDM already open switches tab | manual | Open CDM settings on Spells tab, then `/tbt`; verify TBT tab becomes selected |
| TAB-07 | No Lua errors after ConfigUI removal | manual | `/tbt` generates no Lua errors; no "attempt to call nil value" |
| TAB-07 | Escape key still closes UI panels | manual | Open any panel (e.g. character sheet), press Escape; verify it closes normally |

### Wave 0 Gaps

None — no automated test infrastructure exists for this project. All verification is manual in-game.

---

## Open Questions

1. **`hud-buff` atlas availability in Midnight**
   - What we know: D-02 specifies `hud-buff`; CONTEXT.md notes "Can be changed during in-game verification."
   - What's unclear: Whether `hud-buff` is available and what it looks like in Midnight 12.0.
   - Recommendation: Use it as specified; user will verify in-game and swap if needed. The XML KeyValue is the only change.

2. **Whether `CooldownViewerSettings.CooldownScroll` should be Hidden vs. moved off-screen**
   - What we know: CDM's `RefreshLayout()` calls `self.categoryPool:ReleaseAll()` and re-adds categories. If `CooldownScroll` is hidden while TBT tab is active and `RefreshLayout` fires, no visual corruption occurs — categories are released and rebuilt but the scroll is hidden.
   - What's unclear: Whether CDM fires `RefreshLayout` on any event while the settings window is open (e.g., if the player's spec changes).
   - Recommendation: Use `:Hide()` / `:Show()` on `CooldownViewerSettings.CooldownScroll`. If `RefreshLayout` fires while it's hidden, the scroll content is rebuilt correctly — it's just invisible until restored.

3. **Whether OnShow's SetDisplayMode call conflicts with SelectTBTTab**
   - What we know: `OnShow` calls `SetDisplayMode("spells")` when `self.displayMode` is nil (first open). After first open, `self.displayMode` is set and the early-return prevents re-firing.
   - Recommendation: On subsequent /tbt presses when CDM is already visible, `SetDisplayMode` will not fire (early return). Only on first open is there ordering to manage. Solution: call `SelectTBTTab()` after `ShowUIPanel()` synchronously — Lua is single-threaded so the order is deterministic.

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `UIDropDownMenu` | `MenuUtil.CreateContextMenu` | Deprecated since Dragonflight; CDM uses MenuUtil |
| Standalone config window (`ConfigUI.lua`) | CDM tab panel | This is the migration happening in Phase 3+4 |
| `table.insert(TabButtons, ...)` at runtime | XML `parentArray="TabButtons"` | Runtime approach requires manual handler wiring; XML is cleaner |

---

## Sources

### Primary (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — `SetupTabs()` (line 848), `SetDisplayMode()` (line 1443), `displayModeToCategories` (line 1437), `OnShow` (line 1380), `LoadCooldownSettings` timing (line 821), `ShowUIPanel`/`TogglePanel` methods (lines 1587-1601)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — `CooldownViewerSettingsTabTemplate` definition (line 140), `CooldownScroll` anchors (lines 201-220), `SpellsTab`/`AurasTab` XML structure (lines 158-179)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua` — `SidePanelTabButtonMixin` (lines 295-338): `SetChecked`, `SetCustomOnMouseUpHandler`, `OnEnter`/`OnLeave`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.xml` — `LargeSideTabButtonTemplate` size/structure (lines 981-1011)
- `C:\Users\jonat\Repositories\TerribleBuffTracker\ConfigUI.lua` — Full audit of what's safe to delete; `UISpecialFrames` insertion location (line 45)
- `C:\Users\jonat\Repositories\TerribleBuffTracker\Core.lua` — Current slash command handler (lines 53-57); init order (ADDON_LOADED → PLAYER_ENTERING_WORLD)
- `.planning/research/STACK.md` — Project-level CDM tab research (HIGH confidence, verified from source)
- `.planning/research/ARCHITECTURE.md` — CDMTab.lua new file recommendation, integration map
- `.planning/research/PITFALLS.md` — Pitfall 1 (COOLDOWN_VIEWER_DATA_LOADED), Pitfall 2 (parentArray), Pitfall 3 (assertsafe), Pitfall 10 (ConfigUI removal)

### Secondary (MEDIUM confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_FrameXML\Bindings_Standard.xml:1251` — `CooldownViewerSettings:TogglePanel()` exposed as a keybinding, confirming the method is the canonical external entry point

---

## Metadata

**Confidence breakdown:**
- Tab injection via XML parentArray: HIGH — verified from CooldownViewerSettings.xml:140 and SpellsTab/AurasTab examples
- SetupTabs handler wiring: HIGH — verified from CooldownViewerSettings.lua:848-857
- SetDisplayMode assertsafe risk: HIGH — verified from CooldownViewerSettings.lua:1454-1455
- CooldownScroll geometry: HIGH — verified from CooldownViewerSettings.xml:201-220
- ShowUIPanel method: HIGH — verified from CooldownViewerSettings.lua:1587-1592
- hud-buff atlas availability: LOW — not verified in source; depends on in-game check
- OnShow/SelectTBTTab ordering: MEDIUM — logic derived from source analysis, untested

**Research date:** 2026-03-28
**Valid until:** 2026-06-28 (stable Blizzard UI source; no expected changes until next major patch)
