---
status: complete
phase: v0.2.1-combined (phases 7-11)
source: [07-01-SUMMARY.md, 08-01-SUMMARY.md, 10-01-SUMMARY.md, 10-02-SUMMARY.md, 11-01-SUMMARY.md, 11-02-SUMMARY.md]
started: 2026-04-04T19:30:00Z
updated: 2026-04-04T19:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Debug Toggle
expected: Type /tbt debug in chat. See "TBT: Debug logging ON" in green. Type again — "TBT: Debug logging OFF" in orange.
result: pass

### 2. Aura Scan — Buff Cancellation
expected: Enable debug logging (/tbt debug). Cast a tracked buff (any spell you have configured). Right-click the buff icon on your unit frame to cancel it. The TBT timer should disappear within ~1 second. Debug chat shows "Cancelled 1 timer(s): [name]".
result: pass

### 3. Lust Detection — Self Cast
expected: Cast Time Warp (Mage) or your class lust. A 40-second timer bar should appear with the correct spell icon (Time Warp icon, not Bloodlust). Debug log shows "Lust detected (spellID XXXXX), timer started."
result: pass

### 4. Lust Cancellation
expected: While lust timer is running, right-click the Temporal Displacement debuff to cancel it (or let it expire on a boss wipe). The lust timer should disappear — it should not keep counting down after the buff is gone.
result: pass

### 5. Lust in Combat (Secret Values)
expected: Enter combat and have lust cast (by you or party member). Even though auras are secret in combat, the Sated debuff detection still triggers and the lust timer starts. Debug log should show detection even if "aura check blocked" is also shown.
result: pass

### 6. CDM Tab — Suggested Section
expected: Open CDM settings (/tbt). The Suggested section shows: the Add (+) icon FIRST, then the Lust/Heroism icon with your class-specific spell icon (Time Warp for Mage, Bloodlust for Shaman, etc.).
result: pass

### 7. CDM Tab — Lust Tooltip
expected: Hover the lust icon in Suggested. Tooltip shows the real spell tooltip (Time Warp / Bloodlust / etc.) plus gray text "TBT Duration: 40s" and "Matches all Heroism/Bloodlust effects" at the bottom.
result: pass

### 8. CDM Tab — Right-Click Suggested
expected: Right-click the lust icon in Suggested. Menu shows only "Add to Bars" and "Add to Buffs" — no "Remove" option.
result: pass

### 9. CDM Tab — Add to Bars from Suggested
expected: Click "Add to Bars" from the right-click menu. Lust appears in the Tracked Bars section with the correct class icon. The icon STAYS in Suggested (it's a static catalog).
result: pass

### 10. CDM Tab — Drag Suggested to Section
expected: Drag the lust icon from Suggested to Tracked Buffs. Since it's already tracked (from test 9), it should MOVE to Buffs (not create a duplicate). Icon stays in Suggested.
result: pass

### 11. CDM Tab — Remove Tracked Lust
expected: Right-click the lust entry in its tracked section and choose "Remove". The lust disappears from that section but remains in Suggested — ready to be re-added.
result: pass

### 12. Preview Preserves Running Buffs
expected: Cast a tracked buff so a timer is running. Open CDM settings (/tbt) — preview timers appear but your real running timer should still be visible with its real countdown (not reset to full duration). Close CDM — the real timer continues counting down, not wiped.
result: pass

### 13. Preview Shows Lust with Class Info
expected: Add lust to Tracked Bars. Open CDM settings. The preview bar for lust shows your class-specific spell name (e.g., "Time Warp" not "Lust / Heroism") and the correct spell icon.
result: pass

## Summary

total: 13
passed: 13
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
