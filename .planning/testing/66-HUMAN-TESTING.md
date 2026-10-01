# Phase 66 — Human Testing (v0.5.1)

**Deployed:** `milestone/v0.5.1-clickable-reminders-new-icons` @ `be337ab` or later (install.bat)
**Date:** 2026-09-30 → 2026-10-01
**Status:** PASSED — 2026-10-01, user sign-off ("all 3 passes on forever, let's /gsd-complete-milestone now")

One testing pass by user decision at kickoff (2026-09-30), Forever and retail, replacing v0.5.0's
two separate review phases. The per-phase HUMAN-UAT files hold the item-by-item results.

## Retail (Midnight)

| Area | Result |
|------|--------|
| Merge Mode: Prismatic Barrier shows buff time and charges together (STEAL-09) | pass |
| Merge Mode off leaves no merged aura behind (fix `8ac21ae`) | pass |
| Edit Mode container selection, no Blizzard method called (EDM-08) | pass |
| Faction-themed tab icons and dialog side tabs (TAB-08/09/10) | pass |
| Clickable reminders: clicks, combat, Edit Mode, layout switch, Alt+Z, cast spell edits (CLICK-01..06) | pass |
| Reminder lead window with real remaining time (REM-05) | pass |
| Retail class-buff suggestions, every class, incl. Mark of the Wild on 1126 and Lightning Shield 192106 (MREM-04/05) | pass |
| Ally-cast clicks (Symbiotic Relationship, Source of Magic) cast on the target | pass |
| Combat and M+: no Lua errors, blocked actions or taint | pass |
| Phase 65 cleanup: Aura ID / Cast spell ID fields, owned tooltip hide, click areas | pass |
| General retail review | pass (user, 2026-10-01) |

## Forever (beta)

| Area | Result |
|------|--------|
| Paladin blessings click-cast, every blessing (CLICK-01) | pass (2026-09-30) |
| Class-buff offer unchanged; no retail row offered (64 #1) | pass (2026-10-01) |
| Blood Pact reminder has no click action (63 #9, CLICK-06) | pass (2026-10-01) |
| No regressions | pass (2026-10-01) |

## Still open

- 61-HUMAN-UAT #2: skipped until backlog 999.19 and 999.20 exist.
