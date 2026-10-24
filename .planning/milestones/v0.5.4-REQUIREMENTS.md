# Requirements — v0.5.4 Buff countdown display fix

**Defined:** 2026-10-24, at kickoff, with the user. Research skipped by user decision. Re-scoped the
same day, by user decision, once Phase 79's planning found the cause.

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces
automatically.

**Scope, set by the user:** fix one bug and get a release ready. As first reported, a buff that was
already up at a cold login showed the wrong time: a reminder and a cooldown buff, each on a buff with
about 1h left, both showed "2h", while the game's own buff showed about 1h. The user then saw it
survive a `/reload`, and saw a buff with 6m left show "2h" on another character. So it is not
login-specific. The likely cause is the icon's countdown text, not the timer. TBT's buff icons use the
cooldown countdown format, which rounds hours up. Blizzard's CDM buff icons switch to the aura format
with `Cooldown:SetUseAuraDisplayTime(true)`
(`Blizzard_CooldownViewer/CooldownViewer.lua:1397`; API doc: "Aura durations are displayed slightly
differently than cooldown durations. Setting this to true will adjust the display logic to stay in
sync with aura timers.").

## v0.5.4 Requirements

### Buff countdown text

- [x] **BUFFTIME-01**: The countdown on a running buff timer's icon (a buff tracker, a reminder, a
  Trinket/Pot proc, or a cooldown's own buff) shows the remaining time the way the game's buff
  display does: a buff with about 1h left never reads "2h".
- [x] **BUFFTIME-02**: A real cooldown's countdown (a cooldown tracker with no buff running, Merge
  Mode untouched) keeps the cooldown format it has today. A pooled icon that switches between a
  buff and a cooldown always gets the right format for what it now shows.
- [x] **BUFFTIME-03**: The fix changes nothing else. The timers themselves (start, sync to the aura,
  end), the sweep, the yellow aura look and the bars stay as in v0.5.3, and no saved value is
  written. On a client without `SetUseAuraDisplayTime`, the icon keeps today's format and raises no
  error.

### Verification

- [x] **VER-14**: Before the release, the user checks BUFFTIME-01..03 in game on Midnight retail,
  including a buff with more than 1h left and the "6m shows 2h" case.

## Future Requirements

None added by this milestone.

## Out of Scope

| Item | Reason |
|------|--------|
| Plain buff trackers reading the aura's duration | Backlog 999.28, not now (user decision) |
| Other backlog items (999.11, 999.15, 999.16, 999.19, 999.27) | None promoted |
| A separate human-testing phase | User decision: the in-game check is part of the fix phase |
| Merge Mode icons | Blizzard's own frames, not TBT's |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUFFTIME-01 | Phase 79 | Complete — verified in game 2026-10-24 |
| BUFFTIME-02 | Phase 79 | Complete — code trace (79-REVIEW.md) |
| BUFFTIME-03 | Phase 79 | Complete — code trace and aura-read gate |
| VER-14 | Phase 79 | Complete — user sign-off 2026-10-24 |

**Coverage:** 4 / 4 requirements mapped, none orphaned, none duplicated.

---
*Requirements defined: 2026-10-24; re-scoped 2026-10-24*
