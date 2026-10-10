---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
reviewed: 2026-10-10T16:55:51Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - Display.lua
  - MergeMode.lua
  - MergeReanchor.lua
  - Core.lua
  - scripts/aura-read-gate.js
  - scripts/migrate-dryrun.js
findings:
  critical: 0
  warning: 2
  info: 6
  total: 8
status: issues_found
---

# Phase 70: Code Review Report

**Reviewed:** 2026-10-10T16:55:51Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

The review covered `git diff f4b643b HEAD` for the six files: about 2,800 lines deleted and 145 added. Checks run against HEAD:

- **Deleted symbols.** No shipped Lua/XML/TOC file references any deleted symbol. That covers `AURA_UNITS`, `auraContainers`, `RefreshMergeAuraGroups`, `PlaceMergeAura`, `RefreshMergeAuraUnits`, `mergeAuraGroupsActive`, `MERGE_AURA_CONTAINER_LEVEL`, `mergeItemFrames`, `ClearMergeAuraLookupBlock`, `IsMergedEntryInPandemic`, `ResolveMergedAuraTiming`, `TryResolveFromSpellID`, `SafeAuraCall`, the relays, `mergedTime`, `ReadPandemicState`, `ReadDispelBorder`, `ApplyMergedAuraCooldown`, `itemCooldownSeen`, `categorySpellID`, `mergeRelayState`, `SetChargeCountRaised`, `ToggleMergeReanchorExperiment` and the `EXPERIMENT (MergeReanchor.lua)` markers.
- **ns members.** A mechanical scan found no `ns:`/`ns.` member that is used but never defined. The only hits were names inside comments.
- **Called identifiers.** Every identifier called in Display.lua, MergeMode.lua and MergeReanchor.lua is either a local defined earlier in the same file or a WoW/Lua global. No upvalue-order trap was found.
- **Load-time reads.** All resolve: `ns.SPELL_CATEGORY_ICON` and `ns.SPELL_CATEGORY_TITLE_KEY` come from Core.lua, which loads first. The `Enum.CooldownSetSpellFlags` reads are guarded. `ns.MarkMergedPlacementDirty` is nil-guarded in `RefreshContainerSettings`, and MergeReanchor.lua loads before Display.lua anyway.
- **Unused locals.** None remain in the three Lua files.
- **Custom trackers.** Custom cooldown trackers keep everything they need. `ApplyCooldownSlot` → `ApplyUserCooldown`, `ApplyChargeCount` (sticky `chargeCapable`), `ApplyItemCount`, `ApplyCooldownHandle` and `ApplyCooldownGrey` are all intact. The deleted `equipSlot`/`spellCategoryID`/relay arms were reachable only by merged entries: no saved tracker entry carries `equipSlot` or `spellCategoryID`; CDMTab only stores `iconOverride`. A custom bag-item tracker with no typed duration ends at the same "clear and full colour" terminus it reached before.
- **Reminders and buffs** are untouched. Merged entries are USER_CD/USER_BUFF, so `ns:ReminderGate` returns nil and no click stamp can land on a merged cell.
- **Merged branches in Display.** The attach arm, the preview-placeholder arm and the fail-closed arm are all correct. The fail-closed arm really is unreachable: `mergeShownSlots` is filled only when `mergeMode == true`, and `ns:SetMergeMode(false)` wipes it inline. Centered counting through `SlotDraws` → `entry.cdmShown` agrees with the render chain on every reachable path.
- **Saved-flag clear.** Core.lua:1891 and its migrate-dryrun mirror (line 488, case N) agree. All three gates pass: `stylua --check .`, `aura-read-gate.js` (both normal and `--selftest`) and `migrate-dryrun.js --selftest`.
- **Central claim of 70-MERGE-PATH-REVIEW.md.** `cellByID`/`idByCell` are one-to-one, and that holds up against the code. Every write is paired (MergeReanchor.lua:505-506). The old cell is cleared only if it still maps back (:488-490). The evicted id loses every per-id row (:500-503). The prune clears `idByCell` only on a match (:565-567). The off path wipes both (:438-439). Nothing else writes either table.
- **C8's "count equality implies set equality".** This also holds. A miscount would need an id attached and then evicted in the same render, which needs one cell attached twice in one render. That cannot happen with per-container pools indexed by slot.

No blockers. The two warnings are (1) a factual error in the whole-path review that would lead the cleanup phase to delete a live constant, and (2) aura-path relics left in the mirror and the diagnostics, with comments that claim consumers which no longer exist.

## Warnings

### WR-01: Whole-path review (and 70-04/70-05 summaries) wrongly says `ns.SPELL_CATEGORY_COMBAT_POTION` has no reader; deleting it would break the Pot meta-tracker icon

**File:** `.planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-MERGE-PATH-REVIEW.md:198-199` (also `70-04-SUMMARY.md:35`, `70-05-SUMMARY.md:53`); reader at `Providers.lua:783`; definition at `Core.lua:166`
**Issue:** The review's "Observations outside the merged path" says the constant "lost its only reader with the engine aura containers" and leaves it to the cleanup phase. That is false. `MetaItemPotProviderMixin:GetDisplayInfo` reads it on the unresolved path:
```lua
return UnresolvedDisplayInfo(POT_KEY, "Damage Pot", ns.SPELL_CATEGORY_ICON[ns.SPELL_CATEGORY_COMBAT_POTION])
```
The Core.lua comment at :164-165 even names the pot meta-tracker as the reason the constant exists. If the cleanup phase acted on this note, `ns.SPELL_CATEGORY_ICON[nil]` would return nil. The Pot tracker would then lose its combat-potion icon until a potion resolves. Three planning artifacts repeat the claim, so the cleanup phase is likely to act on it.
**Fix:** Correct the observation in all three files. For example: "`ns.SPELL_CATEGORY_COMBAT_POTION` is still read by `Providers.lua:783` (Pot meta-tracker unresolved icon); keep it." Remove it from the cleanup-phase candidates.

### WR-02: Mirror still builds aura-path-only fields, and their comments name consumers that this phase deleted

**File:** `MergeMode.lua:51-54, 239-255, 451-457, 463-480, 1518-1527`
**Issue:** The redraw path that consumed `linkedSpellIDs`, `hideAura`, `hasCharges` and `selfAura` is gone. A grep shows the only remaining reader of all four is `ns:PrintMergeDiagnostics`. The comments still describe the deleted behaviour as live:
- :51-54: `HIDE_AURA` "must NOT swap its cooldown sweep for its aura's, which is the one exception to the aura-wins rule below". No aura-wins rule exists any more.
- :451-457: `linkedSpellIDs` "Matching only on spellID is why those entries never resolved". There is no aura lookup left to resolve.
- :468-472: `hasCharges` "Display uses it to pick the recharge handle over the cooldown handle". Display never reads it. Display.lua:1162 says so explicitly, and merged entries never reach `ApplyCooldownSlot` now.
- :463-467: `hideAura` "reading it per frame would mean a bit.band per merged slot per tick". Nothing reads it per frame or at all.

`CopyLinkedSpellIDs` still allocates one table per entry on every mirror rebuild, for a diagnostic count only. `/tbt merge` still prints `linked=`, `cdmCharges`, `hideAura` and a yellow-highlighted `notSelfAura` for most entries. That highlight flags nothing actionable now. 70-CONTEXT.md says the diagnostics should be "trimmed to what still exists (mirror, shown slots, placement)". These are aura-resolution relics, and the misleading comments will mislead the next reader who looks for the consumer.
**Fix:** Either delete the four fields, `CopyLinkedSpellIDs`, `HIDE_AURA` and the matching diagnostic bits (keeping `id`, `spell`, `shown`, `visible`, `cell`, `equipSlot`, `itemIcon`, `cat`), or keep them deliberately as diagnostic-only data and rewrite each comment to say so:
```lua
-- Diagnostic only (/tbt merge): no render path reads this since Phase 70.
hasCharges = info.charges == true,
```
At minimum, drop the yellow colour on `notSelfAura`, since it no longer signals a problem.

## Info

### IN-01: Stale comments in Display.lua describe deleted merged/aura machinery

**File:** `Display.lua:12-15, 576-581, 864-870`
**Issue:**
- :12-15 justifies `ns:GridSlotPlacement` as shared with "the engine aura slots MergeMode hands to Blizzard". Those slots are deleted, and the function's only caller is now Display.lua:1589.
- :580-581 says "Phase 40 will put a merged CDM Essential cooldown beside a TBT one in the same container, where any difference in font, size or position would show". Merged cells now hold Blizzard's own frame, not a TBT-drawn count.
- :866 says `ApplyCooldownGrey` was "Split out of ApplyCooldownHandle ... so the aura branch can reach it too". The aura branch (`ApplyMergedAuraCooldown`) is deleted, and `ApplyCooldownHandle` is the only caller.

**Fix:** Reword the three comments to the current state. Optionally make `GridSlotPlacement` a file-local, since it no longer has a cross-file caller.

### IN-02: `SlotDraws` does not mirror the fail-closed merged arm

**File:** `Display.lua:88-91` vs `Display.lua:1617-1621`
**Issue:** The function's own header (:76-80) says it must mirror `RenderIconContainer`'s branch chain exactly. For a merged entry it returns `entry.cdmShown == true` whether or not the re-anchor arm is taken. The fail-closed arm always hides the icon. If that arm were ever reached, a centred run would reserve a cell for an icon that never draws, leaving a gap. Today the arm is unreachable (see Summary), so this is latent.
**Fix:**
```lua
if entry.isMerged then
	return ns:IsMergeReanchorActive() and entry.cdmShown == true
end
```

### IN-03: Per-tick work on hidden, attached merged bar rows

**File:** `Display.lua:1322-1417`
**Issue:** The relays are gone, so a live merged bar row only needs to be laid out, styled and attached. Every 50 ms it still runs `ApplyCachedIcon`, `bar.label:SetText`, `statusBar:SetValue(0)`, `pip:Hide()` and `time:SetText("")` on a bar that is then hidden (:1433-1435). That work is needed only for the preview placeholder (`cdmFrameVisible == false`). CLAUDE.md asks for redundant per-frame work to be flagged after each commit.
**Fix:** In the loop, test `reanchorHere and slot.isMerged and slot.cdmFrameVisible ~= false` right after `ApplyBarStyle`. In that case hide the bar, attach it and `goto`/skip the content block. Otherwise fall through as now.

### IN-04: Whole-path review C5 says a viewer-less container passes `false`; it passes `nil`

**File:** `.planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-MERGE-PATH-REVIEW.md:88`; code at `Display.lua:1243, 1501`
**Issue:** `reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])` evaluates to `nil`, not `false`, when neither lookup resolves. The fail-closed conclusion still holds: an item frame's parent is never nil, so `parent ~= viewerByID[id]` releases it. The stated mechanism is wrong, though.
**Fix:** Change "passes `false`" to "passes `nil`" in C5.

### IN-05: migrate-dryrun mirrors the new silent clear but not its sibling `dialogStyle` clear

**File:** `scripts/migrate-dryrun.js:487-488`; `Core.lua:1888-1891`
**Issue:** The block is labelled "Core.lua ADDON_LOADED defaults, in source order". It now mirrors `ns.db.mergeReanchorExperiment = nil` but still omits the `ns.db.dialogStyle = nil` line just before it. The omission predates this phase, but the new line makes the mirror visibly inconsistent: a SavedVariables file that carries `dialogStyle` dry-runs without the clear the client performs.
**Fix:** Add, before the new line:
```js
if (g('dialogStyle') != null) { db.delete('dialogStyle'); log.push('clear dialogStyle (dev-only)'); }
```

### IN-06: MergeReanchor `OPEN ITEM` block mixes resolved and open items

**File:** `MergeReanchor.lua:166-195`
**Issue:** The `OPEN ITEM` block heads a list in which Visibility is marked "RESOLVED" and Click to Cast "not applicable". Only the Show Timer swipe gaps and the release-name lag are actually open. Now that the prototype has become the only path, the "OPEN ITEM" framing makes the list read as unfinished work.
**Fix:** Split the block into "Known limitations" (the swipe gaps and release-name lag) and "Settled" (Hide When Inactive, Visibility, Click to Cast). Alternatively, retitle it.

---

_Reviewed: 2026-10-10T16:55:51Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
