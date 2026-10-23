---
phase: 76-buff-duration-on-bag-items
plan: 02
subsystem: tracker dialog (CDMTab.lua TRACKER_FIELDS)
tags: [bag-items, cooldown-buff, edit, dialog, greyed-state]
requires:
  - plan 76-01 (ns:IsEditableTracker admits bag items, ns:UpdateTrackedBuff routes them to ns:UpdateTrackedItemBuff)
  - Phase 74 greyed field state (enabled() hook, ApplyFieldEnabled)
provides:
  - NotItemField enabled() hook greying a bag item's existing fields
  - buff fields shown for bag items (CarriesCooldownBuff widened)
  - opts.follows on BuildFollowSpellIDField (an item's buff Aura ID never follows)
  - item portrait, "Edit Item Tracker" title, Advanced-first open for items
affects:
  - Phase 78 in-game checks
tech-stack:
  added: []
  patterns: [per-kind enabled() hook, compare-before-write portrait arm]
key-files:
  created: []
  modified:
    - CDMTab.lua
decisions:
  - auraID and endOnCast are hidden for a bag item through visible(), not greyed; it never had either value
  - Load prefill reads ns:TrackerLoad, so user kinds keep their mapping and a bag item shows Always
  - A bag item opens on the Advanced tab, where its only editable fields are
  - Plan-checker info applied, the portrait falls back to ns:ItemDisplayInfo(itemID).icon when the entry has no iconOverride
metrics:
  duration: ~12 min
  completed: 2026-10-22
  tasks: 2
  files: 1
requirements: [BUFFCD-05, BUFFCD-06]
---

# Phase 76 Plan 02: Buff-only edit dialog for bag items Summary

A bag item moved out of Suggested now opens "Edit Item Tracker" on the Advanced tab. The portrait shows the item's icon and name, and hovering it shows the item tooltip. Spell ID (empty), Duration, Cover all ranks and Load (Always) are shown greyed, labels included. The only editable fields are "Track buff duration", an Aura ID that starts empty and never follows, and Duration. They use the Phase 74 save rule. A Suggested tile still has no Edit entry.

## Tasks

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Greyed item fields, buff fields for items, non-following item Aura ID | c95049d | CDMTab.lua |
| 2 | Item portrait, Edit Item Tracker title, Advanced-first open, menu comment | 7b4a30f | CDMTab.lua |

## What changed

- **`CarriesCooldownBuff`** now also admits `ns.KIND.META_ITEM`.
- **`NotItemField`** is a new hook, declared above TRACKER_FIELDS. It is set as `enabled` on `spellID`, `duration`, `coverAllRanks` and `load`. Each of those keeps its `label` in state, so ApplyFieldEnabled greys the label too. A greyed field is not validated, so Spell ID's "> 0" check and Duration's non-empty check never block an item's Save.
- **`load` prefill** now reads `ns:TrackerLoad(ctx.editingKey, entry)`.
- **`BuildFollowSpellIDField`** has an optional `opts.follows(ctx)`, used in reset and prefill. Only `buffAuraID` passes it, and it is false for META_ITEM. With the box ticked and the Aura ID empty, "Enter the buff's Aura ID" fires (mitigates T-76-05). `auraID` and `castID` are unchanged.
- **`auraID` and `endOnCast`** are hidden for META_ITEM.
- **`spellPreview`** has a new item arm:
  - `itemTooltipProc` is built once, when the field is built.
  - OnEnter shows the item tooltip.
  - reset clears the item stamp.
  - prefill stashes the item's icon and label, falling back to `ns:ItemDisplayInfo` when there is no iconOverride.
  - update draws the item compare-before-write and returns before `ns:RefreshIDPreview`.
- **`EDIT_TITLE_BY_KIND`** gains `[ns.KIND.META_ITEM] = "Edit Item Tracker"`.
- **`dialog.OpenForEdit`** selects Advanced for a bag item and General for every other kind. The confirm handler is unchanged: plan 76-01 routes the save.
- **Comments updated:** the field-contract block (ctx kinds, the Advanced-tab bullet, the built-in sentences) and the tracked-tile menu comment.

## Verification

- Both task gates printed PASS. Before this plan, both would have failed, because NotItemField, the META_ITEM title row and the portrait item arm did not exist.
- `node scripts/aura-read-gate.js` passes.
- `stylua --check .` is clean.
- CDMTab.lua is `w/crlf` with no `\r\r`.
- `./scripts/install.bat` deployed to every client folder.
- In-game checks are deferred to Phase 78, by user decision.

## Deviations from Plan

- The plan-checker's optional info item was applied. When an item entry has no `iconOverride`, the portrait prefill falls back to `ns:ItemDisplayInfo(entry.itemID).icon`. This runs at edit time only, never on a render path.

Otherwise the plan was executed as written.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: CDMTab.lua modifications
- FOUND: c95049d, 7b4a30f
