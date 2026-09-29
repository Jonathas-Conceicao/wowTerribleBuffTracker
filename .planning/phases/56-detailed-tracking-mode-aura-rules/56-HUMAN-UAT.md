---
status: complete
phase: 56-detailed-tracking-mode-aura-rules
source: [56-VERIFICATION.md, 56-REVIEW.md]
started: 2026-09-28
updated: 2026-09-28
---

## Current Test

[awaiting human testing — deferred to the end of the autonomous run, Phases 56-57]

## Tests

Run on Midnight retail AND the Forever beta. Persistence checks need a REAL logout/login, never
`/reload`. The build is already deployed to every client folder.

### 1. Portrait look (ADD-06)
expected: on both tabs a centered 50px CDM-styled icon under the title, spell name centered beneath, "secret?" badge on its top-right corner; the old 18px row is gone.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 2. Portrait empty / unknown
expected: empty Spell ID → dimmed question mark; unknown ID → question mark + "Unknown spell"; no Lua error.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 3. Portrait and badge hover
expected: portrait hover = game tooltip + secrecy line; badge hover = explanation. On Forever note whether the badge is the icon or "(secret?)" text, and whether the portrait mask/border draws (fallback: plain square).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 4. Detailed checkbox
expected: Buffs tab — checking "Detailed tracking" shows Aura ID and "End when the aura is lost"; unchecking hides them and the dialog resizes. Cooldowns tab has no Detailed checkbox yet (Phase 57 adds its options).
result: skipped: superseded by the 57.1 General/Advanced tabs

### 5. Aura ID row
expected: typing an aura ID shows its own small icon/name preview and, only for a typed ID, its own secret badge; blank shows no second badge.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 6. Simple trackers unchanged
expected: existing and new simple trackers behave exactly as before.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 7. Differing aura ID no longer ends early (DTRK-02)
expected: a detailed buff whose aura ID differs from its cast ID starts on the cast and ends when that aura is removed out of combat — not at the first aura event.
result: pass (user, 2026-09-29)

### 8. Cancellation opt-out (DTRK-04)
expected: with "End when the aura is lost" unchecked, clicking the aura off leaves the timer running its full duration; new detailed trackers default to checked.
result: pass (user, 2026-09-29)

### 9. Unreadable aura never ends a tracker (DTRK-06)
expected: in combat, in M+, or with a secret aura, a detailed tracker is never ended because its aura couldn't be read; after combat it follows the aura's real state.
result: pass (user, 2026-09-29)

### 10. Edit prefill and mode switching
expected: Edit prefills Detailed, Aura ID and the opt-out; switching to simple and back keeps the detailed values.
result: skipped: superseded by the 57.1 General/Advanced tabs (no mode)

### 11. Persistence
expected: all detailed settings survive a real logout/login.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 12. Forever: cover all ranks + aura ID (review fix WR-04)
expected: with "Cover all ranks" on and a detailed aura ID set, casting a LOWER rank is not cancelled early; the tracker ends when the aura (typed ID or the rank's own aura) is gone.
result: pass (user, 2026-09-29)

### 13. Editing a running tracker
expected: changing a running tracker's aura ID takes effect from the next cast.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 13
passed: 11
issues: 0
pending: 0
skipped: 2
blocked: 0

## Gaps
