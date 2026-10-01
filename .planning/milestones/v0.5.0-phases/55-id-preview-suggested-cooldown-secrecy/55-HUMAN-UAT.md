---
status: complete
phase: 55-id-preview-suggested-cooldown-secrecy
source: [55-VERIFICATION.md, 55-REVIEW.md]
started: 2026-09-28
updated: 2026-09-28
---

## Current Test

[awaiting human testing — deferred to the end of the autonomous run, Phases 53-55]

## Tests

Run on Midnight retail AND the Forever beta. `/reload` is enough to load the code; items 4 and 13
need a REAL logout/login. The build is already deployed to every client folder.

### 1. Live preview updates as you type
expected: in Add on both tabs, typing an ID updates the icon and name on every keystroke.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 2. Edit opens with the preview filled
expected: Edit shows the tracker's own spell in the preview immediately.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 3. Unknown ID
expected: with script errors on, typing 999999999 shows the question-mark icon and "Unknown spell"; hovering shows "Unknown spell" then "Spell ID: 999999999"; no Lua error.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 4. Uncached spell resolves
expected: after a real logout/login, an uncommon spell ID shows its name — or corrects itself after one more keystroke anywhere in the dialog.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 5. Preview hover tooltip
expected: hovering the preview shows the game tooltip with exactly one Spell ID line and one "Aura secrecy: …" line, plus the scope note ("Secrecy is for this ID's own aura; the buff's may differ."). Check the note doesn't make the tooltip awkwardly wide.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 6. Secrecy line on game tooltips, never twice
expected: an action button, a spellbook spell, a buff (out of combat) and a TBT tracker tile each show exactly one "Aura secrecy: …" line, directly under the ID line.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 7. "Secret?" badge on both tabs
expected: a Contextual or Always-secret ID shows the badge on BOTH the Buffs and Cooldowns tabs, with an explanatory tooltip; a Never-secret ID shows no badge.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 8. Badge art on Forever
expected: note whether the badge draws as the warning atlas icon or as the "(secret?)" text fallback.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 9. Suggested cooldown
expected: on the Cooldowns tab the Duration suggestion follows the ID until you type your own value; a cleared box refills when the ID changes. **On retail, note whether a non-charge spell gets a suggestion at all** (the legacy `GetSpellBaseCooldown` fallback is not in the 12.1 UI source — if only charge spells get suggestions, decide whether that's acceptable).
result: pass (user, 2026-09-29, retail: "cd suggestions is working too")

### 10. No cooldown → no suggestion
expected: a spell with no cooldown leaves Duration empty and Add stays disabled.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 11. Buffs tab never suggests
expected: the Buffs tab never fills Duration.
result: skipped: superseded 2026-09-29, buff trackers now get a live-aura duration suggestion when the buff is up

### 12. Edit keeps the saved duration
expected: editing a cooldown tracker and changing its ID keeps the saved duration (no suggestion overwrite).
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 13. Typed value wins and persists
expected: a value typed over a suggestion is what gets saved, and survives a real logout/login.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

### 14. Late resolve updates badge and suggestion (review fix WR-01)
expected: on the Cooldowns tab, type a spell ID the client hasn't loaded yet, then change something else in the dialog; once the preview shows the spell, the badge and the empty Duration box update.
result: pass (covered by the user-approved Forever (59) and retail (60) full reviews, 2026-09-29)

## Summary

total: 14
passed: 13
issues: 0
pending: 0
skipped: 1
blocked: 0

## Gaps
