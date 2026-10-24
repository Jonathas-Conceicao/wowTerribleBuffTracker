# Phase 79: Buff Countdown Display Fix — Context

**Gathered:** 2026-10-24, during `/gsd-plan-phase 79`, with the user. No discuss step.

## Phase Boundary

A running buff timer's icon shows its remaining time in the aura countdown format, as the CDM's buff
icons do. A real cooldown keeps the cooldown format. This is a display-only change in `Display.lua`.

## What the user saw

- A reminder and a cooldown buff (a flask, typed 1h), each on a buff with about 1h left, both read
  "2h". The game's own buff showed about 1h at the same moment.
- It survived a `/reload`, so the cold login is not the cause (the milestone was first scoped as a
  login bug and re-scoped by user decision).
- The CDM settings preview showed the reminder's timer correctly. The user suspects "the value shown
  and not the internal value". This matches the cause below: the timer is right and the text is not.
- On another character, a buff with 6m left read "2h". The cause below does not explain that case
  cleanly. It is part of the in-game check (VER-14). If it is still wrong after the fix, it is a
  separate bug to investigate then. Do not widen this phase for it.

## Cause (found during planning)

TBT's icons draw every sweep with `icon.cooldown:SetCooldown(start, duration)` on a
`CooldownFrameTemplate` (Display.lua `CreateTimerIcon`, :518), and never set the countdown format.
The cooldown countdown text rounds hours up, so a buff with a bit over 1h left reads "2h".

Blizzard's CDM buff icons call `cooldownFrame:SetUseAuraDisplayTime(true)`
(`wow-ui-source/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:1397`, in
`CooldownViewerBuffIconItemMixin:OnLoad`). The CDM's cooldown items switch it per state through
`self.cooldownUseAuraDisplayTime`: true while an aura drives the sweep (:877, :895), false for a
cooldown (:924, :1006, :1040, :1059, :1086), and applied at :1150. API doc
(`Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua:545`): "Aura durations are
displayed slightly differently than cooldown durations. Setting this to true will adjust the display
logic to stay in sync with aura timers." `SecretArguments = "AllowedWhenUntainted"`; the argument is
a plain boolean TBT computes itself.

## Implementation Decisions

- **D-01:** Every icon drawn by the timer branch (a running proc: buff tracker, reminder, Trinket/Pot,
  a cooldown's own buff) uses `SetUseAuraDisplayTime(true)`. Every real cooldown sweep
  (`ApplyCooldownSlot` and what it calls) uses false. This mirrors the CDM's per-state switch.
- **D-02:** Pooled icons move between branches, so the format is set every time an icon is drawn,
  guarded by a per-icon cache stamp so the hot path makes no call when nothing changed. Follow the
  existing `ApplySwipeLook` (:898) shape: a small file-local helper with an `icon._...` stamp. Put it
  near `ApplySwipeLook`; whether to fold it into that helper is the planner's call, but
  `ApplySwipeLook`'s `aura` argument means "the yellow cooldown-buff look", which is true only for a
  cooldown slot's buff, so it is not the same flag. Do not reuse it as-is.
- **D-03:** Guard the method (`if cooldown.SetUseAuraDisplayTime then`). The existing comment at
  :892-894 says the call "cannot be confirmed on the Forever client from the Midnight-only source
  tree". A client without it keeps today's format, with no error. Update that comment, which today
  says the call "is not used".
- **D-04:** Whether a format change needs the sweep re-issued (nil the `_lastStart` / `_userCdState`
  / `_cdGen` stamps as `ApplySwipeLook` does) is the planner's call. Re-issuing is the safe default
  and costs nothing when the stamp is unchanged.
- **D-05:** Nothing else changes: timers, `ns:RefreshAuraStates`, the sweep, the yellow aura look,
  the bars (`FormatTime`, :401, already prints m:ss), Merge Mode (Blizzard's own frames), saved data.

## Project rules that apply

- `stylua .` after editing; `./scripts/install.bat` to deploy; CRLF on Lua (check
  `git ls-files --eol Display.lua`).
- `node scripts/aura-read-gate.js` must still pass (no aura API is touched, but run it).
- A file-local helper must be declared above every function that calls it (memory: the Lua
  upvalue-order trap, hit 5 times). `ApplySwipeLook` sits at :898, above both callers.
- Match the surrounding comment style: say why, cite the Blizzard source line.

## Verification

The user checks in game on Midnight retail before the release (VER-14). There is no separate testing
phase. The plan ends with a human checkpoint listing the checks:
1. A flask (or any buff) with more than 1h left, on a cooldown's buff, a reminder and a buff tracker:
   the icon's countdown matches the game's buff display (no "2h").
2. A real cooldown's countdown looks as before.
3. A pooled icon switching (a cooldown's buff ending into the grey cooldown) shows the right format.
4. The "6m shows 2h" case, if the user can reproduce it.

## Deferred

- Backlog 999.28 (one aura pass for all three kinds): not now, user decision.
