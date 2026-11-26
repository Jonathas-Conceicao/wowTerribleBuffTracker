---
phase: 91-cleanup
requirements: [CLEAN-03]
status: complete
completed: 2026-11-26
---

# Phase 91: Cleanup — Summary

Run inline by the autonomous orchestrator (the cleanup was one script edit; no planner/executor
agents were spawned for it). Scope: the code v0.5.8 introduced only (PROJECT.md "No refactors during
cleanup phases").

## Checks (CLEAN-03)

| Check | Result |
|-------|--------|
| Unused code the milestone introduced | None. `ns:ItemEquippedInSlot`, `ns:ReminderEquippedUse`, `ns:IsMetaReminderOfferSlot`, `metaReminderOfferSlots`, `def.offerSlot`, `def.slotAttr` each have a caller |
| Duplication the milestone introduced | None to unify. `ns:ItemEquippedInSlot` sits beside `ns:ItemInBags` by design: different API, same guard shape, each the single read for its case |
| Hot paths touched | `ReminderClick.lua` Flush adds one map read per clickable icon per flush (never per frame); Core's PLAYER_EQUIPMENT_CHANGED branch adds one table read, and for slot 16 on Forever a flag-only, CDM-open-only, coalesced redraw. No allocation |
| `stylua .` | No diff |
| Line endings | `Core.lua`, `Providers.lua`, `ReminderClick.lua`, `docs/REMINDERS.md`, `scripts/reminders-doc-check.js` all `w/crlf` |
| Release scripts | `install.*`, `release.bat`, `.github/`, `.pkgmeta`, the TOC: untouched by the milestone |
| `node scripts/aura-read-gate.js` | PASS |

## Phase 90 review Info items

- **IN-01 (accepted, no change):** the Suggested redraw on a slot-16 change goes through
  `ns:MarkItemCatalogueDirty`, a coalesced rescan that runs only while the CDM is open. Equipping
  the staff from the bags already fires BAG_UPDATE, which triggers the same rescan, so the added
  cost is nil in practice; a Suggested-only redraw would be new machinery.
- **IN-02:** resolved in Phase 90 (WoWUI `forever-beta` matches retail).
- **IN-03 (fixed):** `scripts/reminders-doc-check.js` now reports an `offerSlot` that is not an
  integer literal, or that has no `offerItem` beside it.
- **IN-04 (fixed):** the vacuous `item:16`/`spell:16` assertion is removed; two selftest cases cover
  IN-03 instead. `--selftest`: 50 cases PASS. `node scripts/reminders-doc-check.js`: PASS (144 Forever
  IDs, 15 retail IDs, 52 rows).
