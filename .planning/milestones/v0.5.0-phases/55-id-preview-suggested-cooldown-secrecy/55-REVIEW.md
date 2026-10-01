---
phase: 55-id-preview-suggested-cooldown-secrecy
reviewed: 2026-09-28T00:00:00Z
depth: deep
files_reviewed: 3
files_reviewed_list:
  - Core.lua
  - Display.lua
  - CDMTab.lua
findings:
  critical: 0
  warning: 2
  info: 5
  total: 7
status: issues_found
fix_status: all_fixed
fixed_at: 2026-09-28
---

# Phase 55: Code Review Report

**Reviewed:** 2026-09-28
**Depth:** deep
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Scope: `git diff fe936cd..HEAD -- '*.lua'`, which covers Core.lua (the secrecy, suggestion and preview helpers, plus the TOOL-01 secrecy line), Display.lua (the secrecy line in the unresolved-ID branch of `ns:ShowBuffTooltip`) and CDMTab.lua (the `spellPreview` and `secrecyBadge` TRACKER_FIELDS entries and the `duration` update hook). I read each hunk against the full surrounding code, including the whole of `CreateAddDialog` (walker, `RefreshState`, `Layout`, the confirm handler, `OpenForAdd` and `OpenForEdit`) and the tile OnEnter path that calls `ShowBuffTooltip`.

There are no BLOCKERs. I checked each item in the focus list and it holds:

- **Closure binding and upvalue order:** both `state` tables are declared before their `SetScript` closures (CDMTab.lua:1351, :1457). Every new CDMTab file-local (`SECRECY_BADGE_ATLAS`, `FormatDuration`) is declared above `TRACKER_FIELDS`. The Core.lua helpers use only file-locals declared above them (`SpellAuraSecrecyAPI`, `SECRECY_*`) and `ns:` methods resolved at call time (`ns:CanReadTable` lives in BuffEngine.lua, which the TOC loads before any caller runs).
- **Secret values:** each new read calls `issecretvalue` first and then checks `type()`. `GetSpellBaseCooldown` and `C_Spell.GetSpellCharges` are existence-checked and pcall'd, and `GetSpellCharges` goes through `ns:CanReadTable`. If `C_Secrets.GetSpellAuraSecrecy`, `Enum.SecrecyLevel` or its `NeverSecret` member is missing, `SECRECY_NEVER` stays nil, every helper returns nil or false, the line is omitted and the badge stays hidden. None of these cases raises an error. See IN-03 for one gap in consistency.
- **TOOL-01 hot path:** the new code creates no table, closure or string. The one C call is pcall'd, the result is checked with `issecretvalue` and `type`, and table indexing with any number cannot throw. Nothing added to the post-call can raise. The per-tooltip `RelatedID` closure is pre-existing and out of scope.
- **Never printed twice:** `ShowBuffTooltip` adds its own secrecy line only in the `not spellResolves` branch, where `SetSpellByID` (and therefore TOOL-01) never ran. Both `ShowBuffTooltip` and `ns:SpellPreview` test for the same thing (`C_Spell.GetSpellInfo ~= nil`), so the preview hover and the tile hover cannot disagree about which path adds the line.
- **Suggestion recursion and scope:** `suggestedForID` and `suggestionText` are recorded before `SetText`, so the nested `RefreshState` returns at the ID compare. The hook applies only when `ctx.kind == ns.KIND.USER_CD`, and a wiped ctx (dialog hidden) never matches. Edit prefill is safe: `prefill` runs after `reset` and leaves `suggestionText` nil. Walking `OpenForEdit` step by step, including the nested `RefreshState` passes that `SetText` in the spellID reset and prefill triggers against the duration field's stale state, the final state is always the saved text. A suggestion longer than 6 characters is dropped, not truncated.
- **Layout:** `secrecyBadge` returns `nextY = y`, so `field.height` is `-0`, the row takes no space, and hiding it has no effect on layout. The preview row is 28 px (a 20 px hover area plus an 8 px gap). The error label is still placed after the last visible row by `Layout` on both flavours (retail ends at `duration`, Forever at `coverAllRanks`). The badge fits inside the 240 px dialog in both art modes: it ends at x=188 as an atlas and at x=228 as text. `CreateAddDialog` has no hunk in the diff.
- **Save path:** the confirm handler reads only fields that are `field.shown and entryKey`. `spellPreview` and `secrecyBadge` have no `entryKey`, so they are validated (both always return true) but never read or written. Neither has an `editBox` key, so neither joins the focus ring.

The findings below are behavioural gaps that the gates in the phase plan could not catch.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: The badge and the suggestion never retry after a late spell resolution, but the preview does

**File:** `CDMTab.lua:1404` (preview retry), `CDMTab.lua:1487-1491` (badge), `CDMTab.lua:1555-1559` (suggestion)
**Issue:** `spellPreview` deliberately re-queries an ID that has not resolved yet on every later dialog change (its `resolved` flag). `secrecyBadge` and `duration` key only on the ID (`checkedID`, `suggestedForID`) and record it whether or not the lookup returned an answer.
**Failure scenario:** On the Cooldowns tab, the player types an ID the client has not loaded yet. The preview shows "Unknown spell". `ns:SpellAuraSecrecy` returns nil (or NeverSecret) and `ns:SuggestedCooldown` returns nil. The player then presses a key in Duration, and the retry makes the preview resolve to the real spell. The badge still reflects the first answer, so a Contextual or Always-secret aura shows no warning, which is a false "safe" signal. Duration stays empty for the rest of the dialog, even though `SuggestedCooldown` would now answer. Both stay stale until the ID itself changes. The phase's own checklist item 4 assumes this late-resolution case exists.
**Fix:** Make the other two fields depend on the preview's resolution, not only on the ID. For example, have the preview bump a counter when it resolves, and compare that counter in both hooks:
```lua
-- spellPreview.update, inside the `if spellName then` branch:
state.generation = (state.generation or 0) + 1
-- secrecyBadge.build: state.preview = preview
-- secrecyBadge.update:
local gen = state.preview.generation
if id == state.checkedID and gen == state.checkedGen then return end
state.checkedID, state.checkedGen = id, gen
```
Apply the same guard in `duration.update`, capturing the preview state at build as `dialog.GetFieldState("spellPreview")`. The existing `text ~= suggestionText` check still protects anything the user typed.

### WR-02: A fractional charge-spell cooldown is either dropped or suggested as a 4-decimal number

**File:** `Core.lua:1435-1443`, `CDMTab.lua:1568-1574`
**Issue:** The fallback returns `C_Spell.GetSpellCharges(id).cooldownDuration` as is. That value is the current recharge time and can be haste-modified (for example `17.3913043`). It is not a whole-second base value like the `GetSpellBaseCooldown` branch returns. `FormatDuration` uses `%.4f` for non-integers.
**Failure scenario:** For a hasted recharge of 17.3913 s, `FormatDuration` produces `"17.3913"` (7 characters), the length check blanks it, and the player gets no suggestion with no explanation. For 8.6957 s it produces `"8.6957"` (6 characters), which is written and saved as 8.6957 s. That is an odd, gear-dependent value that becomes wrong when haste changes. In practice, most charge spells with hasted recharges get no suggestion or a noisy one.
**Fix:** Round the suggestion before formatting, for example in `ns:SuggestedCooldown`'s charge branch or in `duration.update`:
```lua
local seconds = id > 0 and ns:SuggestedCooldown(id) or nil
if seconds then
	seconds = math.floor(seconds + 0.5) -- whole seconds; a starting value, not a measurement
	if seconds <= 0 then seconds = nil end
end
```
The code comment should also say the charge value can be the current (hasted) recharge, not a base value.

## Info

### IN-01: "Aura secrecy" on a cast-spell tooltip describes an aura ID that is often not the buff

**File:** `Core.lua:1543-1546`, `CDMTab.lua:1491`
**Issue:** On a `Spell`-type tooltip, and in the dialog badge, the secrecy is looked up for the cast spell's ID. The TOOL-01 header says a buff's aura ID "is frequently a different number". For those spells, "Aura secrecy: Never secret" describes a nonexistent aura, while the real buff may be contextually secret.
**Fix:** This is the user-decided scope, so no code change is required. Consider making the label say which ID it describes (for example `"Aura secrecy (this ID): ..."` when `isSpell`), or adding one sentence to the badge explanation.

### IN-02: An unrecognised future SecrecyLevel hides the warning instead of showing it

**File:** `Core.lua:1382-1385`, `Core.lua:1409-1414`
**Issue:** `ns:SpellAuraSecrecy` returns nil for any level not in `SECRECY_LABELS`. If Blizzard adds a fourth, more restrictive level, the tooltip line and the badge silently disappear. For a warning feature, an unknown answer then looks the same as "no warning".
**Fix:** Return any numeric level that is not secret, and have `SecrecyWarns` return `level ~= SECRECY_NEVER` for every number. Map unknown levels to a generic prebuilt line (for example `"Aura secrecy: Restricted"`) built once at load.

### IN-03: `ns:SpellPreview` is less guarded than the section header claims

**File:** `Core.lua:1454-1457`
**Issue:** `pcall(C_Spell.GetSpellInfo, spellID)` indexes `C_Spell` outside the pcall, while `SuggestedCooldown` checks `C_Spell and ...`. The result is also checked only with `type(info) == "table"`, not the project's `ns:CanReadTable` (`canaccesstable`). Current docs do not mark `GetSpellInfo` as secret-returning, so this does not fail today. It does contradict the header's statement that every read here is "capability-checked".
**Fix:** `if not (C_Spell and C_Spell.GetSpellInfo) then return nil end`, then `if not ok or not ns:CanReadTable(info) then return nil end`.

### IN-04: A preview tooltip already open is not refreshed when the ID changes

**File:** `CDMTab.lua:1357-1361`, `CDMTab.lua:1384-1426`
**Issue:** If the mouse is resting on the preview row while the player types in the Spell ID box, the open GameTooltip keeps showing the previous spell (and its ID and secrecy lines) until the mouse leaves and re-enters.
**Fix:** At the end of `update`, when `GameTooltip:IsOwned(state.hover)`, re-run the OnEnter body (or hide the tooltip if `state.spellID` is nil).

### IN-05: Opening the dialog runs `duration.update` against the previous session's state

**File:** `CDMTab.lua:1524-1543` (with the walker at `CDMTab.lua:1913-1915` and `1949-1955`)
**Issue:** `OpenForAdd` and `OpenForEdit` reset (and prefill) fields in array order. The `SetText` in the spellID field's reset and prefill fires `RefreshState` before `duration.reset` has cleared `suggestedForID` and `suggestionText`. `duration.update` then compares the new ID against the previous session's state. It can call `ns:SuggestedCooldown` and write a throwaway suggestion into the box, which `duration.reset` and `prefill` then overwrite. The final state is correct, but only because `duration` comes after `spellID` in `TRACKER_FIELDS`. If the fields are reordered, or a later field reads Duration during the reset pass, this becomes a real bug.
**Fix:** Document the dependency on field order in the contract comment. Alternatively, have `duration.update` return early when `state.editBox` has not been reset in this open, for example by setting a `state.opened` flag in `reset` and `prefill` and clearing it in `OnHide`. That keeps `CreateAddDialog` unchanged.

## Fix Outcomes

Applied 2026-09-28 by gsd-code-fixer (`--auto`), one commit per finding. `CreateAddDialog` still hashes to `64e38633612791cb7e1ea41902b75ae45c18167b`, and all three Lua files are `w/crlf` with no CRCRLF. `stylua --check` is clean, `node scripts/migrate-dryrun.js --selftest` passes (7 cases), and the build is redeployed with `./scripts/install.bat`. Display.lua was not changed.

| ID | Outcome | Commit | What changed |
|----|---------|--------|--------------|
| WR-01 | Fixed (needs in-game check) | `460b233` | `spellPreview` bumps a never-reset `generation` counter each time it resolves a spell. `secrecyBadge` (`checkedID`/`checkedGen`) and `duration` (`suggestedForID`/`suggestedGen`) key on the ID and that counter, so a late resolution re-runs both lookups once. Compare-before-write, the nested-`SetText` return and the typed-text guard are unchanged. |
| WR-02 | Fixed | `3535abd` | The `GetSpellCharges().cooldownDuration` branch of `ns:SuggestedCooldown` rounds to whole seconds (`math.floor(d + 0.5)`, still required to be > 0). The comment says it is the current, possibly hasted, recharge. |
| IN-01 | Fixed (wording only) | `f711248` | New `ns:SecrecyScopeNote()` returns one prebuilt string, or nil without the secrecy API: "Secrecy is for this ID's own aura; the buff's may differ." The badge tooltip shows it, and the preview tooltip gets it as a static `extraLines` entry built once at build. The TOOL-01 global line is unchanged. |
| IN-02 | Fixed | `5441bc3` | `ns:SpellAuraSecrecy` returns any readable numeric level. An unrecognised level maps to a prebuilt "Aura secrecy: Unknown" line and a generic explanation, and `ns:SecrecyWarns` treats it as not NeverSecret, so the badge shows. The tooltip path is still one table read with no allocation. The write-only `SECRECY_LABELS` table is removed. |
| IN-03 | Fixed | `f9de91d` | `ns:SpellPreview` existence-checks `C_Spell.GetSpellInfo` before the pcall and accepts the result only through `ns:CanReadTable`. That is an `ns` method, resolved at call time, so the upvalue-order trap does not apply. |
| IN-04 | Fixed | `8b307c3` | When `GameTooltip:IsOwned(state.hover)`, `spellPreview.update` redraws the tooltip after a real row change, or hides it when the box empties. It does not run on the unknown-ID retry early return. |
| IN-05 | Documented | `859d50c` | The TRACKER_FIELDS contract comment gains an "Order is load-bearing" paragraph: update/reset/prefill run in array order, and the spellID < spellPreview < secrecyBadge < duration order must be kept. No code change. |

---

_Reviewed: 2026-09-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
