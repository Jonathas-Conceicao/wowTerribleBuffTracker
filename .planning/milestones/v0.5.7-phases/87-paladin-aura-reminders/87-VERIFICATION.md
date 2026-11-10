---
phase: 87
status: passed
verified: 2026-11-10
---

# Phase 87 Verification

| Success criterion | Evidence | Result |
|---|---|---|
| 1. Forever rows 10293, 10301, 19746, 19896, 19898, 19900, permanent, offered by known rank | `Providers.lua` paladin block, `minutes = 0`, default knownID (rank family by name) | pass |
| 2. Any Forever aura of any rank hides all (one group in the Forever block) | the single 22-ID group inside `if ns.CLIENT_IS_FOREVER` lists all six rows | pass |
| 3. Retail 465, 317920, 32223 tagged retail, mutual group | rows declared before `MetaReminderGroup(465, 317920, 32223)` | pass |
| 4. No shared ID; Devotion keys unchanged | row scan: only 1459 (`both`) in both sets; 10293 and 465 rows untouched | pass |
| 5. Doc lists every aura row; doc check and selftest pass; exclusions recorded internally | doc check PASS 46 rows, selftest 46 cases; NOT-INCLUDED has Sanctity and retail Retribution | pass |

In-game behaviour is deferred to Phase 89 (VER-16) by design.
