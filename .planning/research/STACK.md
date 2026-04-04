# Technology Stack

**Project:** TerribleBuffTracker
**Sources:** Blizzard UI source at `C:\Users\jonat\Repositories\wow-ui-source`
**Confidence:** HIGH — all findings verified against local Blizzard source files

---

## v0.2.1 Addition: Aura-Based Timer Cancellation APIs

**Researched:** 2026-04-03
**Scope:** WoW Midnight (Interface 120000+) APIs for UNIT_AURA event handling, aura scanning, and secret value detection

### The Key Event: UNIT_AURA

**Event name (literal):** `UNIT_AURA`
**Registration:** `frame:RegisterUnitEvent("UNIT_AURA", "player")` — unit-scoped registration restricts delivery to the specified unit token only. Do NOT use `RegisterEvent("UNIT_AURA")`, which fires for all units (target, nameplate targets, etc.) and generates unnecessary traffic.

**Payload:**
```lua
-- arg1: unitTarget (string) — the unit token that changed, e.g. "player"
-- arg2: updateInfo (UnitAuraUpdateInfo table)
local unit, updateInfo = ...
```

**UnitAuraUpdateInfo structure** (from `UnitConstantsDocumentation.lua`):
```lua
updateInfo = {
  isFullUpdate            = false, -- bool, always present (default false)
  removedAuraInstanceIDs  = { },   -- table<number> or nil; NeverSecretContents = true (ALWAYS SAFE)
  addedAuras              = { },   -- table<AuraData> or nil; ConditionalSecretContents = true (MAY BE SECRET)
  updatedAuraInstanceIDs  = { },   -- table<number> or nil; NeverSecretContents = true (ALWAYS SAFE)
}
```

Critical distinction: `removedAuraInstanceIDs` is tagged `NeverSecretContents` — instance IDs are always readable. `addedAuras` contents are `ConditionalSecretContents` — individual AuraData fields may be secret values when aura data is restricted.

When `isFullUpdate = true`, the incremental lists are unreliable; do a full re-scan of all active timers instead. This fires on zone transitions, loading screens, and similar wholesale state changes.

---

### AuraData Field Reference

`AuraData` is a Lua table returned by all C_UnitAuras lookup functions. Key fields confirmed in Blizzard source (`AuraUtil.lua`, `CooldownViewerItemData.lua`, `CooldownViewer.lua`):

```lua
auraData = {
  auraInstanceID          = number, -- unique instance for this aura application (safe to read)
  spellId                 = number, -- spell ID (may be secret when auras restricted)
  name                    = string, -- localized spell name (may be secret)
  icon                    = number, -- texture ID (may be secret)
  applications            = number, -- stack count (may be secret)
  duration                = number, -- total duration in seconds (may be secret)
  expirationTime          = number, -- GetTime() value when aura expires (may be secret)
  sourceUnit              = string, -- unit token of caster (may be secret)
  isHelpful               = bool,   -- buff flag
  isHarmful               = bool,   -- debuff flag
  isFromPlayerOrPlayerPet = bool,
  canApplyAura            = bool,
  isBossAura              = bool,
}
```

Note: Field name is `spellId` (lowercase 'd'), not `spellID`. This is confirmed throughout `CooldownViewerItemData.lua` and `CooldownViewer.lua`. This is different from the `spellID` convention used elsewhere in WoW APIs.

---

### Primary Lookup APIs

#### C_UnitAuras.GetPlayerAuraBySpellID(spellID) — RECOMMENDED for TBT

```lua
-- Returns AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- RequiresNonSecretAura = true  <- returns nil if the aura is a secret value
local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
if aura then
  -- buff is present and not a secret
end
```

Most direct API for TBT's use case. Checks a specific spell by ID on the player. Returns `nil` if the aura is absent OR if the aura exists but is a secret value. This ambiguity is why secret detection must gate the scan — see "Secret Value Detection" below.

This is exactly how CDM's `CooldownViewerItemData:FindLinkedSpellForCurrentAuras()` operates.

#### C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)

```lua
-- Returns first matching AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- RequiresNonSecretAura = true
local aura = C_UnitAuras.GetUnitAuraBySpellID("player", spellID)
```

More general form of the above. Same secret behavior. Useful if TBT ever needs to scan a non-player unit.

#### C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)

```lua
-- Returns AuraData or nil
-- SecretWhenUnitAuraRestricted = true
-- SecretArguments = "AllowedWhenUntainted"
local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
```

Useful if you have stored a `auraInstanceID` from a previous `addedAuras` event and want to verify the aura is still present. Requires tracking instance IDs per-timer.

#### AuraUtil.ForEachAura(unit, filter, batchSize, func, usePackedAura)

```lua
-- Iterates all auras matching filter; calls func(auraData) per aura
-- batchSize: max slots per batch (nil = unlimited)
-- usePackedAura: true = func receives AuraData table (use this)
AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
  -- aura.spellId, aura.auraInstanceID, etc.
  return true -- return true to stop early
end, true)
```

Full-scan approach. Works for `isFullUpdate` recovery. Subject to the same secret restrictions as the underlying slot APIs. For TBT's targeted cancellation, `GetPlayerAuraBySpellID` per tracked buff is cheaper than a full enumeration.

---

### Secret Value Detection

#### The Core Problem

When "auras are secret" (competitive/combat PvP contexts), `GetPlayerAuraBySpellID` returns `nil` even when the buff is active. This is indistinguishable from "buff ended" without an explicit secret check. Cancelling a timer on a false `nil` is incorrect behavior.

#### C_Secrets.ShouldAurasBeSecret() — RECOMMENDED GATE CHECK

```lua
-- Returns true if aura queries will generally produce secret values
-- No arguments, no SecretArguments restriction
if C_Secrets.ShouldAurasBeSecret() then
  -- set blocked flag, skip aura scan entirely
  ns.auraCheckBlocked = true
  return
end
```

This is the authoritative, zero-cost up-front check. Call it before attempting any aura scan in the `UNIT_AURA` handler. Source: `SecretPredicateAPIDocumentation.lua` — "Returns true if queries for aura data will generally produce secret values."

This is the correct mechanism for the "blocked flag" requirement in TBT's PROJECT.md.

#### issecretvalue(value) — Per-Value Fallback

```lua
-- Global Lua function, not namespaced
-- Returns true if the given value is a secret value type
if issecretvalue(aura.spellId) then
  -- this specific value is hidden; treat as inconclusive
end
```

Operates on individual values after a scan has run. Documented in `FrameScriptDocumentation.lua`. Used throughout Blizzard's restricted infrastructure code (`RestrictedInfrastructure.lua`, `Dump.lua`, etc.). Useful as a belt-and-suspenders guard inside a scan loop if `ShouldAurasBeSecret()` ever lags, but `ShouldAurasBeSecret()` is the right global gate.

#### C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID) — Granular Check

```lua
local isSecret = C_Secrets.ShouldUnitAuraInstanceBeSecret("player", auraInstanceID)
```

Per-instance granularity. Requires a known `auraInstanceID`. Less relevant for TBT since we scan by `spellId`.

#### When Secrets Are Active

`C_Secrets.ShouldAurasBeSecret()` returns `true` primarily in rated competitive PvP (arenas, rated battlegrounds). Blizzard's AuraUtil explicitly clears its caches on `PLAYER_REGEN_ENABLED` (leaving combat), confirming that combat exit is the primary state transition point.

The blocked flag in TBT should clear on:
- `PLAYER_REGEN_ENABLED` — left combat
- `ZONE_CHANGED_NEW_AREA` — zone transition resets secrecy context
- `PLAYER_ENTERING_WORLD` — login/reload/loading screen

---

### State Reset Events

#### PLAYER_REGEN_ENABLED

```lua
-- Fires when the player leaves combat (regeneration re-enabled)
-- No payload arguments
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
```

Blizzard's AuraUtil uses this exact event to dump visualization caches. For TBT: clear `ns.auraCheckBlocked` so the next `UNIT_AURA` can scan.

#### ZONE_CHANGED_NEW_AREA

```lua
-- Fires when the player transitions to a new zone
-- No payload arguments
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
```

Clears blocked flag. After a zone change, secrecy context may be different (e.g. leaving arena). A `UNIT_AURA` with `isFullUpdate = true` typically fires shortly after zone transitions, which naturally triggers a full rescan.

#### PLAYER_ENTERING_WORLD

```lua
-- Fires on login, reload, loading screen completion
-- Payload: isInitialLogin (bool), isReloadingUi (bool) — not needed for this use case
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
```

Full state reset. Followed by `UNIT_AURA` with `isFullUpdate = true`.

---

### Event Registration Pattern

Follow the existing TBT registration style in `Core.lua`:

```lua
-- Add to the event registration block in Core.lua:
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Add to the OnEvent dispatch:
elseif event == "UNIT_AURA" then
  ns:OnUnitAura(...)
elseif event == "PLAYER_REGEN_ENABLED" then
  ns:OnRegenEnabled()
elseif event == "ZONE_CHANGED_NEW_AREA" then
  ns:OnZoneChanged()
```

---

### AuraFilters Reference

String constants from `AuraUtil.AuraFilters` (pass as string literals):

| Filter | Meaning |
|--------|---------|
| `"HELPFUL"` | Buffs only |
| `"HARMFUL"` | Debuffs only |
| `"PLAYER"` | Cast by the player |
| `"HELPFUL\|PLAYER"` | Player-cast buffs only |
| `"CANCELABLE"` | Buffs the player can cancel |

For TBT scanning the player's own tracked buffs: `"HELPFUL"` covers all player buffs regardless of caster. Use `"HELPFUL|PLAYER"` if TBT only wants to cancel timers for self-cast buffs (which is the typical TBT use case — you cast the spell, it starts a timer, you want to cancel when it ends).

---

### What NOT to Use

| API | Reason |
|-----|--------|
| `UnitBuff(unit, index)` | Deprecated pre-Midnight; replaced by C_UnitAuras APIs |
| `UnitDebuff(unit, index)` | Same — deprecated |
| `UnitAura(unit, index, filter)` | Deprecated; use `C_UnitAuras.GetAuraDataByIndex` |
| `C_UnitAuras.GetUnitAuras(unit, filter)` | Returns bulk table with `ConditionalSecretContents`; harder to reason about per-entry than querying each tracked spell directly |
| `addedAuras` as cancellation signal | For cancelling timers, read `removedAuraInstanceIDs` (always safe) or use full-scan via `GetPlayerAuraBySpellID`. Never use `addedAuras` for removal logic |
| `COMBAT_LOG_EVENT_UNFILTERED` | Disabled in Midnight (CLAUDE.md constraint) |
| `RegisterEvent("UNIT_AURA")` without unit filter | Fires for all units; use `RegisterUnitEvent("UNIT_AURA", "player")` |

---

### Recommended Flow for BuffEngine.lua

```lua
-- ns.auraCheckBlocked = false  (initialized in Core.lua namespace)

function ns:OnUnitAura(unit, updateInfo)
  -- Step 1: Check if aura data is restricted
  if C_Secrets.ShouldAurasBeSecret() then
    ns.auraCheckBlocked = true
    return  -- do not cancel any timers; data is unreliable
  end

  -- Step 2: Full update — rescan everything
  if updateInfo and updateInfo.isFullUpdate then
    ns:ScanAndCancelStaleTimers()
    return
  end

  -- Step 3: Incremental update — check for removals
  if updateInfo and updateInfo.removedAuraInstanceIDs then
    -- removedAuraInstanceIDs is NeverSecretContents, always safe
    -- If TBT stores auraInstanceID per timer, cancel directly here
    -- Otherwise, a full scan is the safe fallback
    ns:ScanAndCancelStaleTimers()
  end
end

function ns:ScanAndCancelStaleTimers()
  for spellID, _ in pairs(ns.activeTimers) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura == nil then
      ns.activeTimers[spellID] = nil
    end
  end
  if ns.UpdateDisplay then
    ns:UpdateDisplay()
  end
end

function ns:OnRegenEnabled()
  ns.auraCheckBlocked = false
end

function ns:OnZoneChanged()
  ns.auraCheckBlocked = false
end
```

The `ScanAndCancelStaleTimers` approach is safe even on full updates because it queries each tracked spell specifically rather than relying on incremental diff data.

---

### Sources (v0.2.1 Research)

All findings verified against `C:\Users\jonat\Repositories\wow-ui-source`:

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` — C_UnitAuras function signatures, SecretWhenUnitAuraRestricted flags, RequiresNonSecretAura flags
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitConstantsDocumentation.lua` — UnitAuraUpdateInfo struct (isFullUpdate, removedAuraInstanceIDs, addedAuras, updatedAuraInstanceIDs field definitions and secret tags)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` — C_Secrets namespace, ShouldAurasBeSecret signature and documentation string
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua` — issecretvalue global function signature
- `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` — AuraUtil.ForEachAura implementation, AuraUtil.AuraFilters, PLAYER_REGEN_ENABLED cache dump pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` — RegisterUnitEvent("UNIT_AURA", "player", "target"), OnUnitAura handler pattern, removedAuraInstanceIDs/addedAuras access pattern
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua` — GetPlayerAuraBySpellID usage, aura.spellId field name (lowercase 'd' confirmed)
- `Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua` — RegisterUnitEvent("UNIT_AURA", "player") registration pattern, updateInfo field access
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` — PLAYER_REGEN_ENABLED event (no payload)
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua` — ZONE_CHANGED_NEW_AREA event (no payload)

---

## v0.2.0 Stack: CDM Tab Integration, Edit Mode, Drag-and-Drop

**Researched:** 2026-03-28
**Confidence:** HIGH (all findings verified directly from Blizzard UI source)

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

### Integration Patterns

#### CDM Tab Integration

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
tbtTab.activeAtlas = "icon_trackedbuffs"
tbtTab.inactiveAtlas = "icon_trackedbuffs"
tbtTab.tooltipText = "TBT Buffs"
-- Anchor below last existing tab
local lastTab = CooldownViewerSettings.TabButtons[#CooldownViewerSettings.TabButtons]
tbtTab:SetPoint("TOP", lastTab, "BOTTOM", 0, -3)
table.insert(CooldownViewerSettings.TabButtons, tbtTab)
```

#### Drag-and-Drop within TBT Settings Panel

CDM implements drag as a **manual drag-follow pattern**, not WoW's native pickup/cursor system:

1. `OnDragStart` or `OnMouseUp(LeftButton)` — call `BeginOrderChange(item)` on the settings frame.
2. `BeginOrderChange` creates a ghost frame parented to `GetAppropriateTopLevelParent()`, sets an `OnUpdate` on the main settings frame to reposition it each frame.
3. Ghost frame's `OnUpdate` calls `GetScaledCursorPositionForFrame(topLevel)` and `SetPoint("TOPLEFT", ...)`.
4. Main settings frame registers `GLOBAL_MOUSE_UP`. On `LeftButton` up: commits move. On `RightButton` up: cancels.

#### Edit Mode — Movable Containers

**Third-party addons cannot register with `Enum.EditModeSystem`** (verified: all `EditModeSystemTemplate` instances require a `system` KeyValue pointing to a server-backed enum entry).

**What third-party addons CAN do:**

```lua
EventRegistry:RegisterCallback("EditMode.Enter", function()
    tbtBarsHandle:Show()
    tbtBuffsHandle:Show()
end, addonKey)

EventRegistry:RegisterCallback("EditMode.Exit", function()
    tbtBarsHandle:Hide()
    tbtBuffsHandle:Hide()
    ns.db.barsAnchor = { GetPoint(tbtBarsContainer) }
    ns.db.buffsAnchor = { GetPoint(tbtBuffsContainer) }
end, addonKey)
```

---

### What NOT to Use (v0.2.0)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `UIDropDownMenu` / `UIDropDownMenuTemplate` | Deprecated since Dragonflight; non-functional in Midnight | `MenuUtil.CreateContextMenu` |
| `EditModeManagerFrame:RegisterSystemFrame(self)` | Requires valid `Enum.EditModeSystem` entry | `EventRegistry:RegisterCallback("EditMode.Enter/Exit")` + manual `StartMoving()` |
| `COMBAT_LOG_EVENT_UNFILTERED` | Disabled in Midnight | `UNIT_SPELLCAST_SUCCEEDED` (already used by TBT) |
| Storing active timer state in SavedVariables | Active timers are runtime-only; stale on reload | Runtime tables only |
| Hooking `CooldownViewerSettings:SetDisplayMode` | Replaces function globally | `hooksecurefunc` or `EventRegistry` callbacks |

---

### Sources (v0.2.0 Research)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua`
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua`
