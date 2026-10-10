---
status: complete
phase: 68-merge-mode-by-re-anchoring
source: [68-VERIFICATION.md]
started: 2026-10-10
updated: 2026-10-10
---

## Current Test

[awaiting human testing — deferred to Phase 72 by user decision for the 67-71 autonomous run]

## Tests

### 1. Merge Mode on is enough
expected: With Merge Mode on and no `/tbt reanchor` toggle, every merged CDM entry shows as Blizzard's own frame on its TBT slot (icons and bars), looking exactly like the CDM inside. TBT draws nothing of its own on a merged slot.
result: pass — retail (2026-10-10)

### 2. TBT layout and container settings drive the moved frames
expected: Merged entries follow TBT order, direction, Centered and padding, interleaved with custom trackers, no overlap. Icon scale, bar width, opacity, Show Timer (countdown + swipe), Show Tooltips and bar Display Mode from TBT's Edit Mode popup all apply to the moved frames.
result: pass — retail (2026-10-10)

### 3. CDM size/settings do not change TBT's merged sizes
expected: Resizing the CDM in Edit Mode or changing its settings leaves the merged frames' size in TBT unchanged.
result: pass — retail (2026-10-10)

### 4. No taint
expected: No Lua error or "blocked action" through combat, Edit Mode, combat while Edit Mode is open, a spec change, and an M+ key. Start from a fresh `/reload`.
result: pass on retail — raid and M+, no Lua error (2026-10-10). Forever passed too (2026-10-10).

### 5. Merge Mode off without /reload
expected: Turning Merge Mode off returns every frame to Blizzard's viewers at their original places, with Blizzard's own scale, opacity, timer and tooltip behaviour.
result: pass — retail (2026-10-10)

### 6. Known, accepted gaps (observe, do not fail)
expected: In a Centered container a newly-up merged buff may appear one frame plus up to 50 ms late; with Show Timer off, a cooldown icon's swipe can flash briefly after a cast or during a charge recharge.
result: pass — retail (2026-10-10): gaps observed as expected

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0

## Gaps

None yet.
