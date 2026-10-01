---
phase: 54-edit-trackers
reviewed: 2026-09-28T12:54:31Z
depth: deep
files_reviewed: 2
files_reviewed_list:
  - BuffEngine.lua
  - CDMTab.lua
findings:
  critical: 1
  warning: 3
  info: 6
  total: 10
status: issues_found
---

# Phase 54: Code Review Report

**Reviewed:** 2026-09-28T12:54:31Z
**Depth:** deep
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Scope: `git diff 4c53325..HEAD -- '*.lua'`, which covers BuffEngine.lua (`ns:TrackerKindWord`, `ns:SpellLabel`, `ns:IsEditableTracker`, `ns:FindTrackerConflict`, `ns:ClearTrackerRuntimeState`, `ENGINE_OWNED`, `ns:AddTrackedBuff` duplicate rejection, `ns:RemoveTrackedBuff`, `ns:UpdateTrackedBuff`) and CDMTab.lua (`FormatDuration`, `TRACKER_FIELDS`, the field-agnostic `CreateAddDialog`, `OpenForAdd`/`OpenForEdit`, the `OnHide` ctx wipe, and the context-menu "Edit" entry). I traced the calls into Core.lua (`ns:TrackerKey`, `ns:RebuildCastIndex`, `ns:RebuildRankIndex`, `ns:CooldownKindFor`, `ns.cooldownStarts`/`ns.cooldownOverrides`), Providers.lua (the `UserSpellProvider` cast path and `AddSuggestedTracker`'s WR-01 path) and Display.lua (`entry.key` slot identity, `RefreshCooldownSlotCounts`). `node scripts/migrate-dryrun.js --selftest` passes (7 cases).

These checks came out clean:

- **Validation before any write.** Every check in `ns:UpdateTrackedBuff` runs before anything is written, with the exceptions in CR-01 and WR-01. An ID change to a key that already exists is refused twice: once by `ns:FindTrackerConflict` and once by the defensive `trackedBuffs[newKey]` check. The move carries the same entry table, so `section` and `layoutOrder` always go with it.
- **Runtime state on an ID change.** It is cleared completely. `ns:ClearTrackerRuntimeState` covers `activeTimers`, `previewTimers`, `cooldownStarts`, `cooldownOverrides`, and the proc, aliveBuffs and displayInfo pools. `ns:RebuildRankIndex` rebuilds the cast index and `ns.rankFamilies`. Nothing else in the addon (Display, MergeMode, Providers) holds state keyed by a user tracker key.
- **Duplicate rules.** A tracker's own key never counts as a duplicate, because of the `exceptKey` early return plus `checkCandidate`. A userCd and a metaSkillCd for the same spell collide in both Add and Update. New IDs still add normally. `AddSuggestedTracker` never calls `ns:AddTrackedBuff`, so the Suggested-tile path is unchanged.
- **Stale edit state.** The `OnHide` wipe clears `ctx.editingKey` on every close. `OpenForAdd` resets every field, including the duration box's raised `SetMaxLetters`, so prefilled values cannot leak into the next Add.
- **Error label placement.** `Layout()` puts the error label below the Duration box on retail (-138, where the box ends at -128) and in the same place as before on Forever (-164).
- **Load-order (upvalue) trap.** No violation. `ENGINE_OWNED` is declared above both functions that read it. `ParseDuration`, `DURATION_HINT` and `FormatDuration` are declared above `TRACKER_FIELDS`, which is above `CreateAddDialog`. The Edit button reaches the dialog through `ns.tbtAddDialog`.
- **Hot path.** Nothing new runs per frame or per cast. `RefreshState` runs on keystrokes and when the dialog opens. It runs 3-5 times per open, because `SetText` fires `OnTextChanged`, but it cannot recurse, since no field defines `update`.

The defects are in the edges of the new code: a nil concatenation that throws after a partial commit, a label read that is not secret-safe and runs after the move has started, and a field-definition contract that will silently delete saved data once Phase 55 adds a `visible()` field.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: In-place edit of a label-less legacy tracker throws after the entry is already modified, skipping every rebuild and leaving the dialog stuck

**File:** `BuffEngine.lua:1044-1052` (the `else` print branch of `ns:UpdateTrackedBuff`)
**Issue:** When the spell ID does not change, the chat line concatenates `entry.label` directly. `entry.label` can be nil for a userBuff or userCd entry:

- `ns:RemoveTrackedBuff` guards against exactly this: "a pre-v1 user buff can carry no label; concatenating nil here would throw after the row is already gone and skip every rebuild below (IN-05)".
- `UserSpellProvider:OnTrigger` falls back to `entry.label or ("Spell " .. ...)`.
- `ns:MigrateKindKeys` gives these entries `trackerType = userBuff` and backfills `spellID`, but never `label`.

So the entry is editable (`ns:IsEditableTracker` is true), and the edit then fails. Failure scenario:

1. The player opens Edit on such a tracker, changes the duration (or un-ticks Cover all ranks on Forever) and clicks Save.
2. `entry.duration` and the `fieldKeys` fields are written to the saved entry.
3. The `print` raises "attempt to concatenate a nil value (field 'label')".
4. Because of the error, these never run: `ns:RebuildRankIndex` (so a coverAllRanks change is not applied until the next SPELLS_CHANGED or world entry), `ns:MarkTrackersDirty`, `ns:MarkCooldownsDirty`, `ns:UpdateDisplay`, and the dialog's own `RefreshTBTSections`, `StartAllPreviewTimers` and `Hide`.
5. The dialog stays open with Save enabled. Every further Save throws again, so the player sees a Lua error and an edit that looks unsaved, although it was half saved.

The comment at `BuffEngine.lua:1025-1026` says the print was hardened against "a malformed legacy entry". It guards `oldSpellID`, the field that cannot be missing here, and not `label`, the one that can.
**Fix:** Derive a safe label once, before any write, and never concatenate the raw field:
```lua
-- before the `if newKey ~= oldKey` block
local shownLabel = entry.label or ns:SpellLabel(spellID)
...
print("|cff00ccffTerribleBuffTracker|r: Updated |cff00ff00" .. shownLabel .. "|r (" ...)
```
(In the move branch, set `shownLabel = entry.label` after re-deriving it.) Merging the two near-identical print blocks (IN-04) removes the second copy of this bug.

**Outcome:** Fixed in `a562ab4` (reworked in `1d058f5`). The label is resolved before the first write: the saved label, or `ns:SpellLabel(spellID)` when there is none. Both prints use that value. Needs a human check in-game with a label-less legacy tracker.

## Warnings

### WR-01: `ns:SpellLabel` boolean-tests `info.name` without `issecretvalue`, and the ID-change branch calls it after the move has already started

**File:** `BuffEngine.lua:727-733` (`ns:SpellLabel`), `BuffEngine.lua:1016-1021` (its call inside the move)
**Issue:** `if info and info.name then` is a boolean test on an API return. This file's own header rule (lines 15-18) says boolean-testing a secret throws. Core.lua already treats `C_Spell.GetSpellInfo(...).name` as possibly secret (`ResolveRankFamily`: `not issecretvalue(infoName) and type(infoName) == "string"`). The new helper drops that guard, and so does the `..` concatenation of the label in both prints. 54-CONTEXT deliberately adds no `InCombatLockdown` guard, so an edit can be made while restrictions are active.

Inside `ns:UpdateTrackedBuff` the call happens after the oldKey runtime state is cleared, `trackedBuffs[oldKey]` is nilled, `trackedBuffs[newKey]` is written and `entry.spellID` is changed. A throw at that point leaves:

- the tracker moved, but with its old duration and fields
- no `PreallocateProc(newKey)`
- a stale cast index: `buffKeyBySpell[oldID]` still points at the now-missing oldKey, and nothing indexes newID until the next rebuild event
- a dialog whose `ctx.editingKey` no longer exists, so every retry answers "This tracker no longer exists"

**Fix:** Make the helper secret-safe, and resolve it before the first write:
```lua
function ns:SpellLabel(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	local name = info and info.name
	if name ~= nil and not issecretvalue(name) and type(name) == "string" and name ~= "" then
		return name
	end
	return "Spell " .. spellID
end
```
and in `ns:UpdateTrackedBuff` compute `local newLabel = (newKey ~= oldKey) and ns:SpellLabel(spellID) or nil` next to the conflict checks, then assign `entry.label = newLabel` inside the move.

**Outcome:** Fixed in `1d058f5`. `ns:SpellLabel` now calls `issecretvalue(name)` before any type check or comparison, and always returns a string (`tostring(spellID)` in the fallback). In `ns:UpdateTrackedBuff`, the label and chat ID text are now computed with the conflict checks, before the first write. The move block only assigns them. A comment there states the rule for later edits.

### WR-02: A field hidden by `visible()` is silently deleted from the saved entry on every edit

**File:** `CDMTab.lua:1615-1620` (values filled only for `field.shown`), `CDMTab.lua:1641` (all `dialog.fieldEntryKeys` passed), `BuffEngine.lua:1028-1034` (`entry[k] = fields and fields[k]`)
**Issue:** `fieldEntryKeys` lists every built field, whether or not it is currently shown. The confirm handler only calls `read` for shown fields, so a hidden field's key is absent from `values`. `ns:UpdateTrackedBuff` then loops over all of `fieldKeys` and writes `entry[k] = nil` for it. The contract says a hidden field "is not read", but in edit mode "not read" becomes "erased". No current field defines `visible`, so this does not fire today. Phase 55 is the stated consumer of this contract and will add runtime show/hide fields (suggested cooldown, preview, badge). The first such field will wipe its saved value whenever the tracker is edited while that field is hidden: data loss with no error.
**Fix:** Pass only the keys that were actually read. Build a reused `readKeys` array alongside `values` in the confirm handler, and hand that to `ns:UpdateTrackedBuff` instead of `dialog.fieldEntryKeys`. Alternatively, have the engine skip keys where `fields[k] == nil and not fieldsRead[k]`. If clearing is the intended meaning, state it explicitly in the contract comment above `TRACKER_FIELDS`.

**Outcome:** Fixed in `544375b`. The confirm handler now fills a reused `readKeys` array with exactly the entry keys it read (shown fields only), and passes that to `ns:UpdateTrackedBuff` in place of `dialog.fieldEntryKeys`. The unused `fieldEntryKeys` list was removed. The `visible()` contract above `TRACKER_FIELDS` and the engine's fields/fieldKeys contract now both say "not read means not written": a hidden field keeps its saved value, and only a read key with a nil value is cleared.

### WR-03: The same menu closure captures `trackerKey` for Edit but leaves Move/Hide/Remove acting on the pooled `self.spellID`

**File:** `CDMTab.lua:386-419`
**Issue:** 54-03 added `local trackerKey = self.spellID` with the comment "Tiles are pooled, so the menu acts on the key it was opened for, not whatever self.spellID holds by the time a button is clicked". The three existing buttons in the same closure still read `self.spellID` when clicked: `SetBuffSection` for Move and Hide, and `ns:RemoveTrackedBuff` for Remove. `ns:RefreshTBTSections` can run while the menu is open. For example, `RequestItemCatalogueRebuild` runs it on a BAG_UPDATE while the CDM is open (CDMTab.lua:59-69). If it re-acquires pool frames in a different order, which can happen whenever the tracker set changes (for example a Suggested drop or an edit in another path), then Remove deletes whichever tracker the frame now shows. That is irreversible data loss on the wrong tracker. The code this phase added documents the hazard, but the destructive button next to it was left unfixed.
**Fix:** Use the captured key in all four callbacks: `ns:SetBuffSection(trackerKey, def.key)`, `ns:SetBuffSection(trackerKey, "hidden")`, `ns:RemoveTrackedBuff(trackerKey)`.

**Outcome:** Fixed in `7ebcb2c`. Move, Hide, Edit and Remove all use `trackerKey`, which is captured when the menu opens. The Suggested tile's "Add to" menu, a separate closure above, still reads `self.spellID`. It is non-destructive and out of scope here.

## Info

### IN-01: `FormatDuration` output does not always parse back, so live validation blocks Save on an unchanged value

**File:** `CDMTab.lua:1203-1219`, `CDMTab.lua:1343-1352`
**Issue:** The header claims "every result this produces parses back through ParseDuration". This is false for tiny values. `".00001"` is a valid 6-character Add input (0.00001 s), but it formats as `"0.0000"`, then `"0."`, then `"0"`, and `ParseDuration("0")` returns nil. `read` would return `originalValue` for the unchanged text, but `validate` calls `ParseDuration(text)` directly. So the dialog opens with the duration hint showing and Save disabled on the tracker's own saved value.
**Fix:** In `validate`, accept `state.originalText ~= nil and text == state.originalText` the same way `read` does. Alternatively, make `FormatDuration` fall back to `%.6f` or clamp to a minimum representable value. Correct the comment either way.

**Outcome:** Left documented, not fixed. This only happens for a saved duration below 0.00005 s, which no real buff or cooldown uses. The orchestrator's scope listed IN-02, IN-04 and IN-06 as the Info items to act on.

### IN-02: A duration-only edit does not update a running buff proc

**File:** `BuffEngine.lua:1027`
**Issue:** When the ID is unchanged, `entry.duration` changes but `ns.activeTimers[key].duration/expiresAt` keep the old cast's values until the proc expires. A running cooldown, by contrast, picks up the new length immediately through `ns:CooldownDuration`. The two kinds behave differently after the same edit. This may be acceptable (the change applies on the next cast), but it is not documented, and checklist item 3 only tests it after a fresh cast.
**Fix:** Document "applies from the next cast" in the function header, or rescale the live proc.

**Outcome:** Documented in `03b0c08`, not rescaled. Rescaling `proc.duration` and `proc.expiresAt` would update the bars, which re-read `timer.duration`. It would not update the icons: Display.lua:2418 only calls `SetCooldown` again when `startedAt` changes, so the sweep would keep drawing the old length while the icon expires at the new time. Closing that means adding a comparison to the per-frame render path, which was out of bounds. The `ns:UpdateTrackedBuff` header now says a buff duration edit applies from the next cast.

### IN-03: The conflict check ignores rank-family coverage

**File:** `BuffEngine.lua:752-777`
**Issue:** Consider a Forever tracker userBuff:A with coverAllRanks whose family includes A2. An edit (or Add) to spell A2 is accepted, because the cast index excludes family members. `RebuildRankIndex` then drops A2 from A's family, since the byKeyIndex hit wins. As a result, casting rank A2 silently stops driving tracker A. This is not a key duplicate, but from the player's point of view it is a "same spell tracked twice" case.
**Fix:** Optionally have `ns:FindTrackerConflict` also consult `ns.rankIndex`/`ns.rankIndexCooldown`, or show a warning rather than a refusal.

**Outcome:** Left documented, not fixed. This is a product decision (refuse, warn, or allow), and it affects only Forever and only coverAllRanks families. It also applies to Add, not just Edit, so it is outside this phase's edit scope. It needs a user call.

### IN-04: Two near-identical print blocks added by this phase

**File:** `BuffEngine.lua:1037-1063`
**Issue:** The two branches differ only in the `"<old> -> "` fragment. Under CLAUDE.md's cleanup mandate, duplication that a milestone introduces should be merged. The duplicate also doubled the CR-01 surface.
**Fix:** Use one print with `local idText = (newKey ~= oldKey) and (tostring(oldSpellID) .. " -> " .. spellID) or tostring(spellID)`.

**Outcome:** Fixed in `fc2ac27`. `idText` is built alongside the label, before the first write, and one `print` serves both branches. `oldSpellID` is gone.

### IN-05: The ctx wipe hangs on `OnHide`, which also fires when UIParent hides

**File:** `CDMTab.lua:1726-1728`
**Issue:** Alt+Z, a cinematic or a pet battle hides UIParent. That fires the dialog's `OnHide` and wipes `ctx` while `dialog:IsShown()` stays true. When UIParent comes back, the dialog would be visible with `ctx.mode == nil`: Add/Save would do nothing, and validation would run with `ctx.kind == nil`. On retail this is masked, because CooldownViewerSettings is also a UIParent child and its OnHide EventRegistry callback calls `ns:DismissTBTDialogs()`. The watcher backstop is parented to UIParent, so it cannot cover a client without that callback.
**Fix:** Call `dialog:Hide()` from the dialog's own `OnHide` when `dialog:IsShown()` is still true, so a parent-driven hide becomes a real close. Alternatively, clear `ctx` in the Cancel, commit and `DismissTBTDialogs` paths instead of in `OnHide`.

**Outcome:** Left documented, not fixed. On retail, CooldownViewerSettings' OnHide callback already dismisses the dialog, so the problem is masked there. Changing close semantics without being able to test Alt+Z, cinematics and pet battles in-game carries more risk than the unmasked case. It should be tested in-game before any change.

### IN-06: `ctx.entry` is written but never read, and the edit dialog does not notice when its tracker is removed underneath it

**File:** `CDMTab.lua:1696`, `CDMTab.lua:1291-1301`
**Issue:** `ctx.entry` has no reader; `prefill` receives `entry` as an argument. Separately, if the edited tracker is deleted while the dialog is open (drag to the delete zone, or Remove from its menu), live validation still enables Save, and each click only answers "This tracker no longer exists".
**Fix:** Drop `ctx.entry` or document it as reserved for Phase 55. Optionally, dismiss the dialog from `ns:RemoveTrackedBuff` when `ctx.editingKey == key`.

**Outcome:** Partly fixed in `b4b470e`: `ctx.entry` was dropped and the ctx contract comment updated. The optional dismiss-on-remove was not done, because it would make BuffEngine.lua reach into CDMTab's dialog state. The current behaviour is safe: the engine refuses the edit with "This tracker no longer exists" and writes nothing.

## Fix Outcomes

| Finding | Outcome | Commit |
|---------|---------|--------|
| CR-01 | Fixed (needs a human check in-game with a label-less legacy tracker) | `a562ab4`, `1d058f5` |
| WR-01 | Fixed | `1d058f5` |
| WR-02 | Fixed | `544375b` |
| WR-03 | Fixed | `7ebcb2c` |
| IN-01 | Documented, not fixed (sub-0.00005 s durations only) | -- |
| IN-02 | Documented as "applies from next cast" (rescale needs a hot-path compare) | `03b0c08` |
| IN-03 | Documented, not fixed (product decision, Forever only) | -- |
| IN-04 | Fixed | `fc2ac27` |
| IN-05 | Documented, not fixed (masked on retail; needs in-game test first) | -- |
| IN-06 | `ctx.entry` dropped; dismiss-on-remove not done | `b4b470e` |

After the fixes: `node scripts/migrate-dryrun.js --selftest` passes (7 cases), `stylua --check BuffEngine.lua CDMTab.lua` is clean, both files are `w/crlf`, and `./scripts/install.bat` deployed to every client folder.

---

_Reviewed: 2026-09-28T12:54:31Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
