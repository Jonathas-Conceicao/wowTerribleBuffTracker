---
phase: 61-bug-fixes
plan: 02
subsystem: display
tags: [merge-mode, charges, frame-level, STEAL-09]
requires: ["61-01"]
provides:
  - "Charge count drawn above the engine aura frame while ns.mergeAuraGroupsActive"
key-files:
  modified: [Display.lua]
decisions:
  - "999.17: raise chargeCount frame level to container+13 only while the engine aura path is active; dirty-checked on icon._chargeRaised"
requirements-completed: [STEAL-09]
completed: 2026-09-30
---

# Phase 61 Plan 02: Merge Mode charge count Summary

## Root cause (999.17)

Suspect 2 is the cause: the engine-drawn aura frame covers the icon's `chargeCount`.

- MergeMode.lua:1355 `AURA_HOST_KEYS = { "buffs", "essential", "utility" }`, so Essential and Utility entries get an engine AuraContainer. MergeMode.lua:1618 and :1665 set it to `host:GetFrameLevel() + 10` on the same cell.
- TBT's icon is a child of the container, and `chargeCount` is a child Frame of the icon (Display.lua:564), so it sits at about container+2. The count was set and shown, only drawn under the aura frame (+11) and its Cooldown (+12).

Suspect 1 is ruled out: `ApplyChargeCount` is called at Display.lua ApplyCooldownSlot inside the `_cdGen` block but outside the aura-ownership guard, so it runs on every generation change whoever owns the sweep. `ApplyMergedAuraCooldown` never touches `chargeCount`. The CDM rule (`RefreshSpellChargeInfo`) shows the count with no aura condition, which TBT's sticky `chargeCapable` already matches.

## Fix

- `CHARGE_OVER_AURA_LEVEL = 13` and `SetChargeCountRaised(icon, raised)` added above `ClearCooldownStamps` (with the diagnosis comment).
- `ApplyCooldownSlot`: inline stamp test `icon._chargeRaised ~= (ns.mergeAuraGroupsActive == true)`, outside the generation block. One comparison per cooldown icon per tick.
- `ClearCooldownStamps`: `SetChargeCountRaised(icon, false)` so a pooled widget leaving a cooldown slot is lowered again.
- `ApplyChargeCount` and `ApplyMergedAuraCooldown` are byte-identical (md5 invariants match). MergeMode.lua untouched. No new aura reads.

## Verification

- stylua --check pass; `git ls-files --eol Display.lua` w/crlf.
- aura-read-gate: PASS (10 reads in 3 allowlisted readers); selftest PASS (30 cases).
- `./scripts/install.bat` deployed to retail, ptr, beta, classic_beta.

## Phase 66 in-game checklist

- Retail Mage, Merge Mode on, cast Prismatic Barrier: buff sweep and charge number show together; when the buff drops, the cooldown shows the correct count.
- A non-charge spell and an idle charge spell look unchanged.
- In Edit Mode, charge numbers do not draw over TBT's container highlight.

Known, out of scope: a spell with charges and aura applications above 1 would put both numbers at BOTTOMRIGHT (-2, 2). Prismatic Barrier has no applications.

## Deviations from Plan

Tasks 1 and 2 edit adjacent code and were committed together in one commit instead of two. Plan-checker notes applied: constant and block placed above the `ClearCooldownStamps` doc comment; assumption comment about the icon frame level added to the helper.

## Self-Check: PASSED
