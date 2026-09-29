---
status: complete
phase: 58-cleanup
source: [58-01-SUMMARY.md, 58-02-SUMMARY.md, 58-03-SUMMARY.md, 58-04-SUMMARY.md]
started: 2026-09-29
updated: 2026-09-29
---

## Current Test

[awaiting human testing]

## Tests

**Setup**
- Turn on `/console scriptErrors 1`.
- Run the session on the Forever beta and on Midnight retail. Items 4 and 6's racial tile are Forever only; item 9 is retail only.
- This is a smoke session. **Behaviour must be unchanged** from the 57.5 build, except item 1 (a fresh install starts with Merge Mode on). Anything that draws, times or saves differently is a regression.
- The TOC did not change, so a /reload picks the build up.
- SavedVariables are read only at login and written only on logout. Item 1 needs the client **fully closed** before the file is moved.

### 0. First load of this build
expected: on Forever and on Midnight retail, /reload gives no Lua error. Every existing tracker and container is as it was, and the Merge Mode switch in `/tbt` is in the same position as before.
result: pass (Forever smoke + retail incl. M+ with no Lua errors, user 2026-09-29)

### 1. A fresh install turns Merge Mode on
expected: with the game closed, move `WTF\Account\<account>\SavedVariables\TerribleBuffTracker.lua` (and its `.bak`) aside, then start the game and log in. `/tbt` shows the Merge switch on, Blizzard's Cooldown Manager displays are hidden and their contents show in TBT's containers, and there is no Lua error. Close the game, restore both files, and log in again. The existing configuration is back, and Merge Mode is whatever it was before: an existing config is never switched on.
result: pass (accepted, not tested by name; covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 2. Reminders
expected: a user reminder shows while its buff is missing, hides on cast, and shows mid-combat when its timer ends. Cancelling the buff out of combat shows it at once.
result: pass (Forever + retail, user 2026-09-29)

### 3. "In Combat" on a reminders container
expected: set Buff Reminders' Edit Mode Visibility to "In Combat". A reminder whose timer runs out mid-combat shows in combat, and the container is hidden out of combat. The option is still offered in the dropdown.
result: pass (accepted, not tested by name; covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 4. Class buffs (Forever)
expected: a class buff tile dragged from the Reminders tab's Suggested section places a reminder that hides on cast. On a paladin, one blessing still hides all the blessing reminders.
result: pass (Forever-only item, user 2026-09-29)

### 5. Buff trackers
expected: a cast starts the timer, and losing the aura ends it. An "Ends when you cast" rule still ends it.
result: pass (Forever + retail: "end when you cast working", user 2026-09-29)

### 6. Cooldowns
expected: a user cooldown starts on cast, and a "Resets when you cast" rule still resets it. On Forever, a racial cooldown tile still works.
result: pass (Forever + retail: cd suggestions and cast rules, user 2026-09-29)

### 7. Load rule
expected: a tracker for a spell this character does not know is greyed out with "Not loaded". Edit it and set Load to "Always", and it loads. On Forever, a "Cover all ranks" tracker loads when a lower rank is known. Learning a spell or changing talents still refreshes the greyed state without a /reload.
result: pass (Forever + retail incl. M+ and spec change, user 2026-09-29)

### 8. Dialog and panel
expected: Add and Edit open with the General and Advanced tabs. The Load dropdown shows three radio choices (When known, Always, Never), and the choice saves. The New Container dialog's category dropdown (Buffs, Cooldowns, Reminders) selects and creates correctly. The three New ... Container buttons in the `/tbt` panel sit exactly where they did.
result: pass (Forever + retail, user 2026-09-29)

### 9. Midnight retail smoke
expected: on Midnight retail, reminders, a buff tracker and a cooldown behave as on Forever. A cast rule naming a spell that has an override (talent-replaced) still fires.
result: pass (user, 2026-09-29, retail: load rules, migration, reminders, M+, spec change, cd suggestion, cast rules)

### 10. Performance
expected: no hitch in combat with many aura changes, or on zone-in.
result: pass (accepted, not tested by name; covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 11
passed: 11
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
