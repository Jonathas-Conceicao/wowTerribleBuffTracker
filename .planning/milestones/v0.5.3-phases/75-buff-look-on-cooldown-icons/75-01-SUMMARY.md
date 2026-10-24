---
phase: 75-buff-look-on-cooldown-icons
plan: 01
subsystem: display
tags: [cooldown-viewer, swipe, charges, render-hot-path]
requires:
  - phase: 74-buff-duration-on-spell-cooldowns
    provides: "ns:CooldownBuffDuration, buff proc filed under the cooldown's own key, buff-duration preview"
provides:
  - "ApplySwipeLook(icon, aura): stamped CDM aura look (yellow, reverse false, no edge) vs TBT's dark cooldown look"
  - "ApplySlotCount(icon, entry): stamped charge/item count, shared by the timer branch and ApplyCooldownSlot"
affects: [76-bag-item-buffs, 78-in-game-verification]
tech-stack:
  added: []
  patterns: ["per-icon look stamp (_auraLook) that nils the sweep stamps so the owning branch re-issues SetCooldown"]
key-files:
  created: []
  modified: [Display.lua]
key-decisions:
  - "Buff look = Essential item template (reverse false) + ITEM_AURA_COLOR (1, 0.95, 0.57, 0.7), no edge; cooldown look unchanged"
  - "Count kept via option (a): ApplySlotCount on its own _cntGen/_cntKey stamps; _cdGen stays nil during the buff so ApplyCooldownHandle re-runs on handover"
  - "SetUseAuraDisplayTime not adopted (cannot be confirmed on Forever; TBT drives sweeps from typed durations)"
requirements-completed: [BUFFDISP-01, BUFFDISP-02, BUFFDISP-03, BUFFDISP-04, BUFFDISP-05]
duration: 15min
completed: 2026-10-22
---

# Phase 75 Plan 01: Buff Look on Cooldown Icons Summary

**A cooldown tracker's icon now shows its own buff in the CDM aura look: a full yellow fill (ITEM_AURA_COLOR, reverse false, no edge) that clears, in full colour. It switches back to TBT's dark cooldown sweep and grey as soon as the buff ends, and the charge or item count stays visible throughout.**

## Performance

- **Duration:** about 15 min
- **Completed:** 2026-10-22
- **Tasks:** 2/2
- **Files modified:** 1 (Display.lua)

## Accomplishments

- `ApplySwipeLook(icon, aura)` sits after `ClearCooldownStamps`. It is stamped on `_auraLook` and sets `SetReverse(not aura)`, the swipe colour (literal numbers) and `SetDrawEdge(not aura)`. On a change it nils `_lastStart`, `_userCdState` and `_cdGen` so the owning branch re-issues its sweep in the same pass. It never touches SetDrawSwipe or SetDesaturated.
- The live-timer branch asserts `ApplySwipeLook(icon, slotEntry and ns:CooldownBuffDuration(entry) ~= nil)`. This gates on the entry, so Buffs-tab, Reminders-tab and Trinket/Pot procs and a buff-off cooldown's preview demo all keep the dark look (BUFFDISP-05). `ApplyCooldownSlot` asserts `ApplySwipeLook(icon, false)` before `ApplyUserCooldown` and the generation block (BUFFDISP-02).
- `ApplySlotCount(icon, entry)` sits after `ApplyItemCount`. It is stamped on `_cntGen`/`_cntKey`, and it is now the only place ApplyCooldownSlot gets its count from, called before the `_cdGen` block so the chargeCapable ordering still holds.
- The live-timer branch handover for a cooldown-slot entry:
  - Another tracker's slot state gets the full `ClearCooldownStamps`.
  - The tracker's own buff starting drops only the sweep and the `_userCdState`/`_userCdGrey`/`_cdGen` stamps, and keeps the count.
  - Then it sets `_cdKey = entry.key` and `_lastStart = nil`, and calls `ApplySlotCount` every tick (a stamp compare on the steady path).
- `ClearCooldownStamps` also resets `_auraLook`, `_cntGen` and `_cntKey`.

## Task Commits

1. **Task 1: Stamped swipe-look helper** - `5af4adb` (feat)
2. **Task 2: Count survives the buff (ApplySlotCount)** - `688c31a` (feat)

## Files Created/Modified

- `Display.lua` - ApplySwipeLook, ApplySlotCount, timer-branch handover, ApplyCooldownSlot look/count calls, ClearCooldownStamps stamp resets, comment updates on the cooldown-slot branch

## Decisions Made

- I followed the plan's per-state look table, which comes from the CDM source (CooldownViewer.xml:48 vs :183, CooldownViewer.lua:20, :883-905).
- The count uses option (a). The handle re-issue depends on `_cdGen`, a stamp the timer branch never sets, so it does not depend on clearing logic that has to stay in sync.
- I reworded the Phase 47 comment on the cooldown-slot branch, which said the generation block branches ApplyChargeCount vs ApplyItemCount, to name ApplySlotCount. It was a comment-only accuracy fix.

## Intended Side Effect

- **A buff-off cooldown's preview demo now keeps its count visible.** Its demo proc goes through the live-timer branch like any proc filed under a cooldown slot's key. That branch now keeps the count for every cooldown-slot entry, while the look stays dark because `ns:CooldownBuffDuration` is nil. Before this plan, ClearCooldownStamps hid the count during the demo.

## Deviations from Plan

None. The plan was executed as written, apart from the one-line comment wording fix noted under Decisions.

## Verification

- The Task 1 and Task 2 automated gates print PASS (re-run after Task 2; Task 1's gate still passes).
- `stylua --check .`, `node scripts/aura-read-gate.js`, and `--selftest` (30 cases) all pass. Display.lua reports `w/crlf` and contains no `\r\r`.
- Only Display.lua changed. Core.lua, BuffEngine.lua, Providers.lua and CDMTab.lua are untouched.
- `./scripts/install.bat` deployed the addon to every client folder.
- The in-game checks (plan verification 1-7) are deferred to Phase 78 by user decision.

## Known Stubs

None.

## Next Phase Readiness

- Phase 76 (bag items) gets this for free: `ns:IsBagItemEntry` entries already answer true to `ns:IsCooldownSlotEntry`, and `ApplySlotCount` takes the `ApplyItemCount` route for them.

## Self-Check: PASSED

- Display.lua modified; commits 5af4adb and 688c31a present in `git log`.
