# Architecture Research

**Domain:** WoW addon — CDM tab integration, Edit Mode movable elements, drag-and-drop buff management
**Researched:** 2026-03-28
**Confidence:** HIGH (sourced directly from Blizzard UI source at C:\Users\jonat\Repositories\wow-ui-source)

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Blizzard Frames (read-only)                   │
│  CooldownViewerSettings (global frame)  EditModeManagerFrame         │
│  TabButtons (parentArray)               registeredSystemFrames []    │
│  CooldownScroll.Content                 EventRegistry                │
└──────────────┬──────────────────────────────────┬───────────────────┘
               │ hooksecurefunc / inject tab       │ EventRegistry callbacks
┌──────────────▼──────────────────────────────────▼───────────────────┐
│                    TerribleBuffTracker (our addon)                    │
├─────────────┬──────────────┬──────────────────┬─────────────────────┤
│  Core.lua   │ BuffEngine   │  Display.lua      │  NEW FILES          │
│  events /   │  timer CRUD  │  bar+icon render  │  CDMTab.lua         │
│  slash cmd  │  db writes   │  CDM hooks        │  EditModeFrames.lua │
│             │              │  SnapshotSettings │  (ConfigUI.lua OUT) │
└─────────────┴──────────────┴──────────────────┴─────────────────────┘
                                        │
                          ┌─────────────▼──────────────┐
                          │    TerribleBuffTrackerDB     │
                          │  trackedBuffs[spellID]       │
                          │  editModePositions (new)     │
                          └────────────────────────────-┘
```

### Component Responsibilities

| Component | Responsibility | Notes |
|-----------|----------------|-------|
| `Core.lua` | Namespace init, event router, slash commands, DB init | Gains `editModePositions` DB init; no other changes |
| `BuffEngine.lua` | Timer CRUD, `trackedBuffs` DB writes, display mode/enabled flags | Gains `section` field on entries; migration backfill needed |
| `Display.lua` | Bar/icon rendering, CDM anchor hooks, SnapshotSettings | Gains Edit Mode position awareness; CDM-anchored parents replaced by free-floating containers when Edit Mode positions exist |
| `ConfigUI.lua` | Standalone config window | REPLACED by `CDMTab.lua`; file can be deleted or kept as dead code until confirmed safe |
| `CDMTab.lua` (NEW) | CDM settings tab injection, 4-section drag-and-drop buff manager | Core of the milestone |
| `EditModeFrames.lua` (NEW) | Two independently movable Edit Mode containers (bars, buffs) | Owns position persistence in `TerribleBuffTrackerDB.editModePositions` |

---

## Recommended Project Structure

```
TerribleBuffTracker/
├── Core.lua            -- namespace, DB init (add editModePositions), events, slash
├── BuffEngine.lua      -- timer engine (add section field, migration backfill)
├── Display.lua         -- rendering (position source: Edit Mode frames when set)
├── CDMTab.lua          -- NEW: CDM settings tab + 4-section drag-drop UI
├── EditModeFrames.lua  -- NEW: two movable Edit Mode registered frames
└── TerribleBuffTracker.toc  -- add CDMTab.lua, EditModeFrames.lua entries
```

### Structure Rationale

- **CDMTab.lua** is isolated because CDM tab injection is complex UI wiring that would bloat `ConfigUI.lua`; separating it keeps `Display.lua` clean.
- **EditModeFrames.lua** is isolated because Edit Mode frame registration (`EditModeManagerFrame:RegisterSystemFrame`) must happen at the frame level, separate from display logic. Mixing it into `Display.lua` would create circular dependencies between positioning source and rendering.
- **ConfigUI.lua** should be removed entirely — the CDM tab replaces it. Keeping dead code risks confusion about which path handles `ToggleConfigUI()`.

---

## Architectural Patterns

### Pattern 1: CDM Tab Injection via `parentArray`

**What:** `CooldownViewerSettings.xml` declares tab buttons using `parentArray="TabButtons"`. The frame iterates `self.TabButtons` in `SetupTabs()` and `SetDisplayMode()`. Adding a tab means creating a frame that inherits `CooldownViewerSettingsTabTemplate` (which inherits `LargeSideTabButtonTemplate`) and inserting it into `CooldownViewerSettings.TabButtons`.

**When to use:** Adding a new display mode tab to the CDM settings window.

**Trade-offs:** Requires the tab's `displayMode` key to be handled in `SetDisplayMode()`. Since TBT cannot modify `displayModeToCategories` (read-only Blizzard code), TBT's tab needs its own `OnMouseUp` handler that bypasses the standard category routing and instead shows/hides TBT's own content panel.

**Pattern:**
```lua
-- In CDMTab.lua, after ADDON_LOADED when CooldownViewerSettings exists:
local tbtTab = CreateFrame("Frame", "TBTSettingsTab", CooldownViewerSettings,
    "CooldownViewerSettingsTabTemplate")
tbtTab.displayMode = "tbt_buffs"
tbtTab.activeAtlas = "tbt_icon_64x64"      -- or a CDM atlas
tbtTab.inactiveAtlas = "tbt_icon_64x64"
tbtTab.tooltipText = "TBT Buffs"
-- Anchor below the last existing tab (AurasTab)
tbtTab:SetPoint("TOP", CooldownViewerSettings.AurasTab, "BOTTOM", 0, -3)
-- Insert into TabButtons so SetDisplayMode iterates it for SetChecked
table.insert(CooldownViewerSettings.TabButtons, tbtTab)

-- Override tab click to show TBT panel instead of standard category layout
tbtTab:SetCustomOnMouseUpHandler(function(tab, button, upInside)
    if button == "LeftButton" and upInside then
        ns:ShowTBTSettingsPanel()
        -- Force SetDisplayMode to de-select other tabs
        for _, t in ipairs(CooldownViewerSettings.TabButtons) do
            t:SetChecked(t == tab)
        end
    end
end)
```

**Key constraint:** `SetDisplayMode()` calls `assertsafe` on unknown display modes. TBT must intercept before `SetDisplayMode` is called, or hook `SetDisplayMode` to no-op for `"tbt_buffs"`. The safest approach is to not call `CooldownViewerSettings:SetDisplayMode("tbt_buffs")` at all — only toggle the tab's checked state and show/hide the TBT content panel directly.

---

### Pattern 2: TBT Content Panel Replacing CDM's ScrollFrame

**What:** When the TBT tab is selected, hide `CooldownViewerSettings.CooldownScroll` and show a TBT-owned frame that is a child of `CooldownViewerSettings` (or `CooldownViewerSettings.Inset`). When other tabs are selected, restore the scroll frame.

**When to use:** TBT needs full control over its own layout (4 sections, drag-drop) without conflicting with CDM's category pool.

**Trade-offs:** Must hook `CooldownViewerSettings:SetDisplayMode` to detect when the user switches away from TBT's tab, which is when to hide the TBT panel and restore `CooldownScroll`.

```lua
-- Hook SetDisplayMode to restore CDM scroll when leaving TBT tab
hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", function(self, mode)
    if mode ~= "tbt_buffs" then
        ns:HideTBTSettingsPanel()
    end
end)
```

---

### Pattern 3: Drag-and-Drop via `registerForDrag` + `GLOBAL_MOUSE_UP`

**What:** Blizzard's CDM settings drag works by: (1) `RegisterForDrag("LeftButton")` on item frames, (2) `OnDragStart` fires `BeginOrderChange` which sets up a cursor proxy frame and registers `GLOBAL_MOUSE_UP`, (3) `GLOBAL_MOUSE_UP` event calls `EndOrderChange` which writes the new category.

TBT's drag model is simpler: dragging a buff icon between 4 sections (Tracked Buffs → Tracked Bars → Not Displayed → Suggested). The target section is the drop zone.

**When to use:** Moving buffs between sections in the TBT tab.

**Pattern:**
```lua
-- Buff item frame
item:RegisterForDrag("LeftButton")
item:SetScript("OnDragStart", function(self)
    ns:BeginBuffDrag(self.spellID)
end)

-- Each section acts as a drop zone — OnEnter/OnLeave highlight, GLOBAL_MOUSE_UP commits
local dropFrame  -- created once, parented to UIParent at TOOLTIP strata
local function BeginBuffDrag(self, spellID)
    ns.dragSpellID = spellID
    dropFrame:SetToCursor(spellID)
    dropFrame:Show()
    -- use EventRegistry or CreateFrame with GLOBAL_MOUSE_UP registration
end
```

**Key difference from CDM:** TBT does not need order-within-section sorting; only section membership matters (`trackedBuffs[id].section`). This is dramatically simpler than CDM's full reorder system.

---

### Pattern 4: Edit Mode Movable Frames (Simplified Registration)

**What:** `EditModeSystemMixin` is designed for frames that are part of Blizzard's layout system (`self.system` must match an `Enum.EditModeSystem` value, and `EditModeManagerFrame:RegisterSystemFrame` adds them to the registered list). Third-party addons cannot use `EditModeSystemMixin` directly because it requires a valid `Enum.EditModeSystem` entry, which only Blizzard can define.

**Verified constraint (HIGH confidence):** `EditModeSystemMixin:OnSystemLoad()` calls `EditModeManagerFrame:RegisterSystemFrame(self)`. The manager's `EnterEditMode()` then calls `OnEditModeEnter()` on each registered frame. Without a valid `Enum.EditModeSystem` value, the frame silently fails initialization.

**What to do instead:** TBT implements its own lightweight "edit mode" toggle by listening to `EventRegistry` for `EditMode.Enter` and `EditMode.Exit` callbacks (already used in `Display.lua` for `SnapshotSettings`). TBT shows a movable drag handle on its containers when Edit Mode is active, and saves the resulting position to `TerribleBuffTrackerDB.editModePositions`.

```lua
-- In EditModeFrames.lua
EventRegistry:RegisterCallback("EditMode.Enter", function()
    ns:ShowEditModeHandles()
end, ns)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    ns:HideEditModeHandles()
    ns:SaveEditModePositions()
end, ns)
```

**Position persistence:**
```lua
-- DB structure added in Core.lua
if not ns.db.editModePositions then
    ns.db.editModePositions = {}
end
-- { bars = { point, relativeTo, relativePoint, x, y },
--   icons = { point, relativeTo, relativePoint, x, y } }
```

**Trade-off:** TBT's Edit Mode handles are not part of Blizzard's snap grid or snap-to-frame system. This is acceptable — the existing CDM integration already treats TBT as a peer, not a registered system.

---

### Pattern 5: CDM Settings Copy on Fresh Install

**What:** On first load (when `editModePositions` is nil), read CDM bar/icon viewer positions via `barViewer:GetPoint()` and write them into `editModePositions`. Thereafter, TBT uses its own saved positions and ignores CDM's anchor.

**When to use:** Fresh install initialization only.

```lua
-- In EditModeFrames.lua, called from InitDisplay when editModePositions is nil
local function CopyInitialCDMPositions()
    local v = ns.cdmBarViewer
    if v then
        local point, rel, relPoint, x, y = v:GetPoint(1)
        ns.db.editModePositions.bars = {
            point = point, relativeTo = rel and rel:GetName() or "UIParent",
            relativePoint = relPoint, x = x, y = y
        }
    end
    -- same for cdmIconViewer
end
```

---

## Data Flow

### Buff Section Change (Drag-and-Drop)

```
User drags buff icon
    ↓
CDMTab.lua: BeginBuffDrag(spellID)
    → show cursor proxy frame
    → register GLOBAL_MOUSE_UP
    ↓
User drops on section
    ↓
CDMTab.lua: EndBuffDrag(targetSection)
    → ns:SetBuffSection(spellID, section)   [BuffEngine.lua]
    → BuffEngine writes trackedBuffs[id].section
    → calls ns:UpdateDisplay()              [Display.lua]
    → calls ns:RefreshTBTTab()             [CDMTab.lua]
```

### Edit Mode Position Save

```
User opens Edit Mode
    ↓
EventRegistry "EditMode.Enter"
    → EditModeFrames.lua shows drag handles on barContainer + iconContainer
    ↓
User drags container
    ↓
OnDragStop fires
    → frame position captured (but not yet saved)
    ↓
EventRegistry "EditMode.Exit"
    → EditModeFrames.lua: SaveEditModePositions()
    → writes barContainer:GetPoint() into TerribleBuffTrackerDB.editModePositions
    → Display.lua: SnapshotSettings() (already hooked)
    → ns:UpdateDisplay()
```

### Data Model Change (DB Schema for v0.2.0)

```lua
-- Existing (v0.1)
trackedBuffs[spellID] = {
    spellID, duration, label, enabled, displayMode  -- "bar" or "buff"
}

-- v0.2.0 migration:
-- "displayMode" values map to sections:
--   "bar"  -> section = "bars"
--   "buff" -> section = "buffs"
--   enabled == false -> section = "hidden"
-- New entries added via CDM tab -> section = "hidden" initially

trackedBuffs[spellID] = {
    spellID, duration, label, enabled, displayMode, section
    -- section: "bars" | "buffs" | "hidden"
}

editModePositions = {
    bars  = { point, relativeTo, relativePoint, x, y } | nil,
    icons = { point, relativeTo, relativePoint, x, y } | nil,
}
```

**Migration backfill in BuffEngine.lua:**
```lua
-- Existing migration block (already has enabled/displayMode backfill)
-- Add section backfill:
if not entry.section then
    if entry.enabled == false then
        entry.section = "hidden"
    elseif entry.displayMode == "buff" then
        entry.section = "buffs"
    else
        entry.section = "bars"
    end
end
```

---

## Component Integration Map: New vs. Modified

| File | Status | What Changes |
|------|--------|--------------|
| `Core.lua` | MODIFIED | Add `editModePositions` DB init; wire `InitCDMTab()` and `InitEditModeFrames()` calls after `InitDisplay()` |
| `BuffEngine.lua` | MODIFIED | Add `section` field; migration backfill; update `AddTrackedBuff` to set `section = "hidden"`; add `SetBuffSection(spellID, section)` |
| `Display.lua` | MODIFIED | Use `editModePositions` for container anchoring when set (fallback to CDM anchor if nil); respond to Edit Mode enter/exit for container re-anchor |
| `ConfigUI.lua` | DELETED | Replaced entirely by `CDMTab.lua`; `ns:ToggleConfigUI()` in slash command re-pointed to `ShowCooldownViewerSettings()` |
| `CDMTab.lua` | NEW | CDM tab button injection; TBT content panel with 4 sections; drag-and-drop between sections; Add button (Suggested → Not Displayed flow) |
| `EditModeFrames.lua` | NEW | Edit Mode enter/exit hooks; movable drag handles for barContainer and iconContainer; position save/restore |
| `TerribleBuffTracker.toc` | MODIFIED | Add `CDMTab.lua` and `EditModeFrames.lua` before `ConfigUI.lua` removal |

---

## Build Order (Dependency-Driven)

### Phase 1: Data Model + Migration

**Files:** `BuffEngine.lua`

Backfill `section` field in existing migration block. Add `SetBuffSection()`. Update `AddTrackedBuff()` to default `section = "hidden"`. This is the data foundation everything else depends on.

**Why first:** CDM tab and Edit Mode both read/write `section`. Nothing can be tested without it.

---

### Phase 2: Edit Mode Frames

**Files:** `EditModeFrames.lua`, `Core.lua` (init call), `Display.lua` (position source)

Create the two movable containers with drag handles. Wire `EditMode.Enter` / `EditMode.Exit` via EventRegistry. Implement `SaveEditModePositions()` and `ApplyEditModePositions()`. Modify `Display.lua` to use saved positions when available. Implement CDM settings copy on fresh install.

**Why second:** Display.lua's container anchoring needs to be stable before the CDM tab can show preview content. Edit Mode frames are also lower-risk (no Blizzard UI injection).

---

### Phase 3: CDM Tab Shell

**Files:** `CDMTab.lua`, `Core.lua` (init call)

Create the tab button (inherits `CooldownViewerSettingsTabTemplate`), inject into `CooldownViewerSettings.TabButtons`, anchor below `AurasTab`. Hook `SetDisplayMode` to hide TBT panel on tab switch. Create the TBT content panel frame parented to `CooldownViewerSettings`.

**Why third:** Tab injection is the riskiest integration step. Isolating it lets us verify the tab appears and switches correctly before adding drag-drop content.

---

### Phase 4: CDM Tab Sections + Static Layout

**Files:** `CDMTab.lua`

Build the 4 sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) as static scroll content. Populate from `trackedBuffs`. Add the Add button in Suggested section (spell ID + duration prompt → `AddTrackedBuff` → refresh). Add the delete drop zone in Not Displayed. No drag yet — items are just displayed.

**Why fourth:** Validates data model reads correctly before adding drag complexity.

---

### Phase 5: Drag-and-Drop Between Sections

**Files:** `CDMTab.lua`

Wire `RegisterForDrag("LeftButton")` on buff items. Implement cursor proxy frame (similar to `CooldownViewerSettingsDraggedItemTemplate`). Register `GLOBAL_MOUSE_UP`. On drop into a section, call `ns:SetBuffSection(spellID, newSection)` then refresh the tab. On drop into delete zone, call `ns:RemoveTrackedBuff(spellID)`.

**Why last:** Most complex piece; depends on all section UI being stable.

---

### Phase 6: Cleanup

**Files:** `ConfigUI.lua` (delete), `Core.lua` (update slash command), `TerribleBuffTracker.toc`

Remove `ConfigUI.lua`. Update `ToggleConfigUI()` to open `CooldownViewerSettings`. Remove TOC entry. Run stylua on all modified files.

---

## Anti-Patterns

### Anti-Pattern 1: Calling `CooldownViewerSettings:SetDisplayMode("tbt_buffs")`

**What people do:** Register TBT's display mode string and call `SetDisplayMode` to switch to it.

**Why it's wrong:** `SetDisplayMode` calls `assertsafe` on the `displayModeToCategories` lookup. An unknown mode triggers a Lua error in the Blizzard UI. Since `displayModeToCategories` is a local table in `CooldownViewerSettings.lua`, it cannot be modified by third-party addons.

**Do this instead:** Never call `SetDisplayMode` for TBT's tab. Manage tab checked states manually via `SetChecked`, and hook `SetDisplayMode` to detect when other tabs are activated.

---

### Anti-Pattern 2: Using `EditModeSystemMixin` Directly

**What people do:** Create a frame that mixes in `EditModeSystemMixin` to get full Edit Mode integration (snap grid, settings dialog, key movement).

**Why it's wrong:** `OnSystemLoad()` requires `self.system` to be a valid `Enum.EditModeSystem` value. This enum is defined by Blizzard and not extensible by addons. The frame will fail to register with `EditModeManagerFrame`, leaving it effectively non-functional as an Edit Mode system.

**Do this instead:** Listen to `EventRegistry` callbacks for `EditMode.Enter` and `EditMode.Exit`. Show custom movable drag handles during Edit Mode. Save positions to `TerribleBuffTrackerDB` on `EditMode.Exit`.

---

### Anti-Pattern 3: Parenting TBT Content to `CooldownViewerSettings.CooldownScroll.Content`

**What people do:** Parent TBT's buff list directly into CDM's existing scroll frame content, using category pool APIs.

**Why it's wrong:** CDM's `RefreshLayout()` calls `self.categoryPool:ReleaseAll()` whenever the display mode changes. Any frames parented to `CooldownScroll.Content` that aren't in the pool will have their anchor points cleared or left dangling. The pool also uses two separate pool entries for different category templates — TBT's entries would not be managed.

**Do this instead:** Create a TBT-owned frame parented to `CooldownViewerSettings` (not its scroll frame). Show/hide this frame when switching tabs. Use an independent scroll frame inside it.

---

### Anti-Pattern 4: Reading CDM Viewer Properties Per-Frame

**What people do:** Read `ns.cdmBarViewer.iconScale` and related properties inside `UpdateDisplay()` on every OnUpdate tick.

**Why it's wrong:** Already identified in `Display.lua` — this is why `SnapshotSettings()` and `cachedBarSettings` exist. The milestone should not introduce new per-frame reads from CDM viewer objects.

**Do this instead:** Extend `SnapshotSettings()` if any new CDM properties are needed. The CDM tab does not need live CDM properties at all — it reads from `TerribleBuffTrackerDB`.

---

## Integration Points

### CDM Settings Window

| Integration | Method | Notes |
|-------------|--------|-------|
| Tab button creation | `CreateFrame("Frame", ..., "CooldownViewerSettingsTabTemplate")` | Frame must exist before `CooldownViewerSettings` is shown |
| Tab array insertion | `table.insert(CooldownViewerSettings.TabButtons, tbtTab)` | `SetDisplayMode` iterates this for `SetChecked` |
| Tab anchor | `SetPoint("TOP", CooldownViewerSettings.AurasTab, "BOTTOM", 0, -3)` | Mirrors XML pattern from `AurasTab` |
| Display mode guard | `hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", ...)` | Detect tab-away to hide TBT panel |
| TBT panel parent | `CreateFrame("Frame", nil, CooldownViewerSettings)` | Anchored inside `Inset`, sized to match `CooldownScroll` |
| Window open/close | `EventRegistry "CooldownViewerSettings.OnShow"` / `"OnHide"` | Use to start/stop preview timers (replacing current `configFrame OnShow/OnHide`) |

### Edit Mode

| Integration | Method | Notes |
|-------------|--------|-------|
| Enter hook | `EventRegistry:RegisterCallback("EditMode.Enter", ...)` | Already available (used by `Display.lua`) |
| Exit hook | `EventRegistry:RegisterCallback("EditMode.Exit", ...)` | Already available (used by `Display.lua`) |
| Position save | `TerribleBuffTrackerDB.editModePositions` | Keyed by `"bars"` and `"icons"` |
| Container re-anchor | Modify `Display.lua:InitDisplay()` | When `editModePositions.bars` exists, parent to UIParent and apply saved position instead of CDM anchor |

### BuffEngine

| Integration | Method | Notes |
|-------------|--------|-------|
| New API: `SetBuffSection` | `ns:SetBuffSection(spellID, section)` | CDMTab calls this on drag-drop |
| Migration | Backfill in `InitBuffEngine()` | Must run before CDMTab reads sections |
| `AddTrackedBuff` default | `section = "hidden"` | New buffs land in Not Displayed per design |

---

## Sources

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — tab injection pattern, `SetDisplayMode`, `TabButtons` parentArray, drag-and-drop order change system (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — `CooldownViewerSettingsTabTemplate` inheriting `LargeSideTabButtonTemplate`, tab anchor patterns (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua` — `EditModeSystemMixin:OnSystemLoad()` confirming `Enum.EditModeSystem` requirement, `RegisterSystemFrame` (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua` — `EnterEditMode`/`ExitEditMode` firing `EventRegistry "EditMode.Enter"/"EditMode.Exit"` (HIGH confidence)
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua` — `SidePanelTabButtonMixin`, `SetChecked`, `SetCustomOnMouseUpHandler` (HIGH confidence)
- Existing `Display.lua` — `SnapshotSettings` pattern, `HookViewerLayout`, EventRegistry `EditMode.Exit` callback already in use (HIGH confidence)

---

*Architecture research for: TerribleBuffTracker v0.2.0 — CDM tab, Edit Mode, drag-and-drop*
*Researched: 2026-03-28*
