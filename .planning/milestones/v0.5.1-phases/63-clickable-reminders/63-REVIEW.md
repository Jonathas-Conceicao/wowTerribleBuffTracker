---
phase: 63-clickable-reminders
reviewed: 2026-09-30T13:05:07Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - ReminderClick.lua
  - Display.lua
  - EditModeFrames.lua
  - CDMTab.lua
  - Providers.lua
  - TerribleBuffTracker.toc
findings:
  critical: 2
  warning: 5
  info: 6
  total: 13
status: fixed
fixed_at: 2026-09-30
fix_scope: critical_and_warning (+ IN-03, IN-04, IN-06 comment where the fixes shared their lines)
---

# Phase 63: Code Review Report

**Reviewed:** 2026-09-30T13:05:07Z
**Depth:** deep
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed `git diff 9f2440c` for the six files, plus all of the new `ReminderClick.lua`. I cross-checked against Blizzard's `SecureTemplates.lua`/`.xml` and `SecureStateDriver.lua` (wow-ui-source `live`) and against the call chains in Core.lua, BuffEngine.lua and CDMTab.lua.

The taint design holds:
- Overlays are parented and anchored only to UIParent.
- No TBT frame becomes protected.
- Every protected write (`SetPoint`/`SetSize`/`SetFrameStrata`/`SetFrameLevel`/`SetAttribute`/`Register|UnregisterStateDriver`/`Hide`/`CreateFrame`) is reachable only from `Flush`, which returns on `InCombatLockdown()`, or from the combat-gated `EditMode.Enter` callback.
- `PLAYER_REGEN_ENABLED` flushes before `SecureStateDriverManager` re-evaluates (its `OnEvent` only zeroes a timer), so a stale overlay is retired before the driver can re-show it.
- A `C_Timer.After(0)` that fires after combat starts lands in the same gate.
- The file-local order in Display.lua is correct: `clickStampedIn` and `ClearClickStamps` are declared above every caller.
- `ns:MarkReminderClicksDirty` is only reached at runtime, never during file load, so the TOC placing ReminderClick.lua after Display.lua is safe.
- The per-tick additions in `RenderIconContainer` are comparisons only.

Two defects stop the feature from working as specified. With the retail default CVar, a mouse click on the overlay never casts anything. An edited Cast spell ID does not reach the overlay. Five robustness gaps also leave overlays live, misplaced or missing in reachable situations.

## Critical Issues

### CR-01: Clicks never cast with the default `ActionButtonUseKeyDown=1`

**File:** `ReminderClick.lua:50`
**Issue:** The overlay registers only `LeftButtonUp`. Look at `SecureActionButton_OnClick` (SecureTemplates.lua:805-829). For an addon button the engine passes no `isKeyPress`/`isSecureAction`, so `isSecureMousePress` is falsy. That makes `useOnKeyDown = SecureActionButton_ShouldUseOnKeyDown(self)`, which falls back to the `ActionButtonUseKeyDown` CVar when the `useOnKeyDown` attribute is nil. The CVar defaults to on. Then `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)` is false for an up-click. `releasePressAndHoldAction` is also false unless `ActionButtonUseKeyHeldSpell` is on, so `OnClick` returns false and nothing is cast. The down-click that would satisfy the check is never delivered, because only `LeftButtonUp` is registered. This is the well-known post-10.0 addon breakage. It applies to retail and to the Forever beta, which runs the same modern SecureTemplates. CLICK-01 fails for every player on default settings; only players who turned the CVar off would get a cast.
**Fix:** Pin the attribute so the button fires on release whatever the CVar says (the usual button feel, and dragging off cancels):
```lua
overlay:RegisterForClicks("LeftButtonUp")
overlay:SetAttribute("useOnKeyDown", false)
overlay:SetAttribute("type1", "spell")
```
(The alternative, `RegisterForClicks("LeftButtonDown", "LeftButtonUp")`, also works under both CVar values, but it casts on press.)

**Resolution:** Fixed in 7823931. `CreateOverlay` sets `useOnKeyDown = false` once at creation (out of combat); `RegisterForClicks("LeftButtonUp")` kept.

### CR-02: Editing a reminder's Cast spell ID never reaches the overlay

**File:** `CDMTab.lua:2882`, `Display.lua:2738-2766`, `ReminderClick.lua:98-101`
**Issue:** The overlay's `spell` attribute is only rewritten inside `Flush`, and `Flush` only runs when `ns:MarkReminderClicksDirty()` is called. That happens only when an icon's click stamp changes (`_clickKey`/anchor/offsets/scale), on container release, or on the registered events. A castID-only edit goes through `ns:UpdateTrackedBuff` (BuffEngine.lua:1338). That keeps the same key (the key changes only with the spell ID) and changes neither layout nor scale, so no stamp moves and no flush runs. The overlay keeps its old `_castName` and a click casts the previous spell. This lasts until an unrelated layout change, Edit Mode exit, a UI scale change or a reload. It fails CLICK-06 as a user sees it. The same applies when a meta row's cast spell changes through `ApplyMetaReminderDef` on a rebuild, though only across builds.
**Fix:** Mark the overlays dirty whenever tracker data can change a cast spell. The simplest single point is after a successful edit or add in the dialog's confirm handler. A broader alternative is the end of `ns:RebuildCastIndex`, which runs on every tracker change:
```lua
local ok, reason = ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, readKeys)
if not ok then ... end
ns:RefreshTBTSections()
ns:StartAllPreviewTimers()
ns:MarkReminderClicksDirty() -- cast spell may have changed without any icon moving
dialog:Hide()
```

**Resolution:** Fixed in 12a4b6c with the broader option. The end of `ns:RebuildCastIndex` (Core.lua) marks the overlays dirty. `ns:UpdateTrackedBuff` reaches it via `ns:RebuildRankIndex`, and so do add, remove, migrations, world entry, SPELLS_CHANGED and meta-row re-application. The call is nil-guarded and coalesced by the existing `scheduled` flag.

## Warnings

### WR-01: Overlays go live during Blizzard Edit Mode when TBT's sidebar checkbox is off

**File:** `ReminderClick.lua:117`, `EditModeFrames.lua:748-750`, `EditModeFrames.lua:837-839`
**Issue:** `Flush` uses `ns.editModeActive` as its "Edit Mode is open" test. That flag means "TBT's Edit Mode behaviour is on", not "Blizzard Edit Mode is open". `OnEditModeEnter` sets it to false when `ns.db.tbtVisible == false`, and the sidebar checkbox's OnClick sets it to false while Edit Mode stays open. The sequence:
1. In Edit Mode, the user unticks the TBT sidebar checkbox.
2. `ns:UpdateDisplay()` runs with `iconEditing == false`.
3. The reminder icons are stamped, which marks the overlays dirty.
4. `Flush` sees `ns.editModeActive == false` and places overlays with active state drivers, all while Edit Mode is still open.

The same thing happens when a reminder appears during Edit Mode with the checkbox off. Those overlays can take the click, and the drag, meant for any Blizzard Edit Mode system frame beneath them, and a click casts a spell. The CONTEXT's Edit Mode rule ("overlays taken out of service when EditMode.Enter fires ... never swallow a drag") is broken.
**Fix:** Track Blizzard Edit Mode with a file-local flag set by ReminderClick's own callbacks, and test it in `Flush`:
```lua
local inBlizzardEditMode = false
EventRegistry:RegisterCallback("EditMode.Enter", function()
	inBlizzardEditMode = true
	...
end, eventFrame)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	inBlizzardEditMode = false
	ns:MarkReminderClicksDirty()
end, eventFrame)
-- Flush:
if not inBlizzardEditMode and not ns.editModeActive and ns.db ~= nil then
```

**Resolution:** Fixed in 323eeec. ReminderClick keeps a file-local `editModeOpen`, which only its own EditMode.Enter/Exit callbacks set. Enter sets it before the combat check, so a combat-deferred flush also stays out. No EditModeManagerFrame read or call.

### WR-02: Click stamps are container-relative, so a container resize can leave overlays misplaced

**File:** `Display.lua:2738-2769`, `Display.lua:2807-2826`
**Issue:** The stamp records `anchor`/`offsetMajor`/`offsetMinor`/`iconScale`, all relative to the container. Containers are anchored by BOTTOM (base defaults, EditModeFrames.lua:26-37) or CENTER (user containers), or by whatever point `StopMovingOrSizing` left. When the container's size changes, every icon moves on screen even if no stamp changes. One reachable case: while the CDM settings window is open (`ns.configOpen`), gate-false reminders join `slots` as placeholders. If they sort after the clickable ones, the clickable icons keep their offsets, but the container grows and re-centres on its anchor. No stamp changes, so no flush runs, and the overlays stay over the old cells. A click there can hit the wrong reminder or empty space. `SetClampedToScreen` pushing a grown container back on screen is a second case of the same gap.
**Fix:** Add the container's computed size to the dirty check. It is already calculated at the end of `RenderIconContainer`, so this needs no API call, only a compare against a cached value:
```lua
-- after computing the container size (w, h) at the end of RenderIconContainer:
if clickStampedIn[def.key] and (container._clickW ~= w or container._clickH ~= h) then
	container._clickW, container._clickH = w, h
	ns:MarkReminderClicksDirty()
end
```

**Resolution:** Fixed in 22658bd. `RenderIconContainer` computes the size it already calculated into locals, calls `SetSize` once, and caches it on the container. On a change it marks the overlays dirty, but only if the container carries stamps. That costs two number compares per tick and no API call. The flag became exact with IN-03 (4a2fa80).

### WR-03: A stamped icon that `Flush` skips is never retried

**File:** `ReminderClick.lua:119-129`, `Display.lua:2285`
**Issue:** `Flush` skips a stamped icon in three cases:
- `icon:IsVisible()` is false (`CollectReminderClickIcons`).
- `GetRect()` returns nil (`Place` returns false).
- The cast name does not resolve yet.

The stamp is still set, though, so nothing marks the overlays dirty again. Example: a reminder's buff drops while UIParent is hidden (Alt+Z, an in-game cinematic, a loading transition). The one-frame flush finds `IsVisible() == false` and retires the overlay. When the UI comes back no stamp changes, so the reminder stays unclickable until something unrelated re-dirties.
**Fix:** When `Flush` skips a stamped icon for any of these reasons, schedule a retry. For example, set `dirty = true` and hook UIParent's `OnShow` once (`UIParent:HookScript("OnShow", function() ns:MarkReminderClicksDirty() end)`), plus a short `C_Timer.After(1, FlushFromTimer)` retry for the GetRect-nil and uncached-name cases.

**Resolution:** Fixed in 34bdba0.
- `ns:CollectReminderClickIcons` now also returns the count of stamped-but-invisible icons.
- `Flush` counts every skip: invisible, `Place` false (nil or secret rect), cast name unresolved.
- On any skip, `Flush` schedules one `C_Timer.After(1)` retry. `retrySpent` bounds it to one per dirty edge (reset by the next `MarkReminderClicksDirty`), so a permanent skip costs one extra flush, never a loop.
- A `UIParent:HookScript("OnShow")` post-hook re-marks after Alt+Z or a cinematic.
- An unknown cast spell (WR-05) is deliberately not counted as a skip.

### WR-04: `GetRect` results are compared without an `issecretvalue` guard

**File:** `ReminderClick.lua:76-82`
**Issue:** CLAUDE.md requires game values to be guarded before comparison. `left, bottom, width, height` come straight from `icon:GetRect()` and are multiplied and compared (`overlay._left ~= left`). Under Midnight's secret-aspect rules, a frame whose layout picks up a secret aspect can return secret rect values. A compare against one throws inside `Flush`, which runs from a timer and from `PLAYER_REGEN_ENABLED`, and that aborts the whole flush, retire loop included. Stale overlays would then stay live.
**Fix:**
```lua
local left, bottom, width, height = icon:GetRect()
if not left or issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width) or issecretvalue(height) then
	return false
end
```

**Resolution:** Fixed in 67df9fe (stylua reflow in 75d157a). All four rect values are tested with `issecretvalue` before the nil test, so nothing compares a secret. Both effective scales are guarded the same way. A guarded icon counts as a WR-03 skip.

### WR-05: No known-spell check on the cast spell

**File:** `ReminderClick.lua:22-35`, `ReminderClick.lua:122-124`
**Issue:** `ResolveCastName` only checks that the client can name the spell, and `C_Spell.GetSpellInfo` answers for any spell in the client DB. A user reminder whose Cast spell ID is a spell this character does not know therefore gets a live, highlighted overlay, and every click raises the "unknown spell" UI error. CONTEXT listed the known-spell check as something to implement ("reuse the load rule's 'When known' helper if it fits"). It was not implemented and no deviation was recorded. Built-in rows are safe only because their load rule asks the same spell.
**Fix:** In `Flush`, skip the overlay unless `ns:ResolveSpellKnown(castID, false) == true`. It is rank-family aware, so any known rank passes on Forever. Out of combat only; the cost is paid on the dirty edge.

**Resolution:** Fixed in 830275e as suggested. `ns:ResolveSpellKnown(castID, false) ~= true` gives no overlay. Before world entry it answers false, and the PLAYER_ENTERING_WORLD mark re-flushes. A learned or lost spell re-marks through SPELLS_CHANGED, then `ns:RebuildCastIndex` (CR-02).

## Info

### IN-01: `ResolveCastName` duplicates existing name resolvers

**File:** `ReminderClick.lua:22-35`
**Issue:** It repeats the body of `ns:SpellPreview` (Core.lua:2478-2493) and the file-local `SpellName` (Core.lua:2672-2678), all of which do `pcall(C_Spell.GetSpellInfo)`, `CanReadTable`, then `issecretvalue(name)`. This duplication was introduced by this milestone.
**Fix:** Expose one `ns:SpellNameOrNil(spellID)` and use it in all three places, in the Phase 65 cleanup.

**Resolution:** Deferred to Phase 65 (out of fix scope).

**Phase 65:** Closed without a code change. The three resolvers are not the same function: `ResolveCastName` returns nil for an unreadable or empty name, which a cast attribute needs; `ns:SpellPreview` substitutes "Spell N" and an icon; Core's file-local `SpellName` skips `CanReadTable` and the empty-string check. The two in Core.lua predate the milestone and are protected, and moving `ResolveCastName` would not remove a copy.

### IN-02: The stamp-clear block is repeated three times in Display.lua

**File:** `Display.lua:150-161`, `Display.lua:2758-2764`, `Display.lua:2775-2781`
**Issue:** The same five-field nil-out appears in `ClearClickStamps`, in the per-icon `else` branch and in the trailing-pool loop.
**Fix:** Extract a `ClearClickStamp(icon)` that returns whether anything was cleared, and use it in all three places.

**Resolution:** Deferred to Phase 65 (out of fix scope).

**Phase 65:** Fixed in `aae99e5`. `ClearClickStamp(icon)` in Display.lua is used by all three sites, and the shared `ClearContainerClickStamps` covers the two identical stamped-container blocks.

### IN-03: `clickStampedIn` never clears on the visible path

**File:** `Display.lua:2767-2769`
**Issue:** The flag is set when any icon is stamped, but it is cleared only on the hidden/no-settings paths. If the last stamp clears while the container stays shown (reminder satisfied, Click to Cast turned off, Edit Mode), the flag stays true. A later hide then walks the pool and triggers one spurious flush. Harmless, but the comment's "one table read" contract is looser than it says.
**Fix:** Track a per-pass local `anyStamped` and assign `clickStampedIn[def.key] = anyStamped or nil` after the loop.

**Resolution:** Fixed in 4a2fa80 as suggested. It was pulled into scope because WR-02's size check reads this flag.

### IN-04: Dead guard `ns.CollectReminderClickIcons ~= nil`

**File:** `ReminderClick.lua:117`
**Issue:** Display.lua loads before ReminderClick.lua and defines it at file scope, so the guard is always true. It dates from 63-02 shipping before 63-03.
**Fix:** Remove it.

**Resolution:** Fixed in 4a2fa80. It shared the line that WR-01 edited.

### IN-05: `OverlayOnLeave` hides the tooltip even when another frame owns it

**File:** `ReminderClick.lua:44-46`
**Issue:** It hides `GameTooltip` unconditionally, while the new EditModeFrames hook correctly checks `GameTooltip:IsOwned(self)`.
**Fix:** `if GameTooltip:IsOwned(self) then GameTooltip:Hide() end`.

**Resolution:** Deferred to Phase 65 (out of fix scope).

**Phase 65:** Fixed in `aae99e5`. `OverlayOnLeave` hides the tooltip only when `GameTooltip:IsOwned(self)`.

### IN-06: The `EDIT_MODE_LAYOUTS_UPDATED` rationale is inaccurate, and the castID field copies auraID

**File:** `ReminderClick.lua:158-160`, `CDMTab.lua:2300-2417`
**Issue:**
- The comment says a layout or profile switch moves containers. TBT positions live account-wide in `ns.db.editModePositions` and are never re-applied on this event (`ApplyContainerPosition` runs only at init and at container creation), so the registration only adds a harmless flush.
- The castID field is a near-verbatim copy of the auraID field's build, reset, prefill, update, read and validate code. The summary already acknowledges this and defers it to Phase 65.

**Fix:** Correct the comment, or drop the event. Fold castID and auraID into a shared "follows Spell ID" field factory in Phase 65.

**Resolution:** The comment was corrected in 4a2fa80 and the registration kept, since it adds only a harmless flush. The castID/auraID field factory is deferred to Phase 65.

**Phase 65:** The castID/auraID part is fixed in `2c08f01`. Both fields are built by `BuildFollowSpellIDField`, and every difference between them is a parameter.

---

_Reviewed: 2026-09-30T13:05:07Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
