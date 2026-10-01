---
status: complete
phase: 63-clickable-reminders
source: [63-VERIFICATION.md]
started: 2026-09-30
updated: 2026-09-30
---

## Current Test

[awaiting human testing — deferred to Phase 66, the milestone's single human testing pass (user decision at kickoff). A FULL client restart is required first: the TOC gained ReminderClick.lua]

## Tests

### 1. Full client restart (new TOC file ReminderClick.lua), then open Edit Mode and check the Click to Cast checkbox
expected: Appears on Buff Reminders and on a user-added reminders container; absent on buff/bar/cooldown containers; ticked by default; tooltip says out of combat only
result: pass — user-tested 2026-09-30 (checkbox only on reminders containers)

### 2. Untick Click to Cast, close Edit Mode; then tick it again
expected: Unticked: that container's reminders are unclickable after Edit Mode closes; ticked: clickable again
result: pass — user-tested 2026-09-30

### 3. Click a shown reminder out of combat (Forever first, then retail), default CVar ActionButtonUseKeyDown=1
expected: Casts the reminder's cast spell on the player by name (highest rank); the square hover highlight shows; the tooltip shows on hover (and respects Show Tooltips)
result: pass — user-tested 2026-09-30 (every paladin blessing)

### 4. Satisfy a reminder (cast the buff); set a container to Hidden; empty a container
expected: No clickable square is left behind in any of these cases
result: pass — user-tested 2026-09-30 (no click area left behind)

### 5. With two reminders shown, satisfy the first
expected: The remaining overlay follows its icon's new cell; overlays match icon position/size after login and after Edit Mode closes
result: pass — user-tested 2026-09-30 (moving a reminder moves its click area)

### 6. Open Blizzard Edit Mode, including with TBT's sidebar checkbox unticked, and drag a container
expected: No overlay swallows the drag or a click (review WR-01)
result: pass — user-tested 2026-09-30 (unticking TBT in Edit Mode leaves nothing clickable)

### 7. Enter and leave combat with reminders shown; click during combat
expected: Clicking does nothing in combat; no Lua error, no ADDON_ACTION_BLOCKED, no taint; overlays return after combat
result: pass — user-tested 2026-09-30 (no click in combat, mid-combat expiry, no errors)

### 8. Switch Edit Mode layout/profile
expected: Overlays re-place over their icons
result: pass — user-tested 2026-09-30 (clicks still work after a layout switch)

### 9. Blood Pact reminder on Forever Warlock (imp)
expected: Shown but has no click action, no hover highlight
result: pass — user-tested 2026-10-01 on Forever (Blood Pact has no click action)

### 10. Edit a reminder's Cast spell ID (Advanced), save, click it; also set it back to the Spell ID
expected: The click casts the new spell without needing a reload (review CR-02); the castID key is nil at default (/dump entry)
result: pass — user-tested 2026-09-30 (swapping the cast spell changes what the click casts)

### 11. Alt+Z hide/show the UI, a cinematic, and a cast spell ID the character does not know
expected: Overlays are restored after the UI returns (WR-03); an unknown cast spell gets no overlay (WR-05)
result: pass — user-tested 2026-09-30 (Alt+Z restores clicks; unknown cast spell does nothing)

### 12. Faction-themed tab icons (TAB-10, follow-up 5a7256d)
expected: After a full client restart, an Alliance character sees the `_ally` set on the three CDM tabs and the dialog's General/Advanced side tabs, and a Horde character the `_horde` set; logging onto a character of the other faction switches the set.
result: pass — user-tested 2026-09-30

### 13. Reminder lead window (REM-05, follow-up 0a40b05)
expected: A reminder with a timed buff appears in the last 10% of the buff's duration (at least 1s; e.g. 6 minutes before a 60-minute blessing), showing the buff's remaining time as sweep and countdown, and is clickable out of combat; clicking recasts and it hides again. Inside combat it still appears (not clickable). A buff with no duration (e.g. Blood Pact) shows only once the buff is gone. With the CDM settings or Edit Mode open, a reminder with a duration previews with a demo sweep, and a reminder whose buff is up shows its real remaining time (fix 064f76c).
result: pass — user-tested 2026-09-30 (lead window, countdown, preview)

### 14. Emptied Cast spell ID = no click action (follow-up 42d0696)
expected: On a user reminder's Advanced tab, clear the Cast spell ID box: the preview reads "No click action"; save and reopen: the box stays empty; the reminder shows but has no click square or highlight. Typing the Spell ID back into the box makes it follow the Spell ID again.
result: pass — user-tested 2026-09-30 (a reminder with no cast spell does nothing)

## Summary

Partial in-game pass by the user, 2026-09-30, not yet mapped item by item: clicks cast the right buff (every paladin blessing), Edit Mode clean with no errors, left/right/centre orientations placed correctly, no click in combat, buffs expiring mid-combat, no errors. Items 12-14 were added after that pass.

total: 14
passed: 14
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
