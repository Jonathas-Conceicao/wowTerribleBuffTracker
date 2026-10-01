---
phase: 63-clickable-reminders
plan: 02
subsystem: reminders
tags: [secure-overlay, click-to-cast, combat-safety]
requires: [63-01]
provides:
  - "ns:MarkReminderClicksDirty()"
  - "ReminderClick.lua secure overlay pool"
affects: [63-03]
key-files:
  created: [ReminderClick.lua]
  modified: [TerribleBuffTracker.toc]
requirements-completed: [CLICK-01, CLICK-03, CLICK-04, CLICK-05]
completed: 2026-09-30
---

# Phase 63 Plan 02: Secure Click Overlay Summary

New module `ReminderClick.lua`: a pool of SecureActionButtonTemplate overlays anchored only to UIParent in screen coordinates, name-based spell attribute on the player, combat visibility owned by RegisterStateDriver, and all protected writes combat-gated and flushed on PLAYER_REGEN_ENABLED.

## Tasks

1. Overlay pool, placement, attributes, dirty flush - commit bfe42c5
2. Events, Edit Mode callbacks (owner eventFrame), TOC entry after Display.lua - see git log (feat(63-02) second commit)

## Deviations from Plan

None - plan executed as written.

## Verification

Both task gates printed PASS as written; `stylua .` clean; aura-read-gate PASS (10 reads in 3 allowlisted readers); ReminderClick.lua and the TOC are w/crlf.

## Notes for later plans

- Depends on `ns:CollectReminderClickIcons` from 63-03 (guarded with a nil check, so the module is inert until then). No deploy done here.
- A TOC change needs a FULL client restart to test (Phase 66); /reload does not re-read the AddOns folder.

## Known Stubs

None.

## Self-Check: PASSED
