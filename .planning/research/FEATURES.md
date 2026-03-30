# Feature Research

**Domain:** WoW addon UI — CDM settings tab integration, Edit Mode movable elements, drag-and-drop buff management
**Researched:** 2026-03-28
**Confidence:** HIGH (all findings sourced directly from Blizzard UI source at C:\Users\jonat\Repositories\wow-ui-source)

---

## Feature Landscape

### Table Stakes (Users Expect These)

These features are required for the milestone goals to be coherent. Missing any of these means the feature set is incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| TBT tab button in CDM settings sidebar | CDM has lateral tab buttons (`LargeSideTabButtonTemplate`) on the left of `CooldownViewerSettings` frame; the `parentArray="TabButtons"` pattern auto-registers tabs into the iterated set; users expect TBT to follow this exact pattern | MEDIUM | Tab buttons are `LargeSideTabButtonTemplate` (43x55px), use `activeAtlas`/`inactiveAtlas`/`tooltipText` key-values, anchored vertically below the last existing tab. Tab selection is driven by `SetDisplayMode()` which iterates `self.TabButtons` and calls `SetChecked(frame.displayMode == displayMode)`. TBT needs a new `displayMode` string key and corresponding category render path |
| Buff icons displayed in CDM settings content area | CDM's content area is a `ScrollFrame > Content` frame; categories are added via `categoryPool` (CreateFramePoolCollection); items are 38x38 icon frames using `CooldownViewerSettingsItemTemplate`; users expect TBT buffs to use the same visual language | MEDIUM | TBT cannot reuse `CooldownViewerCategory` directly (it's tied to `Enum.CooldownViewerCategory` which is Blizzard-internal). TBT must create its own category frame within CDM's scroll content, mimicking the visual style |
| 4 named sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) | CDM itself uses collapsible sections with headers (`ListHeaderThreeSliceTemplate`) and grid layout containers; users familiar with CDM expect the same sectioning pattern | MEDIUM | Each section is a `CooldownViewerSettingsCategoryTemplate`-style frame: a `Header` button + `Container` (GridLayoutFrame). TBT replicates this structure manually since it cannot inject into Blizzard's `cooldownCategories` table (which is local to CooldownViewerSettings.lua) |
| Drag buff icons between sections | CDM implements drag-and-drop via `OnDragStart`/`OnMouseUp`/`GLOBAL_MOUSE_UP` event pattern; a floating cursor icon (`CooldownViewerSettingsDraggedItemMixin`) follows the mouse; `OnEnter` triggers fire `EventRegistry` events; drop commits via `EndOrderChange()` calling `SetCooldownToCategory()` or `ChangeOrderIndex()`. Users expect the same feel | HIGH | TBT must implement its own parallel drag system: pickup frame following cursor via `OnUpdate`, `GLOBAL_MOUSE_UP` listener on the settings window, reorder marker (`ReorderMarker` frame), `GetBestCooldownItemTarget()` hit-test logic weighted by distance. The CDM drag system is entirely in `CooldownViewerSettingsMixin`; TBT cannot hook into it and must replicate the pattern |
| Edit Mode movable elements (bars container, buffs container) | Blizzard uses `EditMode.Enter` / `EditMode.Exit` EventRegistry callbacks for showing/hiding system selection frames; the existing Display.lua already hooks `EventRegistry:RegisterCallback("EditMode.Exit", ...)`. Users expect both TBT containers to be independently draggable in Edit Mode | HIGH | Full `EditModeSystemMixin` registration requires `self.system` set to a valid `Enum.EditModeSystem` value — this is Blizzard-internal and not available to addons. TBT cannot use native Edit Mode registration. Instead: listen to `EditMode.Enter`/`EditMode.Exit` events, show custom drag handles on the containers, and save positions to `TerribleBuffTrackerDB` manually |
| Position persistence for Edit Mode elements | Users expect positions to survive reloads | LOW | Store `anchorInfo` (point, offsetX, offsetY relative to UIParent) in `TerribleBuffTrackerDB`; apply on `PLAYER_ENTERING_WORLD`. Already precedented by Display.lua's cached settings pattern |
| Migration: existing tracked buffs preserved | Any existing `TerribleBuffTrackerDB` data must survive the UI rework | LOW | The buff data model is unchanged; only the config UI is being replaced. A version flag in `TerribleBuffTrackerDB` ensures the migration runs once. No data transformation needed if category assignment defaults are sensible |

### Differentiators (Competitive Advantage)

Features that make TBT's config feel native rather than bolted-on.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Reorder marker between icons during drag | CDM uses an 8px wide `ReorderMarker` frame (vertical or horizontal) that updates every frame during drag to show where the icon will land. This visual polish is what makes the drag feel native rather than approximate | MEDIUM | `UpdateReorderMarkerPosition()` is called per-frame during `OnUpdate`. The marker toggles between vertical (icon grid) and horizontal (bar list) orientation based on category type. For TBT's simpler 2-category setup this is achievable without the full weighted hit-test machinery |
| Context menu on right-click (reassign to section) | CDM's items show a context menu via `MenuUtil.CreateContextMenu` with "Assign to [Section]" options; right-click reassignment is faster than drag for power users | MEDIUM | TBT can use `MenuUtil.CreateContextMenu` with section reassignment options. This is independent of drag and simpler to implement |
| Add button in Suggested section (spell ID + duration prompt) | New buffs land in Not Displayed by default; this matches CDM's "disabled" category convention and prevents clutter. The Add workflow is a static popup or custom dialog | MEDIUM | `StaticPopupDialogs` pattern is well-established. Two fields needed: Spell ID and Duration. On accept: create entry in `TerribleBuffTrackerDB`, assign to `NotDisplayed` category |
| Delete drop zone in Not Displayed section | A dedicated delete target (trash/drop zone) gives users a visual affordance for removal during drag. CDM has no exact equivalent but the "empty slot" pattern (`SetAsEmptyCategory`) provides a model for a special drop target | MEDIUM | Implement as a special slot frame in Not Displayed that, when a drag is released over it, removes the buff from `TerribleBuffTrackerDB` entirely. Can be a fixed square with a trash atlas icon |
| One-time CDM settings copy for fresh installs | On first install, copy CDM's current scale/padding/bar width into `TerribleBuffTrackerDB` so TBT's bars match CDM visually without manual calibration | LOW | Check for version sentinel in `TerribleBuffTrackerDB` on `ADDON_LOADED`. If absent: read CDM settings via the cached settings path already in Display.lua, write to DB, set sentinel. This runs once and never again |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Native `EditModeSystemMixin` registration | Would give TBT frames the full Edit Mode chrome (highlight border, settings dialog, snap lines) | `Enum.EditModeSystem` values are Blizzard-internal enums; addons cannot add new entries. `EditModeManagerFrame:RegisterSystemFrame()` expects `self.system` to match a known enum value. Attempting this causes taint and API errors | Listen to `EditMode.Enter`/`EditMode.Exit` EventRegistry events; show custom drag handles on TBT containers; save positions manually. This is how Display.lua already handles `EditMode.Exit` |
| Injecting into CDM's `cooldownCategories` table | Would allow TBT entries to appear in CDM's native sections (Essential, Utility, etc.) | `cooldownCategories` is a `local` table in `CooldownViewerSettings.lua`. It is initialized in a `do...end` block and never exposed. No upvalue injection path exists | Add a TBT-owned tab via `parentArray="TabButtons"` which renders TBT's own category UI inside CDM's scroll content |
| Hooking CDM's drag system | Reusing `CooldownViewerSettingsMixin:BeginOrderChange` / `EndOrderChange` would avoid reimplementing drag | These methods operate on `CooldownViewerSettingsItemMixin` instances which reference internal `CooldownID` / `GetCooldownInfo()` APIs tied to Blizzard's spell data. TBT items have no such backing data | Implement a parallel drag system using the same event pattern (`GLOBAL_MOUSE_UP`, `OnUpdate`, `OnDragStart`) but operating on TBT's own item frames |
| Real spell suggestions in Suggested section | Users want auto-populated recommendations based on their spec | Spell IDs are often Secret Values in Midnight; `GetSpellInfo` behavior is restricted; building a reliable suggestion engine requires per-spec spell ID databases that go stale | Placeholder section with a single Add button. Document the placeholder clearly. Real suggestions are a future milestone |
| SavedVariables for drag order within CDM's layout manager | Sharing CDM's layout persistence (which uses `C_CooldownViewer` APIs) | The layout manager APIs (`CooldownViewerLayoutManagerMixin`, serializer, data provider) are tightly coupled to CDM's internal IDs. TBT has no `CooldownID` for its tracked buffs | Store buff order and section assignment directly in `TerribleBuffTrackerDB` using spellID as key |

---

## Feature Dependencies

```
CDM Tab Button (parentArray="TabButtons")
    └──requires──> CDM settings window exists and is loaded
                       └──requires──> COOLDOWN_VIEWER_DATA_LOADED event fired

TBT Content Frame (category sections)
    └──requires──> CDM Tab Button (content only shown when tab is active)
    └──requires──> TerribleBuffTrackerDB buff list

Drag-and-Drop (section reassignment)
    └──requires──> TBT Content Frame (needs rendered item frames as drag targets)
    └──requires──> TerribleBuffTrackerDB category field per buff

Delete Drop Zone
    └──requires──> Drag-and-Drop (only activated during drag)

Add Button (Suggested section)
    └──requires──> TBT Content Frame rendered

Edit Mode Movable Elements
    └──requires──> EventRegistry "EditMode.Enter" / "EditMode.Exit" (already used in Display.lua)
    └──requires──> Position stored in TerribleBuffTrackerDB

One-Time CDM Settings Copy
    └──requires──> ADDON_LOADED (already handled in Core.lua)
    └──enhances──> Edit Mode Movable Elements (sets initial position from CDM anchor)

Migration (existing buffs preserved)
    └──requires──> TerribleBuffTrackerDB version sentinel
    └──must complete before──> TBT Content Frame renders (needs category assignments)
```

### Dependency Notes

- **CDM Tab requires COOLDOWN_VIEWER_DATA_LOADED:** CDM's own `OnLoad` uses `EventUtil.ContinueAfterAllEvents` waiting on `VARIABLES_LOADED`, `PLAYER_ENTERING_WORLD`, and `COOLDOWN_VIEWER_DATA_LOADED`. TBT's tab injection must happen after this sequence completes or the CDM settings window won't exist yet.
- **Drag requires rendered items:** The `OnEnter` / `GetBestCooldownItemTarget` hit-test only works on visible, positioned frames. Items must be laid out before drag begins.
- **Edit Mode is independent of CDM tab:** The two features share no code path. Edit Mode affects `Display.lua` containers; the CDM tab affects `ConfigUI.lua`. They can be developed in parallel.
- **Migration must run before first render:** Category assignments default to `NotDisplayed` for new buffs; existing buffs without a category field need one assigned on first load. This guard is a single nil-check on load, not a blocking event.

---

## MVP Definition

This is milestone v0.2.0 — the "minimum" is defined by the milestone scope in PROJECT.md, not by product-market fit. All items below are in scope.

### Launch With (v0.2.0)

- [ ] CDM tab button ("TBT Buffs") via `LargeSideTabButtonTemplate` + `parentArray="TabButtons"` — without this, nothing else has a home
- [ ] 4 sections rendered in CDM scroll content: Tracked Buffs, Tracked Bars, Not Displayed, Suggested — the core organizational structure
- [ ] Drag icons between sections to reassign display mode or disable — primary interaction model
- [ ] Delete drop zone in Not Displayed — required to remove buffs without needing a separate button
- [ ] Add button in Suggested section (spell ID + duration prompt, lands in Not Displayed) — required to add new buffs in the new UI
- [ ] Edit Mode movable elements: bars container and buffs container independently draggable — required by milestone spec
- [ ] Position persistence for Edit Mode elements in `TerribleBuffTrackerDB` — Edit Mode is useless without persistence
- [ ] Migration: existing buffs get `category = "NotDisplayed"` default if field absent — required to not break existing installs
- [ ] One-time CDM settings copy for fresh installs — required by milestone spec

### Add After Validation (v0.2.x)

- [ ] Context menu (right-click) for section reassignment — good ergonomics but drag covers the primary case
- [ ] Reorder marker visual during drag — polish; drag still works without it
- [ ] Collapsible section headers — useful if buff lists grow long; not needed for initial use

### Future Consideration (v0.3+)

- [ ] Real spell suggestions in Suggested section — blocked on reliable spell ID data for Midnight
- [ ] Import/export buff list (similar to CDM's clipboard layout sharing) — only valuable once users have large curated lists
- [ ] Per-spec buff configurations — scope expansion; requires spec-detection event handling

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CDM tab button | HIGH | MEDIUM | P1 |
| 4 sections rendered | HIGH | MEDIUM | P1 |
| Drag between sections | HIGH | HIGH | P1 |
| Edit Mode movable elements | HIGH | HIGH | P1 |
| Delete drop zone | MEDIUM | MEDIUM | P1 |
| Add button (Suggested) | HIGH | MEDIUM | P1 |
| Position persistence | HIGH | LOW | P1 |
| Migration guard | HIGH | LOW | P1 |
| One-time CDM settings copy | MEDIUM | LOW | P1 |
| Context menu (right-click reassign) | MEDIUM | MEDIUM | P2 |
| Reorder marker visual | MEDIUM | MEDIUM | P2 |
| Collapsible section headers | LOW | LOW | P2 |
| Real spell suggestions | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for v0.2.0 launch
- P2: Should have, add in v0.2.x
- P3: Future milestone

---

## Implementation Complexity Notes

### CDM Tab Injection: How It Actually Works

The `CooldownViewerSettings` XML frame defines tabs with `inherits="CooldownViewerSettingsTabTemplate" parentArray="TabButtons"`. The `parentArray` attribute causes WoW's XML parser to add each tab frame to `CooldownViewerSettings.TabButtons[]`. `SetupTabs()` iterates `self.TabButtons` and attaches a `SetCustomOnMouseUpHandler`. `SetDisplayMode()` then iterates the same array calling `SetChecked`.

For TBT to add a tab:
1. Create a frame inheriting `CooldownViewerSettingsTabTemplate` (or replicating it) with `CooldownViewerSettings` as parent.
2. The frame must be added to `CooldownViewerSettings.TabButtons` manually (since it won't be in the XML `parentArray` at load time).
3. Set `frame.displayMode = "tbt"` key-value.
4. Hook or wrap `CooldownViewerSettingsMixin:SetDisplayMode` to handle `"tbt"` — show TBT content, hide CDM scroll content.

This is the critical architectural decision: TBT's tab selection must hide CDM's `CooldownScroll` and show TBT's own content frame (or vice versa). CDM's display mode system only shows/hides content via `SetCurrentCategories()` which operates on CDM's internal category pool — TBT cannot participate in that.

**Confidence: HIGH** — Tab pattern fully confirmed from XML and Lua source.

### Drag-and-Drop: Event Chain

CDM's drag chain (confirmed from source):
1. `OnDragStart` on item frame → `BeginOrderChange()` → `PickupCooldownItemCursor()` creates floating icon frame → `SetScript("OnUpdate", ...)` on settings window → registers `GLOBAL_MOUSE_UP`
2. Per-frame `OnUpdate` → `UpdateReorderMarker()` → `GetBestCooldownItemTarget()` hit-tests all items in hovered category → positions `ReorderMarker`
3. `GLOBAL_MOUSE_UP` (LeftButton) → `EndOrderChange()` → commits category change or order change → `RefreshLayout()`
4. `GLOBAL_MOUSE_UP` (RightButton) → `CancelOrderChange()` → discards

TBT replicates this pattern using its own item frames and a simpler data model (category string per buff rather than `CooldownID` + layout manager). The floating cursor frame is a standard `CreateFrame` parented to `GetAppropriateTopLevelParent()`.

**Confidence: HIGH** — Pattern confirmed from complete source trace.

### Edit Mode Integration: What's Actually Possible

`EditModeSystemMixin:OnSystemLoad()` calls `EditModeManagerFrame:RegisterSystemFrame(self)` which requires `self.system` to be a valid `Enum.EditModeSystem` value. These are Blizzard-internal — confirmed by examining `EditModePresetLayoutManager:GetModernSystems()` and the system registration flow. Third-party addons cannot add new systems.

What TBT CAN do (and already partially does via `EventRegistry:RegisterCallback("EditMode.Exit", ...)`):
- Listen to `"EditMode.Enter"` to show custom drag handles on TBT containers
- Listen to `"EditMode.Exit"` to hide handles and persist positions
- Implement `StartMoving()` / `StopMovingOrSizing()` on the container frames during edit mode
- Save final position as `point, relativeTo:GetName(), relativePoint, offsetX, offsetY` in `TerribleBuffTrackerDB`

This gives users draggable TBT elements during Edit Mode without native Edit Mode chrome. The trade-off: no snap lines, no settings dialog, no "Reset to default position" button in the Edit Mode UI. These can be approximated with TBT's own UI elements if needed in a future milestone.

**Confidence: HIGH** — Confirmed from EditModeManager.lua and existing Display.lua patterns.

---

## Sources

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — Tab template definitions, item templates, category templates, full frame hierarchy
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — Tab setup, display mode switching, drag-and-drop event chain, order change logic, category pool management
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua` — `EditModeSystemMixin` full API, `OnEditModeEnter`/`OnEditModeExit`, `RegisterSystemFrame`, position persistence via `systemInfo.anchorInfo`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua` — `RegisterSystemFrame`, `EnterEditMode`/`ExitEditMode`, `EditMode.Enter`/`EditMode.Exit` event triggers
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.xml` — `LargeSideTabButtonTemplate` definition (43x55px, `SidePanelTabButtonMixin`, atlas keys)
- `C:\Users\jonat\Repositories\TerribleBuffTracker\Display.lua` — Existing `SnapshotSettings()`, `EventRegistry:RegisterCallback("EditMode.Exit", ...)` pattern already in production

---
*Feature research for: WoW addon UI — CDM tab integration, Edit Mode, drag-and-drop management*
*Researched: 2026-03-28*
