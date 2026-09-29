---
phase: 58-cleanup
plan: 01
subsystem: reminder runtime, tracker conflict check, saved-variable defaults
tags: [cleanup, rename, dead-code, merge-mode, 57.2-WR-05, 57.4-IN-01]
requires: []
provides:
  - "ns.reminderKeys / ns.reminderAuraID / ns.reminderWatch, ns:RebuildReminderWatch, ns:ReminderGate, ns:ReminderShowsIn (formerly visibility*)"
  - "FindTrackerConflict without the unreachable metaReminder branch"
  - "Fresh-database Merge Mode seed (freshDB)"
affects: [58-03, 58-04]
tech-stack:
  added: []
  patterns: ["mechanical rename proven by reverse mapping against the phase base", "fresh = the SavedVariables table did not exist at ADDON_LOADED"]
key-files:
  created: []
  modified: [Core.lua, BuffEngine.lua, Display.lua, CDMTab.lua]
decisions:
  - "Fresh database = TerribleBuffTrackerDB was nil at ADDON_LOADED (the branch that creates it sets freshDB); no schemaVersion or trackedBuffs heuristic"
  - "No prose change needed after the rename: every remaining 'visibility' in the four files is the container setting, dialog field visibility, the saved entry.visibility migrations, or history of the removed Phase 57 option"
metrics:
  duration: "~10 min"
  completed: 2026-09-29
---

# Phase 58 Plan 01: Reminder runtime rename, dead branch, fresh Merge Mode default Summary

The Phase 57 "visibility" runtime now carries reminder names everywhere in Lua, proven mechanical against be7ca11. The unreachable metaReminder branch in `ns:FindTrackerConflict` is gone. A first-ever install now starts with Merge Mode on, and existing databases are unchanged.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 6550e34 | refactor(58-01): rename the reminder runtime from visibility* to reminder* |
| 2 | a8be1f4 | refactor(58-01): drop the unreachable metaReminder conflict branch and stale reminder prose |
| 3 | e653b40 | feat(58-01): start Merge Mode on for a fresh database |

## Gate results

Each gate was extracted verbatim from the PLAN into the executor scratch folder and run before and after its task.

| Gate | Before | After |
|------|--------|-------|
| T1 | FAIL: an old reminder name remains outside a formerly note | ok (reverse-mapping proof against be7ca11 passes) |
| T2 | FAIL: FindTrackerConflict still has the unreachable metaReminder branch | ok |
| T3 | FAIL: freshDB is not set inside the branch that creates the database | ok |

aura-read-gate.js PASS (selftest 30 cases), migrate-dryrun.js --selftest 12 cases, `stylua --check .` clean, all four files `w/crlf` with one CR per line and no CRCR. The aura-read-gate allowlist is unchanged; it names none of the renamed identifiers.

## Task 1: rename

The per-file hit counts matched the plan's table exactly: RebuildVisibilityWatch 7, visibilityKeys 7, visibilityAuraID 12, visibilityWatch 8, VisibilityGate 8, VisibilityShowsIn 4. That is BuffEngine.lua 13, Core.lua 26, Display.lua 6 and CDMTab.lua 1. The three-line "formerly" history note sits directly above the reminder-keys comment block in Core.lua. Every line of the note contains "formerly".

## Task 2: dead branch and prose

- `ns:FindTrackerConflict`: the `if kind == ns.KIND.META_REMINDER then` branch is removed. It had no caller: the three callers are AddTrackedBuff, UpdateTrackedBuff and the dialog's validate. AddTrackedBuff maps its requested type to a user kind only, UpdateTrackedBuff uses the entry's own kind (user kinds only reach the dialog), and the dialog opens editable kinds only. The comment now says a metaReminder never reaches the function and that AddSuggestedTracker's canonical-key check is its guard. The "Kept rather than removed ... 57.4-01 gate" sentence is gone. The `ns.REMINDER_KINDS[kind]` block is unchanged.
- **The 57.4-01 plan gate's branch assertion now fails by design.** It is a historical gate, like 57.4-03 T1 and 57.5-03 T2, and was not edited.
- The `grep -n -i visibility` lines deliberately kept (all accurate):
  - Core.lua:208, the container `visibility = 0` default (setting)
  - Core.lua:652, "never 'visibility', which containers already have" (Load field naming)
  - Core.lua ~1827, "the old visibility watch" (history of the removed option)
  - BuffEngine.lua 531-652, the v9/v10 migrations of the saved `entry.visibility`
  - Display.lua 150, 196, 813, 885, 968, container visibility and the shown state
  - CDMTab.lua 1580, 2556, 2621, 2801, 2836, dialog field visibility
  - CDMTab.lua 1650, 2014, the removed visibility field/option (history)
  - CDMTab.lua 2278, the Load field "Never called 'visibility'"
  - CDMTab.lua 3398, the CDM visibility watcher
- No Lua comment claims a reminders container on "In Combat" never shows anything. The only `in combat.*never` hit is BuffEngine.lua ~1768 ("unreadable is never absent"), which is unrelated.

## Task 3: Merge Mode on for a fresh database

**Decision: how a fresh database is detected.** Fresh means `TerribleBuffTrackerDB` was nil at ADDON_LOADED. The `if not TerribleBuffTrackerDB then` branch, the only place TBT creates the database, sets `local freshDB = true`. The seed is `if ns.db.mergeMode == nil then ns.db.mergeMode = freshDB end`. A saved true or false stays as it is, and an old database without the key is seeded false as before. No schemaVersion or trackedBuffs heuristic is used.

**Login path confirmed by reading.** A first login with the true default follows the same path as an existing user who logs in with Merge Mode already on:
- MergeMode.lua reads `ns.db.mergeMode` only inside functions (lines ~236, 971, 1686, 2154, 2467), never at file scope.
- PLAYER_ENTERING_WORLD is in both REFRESH_MIRROR and REASSERT_VISIBILITY, so it queues `ns:QueueMergeMirror()` and `ns:QueueMergeVisibility()`, the same two calls `ns:SetMergeMode` makes. The REASSERT_VISIBILITY comment already names this case ("a login where ns.db.mergeMode is already true").
- Config.lua's switch reads `ns.db.mergeMode == true` when built (~201, ~326).

No SetMergeMode call at load was needed or added. The seed comment was rewritten: the writer is `ns:SetMergeMode` (reached from Config.lua's switch), not "the checkbox in CDMTab.lua"; the stale "Nothing reads this flag until Phase 40" is removed; the fresh rule is stated on the line directly above the `if`. No comment in Core/MergeMode/Config/CDMTab said Merge Mode is off by default. `ns:SetMergeMode`'s "written here and in one other place only" comment stays true.

**README.md lines left for the user (not edited):**

```
23: - **Merge Mode** - Enable it on config via `/tbt`: Blizzard's Cooldown
53: - I recommend enabling the **Merge Mode** and have custom buffs integrated to Blizzard's CDM
```

A fresh install now has it on already, so the user may want to reword these. CHANGELOG.md was not touched.

## Deviations from Plan

- **Tooling:** the plan says the Edit tool is unavailable. It was available in this run, so the targeted edits (the history note, the branch removal, the seed) used Edit, and the rename used the plan's node script. Every touched file was asserted `w/crlf`, one CR per line, no CRCR afterwards.
- **Scratch folder:** gates and scripts live in `scratchpad\p58\exec\` (orchestrator instruction), not `exec-58-01\`.

Otherwise the plan executed as written.

## Known Stubs

None.
