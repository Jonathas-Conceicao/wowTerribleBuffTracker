---
phase: 15-display-integration-active-icon-switching
plan: 01
subsystem: display
tags: [verification-only, icon-transition]

requires:
  - "Phase 13: OnSpellCastSucceeded sets timer.icon to cast spell icon"
  - "Phase 14: placeholder branch reads ns.metaIcons for at-rest icon"

provides:
  - "ICON-03 verified: active timer shows cast spell icon"
  - "ICON-04 verified: timer expiry reverts icon to at-rest resolved icon"

affects:
  - 16-cleanup

key-files:
  created: []
  modified:
    - .planning/REQUIREMENTS.md  # ICON-03/04 marked Complete

commits:
  - 15-01: Verification-only phase, no code commits

---

# Plan 15-01 Summary — Verify Active/At-Rest Icon Transition

## What was done

Zero code changes. Phase 15 requirements (ICON-03, ICON-04) were already satisfied by prior phases:

- **ICON-03** — Phase 13's `OnSpellCastSucceeded` sets `timer.icon = ns:GetSpellIcon(spellID)` where spellID is the numeric cast ID. Display's `if timer then` branch reads `timer.icon` directly, rendering the cast spell's icon.

- **ICON-04** — Phase 14's placeholder branch (`GetSuggestedAtRestIcon` → `ns.metaIcons[key]`) kicks in when `GetActiveTimers` cleans up an expired timer. Icon automatically reverts to at-rest equipped-trinket or bag-pot icon.

## In-game verification (user-confirmed)

User performed 7-step smoke test and approved:
1. `/reload` successful
2. Trinket and pot in correct sections
3. Trinket cast → bar icon = cast spell icon, label matches, fill animates
4. Expiry → icon reverts to at-rest equipped-trinket icon, bar returns to placeholder
5. Pot cast → buff icon = pot's spell icon, cooldown swipe animates
6. Pot expiry → icon reverts to at-rest bag-pot icon
7. No Lua errors throughout

## Deviations

None — phase scope was already met by prior work. This plan was a formal verification gate.

## Known Stubs

None.
