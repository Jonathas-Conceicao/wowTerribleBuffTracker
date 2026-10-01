---
phase: 65-cleanup
reviewed: 2026-10-01T04:25:24Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - CDMTab.lua
  - Display.lua
  - ReminderClick.lua
  - Core.lua
  - scripts/install.ps1
  - scripts/png2blp.js
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: fixed
---

# Phase 65: Code Review Report

**Reviewed:** 2026-10-01T04:25:24Z
**Depth:** standard (cross-file where the diff reaches: TOC load order, `ns:RebuildCastIndex` callers in BuffEngine.lua/Core.lua, `ns:RefreshIDPreview`, `ns:BuildSecrecyBadge`, `ns:ShowBuffTooltip`)
**Files Reviewed:** 6
**Status:** fixed (WR-01 fixed 2026-10-01; IN-01 and IN-02 skipped, see Resolution)

## Summary

Reviewed `git diff 631c7b3..HEAD` for CDMTab.lua, Display.lua, ReminderClick.lua, Core.lua, scripts/install.ps1 and scripts/png2blp.js (commits 2c08f01, aae99e5, 549c3de, a860d0e, 956feb8). I read the full functions around each hunk, not just the changed lines. `stylua --check .` is clean, `node --check scripts/png2blp.js` passes, and `git ls-files --eol` shows `eol=crlf` for every touched Lua file and for install.ps1.

**These parts are correct (no behaviour drift):**
- **`BuildFollowSpellIDField` (D-01).** I compared the old and new code line by line for both fields.
  - Aura ID field (`secrecy = true`, `emptyIsNone` unset), matching the old code in every step:
    - **Build:** the label, box, hover, icon and name geometry are unchanged. The scope note goes into `tooltipOpts.extraLines`, and the badge is built and anchored `LEFT` of hover at +6, then hidden.
    - **Reset:** it clears `level`, `checkedID` and `checkedGen`, then hides the badge.
    - **Prefill:** it clears `checkedID` but not `checkedGen`, as before.
    - **Update:** it never reaches the `emptyIsNone` branch, so the badge logic is unchanged.
    - **Read:** a value of 0 or less returns nil, an ID equal to the Spell ID returns nil, and any other ID returns the typed number. This is equivalent to the old `typed > 0 and typed ~= spell`.
    - **Validate:** the message is the same.
  - Cast spell ID field (`emptyIsNone = true`, `secrecy` unset), also matching the old code:
    - **Build:** no scope note, no badge and no `state.badge`. Nothing outside the factory reads `state.badge` from this field. The portrait badge at CDMTab.lua:2059 is its own state.
    - **Reset and prefill:** they never touch the badge fields. Prefill still turns a saved `false` into an empty box that does not follow the Spell ID.
    - **Update:** the "No click action" branch is unchanged, and the function now returns before the secrecy block.
    - **Read:** still nil while following, `false` when the box was emptied, nil when equal to the Spell ID, and the number otherwise.
  - `id` and `entryKey` both come from `opts.id`. `tab`, `visible` and the field order in `TRACKER_FIELDS` are unchanged.
  - The factory is a file-local declared at CDMTab.lua:1589, above `TRACKER_FIELDS` (1902). It references only `ns:` methods and globals, so it has no upvalue-order exposure.
- **`ClearClickStamp` / `ClearContainerClickStamps` (D-02).** Both are declared at Display.lua:150/171, above every caller: `ns.ReleaseContainerRuntime` (274), `RenderIconContainer` (~2430) and `ns:UpdateDisplay`.
  - **Else-branch site:** this branch runs only when `icon._clickKey ~= clickKey` and `clickKey == nil`, so `_clickKey` is non-nil there. The early return in `ClearClickStamp` can therefore never skip a clear that the old unconditional nil-out did. The five fields are only ever written together (Display.lua:2773-2777), and `MarkReminderClicksDirty` is still called right after.
  - **Trailing-pool site:** `if ClearClickStamp(pool[i]) then Mark...` is exactly the old `if _clickKey ~= nil then <clear>; Mark... end`.
  - **The two container sites:** both keep the old order (nil the `clickStampedIn` flag, clear the pool, mark once), and both cost one table read when nothing is stamped.
- **Removed guard in `RebuildCastIndex` (D-04).** Every caller is reached only from ADDON_LOADED or later events:
  - `InitBuffEngine` and the four migrations, run from Core.lua:2039-2066.
  - `RebuildRankIndex`, run from `RunLoadRefresh`, PLAYER_ENTERING_WORLD and the CDMTab/BuffEngine edit paths.

  All of these run after every TOC file has executed. `ns:MarkReminderClicksDirty` is defined at ReminderClick.lua:200, which comes before any statement in that file that could raise (`CreateFrame`, `UIParent:HookScript`, `EventRegistry`). The same function was already called unguarded from Display.lua. `scripts/migrate-dryrun.js` mirrors the migrations in JS and does not execute Lua, so it is not affected.
- **`OverlayOnLeave` (D-05).** `OverlayOnEnter` shows the tooltip through `ns:ShowBuffTooltip(self, ...)`, which calls `GameTooltip_SetDefaultAnchor(GameTooltip, frame)` (Display.lua:343). That sets the overlay as owner, so `IsOwned(self)` is true for every tooltip the overlay itself opened.
- **install.ps1 empty-directory prune (D-06).**
  - **Scope:** it enumerates only the children of `$dest`, so the addon folder itself is never a candidate.
  - **Deletion:** `Directory.Delete(path, $false)` is non-recursive. A child path is always longer than its parent's, so the length sort removes children before their parents. The emptiness probe runs fresh for each folder, so a parent emptied by a child's removal is caught in the same pass.
  - **Empty check:** `@(Get-ChildItem ... -Force).Count` returns 0 for an empty folder in PS 5.1 (AutomationNull, not `$null`). The probe uses `-Force`, so a folder that holds only hidden files is kept.
  - Everything used is PS 5.1-compatible.
- **png2blp.js (D-07).**
  - **Missing `Media/Source`:** handled through `fail()`, and only when no argv inputs are given.
  - **Duplicate outputs:** the check is case-insensitive, which is right on Windows.
  - **Signature:** `b.length < 8` is guarded before `subarray(0, 8).equals(...)`.
  - **Valid input:** behaviour is unchanged. The output path is `outName(input)`, the same expression as before.

**Defects:** none in the refactors. One warning on the new install.ps1 guard, which turns off the D-06 prune whenever `$dest` is not in canonical form. That guard sits next to an older prune loop with a real hazard of the same kind. There are also two latent info items.

## Warnings

### WR-01: install.ps1 compares a non-canonical `$dest` with canonical `FullName`s, so the D-06 prune silently does nothing under some `TBT_WOW_ROOT` values

**File:** `scripts/install.ps1:120`, `scripts/install.ps1:151` (new); `scripts/install.ps1:138` (pre-existing, same root cause)

**Issue:** `$dest` is `Join-Path $clientDir 'Interface\AddOns\TerribleBuffTracker'`, and `$clientDir` comes straight from `$env:TBT_WOW_ROOT`. Join-Path does not normalise the parent. `Get-ChildItem` returns `FullName`s that .NET has normalised (backslashes, absolute path).
- **Forward slashes** (`TBT_WOW_ROOT=D:/Games/World of Warcraft`, a common Git Bash habit): `$dir.FullName.StartsWith($dest + '\')` is false for every folder. The new prune skips everything and prints nothing, so D-06 quietly stops working. It is fail-safe, but the feature is lost without any message.
- **Relative path** (`TBT_WOW_ROOT=..\WoW`): the new loop is again a silent no-op. The older file-prune loop at line 138 is worse. It runs `$existing.FullName.Substring($dest.Length)`, where `$dest` is short and relative and `FullName` is absolute, so `$rel` comes out as a garbage tail that is never in `$files`. That loop then deletes every file the script has just copied, and the deployed addon folder is left empty.

The line-138 hazard predates this phase. It is listed here because the one-line fix below removes both problems.

**Fix:** canonicalise `$dest` once after it exists, so both loops compare like with like:

```powershell
$dest = Join-Path $clientDir 'Interface\AddOns\TerribleBuffTracker'
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
$dest = (Get-Item -LiteralPath $dest).FullName.TrimEnd('\')
```

If the pre-existing line 138 is out of cleanup scope, apply only the canonicalisation and record the file-prune hazard as fixed incidentally.

## Info

### IN-01: The factory lets `emptyIsNone` and `secrecy` combine, and the combination would leave a stale badge

**File:** `CDMTab.lua:1736-1756`

**Issue:** When `opts.emptyIsNone` is set and the user empties the box, `update` returns early, before the secrecy block. If a future field set both options, the badge from the previous ID would stay visible and `state.level` would go stale. Neither field sets both today, so this cannot happen yet. The factory's header comment documents the two options as independent, though.

**Fix:** Either note in the header that the two options are mutually exclusive, or run the badge block on the early path with `badgeID = 0`. For example, hide the badge and nil `state.level` before the `return` when `opts.secrecy` is set.

### IN-02: png2blp.js maps any non-`.png` input name to itself, so the duplicate check does not cover it

**File:** `scripts/png2blp.js:186`

**Issue:** `outName` only rewrites a `.png` suffix. Suppose an argv input is a real PNG with another name, such as `icon` (no extension) or `icon.png.bak`. It passes the new 8-byte signature check and is written to `Media/Textures/icon` or `Media/Textures/icon.png.bak`. install.ps1 never ships that file (it ships only `.blp`/`.tga`), and the run reports success. This behaviour predates the phase. D-07 tightened the input checks without covering it.

**Fix:** reject the input up front in the same pre-pass:

```js
for (const input of inputs) {
	if (!/\.png$/i.test(input)) fail(input + " is not a .png file");
	...
}
```

---

## Resolution

### WR-01: fixed

`$dest` is canonicalised right after it is created, with `(Get-Item -LiteralPath $dest).FullName.TrimEnd('\')`, so both prune loops compare like with like. Checked with a real install using `TBT_WOW_ROOT=C:/Program Files (x86)/World of Warcraft` (forward slashes): all four clients installed, nothing pruned, 22 files deployed to retail.

### IN-01: skipped

No field sets both `emptyIsNone` and `secrecy`. A guard would be code for a combination that does not exist.

### IN-02: skipped

Pre-existing behaviour: an extension-less input was always written under its own name. install.ps1 ships only the `.blp` files in its TOC-derived set, so nothing wrong can reach a release.

---

_Reviewed: 2026-10-01T04:25:24Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
