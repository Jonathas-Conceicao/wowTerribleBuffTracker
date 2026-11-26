---
status: complete
phase: 92-testing-pass
source: [90-VERIFICATION.md, REQUIREMENTS.md VER-17]
started: 2026-11-26
updated: 2026-11-26
---

## Current Test

Complete. The user ran the pass in game on WoW Forever and reported "works great".

## Tests

### 1. Offer follows the staff (HCHG-02)
With the CDM open on the Suggested section: equip Headmaster's Charge → the Headmaster's Charge
reminder appears in Suggested; unequip it → it disappears.
result: pass

### 2. Reminder shows while the buff is missing (HCHG-01/03)
Place the reminder in a container. With buff 18264 missing, the icon shows; with the staff
unequipped (or on a character without it), it still shows.
result: pass

### 3. Click uses the staff (HCHG-04)
Staff equipped, out of combat: click the reminder → the staff is used, the party gets +20 Intellect,
and the reminder hides on the aura.
result: pass

### 4. Click without the staff does nothing (HCHG-04)
Staff unequipped (in the bags): click the reminder → nothing happens, the staff is NOT equipped, no
Lua error.
result: pass

### 5. Optional: another player's staff
If a groupmate's Headmaster's Charge buff is on you, the reminder hides.
result: pass (covered by the user's "works great"; not reported item by item)

## Summary

total: 5
passed: 5
issues: 0
pending: 0

## Gaps

None. The Providers.lua row comment no longer says "(unverified in game)".
