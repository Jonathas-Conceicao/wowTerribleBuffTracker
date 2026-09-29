# Phase 60 — Retail Full Review (v0.5.0)

**Deployed:** `milestone/v0.5.0-elaborate-tracking` @ `db80522` or later (install.bat)
**Date:** 2026-09-29
**Status:** PASSED — 2026-09-29, marked complete by the user ("both full review were human reviewed and approved")

## Results so far (user, 2026-09-29)

"On retail everything going good so far; load rules are working, migration went nicely, reminder
is working as intended, no suggestions on reminders as intended for now on retail; gonna test
things in M+ now to see if we get any lua errors"

| Area | Result |
|------|--------|
| Save-format migration (retail save file brought up to v11) | pass |
| Load rule (When known / Always / Never) | pass |
| Reminders (user reminders) | pass |
| No class-buff Suggested tiles on retail (57.4 MREM-02) | pass |
| M+: no Lua errors | pass |
| M+: reminders inside a key | pass. Expected limit: an aura the player cancels by hand mid-key isn't picked up, because auras are secret there (by design, DTRK-06) |
| M+: Load rule inside a key | pass |

| Spec change (Load rule, both directions) | pass |
| Cooldown duration suggestion (55 #9, `GetSpellBaseCooldown` question) | pass |
| "Ends/Resets when you cast" | pass |

Later (user, 2026-09-29): "spec change worked both ways; cd suggestions is working too; end when
you cast working as well".

M+ results (user, 2026-09-29): "tested reminders inside a key, most user-cleared auras, i.e.,
unexpected cancelations, are not picked up due to secrecy, but this is expected. And no lua errors
which is the main thing. Load rules also working all the same inside m+"

## Still open on retail (from the HUMAN-UAT files)
- 57.3: spec swap unloads an off-spec spell (#22), talent learn/unlearn flips live (#8), a
  talent-override tracker after the talent is dropped (#26)
- 55 #9: `GetSpellBaseCooldown` suggestions for cooldowns without charges
- 57.5 #19 / 58 #9: a cast rule on a talent-replaced spell, including a mid-fight spellbook change
- 58: the retail half of the smoke items
