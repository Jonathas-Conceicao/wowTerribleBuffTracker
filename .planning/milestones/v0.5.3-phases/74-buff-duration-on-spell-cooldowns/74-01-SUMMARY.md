---
phase: 74-buff-duration-on-spell-cooldowns
plan: 01
subsystem: tracker dialog (CDMTab.lua TRACKER_FIELDS)
tags: [dialog, field-contract, greyed-state, buff-duration]
requires: []
provides:
  - "enabled(state, ctx, dialog) greyed hook in the TRACKER_FIELDS contract + ApplyFieldEnabled"
  - "saved entry keys buffEnabled / buffAuraID / buffDuration on userCd trackers"
  - "CarriesCooldownBuff / BuffFieldEnabled predicates (Phase 76 widens CarriesCooldownBuff)"
affects: [74-02, 76]
tech-stack:
  added: []
  patterns: ["compare-before-write enabled flag in RefreshState", "greyed = relevant + read + not validated + skipped by focus"]
key-files:
  created: []
  modified: [CDMTab.lua]
decisions:
  - "Greyed state is a field-contract hook (enabled), not a per-def setEnabled: one generic applier greys label/editBox/check/dropdown/hover/name, so Phase 76 needs no per-field code"
  - "Greying an edit box also ClearFocus()es it (plan-checker info note)"
  - "Buff Aura ID required-check reuses BuildFollowSpellIDField via opts.requiredMessage; a box still following the Spell ID counts as filled"
metrics:
  duration: "~15 min"
  completed: 2026-10-22
  tasks: 2
  files: 1
requirements: [BUFFCD-01, BUFFCD-02, BUFFCD-08]
---

# Phase 74 Plan 01: Buff fields on the cooldown dialog Summary

The shared tracker dialog now has a reusable greyed field state (`enabled()` hook + `ApplyFieldEnabled`), and a user cooldown's Advanced tab gains "Track buff duration", a following "Aura ID:" box and an empty "Duration (30, 45s, 2m):" box, saved as `buffEnabled` / `buffAuraID` / `buffDuration` through the engine's existing fields copy (no schema bump).

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Reusable greyed (enabled) state in the field contract | 0c32ed4 | CDMTab.lua |
| 2 | Track buff duration checkbox, buff Aura ID and Duration fields | f77f30c | CDMTab.lua |

## What was built

- **`ApplyFieldEnabled(state, enabled)`** (file-local, above `CreateAddDialog`): 0.5 grey / white restore on `label` and `editBox` text, `SetEnabled` on `editBox`, `check`, `dropdown`, alpha 0.5 on the follow-field `hover` and `name`; clears focus from a box being greyed. Allocates nothing.
- **Contract:** `enabled(state, ctx, dialog)` documented next to `visible()`. RefreshState evaluates it after update, compare-before-write on `field.enabled`, no layout change. ValidateAll skips `field.enabled == false`; the Tab/Enter ring and FocusFirstShown skip greyed boxes. The confirm read loop is unchanged, so greyed values are kept.
- **BuildFollowSpellIDField:** stores `label` in state, forwards `opts.enabled`, and honours `opts.requiredMessage` after the unchanged too-large check. `auraID` and `castID` pass neither, so they behave as before.
- **Fields** (after `castID`, before `load`): `buffEnabled` checkbox (reset unchecked, prefill `entry.buffEnabled == true`, read true/nil); `buffAuraID` via the factory with `requiredMessage = "Enter the buff's Aura ID"`, `secrecy = true`; `buffDuration` copied from `duration` at x=32 with no `update`, empty-box message "Enter the buff duration", DURATION_HINT for unparseable text. All three use `visible = CarriesCooldownBuff`; the two boxes use `enabled = BuffFieldEnabled`.
- Comments updated: the Advanced-tab paragraph names the buff fields and their runtime readers (`ns:CooldownBuffDuration` / `ns:CooldownBuffAuraID`, plan 74-02); keepOnAuraLoss's stale "never enters ns.activeTimers" note is replaced.

## Verification

- Task 1 and Task 2 automated gates print PASS. Both failed before the change because none of the new identifiers existed.
- `stylua --check .` exits 0; `git ls-files --eol CDMTab.lua` reports `w/crlf`.
- `./scripts/install.bat` deployed to every client folder.
- In-game checks are deferred to Phase 78 by user decision.

## Deviations from Plan

The plan ran as written, with one addition. Following the plan-checker info note, `ApplyFieldEnabled` calls `ClearFocus()` on an edit box as it greys it, so the box stops taking keystrokes.

## Known Stubs

None. The saved keys are read at runtime by plan 74-02, which this plan does not cover.

## Threat Flags

None. T-74-01 is handled by the numeric box and the factory's tooLarge check. T-74-02 is handled by ParseDuration plus validate while the box is ticked. T-74-03 is handled because an enabled flip is compare-before-write and never calls SetText.

## Self-Check: PASSED

- FOUND: CDMTab.lua (modified)
- FOUND: 0c32ed4
- FOUND: f77f30c
