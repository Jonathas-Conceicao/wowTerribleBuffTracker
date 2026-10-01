---
phase: 63-clickable-reminders
plan: 03
subsystem: reminders
tags: [click-to-cast, display, edit-mode]
requires: [63-01, 63-02]
provides:
  - "ns:CollectReminderClickIcons(out)"
  - "icon._clickKey stamps, clickToCast container setting"
  - "Click to Cast checkbox on reminders containers"
key-files:
  modified: [Display.lua, EditModeFrames.lua, ReminderClick.lua]
requirements-completed: [CLICK-01, CLICK-02, CLICK-04]
completed: 2026-09-30
---

# Phase 63 Plan 03: Display Wiring and Click to Cast Option Summary

RenderIconContainer stamps clickable reminder icons on change only, ReminderClick collects them via `ns:CollectReminderClickIcons`, and every reminders container gets a default-on "Click to Cast" checkbox with an out-of-combat tooltip. Deployed.

## Tasks

1. Display.lua stamps, collector, `dst.clickToCast` - commit db6a061
2. EditModeFrames.lua Click to Cast checkbox - commit d8c61f2
3. Whole-phase gates and deploy - the EDIT_MODE_LAYOUTS_UPDATED registration in ReminderClick.lua is committed with this SUMMARY

## Deviations from Plan

**Plan-checker note folded in:** I did register `EDIT_MODE_LAYOUTS_UPDATED` on ReminderClick's eventFrame (pcall-guarded, so a client without the event cannot error at load). Its handler falls into the existing else branch, which calls `ns:MarkReminderClicksDirty()`, so a layout or profile switch re-places overlays.

Otherwise none.

## Verification (every gate run as written)

- Task 1 gate: PASS. Task 2 gate: PASS. Task 3 gate: PASS.
- `stylua .` clean; `git ls-files --eol` shows w/crlf for Display, EditModeFrames, Providers, CDMTab, ReminderClick, TOC.
- `node scripts/aura-read-gate.js`: AURA-READ GATE PASS (10 reads in 3 allowlisted readers).
- `node scripts/migrate-dryrun.js --selftest`: SELFTEST PASS (12 cases).
- `./scripts/install.bat` deployed 17 files to _retail_, _ptr_, _beta_ and _classic_beta_; ReminderClick.lua present in retail and classic_beta.
- The TOC gained ReminderClick.lua, so Phase 66 must FULLY restart the client (a /reload does not re-read the AddOns folder).

## Performance review

RenderIconContainer additions are comparisons only: no allocation, no API call, no GetRect. The dirty call fires only on a stamp change. The hidden-container path costs one table read (`clickStampedIn`) per tick. ReminderClick has no OnUpdate; flushes run from a one-shot C_Timer.After(0) or PLAYER_REGEN_ENABLED.

## Phase 66 checks

1. Click to Cast appears on Buff Reminders and on a user reminders container, not on buff/bar/cooldown containers.
2. Unticking it makes that container's reminders unclickable after Edit Mode closes; ticking restores it.
3. A satisfied reminder (buff cast) leaves no clickable square behind; a container set to Hidden has none.
4. With two reminders shown, satisfy the first: the remaining overlay follows its icon's new cell.
5. No ADDON_ACTION_BLOCKED in combat with reminders shown.
6. Full client restart first (new TOC file). Also confirm a layout/profile switch re-places overlays, that a click casts on the player by name, that Blood Pact has no click, and that tooltips show on the overlay.

## Known Stubs

None.

## Self-Check: PASSED
