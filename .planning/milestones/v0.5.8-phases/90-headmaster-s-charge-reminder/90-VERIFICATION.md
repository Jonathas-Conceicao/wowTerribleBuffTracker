---
phase: 90-headmaster-s-charge-reminder
verified: 2026-11-26T18:22:11Z
status: passed
score: 7/7 must-haves verified (4/4 roadmap success criteria at source level)
overrides_applied: 0
deferred:
  - truth: "In-game behaviour on Forever: offer follows equip/unequip, reminder shows/hides on aura 18264, slot-16 click uses the staff, no-op when unequipped"
    addressed_in: "Phase 92"
    evidence: "Phase 92 Testing Pass, VER-17: 'the user checks the reminder in game on Forever'; the row keeps '(unverified in game)' until then"
human_verification:
  - test: "On a Forever character, open the CDM with Headmaster's Charge (13937) equipped in the main hand, then unequip it with the CDM still open"
    expected: "Suggested shows the Headmaster's Charge reminder while equipped and drops it within a frame after unequip (and re-adds it on re-equip)"
    why_human: "Depends on PLAYER_EQUIPMENT_CHANGED payload and GetInventoryItemID in the live Forever client"
  - test: "Place the reminder, log onto a Forever character without the staff"
    expected: "The reminder loads and shows while buff 18264 is missing; Load = Never hides it"
    why_human: "Load and aura display run only in game"
  - test: "With the staff equipped and buff 18264 missing, click the reminder out of combat; then unequip the staff and click again"
    expected: "First click uses the staff (applies 18264, reminder hides); second click does nothing, never equips the staff, no Lua error"
    why_human: "Secure action behaviour (type1 item, item '16') can only be observed in the client"
  - test: "Have another player's Headmaster's Charge apply 18264 to you"
    expected: "The reminder hides while the aura is up"
    why_human: "Aura readability of a party buff on Forever is runtime-only"
---

# Phase 90: Headmaster's Charge Reminder Verification Report

**Phase Goal:** A Forever player carrying Headmaster's Charge is reminded when the party Intellect buff is missing, and a click uses the staff
**Verified:** 2026-11-26T18:22:11Z
**Status:** passed (source level; in-game checks deferred to Phase 92 / VER-17 per the roadmap)
**Re-verification:** No — initial verification

## Goal Achievement

### Roadmap Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Forever: Suggested offers the row with staff equipped, not without; retail never registers it | VERIFIED (source) | Providers.lua:1261 row has no `client` opt -> defaults to "forever"; MetaReminderRow returns early on retail (1155-1159) before indexing or writing `metaReminderOfferSlots`. MetaReminderSuggestionKeys takes `if def.offerSlot then offered = ns:ItemEquippedInSlot(...)` branch |
| 2 | Placed reminder shows while 18264 missing on every Forever character, hides while aura up | VERIFIED (source) | Core.lua:702-708 and 1350-1358 SBAG-03 branches key on `ns:MetaReminderOfferItem(spellID)`, which returns 13937 for this row -> loaded regardless of staff; Never decided earlier (1347). Aura = spellID 18264 (no auraID opt) via the existing meta-reminder aura path |
| 3 | Click with staff equipped uses slot 16; unequipped does nothing/no equip/no error; overlay follows equipment changes | VERIFIED (source) | ReminderClick.lua Flush: `slotAttr, usesSlot = ns:ReminderEquippedUse(entry)`; `itemAttr = useItems and PickUseItem(useItems) or slotAttr`; Place sets type1 "item". ReminderEquippedUse returns "16" only when `GetInventoryItemID("player",16) == 13937`, else nil (no overlay, no skip, castID false -> no cast). Core.lua PLAYER_EQUIPMENT_CHANGED else-branch marks clicks dirty for slot 16 while `reminderItemClickActive` |
| 4 | docs/REMINDERS.md lists the row; doc-check and --selftest pass | VERIFIED | Ran both: PASS (144 Forever IDs, 15 retail IDs, 52 rows); SELFTEST PASS (48 cases) |

### Observable Truths (PLAN must_haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | HCHG-01 row `MetaReminderRow(18264, 15, nil, nil, false, { offerItem = 13937, offerSlot = 16 })`, comment starts "-- General: Headmaster's Charge", ends "(unverified in game)" | VERIFIED | Providers.lua:1261, exact text |
| 2 | HCHG-02 offer via ns:ItemEquippedInSlot (pcall, issecretvalue first, false on failure); Well-Rested still ItemInBags; others ResolveSpellKnown | VERIFIED | Providers.lua:1587-1593 (missing-API guard, pcall, `not issecretvalue(equipped) and type == number and equipped == itemID`); branch order offerSlot -> offerItem -> known spell |
| 3 | HCHG-02 D-04 PLAYER_EQUIPMENT_CHANGED -> MarkItemCatalogueDirty when IsMetaReminderOfferSlot(slot) | VERIFIED | Core.lua else-branch (~2222-2235); `slot = ...` is event payload; IsMetaReminderOfferSlot guards secret/non-number. MarkItemCatalogueDirty -> CDMTab.lua RequestItemCatalogueRebuild (configOpen-gated, once per frame) -> RefreshTBTSections |
| 4 | HCHG-03 load through existing SBAG-03 branches, no load-rule change | VERIFIED | `git diff aafbafb..HEAD -- Core.lua` touches only the event handler; load branches unchanged and satisfied by offerItem |
| 5 | HCHG-04 overlay type1 "item", item "16" (def.slotAttr built at load) only while 13937 in slot 16; never "item:13937" | VERIFIED | Providers.lua:1172 `slotAttr = offerSlot and tostring(offerSlot)`; ReminderEquippedUse 1477-1489; grep finds "item:13937" only in a ReminderClick.lua comment |
| 6 | HCHG-04 D-08 PLAYER_EQUIPMENT_CHANGED marks clicks dirty while reminderItemClickActive; Flush sets it for slot reminder | VERIFIED | Flush `if useItems or usesSlot then sawItemReminder = true`; usesSlot true for the row even when unequipped; Flush returns early and stays dirty in combat |
| 7 | DOC-09 doc row links /forever/spell=18264 and /forever/item=13937; doc-check collects offerItem; PASS line exact | VERIFIED | docs/REMINDERS.md General row; reminders-doc-check.js parseCode offerItem + codeSets `offerItem of`; output matches expected string exactly |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| Providers.lua | row, offerSlot/slotAttr, ItemEquippedInSlot, IsMetaReminderOfferSlot, ReminderEquippedUse, offer branch | VERIFIED | All present, substantive, called from ReminderClick.lua and Core.lua |
| ReminderClick.lua | Flush uses ns:ReminderEquippedUse(entry) | VERIFIED | Wired into Place |
| Core.lua | `ns:IsMetaReminderOfferSlot(slot)` re-marks | VERIFIED | Event registered at Core.lua:1941 |
| scripts/reminders-doc-check.js | offerItem collection + 2 selftests | VERIFIED | Both cases run in the 48-case selftest |
| docs/REMINDERS.md | forever/item=13937 | VERIFIED | |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| MetaReminderSuggestionKeys | ns:ItemEquippedInSlot(def.offerItem, def.offerSlot) | WIRED |
| ReminderClick Flush | ns:ReminderEquippedUse -> ItemEquippedInSlot -> def.slotAttr -> Place type1 "item" | WIRED |
| Core PLAYER_EQUIPMENT_CHANGED | MarkItemCatalogueDirty / MarkReminderClicksDirty via `ns.IsMetaReminderOfferSlot and ns:IsMetaReminderOfferSlot(slot)` | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real | Status |
|----------|------|--------|------|--------|
| Suggested tile | offered | GetInventoryItemID("player", 16) per RefreshTBTSections | Yes (live API) | FLOWING |
| Click overlay | itemAttr "16" | def.slotAttr gated by live equipped read per Flush | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Doc/code agreement | `node scripts/reminders-doc-check.js` | REMINDERS-DOC CHECK PASS (144 Forever IDs, 15 retail IDs, 52 rows) | PASS |
| Doc-check selftest | `node scripts/reminders-doc-check.js --selftest` | REMINDERS-DOC SELFTEST PASS (48 cases) | PASS |
| Formatting | `stylua --check .` | exit 0 | PASS |
| Aura-read gate (DTRK-06 regression) | `node scripts/aura-read-gate.js` | AURA-READ GATE PASS | PASS |
| Line endings | `git ls-files --eol` on 5 touched files | Lua files `attr/text eol=crlf w/crlf`; .md/.js `w/crlf` | PASS |

### Probe Execution

Not applicable: no probes declared; the doc-check and its selftest were run directly above.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| HCHG-01 | 90-01 | SATISFIED (source) | Truth 1 |
| HCHG-02 | 90-01 | SATISFIED (source) | Truths 2, 3 |
| HCHG-03 | 90-01 | SATISFIED (source) | Truth 4 |
| HCHG-04 | 90-01 | SATISFIED (source) | Truths 5, 6 |
| DOC-09 | 90-01 | SATISFIED | Truth 7, both commands pass |

REQUIREMENTS.md maps exactly HCHG-01..04 and DOC-09 to Phase 90; all are claimed by 90-01-PLAN. No orphaned IDs. (Checkboxes in REQUIREMENTS.md remain `[ ]`/Pending; updating them is the orchestrator's job.)

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (5 touched files) | - | TBD/FIXME/XXX | none found | - |
| Core.lua | ~2231 | Suggested redraw rides on the item-catalogue dirty flag (bag walk on slot-16 change) | Info | Review IN-01; works today, fragile coupling. Candidate for Phase 91 cleanup |
| scripts/reminders-doc-check.js | 343-350 | `offerSlot` not validated as an integer literal | Info | Review IN-03 |
| scripts/reminders-doc-check.js | 1138-1141 | offerSlot assertion is vacuous | Info | Review IN-04 |
| .planning/phases/90-*/*.md | - | working copies are `w/lf` while earlier phases' planning docs are `w/crlf` | Info | Not a source file; index is `i/lf` either way, so no content change |

No blockers. Scope rule respected: every new branch is reached only via `def.offerSlot` (this row alone) or the slot-16 gate, empty on retail.

### Human Verification Required (deferred to Phase 92, VER-17)

1. **Offer follows equip** — CDM open on Forever, equip/unequip the staff; Suggested adds/drops the tile.
2. **Load everywhere** — placed reminder shows on a staff-less Forever character while 18264 is missing; Never hides it.
3. **Click** — equipped: uses the staff; unequipped: nothing happens, nothing equipped, no Lua error.
4. **Aura hide** — another player's staff buff hides the reminder.

These are listed per the roadmap's explicit deferral of in-game checks to Phase 92 and do not block this phase.

### Gaps Summary

None at source level. All seven plan truths and four roadmap success criteria are backed by code that exists, is substantive, is wired, and reads live data; the doc check, selftest, stylua and aura gate all pass. The remaining risk is purely in-game (secure item action on Forever, event payload, aura visibility), which the roadmap assigns to Phase 92.

---

_Verified: 2026-11-26T18:22:11Z_
_Verifier: Claude (gsd-verifier)_
