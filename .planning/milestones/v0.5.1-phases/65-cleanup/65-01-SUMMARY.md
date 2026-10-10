---
phase: 65-cleanup
plan: 01
subsystem: lua-cleanup
tags: [cleanup, refactor, dead-code, hot-path-audit]
requires: []
provides:
  - BuildFollowSpellIDField factory (CDMTab.lua)
  - ClearClickStamp / ClearContainerClickStamps (Display.lua)
  - ownership-checked OverlayOnLeave (ReminderClick.lua)
key-files:
  modified: [CDMTab.lua, Display.lua, ReminderClick.lua, Core.lua]
decisions:
  - D-01, D-02, D-04, D-05, D-08 implemented; D-03 and D-09 recorded here
metrics:
  tasks: 3
  files: 4
  completed: 2026-10-01
---

# Phase 65 Plan 01: Lua cleanup Summary

Aura ID and Cast spell ID dialog fields now come from one factory, the click-stamp clear lives in one helper, overlays only hide a tooltip they own, and the milestone's dead nil-guard is gone.

## Commits

- `2c08f01` refactor(65-01): one factory for the Aura ID and Cast spell ID fields (CDMTab.lua)
- `aae99e5` refactor(65-01): one click-stamp clear in Display, owned tooltip hide on overlays (Display.lua, ReminderClick.lua)
- `549c3de` refactor(65-01): drop the dead click-dirty guard in RebuildCastIndex (Core.lua)

## D-01 difference table (re-derived from source; matched the plan exactly, no extra differences)

| Aspect | Aura ID | Cast spell ID | Factory parameter |
|---|---|---|---|
| visible | `ctx.kind ~= USER_CD` | `REMINDER_KINDS[ctx.kind] == true` | `opts.visible` |
| label | "Aura ID:" | "Cast spell ID:" | `opts.label` |
| tooltip extraLines (scope note) | yes | none | `opts.secrecy` |
| secrecy badge (build) | yes | none | `opts.secrecy` |
| reset extra clears (level, checkedID, checkedGen, badge:Hide) | yes | none | `opts.secrecy` |
| prefill extra clear (checkedID) | yes | none | `opts.secrecy` |
| update: "No click action" early return | none | yes | `opts.emptyIsNone` |
| update: badge block | yes | none | `opts.secrecy` (early return after preview when false) |
| read when typed <= 0 | nil | nil while following, false once emptied | `opts.emptyIsNone` |
| validate message | "Aura ID is too large" | "Cast spell ID is too large" | `opts.tooLarge` |

The factory is declared above the TRACKER_FIELDS contract comment block (so above `local TRACKER_FIELDS`). Field order unchanged. The header comment block was left alone (it does not name the build code).

## D-03 (no code change; Plan 03 copies this into 63-REVIEW IN-01)

The three resolvers differ. `ResolveCastName` (ReminderClick.lua) returns nil for an unreadable or empty name, which a cast attribute needs. `ns:SpellPreview` (Core.lua) substitutes "Spell N" and an icon. Core's file-local `SpellName` skips `CanReadTable` and the empty-string check. The two Core ones predate the milestone and are protected, and moving `ResolveCastName` would not remove a copy.

## D-04 sweep

- REM-05 lead-window test lives only in `ns:ReminderInLead` (BuffEngine.lua:1710); called by `ns:ReminderGate` (:1730) and `ns:GetActiveTimers` (:998).
- Faction suffix lives only in `TabIcon` (CDMTab.lua:15).
- Retail rows' option handling lives in `MetaReminderRow` (Providers.lua); not duplicated elsewhere.
- `ns:ReminderCastID` and `ns:ReminderCastUnit` (Providers.lua:1654, :1685) each read the def table once.
- Duplication fixed: the two stamp-clear blocks and the two "stamped container goes away" blocks (Task 2).

## D-08 sweep

- (a) No reference to INV_Misc_Book_09, GM-icon-settings, Trade_Engineering, SetAdvancedSideTabIcon, SIDE_TAB_GENERAL_ICON, SIDE_TAB_ADVANCED_ or bare ICON_PATH in any Lua/XML/TOC.
- (b) Every tab icon goes through `TabIcon(name)` (CDMTab.lua:2781, 2783, 3382-3384); no non-faction `icon_<name>` path.
- (c) 10 BLPs in Media/Textures, 10 PNGs in Media/Source, one-to-one by name, each base name has a `TabIcon("icon_<name>")` caller; nothing else under Media.
- (d) 95 locals / functions added by the milestone's Lua diff; each name appears at least twice across `*.lua` (none single-use). Nothing removed.
- Dead guard removed: `if ns.MarkReminderClicksDirty then` in `ns:RebuildCastIndex` (all seven call sites are inside function bodies, so the function always exists by then).

## D-09 hot-path audit

`ns:MarkReminderClicksDirty()` callers:
- Core.lua:1483 `RebuildCastIndex` (spell/rule edits, not per tick)
- Display.lua:175 `ClearContainerClickStamps` (hidden or no-settings container, only when stamped)
- Display.lua:284 `ns.ReleaseContainerRuntime` (unconditional, release path)
- Display.lua:2781 stamp change; :2793 trailing-pool clear; :2849 container size change while stamped
- ReminderClick.lua:223 (events PLAYER_ENTERING_WORLD, UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED, EDIT_MODE_LAYOUTS_UPDATED), :231 UIParent OnShow, :250 EditMode.Exit

`MarkReminderClicksDirty` (ReminderClick.lua:200) only sets a flag and schedules `C_Timer.After(0, FlushFromTimer)` once (coalesced; skipped in combat). GetRect and every secure write happen in Flush, with the one bounded retry. The per-tick stamp test in Display is comparisons only. `ns:ReminderInLead` and the GetActiveTimers branch allocate nothing. `ns:ReminderGate` calls `GetTime()` once per call while a timer runs: no allocation, a cheap C call; threading `now` through pre-milestone callers would be a refactor of old code, so accepted. `SetChargeCountRaised` re-levels only on a state change (`icon._chargeRaised ~= raised` at the caller, `elseif icon._chargeRaised` inside). `container:SetSize` per tick predates the milestone; the added `_clickW/_clickH` test is two compares. No milestone-added waste found.

## Deviations from Plan

None. Gate scripts ran as written (the Task 3 gate's `AURA-READ SELFTEST PASS (30 cases)` and `SELFTEST PASS (12 cases)` matched). The factory text was inserted from a scratchpad file by node script (CRLF preserved; no CRCR).

## Carried check for Phase 66 (in-game)

Aura ID and Cast spell ID fields follow, preview, badge and save exactly as before; an overlay no longer hides a tooltip another frame owns (D-05, the one behaviour change).

## Verification

`stylua --check .` clean; aura-read-gate pass (10 reads, 30-case selftest); migrate-dryrun selftest 12 cases; CDMTab/Core/Display/ReminderClick all `w/crlf`, no CRCR; CHANGELOG.md, STATE.md, ROADMAP.md and Assets/ untouched.

## Self-Check: PASSED
