---
phase: 40-cdm-steal-mode
plan: 03
subsystem: cdm-steal-mode
tags: [cdm, taint, visibility, edit-mode, config]
requires:
  - "40-01: ns:RefreshStealMirror, ns.stealSlots, the steal event frame"
  - "35.1: ns.db.stealMode default seed in Core.lua, the CDM tab steal checkbox"
provides:
  - "ns:SetStealMode(enabled) — the single, all-or-nothing entry point for the steal-mode flag"
  - "ns:ApplyStealVisibility() — the only writer of Blizzard CDM viewer visibility, three-gated"
  - "ns:QueueStealVisibility() — single-flight C_Timer.After(0) deferral"
  - "ns.stealPriorShown — runtime-only prior visibility capture (STEAL-07)"
affects:
  - "StealMode.lua"
  - "CDMTab.lua"
tech-stack:
  added: []
  patterns:
    - "EventRegistry callbacks instead of HookScript on CooldownViewerSettings"
    - "suspend-not-reassert while ShouldBeShown is unconditionally true"
    - "hoisted flush function so the deferral allocates nothing per queue"
key-files:
  created: []
  modified:
    - "StealMode.lua"
    - "CDMTab.lua"
decisions:
  - "pendingApply was deleted rather than shipped: the explicit re-trigger events are the retry"
  - "EventRegistry owner is stealEventFrame, not ns — ns already owns EditMode.Enter/Exit"
  - "PLAYER_LEVEL_CHANGED, never PLAYER_LEVEL_UP"
metrics:
  tasks: 4
  commits: 3
  completed: 2026-09-21
---

# Phase 40 Plan 03: Hide, Restore and the Toggle Summary

TBT now hides Blizzard's four CDM viewers when steal mode is on and restores each to exactly
its prior shown state when it is off, through a three-gated, deferred apply whose entire
contact with a Blizzard frame is a global lookup plus `IsShown`, `Hide` and `Show`.

## Commits

| Commit | Task | Scope |
|---|---|---|
| `d7b88e9` | 1 | `StealMode.lua` — capture, hide, restore, queue, `ns:SetStealMode` |
| `8107ae0` | 2 | `StealMode.lua` — re-assert triggers and the two suspension pairs |
| `8264754` | 3 | `CDMTab.lua` — checkbox wired to `ns:SetStealMode` |
| — | 4 | audit + format only; produced no file change, see Deviations |

## The complete CDM frame interaction surface

Every interaction TBT has with a Blizzard CDM frame that this plan introduced, classified
against the four permitted operations:

| Site | Operation | Class | Permitted |
|---|---|---|---|
| `StealMode.lua` `EachViewer` | `_G[def.cdmViewerGlobal]` | global table lookup, no frame method | #1 yes |
| `StealMode.lua` `CaptureAndHide` | `viewer:IsShown()` | C widget method, read | #2 yes |
| `StealMode.lua` `CaptureAndHide` | `viewer:Hide()` | C widget method, write | #3 yes |
| `StealMode.lua` `RestorePrior` | `viewer:Show()` | C widget method, write | #4 yes |
| `StealMode.lua` `RestorePrior` | `viewer:Hide()` | C widget method, write | #3 yes |

Nothing else. No CDM mixin method is called. No field is written on a CDM frame. No frame is
parented into one. `C_CooldownViewer.SetLayoutData` is never called anywhere in the addon.

Pre-existing and untouched by this plan (protected by the no-refactor rule):
`EditModeFrames.lua`'s Copy-Config button (mixin getter calls, v0.3.0) and `Display.lua`'s
`ns:InitDisplay` viewer lookup plus its `viewer.itemFramePool` **field read** (Phase 35,
commit `0537ee9`).

## Gate order, and what happened to `pendingApply`

`ns:ApplyStealVisibility` is reached from exactly one place — the `C_Timer.After(0, ...)` body
inside `ns:QueueStealVisibility`. Its gates, in order:

1. **Suspended** — `editModeOpen or cdmSettingsOpen` → return, no write. `ShouldBeShown`
   returns true unconditionally in both states (`CooldownViewer.lua:1888-1920`), so
   re-asserting would be a losing write loop in the code path that produced every recorded
   taint failure. Zero writes for the entire duration of either session.
2. **Combat** — `InCombatLockdown()` → return, no write.
3. **Structural, not a branch** — the single-caller-through-a-timer property, so the writes
   below never land on a Blizzard call stack.

**`pendingApply` was deleted.** As drafted, both early-return gates wrote it and nothing read
it; correctness is carried entirely by the explicit re-trigger events (`PLAYER_REGEN_ENABLED`,
`EditMode.Exit`, `CooldownViewerSettings.OnHide`), each of which re-queues. A flag with no
reader would have advertised a retry mechanism that does not exist. A comment on gate 2 records
this.

## Re-assert events as registered

On `stealEventFrame`, all through the pcall-guarded `TryRegisterStealEvent`:

- `PLAYER_ENTERING_WORLD` (already registered by Plan 01 for the mirror; now also re-asserts)
- `PLAYER_REGEN_ENABLED`
- **`PLAYER_LEVEL_CHANGED`** — confirmed, **not** `PLAYER_LEVEL_UP`. Blizzard re-asserts
  `UpdateShownState()` on `PLAYER_IN_COMBAT_CHANGED` and `PLAYER_LEVEL_CHANGED`
  (`CooldownViewer.lua:1764-1765`); `PLAYER_LEVEL_UP` appears in the file only inside the
  comment that explains why it was rejected.
- `VARIABLES_LOADED`
- `CVAR_UPDATE`
- `EDIT_MODE_LAYOUTS_UPDATED`

`PLAYER_IN_COMBAT_CHANGED` is deliberately absent — the write it would provoke is the one the
combat gate forbids.

`EventRegistry` callbacks (all behind `if EventRegistry then`, owner `stealEventFrame`):
`EditMode.Enter` (suspend), `EditMode.Exit` (resume + queue),
`CooldownViewerSettings.OnShow` (suspend), `CooldownViewerSettings.OnHide` (resume + queue).

## How STEAL-07 avoids recording TBT's own hidden state

`CaptureAndHide` captures **only when `ns.stealPriorShown[globalName] == nil`**, so the read
happens on the first apply of a steal-mode session and never again. Every later apply while
steal mode is on sees a non-nil entry and skips straight to `Hide()`, so the `false` TBT itself
produced can never overwrite the user's real preference. Switching steal mode off restores from
the table and then `wipe()`s it, so the next switch-on re-captures from scratch. The same nil
test makes the two entry paths identical: a checkbox click and a login with `ns.db.stealMode`
already true. In the checkbox case the capture is additionally well-timed for free — the
checkbox lives inside the CDM settings window, so gate 1 suspends the apply until that window
closes and `IsShown()` is read after Blizzard has settled its own state.

## Verification results

`stylua --check .` from the repo root exits **0**. `luac` is not on this machine's PATH, so the
syntax-check step was skipped — stated rather than silently omitted. There is no test runner,
no CI suite and no headless harness for a WoW addon; the static assertions below are the
verification.

| Check | Result |
|---|---|
| `grep -nE 'viewer:[A-Za-z]+\(' StealMode.lua` | pass — exactly three distinct names: `IsShown`, `Hide`, `Show` (lines 199/201/215/217, plus three documentation lines in the surface table comment) |
| `grep -nE 'viewer\.[A-Za-z_]+ *=' StealMode.lua` | pass — no output |
| `grep -n 'SetParent' StealMode.lua` | pass — no output |
| `grep -n 'GetSettingValue\|IsActive(\|ShouldBeShown(\|GetItemCount(\|RefreshLayout(\|SetLayoutData(' StealMode.lua` | pass — no output |
| `grep -n 'function ns:SetStealMode' / 'function ns:ApplyStealVisibility'` | pass — one each (lines 281, 223) |
| `grep -n 'InCombatLockdown()' StealMode.lua` | pass — line 240, guarding every write path |
| `grep -n 'stealPriorShown' StealMode.lua` | pass — declaration 162, capture 198-199, restore 207, wipe 253 |
| `grep -n 'stealPriorShown' Core.lua BuffEngine.lua` | pass — no output; never persisted |
| four `EventRegistry` callback names present | pass — lines 391/394/398/401 |
| six re-assert event names present | pass |
| `grep -n 'ns.editModeActive' StealMode.lua` | pass — no output |
| `grep -n 'HookScript' StealMode.lua` | pass — no output |
| `ns:ApplyStealVisibility` call sites | pass — one, inside `FlushStealVisibility`, itself the sole `C_Timer.After(0, ...)` target |
| `grep -n 'C_Timer.After' StealMode.lua` | pass — one call, line 275 (four other hits are comment prose, none a call form) |
| `grep -n 'ns.db.stealMode = ' CDMTab.lua` | pass — no output |
| `grep -rn 'ns.db.stealMode = ' *.lua` | pass — exactly two: `Core.lua:626` default seed, `StealMode.lua:286` inside `ns:SetStealMode` |
| `grep -rno 'steal[A-Za-z]*' *.lua \| sort -u` | pass — `stealCheck`, `stealDesc`, `stealEventFrame`, `stealLabel`, `stealMode`, `stealPriorShown`, `stealSlots`. No per-category variant (STEAL-06) |
| `grep -c 'TBTStealModeCheckbox' CDMTab.lua` | pass — 1 |
| `git diff CDMTab.lua` | pass — changes confined to the checkbox `OnClick` and its comment |
| `grep -rn 'SetLayoutData(' *.lua` | pass — no output |
| `grep -rn 'GetBuildInfo' *.lua` | pass — one hit, `Core.lua:336` |
| `grep -rn 'CLIENT_HAS_SPELL_RANKS' *.lua` | pass — one definition (`Core.lua:344`), one reader (`CDMTab.lua:941`) |
| `grep -rn 'schemaVersion' *.lua` | pass — unchanged, `CURRENT_SCHEMA_VERSION = 4` |
| `git status --porcelain` | pass — only `StealMode.lua` and `CDMTab.lua` were modified by this plan |

### Two audit criteria whose literal wording did not match reality

Both concern **pre-existing** code, and the substantive assertion behind each still holds.

1. `grep -rn 'cdmViewerGlobal' *.lua` — the plan predicted hits only in `Core.lua`,
   `EditModeFrames.lua` and `StealMode.lua`. There are also hits in **`Display.lua:471-474`**
   (`ns:InitDisplay`). `git blame` dates them to Phase 35 (`0537ee9 feat(35-04)`), not this
   phase. They are a global lookup plus a `viewer.itemFramePool` field *read* — no mixin call,
   no write, no parenting. The criterion's intent, "no **new** file references a CDM viewer",
   is met: this plan added references in `StealMode.lua` only.
2. `grep -rn 'SetParent' *.lua` — the plan predicted every hit would be `Display.lua`'s
   `pool[i]:SetParent(nil)`. There are five hits: `Display.lua:139` and
   `EditModeFrames.lua:866` (both `SetParent(nil)`), `CDMTab.lua:1495` (`SetParent(nil)`), and
   `CDMTab.lua:380`/`391` (the drag marker reparented onto `section.container`, a TBT panel
   frame). Read individually, **no frame is parented into a CDM frame anywhere in the addon** —
   which is the assertion that matters. All five predate this phase.

## Deviations from Plan

**1. [Rule 2 — correctness] `EventRegistry` owner changed from `ns` to `stealEventFrame`.**
- **Found during:** Task 2.
- **Issue:** The plan's idiom would have registered `EditMode.Enter` / `EditMode.Exit` with
  owner `ns`. `CallbackRegistryMixin:RegisterCallback` allows **one callback per owner per
  event** and unregisters the previous one first (`CallbackRegistry.lua:128-130`), and
  `EditModeFrames.lua:887-892` already registers both of those events with owner `ns`. Shipping
  as drafted would have silently replaced TBT's own `ns:OnEditModeEnter` / `ns:OnEditModeExit`
  handlers — a live bug in container positioning, not a style issue.
- **Fix:** All four new callbacks use `stealEventFrame` as the owner. `StealMode.lua`'s
  pre-existing `CooldownViewerSettings.OnDataChanged` registration keeps owner `ns` (no
  collision, and the no-refactor rule applies).
- **Commit:** `8107ae0`

**2. [reporting] Three comments name an API by description instead of by identifier.**
- **Found during:** Task 2.
- **Issue:** The plan asked for comments explaining why `PLAYER_LEVEL_UP`, TBT's own Edit-Mode
  flag and script-hooking the CDM settings frame were each rejected — while *also* asserting
  that `grep -n 'ns.editModeActive'` and `grep -n 'HookScript'` return nothing. Prose mentioning
  the identifier satisfies the first and breaks the second.
- **Fix:** The Edit-Mode flag and the hook API are named by description, each with a
  parenthetical stating that this is to keep the STEAL-08 audit grep a true negative. The same
  treatment was applied to the mixin getter in the surface-table comment. `PLAYER_LEVEL_UP` is
  kept verbatim — no negative grep covers it, and naming the rejected alternative is exactly
  the anti-regression note plan review asked for.
- **Commit:** `8107ae0` (plus `d7b88e9` for the getter mention)

**3. Task 4 produced no commit.** `stylua` was run from the repo root after every task, so by
Task 4 `stylua --check .` already exited 0 and there was nothing left to reformat. The audit is
recorded here instead of in a commit body. No code change was invented to justify a commit.

**4. `ns:SetStealMode` has an `if not ns.db then return end` guard** not spelled out in the
plan — the standing capability-guard rule (a missing prerequisite degrades to a no-op, never an
error).

**5. `PLAYER_ENTERING_WORLD` re-asserts visibility as well as refreshing the mirror.** Task 2's
prose says "these five events", but the Approach section's named re-assert trigger list includes
`PLAYER_ENTERING_WORLD`, and correctness requires it: without it, a login with `ns.db.stealMode`
already true would never hide the viewers. Six events are in `REASSERT_VISIBILITY`.

No auth gates occurred.

## Known Stubs

None. Every code path added by this plan is wired to a real data source and a real trigger.

## Threat Flags

None. This plan adds no network endpoint, no auth path, no file access and no schema change.

## In-game checks — Forever only (Phase 42)

`human_needed` — **not attempted, not claimed.** Retail is untouched until Phase 44. These are
the only human verification in the phase and they fold into Phase 42.

1. **Fresh `/reload`, then `/tbt`.** Steal-mode checkbox is unticked on a database that has
   never had it on (`STEAL-01`).
2. **Tick it, close the CDM window, out of combat.** All four Blizzard viewers disappear; their
   items appear in TBT's four base containers alongside the user's own trackers, styled as TBT
   items (`STEAL-02`, `STEAL-03`, `STEAL-04`).
3. **Same session: add a spell to a CDM category and remove another.** TBT's containers follow
   within a second or two, with no `/reload` (`STEAL-05`).
4. **Untick the checkbox and close the CDM window.** Each Blizzard viewer returns to exactly the
   shown/hidden state it had at step 2, including any viewer that was already hidden then
   (`STEAL-07`).
5. **Taint run — must start from a fresh `/reload`, because taint is sticky and clears only on
   `/reload`.** With steal mode on: enter open-world combat and cast repeatedly; leave combat;
   open Edit Mode; move a TBT container; save and exit Edit Mode; enter combat again and cast
   repeatedly. Expect **no Lua error**, and specifically no
   `CooldownViewerItemData.lua:782: attempt to perform boolean test on local 'hasTotem'`
   (`STEAL-08`).
6. **Known and expected during step 5:** Blizzard's viewers reappear the moment combat starts
   and disappear again when it ends. That is the accepted consequence of the combat gate, not a
   failure — see the plan's **Risks**.

## Self-Check: PASSED

- `StealMode.lua` — FOUND (405 lines added across the phase; this plan's additions present)
- `CDMTab.lua` — FOUND, modified
- `.planning/phases/40-cdm-steal-mode/40-03-SUMMARY.md` — FOUND
- commit `d7b88e9` — FOUND
- commit `8107ae0` — FOUND
- commit `8264754` — FOUND
