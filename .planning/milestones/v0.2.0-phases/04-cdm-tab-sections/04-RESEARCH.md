# Phase 4: CDM Tab Sections - Research

**Researched:** 2026-03-29
**Domain:** WoW Midnight addon — CDM settings panel section layout, icon grids, context menus, custom dialog
**Confidence:** HIGH (all findings verified from Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Vertical stack of 4 collapsible sections inside `ns.tbtScrollChild`. Order: Tracked Bars, Tracked Buffs, Not Displayed, Suggested.
- **D-02:** Collapsible headers matching CDM's own section style. Reference `ListHeaderThreeSliceTemplate` or CDM's category headers from Blizzard source.
- **D-03:** Each section header is clickable to collapse/expand its content area.
- **D-04:** Icons only (no label text inline). Spell icons in a flow/grid layout.
- **D-05:** Tooltip on mouseover showing buff name, spell ID, and duration.
- **D-06:** Icon size and spacing match CDM's own cooldown item style.
- **D-07:** Buffs placed in sections based on `entry.section` — "bars" → Tracked Bars, "buffs" → Tracked Buffs, "hidden" → Not Displayed.
- **D-08:** Add button appears in the Suggested section matching CDM visual patterns.
- **D-09:** Clicking Add opens a popup dialog (small modal frame) with two input fields: Spell ID (number) and Duration (seconds). Add and Cancel buttons.
- **D-10:** On Add: calls `ns:AddTrackedBuff(spellID, duration)` → `section="hidden"` → appears in Not Displayed. Dialog closes.
- **D-11:** Validation: reject non-numeric or <= 0 values. Show inline error text in the dialog.
- **D-12:** Not Displayed section shows a visible delete drop zone (visual placeholder). Non-functional in Phase 4.
- **D-13:** Delete zone visual: distinct area (red-tinted or trash icon) so users understand its purpose.
- **D-14:** Right-clicking any buff icon shows a context menu using `MenuUtil.CreateContextMenu`.
- **D-15:** Menu options vary by section:
  - In Tracked Bars: "Move to Buffs", "Hide", "Remove"
  - In Tracked Buffs: "Move to Bars", "Hide", "Remove"
  - In Not Displayed: "Move to Bars", "Move to Buffs", "Remove"
  - In Suggested: no context menu
- **D-16:** "Move to Bars" → `entry.section="bars"`, "Move to Buffs" → `entry.section="buffs"`, "Hide" → `entry.section="hidden"`, "Remove" → `ns:RemoveTrackedBuff(spellID)`.
- **D-17:** After any context menu action, refresh the section display.

### Claude's Discretion

- Exact icon size (check CDM source for cooldown item dimensions)
- Grid vs flow layout implementation details
- Collapse animation (instant hide/show vs smooth transition)
- Delete zone icon/visual treatment
- Dialog frame positioning relative to CDM window

### Deferred Ideas (OUT OF SCOPE)

- Drag-and-drop between sections — Phase 5
- Delete via drag to drop zone — Phase 5
- Real buff suggestions in Suggested section — future milestone
- Edit Mode selection highlighting + per-element config panel — future

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TAB-03 | User sees 4 sections: Tracked Buffs, Tracked Bars, Not Displayed, Suggested | Section construction with `ListHeaderThreeSliceTemplate` + `GridLayoutFrame` container per section documented below |
| TAB-04 | User can add a new buff via Add button in Suggested (prompts Spell ID + Duration) | Custom two-field modal dialog pattern documented; `StaticPopup_ShowCustomGenericInputBox` covers single-field only, two fields require custom frame |
| TAB-05 | Newly added buffs appear in Not Displayed section | `ns:AddTrackedBuff` already defaults `section="hidden"`; refresh after call documented |
| TAB-06 | User can drag a buff onto the delete drop zone in Not Displayed to remove it | NOTE: Per CONTEXT.md D-12, delete zone is visual-only in Phase 4 (non-functional). Drag is Phase 5. TAB-06 is partially addressed here (zone exists) but deletion is deferred. |

</phase_requirements>

---

## Summary

Phase 4 builds on the `ns.tbtPanel` / `ns.tbtScrollChild` frame hierarchy created in Phase 3. All work happens in `CDMTab.lua`. The goal is to construct four vertically stacked collapsible sections inside `ns.tbtScrollChild`, populate them from `ns.db.trackedBuffs`, wire a right-click context menu for section moves/removal, and implement an Add dialog in the Suggested section.

The CDM category pattern is the direct blueprint: `CooldownViewerSettingsCategoryTemplate` is a `ResizeLayoutFrame` with a `ListHeaderThreeSliceTemplate` header button and a `GridLayoutFrame` (named `Container`) child for icons. TBT should mirror this structure exactly, creating the same frame hierarchy manually (not inheriting CDM templates, since those tie into CDM's data pool and category system which TBT cannot use).

The critical constraints for this phase:
1. TBT sections must be standalone frames parented to `ns.tbtScrollChild`, not plugged into CDM's `categoryPool`. CDM's `RefreshLayout()` calls `categoryPool:ReleaseAll()` and would destroy any frames inserted there.
2. The Add dialog requires two numeric inputs (Spell ID + Duration). Blizzard's `GENERIC_INPUT_BOX` static popup only supports one edit box. A custom lightweight modal frame is required.
3. `MenuUtil.CreateContextMenu` is the correct context menu API. The old `UIDropDownMenu` is deprecated and non-functional in Midnight.
4. `ns:SetBuffSection()` does not yet exist in BuffEngine.lua — it must be added in this phase or as a Wave 0 task.

**Primary recommendation:** Build each section as a plain `Frame` + `Button` (header) + `Frame` (container) triplet, mirroring CDM's category structure. Use `CreateFramePool` per section for icon frames. Call `GridLayoutFrame:Layout()` after each pool refresh. Wire section header clicks to toggle `Container:SetShown()`.

---

## Standard Stack

### Core

| Component | Source | Purpose | Why Use It |
|-----------|--------|---------|------------|
| `ListHeaderThreeSliceTemplate` | `Blizzard_SharedXMLGame/Mainline/ListTemplates.xml` | Section header with collapse arrow and title | Exact visual CDM uses for its own category headers; provides `Name` FontString, `Left`/`Middle`/`Right` three-slice textures |
| `GridLayoutFrame` | `Blizzard_SharedXML/LayoutFrame.xml` | Auto-layout icon grid inside each section | CDM's `Container` uses this with `stride=7`, `childXPadding=8`, `childYPadding=8`; handles wrapping and height auto-sizing |
| `ResizeLayoutFrame` | `Blizzard_SharedXML/LayoutFrame.xml` | Auto-height section wrapper | CDM's `CooldownViewerSettingsCategoryTemplate` inherits this; section height adjusts as icons are added/removed |
| `CreateFramePool` | WoW Frame API | Icon frame recycling per section | CDM uses `CreateFramePool("Frame", self.Container, itemTemplate)` with `Acquire()`/`ReleaseAll()` |
| `MenuUtil.CreateContextMenu` | `Blizzard_Menu/MenuUtil.lua` | Right-click context menus on icons | Correct Midnight API; replaces deprecated `UIDropDownMenu`; plays sound automatically on open |

### Supporting

| API | Source | Purpose | When to Use |
|-----|--------|---------|-------------|
| `ListHeaderMixin:SetHeaderText(text)` | `ListTemplates.lua` line 57 | Set header title text | Called in section `OnLoad` with section name string |
| `ListHeaderMixin:SetClickHandler(handler)` | `ListTemplates.lua` line 84 | Register header click callback | Used in CDM's category `OnLoad`: `self.Header:SetClickHandler(function(...) self:ToggleCollapsed() end)` |
| `ListHeaderMixin:UpdateCollapsedState(collapsed)` | `ListTemplates.lua` line 143 | Sync collapse button arrow | Call with `true`/`false` when toggling; `ListHeaderThreeSliceMixin` overrides to swap `Right` atlas |
| `ListHeaderThreeSliceMixin:GetTitleRegion()` | `ListTemplates.lua` line 156 | Returns `self.Name` FontString | Used internally by `SetHeaderText` — title is on `self.Name` for three-slice variant |
| `C_Spell.GetSpellInfo(spellID)` | WoW API | Fetch spell name and icon | Returns `{ name, iconID, ... }` — `iconID` is what `icon:SetTexture(iconID)` expects |
| `GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")` | WoW API | Tooltip anchor for icon hover | Standard pattern; use `GameTooltip:SetText()` or `GameTooltip:AddLine()` for custom content |
| `rootDescription:CreateButton(text, callback)` | `Blizzard_Menu` | Menu item in context menu | Primary API for context menu actions (Move to Bars, Move to Buffs, Hide, Remove) |
| `rootDescription:CreateDivider()` | `Blizzard_Menu` | Separator between menu groups | Optional visual grouping; CDM uses it between alert buttons and category reassignment buttons |

### Not Available / Don't Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `CooldownViewerSettingsCategoryTemplate` (inherit) | Ties into CDM's `categoryPool` and data provider; `RefreshLayout()` would destroy TBT frames | Build equivalent structure manually |
| `UIDropDownMenu` | Deprecated and non-functional in Midnight | `MenuUtil.CreateContextMenu` |
| `StaticPopup_ShowCustomGenericInputBox` for two fields | `GENERIC_INPUT_BOX` dialog only has `hasEditBox = 1` (single field) | Custom modal frame |
| Parenting sections to `CooldownViewerSettings.CooldownScroll.Content` | `categoryPool:ReleaseAll()` in `RefreshLayout()` would clear or orphan TBT frames | Parent to `ns.tbtScrollChild` (already TBT-owned) |

---

## Architecture Patterns

### Section Structure (mirrors CDM category without inheriting its pool)

Each of the four sections is a three-level frame hierarchy:

```
ns.tbtScrollChild
└── sectionFrame  (ResizeLayoutFrame or plain Frame)
    ├── headerBtn  (Button inheriting ListHeaderThreeSliceTemplate)
    └── container  (GridLayoutFrame)
        ├── iconFrame  (from pool, 38x38)
        ├── iconFrame
        └── ...
```

**Construction:**
```lua
-- Source: CooldownViewerSettings.lua:639-650, ListTemplates.lua:57-148
local section = CreateFrame("Frame", nil, ns.tbtScrollChild)
section:SetWidth(300)

local header = CreateFrame("Button", nil, section, "ListHeaderThreeSliceTemplate")
header:SetSize(0, 22)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetClickHandler(function(_hdr, button)
    if button == "LeftButton" then
        section.collapsed = not section.collapsed
        container:SetShown(not section.collapsed)
        header:UpdateCollapsedState(section.collapsed)
    end
end)
header:SetTitleColor(false, NORMAL_FONT_COLOR)
header:SetTitleColor(true,  NORMAL_FONT_COLOR)
header:SetHeaderText("Tracked Bars")
header:UpdateCollapsedState(false)

local container = CreateFrame("Frame", nil, section, "GridLayoutFrame")
container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 13, -8)
container:SetWidth(300)
-- Grid params (match CDM icon category — stride 7, 38x38 icons, 8px padding)
container.childXPadding = 8
container.childYPadding = 8
container.isHorizontal = true
container.stride = 7
container.layoutFramesGoingRight = true
container.layoutFramesGoingUp = false
container.alwaysUpdateLayout = true
```

**Icon dimensions confirmed from source:** `CooldownViewerSettingsItemTemplate` is `38x38` (CooldownViewerSettings.xml line 18). Icon texture fills all points. Highlight texture uses `ButtonHilight-Square` with `ADD` alpha mode.

**Stride calculation:** CDM uses `stride = 7` with icons at 38px + 8px padding = 46px per slot. At 300px container width, 7 icons × 46px = 322px (slightly over, but CDM sets `Container` width to 315px). TBT can use `stride = 6` at 300px width to fit cleanly (6 × 46 = 276px) or match CDM at 7.

### Populating Icons from DB

```lua
-- Source pattern from CooldownViewerSettingsCategoryMixin:RefreshLayout (line 696-719)
local function RefreshSection(section, targetSectionName)
    section.itemPool:ReleaseAll()
    for spellID, entry in pairs(ns.db.trackedBuffs) do
        if entry.section == targetSectionName then
            local item = section.itemPool:Acquire()
            item.spellID = spellID
            item.Icon:SetTexture(ns:GetSpellIcon(spellID))
            item.sectionName = targetSectionName
            item.layoutIndex = spellID  -- stable key for pool
            item:Show()
        end
    end
    section.container:Layout()
    -- ResizeLayoutFrame auto-adjusts section height after Layout()
end
```

### Section Vertical Stacking

CDM stacks categories with `SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT", 0, -18)`. TBT does the same:

```lua
-- Source: CooldownViewerSettingsMixin:AddCategory (line 1472-1486)
local prevSection = nil
for _, sectionDef in ipairs(SECTION_ORDER) do
    local section = BuildSection(sectionDef)
    if prevSection then
        section:SetPoint("TOPLEFT", prevSection, "BOTTOMLEFT", 0, -12)
    else
        section:SetPoint("TOPLEFT", ns.tbtScrollChild, "TOPLEFT", 0, 0)
    end
    prevSection = section
end
```

After all sections are built, `ns.tbtScrollChild` needs its total height set so the scroll frame works. CDM handles this via `ResizeLayoutFrame` auto-sizing. TBT can call `ns.tbtScrollChild:SetHeight(totalHeight)` after layout, or use a `ResizeLayoutFrame` for `tbtScrollChild` itself.

### Right-Click Context Menu

```lua
-- Source: CooldownViewerSettingsItemMixin:DisplayContextMenu (line 462-495)
-- and MenuUtil.CreateContextMenu in Blizzard_Menu/MenuUtil.lua
item:SetScript("OnMouseUp", function(self, button, upInside)
    if button == "RightButton" and upInside then
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            local section = self.sectionName
            if section == "bars" then
                rootDescription:CreateButton("Move to Buffs", function()
                    ns:SetBuffSection(self.spellID, "buffs")
                    ns:RefreshTBTSections()
                end)
                rootDescription:CreateButton("Hide", function()
                    ns:SetBuffSection(self.spellID, "hidden")
                    ns:RefreshTBTSections()
                end)
            elseif section == "buffs" then
                rootDescription:CreateButton("Move to Bars", function()
                    ns:SetBuffSection(self.spellID, "bars")
                    ns:RefreshTBTSections()
                end)
                rootDescription:CreateButton("Hide", function()
                    ns:SetBuffSection(self.spellID, "hidden")
                    ns:RefreshTBTSections()
                end)
            elseif section == "hidden" then
                rootDescription:CreateButton("Move to Bars", function()
                    ns:SetBuffSection(self.spellID, "bars")
                    ns:RefreshTBTSections()
                end)
                rootDescription:CreateButton("Move to Buffs", function()
                    ns:SetBuffSection(self.spellID, "buffs")
                    ns:RefreshTBTSections()
                end)
            end
            rootDescription:CreateDivider()
            rootDescription:CreateButton("Remove", function()
                ns:RemoveTrackedBuff(self.spellID)
                ns:RefreshTBTSections()
            end)
        end)
    end
end)
```

### Add Dialog (Custom Two-Field Modal)

`StaticPopup_ShowCustomGenericInputBox` only supports one `EditBox` (`hasEditBox = 1`). TBT needs Spell ID + Duration: two numeric fields. The correct approach is a custom modal frame created once and shown/hidden.

```lua
-- Custom modal: created once in InitCDMTab, stored as ns.tbtAddDialog
local dialog = CreateFrame("Frame", "TBTAddBuffDialog", CooldownViewerSettings, "ButtonFrameTemplate")
dialog:SetSize(240, 160)
dialog:SetPoint("CENTER", CooldownViewerSettings, "CENTER")
dialog:SetTitle("Add Tracked Buff")
dialog:Hide()

-- Spell ID editbox
local spellIdBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
spellIdBox:SetNumeric(true)
spellIdBox:SetSize(160, 22)
spellIdBox:SetPoint("TOP", dialog.Inset, "TOP", 0, -16)
spellIdBox:SetMaxLetters(10)

-- Duration editbox
local durationBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
durationBox:SetNumeric(true)
durationBox:SetSize(160, 22)
durationBox:SetPoint("TOP", spellIdBox, "BOTTOM", 0, -10)
durationBox:SetMaxLetters(6)

-- Error label
local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontRed")
errorLabel:SetPoint("TOP", durationBox, "BOTTOM", 0, -6)
errorLabel:SetText("")

-- Add button
local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
addBtn:SetSize(80, 22)
addBtn:SetText("Add")
addBtn:SetPoint("BOTTOMLEFT", dialog.Inset, "BOTTOMLEFT", 10, 10)
addBtn:SetScript("OnClick", function()
    local spellID = tonumber(spellIdBox:GetNumber())
    local duration = tonumber(durationBox:GetNumber())
    if not spellID or spellID <= 0 then
        errorLabel:SetText("Invalid Spell ID")
        return
    end
    if not duration or duration <= 0 then
        errorLabel:SetText("Invalid Duration")
        return
    end
    ns:AddTrackedBuff(spellID, duration)
    ns:RefreshTBTSections()
    dialog:Hide()
end)

-- Cancel button
local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
cancelBtn:SetText("Cancel")
cancelBtn:SetSize(80, 22)
cancelBtn:SetPoint("BOTTOMRIGHT", dialog.Inset, "BOTTOMRIGHT", -10, 10)
cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

table.insert(UISpecialFrames, "TBTAddBuffDialog")
ns.tbtAddDialog = dialog
```

**Key detail:** `ButtonFrameTemplate` provides a standard Blizzard panel with `Inset`, title bar, and close button. `InputBoxTemplate` provides a styled numeric-only edit box. `UISpecialFrames` registration ensures Escape closes the dialog.

### Delete Drop Zone

```lua
-- Non-functional visual placeholder (Phase 4). Phase 5 wires drag-drop.
-- Source: CDM "empty category" pattern — CooldownViewerSettingsItemMixin:SetAsEmptyCategory
-- uses Atlas "cdm-empty". TBT uses a distinct visual.
local deleteZone = CreateFrame("Frame", nil, notDisplayedSection.container)
deleteZone:SetSize(38, 38)
-- Parented in the grid so it occupies a slot — Phase 5 makes it respond to drops
local bg = deleteZone:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(deleteZone)
bg:SetColorTexture(0.8, 0.1, 0.1, 0.4)  -- red tint
local trashIcon = deleteZone:CreateTexture(nil, "OVERLAY")
trashIcon:SetAtlas("common-icon-redx")  -- or a trash atlas if available
trashIcon:SetSize(24, 24)
trashIcon:SetPoint("CENTER")
```

**Note:** The delete zone must always occupy a slot in the "Not Displayed" container's grid. It is never in the item pool — it is a permanent frame inside the container. Place it before calling `container:Layout()` so it is laid out consistently.

### Missing BuffEngine API: `ns:SetBuffSection`

BuffEngine.lua currently has `ns:SetBuffDisplayMode` (maps old "buff"/"bar" strings) and `ns:SetBuffEnabled`. It does NOT have `ns:SetBuffSection(spellID, section)` with direct section string support as required by D-16 context menu actions.

**Must add to BuffEngine.lua:**
```lua
function ns:SetBuffSection(spellID, section)
    local entry = ns.db.trackedBuffs[spellID]
    if not entry then return end
    entry.section = section
    -- Sync active timer section if running
    if ns.activeTimers[spellID] then
        ns.activeTimers[spellID].section = section
    end
    -- If hiding, clear active timer
    if section == "hidden" then
        ns.activeTimers[spellID] = nil
    end
    if ns.UpdateDisplay then
        ns:UpdateDisplay()
    end
end
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Header collapse arrow + three-slice bar | Custom textures and font strings | `ListHeaderThreeSliceTemplate` | Exact match to CDM visual; handles highlight, atlas swap on collapse, text color |
| Icon grid flow layout | Manual `SetPoint` per icon on each refresh | `GridLayoutFrame` with `alwaysUpdateLayout=true` | Handles stride, wrapping, padding automatically; auto-sizes parent when combined with `ResizeLayoutFrame` |
| Icon frame recycling | Table of manually created frames | `CreateFramePool` per section | Pool acquire/release prevents frame leak; CDM's proven pattern |
| Right-click menu | Custom dropdown frame | `MenuUtil.CreateContextMenu` | Native Midnight API; handles positioning, focus, ESC close, sound |

---

## Common Pitfalls

### Pitfall 1: Section frames destroyed by CDM RefreshLayout
**What goes wrong:** Parenting TBT sections to `CooldownViewerSettings.CooldownScroll.Content` causes them to be destroyed by `categoryPool:ReleaseAll()` when CDM switches tabs.
**Why it happens:** CDM's category pool owns all children of `CooldownScroll.Content`. `ReleaseAll()` recycles every active frame.
**How to avoid:** Always parent TBT sections to `ns.tbtScrollChild`, which is a child of `ns.tbtPanel` — a TBT-owned frame, not part of CDM's pool.
**Warning signs:** Sections disappear after clicking Spells or Auras tab and back.

### Pitfall 2: GridLayoutFrame doesn't auto-size without Layout() call
**What goes wrong:** Icons appear stacked at position 0,0 or the container height stays at 0.
**Why it happens:** `GridLayoutFrame` only updates child positions when `Layout()` is explicitly called (or when `alwaysUpdateLayout=true` and a child's visibility changes).
**How to avoid:** Call `container:Layout()` after every pool `Acquire()` batch. Set `alwaysUpdateLayout = true` on the container so show/hide of children auto-triggers layout.
**Warning signs:** All icons overlap at top-left of container; section height does not expand.

### Pitfall 3: `ListHeaderThreeSliceTemplate` requires `ListHeaderMixin` for API calls
**What goes wrong:** Calling `header:SetHeaderText()` fails because `ListHeaderThreeSliceTemplate` inherits `ListHeaderCodeTemplate` (which has `ListHeaderMixin`) but NOT `ListHeaderVisualMixin` directly — `ListHeaderThreeSliceMixin` provides `SetHeaderText` via mixin.
**Why it happens:** The mixin chain is: `ListHeaderThreeSliceTemplate` → `ListHeaderCodeTemplate` (mixin=`ListHeaderMixin`) + `ListHeaderThreeSliceMixin`. `ListHeaderThreeSliceMixin` inherits `ListHeaderVisualMixin`, so `SetHeaderText` resolves correctly.
**How to avoid:** Always create headers as `CreateFrame("Button", nil, section, "ListHeaderThreeSliceTemplate")`. Do not create plain Button frames and try to call these methods.
**Warning signs:** Lua error "attempt to call nil value (method 'SetHeaderText')".

### Pitfall 4: SetNumeric EditBox returns integer only
**What goes wrong:** Duration edit box rejects decimals — user can't enter 1.5s.
**Why it happens:** `editBox:SetNumeric(true)` constrains input to integers only.
**How to avoid:** For duration, either accept integers only (simplest — document "seconds as whole number"), or use a plain text EditBox and call `tonumber()` on the text string, then validate >= 0.
**Warning signs:** User types "30.5" and it becomes "305" or rejects input.

### Pitfall 5: tbtScrollChild height must be set manually
**What goes wrong:** Scroll frame shows no scroll bar even when sections overflow; all sections visible but outside the viewport.
**Why it happens:** `ns.tbtScrollChild:SetHeight(1)` is the initial value from Phase 3. Scroll frame height is determined by the scroll child height minus the scroll frame height. If scroll child stays at height 1, no scrolling occurs.
**How to avoid:** After all sections are laid out, calculate total content height and call `ns.tbtScrollChild:SetHeight(totalHeight)`. Or use `ResizeLayoutFrame` for `tbtScrollChild` itself so it auto-sizes.
**Warning signs:** Tall section list appears clipped; no scroll bar appears.

### Pitfall 6: Phase 3 CRITICAL LESSON — never touch TabButtons array or call SetDisplayMode
**What goes wrong:** Calling `CooldownViewerSettings:SetDisplayMode("tbt_buffs")` triggers `assertsafe` on the `displayModeToCategories` local table, crashing CDM.
**Why it happens:** `displayModeToCategories` is file-local in CooldownViewerSettings.lua and only has "spells" and "auras" keys.
**How to avoid:** CDMTab.lua already handles this correctly — `ShowTBTPanel()` never calls `SetDisplayMode`. The `hooksecurefunc` on `SetDisplayMode` only triggers when CDM calls it for its own tabs.
**Warning signs:** Lua error "Add missing category data for displayMode".

---

## Code Examples

### Full section construction (verified against CDM source pattern)

```lua
-- Source: CooldownViewerSettings.lua:639-718 (category OnLoad + RefreshLayout)
-- Source: ListTemplates.lua:70-163 (ListHeaderMixin, ListHeaderThreeSliceMixin)
-- Source: CooldownViewerSettings.xml:100-134 (CooldownViewerSettingsCategoryTemplate)
local function BuildTBTSection(parent, title)
    local section = {}

    section.frame = CreateFrame("Frame", nil, parent)
    section.frame:SetWidth(300)

    section.header = CreateFrame("Button", nil, section.frame, "ListHeaderThreeSliceTemplate")
    section.header:SetSize(0, 22)
    section.header:SetPoint("TOPLEFT", section.frame, "TOPLEFT")
    section.header:SetPoint("TOPRIGHT", section.frame, "TOPRIGHT")
    section.header:SetTitleColor(false, NORMAL_FONT_COLOR)
    section.header:SetTitleColor(true,  NORMAL_FONT_COLOR)
    section.header:SetHeaderText(title)
    section.header:UpdateCollapsedState(false)
    section.header:SetClickHandler(function(_hdr, button)
        if button == "LeftButton" then
            section.collapsed = not section.collapsed
            section.container:SetShown(not section.collapsed)
            section.header:UpdateCollapsedState(section.collapsed)
            section.frame:SetHeight(section.collapsed and 22 or section.header:GetHeight() + section.container:GetHeight() + 23)
        end
    end)

    section.container = CreateFrame("Frame", nil, section.frame, "GridLayoutFrame")
    section.container:SetPoint("TOPLEFT", section.header, "BOTTOMLEFT", 13, -8)
    section.container:SetWidth(276)  -- 6 icons × 46px = 276px
    section.container:SetHeight(54)  -- initial: one row of 38px + 8px padding
    section.container.childXPadding   = 8
    section.container.childYPadding   = 8
    section.container.isHorizontal    = true
    section.container.stride          = 6
    section.container.layoutFramesGoingRight = true
    section.container.layoutFramesGoingUp    = false
    section.container.alwaysUpdateLayout     = true

    section.itemPool = CreateFramePool("Frame", section.container, "TBTBuffIconTemplate")
    -- TBTBuffIconTemplate defined in CDMTab.xml (or created inline if no XML)

    return section
end
```

### Icon frame setup (inline, no XML)

```lua
-- Source: CooldownViewerSettings.xml:17-33 (CooldownViewerSettingsItemTemplate)
local function CreateIconFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(38, 38)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    f.Icon = icon

    local highlight = f:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(f)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local entry = ns.db.trackedBuffs[self.spellID]
        if entry then
            GameTooltip:SetText(entry.label, 1, 1, 1)
            GameTooltip:AddLine("Spell ID: " .. self.spellID, 1, 0.8, 0)
            GameTooltip:AddLine("Duration: " .. entry.duration .. "s", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return f
end
```

### MenuUtil.CreateContextMenu (verified from source)

```lua
-- Source: Blizzard_Menu/MenuUtil.lua:153-168
-- Source: CooldownViewerSettings.lua:462-495 (DisplayContextMenu)
f:SetScript("OnMouseUp", function(self, button, upInside)
    if button == "RightButton" and upInside then
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            -- Buttons vary by section (D-15)
            if self.sectionName == "bars" then
                rootDescription:CreateButton("Move to Buffs", function()
                    ns:SetBuffSection(self.spellID, "buffs")
                    ns:RefreshTBTSections()
                    ns:UpdateDisplay()
                end)
                rootDescription:CreateButton("Hide", function()
                    ns:SetBuffSection(self.spellID, "hidden")
                    ns:RefreshTBTSections()
                    ns:UpdateDisplay()
                end)
            -- ... other section cases
            end
            rootDescription:CreateDivider()
            rootDescription:CreateButton("Remove", function()
                ns:RemoveTrackedBuff(self.spellID)
                ns:RefreshTBTSections()
            end)
        end)
    end
end)
```

---

## State of the Art

| Old Approach | Current Approach | Relevant Here |
|--------------|------------------|---------------|
| `UIDropDownMenu` | `MenuUtil.CreateContextMenu` | Use CreateContextMenu for all right-click menus |
| `StaticPopup` with `hasEditBox` | Still works for single-field; two-field requires custom frame | Add dialog needs custom frame |
| Manual icon positioning in `OnUpdate` | `GridLayoutFrame` with `alwaysUpdateLayout` | Use GridLayoutFrame for icon grids |

---

## Open Questions

1. **Scroll child auto-height**
   - What we know: `ns.tbtScrollChild` starts at `SetHeight(1)` from Phase 3. Sections are added dynamically.
   - What's unclear: Best strategy — manually sum section heights and call `SetHeight()` after layout, or wrap `tbtScrollChild` in a `ResizeLayoutFrame`.
   - Recommendation: Manually track a `prevSection` pointer and calculate total height after building all sections, then call `ns.tbtScrollChild:SetHeight(totalHeight)`. This is explicit and predictable. Avoid `ResizeLayoutFrame` on the scroll child itself as its interaction with `ScrollFrameTemplate` scroll range calculation is not well-documented.

2. **`ns:SetBuffSection` missing from BuffEngine.lua**
   - What we know: `ns:SetBuffDisplayMode` exists but uses old "buff"/"bar" string mapping. Context menu actions need direct section string ("bars"/"buffs"/"hidden").
   - What's unclear: Whether to add `SetBuffSection` or repurpose `SetBuffDisplayMode`.
   - Recommendation: Add `ns:SetBuffSection(spellID, section)` as a new function. Keep `SetBuffDisplayMode` as-is for backward compat. `SetBuffSection` should also clear `ns.activeTimers[spellID]` when section is "hidden".

3. **`GetNumber()` vs `GetText()` for duration input**
   - What we know: `editBox:SetNumeric(true)` constrains to integers. `editBox:GetNumber()` returns integer.
   - What's unclear: Whether sub-second durations are needed.
   - Recommendation: Use integer seconds for Phase 4. `SetNumeric(true)` + `GetNumber()` is simplest and avoids validation complexity.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is a code-only change to `CDMTab.lua` and `BuffEngine.lua`. No external tools, services, or CLIs are required beyond the existing WoW installation and `stylua`.

---

## Validation Architecture

> `workflow.nyquist_validation` is absent from `.planning/config.json` — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual in-game testing (no automated test runner for WoW Lua addons) |
| Config file | None |
| Quick run command | `./scripts/install.bat` then `/tbt` in-game |
| Full suite command | Manual verification of all 4 sections, context menu, add dialog, scroll behavior |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TAB-03 | 4 sections visible with headers and icons | manual smoke | `./scripts/install.bat` | N/A |
| TAB-04 | Add button opens two-field dialog; spell appears after Add | manual smoke | `./scripts/install.bat` | N/A |
| TAB-05 | Newly added buff appears in Not Displayed section | manual smoke | `./scripts/install.bat` | N/A |
| TAB-06 | Delete zone visible in Not Displayed section | manual smoke (visual only) | `./scripts/install.bat` | N/A |

### Wave 0 Gaps

- [ ] `ns:SetBuffSection(spellID, section)` must be added to `BuffEngine.lua` before any section refresh can work
- [ ] `ns:RefreshTBTSections()` function must be defined in `CDMTab.lua` (the main refresh entry point called by context menu actions and after AddTrackedBuff)

*(No automated test framework exists for WoW addon Lua; all validation is manual in-game.)*

---

## Sources

### Primary (HIGH confidence)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — `CooldownViewerSettingsCategoryTemplate` (ResizeLayoutFrame + ListHeaderThreeSliceTemplate + GridLayoutFrame), `CooldownViewerSettingsItemTemplate` (38x38 icon frame with Highlight texture), `CooldownViewerSettingsDraggedItemTemplate`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — `CooldownViewerSettingsCategoryMixin:OnLoad` (pool creation, header click handler, SetupGridLayoutParams), `RefreshLayout` (pool ReleaseAll + Acquire pattern), `DisplayContextMenu` (`MenuUtil.CreateContextMenu` usage), `SetDisplayMode` (`assertsafe` on unknown modes — confirms TBT must never call it)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXMLGame\Mainline\ListTemplates.xml` — `ListHeaderThreeSliceTemplate` frame definition: three-slice textures (Options_ListExpand_Left/Middle/Right), Name FontString, collapse arrow via Right atlas swap
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXMLGame\Mainline\ListTemplates.lua` — `ListHeaderMixin:SetHeaderText`, `SetClickHandler`, `UpdateCollapsedState`; `ListHeaderThreeSliceMixin:UpdateCollapsedState` (swaps Right atlas)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_Menu\MenuUtil.lua` — `MenuUtil.CreateContextMenu(ownerRegion, generator)` signature; plays sound automatically; takes `rootDescription:CreateButton(text, callback)` calls
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_StaticPopup_Game\GameDialogDefs.lua` — `GENERIC_INPUT_BOX` definition: `hasEditBox = 1` (single field only); confirms two-field dialog needs custom frame

### Secondary (verified against source)

- `TerribleBuffTracker\CDMTab.lua` — Phase 3 implementation confirming `ns.tbtPanel`, `ns.tbtScrollChild`, `ShowTBTPanel`/`HideTBTPanel`, the hooksecurefunc guard, and the `C_Timer.After` pattern for tab selection
- `TerribleBuffTracker\BuffEngine.lua` — Confirms `ns:AddTrackedBuff` defaults `section="hidden"`, `ns:RemoveTrackedBuff` exists, `ns:GetSpellIcon` exists; confirms `ns:SetBuffSection` is NOT yet present

---

## Metadata

**Confidence breakdown:**
- Section structure (ListHeaderThreeSliceTemplate + GridLayoutFrame): HIGH — directly sourced from CDM XML and Lua
- Context menu (MenuUtil.CreateContextMenu): HIGH — sourced from MenuUtil.lua and CDM usage
- Add dialog (custom two-field frame): HIGH — confirmed GENERIC_INPUT_BOX is single-field; ButtonFrameTemplate + InputBoxTemplate is standard WoW addon practice
- `ns:SetBuffSection` gap: HIGH — read BuffEngine.lua directly; function is absent

**Research date:** 2026-03-29
**Valid until:** 2026-06-29 (stable Blizzard source; low churn risk)
