---
phase: 74-buff-duration-on-spell-cooldowns
plan: 02
subsystem: timer engine (Core.lua, Providers.lua, BuffEngine.lua)
tags: [buff-duration, cooldown, activeTimers, preview, end-on-cast]
requires: [74-01]
provides:
  - "ns:CooldownBuffDuration(entry) / ns:CooldownBuffAuraID(entry) (Phase 76 reuses them for bag items)"
  - "ns:StartCooldownBuffFromCast(key, entry): pooled buff proc under the cooldown's own key"
  - "cooldown reset ends its buff; preview uses the buff duration; edit-off ends a running buff"
affects: [75, 76]
tech-stack:
  added: []
  patterns: ["Fill-then-override pooled proc (FillUserBuffProc, then duration/expiresAt/aliveBuffs)", "side-effect activeTimers writer from OnTrigger"]
key-files:
  created: []
  modified: [Core.lua, Providers.lua, BuffEngine.lua, Display.lua]
decisions:
  - "The buff proc is keyed under the cooldown's own key, so RenderIconContainer's live-timer branch draws it on that icon only"
  - "A cooldown filed in a bar container (old saved data) starts no buff, so the buff never draws as a separate bar"
  - "aliveBuffs is set unconditionally: a cooldown's buff has no 'End when the aura is lost' opt-out"
  - "'Resets when you cast' ends both the cooldown and its buff timer (orchestrator decision)"
metrics:
  duration: "~10 min"
  completed: 2026-10-22
  tasks: 2
  files: 4
requirements: [BUFFCD-03, BUFFCD-04, BUFFCD-08]
---

# Phase 74 Plan 02: Cooldown buff timer Summary

When a user cooldown's buff is on, the cast that starts the cooldown now also files a pooled buff proc under the cooldown's own key. The proc uses the typed duration, and its aliveBuffs holds the typed Aura ID. The cooldown runs exactly as it did before. The existing cancellation scan ends the buff on a readable aura loss. The existing live-timer render draws it on the cooldown's icon.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Buff helpers and the cast-side buff start | cb821e3 | Core.lua, Providers.lua |
| 2 | End-on-cast, preview and edit-off handling; stale comments | 36029da | BuffEngine.lua, Display.lua |

## What was built

- **Core.lua:** `ns:CooldownBuffDuration(entry)` returns `buffDuration` only when `buffEnabled == true` and the duration is a positive number. It never reads `entry.duration`. `ns:CooldownBuffAuraID(entry)` returns `buffAuraID` when that is a positive number, otherwise `spellID`. The `ns.activeTimers` / stamps comment was rewritten.
- **Providers.lua:** `ns:StartCooldownBuffFromCast(key, entry)` refuses an entry that is hidden, not a cooldown slot, filed in a bar container, or has its buff off. Otherwise it calls `FillUserBuffProc` and then overrides `duration`, `expiresAt` and `aliveBuffs` (`AcquireAliveBuffs(key, CooldownBuffAuraID(entry))`). It keeps `castAt`/`startedAt = now`, files the proc in `ns.activeTimers[key]`, queues the post-cast aura recheck and redraws. It allocates nothing. OnTrigger calls it right after `ns:StartCooldownFromCast`. The cross-spell skip key (`cdKey`) already stops this cast from resetting the buff it starts. The dispatcher note now lists three writers.
- **BuffEngine.lua:** the `ApplyEndOnCast` USER_CD branch also nils `ns.activeTimers[k]` (redraw goes through `endedBuff`). `StartAllPreviewTimers` previews a cooldown with its buff on using the typed buff duration and leaves `GetDisplayInfo` unchanged. `UpdateTrackedBuff` nils `ns.activeTimers[newKey]` when a cooldown's buff is off after the edit. `ENGINE_OWNED` and `CURRENT_SCHEMA_VERSION = 12` are unchanged.
- **Display.lua:** comment changes only. No code changed.

## Verification

- Both task gates print PASS. Before the plan, both would have failed because the new functions did not exist and `ApplyEndOnCast` had one `ns.activeTimers[k] = nil`.
- `node scripts/aura-read-gate.js` and `--selftest` (30 cases) pass. The allowlist is unchanged.
- `stylua --check .` exits 0. All four files report `w/crlf`.
- The Display.lua diff has no non-comment lines.
- `./scripts/install.bat` deployed to every client folder.
- No migrate dry-run was run because the schema did not change.
- In-game checks are deferred to Phase 78 by user decision.

## Deviations from Plan

None. The plan was executed as written.

## Known Stubs

None.

## Threat Flags

None. T-74-04: no new aura read was added, and the gate passes. T-74-05: the helpers type-check the saved keys. T-74-06: the proc and aliveBuffs come from pools, and the gate asserts there is no `{` in the cast function.

## Self-Check: PASSED

- FOUND: Core.lua, Providers.lua, BuffEngine.lua, Display.lua (modified)
- FOUND: cb821e3
- FOUND: 36029da
