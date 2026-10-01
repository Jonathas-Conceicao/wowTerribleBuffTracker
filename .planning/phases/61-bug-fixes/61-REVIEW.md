---
phase: 61-bug-fixes
reviewed: 2026-09-30T12:44:09Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - EditModeFrames.lua
  - Display.lua
findings:
  critical: 0
  warning: 4
  info: 2
  total: 6
status: fixed
fixed_at: 2026-09-30
fixes:
  WR-01: f1de738
  WR-02: b1ded50
  WR-03: d059f1c
  WR-04: 7f03cca
  IN-01: 7c073e1
  IN-02: b1ded50
---

# Phase 61: Code Review Report

**Reviewed:** 2026-09-30T12:44:09Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** fixed (all four warnings and both infos, 2026-09-30; in-game check deferred to Phase 66)

## Summary

Scope: `git diff e759919 -- EditModeFrames.lua Display.lua`. That covers the removal of the `ClearSelectedSystem` pcall from `ns:SelectContainer` (EDM-08) and the `SetChargeCountRaised` / `CHARGE_OVER_AURA_LEVEL` raise of `icon.chargeCount` over MergeMode's engine aura container (STEAL-09).

Checks that came back clean:
- **Upvalue order:** `CHARGE_OVER_AURA_LEVEL` and `SetChargeCountRaised` are declared at Display.lua:1107-1118. That is above both callers, `ClearCooldownStamps` (1139) and `ApplyCooldownSlot` (1671).
- **Hot path:** the per-tick cost is one boolean comparison. Nothing is allocated per frame.
- **Secret values:** no new aura, charge or secret read was added.
- **Line endings:** CRLF in the working tree, and no CRCRLF.
- **Leftover calls:** no other `EditModeManagerFrame` mixin call remains in TBT. The only reference left is a plain `IsShown` read in MergeMode.lua:1302.

The EDM-08 deletion is correct as written. The problems are in what the charge-count raise also reaches:
- The raised count now shares a corner with the engine aura frame's own stack count.
- The raise also applies to the item-backed Tracked Buffs tiles, which the fix was not scoped to.
- The "lowered" path now re-levels every cooldown icon onto a frame level shared with its Cooldown and dispel-border siblings. The file itself calls the draw order of those siblings load-bearing.
- On the Edit Mode side, the accepted-cost note does not mention one thing. Blizzard's settings dialog and TBT's popup share strata and frame level, and (per TBT's own comment) the same anchor, so they will overlap exactly.

## Warnings

### WR-01: Raised charge count collides with the engine aura frame's stack count on the same corner

**File:** `Display.lua:1107-1118` (interacts with `MergeMode.lua:1433-1437`)
**Issue:** `InitializeAuraFrame` registers an engine-filled Applications FontString on every engine aura frame:
- `NumberFontNormal`, anchored `BOTTOMRIGHT, -2, 2`.
- It is shown whenever applications > 1.

TBT's `chargeCount.Current` uses the same font and the same anchor (`CreateTimerIcon`, Display.lua:566-568). Before this change the aura frame covered the charge count completely, so only the stack number was visible. At +13 the count now draws on top of the stack number at the same pixel position. On an Essential/Utility cell whose spell has charges and whose aura stacks, the two digits overlap and neither can be read.

The CDM does not have this collision. `CooldownViewerEssentialItemTemplate` and `CooldownViewerUtilityItemTemplate` have a `ChargeCount` frame and no `Applications` frame (CooldownViewer.xml:54, :123; Applications exists only on the BuffIcon and BuffBar templates at :195, :237). So the claim in the comment at Display.lua:1103-1104, that TBT "already matches" the CDM rule, holds for the charge count alone, not for what now renders on the cell.
**Fix:** Make the cell match the CDM: one count per corner.
- Preferred: register `SetApplicationCount` only for aura containers hosted on the Tracked Buffs container. Essential/Utility hosts would then match the CDM templates, which have no Applications. `SyncEntryContainers` already knows the host. Pass a flag through to the `initializeFrame` choice (for example, two initializer functions).
- Alternative: keep both counts and move the raised charge count to a different corner while it is raised. This departs from the CDM and is the weaker option.

**Resolution: FIXED in f1de738 (preferred option).** `InitializeAuraFrame` became `SetupAuraFrame(frame, withApplications)` with two binders, `InitializeBuffAuraFrame` (true) and `InitializeCooldownAuraFrame` (false). `RefreshMergeAuraGroups` picks one per host key and passes it to `SyncEntryContainers`. Tracked Buffs aura frames are built exactly as before, so nothing changes there. Essential/Utility aura frames no longer register an Applications FontString, which matches the CDM Essential/Utility templates (`RefreshSpellChargeInfo` is the only count they show). The initializer is fixed at container creation. A re-parent only moves Essential and Utility, which share an initializer, because the CDM keeps aura and cooldown cooldownIDs apart. Visible change: an Essential/Utility merged aura with more than one stack no longer shows the stack number. The CDM's own cells never showed it.

### WR-02: Raise also applies to item-backed Tracked Buffs tiles, contradicting the stated scope

**File:** `Display.lua:1686-1692` (reached from `Display.lua:2472-2476`)
**Issue:** The `engineDrawsHere and entry.isMerged` branch calls `ApplyCooldownSlot` for a trinket or potion tracked buff (`entry.equipSlot or entry.spellCategoryID`). That branch only runs while `ns.mergeAuraGroupsActive` is true, so these icons are always raised.

The effect is that the item count (`ApplyItemCount`, which writes into the same `chargeCount`) now draws on top of the engine's buff tile whenever the buff is up:
- Before: the buff tile covered the item icon completely. This matched the CDM's own buff icon, which shows no item count.
- Now: a potion stack count sits over the buff's duration display, and over its Applications text (same collision as WR-01).
- It also draws over the pandemic FX, which is at container+11.

This is a visible behaviour change on the Tracked Buffs container, which STEAL-09 does not cover. The comment at Display.lua:1105-1106 ("nothing else changes") is incorrect for this path.
**Fix:** Limit the raise to cooldown-container cells whose spell has charges, and never raise on the Tracked Buffs host. For example:
```lua
local raised = ns.mergeAuraGroupsActive == true and entry.isMerged == true
	and not ns:IsBagItemEntry(entry) and icon.containerKey ~= TRACKED_BUFFS_KEY
```
The last condition can equally be a parameter passed from the call site in the cooldown-slot branch. Also correct the comment.

**Resolution: FIXED in b1ded50.** Implemented as a parameter. `ApplyCooldownSlot(icon, entry, settings, now, overAura)` is called with `false` from the item-backed Tracked Buffs branch and `true` from the cooldown-slot branch. `raised = overAura == true and entry.isMerged == true and ns.mergeAuraGroupsActive == true`. This is narrower than suggested: non-merged cooldown entries never have an aura container on their cell, so they are never raised either. The header comment was corrected.

### WR-03: The "lowered" path re-levels every cooldown icon onto a frame level its siblings share, and the file relies on their order

**File:** `Display.lua:1115-1116`, `Display.lua:1145`, `Display.lua:1690`
**Issue:** `CreateTimerIcon` (Display.lua:532-536, :553-555) states that the charge count draws above the swipe because of creation order. Three children sit at the same level: `cooldown`, `dispelBorder` and `chargeCount`, all at icon+1. The comment calls this "load-bearing, not taste".

The change now calls `SetFrameLevel(icon:GetFrameLevel() + 1)` in cases where nothing was ever raised:
- On the first `ApplyCooldownSlot` of every fresh icon. `nil ~= false` holds, so the call runs even with Merge Mode off.
- On every `ClearCooldownStamps`.
- On every raise/lower round trip, which means each Edit Mode entry/exit and each open/close of the CDM settings window.

Calling `SetFrameLevel` re-inserts the frame among its same-level siblings. Whether it lands above or below the Cooldown then depends on the client, not on creation order. The invariant the file documents as load-bearing is now in the client's hands. Nothing in this phase verified it in game (UAT is deferred to Phase 66). If it loses, the charge count and the racial stack count sit under the swipe for every cooldown icon, including with Merge Mode off.
**Fix:** Make the resting order explicit, and only touch the level when leaving a raised state:
```lua
local CHARGE_REST_LEVEL = 2 -- above cooldown (+1) and dispelBorder (+1) by level, not by creation order
local function SetChargeCountRaised(icon, raised)
	if raised then
		icon.chargeCount:SetFrameLevel(icon:GetParent():GetFrameLevel() + CHARGE_OVER_AURA_LEVEL)
	elseif icon._chargeRaised then
		icon.chargeCount:SetFrameLevel(icon:GetFrameLevel() + CHARGE_REST_LEVEL)
	end
	icon._chargeRaised = raised
end
```
Also set the same `CHARGE_REST_LEVEL` once in `CreateTimerIcon`, so a raised-then-lowered icon ends up on exactly the level a new one starts on.

**Resolution: FIXED in d059f1c, as suggested.** `CHARGE_REST_LEVEL = 2` is declared above `CreateTimerIcon`, to respect the upvalue-order rule. `CreateTimerIcon` sets `chargeCount` to icon+2 and stamps `_chargeRaised = false`. `SetChargeCountRaised` re-levels only when entering or leaving a raised state. The CreateTimerIcon comment now notes that the order is set by level.

### WR-04: Blizzard's settings dialog and TBT's popup can now be shown together, at the same strata, level and anchor

**File:** `EditModeFrames.lua:168-172` (interacts with `EditModeFrames.lua:200, 211-212, 225`)
**Issue:** Removing `ClearSelectedSystem` is the right decision and should stay removed. Its consequence, though, goes beyond "Blizzard's yellow highlight and popup may stay".

TBT's popup is `DIALOG` / frame level `200`, and its header comment says it sits at `BOTTOMRIGHT -250, 200`, the "same as CDM's Edit Mode popup". `EditModeSystemSettingsDialog` is also `frameStrata="DIALOG" frameLevel="200"` (EditModeDialogs.xml:254).

So the sequence is: select a Blizzard system, then click a TBT container. Two dialogs of the same kind are now stacked on the same spot, and which one is on top is not defined. A player can then change a Blizzard system's setting while believing they are editing the TBT container. The accepted cost in 61-CONTEXT.md does not cover this.
**Fix:** A fix does not need a Blizzard mixin call. Either of these works:
- In `ns:ShowSettingsPopup`, call `tbtSettingsPopup:Raise()`. `Raise` is a widget method on TBT's own frame, not an Edit Mode mixin method.
- Offset TBT's popup when `EditModeSystemSettingsDialog:IsShown()`. That is a plain widget read, of the same kind MergeMode.lua:1302 already makes on `EditModeManagerFrame`.

Also record the overlap in the SelectContainer comment, so the "accepted cost" note is complete.

**Resolution: FIXED in 7f03cca (first option).** `ns:ShowSettingsPopup` calls `popup:Raise()` on TBT's own frame after `Show()`. No Blizzard Edit Mode, `EditModeManagerFrame` or `EditModeSystemSettingsDialog` method is called or read. The offset option was not taken. The popup is user-draggable and is anchored only once, at creation, so re-anchoring on every show would discard the player's drag. The overlap is recorded in the SelectContainer accepted-cost comment.

## Info

### IN-01: `CHARGE_OVER_AURA_LEVEL = 13` is a magic offset coupled to constants in another file

**File:** `Display.lua:1107`, `Display.lua:679`, `MergeMode.lua:1618, 1665`
**Issue:** The +13 only works because MergeMode places its aura container at host+10. It also assumes, without verifying in game, that the engine's aura frame and its Cooldown land at +11 and +12. `EnsurePandemicIconFX` repeats the same coupling with +11, and its comment cites stale line numbers (`MergeMode.lua:1410, :1457`; the calls are now at 1618 and 1665). If someone changes MergeMode's +10, both overlays silently drop back underneath.
**Fix:** Put a shared `ns.MERGE_AURA_CONTAINER_LEVEL = 10` in MergeMode.lua and derive both offsets from it (`+1`, `+3`). Refresh the line references in the comment.

**Resolution: FIXED in 7c073e1, as suggested.** MergeMode.lua loads before Display.lua (TOC order), so the file-level `CHARGE_OVER_AURA_LEVEL = ns.MERGE_AURA_CONTAINER_LEVEL + 3` is safe. The stale line references now name `SyncEntryContainers` instead.

### IN-02: Brief window at Edit Mode entry where the raised count sits above TBT's selection overlays

**File:** `Display.lua:1105-1106`
**Issue:** `EditMode.Enter` only queues the mirror refresh (`MergeMode.lua:2395-2402`). `ns.mergeAuraGroupsActive` stays true until that queued pass runs, and the icons lower on the render tick after it. Until then the count, at container+13, draws above `containerOverlays` and `containerSelectedOverlays` (+10/+11, EditModeFrames.lua:109, :135). The comment states this as an invariant, when it is only true eventually.
**Fix:** Change the comment to say "after the queued mirror pass". Alternatively, include `ns:IsMergePreviewState()` in the `raised` test, which makes the lowering immediate.

**Resolution: FIXED (comment option) in b1ded50.** It was folded into the WR-02 comment rewrite. The comment now says the icons lower on the render tick after the queued mirror pass. The behavioural option was not taken: it would add a per-tick function call to the hot path to close a window of one or two frames.

---

_Reviewed: 2026-09-30T12:44:09Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
