---
phase: 79-buff-countdown-display-fix
plan: 01
subsystem: display
tags: [display, cooldown-frame, countdown]
requirements: [BUFFTIME-01, BUFFTIME-02, BUFFTIME-03, VER-14]
key-files:
  modified: [Display.lua]
commits: [cbc4008]
completed: 2026-10-24
---

# Phase 79 Plan 01: Buff countdown display fix — Summary

**Buff timer icons now count down in the aura format, as the CDM's buff icons do. A buff with a
little over 1h left no longer reads "2h".**

## Cause

TBT drew every icon sweep with `SetCooldown` on a `CooldownFrameTemplate` and never set the countdown
format. The cooldown format rounds hours up. Blizzard's CDM buff icons switch the frame to the aura
format with `SetUseAuraDisplayTime(true)` (`CooldownViewer.lua:1397`, and per state at :877/:895 vs
:924, applied at :1150). The timer itself was always right; only the text was wrong. That is why
the settings preview looked right and why the bug survived a `/reload`. It was first reported as a
cold-login bug, and the milestone was re-scoped once that was ruled out.

## What changed (`cbc4008`)

- **New helper:** `ApplyCountdownFormat(icon, auraTime)` sits in Display.lua, directly below
  `ApplySwipeLook`, above both callers.
  - It keeps one per-icon stamp (`icon._auraTime`) and calls `SetUseAuraDisplayTime` only when the
    stamp changes, and only if the client has the method. On a client without it, the icon keeps
    today's format and raises no error.
  - When the format changes, it clears the sweep stamps (`_lastStart`, `_userCdState`, `_cdGen`),
    so the owning branch redraws the sweep in the new format in the same pass.
- **Timer branch** (every running proc: buff tracker, reminder, Trinket/Pot, a cooldown's own buff):
  calls `ApplyCountdownFormat(icon, true)` before its `SetCooldown`.
- **`ApplyCooldownSlot`:** calls `ApplyCountdownFormat(icon, false)`. This is the only path to both
  real-cooldown sweep owners (`ApplyUserCooldown` and `ApplyCooldownHandle`), so a pooled icon
  handed from a buff to a cooldown always gets the cooldown format back.
- **Old comment:** the `ApplySwipeLook` comment that said the call "is not used" is updated.

## Checks

- **Gates:** both plan gates exit 0. The Task 2 gate was corrected at planning time: it used to count
  the declaration line too.
- **Tooling:** `stylua .` is clean, `node scripts/aura-read-gate.js` passes, and `Display.lua` is
  `w/crlf`.
- **Deploy:** `./scripts/install.bat` deployed to every client folder.

## In-game check (VER-14), Midnight retail, 2026-10-24

- **Relog:** the flask on a cooldown's buff showed the correct time.
- **One-off miss:** one `/reload` showed the flask icon with no timer until the next relog. Lua
  errors were off at the time, so a hidden error cannot be ruled out. It did not happen again:
  - On the two `/reload`s that followed, it looked right.
  - A temporary diagnostic (`/tbt dump`, never committed) showed the running buff (3530.1s left)
    matching the aura exactly, with auras readable.
  - The user called it a fluke, to ignore for now. The diagnostic was removed before closing.
- **Sign-off:** the user signed off for the release.
- **Not reported one by one:** the reminder and buff-tracker icons, real cooldowns (check 2), and
  the buff-to-cooldown handover (check 3).
- **Not reproduced:** the "6m shows 2h" case from another character (check 4).

## Deviations

None in code. The plan ran as written.
