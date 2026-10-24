---
phase: 75-buff-look-on-cooldown-icons
fixed_at: 2026-10-22T00:00:00Z
review_path: .planning/phases/75-buff-look-on-cooldown-icons/75-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 2
skipped: 2
status: partial
---

# Phase 75: Code Review Fix Report

**Fixed at:** 2026-10-22
**Source review:** .planning/phases/75-buff-look-on-cooldown-icons/75-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (WR-01, WR-02, IN-01, IN-02)
- Fixed: 2
- Skipped: 2

## Fixed Issues

### WR-02: `ApplyCooldownSlot` keeps the user-cooldown stamps when a pooled widget moves between keys

**Files modified:** `Display.lua`
**Commit:** becc0ac
**Status:** fixed: requires human verification (a logic and state-handover change)
**Applied fix:** Before `ApplyUserCooldown`, `ApplyCooldownSlot` now nils `_userCdState` and `_userCdGrey` whenever `icon._cdKey ~= entry.key`. `_cdKey` still names the previous tracker at that point, because the generation block below is what moves it, so this follows the same key rule as the timer branch. When a widget goes K1, then K2, then back to K1, it re-issues K1's own `SetCooldown`/`Clear` and `SetDesaturated`. `_userCdGrey` being nil also resets `_desat` through the existing grey branch. No other stamp was needed: `_lastStart` and `_cdGen` are already handled by the generation block on a key change.

### IN-01: The ordering comment overstates the coupling between `ApplySlotCount` and the generation block

**Files modified:** `Display.lua`
**Commit:** 9995952
**Applied fix:** I reworded the comment. `ApplySlotCount` runs first on every pass and does work whenever the generation or key moved, so `chargeCapable` is filled for the current generation before the block asks for it. The block can also re-run on its own, after `ApplySwipeLook` or the timer-branch handover nils `_cdGen`, and the count is already current then.

## Skipped Issues

### WR-01: The timer branch's icon cache ignores `entry.iconOverride`

**File:** `Display.lua:1745-1749`
**Reason:** skipped (deferred to Phase 76). The orchestrator decided this: Phase 76's plan owns the live-timer icon fix for bag items. The bug stays latent until then, because nothing lets a bag item set `buffEnabled` yet.
**Original issue:** The timer branch takes its texture only from `timer.spellID`. A bag item's buff proc carries `spellID = nil`, so a pooled widget shows the 134400 question mark. The question mark then stays as the cooldown icon afterwards, because `ApplyCachedIcon` sees matching `cachedSpellID`/`cachedOverride` stamps.

### IN-02: `entry.spellID` is sanitised twice per cooldown-slot pass

**File:** `Display.lua:1114-1117` and `Display.lua:1194-1197`
**Reason:** skipped. There is no clean local change. The second check in `ApplySlotCount` sits inside its `_cntGen`/`_cntKey` stamp gate, so it runs only when the generation or key moves, not every pass. Hoisting it as suggested would mean the live-timer branch sanitises `entry.spellID` at its call site on every tick, which moves a stamped check into ungated per-tick work on the render hot path. The timer branch's own handover gate cannot stand in for it either, because `ApplySlotCount` also fires on a generation change that this gate does not see. The duplicate is two lines and costs nothing on the steady path.
**Original issue:** `ApplySlotCount` repeats the `type(spellID) ~= "number"` guard that `ApplyCooldownSlot` already applies.

## Verification

- `stylua .` made no changes. `Display.lua` reports `w/crlf` and contains no `\r\r`.
- `node scripts/aura-read-gate.js` passed, and so did `--selftest` (30 cases).
- `./scripts/install.bat` deployed to every client folder.

---

_Fixed: 2026-10-22_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
