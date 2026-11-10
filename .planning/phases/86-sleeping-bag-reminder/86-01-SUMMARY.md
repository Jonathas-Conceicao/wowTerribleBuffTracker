---
phase: 86-sleeping-bag-reminder
plan: 01
subsystem: reminders
tags: [forever, reminders, suggested, load-rule, click]
requires: [CLICK-07 item click path, MetaReminderRow table]
provides: [Well-Rested reminder row, def.offerItem opt, ns:MetaReminderOfferItem, item-gated Suggested offer, item-offered load rule]
affects: [Providers.lua, Core.lua, ReminderClick.lua, docs/REMINDERS.md]
tech-stack:
  added: []
  patterns: [load-time row opt switching offer/load rule for one row, guarded C_Item.GetItemCount read]
key-files:
  created: []
  modified: [Providers.lua, Core.lua, ReminderClick.lua, docs/REMINDERS.md]
key-decisions:
  - "Opt name offerItem; accessor ns:MetaReminderOfferItem; file-local OfferItemInBags declared above ns:MetaReminderSuggestionKeys"
  - "No memo or new event hook for the offer: the Suggested list is rebuilt on every RefreshTBTSections and a BAG_UPDATE while the CDM is open already redraws"
  - "Doc class cell 'General' (sorts between Druid and Hunter, no doc-check change)"
requirements-completed: [SBAG-01, SBAG-02, SBAG-03, SBAG-04]
metrics:
  duration: "~10 min"
  completed: 2026-11-10
  tasks: 2
  files: 4
---

# Phase 86 Plan 01: Sleeping Bag Reminder Summary

Forever-only Well-Rested reminder (429959, 120 min) offered in Suggested only while the Cozy Sleeping Bag (211527) is in the bags, loaded under When known without asking a known spell, and clicked through the existing CLICK-07 item path.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Well-Rested row, def.offerItem, ns:MetaReminderOfferItem, item-gated Suggested offer | ca251c6 | Providers.lua |
| 2 | Load rule and tooltip reason, comment updates, doc row | f5c3356 | Core.lua, ReminderClick.lua, docs/REMINDERS.md |

## Gate results

- `node .planning/phases/86-sleeping-bag-reminder/86-check.js`: 18 FAIL before, "all checks passed" after
- `node scripts/reminders-doc-check.js`: `REMINDERS-DOC CHECK PASS (133 Forever IDs, 15 retail IDs, 39 rows)`
- `node scripts/reminders-doc-check.js --selftest`: `REMINDERS-DOC SELFTEST PASS (46 cases)`
- `node scripts/aura-read-gate.js`: `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`
- `stylua .` then `stylua --check .`: clean
- `git ls-files --eol`: Providers.lua, Core.lua, ReminderClick.lua, docs/REMINDERS.md all `w/crlf` (unchanged)

## Code trace

- (a) Retail: the row has no client opt, so MetaReminderRow returns before registering it; no def carries offerItem, OfferItemInBags is never called, ns:MetaReminderOfferItem returns nil for every key, and every offer and load is unchanged.
- (b) Forever, bag in the bags: Suggested lists metaReminder:429959; without it, it is not listed. The list follows the bag on the next CDM open, drag, or a BAG_UPDATE while the CDM is open (ns:IsSuggestedKeyResolvable's memo is never asked for a metaReminder key).
- (c) Placed, When known, character without the bag: the new RebuildTrackerLoad branch sets loaded = true, so the reminder shows while 429959 is missing.
- (d) Load = Never: decided by the NEVER branch above the new one; TrackerLoadReason returns "Load is set to Never" before the new nil return.
- (e) Click with the bag: PickUseItem({ { 211527, 1 } }) returns "item:211527", overlay type1 "item". Without: nil, no overlay, no error (castID false gives no cast fallback). A bag change re-marks through ns.reminderItemClickActive, which is true while the icon is a shown reminder with useItems.
- (f) Every other row: def.offerItem is nil, so the SuggestionKeys else branch and the RebuildTrackerLoad known-spell branch run as before (gate P5/P6/C1 confirm).
- (g) Blood Pact and the familiar keep their knownID tooltip line: the new TrackerLoadReason branch is false for them.

## Post-commit performance and cleanup review

- OfferItemInBags runs only at render time inside ns:MetaReminderSuggestionKeys, once per item-offered row (one row), with one pcall and no table. It is not on a per-frame path.
- RebuildTrackerLoad's new branch adds one map read (ns:MetaReminderOfferItem) per numeric metaReminder entry on the event-driven rebuild; nothing per frame, no allocation.
- TrackerLoadReason's branch runs at tooltip hover only.
- No dead code was added. The click path has no code change (gate R1). The useItems "item:<id>" string is built once at load by the existing MetaReminderRow.

## Deviations from Plan

- I skipped the plan's `./scripts/install.bat` deploy step because the orchestrator's rules say not to run install.bat. The user deploys.
- Reflowed the reworded BAG_UPDATE_DELAYED comment onto three lines so no line is overlong. This is a comment-only change.

Otherwise the plan ran as written.

## Known Stubs

None. The row comment keeps "(unverified in game)" on purpose. In-game checks belong to Phase 89.

## Self-Check: PASSED

- FOUND: Providers.lua, Core.lua, ReminderClick.lua, docs/REMINDERS.md changes
- FOUND: ca251c6, f5c3356
