---
status: partial
phase: 61-bug-fixes
source: [61-VERIFICATION.md]
started: 2026-09-30
updated: 2026-09-30
---

## Current Test

[awaiting human testing — deferred to Phase 66, the milestone's single human testing pass (user decision at kickoff)]

## Tests

### 1. Prismatic Barrier shows buff time and charges together (STEAL-09)
expected: Retail Mage, Merge Mode on, Prismatic Barrier in the CDM. Cast it: the TBT cell shows the buff duration sweep AND the charge count at once, as the CDM's own icon does. When the buff ends, the cooldown display returns with the correct count.
result: pass — user-tested 2026-09-30 (charges show through the buff duration)

### 2. Charge and stack counts still draw above the swipe with Merge Mode off (review WR-03)
expected: Merge Mode off — an idle charge spell, a non-charge spell and a racial stack count all draw their number above the cooldown swipe, as before Phase 61. Note 2026-09-30: TBT's own user trackers carry no charge count, so test a racial stack count (e.g. Eureka). (The Prismatic Barrier the user saw here was a TBT bug, see #6.)
result: skipped — not testable, user decision 2026-09-30: TBT's custom trackers show no stack count (nor a duration on the buff icon itself), so there is no TBT-drawn number to check against the swipe. Testable only once BOTH backlog 999.19 (stack count) and 999.20 (duration on the icon) are done

### 3. Charge numbers never draw over TBT's Edit Mode overlays
expected: Enter Edit Mode with Merge Mode on — TBT's selection highlight/overlay on a container is not covered by charge numbers.
result: pass — user-tested 2026-09-30 (charge numbers cause no problem in Edit Mode)

### 4. Selecting a TBT container after a Blizzard system (EDM-08, review WR-04)
expected: Select a Blizzard Edit Mode system, then click a TBT container: TBT selects on mouse-down, its popup sits on top of Blizzard's dialog; Blizzard's yellow highlight may stay on (accepted). No Lua error, no taint message, including after leaving Edit Mode and entering combat.
result: pass — user-tested 2026-09-30 (Blizzard selection no longer cleared, as designed; no errors)

### 5. Merged Essential/Utility cell with a stacking aura shows no stack number (review WR-01)
expected: Merge Mode on, a merged Essential or Utility cell whose aura stacks: no stack number drawn (matches the CDM, whose Essential/Utility cells show only charges or cast count). Tracked Buffs cells still show their stacks.
result: pass — user-tested 2026-09-30

### 6. Merge Mode off leaves no merged aura behind (fix 8ac21ae)
expected: Reported 2026-09-30 with the CDM disabled and Merge Mode off: after using Prismatic Barrier, opening the settings preview showed the barrier buff on a TBT cell. Cause: turning Merge Mode off never re-sent the engine aura containers' filters, so containers built while it was on kept drawing their buffs' real auras. Check: Merge Mode on, then off (no reload); cast Prismatic Barrier; open the CDM settings: no barrier aura on any TBT container. Merge Mode back on: the merged cell shows the barrier again.
result: pass — user-tested 2026-09-30 (the Merge Mode off leftover is gone)

## Summary

total: 6
passed: 5
issues: 0
pending: 0
skipped: 1
blocked: 0

## Gaps
