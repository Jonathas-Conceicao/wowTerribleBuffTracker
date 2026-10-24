---
phase: 79-buff-countdown-display-fix
reviewed: 2026-10-24T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - Display.lua
findings:
  critical: 0
  warning: 0
  info: 4
  total: 4
status: issues_found
---

# Phase 79: Code Review Report

**Reviewed:** 2026-10-24
**Depth:** standard
**Files Reviewed:** 1 (Display.lua, commit cbc4008)
**Status:** issues_found (info only)

## Summary

The commit adds `ApplyCountdownFormat(icon, auraTime)` (Display.lua:937-948) and calls it from two places: the `elseif timer then` branch with `true` (:1814) and `ApplyCooldownSlot` with `false` (:1241). I traced every path that draws a sweep and every path that hands a pooled icon from one branch to another. I found no correctness bug, no path that issues a sweep without first setting its format, and no new way for the code to raise an error.

**Sweep coverage.** Display.lua has only three sweep writers: `SetCooldown` at :1818 (timer branch), `SetCooldown` at :1208 (`ApplyUserCooldown`) and `SetCooldownFromDurationObject` at :1054 (`ApplyCooldownHandle`). A grep of every `*.lua` file found no other `"Cooldown"` frame, `SetCooldown` or `CooldownFrame_Set`. The :1818 writer always runs after `ApplyCountdownFormat(icon, true)`. The other two are reachable only through `ApplyCooldownSlot`, and both run after `ApplyCountdownFormat(icon, false)`. The placeholder branch (:1838), `ShowMergedPlaceholderIcon` (:1599), the re-anchor branch and the fail-closed `isMerged` arm only `Clear()` or hide the icon. They do not need the format.

**Pooled-icon handover.**
- **Cooldown to buff (same key).** The Phase 75 block (:1771-1782) clears the sweep and nils `_lastStart`. `ApplyCountdownFormat(true)` then flips the stamp and nils the stamps again, and :1816 issues the sweep. On the next tick `_cdGen` is nil and `_cdKey` matches, so the Clear does not repeat.
- **Buff to cooldown.** The flip to `false` nils `_userCdState` and `_cdGen`. `ApplyUserCooldown` therefore issues its sweep or Clear again, and the generation block (:1273) runs again to call `ApplyCooldownHandle`.
- **Different key, or a non-slot timer on an icon that holds slot state.** `ClearCooldownStamps` runs first, and the format flip then forces the sweep to be issued again.

`_auraTime` changes only inside the helper. The helper is the only code that calls the widget setter, and nothing outside Display.lua touches `icon.cooldown`. So the stamp cannot fall out of step with the widget on Midnight.

**Hot path.** On the steady path the cost is one field compare per drawn icon per tick in each branch. There is no call, no allocation and no closure. A format flip costs one C call plus the existing sweep re-issue, and it happens only on a real change of branch.

**Comments.** The Blizzard line citations check out against wow-ui-source:
- :877 and :895 set `cooldownUseAuraDisplayTime = true` in the aura arms.
- :924 sets it to false.
- :1150 calls `SetUseAuraDisplayTime` just before `CooldownFrame_Set` at :1151.
- :1397 is `CooldownViewerBuffIconItemMixin:OnLoad`.

The claim "Blizzard's buff icon relies on Clear() not resetting the format" also holds. `CooldownViewerBuffIconItemMixin:RefreshCooldownInfo` (:1411-1426) alternates between `CooldownFrame_Set` and `CooldownFrame_Clear` and never sets the flag again. The small inaccuracies are listed under Info.

**The one-off "flask showed no timer after /reload" report.** Nothing in this diff plausibly causes it:
- **Errors.** `icon.cooldown` exists on every icon. All icons come from `GetIcon` and then `CreateTimerIcon` (:538), and `ApplyCooldownSlot` and the timer branch receive only those pooled icons, never Blizzard's re-anchored frames. The method lookup is guarded. The argument is a literal boolean, so the `AllowedWhenUntainted` rule (which applies to secret arguments only) cannot trip. The diff adds no new way for the code to raise an error.
- **State after /reload.** /reload rebuilds every frame, so each Cooldown widget starts in its default format and `_auraTime` starts nil. The first draw always calls the setter and nils the sweep stamps. Nothing carries over the reload.
- **Stamp order.** On both call sites the format is applied, and the stamps nilled, before the branch's own `_lastStart` / `_userCdState` / `_cdGen` test. A nil can only cause the sweep to be issued again, never to be skipped. The diff only removes skip conditions.
- **Branches that do not issue a sweep again.** The branches that skip the call (placeholder, merged placeholder, re-anchor, hidden) issue no sweep at all. When such an icon later goes through either sweep branch, that branch's own call flips the stamp, or finds it already correct, before it draws.

If that state recurs, look at the code this diff did not touch:
- whether `timersByContainer` held the flask's timer on the first passes after the reload;
- `ApplyIconStyle`'s `SetDrawSwipe(settings.timerShown)`, in case settings were not cached yet;
- a raise in an earlier container under the render `xpcall` (Display.lua:2028ff). With Lua errors off it would skip the remaining containers for that pass, silently.

A `GetUseAuraDisplayTime()` / `GetCooldownTimes()` dump on the affected icon would separate the format from the sweep.

The cooldown preview demo now counts down in the aura format. CONTEXT D-01 decided that explicitly, so it is not a finding.

## Narrative Findings (AI reviewer)

## Info

### IN-01: ApplyUserCooldown's "the timer branch drew here" guard can no longer fire

**File:** `Display.lua:1182-1195`
**Issue:** `ApplyCooldownSlot` now calls `ApplyCountdownFormat(icon, false)` (:1241) before `ApplyUserCooldown` (:1262). The timer branch sets `_lastStart` (:1817) only after `ApplyCountdownFormat(icon, true)` has set `_auraTime = true`. As a result, every icon that reaches :1192 with `_lastStart ~= nil` has `_auraTime == true`. The flip at :1241 has already nilled `_lastStart` and `_userCdState`, so the `if icon._lastStart ~= nil` block is unreachable. This holds on Forever too, because the stamp flips even when the method is missing.

The ten-line comment above it still describes this block as the mechanism that ends a preview sweep. In fact, the timer-to-cooldown handover is now carried silently by the format stamp. Behaviour is correct today. The risk is that a later change to `ApplyCountdownFormat` (for example, dropping the stamp nils because "the format does not need a re-issue") would quietly reopen the stuck-preview-sweep bug, while this comment claims the bug is still guarded here.
**Fix:** Do not refactor it (pre-existing code, PROJECT.md "No refactors during cleanup phases"). Add one comment line at :1192, or in the `ApplyCountdownFormat` header, saying that the `false` flip in `ApplyCooldownSlot` also covers this handover and that the guard is kept as a second line of defence. That makes the coupling visible.

### IN-02: Generation-block comment lists the stamp-nilling sources incompletely

**File:** `Display.lua:1269-1270`
**Issue:** "The block can also re-run on its own, when ApplySwipeLook or the timer-branch handover nils _cdGen". `ApplyCountdownFormat` now also nils `_cdGen`, and on a dark-look buff-to-cooldown handover it is the only one that does: `ApplySwipeLook(icon, false)` does not flip there, because `_auraLook` was already false.
**Fix:** `-- ApplySwipeLook, ApplyCountdownFormat or the timer-branch handover nils _cdGen; ...`

### IN-03: "keeps matching the widget's real state" does not hold on a client without the method

**File:** `Display.lua:934-936`
**Issue:** On a client without `SetUseAuraDisplayTime` (the guarded Forever case), `_auraTime` still records the requested value, but the widget has no such state. The stamp then tracks the request, not the widget. This is harmless, since it only causes a sweep re-issue on each real branch change. The comment, however, states something the guard makes untrue on Forever.
**Fix:** Reword it to "...so the stamp keeps matching the last value requested of the widget (its real state wherever the method exists)."

### IN-04: The AllowedWhenUntainted sentence suggests that the plain-boolean stamp is what permits the call

**File:** `Display.lua:931-932`
**Issue:** "`auraTime` is a plain boolean TBT passes in, never a game value, so the stamp compare is secret-safe and the AllowedWhenUntainted call is allowed." `SecretArguments = "AllowedWhenUntainted"` restricts only secret arguments passed by tainted code. Non-secret arguments are always allowed, so the call is allowed because the argument is not secret. The stamp compare plays no part. The current wording links two unrelated facts, and a future reader could take the stamp to be a security guard.
**Fix:** Reword it to "`auraTime` is a plain boolean TBT passes in, never a game value: the stamp compare is secret-safe, and a non-secret argument is allowed for tainted code under AllowedWhenUntainted."

---

_Reviewed: 2026-10-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
