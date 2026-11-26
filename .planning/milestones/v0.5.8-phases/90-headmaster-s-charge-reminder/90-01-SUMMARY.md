---
phase: 90-headmaster-s-charge-reminder
plan: 01
subsystem: reminders
tags: [forever, reminder, item-click, secure-action, doc-check]
requires:
  - Phase 86 Well-Rested item-offered row (offerItem, SBAG-03 load branches, CLICK-07 item click)
provides:
  - Headmaster's Charge reminder row (18264) on Forever
  - def.offerSlot / def.slotAttr row options
  - ns:ItemEquippedInSlot, ns:IsMetaReminderOfferSlot, ns:ReminderEquippedUse
  - PLAYER_EQUIPMENT_CHANGED offer-slot re-marks in Core.lua
  - offerItem collection in scripts/reminders-doc-check.js
affects: [Providers.lua, ReminderClick.lua, Core.lua, scripts/reminders-doc-check.js, docs/REMINDERS.md]
tech-stack:
  added: []
  patterns:
    - load-time attribute string (def.slotAttr) so Flush allocates nothing
    - load-time offer-slot set read by a guarded ns accessor from Core (Core loads before Providers)
key-files:
  created: []
  modified:
    - Providers.lua
    - ReminderClick.lua
    - Core.lua
    - scripts/reminders-doc-check.js
    - docs/REMINDERS.md
decisions:
  - "D-04: BAG_UPDATE does not fully cover equipment changes (not ordered after the slot update; does not fire when no bag is touched), so Core's PLAYER_EQUIPMENT_CHANGED branch calls ns:MarkItemCatalogueDirty() for an offer slot only (slot 16 on Forever, never on retail)"
  - "The slot click is item \"16\" (UseInventoryItem), never item:13937 (which would equip the staff from the bags), and is placed only while 13937 is in slot 16"
metrics:
  duration: ~20 min
  completed: 2026-11-26
---

# Phase 90 Plan 01: Headmaster's Charge Reminder Summary

Forever-only reminder for the Headmaster's Charge party Intellect buff (18264), offered in Suggested
only while the staff 13937 is equipped in the main hand, loaded on every character once placed, and
clickable through main-hand slot "16" only while the staff is there.

## What was built

- **Providers.lua (HCHG-01/02/04):** `MetaReminderRow(18264, 15, nil, nil, false, { offerItem = 13937, offerSlot = 16 })`
  under General after Well-Rested, comment ending `(unverified in game)`. MetaReminderRow now reads
  `opts.offerSlot`, stores `def.offerSlot` and the load-built `def.slotAttr = "16"`, and records the
  slot in a file-local `metaReminderOfferSlots` set (declared above MetaReminderRow; empty on retail
  because the client gate returns first). New `ns:ItemEquippedInSlot(itemID, slot)` (pcall-guarded
  `GetInventoryItemID`, missing-API check, `issecretvalue` before comparison),
  `ns:IsMetaReminderOfferSlot(slot)` (secret/non-number guard, one table read) and
  `ns:ReminderEquippedUse(entry)` (returns `slotAttr, true` while equipped, `nil, true` otherwise for
  the slot row, `nil, false` for everything else incl. a nil entry). `ns:MetaReminderSuggestionKeys`
  asks the slot for an `offerSlot` row, the bags for other `offerItem` rows, the known spell otherwise.
- **ReminderClick.lua (HCHG-04):** Flush reads `ns:ReminderEquippedUse(entry)`; `sawItemReminder` is
  set for a slot reminder too; `itemAttr = useItems and PickUseItem(useItems) or slotAttr`. Place is
  untouched: with the staff equipped it writes type1 "item" / item "16". Header and Flush comments
  updated.
- **Core.lua (D-04, D-08):** the PLAYER_EQUIPMENT_CHANGED half of the shared branch now reads the slot
  payload and, only for an offer slot, calls `ns:MarkItemCatalogueDirty()` and (while
  `ns.reminderItemClickActive`) `ns:MarkReminderClicksDirty()`. BAG_UPDATE_DELAYED body unchanged; no
  load-rule change (D-05).
- **scripts/reminders-doc-check.js (DOC-09):** parses `offerItem` as an integer literal (problem
  otherwise) and collects `item:<id>` per client; header comment updated; two new selftest cases.
- **docs/REMINDERS.md (D-10):** one General row for 18264 with /forever/spell=18264 and
  /forever/item=13937 links, `15 min`, `none`.

## Gate results

| Gate | Before | After |
|------|--------|-------|
| Task 1 (Providers.lua identifiers, row, crlf) | FAIL | PASS |
| Task 2 (ReminderClick/Core lines; MarkReminderClicksDirty 2->3, MarkItemCatalogueDirty 1->2) | FAIL | PASS |
| Task 3 RED selftest | 2/48 failed (both offerItem cases, for the right reason) | - |
| Task 3 (doc check, selftest, stylua --check, 5x w/crlf) | FAIL (142/51, 46 cases) | PASS |

- `node scripts/reminders-doc-check.js`: `REMINDERS-DOC CHECK PASS (144 Forever IDs, 15 retail IDs, 52 rows)`
- `node scripts/reminders-doc-check.js --selftest`: `REMINDERS-DOC SELFTEST PASS (48 cases)`, 2 lines `SELFTEST PASS offerItem`
- Code lines naming `item:13937` in Providers.lua / ReminderClick.lua: 0
- `git diff Core.lua | grep -c MetaReminderOfferItem`: 0; Core diff is one hunk inside the equipment branch
- `git ls-files --eol`: all five files `w/crlf`; CHANGELOG.md and README.md untouched
- `./scripts/install.bat`: deployed 23 files (version v0.5.7-9-g0f12d2d-dev) to _retail_, _ptr_,
  _beta_, _forever_ and _classic_era_

## Code trace (no Lua runs here; in-game verification is Phase 92, VER-17)

- (a) Retail: the row is not registered, `metaReminderOfferSlots` is empty, `ns:IsMetaReminderOfferSlot`
  is false for every slot, `ns:ReminderEquippedUse` returns `nil, false` for every entry: retail unchanged.
- (b) Forever, staff in slot 16: Suggested lists `metaReminder:18264`; staff in bags or absent: not
  listed; equipping/unequipping with the CDM open redraws via PLAYER_EQUIPMENT_CHANGED ->
  MarkItemCatalogueDirty (coalesced, CDM-open-only).
- (c) Placed, When known, a character without the staff: loaded through the SBAG-03 offerItem
  branches, shown while 18264 is missing, hidden while the aura is up; Never: not loaded.
- (d) Click with the staff in slot 16: type1 "item", item "16" -> UseInventoryItem(16). Without it:
  itemAttr nil and castID false, so neither the placing branch nor the skip runs: no overlay, no
  retry, no error, nothing equipped.
- (e) Well-Rested and every other row: `def.offerSlot` nil, so their offer, load and click paths are
  unchanged.

## Commits

- dd11ed2 feat(90-01): Headmaster's Charge row with equipped-slot offer and click accessor
- 0cffe71 feat(90-01): slot click overlay and PLAYER_EQUIPMENT_CHANGED re-marks for Headmaster's Charge
- 999f2cc test(90-01): add failing offerItem doc-check selftest cases
- 0f12d2d feat(90-01): doc-check collects offerItem IDs; Headmaster's Charge doc row

## Deviations from Plan

None in code. Process note: Task 3 (tdd="true") was committed as two commits, a RED `test(90-01)`
commit followed by the GREEN `feat(90-01)` commit, per the executor's TDD gate protocol.

## TDD Gate Compliance

RED commit 999f2cc (both new cases failed: collector absent) precedes GREEN commit 0f12d2d.

## Post-commit performance review

Flush adds one `ns:ReminderEquippedUse` call per shown icon: an early return for non-reminder or
non-slot rows, one map read, and one pcall only for the Headmaster's Charge row; no allocation (the
"16" string is built at load). The Core branch adds one table read per PLAYER_EQUIPMENT_CHANGED and
work only for slot 16 on Forever. No dead code introduced.

## Known Stubs

None.

## Self-Check: PASSED
