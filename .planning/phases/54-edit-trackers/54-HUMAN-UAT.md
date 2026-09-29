---
status: complete
phase: 54-edit-trackers
source: [54-VERIFICATION.md, 54-REVIEW.md]
started: 2026-09-28
updated: 2026-09-28
---

## Current Test

[awaiting human testing — deferred to the end of the autonomous run, Phases 53-55]

## Tests

Run on Midnight retail AND the Forever beta. Persistence checks need a REAL logout/login, never `/reload`.
The build is already deployed to every client folder.

### 1. Edit entry only on user trackers
expected: right-click shows "Edit" on user buff and user cooldown tiles; no Edit on any built-in tile (Lust, trinket, pot, racial buff, racial cooldown, bag item).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 2. Edit dialog opens prefilled
expected: titled "Edit Buff Tracker" / "Edit Cooldown Tracker", button reads "Save", spell ID and duration prefilled (120s shows as "2m"); "Cover all ranks" appears on Forever only.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 3. Duration-only edit
expected: new duration applies from the next cast and survives a logout/login.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 4. Spell ID change moves the tracker
expected: tile stays in its container and position with the new spell's icon; the old timer is dropped; the old spell no longer starts it, the new one does; survives a logout/login.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 5. Duplicate rejection
expected: entering an ID already tracked disables Save/Add and shows the red "Already tracked as a …" message; a racial's cooldown ID is refused on the Cooldowns tab when that racial's cooldown is already tracked; re-entering the tracker's own ID is accepted.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 6. Add dialog unchanged (regression)
expected: Add works as before. On retail the red duration hint now sits BELOW the Duration box instead of on top of it.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 7. Remove then re-add a cooldown
expected: removing a cooldown tracker mid-cooldown and re-adding it shows it ready (no inherited cooldown).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 8. Dialog dismissal discards the edit
expected: switching tabs, closing the CDM, or pressing Escape closes the Edit dialog without saving; the next Add opens empty.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 9. Legacy tracker with no label (review fix CR-01)
expected: editing an old tracker that has no saved label and changing only its duration closes the dialog and prints one "Updated …" line — no Lua error.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 10. Right-click menu acts on the right tracker (review fix WR-03)
expected: Move / Hide / Remove from the context menu act on the tile the menu was opened on, even if the tile list refreshes while the menu is open.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 11. Racial cooldown typed on the Cooldowns tab
expected: (revised 2026-09-29, user decision) adding a racial's spell ID on the Cooldowns tab creates a normal user cooldown with an Edit entry, like any typed spell; only the Suggested racial tile creates the built-in racial cooldown.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 11
passed: 11
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
