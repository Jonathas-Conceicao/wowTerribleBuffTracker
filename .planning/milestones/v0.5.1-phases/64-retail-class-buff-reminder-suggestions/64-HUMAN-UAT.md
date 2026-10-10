---
status: complete
phase: 64-retail-class-buff-reminder-suggestions
source: [64-VERIFICATION.md]
started: 2026-09-30
updated: 2026-09-30
---

## Current Test

[awaiting human testing -- deferred to Phase 66 (Forever first, then retail). /reload is enough: the TOC did not change]

## Tests

### 1. Forever offer unchanged
expected: Forever: the class-buff Suggested offer is exactly as before -- no 6673, 465 or 21562 rows appear; paladin blessings still self-cast; Blood Pact still has no click; a lower-rank cast still starts a reminder (rank coverage unchanged).
result: passed (2026-10-01, Forever; and no Forever row is offered on retail)

### 2. Retail Mage: Arcane Intellect and Arcane Familiar (MREM-04)
expected: Retail Mage: Arcane Intellect is offered; Arcane Familiar is offered only with talent 205022 known; the two place as separate reminders. Arcane Familiar shows when aura 210126 is missing and hides when it is present (not kept hidden by the passive talent, review CR-01); with only Arcane Familiar placed, casting Arcane Intellect hides it once 210126 appears.
result: passed (2026-10-01, user: "mage is a full pass")

### 3. Each retail class is offered only its known rows (MREM-05)
expected: Priest Power Word: Fortitude, Druid Mark of the Wild and Symbiotic Relationship, Warrior Battle Shout, Shaman Skyfury and Lightning Shield (192106, added 2026-10-01), Evoker Blessing of the Bronze and Source of Magic, Paladin Devotion Aura -- each offered only to a character that knows it.
result: passed (2026-10-01, retail: Mage, Druid, Paladin, Shaman incl. Lightning Shield, Evoker, Priest, Warrior)

### 4. Mark of the Wild ID (review IN-03)
expected: With TBT's ID tooltip, confirm 102046 (the user's data) is the castable retail Mark of the Wild; the widely published ID is 1126. If it is wrong, the row is changed BEFORE anyone places it (the key is saved).
result: passed after fix (2026-10-01) -- originally an issue -- a retail Druid was offered no Mark of the Wild: 102046 is a same-named spell no druid knows, so the row never passed the known check. Row changed to 1126 before anyone placed it. Re-test: a Druid is offered Mark of the Wild, and it hides while the buff is up (confirm the aura reads as 1126 with TBT's ID tooltip).
re-test: passed (2026-10-01, user: "druid is a full pass")

### 4b. Symbiotic Relationship
expected: Offered only when known; clicks cast on the target.
result: passed (2026-10-01)

### 5. Rows with their own aura ID, and Devotion Aura
expected: Symbiotic Relationship hides on aura 474754 and Blessing of the Bronze on 381748. Devotion Aura shows only while none of Devotion (465), Concentration (317920) or Crusader (32223) Aura is up, with no timer.
result: passed (2026-10-01, retail: Symbiotic Relationship, Devotion Aura, Blessing of the Bronze)

### 6. Click targets
expected: Symbiotic Relationship and Source of Magic cast on the selected friendly target (no target: the game's default targeting); every other reminder still casts on the player. No ADDON_ACTION_BLOCKED.
result: passed (2026-10-01, user: "all trackers and clicks working on retail")

### 7. Lead window and click on a retail row
expected: A placed 60-minute retail row (e.g. Arcane Intellect) appears in its last 6 minutes with its remaining time, and a click recasts it.
result: passed (2026-10-01, retail)

### 8. Combat on retail
expected: Fight with retail class-buff reminders placed, including anything that changes your spells mid-combat (a form, a proc that swaps a spell): no reminder disappears or starts watching the wrong buff, and no errors appear.
result: passed (2026-10-01, retail combat and M+)

## Summary

total: 9
passed: 9
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
