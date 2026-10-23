---
phase: 74-buff-duration-on-spell-cooldowns
fixed_at: 2026-10-22T00:00:00Z
review_path: .planning/phases/74-buff-duration-on-spell-cooldowns/74-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 74: Code Review Fix Report

**Fixed at:** 2026-10-22
**Source review:** .planning/phases/74-buff-duration-on-spell-cooldowns/74-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (scope set by the orchestrator: CR-01, WR-01 comment only, WR-02 comment only, IN-01..IN-05)
- Fixed: 8
- Skipped: 0

Gates after the last fix: `stylua .` leaves no change, `node scripts/aura-read-gate.js` PASS, `--selftest` PASS (30 cases), and Core.lua, Providers.lua, BuffEngine.lua and CDMTab.lua all report `w/crlf`. No Lua interpreter is installed, so `stylua --check` (which parses each file) was the syntax tier. In-game checks are deferred to Phase 78.

## Fixed Issues

### CR-01: Cooldown buff drops the Forever rank family, so the timer is cancelled after the cast grace for any non-saved rank

**Files modified:** `Core.lua`, `Providers.lua`
**Commit:** 4aea96f
**Status:** fixed: requires human verification (logic change; Forever check belongs in Phase 78)
**Applied fix:**
- New `ns:CooldownBuffTypedAuraID(entry)` in Core.lua returns the typed buff Aura ID, or nil when the box follows the Spell ID. `ns:CooldownBuffAuraID` now uses it.
- New `ns:CooldownBuffAliveBuffs(key, entry)` in Core.lua makes the choice. With no typed ID it returns `ns.rankFamilies[key]`, else the pooled `{spellID}`. With a typed ID it returns `ns.detailedRankFamilies[key]`, else the pooled `{typedID}`. It does two table reads and allocates nothing.
- `ns:RebuildRankIndex` reuses the existing `detailedRankFamilies` mechanism and does not add a parallel table. A USER_CD owner with "Cover all ranks" and a typed buff Aura ID now gets `{ typedID, family... }` under its own key. The only other readers are `FillUserBuffProc`, gated on `ns:DetailedAuraID`, which is nil for cooldowns, and `RebuildReminderWatch`, which reads reminder keys only. Neither sees the new entries.
- `ns:StartCooldownBuffFromCast` uses `ns:CooldownBuffAliveBuffs`.

### WR-01: "Resets when you cast" now ends a cooldown's buff timer whose aura may still be up

**Files modified:** `Providers.lua`
**Commit:** c201cfb
**Applied fix:** The behaviour is kept, as the orchestrator decided. Only the Providers.lua header was corrected. It now lists every way the buff ends: the aura scan; the "Resets when you cast" reset (`ns:ApplyEndOnCast`); edit-off (`ns:UpdateTrackedBuff`); moving to hidden (`ns:SetBuffSection`); and unloading or removing the tracker.

### WR-02: A cooldown's buff has no opt-out from aura-loss cancellation

**Files modified:** `Providers.lua`
**Commit:** 0d47b4e
**Applied fix:** No code change, because this is a locked decision. A comment at the aliveBuffs assignment in `ns:StartCooldownBuffFromCast` says the buff follows the user-buff readable-only aura-loss rule with no opt-out. If a wrong or ally-only Aura ID ends the timer, the user corrects it in the Aura ID box.

### IN-01: Cast path computes and discards work for the cooldown buff

**Files modified:** `Providers.lua`
**Commit:** 978a98c
**Applied fix:** `ns:FillUserBuffProc` takes an optional fourth parameter, `aliveBuffsOverride`. When it is given, Fill's own `CancelsOnAuraLoss` / `DetailedAuraID` / `AcquireAliveBuffs` choice is skipped. The cooldown buff passes `ns:CooldownBuffAliveBuffs(...)` in, so the pooled list is no longer filled twice. All other callers pass nothing and behave as before. The `"Spell " .. id` label fallback is kept and documented: every add stores a label, so the fallback only runs for a legacy entry saved without one, which is the same cost every user buff cast pays.

### IN-02: Stale preview comment

**Files modified:** `BuffEngine.lua`
**Commit:** 42e9cb3
**Applied fix:** The `StartAllPreviewTimers` comment now says that a cooldown with its buff on previews from `entry.buffDuration`.

### IN-03: Greyed follow-field still shows its secrecy badge and hover tooltip

**Files modified:** `CDMTab.lua`
**Commit:** 24e1696
**Applied fix:** This goes through `ApplyFieldEnabled` and nowhere else. `state.badge` gets its own alpha, since it is parented to the row and not to hover. `state.hover` and `state.badge` now call `EnableMouse(enabled)`, so a greyed field raises no tooltip. Alpha and mouse state survive the badge's `SetShown` toggling.

### IN-04: An edit that keeps the buff on does not refresh a running buff proc

**Files modified:** `BuffEngine.lua`
**Commit:** d34b2ca
**Status:** fixed: requires human verification (logic change)
**Applied fix:** This runs in `ns:UpdateTrackedBuff`, after `ns:RebuildRankIndex`, so the family lists are the ones this edit produced. If a cooldown's buff stays on and a buff timer is running:
- **Buff Duration changed:** the timer ends, and the next cast starts it at the new length. Rescaling it in place was rejected: Display.lua caches the icon sweep on `startedAt` alone, so it would keep drawing the old length. That is the same reason as the existing IN-02 note in that function.
- **Duration unchanged:** `aliveBuffs` is repointed through `ns:CooldownBuffAliveBuffs`, so a corrected Aura ID applies at once.

This runs at edit time only and allocates nothing. Nothing changes per tick.

### IN-05: `ns:CooldownBuffAuraID` is not nil-safe, unlike its sibling

**Files modified:** `Core.lua`
**Commit:** fc9e009
**Applied fix:** `ns:CooldownBuffAuraID` and the new `ns:CooldownBuffTypedAuraID` now return nil for a nil entry.

---

_Fixed: 2026-10-22_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
