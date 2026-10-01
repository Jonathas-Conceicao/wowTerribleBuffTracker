---
status: complete
phase: 65-cleanup
source: [65-VERIFICATION.md]
started: 2026-10-01
updated: 2026-10-01
---

## Current Test

[testing complete -- all 3 passed on retail 2026-10-01]

## Tests

### 1. Aura ID and Cast spell ID fields unchanged (D-01 shared builder)
expected: In a buff's and a reminder's Advanced tab, both fields still follow the Spell ID while untouched, preview the spell as you type, show the secrecy badge on Aura ID only, reject a bad ID with the same message, and save. Emptying Cast spell ID still previews "No click action" and the click does nothing; setting it back to the Spell ID follows again.
result: passed (2026-10-01, retail)

### 2. Tooltip on mouse-out (D-05)
expected: Hovering a clickable reminder shows its tooltip and moving off hides it. Moving quickly from a reminder onto another frame with its own tooltip (a bag item, an action button) leaves that other tooltip showing.
result: passed (2026-10-01, retail)

### 3. Click areas after the stamp-clear refactor (D-02)
expected: After login, /reload, Edit Mode exit and satisfying one of two shown reminders, each click area sits on its icon and none is left where no icon shows.
result: passed (2026-10-01, retail)

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
