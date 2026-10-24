---
phase: 75-buff-look-on-cooldown-icons
reviewed: 2026-10-22T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - Display.lua
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 75: Code Review Report

**Reviewed:** 2026-10-22
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

Reviewed `git diff 47cfe7f..HEAD -- Display.lua`: `ApplySwipeLook`, `ApplySlotCount`, the timer-branch handover for cooldown-slot entries, the `ApplyCooldownSlot` look and count calls, and the extra resets in `ClearCooldownStamps`.

I traced each handover the brief named:

- **Cooldown to own buff (same key):** the `_cdGen ~= nil` arm clears the sweep and the user-cooldown stamps. `ApplySwipeLook(true)` nils `_lastStart`, so `SetCooldown` is reissued in the same pass, and `ClearIconDesaturation` writes false because `_desat` was left nil.
- **Own buff to cooldown:** `ApplySwipeLook(false)` changes the look and nils `_userCdState`/`_cdGen`. Both the user-owned and the engine-owned sweeps are reissued at once, and grey comes back through `_userCdGrey` (nil) or `ApplyCooldownGrey`.
- **Slot buff to Buffs-tab timer, and back:** this goes through `ClearCooldownStamps` (`_auraLook` nil), then `ApplySwipeLook(false)`, which nils `_lastStart`. The sweep is reissued in the dark look.
- **K1 buff to K2 buff:** a full clear, then the look is set again.
- **Placeholders and merged placeholders:** they draw no sweep, and their `ClearCooldownStamps` leaves `_auraLook` nil, so the next owner always sets the look again.
- **Buff-off preview demo:** the look stays dark. The `_lastStart` handover in `ApplyUserCooldown` still clears the demo sweep on close.

The invariant "`_auraLook == true` implies `_cdKey` is set" holds, so no widget can keep the yellow look without a stamp that forces it to be reset.

Other checks:

- **Upvalue order:** correct. `ApplySwipeLook` (898) and `ApplySlotCount` (1107) are declared before every caller.
- **Hot path:** no allocation is added. The new per-tick work is two `ns:` method calls and stamp compares.
- **Secret values:** no secret value is compared. `aura` comes only from DB fields, and the count goes through the existing `ApplyChargeCount` guards.
- **CDM fidelity:** the look matches the CDM source. That is `ITEM_AURA_COLOR` (CooldownViewer.lua:20), the Essential item Cooldown with no `reverse` (CooldownViewer.xml:48), `cooldownShowDrawEdge = false` and `cooldownDesaturated = false` (CooldownViewer.lua:883-905), and the count kept during the aura (:885-886).

Both warnings are icon-cache and stamp handovers that this phase's new slot-entry routing exposes. One is latent until Phase 76; the other predates the phase.

## Warnings

### WR-01: The timer branch's icon cache ignores `entry.iconOverride`, so a bag item's buff would draw the question mark and then keep it

**File:** `Display.lua:1745-1749` (interacting with `ApplyCachedIcon`, `Display.lua:839-846`)

**Issue:** Phase 75 routes every cooldown-slot entry's proc through the live-timer branch as a first-class state, with count and look kept. The SUMMARY says Phase 76 "gets this for free" for bag items. The timer branch still resolves its texture only from `timer.spellID`:

```lua
if icon.cachedSpellID ~= timer.spellID then
	icon.cachedSpellID = timer.spellID
	icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
end
```

A bag-item entry has `spellID = nil` and gets its icon only from `entry.iconOverride` (CDMTab.lua:204-214). Its buff proc (`ns:FillUserBuffProc` copies `entry.spellID`) or its buff-on preview proc (`spellID = info.spellID`) would therefore carry `spellID = nil`.

On any pooled widget whose `cachedSpellID` is not already nil (for example, it last drew a spell buff), the branch stores `ns:GetSpellIcon(nil)`, which is 134400 (BuffEngine.lua:766-768), and shows a question mark for the whole buff.

Worse, the cache is then wrong when the buff ends. `ApplyCachedIcon` sees `cachedSpellID == nil`, `cachedOverride == iconOverride` (the timer branch never touches `cachedOverride`), and a non-nil `cachedIcon`. It skips the refresh, so the bag item keeps the question mark as its cooldown icon until some other key reuses the widget.

The cache also breaks the other way. The timer branch changes `cachedSpellID`/`cachedIcon` without invalidating `cachedOverride`, so any override-carrying entry that goes back to `ApplyCooldownSlot` can be left with the timer branch's texture.

This is latent today, because nothing lets a bag item set `buffEnabled`. It becomes live with Phase 76, the very next phase, which this phase's SUMMARY says needs no Display work.

**Fix:** Route slot entries in the timer branch through `ApplyCachedIcon` with the entry's own identity, so the cooldown's icon stays during its buff, as in the CDM. Alternatively, invalidate the shared cache when the timer branch writes it:

```lua
if slotEntry then
	-- A cooldown's own buff keeps the cooldown's icon (CDM shows the item's icon during its aura).
	local sid = entry.spellID
	if type(sid) ~= "number" then
		sid = nil
	end
	ApplyCachedIcon(icon, sid, entry.iconOverride)
else
	if icon.cachedSpellID ~= timer.spellID or icon.cachedOverride ~= nil then
		icon.cachedSpellID = timer.spellID
		icon.cachedOverride = nil
		icon.cachedIcon = ns:GetSpellIcon(timer.spellID)
	end
	icon.icon:SetTexture(icon.cachedIcon)
end
```

### WR-02: `ApplyCooldownSlot` keeps the user-cooldown stamps when a pooled widget moves between keys, so K1 to K2 to K1 shows K2's sweep and grey on K1

**File:** `Display.lua:1157-1186`, `Display.lua:1223-1228`

**Issue:** The new timer-branch handover handles a key change correctly, because `_cdKey ~= entry.key` leads to a full `ClearCooldownStamps`. The new `_cntKey` stamp also follows the key. `ApplyCooldownSlot` does neither for `_userCdState`/`_userCdGrey`.

Trace with pool index *i*:

1. *i* draws K1, a user-owned running cooldown. The stamps become `_userCdState = t1` and `_userCdGrey = true`.
2. A slot-list change (a load-rule toggle or a spec swap reorders `slots`) moves *i* to K2, an engine-owned slot with `duration` 0 or unset. `ApplyUserCooldown` returns false at its first guard and leaves both stamps alone. The generation block (key mismatch) calls `SetCooldownFromDurationObject(K2)` and `ApplyCooldownGrey(K2)`.
3. *i* goes back to K1 while it is still running. `ApplySwipeLook(false)` does nothing (the look is unchanged). `_lastStart` is nil because the generation block cleared it, so the reset in `ApplyUserCooldown` at 1157 does not fire. `want == t1 == _userCdState`, so `SetCooldown` is skipped. `running == _userCdGrey`, so `SetDesaturated` is skipped.

K1 now draws K2's engine sweep and K2's grey state until K1's cooldown ends. This predates Phase 75, but it is the same pooled-handover surface this phase reworked, and the slot-key stamp handling is now asymmetric between the two branches.

**Fix:** Reset the user-cooldown stamps on a key change before `ApplyUserCooldown` runs, using the same rule as the timer branch:

```lua
-- in ApplyCooldownSlot, before ApplyUserCooldown
if icon._cdKey ~= entry.key then
	icon._userCdState = nil
	icon._userCdGrey = nil
end
local userOwned = ApplyUserCooldown(icon, entry, now)
```

## Info

### IN-01: The ordering comment overstates the coupling between `ApplySlotCount` and the generation block

**File:** `Display.lua:1216-1221`

**Issue:** The comment says "ApplySlotCount is stamped on the same generation, so it re-runs whenever the block does, and always before it." That is no longer true. The generation block also runs when `ApplySwipeLook` or the timer-branch handover nils `_cdGen`, and `ApplySlotCount` does not re-run then, because `_cntGen`/`_cntKey` still match. Behaviour is correct, because `chargeCapable` was already filled during the buff at that generation, but the comment is the stated reason for the ordering and will mislead the next edit.

**Fix:** Reword it, for example: "ApplySlotCount runs first on every pass; it does work whenever the generation or key moved, so chargeCapable is always filled for the current generation before the block below can ask for it."

### IN-02: `entry.spellID` is sanitised twice per cooldown-slot pass

**File:** `Display.lua:1114-1117` and `Display.lua:1194-1197`

**Issue:** `ApplySlotCount` repeats the `type(spellID) ~= "number"` check that `ApplyCooldownSlot` has already done. The cost is trivial, but there are now two copies of the same guard on the same field, which this phase introduced.

**Fix:** Pass the sanitised `spellID` into `ApplySlotCount(icon, entry, spellID)`, and have the timer branch sanitise it once at its call site.

---

_Reviewed: 2026-10-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
