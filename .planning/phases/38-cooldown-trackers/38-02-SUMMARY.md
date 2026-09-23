---
phase: 38-cooldown-trackers
plan: 02
subsystem: display
tags: [cooldown, render, charges, secret-values, hot-path]
requires: ["38-01"]
provides:
  - "Display.lua cooldown render branch (icon-only, engine-driven sweep)"
  - "Display.lua chargeCount widget on CreateTimerIcon"
  - "Display.lua cooldownSlotCounts generation-stamped cache"
affects: ["Display.lua"]
tech-stack:
  added: []
  patterns:
    - "generation-stamped invalidation instead of per-frame API reads"
    - "sticky capability cache written only from a non-secret value"
    - "index-inside-pcall for a possibly-secret struct field"
key-files:
  created: []
  modified: ["Display.lua"]
decisions:
  - "Charge font/anchor taken verbatim from CooldownViewerBuffIconItemTemplate / CooldownViewerEssentialItemTemplate: NumberFontNormal at BOTTOMRIGHT (-2, 2)"
  - "A cooldown slot counts as activity for hideWhenInactive, so a cooldown-only container never auto-hides"
  - "Cooldown entries are skipped by RenderBarContainer rather than drawn as empty bars"
metrics:
  tasks: 4
  commits: 3
  completed: 2026-09-21
---

# Phase 38 Plan 02: Cooldown Slot Rendering and the CDM Charge Count Summary

Cooldown trackers now render as icons with an engine-driven sweep from
`C_Spell.GetSpellCooldownDuration`, plus a CDM-matching charge count, with every API read
gated behind `ns.cooldownGeneration` / `ns.trackerGeneration` so the 0.05s render tick stays
allocation-free and read-free.

## Commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 | `31ccdbf` | CDM charge-count widget on `CreateTimerIcon` |
| 2 | `3c4d552` | Module-level cooldown helpers and the slot-count cache |
| 3 | `fa19683` | Cooldown branch wired into the render path |
| 4 | — | `stylua` formatting folded into the commits above; no separate change |

## What Was Built

**`CreateTimerIcon`** gains `frame.chargeCount`, a `setAllPoints` child `Frame` created
*after* `frame.cooldown` (so it draws above the swipe) holding one `OVERLAY` `FontString`
with `SetFontObject(NumberFontNormal)` anchored `BOTTOMRIGHT, -2, 2`, hidden on creation.
Taken field-for-field from `Blizzard_CooldownViewer/CooldownViewer.xml` — the `Applications`
frame of `CooldownViewerBuffIconItemTemplate` and the `ChargeCount` frame of
`CooldownViewerEssentialItemTemplate` use the identical construction. The 30x30
`CooldownViewerUtilityItemTemplate`'s `NumberFontNormalSmall` is deliberately not used.

**Module-level state:** `cooldownSlotCounts` + `cooldownCountStamp` (per-container cooldown
slot counts, rebuilt only when `ns.trackerGeneration` moves) and `chargeCapable` (sticky
`spellID -> boolean`, written only from a value `issecretvalue` says is readable).

**Four file-local helpers** above `RenderBarContainer`:
- `RefreshCooldownSlotCounts()` — integer compare and return on an unchanged generation;
  otherwise nil-guards `ns.db.trackedBuffs`, stamps, `wipe()`s and walks once. The stamp is
  written *after* the DB guard, so a not-yet-ready DB is retried rather than cached as "no
  cooldown slots".
- `ApplyCooldownHandle(icon, spellID)` — handle flows from the fetch straight into
  `SetCooldownFromDurationObject` with a nil test as the only thing done to it. Both symbol
  tests (`C_Spell.GetSpellCooldownDuration`, `icon.cooldown.SetCooldownFromDurationObject`)
  are capability checks; a client missing either gets an icon with no sweep, not an error.
- `SetChargeText(fontString, info)` — exists solely so the `info.currentCharges` index happens
  *inside* the protected call.
- `ApplyChargeCount(icon, spellID)` — `ns:CanReadTable(info)` gates every read;
  `issecretvalue` guards the only comparison (`maxCharges > 1`); the value reaches `SetText`
  and nothing else.
- `ApplyCooldownSlot(icon, entry, settings)` — texture (with the `or icon.cachedIcon == nil`
  half of the cache test), `ApplyIconStyle`, `icon.proc = entry`; API calls only when
  `icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key`.

**Render path:** `ns:UpdateDisplay` calls `RefreshCooldownSlotCounts()` once per tick outside
the container loop. `RenderBarContainer`'s placeholder walk gains
`and entry.trackerType ~= "cooldown"`. `RenderIconContainer`'s `hasActiveIcons` becomes
`#timers > 0 or (cooldownSlotCounts[def.key] or 0) > 0`, and the branch chain is now
timer → cooldown → placeholder → hide, with both non-cooldown branches dropping a stale
`_cdKey` / charge count / engine sweep from a recycled pooled widget.

## Verification

| Check | Result |
| ----- | ------ |
| `grep -n 'GetSpellCooldownDuration(' Display.lua` | 1 call site, in `ApplyCooldownHandle` — PASS |
| `grep -n 'GetSpellCharges(' Display.lua` | 1 call site, in `ApplyChargeCount` — PASS |
| `grep -n 'SetCooldownFromDurationObject(' Display.lua` | 1 call, in `ApplyCooldownHandle` — PASS |
| `grep -n 'ScanActiveTimersForCancellation' Display.lua` | nothing — PASS |
| `grep -n 'GetBuildInfo\|CLIENT_HAS_SPELL_RANKS' Display.lua` | nothing — PASS |
| `grep -c 'ApplyCooldownSlot' Display.lua` | 2 — PASS |
| `{` in the four new helpers | 0 — PASS |
| `{` in `ns:UpdateDisplay` / `RenderBarContainer` / `RenderIconContainer` | 0 / 1 / 1, identical to `ba9a163` — PASS |
| `stylua --check .` from repo root | exit 0 — PASS |
| `git diff --name-only` before commit | `Display.lua` only, 44 insertions / 2 deletions, no line-ending churn — PASS |
| `luac` syntax gate | `luac` is not on this machine's PATH — skipped, as the plan states |

### Criterion corrected

Task 1's `grep -n 'NumberFontNormalSmall' Display.lua returns nothing` conflicts with the same
task's instruction to comment the block explaining that the Utility template's
`NumberFontNormalSmall` is the wrong pair for a 40x40 icon. The comment was written as
instructed, so the grep matches one comment line. Verified instead that there is no *code* use:
`grep -n 'NumberFontNormalSmall' Display.lua | grep -v -- '--'` is empty. Same class of
comment-vs-code conflict the plan already corrected for the three `(`-suffixed API greps.

The `ScanActiveTimersForCancellation` verification grep hit the same conflict — a new comment
named the function. The comment was reworded to "BuffEngine's aura-driven cancellation scan",
which preserves the meaning and leaves the grep clean.

## In-Game Checks — Forever only, deferred to Phase 42

Not attempted in this plan. Each line is a labelled human observation, not an automated gate.
Retail is untouched until Phase 44.

1. Add a spell the Blizzard CDM does not track (Escape Artist, or another racial) as a
   **Cooldown** into Essential Cooldowns. Its icon appears immediately, with no sweep. (`CD-04`)
2. Use it. The sweep starts and runs down correctly. Enter combat mid-sweep; it keeps running
   and no Lua error appears. (`CD-02`)
3. In combat, trigger an effect that reduces that spell's cooldown. The sweep jumps, with no
   `/reload` and without leaving combat. (`CD-02`)
4. Add a genuine multi-charge spell as a Cooldown. Out of combat its charge count shows at the
   bottom-right of the icon; spend one charge and the number drops; wait and it rises again.
   Compare the number's font, size and position against a CDM Essential icon side by side.
   (`CD-03`)
5. Open the CDM settings tab. The cooldown icon previews with a demo sweep beside buff bars and
   buff icons. Close it; the preview clears and any real sweep is still correct. (`CD-05`)
6. With `hideWhenInactive` on and no buffs up, a container holding only cooldown trackers stays
   visible.
7. From a clean `/reload`: combat, then Edit Mode out of combat, then an Edit Mode save, then
   combat again. No Lua error, and specifically none from `SetText` on a secret charge count.

`CD-06`'s persistence half can only be proven on retail in Phase 44 — the Forever beta never
reads saved variables back.

## Deviations from Plan

Two acceptance greps were wrong about the code rather than the code being wrong; both are
documented under "Criterion corrected" above. No other deviation.

## Known Stubs

None.

## Self-Check: PASSED

- `Display.lua` exists and is formatted.
- Commits `31ccdbf`, `3c4d552`, `fa19683` exist on
  `milestone/v0.4.0-cooldown-tracking-cdm-view`.
