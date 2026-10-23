---
phase: 75-buff-look-on-cooldown-icons
verified: 2026-10-22T00:00:00Z
status: passed
score: 12/12 must-haves verified (5 roadmap success criteria + 7 plan truths)
overrides_applied: 0
deferred_to_phase_78:
  - test: "A userCd with its buff on: cast it"
    expected: "Full yellow fill that clears over the buff duration, icon in full colour, no edge, no cooldown sweep"
    why_human: "Visual rendering of a Cooldown widget; code-level trace done"
  - test: "Let the buff expire (or cancel it) while the cooldown still runs"
    expected: "The dark cooldown sweep with edge and a grey icon appear at once"
    why_human: "Real-time handover, needs the live client"
  - test: "Neither running; and a buff-off userCd"
    expected: "Full colour with no sweep; a buff-off userCd behaves exactly as before"
    why_human: "Visual"
  - test: "A charge spell with its buff on"
    expected: "Charge count stays visible during the buff and after it"
    why_human: "Depends on GetSpellCharges readability in the live client"
  - test: "Buffs-tab, Reminders-tab, Trinket and Pot icons"
    expected: "Dark swipe as before"
    why_human: "Visual regression check"
  - test: "Edit Mode / CDM settings preview"
    expected: "A buff-on cooldown previews yellow with its typed buff duration; a buff-off cooldown previews dark and now keeps its count"
    why_human: "Visual"
  - test: "Container 'Show Timer' off"
    expected: "The swipe is hidden in both looks"
    why_human: "Visual"
---

# Phase 75: Buff Look on Cooldown Icons Verification Report

**Phase Goal:** A cooldown tracker's icon shows its buff the way the CDM shows a cooldown entry's aura, and shows the cooldown again once the buff is gone.
**Verified:** 2026-10-22
**Status:** passed. Code-level verification is complete. The in-game checks are deferred to the Phase 78 retail pass by user decision.
**Re-verification:** No. This is the first verification.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 / BUFFDISP-01 | While the buff runs: yellow swipe (1, 0.95, 0.57, 0.7) that clears back to full colour, no edge, icon not grey, no cooldown shown | VERIFIED | Display.lua:1757 `ApplySwipeLook(icon, slotEntry and ns:CooldownBuffDuration(entry) ~= nil)` comes before the `_lastStart`/`SetCooldown(timer.startedAt, timer.duration)` block. ApplySwipeLook (:898-913) sets `SetReverse(false)`, `SetSwipeColor(1, 0.95, 0.57, 0.7)` and `SetDrawEdge(false)`, then nils `_lastStart` so the sweep is re-issued under the new look in the same pass. ClearIconDesaturation (:1753) keeps the icon in full colour. The timer branch comes first in the chain, so ApplyCooldownSlot does not run while the buff does and the cooldown is not shown. The handover's `cooldown:Clear()` (:1727) drops the running cooldown sweep. |
| SC2 / BUFFDISP-02 | When the buff ends or is cancelled while the cooldown still runs, the white-to-grey sweep and grey icon show at once | VERIFIED | The proc leaves activeByKey, so the next render takes the cooldown-slot branch and calls ApplyCooldownSlot. `ApplySwipeLook(icon, false)` (:1203) flips the stamp from true to false and re-asserts reverse true, black 0.7 and edge on. It also nils `_userCdState`/`_cdGen`. For a typed duration, ApplyUserCooldown re-issues `SetCooldown` and `SetDesaturated(running)` because the handover nilled `_userCdGrey`. For an engine-owned slot, `_cdGen` is nil, so the generation block re-runs `ApplyCooldownHandle`, which calls SetCooldownFromDurationObject and ApplyCooldownGrey. All of this happens in one pass. |
| SC3 / BUFFDISP-03 | Grey only while a cooldown shows and no buff does; with neither running, full colour and no sweep | VERIFIED | Only ApplyUserCooldown, ApplyCooldownGrey and ApplyCooldownHandle can grey the icon, and all three are reachable only from ApplyCooldownSlot, so only when no proc exists. The timer branch always calls ClearIconDesaturation. With neither running: `want=false` leads to `Clear()` and `SetDesaturated(false)` (existing behaviour, unchanged). ApplySwipeLook never calls SetDesaturated. |
| SC4 / BUFFDISP-04 | Charge or item count stays visible while the buff runs | VERIFIED | The timer branch calls `ApplySlotCount(icon, entry)` (:1733) for slot entries. When the tracker's own buff starts (same key), the handover leaves `chargeCount` shown and keeps `_cntGen`/`_cntKey` (:1722-1728). ApplySlotCount (:1107-1121) re-runs ApplyChargeCount/ApplyItemCount whenever the generation changes during the buff. |
| SC5 / BUFFDISP-05 | Buffs-tab, Reminders-tab and Trinket/Pot icons look exactly as today | VERIFIED | The look gate is `slotEntry and CooldownBuffDuration(entry) ~= nil`. `ns:IsCooldownSlotEntry` (Core.lua:582-590) is false for userBuff, userReminder and metaReminder, and for Trinket/Pot (META_ITEM with a non-numeric id, so no numeric itemID). Those timers get `ApplySwipeLook(false)`, which is the constructor look. A widget that carried the yellow look has `_cdKey` set, so ClearCooldownStamps runs and nils `_auraLook`, which forces the dark look to be re-asserted. |
| P1 | Look applies to the preview too | VERIFIED | BuffEngine.lua:1585-1588: the preview proc for a buff-on cooldown uses the typed buff duration and runs through the same timer branch. |
| P2 | Buff-off cooldown (and its preview demo) keeps the dark look | VERIFIED | `CooldownBuffDuration` is nil, so the gate is false. |
| P3 | Show Timer still applies to both looks; the helper never calls SetDrawSwipe | VERIFIED | ApplyIconStyle (:694) still owns SetDrawSwipe and runs in both branches. ApplySwipeLook has no SetDrawSwipe (gate-checked). |
| P4 | Only two non-comment SetReverse sites (constructor + helper) | VERIFIED | `grep` shows Display.lua:561 and :902 only. No other file touches the swipe colour, reverse or edge. |
| P5 | Look and count stamps reset when a pooled icon switches tracker | VERIFIED | ClearCooldownStamps (:858-869) nils `_auraLook`, `_cntGen` and `_cntKey`. A widget reassigned from another tracker's slot gets the full clear (:1719-1720). |
| P6 | Steady per-tick path is stamp compares only, with no allocation | VERIFIED | Steady buff tick: `_cdGen ~= nil` and `_cdKey ~=` compares, ApplySlotCount's two compares, and ApplySwipeLook's one compare. The colours are literals. There is no `{` in either helper (gate-checked). |
| P7 | Count updates on a generation change during the buff | VERIFIED | ApplySlotCount is stamped on `ns.cooldownGeneration`, independent of `_cdGen`. |

**Score:** 12/12

### CDM ground-truth comparison (wow-ui-source, read-only)

| Aspect | Blizzard | TBT | Match |
|--------|----------|-----|-------|
| Aura swipe colour | `ITEM_AURA_COLOR = CreateColor(1, 0.95, 0.57, 0.7)` (CooldownViewer.lua:20) | `SetSwipeColor(1, 0.95, 0.57, 0.7)` | Yes |
| Aura edge | `cooldownShowDrawEdge = false` (:891), passed through CooldownFrame_Set (:1150) | `SetDrawEdge(false)` | Yes |
| Aura desaturation | `cooldownDesaturated = false` for a player aura (:899-901) | ClearIconDesaturation | Yes |
| Aura reverse | Essential/Utility item `<Cooldown>` has no `reverse` (CooldownViewer.xml:48, :117) | `SetReverse(false)` | Yes |
| Charge count during aura | Kept ("keep the charge count display", :885-886) | ApplySlotCount in the timer branch | Yes |
| Buff-viewer look | `reverse="true"` with a 0,0,0,0.7 swipe (CooldownViewer.xml:183-185) | Constructor look kept for buff/reminder/meta | Yes |
| `SetUseAuraDisplayTime(true)` | Set in the aura state (:1146) | Not adopted (documented plan decision: Forever availability unconfirmed, and TBT drives the sweep from typed durations) | Deliberate divergence, not a gap |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Display.lua` ApplySwipeLook | Stamped look helper | VERIFIED | :898. Declared above both callers (upvalue order is safe). Wired at :1203 and :1757. |
| `Display.lua` ApplySlotCount | Stamped count helper | VERIFIED | :1107. Declared after ApplyItemCount and before ApplyCooldownSlot. Wired at :1221 and :1733. |
| `Display.lua` ClearCooldownStamps | Resets the new stamps | VERIFIED | :864-866 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| RenderIconContainer timer branch | ApplySwipeLook | `ApplySwipeLook(icon, slotEntry and ns:CooldownBuffDuration(entry) ~= nil)` before the `_lastStart` block | WIRED |
| ApplyCooldownSlot | ApplySwipeLook | `ApplySwipeLook(icon, false)` before `ApplyUserCooldown` | WIRED |
| RenderIconContainer timer branch | ApplySlotCount | `ApplySlotCount(icon, entry)` inside `if slotEntry` | WIRED |
| ApplyCooldownSlot | ApplySlotCount | Before the `_cdGen` block, so the chargeCapable ordering is kept | WIRED |
| Phase 74 buff proc / preview | Timer branch | Proc filed under the cooldown's own key in activeTimers/previewTimers (BuffEngine.lua:1585) | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Look boolean | `entry.buffEnabled` / `entry.buffDuration` | SavedVariables, type-checked in ns:CooldownBuffDuration | Yes | FLOWING |
| Buff sweep | `timer.startedAt` / `timer.duration` | Phase 74 proc (cast via UNIT_SPELLCAST_SUCCEEDED) or preview | Yes | FLOWING |
| Count | GetSpellCharges / ns:TrackedItemCount | Game API (guarded) / provider | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Plan Task 1 gate | Extracted `<automated>` from 75-01-PLAN.md | PASS | PASS |
| Plan Task 2 gate | Extracted `<automated>` from 75-01-PLAN.md | PASS | PASS |
| Aura-read gate | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)` | PASS |
| Gate self-test | `node scripts/aura-read-gate.js --selftest` | `AURA-READ SELFTEST PASS (30 cases)` | PASS |
| Formatting | `stylua --check .` | exit 0 | PASS |
| Line endings | `git ls-files --eol Display.lua`; `grep -c $'\r\r'` | `i/lf w/crlf attr/text eol=crlf`; 0 | PASS |
| Scope | `git diff 47cfe7f..HEAD --stat` | Display.lua plus the SUMMARY only | PASS |

### Probe Execution

There are no probes declared for this phase, and it is not a migration or tooling phase. Skipped.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| BUFFDISP-01 | 75-01 | SATISFIED | SC1 |
| BUFFDISP-02 | 75-01 | SATISFIED | SC2 |
| BUFFDISP-03 | 75-01 | SATISFIED | SC3 |
| BUFFDISP-04 | 75-01 | SATISFIED | SC4 |
| BUFFDISP-05 | 75-01 | SATISFIED | SC5 |

REQUIREMENTS.md maps exactly these five IDs to Phase 75, so no requirement is left unclaimed.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Display.lua (added lines) | none | No TBD/FIXME/XXX/TODO/HACK | none | none |
| Core.lua | 592-593 | Stale comment: says IsBagItemEntry is "narrower than ns:IsCooldownSlotEntry, which also answers true for trinket/pot". The two expressions are identical in the META_ITEM arm, and Trinket/Pot return false. This predates the phase. | Info | None at runtime. Candidate for the Phase 77 cleanup. |

### Intended behaviour change (noted, not a gap)

A buff-off cooldown's preview demo now keeps its charge or item count visible. Before, ClearCooldownStamps hid it. The SUMMARY documents this as intended.

### Deferred to Phase 78 (in-game, retail; user decision)

1. A userCd with its buff on: cast it. Expect a full yellow fill that clears, full colour, no edge and no cooldown sweep.
2. The buff expires or is cancelled while the cooldown runs. Expect the dark sweep with edge and a grey icon at once.
3. With neither running: full colour, no sweep. A buff-off userCd is unchanged.
4. A charge spell with its buff on keeps its charge count during the buff and after it.
5. Buffs-tab, Reminders-tab, Trinket and Pot icons keep the dark swipe.
6. Preview: a buff-on cooldown previews yellow with its typed buff duration; a buff-off cooldown previews dark.
7. Container "Show Timer" off hides the swipe in both looks.

### Gaps Summary

There are no code gaps. Every render path was traced at code level: buff start on the same key, buff start on a reused widget, the steady buff tick, a generation bump during the buff, buff end with a typed duration, buff end with an engine handle, buff end after the cooldown is done, preview open and close, and reassignment to a non-slot, placeholder or merged widget. Each one leaves the stamps consistent with the widget's real state and gives the look the CDM source specifies. What remains is visual confirmation, which is scheduled for Phase 78.

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
