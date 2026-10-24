---
phase: 76-buff-duration-on-bag-items
fixed_at: 2026-10-22T00:00:00Z
review_path: .planning/phases/76-buff-duration-on-bag-items/76-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 5
skipped: 1
status: partial
---

# Phase 76: Code Review Fix Report

**Fixed at:** 2026-10-22
**Source review:** .planning/phases/76-buff-duration-on-bag-items/76-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (the orchestrator set the scope: WR-01 and IN-01 to IN-05)
- Fixed: 5
- Skipped: 1 (IN-03, deferred to Phase 77 Cleanup)

## Fixed Issues

### WR-01: `ns:UpdateTrackedItemBuff` ignores `fieldKeys`, breaking the WR-02 "not read means not written" contract

**Files modified:** `BuffEngine.lua`
**Commit:** d66991c
**Status:** fixed: requires human verification (save-path logic)
**Applied fix:**
- `ns:UpdateTrackedBuff` now forwards `fieldKeys` to `ns:UpdateTrackedItemBuff(key, fields, fieldKeys)`.
- The function works out which of `buffEnabled`, `buffAuraID` and `buffDuration` were read. It uses three boolean locals, so no table is allocated.
- It writes only the keys that were read. A read key that is nil clears the saved value, the same as the `fieldKeys` loop in `UpdateTrackedBuff`.
- The engine guard checks the values the entry will hold after the write: the read value for a read key, the saved value otherwise.
- The chat line's local was renamed to `savedDuration`, so it no longer shadows the new `buffDuration` local.
- The header comment was rewritten to match.

### IN-01: The shared use-spell comment says more than the code can know

**Files modified:** `Providers.lua`
**Commit:** 4fa4d5a
**Applied fix:** The comment above `ns:StartCooldownBuffFromCast` in `MetaItemBagProviderMixin:OnTrigger` was reworded. The key names the item the use-spell map currently holds, which is not necessarily the item that was used. When two tracked items share a use-spell, the map keeps whichever one `RegisterAllTrackedItemUseSpells` wrote last, and that depends on `pairs()` order. This is "last writer wins", which 76-CONTEXT accepts. Only the comment changed; behaviour is the same.

### IN-02: Stale comment says the timer branch never uses `ApplyCachedIcon`

**Files modified:** `Display.lua`
**Commit:** b229425
**Applied fix:** The comment now says that RenderIconContainer's TIMER branch uses `ApplyCachedIcon` for cooldown-slot entries (Phase 76) and keeps its own spellID-only cache block for every other proc.

### IN-04: The engine guard is looser than the dialog's Aura ID validation

**Files modified:** `BuffEngine.lua`
**Commit:** 473f836
**Applied fix:** With the buff on, the guard now requires the Aura ID to be a positive integer no larger than 2147483647 (`> 0`, `<= 2147483647`, `== math.floor(...)`). This is the same rule the dialog applies. The comment says so.

### IN-05: The item portrait shows the saved label, which can be the "Item <id>" placeholder

**Files modified:** `CDMTab.lua`
**Commit:** 4b69aa6
**Applied fix:** In the `spellPreview` prefill for a META_ITEM, a saved label that is nil or exactly `"Item " .. itemID` triggers a fresh name lookup through `ns:ItemDisplayInfo(entry.itemID)`. That function is secret-safe (`issecretvalue` first). The same single call still supplies the icon fallback. This runs once per dialog open, never per tick or on a render path. If the client still has no name, the result is the same placeholder.

## Skipped Issues

### IN-03: The post-commit tail is duplicated between `UpdateTrackedItemBuff` and `UpdateTrackedBuff`

**File:** `BuffEngine.lua` (the `MarkTrackersDirty` / `MarkCooldownsDirty` / `UpdateDisplay` tail of both functions)
**Reason:** skipped (deferred to Phase 77 Cleanup). By orchestrator decision, the duplicated end-of-save steps are unified there under the CLAUDE.md milestone-cleanup mandate.
**Original issue:** The nil-guarded `MarkTrackersDirty`, `MarkCooldownsDirty` and `UpdateDisplay` sequence is copied between the two commit functions.

## Verification

- `stylua .` is clean, and every touched file is `w/crlf` with no `\r\r`.
- `node scripts/aura-read-gate.js` passes, and so does `--selftest` (30 cases).
- `./scripts/install.bat` deployed to every client folder.
- In-game checks are deferred to Phase 78.

---

_Fixed: 2026-10-22_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
