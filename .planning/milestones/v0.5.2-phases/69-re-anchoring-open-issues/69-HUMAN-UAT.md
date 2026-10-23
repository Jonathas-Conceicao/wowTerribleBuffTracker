---
status: complete
phase: 69-re-anchoring-open-issues
source: [69-VERIFICATION.md]
started: 2026-10-10
updated: 2026-10-10
---

## Current Test

[awaiting human testing — deferred to Phase 72 by user decision for the 67-71 autonomous run]

## Tests

### 1. Reorder and category moves in the CDM settings window (STEAL-13)
expected: With the CDM settings window open, reorder a tracked buff, then move a buff into Tracked Bars and back. TBT's preview updates right away, before the window closes: nothing lands in the wrong container, no bar is mis-sized or misaligned. Same for a reorder in Essential / Utility.
result: pass — retail (2026-10-10)

### 2. Edit Mode preview shows every merged entry (STEAL-14)
expected: Enter Edit Mode with the Edit Mode "Cooldown Manager" checkbox on, then off. In both cases every merged entry shows in TBT's containers, bars included — as Blizzard's frame where Blizzard draws it, otherwise as TBT's placeholder. Toggling that checkbox may leave a placeholder lagging until the next update (accepted limitation).
result: pass — retail (2026-10-10)

### 3. Hidden TBT container hides its merged frames (STEAL-15)
expected: Set a container's Visibility to Hidden, then In Combat (while out of combat), and test Hide When Inactive. Merged frames vanish with the container and are not hoverable (no tooltips from empty space); showing the container brings them back on the next update.
result: pass — retail (2026-10-10)

### 4. CDM Visibility notice
expected: Set a Cooldown Manager section's own Visibility to In Combat or Hidden while it has merged entries: one chat line per viewer per session explains the fix; `/tbt merge` lists each viewer's Visibility.
result: pass — retail (2026-10-10)

### 5. No taint
expected: No Lua error or blocked action through combat, Edit Mode, combat with Edit Mode open, a spec change, and M+.
result: pass on retail — raid and M+, no Lua error (2026-10-10). Forever passed too (2026-10-10).

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0

## Gaps

None yet.
