---
status: complete
phase: 57-detailed-tracking-visibility-cross-spell-rules
source: [57-VERIFICATION.md, 57-REVIEW.md]
started: 2026-09-28
updated: 2026-09-28
---

## Current Test

[awaiting human testing — deferred to the end of the autonomous run, Phases 56-57]

## Tests

Run on Midnight retail AND the Forever beta with `/console scriptErrors 1`. Persistence needs a REAL
logout/login, never `/reload`. The build is already deployed to every client folder.

### 1. Dialog on both tabs
expected: Detailed now also exists on the Cooldowns tab. Buffs detailed: Aura ID, "End when the aura is lost", visibility (Always / present / absent, exclusive), "Ends when you cast:". Cooldowns detailed: Aura ID, visibility, "Resets when you cast:" (no aura-loss option).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 2. Cast-rule box
expected: comma-separated IDs show a small icon row; unknown IDs are marked; malformed input is rejected; "123," while typing is accepted; more than 8 IDs or the tracker's own ID is refused with a message.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 3. "Always" unchanged
expected: a detailed tracker left on Always behaves exactly like before.
result: skipped: visibility option removed in 57.2

### 4. "Present" — including a buff someone else cast on you
expected: the tracker shows while the aura is up and hides when it's gone; a buff cast on you by another player starts it (out of combat).
result: skipped: visibility option removed in 57.2

### 5. "Absent" reminder — icons and bars
expected: a full-colour reminder icon (bar: idle bar) shows while the aura is missing, even with hide-when-inactive on, and hides once the aura is up. No empty grid cell is left where a hidden tracker would be (review fix WR-01).
result: pass (user, 2026-09-29: "tested ... the show when not present"). The visibility option itself is replaced by the Reminders category in Phase 57.2

### 6. In combat / M+ / secret aura
expected: when the aura can be read, visibility follows it even in combat (review fix WR-03); when it can't be read, the last state holds — no flicker entering or leaving combat. A "present" start that comes due in combat happens when combat ends.
result: skipped: visibility option removed in 57.2 (reminders cover it)

### 7. Timer end marks the aura absent (review fix WR-03)
expected: when a visibility tracker's timer runs out or is cancelled, "present" hides and "absent" shows its reminder. Watch for: a buff that outlasts the typed duration — the tracker should restart cleanly on the next aura update, not flicker.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 8. Cooldown visibility
expected: a cooldown with an aura ID and present/absent draws only in that state; present/absent without an aura ID is refused in the dialog.
result: skipped: visibility option removed in 57.2

### 9. Cross-spell end (buffs) — in and out of combat, and in M+
expected: casting a listed spell ends the buff tracker immediately.
result: pass (user, 2026-09-29) (M+ part pending on retail)

### 10. Cross-spell reset (cooldowns)
expected: casting a listed spell resets the cooldown tracker to ready.
result: pass (user, 2026-09-29)

### 11. Ranks and talent overrides
expected: casting a talent-override or (Forever) another rank of a listed spell also triggers the rule.
result: pass (user, 2026-09-29)

### 12. Same-cast skip (Forever, "Cover all ranks" ON)
expected: listing another rank of A's own spell on A and casting it restarts A rather than ending it. With "Cover all ranks" OFF, cast A's own spell first, then the rank: the rank cast ends A.
result: pass (user, 2026-09-29)

### 13. Rule that doesn't match the game
expected: if a cross-spell rule marks a "present" tracker's aura absent while the aura is actually still up, the next out-of-combat aura event restarts it (known, acceptable behaviour — confirm it isn't disruptive).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 14. Forever rank family for visibility (review fix WR-02)
expected: on Forever with "Cover all ranks", casting a lower rank doesn't flip the tracker to "absent" while the buff is up.
result: skipped: visibility option removed in 57.2

### 15. Edit, prefill and switching back to simple
expected: Edit prefills visibility and the cast list; switching to simple makes the tracker behave as Always and ignores the rules, while keeping the saved values for later.
result: skipped: superseded by the 57.1 tabs (no simple mode)

### 16. Persistence and no Lua errors
expected: all settings survive a real logout/login; no Lua errors in the whole session.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 16
passed: 10
issues: 0
pending: 0
skipped: 6
blocked: 0

## Gaps
