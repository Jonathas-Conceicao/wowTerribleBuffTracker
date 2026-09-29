# Phase 59 — Forever Full Review (v0.5.0)

**Deployed:** `milestone/v0.5.0-elaborate-tracking` @ `db80522` (install.bat, all client folders)
**Date:** 2026-09-29
**Status:** PASSED — 2026-09-29, marked complete by the user

## Sign-off

The user tested every feature this milestone built on the Forever beta, in-game, across the
milestone. The user's statements:
- "Just did a quick test of every change on Forever and it's on passable state, will test things in
  Retail now" (Phase 58 smoke, covering everything up to the final build)
- "also mark phase 59, Forever Full Review as complete please"

## Evidence recorded per phase (Forever)

| Phase | What passed on Forever | Record |
|-------|------------------------|--------|
| 53-57 | Naming migration (implied by later migrations running clean), Merge Mode, detailed aura rules, cross-spell rules and ranks | 53/56/57 HUMAN-UAT |
| 57.1 | Tabs, v9 migration | 57.1-HUMAN-UAT |
| 57.2 | Reminders, v10 migration, cast timer and mid-combat expiry, expiry sync, buff + reminder on one spell | 57.2-HUMAN-UAT |
| 57.3 | Load rule in all 3 states, previews, greyed tiles in the CDM window, side-tab dialog | 57.3-HUMAN-UAT |
| 57.4 | Class-buff meta reminders (Mage, Paladin, Warlock tested; other classes same code path) | 57.4-HUMAN-UAT |
| 57.5 | Reminder alternatives, blessing group, v11 migration | 57.5-HUMAN-UAT |
| 58 | Smoke test of every change after the cleanup | 58-HUMAN-UAT (Forever: pass, retail pending) |

## Success criteria

1. The naming migration preserves every tracker across a real logout/login: passed. The v9, v10
   and v11 migrations ran on the same data without loss.
2. Editing works end-to-end, including a spell-ID change and "cover all ranks": passed.
3. ID preview, suggested cooldown, secrecy level and "secret?" badge: passed or degrade silently.
   The secrecy text was trimmed by the user.
4. Every detailed-tracking option works in and out of combat, with no Lua errors: passed. The
   options are now General/Advanced, reminders, alternatives and Load.

## Left for Phase 60 (retail)

Every retail item in the HUMAN-UAT files, the M+ restriction checks, and the retail-only Load-rule
checks (spec swap, talent override, `GetSpellBaseCooldown`).
