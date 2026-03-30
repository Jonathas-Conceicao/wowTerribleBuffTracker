# Pitfalls Research

**Domain:** WoW addon — CDM tab integration, Edit Mode movable elements, drag-and-drop buff management
**Researched:** 2026-03-28
**Confidence:** HIGH (sourced directly from Blizzard UI source at `wow-ui-source`)

---

## Critical Pitfalls

### Pitfall 1: CDM Settings Frame Not Initialized When Addon Loads

**What goes wrong:**
TBT tries to insert a tab into `CooldownViewerSettings` at `ADDON_LOADED` or `PLAYER_ENTERING_WORLD`, but `CooldownViewerSettings` defers its own initialization. The Blizzard source shows CDM waits for all three events before running `LoadCooldownSettings`:

```lua
EventUtil.ContinueAfterAllEvents(LoadCooldownSettings,
    "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED");
```

`COOLDOWN_VIEWER_DATA_LOADED` fires after `PLAYER_ENTERING_WORLD`. Any attempt to read `CooldownViewerSettings:GetLayoutManager()` or `CooldownViewerSettings:GetDataProvider()` before that event will return nil and crash.

**Why it happens:**
The addon developer sees the CDM frame exists in the global namespace and assumes it is ready. It exists (defined in XML as `parent="UIParent"`), but it has not run its internal data initialization.

**How to avoid:**
TBT must also wait for `COOLDOWN_VIEWER_DATA_LOADED` before touching CDM internals. Use `EventUtil.ContinueAfterAllEvents` mirroring the CDM pattern, or listen for `COOLDOWN_VIEWER_DATA_LOADED` explicitly before inserting the tab and injecting the content frame.

**Warning signs:**
- Lua error: "attempt to index a nil value" on `CooldownViewerSettings.layoutManager` or `.dataProvider`
- Tab button appears but content frame is empty or crashes on show

**Phase to address:**
CDM tab integration phase (Phase 1 of the milestone). Gate all CDM interaction behind `COOLDOWN_VIEWER_DATA_LOADED`.

---

### Pitfall 2: Tab Insertion Into `TabButtons` parentArray Requires XML Registration

**What goes wrong:**
`CooldownViewerSettingsMixin:SetupTabs` iterates `self.TabButtons` — a parentArray populated at XML load time by the `parentArray="TabButtons"` attribute on child frames. Any tab button created at runtime via `CreateFrame` will NOT be added to `self.TabButtons` automatically.

`SetDisplayMode` also iterates `self.TabButtons` to call `SetChecked`, so a runtime-created tab that is not in that array will never receive the checked/unchecked state update and will appear permanently active or inactive.

**Why it happens:**
`parentArray` is an XML-only mechanism. Developers assume they can call `CreateFrame("Frame", CooldownViewerSettings, "CooldownViewerSettingsTabTemplate")` and the frame will self-register.

**How to avoid:**
Two viable approaches:
1. Create the tab via XML in a separate TBT `.xml` file, parented to `CooldownViewerSettings` with `parentArray="TabButtons"` — this registers it at load time exactly like the built-in tabs.
2. Create the tab at runtime and manually append it to `CooldownViewerSettings.TabButtons` before `SetupTabs` is called — but this requires hooking `OnLoad`, which fires before addon code typically runs.

Approach 1 is cleaner. Approach 2 requires careful ordering. Both require knowing that `SetupTabs` only runs once (during `OnLoad`), so runtime insertion after that point requires also calling `tabButton:SetCustomOnMouseUpHandler` directly.

**Warning signs:**
- Tab button renders but clicking it does nothing or errors in `SetDisplayMode`
- Tab button does not switch between checked/unchecked state when other tabs are selected

**Phase to address:**
CDM tab integration phase. Decide early on XML vs. runtime approach; do not defer.

---

### Pitfall 3: `SetDisplayMode` Asserts on Unknown Display Modes

**What goes wrong:**
`CooldownViewerSettingsMixin:SetDisplayMode` calls:
```lua
assertsafe(type(categories) == "table",
    "Add missing category data for displayMode: " .. tostring(displayMode));
```
The local `displayModeToCategories` table only contains `"spells"` and `"auras"`. If TBT adds a third `displayMode` string (e.g., `"tbt"`) and calls `SetDisplayMode("tbt")`, the assertsafe fires and CDM's layout collapses.

**Why it happens:**
TBT cannot modify `displayModeToCategories` — it is a local variable inside `CooldownViewerSettings.lua`, not exposed to external code.

**How to avoid:**
TBT must NOT attempt to create a new display mode inside CDM's mode system. Instead, TBT's tab button should manage its own content panel as a separate frame, shown/hidden independently of CDM's `SetDisplayMode`. The TBT tab button should hide CDM's scroll frame and show TBT's own frame when selected; restoring CDM's scroll frame when deselected. Never call `CooldownViewerSettings:SetDisplayMode` with a TBT-owned string.

**Warning signs:**
- Lua error: `assertsafe` firing with "Add missing category data for displayMode"
- CDM settings window goes blank after clicking TBT tab

**Phase to address:**
CDM tab integration phase. Architecture decision: TBT's tab is a visibility toggle for a TBT-owned content frame, not a new display mode injected into CDM internals.

---

### Pitfall 4: Edit Mode Registration Must Happen Before `EditModeManagerFrame:EnterEditMode`

**What goes wrong:**
`EditModeManagerFrameMixin:RegisterSystemFrame` simply appends to `self.registeredSystemFrames`. When Edit Mode is opened, `EnterEditMode` calls `secureexecuterange(self.registeredSystemFrames, callOnEditModeEnter)`. If TBT's frame calls `RegisterSystemFrame` after `EnterEditMode` has already run (e.g., because the user opened Edit Mode before TBT finished loading), TBT's frame will never receive `OnEditModeEnter` for that session.

Additionally, `EditModeSystemMixin:OnSystemLoad` calls `EditModeManagerFrame:RegisterSystemFrame(self)` — this only works if `EditModeManagerFrame` is already loaded. If CDM loads after TBT on some load order variation, this call hits nil.

**Why it happens:**
Addon load order is not guaranteed. TBT may complete loading before or after `Blizzard_EditMode` initializes `EditModeManagerFrame`.

**How to avoid:**
- In the XML template for TBT's Edit Mode frames, set `mixin="EditModeSystemMixin"` and include `<Scripts><OnLoad method="OnSystemLoad"/></Scripts>`. The `OnSystemLoad` method on `EditModeSystemMixin` is safe to call after the fact — it only fails if `EditModeManagerFrame` itself does not exist, which will not happen since it is a Blizzard frame.
- Also listen for `EditMode.Enter` via `EventRegistry` as a fallback to late-register or re-trigger setup.
- Do not attempt manual `RegisterSystemFrame` calls from Lua; rely on `OnSystemLoad` via the mixin.

**Warning signs:**
- TBT elements do not show selection handles in Edit Mode
- Dragging TBT elements in Edit Mode has no effect on position persistence

**Phase to address:**
Edit Mode integration phase. Test by entering Edit Mode before and after first login, and after `/reload`.

---

### Pitfall 5: Edit Mode Positions Stored Using Frame Name as Anchor Key

**What goes wrong:**
`ConvertToAnchorInfo` stores position as:
```lua
anchorInfo.relativeTo = relativeTo and relativeTo:GetName() or "UIParent";
```
If the TBT container frame has no name (created with `CreateFrame("Frame", nil, ...)`) the anchor stores `relativeTo = nil` which becomes `"UIParent"`. This is fine at first, but if TBT's frame is parented to a CDM viewer frame and that viewer has a globally unique name, anchoring to it works — however if the CDM viewer is ever recreated or nil on a reload, position restoration will fail silently (the frame will teleport to `UIParent`).

TBT currently creates `barContainer` and `iconContainer` as unnamed frames parented to CDM viewers. For Edit Mode, these must have global names so `GetName()` returns a stable, non-nil value.

**Why it happens:**
Developers create containers without names for encapsulation, not realising Edit Mode position serialization depends on `GetName()`.

**How to avoid:**
Give TBT's Edit Mode system frames stable global names (e.g., `"TBTBarContainer"`, `"TBTIconContainer"`). Parent them to `UIParent` for Edit Mode independence — decoupling from CDM viewers is a stated goal of this milestone. Anchoring to a CDM viewer frame will re-introduce the coupling that Edit Mode is meant to remove.

**Warning signs:**
- Position resets to UIParent default on every reload
- `/reload` loses position even after user saved via Edit Mode "Save Changes"

**Phase to address:**
Edit Mode integration phase. Name frames before writing any anchor persistence logic.

---

### Pitfall 6: Drag-and-Drop Cursor Frame Must Live at TOOLTIP Strata

**What goes wrong:**
Blizzard's drag cursor for CDM settings items uses:
```xml
<Frame name="CooldownViewerSettingsDraggedItemTemplate" frameStrata="TOOLTIP" ...>
```
If TBT's drag cursor frame is created at a lower strata (e.g., `HIGH` or `DIALOG`), it will render beneath the CDM settings window itself and appear invisible or partially clipped when dragging over the panel.

Additionally, the cursor frame must be parented to `GetAppropriateTopLevelParent()`, not to the CDM settings frame directly. Parenting to the CDM settings frame causes the cursor to be clipped by that frame's bounds and masked by its strata.

**Why it happens:**
Developers parent the cursor frame to the closest logical ancestor (the settings panel) and use a convenient strata like `DIALOG`. The Blizzard source is explicit that TOOLTIP strata + UIParent-level parent is the correct pattern.

**How to avoid:**
Use `frameStrata="TOOLTIP"` and parent to `GetAppropriateTopLevelParent()`. Set position via `GetScaledCursorPositionForFrame(topLevel)` in `OnUpdate`, exactly as `CooldownViewerSettingsDraggedItemMixin:OnUpdate` does.

**Warning signs:**
- Dragged icon is invisible or only visible outside the CDM settings window bounds
- Dragged icon renders behind the settings panel

**Phase to address:**
Drag-and-drop implementation phase.

---

### Pitfall 7: GLOBAL_MOUSE_UP Must Be Registered/Unregistered Per Drag Session

**What goes wrong:**
Blizzard's drag reorder system in CDM settings registers `GLOBAL_MOUSE_UP` at `BeginOrderChange` and unregisters at `EndOrderChange`/`CancelOrderChange`. If TBT registers `GLOBAL_MOUSE_UP` permanently (e.g., in `OnLoad`), it will fire on every mouse release across the entire UI — including clicks in chat, action bars, and other panels — causing spurious drag completion calls.

Conversely, if TBT never registers `GLOBAL_MOUSE_UP` and relies solely on `OnMouseUp` on the drop targets, the drag will fail to complete when the mouse is released over a non-TBT frame (which is the normal case during a drag).

**Why it happens:**
Developers either register the event too broadly or miss that `OnMouseUp` on individual frames only fires when the cursor is over that frame at release time.

**How to avoid:**
Mirror the CDM pattern exactly: register `GLOBAL_MOUSE_UP` on the settings frame at drag start, unregister at drag end. Use a single `OnUpdate` on the settings frame (not on each dragged item) to update cursor position.

**Warning signs:**
- Drag ends immediately when cursor leaves a buff item frame
- Drop targets register drops on random mouse releases unrelated to dragging

**Phase to address:**
Drag-and-drop implementation phase.

---

### Pitfall 8: Migration Must Not Overwrite Existing `trackedBuffs` Structure

**What goes wrong:**
The new milestone adds sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) and a display category per buff. If migration code overwrites or reinitialises `TerribleBuffTrackerDB.trackedBuffs` to add the `category` field, it may reset user-customised data (enabled/disabled state, custom labels) that was saved in v0.1.

A common mistake is checking `if not TerribleBuffTrackerDB` at the top of `ADDON_LOADED` and reinitialising the whole table — this silently nukes existing saves if the DB structure test is wrong.

**Why it happens:**
The `ADDON_LOADED` default initialisation block already exists in `Core.lua` and is easy to expand incorrectly. Adding a new top-level field check alongside the existing structure check is error-prone.

**How to avoid:**
Add a `schemaVersion` field to `TerribleBuffTrackerDB`. On load, if `schemaVersion` is absent or less than the current version, run a targeted migration: iterate existing `trackedBuffs`, add missing `category` fields with a default of `"trackedBuff"`, and set `schemaVersion`. Never wipe or reinitialise the whole table during migration.

**Warning signs:**
- All tracked buffs reset to defaults on first login after update
- User-configured enable/disable states are lost

**Phase to address:**
Data migration phase (should be the first phase of the milestone, before any UI work).

---

### Pitfall 9: Existing Display Anchors Break When Edit Mode Decouples Containers from CDM

**What goes wrong:**
`Display.lua` currently creates `barContainer` and `iconContainer` as children of CDM viewer frames:
```lua
barContainer = CreateFrame("Frame", nil, ns.cdmBarViewer)
barContainer:SetPoint("TOPLEFT", ns.cdmBarViewer, "BOTTOMLEFT")
```
When Edit Mode is added and these containers become independently movable (parented to `UIParent`), the existing `SnapshotSettings()` flow hooks CDM viewer layout events to re-anchor TBT bars. Those hooks will fire and attempt to reapply CDM-relative positions even though the containers are now UIParent-relative. The result is containers that teleport on CDM layout refresh.

**Why it happens:**
The Display.lua layout hooks were designed for a world where TBT anchors follow CDM. Edit Mode changes the fundamental assumption without removing the old hooks.

**How to avoid:**
When Edit Mode integration is added, audit every `HookViewerLayout` callback in `Display.lua`. Add a guard: if the container is in Edit-Mode-owned position (i.e., no longer CDM-relative), skip the CDM layout re-anchor. The CDM settings copy on fresh install (one-time) should still run but must be detected and skipped on subsequent loads.

**Warning signs:**
- Containers jump to CDM position on every CDM settings change after being moved in Edit Mode
- `SnapshotSettings` overwrites Edit Mode positions

**Phase to address:**
Edit Mode integration phase. Must be addressed before or during the phase that adds Edit Mode — not deferred.

---

### Pitfall 10: Removing ConfigUI.lua Without Updating the Slash Command

**What goes wrong:**
The `/tbt` slash command calls `ns:ToggleConfigUI()`. If `ConfigUI.lua` is removed or disabled without redirecting the slash command, players get a Lua error. If the CDM settings window is the replacement, the slash command should call `ShowUIPanel(CooldownViewerSettings)` or scroll/focus to the TBT tab.

Additionally, `UISpecialFrames` (Escape-to-close) registration in the old ConfigUI must be explicitly removed. If not removed, `UISpecialFrames` retains a reference to the destroyed/hidden frame and Escape key handling may error or silently fail for all UI panels.

**Why it happens:**
ConfigUI removal feels like a simple file deletion, but it has two integration points (slash command and UISpecialFrames) that are invisible during development and only surface in-game.

**How to avoid:**
Before removing ConfigUI.lua: (1) update the slash command handler in `Core.lua` to open CDM settings to the TBT tab, and (2) explicitly remove the ConfigUI frame from `UISpecialFrames` (or ensure the frame is never added if the file is excluded from the .toc).

**Warning signs:**
- `/tbt` produces "attempt to call nil value (field 'ToggleConfigUI')"
- Escape key stops working for all UI panels

**Phase to address:**
ConfigUI replacement phase (same phase as CDM tab integration).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `schemaVersion` field, just add new fields inline | Simpler migration code | Any future field addition risks collision with old field names; no way to detect already-migrated state | Never — schemaVersion is low cost, high safety |
| Parent drag cursor to CDM settings frame | Avoids `GetAppropriateTopLevelParent()` lookup | Cursor clips behind settings panel; invisible during drags | Never |
| Leave CDM layout hooks active after Edit Mode integration | Avoids conditional logic | Containers teleport on CDM refresh after user moves them | Never |
| Use `parentArray` trick without XML file | Avoids adding a .xml file to .toc | Tab not registered in `TabButtons`; mode switching breaks | Never — XML is required |
| Hardcode Edit Mode system enum value | Avoids investigating Enum namespace | Breaks on any Blizzard enum reshuffle | Acceptable only if protected by a nil check with graceful fallback |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CDM `SetupTabs` | Call `CooldownViewerSettings:SetDisplayMode("tbt")` to show TBT content | TBT tab shows/hides its own content frame; never injects into CDM's displayMode system |
| CDM tab `TabButtons` parentArray | Create tab with `CreateFrame` at runtime expecting auto-registration | Define tab in XML with `parentArray="TabButtons"` so it is populated during XML load |
| Edit Mode `OnSystemLoad` | Call `RegisterSystemFrame` manually from Lua after load | Use `mixin="EditModeSystemMixin"` in XML; `OnSystemLoad` calls `RegisterSystemFrame` at the right time |
| Drag cursor frame | Parent to settings panel at `HIGH` strata | Parent to `GetAppropriateTopLevelParent()` at `TOOLTIP` strata |
| `GLOBAL_MOUSE_UP` | Register permanently in `OnLoad` | Register only for the duration of a drag session |
| CDM data access | Access `CooldownViewerSettings:GetLayoutManager()` at `PLAYER_ENTERING_WORLD` | Gate behind `COOLDOWN_VIEWER_DATA_LOADED` |
| Edit Mode anchor serialization | Use unnamed (`nil`) frame names for containers | Give containers stable global names; `ConvertToAnchorInfo` uses `GetName()` |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Running `SnapshotSettings()` inside CDM layout hooks after Edit Mode decouples containers | Containers teleport on every CDM change | Guard: skip CDM re-anchor if container is in Edit Mode position | Immediately after Edit Mode integration |
| `GLOBAL_MOUSE_UP` registered permanently | Drag completion fires on any mouse up across all UI | Register/unregister per drag session only | As soon as player clicks outside TBT UI during a drag |
| TBT tab `OnUpdate` running cursor tracking when no drag is active | Unnecessary work every frame | Set `OnUpdate` script only during drag; nil it at end | Low impact alone, but consistent with CDM's own pattern |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| New buffs added via Suggested section land directly in a visible section | Users see unexpected bars/icons appear immediately | New buffs land in "Not Displayed" first; user explicitly promotes to Tracked Buffs or Tracked Bars |
| CDM settings copy runs on every login instead of once | User's manual CDM position overrides are reset each session | Set a `cdmSettingsCopied` flag in DB after first copy; skip on subsequent loads |
| TBT tab does not restore the previously selected CDM tab (Spells vs. Auras) when dismissed | Disorienting for users who were on the Spells tab | Cache `CooldownViewerSettings.displayMode` before showing TBT tab; restore it when TBT tab is deselected |
| Delete drop zone always visible | Clutters the UI for users not in a drag session | Only show delete zone when a drag is active |

---

## "Looks Done But Isn't" Checklist

- [ ] **CDM tab button:** Tab appears in the settings window AND clicking it shows TBT content AND deselecting it restores CDM scroll content AND `SetChecked` state matches selection — verify all four
- [ ] **Edit Mode elements:** Frames appear with selection handles AND dragging saves position AND `/reload` restores position AND "Reset Position" button works — verify all four
- [ ] **Drag-and-drop:** Drag picks up item AND cursor icon follows mouse across entire screen (not just within settings panel) AND dropping in a section updates the category AND cancelling (Escape/drop outside) restores original state — verify all
- [ ] **Migration:** Fresh install with no DB works AND existing v0.1 DB with tracked buffs is preserved AND all enabled/disabled states survive — verify all three scenarios
- [ ] **ConfigUI removal:** `/tbt` opens CDM to TBT tab AND Escape still closes UI panels AND no Lua error on `/tbt` — verify all three
- [ ] **CDM settings one-time copy:** Runs on fresh install AND does not run on second login AND does not run after user manually changes CDM settings — verify all three

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| COOLDOWN_VIEWER_DATA_LOADED timing missed | LOW | Add event listener; test with `/reload` in loaded game |
| Tab not in `TabButtons` array | MEDIUM | Restructure to use XML-defined tab; requires adding .xml file and .toc entry |
| Edit Mode positions lost on reload | MEDIUM | Add global frame names; re-test position persistence |
| Migration wiped user data | HIGH | No automated recovery; document in changelog; advise users to re-add tracked buffs |
| Slash command broken after ConfigUI removal | LOW | Re-wire `ns.ToggleConfigUI` to open CDM settings; 5-line fix |
| Drag cursor invisible | LOW | Change parent to `GetAppropriateTopLevelParent()` and strata to `TOOLTIP`; immediate fix |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CDM data not ready at load time | Phase 1: CDM tab integration | Test tab interaction before and after `COOLDOWN_VIEWER_DATA_LOADED` fires |
| Tab not in `TabButtons` parentArray | Phase 1: CDM tab integration | Confirm tab receives `SetChecked` state changes when other tabs are selected |
| `SetDisplayMode` asserts on unknown mode | Phase 1: CDM tab integration | Confirm TBT never calls `SetDisplayMode` with a non-CDM mode string |
| Edit Mode registration timing | Phase 2: Edit Mode integration | Enter Edit Mode before and after `/reload`; verify selection handles appear |
| Edit Mode anchor serialization (unnamed frames) | Phase 2: Edit Mode integration | Verify `GetName()` returns stable value; check `ConvertToAnchorInfo` output |
| CDM layout hooks conflicting with Edit Mode | Phase 2: Edit Mode integration | Move TBT container in Edit Mode, trigger CDM layout, confirm container does not teleport |
| Drag cursor strata and parent | Phase 3: Drag-and-drop | Drag item across entire screen including over non-TBT frames; cursor visible throughout |
| GLOBAL_MOUSE_UP scope | Phase 3: Drag-and-drop | Click chat, action bars during a drag; confirm spurious drops do not fire |
| Migration data integrity | Phase 0: Data migration (first) | Test with v0.1 DB snapshot; verify all fields preserved |
| ConfigUI removal side effects | Phase 1: CDM tab integration | Verify `/tbt`, Escape key, and no Lua errors after removal |

---

## Sources

- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.lua` — CDM initialization, tab system, drag-and-drop implementation, `SetDisplayMode` constraints
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.xml` — `CooldownViewerSettingsTabTemplate` with `parentArray="TabButtons"`, drag cursor template at `TOOLTIP` strata
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua` — `EditModeSystemMixin:OnSystemLoad`, `RegisterSystemFrame`, anchor serialization
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua` — `RegisterSystemFrame`, `ConvertToAnchorInfo`, `EnterEditMode` flow
- `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua` — `SidePanelTabButtonMixin`, `SetChecked`, `SetCustomOnMouseUpHandler`, `activeAtlas`/`inactiveAtlas` requirements
- `TerribleBuffTracker/Display.lua` — existing container anchoring, `HookViewerLayout`, `SnapshotSettings`
- `TerribleBuffTracker/Core.lua` — existing `ADDON_LOADED`, `PLAYER_ENTERING_WORLD` initialization order

---
*Pitfalls research for: WoW addon CDM tab integration, Edit Mode movable elements, drag-and-drop*
*Researched: 2026-03-28*
