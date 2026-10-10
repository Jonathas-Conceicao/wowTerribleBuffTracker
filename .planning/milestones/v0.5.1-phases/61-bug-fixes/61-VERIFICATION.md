---
phase: 61-bug-fixes
verified: 2026-09-30T00:00:00Z
status: human_needed
score: 6/6 must-haves verified in code (in-game behaviour deferred to Phase 66)
overrides_applied: 0
human_verification:
  - test: "Retail Mage, Merge Mode on, cast Prismatic Barrier"
    expected: "Buff sweep and charge number show together on the Essential/Utility cell; when the buff drops, the cooldown shows the correct count"
    why_human: "Frame-level draw order against the engine aura frame (+11/+12) cannot be proven by static reading"
  - test: "Idle charge spell, non-charge spell, racial stack count with Merge Mode off"
    expected: "Unchanged; charge/stack count still draws above the swipe (WR-03 resting level icon+2 replaced creation-order reliance)"
    why_human: "Same-level sibling ordering is client behaviour"
  - test: "Enter Edit Mode with Merge Mode on"
    expected: "Charge numbers do not draw over TBT's container highlight/selected overlay (after the queued mirror pass)"
    why_human: "Runtime frame-level rendering"
  - test: "Edit Mode: select a Blizzard system, then click a TBT container"
    expected: "TBT selects on mouse-down, overlay shows, TBT popup opens on top of Blizzard's dialog; no taint/blocked-action errors in Blizzard Edit Mode"
    why_human: "Taint absence and popup stacking are only observable in game"
---

# Phase 61: Bug Fixes Verification Report

**Phase Goal:** Selecting a TBT container in Edit Mode no longer reaches into Blizzard's Edit Mode, and a merged charge spell reads "buff time left, N charges" at once, as the CDM's own icon does.
**Status:** human_needed (all code-level truths verified; in-game checks deferred to Phase 66 by design)
**Re-verification:** No (initial)

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ns:SelectContainer no longer calls any Edit Mode method, pcall deleted not replaced | VERIFIED | EditModeFrames.lua function body read: only guard, deselect, comment, overlay Show, ShowSettingsPopup. `grep ClearSelectedSystem\|selectedSystem\|HideSystemSelections *.lua` finds nothing in shipped files. |
| 2 | Selection still mouse-down, overlay + popup as before | VERIFIED | Body retains `selectedContainer = which`, `overlay:Show()`, `ns:ShowSettingsPopup(which)`; comment cites 999.9 and accepted cost. |
| 3 | No TBT code calls an EditModeManagerFrame / Edit Mode mixin method (final state after review fixes) | VERIFIED | Grep of all .lua: only Config.lua:415 `pcall(ShowUIPanel, EditModeManagerFrame)` (global fn), MergeMode.lua:1302 `:IsShown()` (widget read), EditModeFrames.lua:680 anchor target/737 comment, `owner:GetFrameLevel()`/`owner:IsShown()` (widget getters), the rest comments. `popup:Raise()` (EditModeFrames.lua:547) is on TBT's own frame. tools/TBTProbe references are throwaway and unshipped. |
| 4 | Root cause diagnosed before fix and reference scan recorded | VERIFIED | 61-02-SUMMARY.md "Root cause (999.17)" at line 19; 61-01-SUMMARY.md "Edit Mode reference scan (999.9)" at line 27; Display.lua comment block present. |
| 5 | Charge count drawn above engine aura frame while engine path active; CDM rule (show whenever charges) unchanged | VERIFIED (code) | Display.lua:1123 `CHARGE_OVER_AURA_LEVEL = ns.MERGE_AURA_CONTAINER_LEVEL + 3` (MergeMode.lua:1360 = 10, used at 1644/1691, so +13 over aura +11/Cooldown +12); SetChargeCountRaised at 1130; ApplyCooldownSlot dirty-checked stamp at 1713 outside generation block, called from cooldown-slot branch with overAura=true (2577) and false for item-backed tracked buffs (2496); reset in ClearCooldownStamps (1164). Declared above both callers. |
| 6 | ApplyChargeCount / ApplyMergedAuraCooldown unchanged, no new aura reads, no hot-path allocation, non-merged/Edit Mode unaffected | VERIFIED | md5 of both functions equal the plan's invariants (e499e5..., 6c771d...). `aura-read-gate` PASS (10 reads, 3 readers), selftest PASS (30). Raise gated on `overAura and isMerged and mergeAuraGroupsActive`; one comparison per tick. |

**Score:** 6/6 code-level truths verified.

## Review-fix pass (final state)
WR-01 (`SetupAuraFrame` with/without Applications; Essential/Utility use InitializeCooldownAuraFrame, MergeMode.lua:1396-1529, 1731), WR-02 (overAura param), WR-03 (CHARGE_REST_LEVEL at Display.lua:483/577, re-level only on leaving raised), WR-04 (popup:Raise), IN-01 (shared ns.MERGE_AURA_CONTAINER_LEVEL, TOC load order puts MergeMode before Display per review) all present in the code. Note: WR-01 is a visible behaviour change (Essential/Utility merged aura no longer shows a stack number), matching CDM templates; MergeMode.lua was touched by this pass beyond the plans' original file list but consistent with the phase goal.

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| EDM-08 | 61-01 | SATISFIED (code); game confirmation deferred | Truths 1-3 |
| STEAL-09 | 61-02 | SATISFIED (code); game confirmation deferred | Truths 5-6 |

No orphaned requirements: REQUIREMENTS.md maps only EDM-08 and STEAL-09 to Phase 61, both claimed. (Checkboxes/traceability still show Pending; the orchestrator should tick them.)

## Anti-Patterns
No TBD/FIXME/XXX markers in Display.lua, EditModeFrames.lua, MergeMode.lua. `stylua --check .` clean. All three files are `w/crlf`.

## Human Verification Required
See frontmatter: four in-game checks (Prismatic Barrier repro, resting draw order with Merge Mode off, Edit Mode overlay stacking, Blizzard-dialog/TBT-popup click sequence and taint absence). These are deferred to Phase 66, so they are not gaps.

## Gaps Summary
None. Both goals are implemented and wired in code; the fixes cannot be proven without the game client.

---
_Verified: 2026-09-30_
_Verifier: Claude (gsd-verifier)_
