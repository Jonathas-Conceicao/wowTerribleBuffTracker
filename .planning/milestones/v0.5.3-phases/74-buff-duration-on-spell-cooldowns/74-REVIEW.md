---
phase: 74-buff-duration-on-spell-cooldowns
reviewed: 2026-10-22T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - CDMTab.lua
  - Core.lua
  - Providers.lua
  - BuffEngine.lua
  - Display.lua
findings:
  critical: 1
  warning: 2
  info: 5
  total: 8
status: issues_found
---

# Phase 74: Code Review Report

**Reviewed:** 2026-10-22
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Reviewed the Phase 74 Lua diff (`094e619..HEAD`): the greyed-field capability and the three buff fields in CDMTab.lua, `ns:CooldownBuffDuration` / `ns:CooldownBuffAuraID` in Core.lua, `ns:StartCooldownBuffFromCast` and its OnTrigger call in Providers.lua, the end-on-cast, preview and edit-off changes in BuffEngine.lua, and the comment-only Display.lua change. I traced the callees too: `FillUserBuffProc`, `AcquireAliveBuffs`, `ScanActiveTimersForCancellation`, `GetActiveTimers`, `RebuildRankIndex`, the `RenderIconContainer` timer and cooldown branches, `ClearCooldownStamps` / `ApplyUserCooldown`, and the dialog's `RefreshState` / `ValidateAll` / confirm read.

Checks that passed:
- Every new aura read still goes through `ns:ReadPlayerAura`, and `node scripts/aura-read-gate.js` passes.
- No new secret value is compared or concatenated.
- Every new helper is either on `ns` or a file-local declared above its users (`ApplyFieldEnabled`, `CarriesCooldownBuff`, `BuffFieldEnabled`), so the upvalue-order trap does not apply.
- The cast path allocates nothing new.
- The timer-to-cooldown handover on the icon re-asserts correctly through `ClearCooldownStamps` and the `_lastStart` reset in `ApplyUserCooldown`.
- The saved keys are not in `ENGINE_OWNED`, and missing keys read as off.

Main defect: the buff's watch list overwrites the rank family on WoW Forever. A cooldown buff cast at any rank other than the saved one is cancelled about 0.6 s after the cast. Secondary issues:
- A cooldown reset now also ends a buff whose aura may still be up, which contradicts the phase's own "ends early only through the scan" note.
- The cooldown buff has no opt-out from aura-loss cancellation, even though 74-CONTEXT names `ns:CancelsOnAuraLoss` as part of the rule.

## Critical Issues

### CR-01: Cooldown buff drops the Forever rank family, so the timer is cancelled after the cast grace for any non-saved rank

**File:** `Providers.lua:236` (with `Core.lua:772-778`)
**Issue:** `ns:StartCooldownBuffFromCast` always overrides `proc.aliveBuffs` with a one-element list holding `ns:CooldownBuffAuraID(entry)`. When no buff Aura ID is typed, that list holds `entry.spellID`. On Forever, every user cooldown is created with "Cover all ranks" ticked by default (CDMTab.lua:2238/2248). `ns:RebuildRankIndex` builds `ns.rankFamilies[key]` for USER_CD owners (Core.lua:1714, 1778), so a cast of any rank resolves to the tracker through `ns.rankIndexCooldown`.

On Forever each rank's aura is its own spell ID (Core.lua:1139-1140; the WR-04 rule that `FillUserBuffProc` exists to honour). So when the player casts rank N:
1. The buff proc watches only the base or saved rank's aura ID.
2. `ns:QueueCastAuraRecheck` fires about 0.6 s later.
3. `ScanActiveTimersForCancellation` reads that ID as readably absent, and the grace has passed.
4. The buff timer ends.

The override also discards the family that `FillUserBuffProc` had just picked for exactly this case (Providers.lua:129). 74-CONTEXT requires "the same readable-only rule as user buff trackers", and user buff trackers keep the family. The TOC declares 16001, so Forever is a shipped flavour.
**Fix:** Keep the family when the Aura ID follows the Spell ID. When the Aura ID is typed, build a combined list at rebuild time, the way `ns.detailedRankFamilies` is built for buff-like owners. Keep it allocation-free on the cast path:
```lua
-- Providers.lua, StartCooldownBuffFromCast
local auraID = entry.buffAuraID
if type(auraID) == "number" and auraID > 0 then
    proc.aliveBuffs = (ns.cooldownBuffFamilies and ns.cooldownBuffFamilies[key])
        or ns:AcquireAliveBuffs(key, auraID)
else
    proc.aliveBuffs = (ns.rankFamilies and ns.rankFamilies[key])
        or ns:AcquireAliveBuffs(key, entry.spellID)
end
```
`ns.cooldownBuffFamilies[key]` is built in `ns:RebuildRankIndex` next to `detailedRankFamilies` (`{ buffAuraID, family... }`) for USER_CD owners with `coverAllRanks`. Add a Forever check to Phase 78 for this.

## Warnings

### WR-01: "Resets when you cast" now ends a cooldown's buff timer whose aura may still be up, and the module comment says this cannot happen

**File:** `BuffEngine.lua:1509-1513`; contradicting comment at `Providers.lua:202-204`
**Issue:** A cross-spell cooldown reset has nothing to do with whether the buff aura is still on the player. Cold Snap resetting a cooldown, or a proc that resets an ability, leaves the earlier cast's buff running. The new branch still deletes `ns.activeTimers[k]`, so the icon loses a buff that is genuinely active. 74-CONTEXT's only early-end rule is "the buff timer ends when its aura is read as gone ... Never on a secret read". The 74-02 summary attributes this behaviour to an "orchestrator decision", not to the user. The new Providers.lua header also says the buff "ends early only through ns:ScanActiveTimersForCancellation", which this branch makes false. So do `UpdateTrackedBuff` (BuffEngine.lua:1400), `SetBuffSection` to hidden, and `EndTrackerRuntime`.
**Fix:** Pick one of these:
- Drop the `activeTimers` removal from the USER_CD branch, so a reset ends only the cooldown and the buff is still governed by the aura scan.
- If the behaviour is wanted, confirm it with the user. Then rewrite the Providers.lua:202-204 bullet to list every way the buff can end (aura scan, the cross-spell reset, edit-off, hidden, unload or remove).

### WR-02: A cooldown's buff has no opt-out from aura-loss cancellation, so buffs that do not land on the player are killed about 0.6 s after the cast

**File:** `Providers.lua:235-236`; `CDMTab.lua:2304-2310` (keepOnAuraLoss stays buff-like only)
**Issue:** `aliveBuffs` is set unconditionally, and `keepOnAuraLoss` stays hidden for cooldowns. Some typed auras are never readably present on the player once the cast grace ends:
- an ally-targeted buff (Power Infusion, Blessing of Protection on someone else),
- a ground or totem effect whose aura ID differs,
- an Aura ID the user typed wrong.

Each time, the first readable absence ends the buff timer: out of combat, in the open world, or wherever auras are not secret. User buff trackers have "End when the aura is lost" for this case. 74-CONTEXT names `ns:CancelsOnAuraLoss` as part of the rule this timer follows, but the implementation bypasses it.
**Fix:** Pick one of these:
- Honour an opt-out. For example, show a "End when the aura is lost" checkbox under the buff fields, greyed with them, stored as `buffKeepOnAuraLoss`. Then:
  ```lua
  if not entry.buffKeepOnAuraLoss then
      proc.aliveBuffs = ... -- as in CR-01
  else
      proc.aliveBuffs = nil
  end
  ```
- Or record this explicitly as a user decision in 74-CONTEXT.

## Info

### IN-01: Cast path computes and discards work for the cooldown buff

**File:** `Providers.lua:232-236`
**Issue:** `FillUserBuffProc` already runs `CancelsOnAuraLoss`, `DetailedAuraID` and possibly `AcquireAliveBuffs(key, entry.spellID)`, which wipes and refills the pooled list. The override then wipes and refills the same pooled list again. When `entry.label` is nil it also builds `"Spell " .. tostring(id)`, a string on every cast. This is harmless today, but it is redundant work on the cast path.
**Fix:** Fold the CR-01 choice into a small `aliveBuffsOverride` parameter of `FillUserBuffProc`, or accept it with a comment.

### IN-02: Stale preview comment

**File:** `BuffEngine.lua:1536-1539`
**Issue:** "A cooldown entry previews from entry.duration like any other entry". Since lines 1566-1569, a cooldown with its buff on previews from `entry.buffDuration` instead.
**Fix:** Amend the comment to mention the Phase 74 exception.

### IN-03: Greyed follow-field still shows its secrecy badge and hover tooltip

**File:** `CDMTab.lua:1741-1767`
**Issue:** `ApplyFieldEnabled` dims `hover` and `name`, but not `state.badge`. The badge is parented to `row`, not `hover`, so it stays at full alpha. `hover` also keeps `EnableMouse(true)`, so a greyed Aura ID still raises its tooltip and still shows a full-strength secrecy warning.
**Fix:** Add `if state.badge then state.badge:SetAlpha(alpha) end`. Optionally add `state.hover:EnableMouse(enabled)`.

### IN-04: An edit that keeps the buff on does not refresh a running buff proc

**File:** `BuffEngine.lua:1398-1402`
**Issue:** Only the off case is handled. If the user edits `buffAuraID` or `buffDuration` while the buff runs, the live proc keeps the old pooled aura list and the old `expiresAt` until the next cast. This is minor, but a corrected Aura ID has no effect on the timer currently shown.
**Fix:** When the buff is still on, repoint `ns.activeTimers[newKey].aliveBuffs` through the same choice as CR-01. Otherwise, document the next-cast behaviour.

### IN-05: `ns:CooldownBuffAuraID` is not nil-safe, unlike its sibling

**File:** `Core.lua:772-778`
**Issue:** `ns:CooldownBuffDuration` guards `entry == nil`, but `ns:CooldownBuffAuraID` indexes `entry.buffAuraID` directly. Every current caller passes a non-nil entry. Phase 76 extends both helpers to bag items, though, and the asymmetry is a trap.
**Fix:** Add `if not entry then return nil end`.

---

_Reviewed: 2026-10-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
