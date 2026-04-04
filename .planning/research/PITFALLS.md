# Pitfalls Research

**Domain:** WoW addon — CDM tab integration, Edit Mode movable elements, drag-and-drop buff management, aura-based timer cancellation
**Researched:** 2026-03-28 (CDM/EditMode/DnD) | 2026-04-03 (aura cancellation v0.2.1)
**Confidence:** HIGH (CDM/EditMode sourced from Blizzard UI source) | MEDIUM (aura section sourced from Warcraft Wiki + Cell addon PR + Midnight dev docs)

---

## v0.2.1 Milestone: Aura-Based Timer Cancellation Pitfalls

This section covers pitfalls specific to adding `UNIT_AURA`-based buff detection to the existing `UNIT_SPELLCAST_SUCCEEDED` timer system in WoW Midnight (Interface 120000+), where `COMBAT_LOG_EVENT_UNFILTERED` is disabled and aura data is subject to secret value restrictions.

---

### Aura Pitfall 1: Lua Error on Comparison Against Secret `spellId` Field

**What goes wrong:**
`C_UnitAuras.GetAuraDataByIndex` returns an `AuraData` table marked `SecretWhenUnitAuraRestricted`. During restricted contexts (Mythic+ in progress, PvP match in progress, encounter in progress), the `spellId` field inside that table is a secret value — a black-box that cannot be compared, indexed, or used in arithmetic by untainted addon code. Attempting `auraData.spellId == trackedSpellID` will throw a Lua error: "attempt to compare a Secret Value".

**Why it happens:**
The natural approach is to iterate auras and compare `spellId` values against `ns.db.trackedBuffs`. This works out-of-combat but silently fails (with a Lua error, not a graceful nil) in restricted contexts.

**Consequences:**
Uncaught errors in event handlers cause the entire event handler to abort. Subsequent `UNIT_AURA` events will keep triggering and keep erroring, producing console spam and potentially tainting the UI frame stack.

**Prevention:**
Before using `auraData.spellId` in any comparison or table lookup, guard with `issecretvalue()`:

```lua
local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
if not auraData then break end
if issecretvalue(auraData.spellId) then
    -- entire aura slot is restricted — set blocked flag and abort scan
    ns.auraCheckBlocked = true
    return
end
if ns.db.trackedBuffs[auraData.spellId] then
    -- buff is present, mark it seen
end
```

**Detection:**
Error in chat: `attempt to perform arithmetic/comparison on a Secret Value` originating from BuffEngine.lua aura scan loop. Occurs only during M+, PvP, or boss encounters — never in open world, making it hard to reproduce in casual testing.

**Phase to address:** v0.2.1 core implementation. This guard must be present before any aura scan logic ships.

---

### Aura Pitfall 2: `C_Secrets` API Functions Are the Preferred Restriction Check

**What goes wrong:**
Patch 12.0.0 added explicit query functions for the restriction state:
- `C_Secrets.ShouldUnitAuraIndexBeSecret(unit, index, filter)`
- `C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)`
- `C_Secrets.ShouldSpellAuraBeSecret(spellID)`

Addons that use only `issecretvalue()` after the fact (checking after reading) rather than querying these functions proactively may read a partially-constructed AuraData table, where some fields are secret and others are not. This produces inconsistent state: `auraInstanceID` is `NeverSecret` and always readable, but `spellId`, `duration`, and `expirationTime` may be secret simultaneously, leading to code that appears to work but has silent gaps.

**Why it happens:**
`issecretvalue()` is well-documented; `C_Secrets.*` functions are newer additions that many tutorials do not cover.

**Prevention:**
Use `C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL")` as the first check per aura index. If it returns true, skip the index entirely — do not read any fields. This avoids the per-field secret check cascade and is the pattern consistent with Blizzard's own internal code.

**Phase to address:** v0.2.1 core implementation.

---

### Aura Pitfall 3: False Positive Timer Cancellation from `isFullUpdate` During Zone Transitions

**What goes wrong:**
`UNIT_AURA` fires with `updateInfo.isFullUpdate = true` during zone transitions and instance loads. At this point, the aura list for "player" may be temporarily empty or partially populated — the game is in the middle of reconstructing the unit's state. If the addon interprets `isFullUpdate = true` + empty aura scan as "all buffs have been removed" and cancels active timers, it will cancel timers for buffs the player actually still has (e.g., a 1-hour food buff that persists across zones).

**Why it happens:**
The natural implementation is: "if isFullUpdate, scan all auras and cancel timers for any tracked buff not found." This is logically correct in steady-state but wrong during the transient empty-aura window after a zone change.

**Consequences:**
Every zone change or instance entry cancels all active timers incorrectly. Players who cast a buff before a dungeon entrance lose the timer as they enter.

**Prevention:**
`PLAYER_ENTERING_WORLD` fires after every loading screen. Suppress aura-driven cancellations for a short window after `PLAYER_ENTERING_WORLD` fires, or gate `isFullUpdate` scans behind a readiness flag that is only cleared once the player is confirmed in-world. The existing `ns.displayInitialized` pattern in `Core.lua` can be extended for this purpose. Additionally, register `PLAYER_ENTERING_WORLD` as a timer-pause trigger — suspend aura cancellation logic, not the timers themselves, until the world is stable.

A simpler approach: **never cancel timers on `isFullUpdate`**. Only cancel on explicit `removedAuraInstanceIDs` entries. Use `isFullUpdate` only for resetting the aura instance ID cache (not for timer cancellation).

**Detection:**
Timers disappear every time the player crosses a zone boundary or enters a dungeon, even when buffs were active.

**Phase to address:** v0.2.1 core implementation — cancellation logic must be written to handle `isFullUpdate` correctly from the start.

---

### Aura Pitfall 4: Race Condition Between `UNIT_SPELLCAST_SUCCEEDED` and `UNIT_AURA`

**What goes wrong:**
When a player casts a spell that refreshes or re-applies a tracked buff, two events fire in close sequence:

1. `UNIT_SPELLCAST_SUCCEEDED` — TBT creates/overwrites the timer in `ns.activeTimers[spellID]`
2. `UNIT_AURA` — TBT scans auras; if the new aura application has not yet appeared in the aura list (or `isFullUpdate` is true while the game re-builds the aura table), TBT may conclude the buff is absent and cancel the timer that was just started

This creates a race where the cast succeeds, a timer is created, and then the aura scan immediately cancels it.

**Why it happens:**
`UNIT_SPELLCAST_SUCCEEDED` and `UNIT_AURA` both fire within the same event dispatch cycle but their relative order is not guaranteed to be stable in all cases, particularly for spells with instant application. The aura table is not necessarily updated before `UNIT_AURA` fires — the event signals "something changed" but the change may not yet be reflected if the scan happens in the same tick.

**Prevention:**
After `UNIT_SPELLCAST_SUCCEEDED` creates a timer, set a short-lived grace period flag on that spell: `ns.recentlyCast[spellID] = GetTime() + 0.5`. In the `UNIT_AURA` cancellation handler, skip cancellation for any spell whose `recentlyCast` entry is still valid. This is a standard pattern used by WeakAuras and similar addons to absorb the cast-to-aura lag.

```lua
-- In OnSpellCastSucceeded:
ns.recentlyCast[spellID] = GetTime() + 0.5

-- In aura cancellation scan:
if ns.recentlyCast[spellID] and GetTime() < ns.recentlyCast[spellID] then
    -- grace period: skip cancellation for this spell
else
    ns.activeTimers[spellID] = nil
end
```

**Detection:**
A tracked buff timer appears for a fraction of a second then immediately disappears after casting the spell.

**Phase to address:** v0.2.1 core implementation. The grace period must be wired before cancellation logic is written.

---

### Aura Pitfall 5: Blocking Logic Must Survive UI Reload and Addon Re-Init

**What goes wrong:**
The planned design caches a "blocked" flag (`ns.auraCheckBlocked`) when secret values are detected. This flag is runtime-only (not persisted). After a `/reload` in the middle of an M+ run, the flag is cleared — the next `UNIT_AURA` event will attempt a scan without the block in place, hit a secret value, error, and then re-set the block. This is one spurious Lua error per reload during restricted content.

The same issue applies if `PLAYER_REGEN_ENABLED` fires and clears the block during a brief lull between pulls within the same M+ key — the key is still "active" even out of combat, so aura data remains secret.

**Why it happens:**
`PLAYER_REGEN_ENABLED` fires when combat drops, but M+ and PvP restrictions are keyed on whether the *instance/match* is active — not on combat state. Out-of-combat during M+ still has secret aura values.

**Prevention:**
Use the correct reset trigger. `PLAYER_REGEN_ENABLED` is appropriate for raid encounter detection but NOT for M+ or PvP. For a safe reset:
- Clear blocked flag on `ZONE_CHANGED_NEW_AREA` (leaving the instance entirely)
- Clear blocked flag on `PLAYER_ENTERING_WORLD` with `isLogin = true` or `isReload = true`
- Do NOT clear on `PLAYER_REGEN_ENABLED` unless the design is limited to encounter-only blocking

Alternatively: clear only on `ZONE_CHANGED_NEW_AREA` and keep the block for the entire instance duration. If aura data becomes readable again (e.g., after an encounter ends and the key hasn't started the next one), re-test on the next `UNIT_AURA` event by checking `issecretvalue` on the first readable field, and only clear the block when a successful non-secret read occurs.

**Detection:**
Intermittent Lua errors during M+ between pulls or after `/reload` mid-run.

**Phase to address:** v0.2.1 blocked-flag logic. Must be designed with correct event triggers before implementation.

---

### Aura Pitfall 6: Full Aura Scan Per Event Is a Performance Problem

**What goes wrong:**
`UNIT_AURA` fires very frequently — on every buff tick, proc, DEBUFF application to any unit that the player has registered, and on haste/modifier changes affecting duration. A naive implementation that iterates all aura slots (`C_UnitAuras.GetAuraDataByIndex` in a loop up to 40+ slots) on every event creates significant per-event CPU cost that compounds in large encounters.

**Why it happens:**
The simple approach: "on UNIT_AURA, loop all auras, check if tracked buffs are present." This works but ignores the incremental update data the event provides.

**Prevention:**
Use the `updateInfo` payload to avoid full scans:

1. If `updateInfo.removedAuraInstanceIDs` is present, only cancel timers whose cached `auraInstanceID` matches entries in that list. No full scan needed.
2. If `updateInfo.addedAuras` is present, skip — TBT does not start timers from aura events, only from `UNIT_SPELLCAST_SUCCEEDED`.
3. Only perform a full scan when `updateInfo.isFullUpdate == true` (and even then, only when not in a grace period or zone transition).

This requires maintaining a mapping: `ns.activeTimers[spellID].auraInstanceID` — populated when the aura is first seen after a cast succeeds. Without this cache, `removedAuraInstanceIDs` cannot be used efficiently.

**Phase to address:** v0.2.1 core implementation. The `auraInstanceID` cache design must be established before writing the event handler.

---

### Aura Pitfall 7: `GetAuraDataByAuraInstanceID` Returns nil for Removed Auras

**What goes wrong:**
The Warcraft Wiki documentation explicitly states: "GetAuraDataByAuraInstanceID will not work on removed aura InstanceIDs." If TBT tries to confirm a removal by calling `C_UnitAuras.GetAuraDataByAuraInstanceID` after receiving a `removedAuraInstanceIDs` entry, the call returns nil — which is correct behavior but may be misinterpreted as "buff not found therefore not tracked" in code that also handles "never existed" nil returns.

**Why it happens:**
Code that calls `GetAuraDataByAuraInstanceID` to validate before cancelling may incorrectly interpret the nil as an error state rather than confirmation of removal.

**Prevention:**
When `removedAuraInstanceIDs` entries arrive, look them up in a locally-maintained reverse map (`ns.auraInstanceToSpellID`) rather than re-querying the API. The reverse map is built as auras are observed via `addedAuras` in prior events. This cache must handle stale entries (from zone transitions where the full aura list resets).

**Phase to address:** v0.2.1 core implementation — establish the reverse-map pattern before writing removal logic.

---

### Aura Pitfall 8: Aura Instance ID Cache Becomes Stale After `isFullUpdate`

**What goes wrong:**
After `isFullUpdate = true`, all previous `auraInstanceID` values are invalid — aura instance IDs are re-assigned. If TBT's reverse map (`ns.auraInstanceToSpellID`) is not cleared on `isFullUpdate`, it will contain stale mappings. A subsequent `removedAuraInstanceIDs` entry containing an instance ID that was re-used for a *different* aura could cause incorrect timer cancellation.

**Why it happens:**
The cache is built incrementally and developers forget that `isFullUpdate` is a full reset signal, not an additive update.

**Prevention:**
On every `isFullUpdate`, wipe the entire `auraInstanceToSpellID` reverse map before rebuilding from the current aura list. This is the correct steady-state behavior: treat `isFullUpdate` as "start over."

**Phase to address:** v0.2.1 core implementation — document the wipe-on-isFullUpdate contract in a comment.

---

### Aura Pitfall 9: Registering `UNIT_AURA` for All Units Instead of Just "player"

**What goes wrong:**
`eventFrame:RegisterEvent("UNIT_AURA")` fires for any unit whose aura changes — including party members, raid members, pets, and focus targets. If TBT registers without filtering, the `UNIT_AURA` handler fires far more often than necessary (every party member's buff tick) and the `unitTarget` argument must be checked first. Missing this check causes full aura scans for non-player units, wasting CPU and potentially reading the wrong unit's aura list.

**Why it happens:**
`RegisterEvent` without `RegisterUnitEvent` does not filter by unit. The event fires globally.

**Prevention:**
Use `eventFrame:RegisterUnitEvent("UNIT_AURA", "player")` instead of `RegisterEvent("UNIT_AURA")`. This limits firing to player-unit aura changes only. The existing pattern in `Core.lua` uses `RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")` with a unit check inside the handler — for aura scanning, unit-scoped registration is cleaner and cheaper.

**Detection:**
`UNIT_AURA` handler fires many times per second during group content, far more than expected from personal buff changes alone.

**Phase to address:** v0.2.1 — use `RegisterUnitEvent` from the start, not `RegisterEvent`.

---

### Aura Pitfall 10: Buffs in Section "hidden" Should Not Trigger Aura Scan

**What goes wrong:**
`ns.db.trackedBuffs` contains entries for all tracked buffs, including those in the `"hidden"` section. When aura scanning determines a buff is absent and calls cancellation, it iterates all tracked buff spell IDs including hidden ones. For hidden buffs, `ns.activeTimers[spellID]` will already be nil (they are never started per `OnSpellCastSucceeded` which early-returns on `section == "hidden"`), so the cancellation is a no-op — but the check still happens. More critically, if the cancellation logic calls `ns:UpdateDisplay()` after removing any timer, and hidden buffs are included in the scan, a display refresh may fire unnecessarily.

**Why it happens:**
The scan logic iterates `ns.db.trackedBuffs` without filtering by section, mirroring the display logic that does filter.

**Prevention:**
Mirror the guard in `OnSpellCastSucceeded`:

```lua
for spellID, entry in pairs(ns.db.trackedBuffs) do
    if entry.section ~= "hidden" and ns.activeTimers[spellID] then
        -- check aura presence
    end
end
```

Only check auras for buffs that have active timers — no active timer means nothing to cancel. This is the simplest and most efficient filter.

**Phase to address:** v0.2.1 — include section guard in first pass of cancellation logic.

---

## Phase-Specific Warning Summary for v0.2.1

| Phase Topic | Pitfall | Mitigation |
|-------------|---------|------------|
| Event registration | `RegisterEvent` instead of `RegisterUnitEvent` fires for all units | Use `RegisterUnitEvent("UNIT_AURA", "player")` |
| Secret value detection | `spellId` comparison throws Lua error in M+/PvP/encounter | Guard with `issecretvalue()` + `C_Secrets.ShouldUnitAuraIndexBeSecret` before any comparison |
| Blocked flag reset | `PLAYER_REGEN_ENABLED` clears block during M+ out-of-combat lull | Reset on `ZONE_CHANGED_NEW_AREA`, not combat drop; or only on confirmed non-secret read |
| Zone transition | `isFullUpdate` with empty aura list cancels all timers on zone change | Suppress cancellation on `isFullUpdate` within `PLAYER_ENTERING_WORLD` window |
| Cast/aura race | New timer cancelled by aura scan that fires before aura appears | Grace period (`recentlyCast[spellID]`) of ~0.5s post-cast |
| Performance | Full aura loop per event in large raids | Use `removedAuraInstanceIDs` for targeted cancellation; full scan only on `isFullUpdate` |
| Instance ID cache | Stale instance IDs after `isFullUpdate` cause wrong cancellations | Wipe `auraInstanceToSpellID` cache on every `isFullUpdate` |
| Removed aura lookup | `GetAuraDataByAuraInstanceID` returns nil for removed auras | Use local reverse map, not API re-query, for removal confirmation |
| Hidden section buffs | Aura scan runs on hidden buffs with no active timers | Skip entries where `ns.activeTimers[spellID]` is nil |
| UI reload mid-restricted | Block flag cleared on reload; first post-reload event errors | Design block detection to be triggered by first secretvalue read, not state from previous session |

---

## Integration Risks With Existing `UNIT_SPELLCAST_SUCCEEDED` System

The two event systems must coexist without interfering. Specific integration risks:

| Risk | Source | Prevention |
|------|--------|------------|
| Timer cancelled immediately after cast | `UNIT_AURA` fires before aura list updates, sees buff absent | Grace period flag on `ns.recentlyCast[spellID]` after each cast |
| Timer reset to wrong duration by aura data | If future code tries to sync timer to `expirationTime` from aura, it overwrites the cast-based timer | Milestone scope: only cancel, never update duration from aura — enforce in code review |
| `UpdateDisplay` called twice per cast | Cast creates timer + calls `UpdateDisplay`; aura scan confirms buff present and also calls `UpdateDisplay` | Aura scan should NOT call `UpdateDisplay` when taking no action (buff confirmed present) |
| `ClearAllTimers` during preview conflicts with aura blocking logic | `StartAllPreviewTimers` creates fake timers; aura scan may cancel them immediately if blocked flag is set | Preview mode should bypass aura cancellation entirely — check `ns.previewMode` guard |

---

## Sources

**Aura cancellation section (v0.2.1):**
- [UNIT_AURA — Warcraft Wiki](https://warcraft.wiki.gg/wiki/UNIT_AURA) — event arguments, `isFullUpdate`, `addedAuras`, `removedAuraInstanceIDs` structure (MEDIUM confidence — current official wiki)
- [C_UnitAuras.GetAuraDataByIndex — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataByIndex) — `SecretWhenUnitAuraRestricted` classification, `auraInstanceID` NeverSecret status (MEDIUM confidence)
- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) — `C_Secrets.ShouldUnitAuraIndexBeSecret`, `C_Secrets.ShouldUnitAuraInstanceBeSecret`, `C_Secrets.ShouldSpellAuraBeSecret` additions; `SecretWhenUnitAuraRestricted` predicate documentation (MEDIUM confidence)
- [New UNIT_AURA Processing Optimizations — Blizzard Forum](https://us.forums.blizzard.com/en/wow/t/new-unitaura-processing-optimizations/1205007) — `isFullUpdate`, `updatedAuras` payload design rationale, early-out optimization pattern (HIGH confidence — official Blizzard post)
- [WoW 12.0.0 Compatibility PR #457 — enderneko/Cell](https://github.com/enderneko/Cell/pull/457) — real-world `issecretvalue()` guard patterns, per-field non-secret checks for `spellId`/`duration`/`expirationTime`, `IsAuraNonSecret()` helper pattern (MEDIUM confidence — peer-reviewed addon code)
- [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes) — `SecretWhenUnitAuraRestricted` context (M+ active, PvP match, encounter in progress) (MEDIUM confidence)
- [How to Track Specific Buffs in Midnight — spiritbloom.pro](https://spiritbloom.pro/blog/tracking-buffs-in-midnight) — real-world limitations of aura field access during secret contexts; aura count workarounds (LOW confidence — third-party guide)

**CDM/EditMode/DnD section (v0.2.0):**
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.lua`
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.xml`
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua`
- `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`
- `TerribleBuffTracker/Display.lua`
- `TerribleBuffTracker/Core.lua`

---

## v0.2.0 Pitfalls (CDM Tab / Edit Mode / Drag-and-Drop)

*These pitfalls were researched for the v0.2.0 milestone and remain valid for ongoing development.*

---

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
| Skip `issecretvalue()` guard on aura spellId | Simpler aura scan loop | Lua error in every M+/PvP/encounter event, console spam, potential UI taint | Never |
| Use `PLAYER_REGEN_ENABLED` to clear aura block flag | Simple single-event reset | Block clears during M+ out-of-combat lulls; errors on next aura scan | Never — use zone change events |
| Full aura scan on every UNIT_AURA event | Simpler scan logic | CPU spike during large encounters; unnecessary work when only specific auras changed | Acceptable only as a temporary fallback behind an `isFullUpdate` guard |

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
| UNIT_AURA registration | `RegisterEvent("UNIT_AURA")` fires for all units | Use `RegisterUnitEvent("UNIT_AURA", "player")` to scope to player only |
| Aura secret value check | Compare `auraData.spellId` directly against tracked buff table | Guard with `issecretvalue(auraData.spellId)` before any comparison or table index |
| Aura cancellation on zone change | Cancel all timers when `isFullUpdate` fires after zone transition | Suppress cancellation during `PLAYER_ENTERING_WORLD` window; never cancel on `isFullUpdate` alone |
| Cast-to-aura ordering | Aura scan cancels timer immediately after `UNIT_SPELLCAST_SUCCEEDED` starts it | Grace period: skip cancellation for ~0.5s after cast succeeds |
| Aura block flag reset | Clear block on `PLAYER_REGEN_ENABLED` (combat drop) | Clear on `ZONE_CHANGED_NEW_AREA` or confirmed non-secret read; M+ is restricted out-of-combat too |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Running `SnapshotSettings()` inside CDM layout hooks after Edit Mode decouples containers | Containers teleport on every CDM change | Guard: skip CDM re-anchor if container is in Edit Mode position | Immediately after Edit Mode integration |
| `GLOBAL_MOUSE_UP` registered permanently | Drag completion fires on any mouse up across all UI | Register/unregister per drag session only | As soon as player clicks outside TBT UI during a drag |
| TBT tab `OnUpdate` running cursor tracking when no drag is active | Unnecessary work every frame | Set `OnUpdate` script only during drag; nil it at end | Low impact alone, but consistent with CDM's own pattern |
| Full aura scan on every `UNIT_AURA` event | CPU spike in raids; UNIT_AURA fires very frequently | Use `removedAuraInstanceIDs` for targeted removal; full scan only on `isFullUpdate` | Large group content with many buff changes per second |
| UNIT_AURA scanning non-hidden tracked buffs with no active timer | Extra iteration over entries that cannot produce a cancellation | Filter scan to `ns.activeTimers[spellID] ~= nil` first | Low cost per event but accumulates at high fire rate |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| New buffs added via Suggested section land directly in a visible section | Users see unexpected bars/icons appear immediately | New buffs land in "Not Displayed" first; user explicitly promotes to Tracked Buffs or Tracked Bars |
| CDM settings copy runs on every login instead of once | User's manual CDM position overrides are reset each session | Set a `cdmSettingsCopied` flag in DB after first copy; skip on subsequent loads |
| TBT tab does not restore the previously selected CDM tab (Spells vs. Auras) when dismissed | Disorienting for users who were on the Spells tab | Cache `CooldownViewerSettings.displayMode` before showing TBT tab; restore it when TBT tab is deselected |
| Delete drop zone always visible | Clutters the UI for users not in a drag session | Only show delete zone when a drag is active |
| Aura cancellation silently removes timers without any feedback | User notices timers disappear but does not know why | This is intentional correct behavior; no feedback needed unless debug mode is active |

---

## "Looks Done But Isn't" Checklist

- [ ] **CDM tab button:** Tab appears in the settings window AND clicking it shows TBT content AND deselecting it restores CDM scroll content AND `SetChecked` state matches selection — verify all four
- [ ] **Edit Mode elements:** Frames appear with selection handles AND dragging saves position AND `/reload` restores position AND "Reset Position" button works — verify all four
- [ ] **Drag-and-drop:** Drag picks up item AND cursor icon follows mouse across entire screen (not just within settings panel) AND dropping in a section updates the category AND cancelling (Escape/drop outside) restores original state — verify all
- [ ] **Migration:** Fresh install with no DB works AND existing v0.1 DB with tracked buffs is preserved AND all enabled/disabled states survive — verify all three scenarios
- [ ] **ConfigUI removal:** `/tbt` opens CDM to TBT tab AND Escape still closes UI panels AND no Lua error on `/tbt` — verify all three
- [ ] **CDM settings one-time copy:** Runs on fresh install AND does not run on second login AND does not run after user manually changes CDM settings — verify all three
- [ ] **Aura cancellation (v0.2.1):** Timers cancel correctly when buff expires early in open world AND no Lua errors occur in M+/PvP/encounter AND no timers cancelled during zone transitions AND cast grace period prevents immediate cancellation AND block flag correctly stays set for entire M+ key duration — verify all five

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
| Lua error on aura spellId comparison in M+ | LOW | Add `issecretvalue()` guard before comparison; 2-line fix per comparison site |
| Timers cancelled on every zone transition | MEDIUM | Wrap `isFullUpdate` cancellation in `PLAYER_ENTERING_WORLD` suppression window; requires careful event ordering |
| Block flag clears mid-M+ causing errors | LOW | Replace `PLAYER_REGEN_ENABLED` reset trigger with `ZONE_CHANGED_NEW_AREA`; 2-line change |
| Timer disappears immediately after cast | LOW | Add grace period flag on `ns.recentlyCast[spellID]`; 5-line addition |

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
| Secret value Lua error on aura spellId | v0.2.1 Phase 1: Event registration + scan core | Test in M+ or PvP content; verify no Lua errors in chat |
| False cancellation on zone change | v0.2.1 Phase 1: Cancellation logic | Cast a buff, enter instance, confirm timer persists through loading screen |
| Cast-to-aura race condition | v0.2.1 Phase 1: Cancellation logic | Cast tracked spell, confirm timer persists for full duration |
| Block flag reset with wrong event | v0.2.1 Phase 1: Block flag logic | Test M+ key active out-of-combat; confirm block stays set |
| Full scan performance | v0.2.1 Phase 1: Scan optimization | Profile in 25+ player raid; confirm no frame time spike on aura changes |
| Aura instance ID cache stale after isFullUpdate | v0.2.1 Phase 1: Instance ID cache | Zone change, confirm reverse map is rebuilt cleanly |

---
*Pitfalls research for: WoW addon CDM tab integration, Edit Mode movable elements, drag-and-drop, aura-based timer cancellation (v0.2.1)*
*Last updated: 2026-04-03*
