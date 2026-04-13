---
phase: 15-display-integration-active-icon-switching
plan: 01
wave: 1
depends_on: []
autonomous: false
requirements: [ICON-03, ICON-04]
files_modified: []
---

# Plan 15-01: Verify Active/At-Rest Icon Transition

<objective>
Phase 15 (ICON-03 + ICON-04) is functionally satisfied by Phases 13 and 14:
- Phase 13 stores cast spell icon in timer.icon (active = cast spell icon = ICON-03)
- Phase 14 placeholder branch reads ns.metaIcons for at-rest (expired → revert = ICON-04)

No code changes needed. This plan is a single human-verify checkpoint that confirms
the transition works cleanly end-to-end for both trinket and pot, on both Bars and
Buffs display sections, with no Lua errors.

After user approval, mark ICON-03 and ICON-04 complete in REQUIREMENTS.md traceability.
</objective>

<tasks>

<task number="1" type="checkpoint:human-verify">
  <name>Verify active → expired icon transition in-game</name>

  <action>
No automated substitute — user must observe the cast/expiry cycle visually.

Verification script (perform in-game):

1. `/reload` to ensure latest build is loaded.
2. Confirm trinket is in Bars section and pot is in Buffs section (or vice-versa).
3. Cast a tracked trinket out of combat.
   - Expected: bar icon switches to the cast spell's icon (e.g. Nullsight for Vaelgor)
   - Expected: bar label matches the cast spell name
   - Expected: bar fill animates countdown from full → empty over the spell's duration
4. Wait for natural expiry (or cancel the buff via right-click).
   - Expected: bar icon reverts to the at-rest resolved icon (first-match equipped trinket)
   - Expected: bar returns to placeholder state (no fill animation)
5. Cast a tracked pot in bags.
   - Expected: buff icon switches to cast pot's spell icon, cooldown swipe animates
6. Wait for natural expiry.
   - Expected: buff icon reverts to at-rest resolved pot icon
7. No Lua errors in chat at any point (`/console scriptErrors 1` should stay silent for TBT).
  </action>

  <verify>
    <automated>MISSING — visual in-game transition cannot be automated</automated>
  </verify>

  <acceptance_criteria>
    - User confirms active bar/icon shows cast spell icon (ICON-03)
    - User confirms icon reverts to at-rest on natural expiry (ICON-04)
    - No Lua errors during transition
  </acceptance_criteria>

  <done>
User replies "approved" confirming all 7 steps pass. Then mark ICON-03 and ICON-04
as complete in .planning/REQUIREMENTS.md traceability.
  </done>
</task>

</tasks>

<must_haves>
  - Active timer displays cast spell icon (ICON-03)
  - Timer expiry reverts icon to at-rest resolved icon (ICON-04)
  - No Lua errors during active/expired transition
</must_haves>

<verification>
User-verified in-game smoke test. Upon approval, Task 1 done step updates REQUIREMENTS.md.
</verification>
