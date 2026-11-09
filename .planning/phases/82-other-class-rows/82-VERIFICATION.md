---
phase: 82-other-class-rows
verified: 2026-11-09T12:00:00Z
status: passed
score: 5/5 roadmap criteria verified (9/9 requirements, 12/12 plan truths)
overrides_applied: 0
human_verification: # deferred to Phase 85 (Forever Testing Pass); code-trace only here
  - test: "Forever warlock: Demon Armor and Demon Skin reminders show; casting either hides both"
    expected: "One armor up hides both reminders; with none up both show"
    why_human: "Aura presence on the live Forever client cannot be traced statically"
  - test: "Forever shaman: Lightning Shield / Water Shield (408510, a reused ID) group"
    expected: "Either shield up hides both; Lightning Shield reappears when its charges are spent"
    why_human: "408510 is a reused ID and the aura ID must be checked with TBT's ID tooltip"
  - test: "Forever priest: Inner Fire (10 min), Shadowform (no timer), Shadowguard only for Trolls, Shadow Protection hidden by Prayer of Shadow Protection or a lower rank from another priest"
    expected: "Each row behaves as described; non-Troll priests are never offered Shadowguard"
    why_human: "Known-spell answers and buffs applied by another player need the live client"
  - test: "Forever paladin: one Devotion Aura reminder hidden by any rank of Devotion, Retribution, Concentration or the three resistance auras"
    expected: "Any paladin aura active hides the reminder"
    why_human: "Aura IDs per rank must match the live client"
  - test: "Forever hunter: Aspect of the Hawk reminder hidden by Monkey, Cheetah, Pack, Wild or Beast, never by Viper or Falcon"
    expected: "Viper/Falcon active leaves the reminder showing"
    why_human: "Live aura reads"
  - test: "Forever mage: Amplify Magic / Dampen Magic group, including lower ranks cast by another mage"
    expected: "Either one up hides both"
    why_human: "Live aura reads"
  - test: "Forever warlock: Demonic Sacrifice (120 min) watches aura 18789 and is hidden by 18790/18791/18792"
    expected: "Sacrificing any demon hides the reminder; the 120 min timer starts on the 18788 cast"
    why_human: "The cast/aura ID split must be confirmed in game"
  - test: "Retail: no new reminder offered, existing reminders unchanged"
    expected: "Suggested list on retail identical to before the milestone"
    why_human: "Final confirmation on the live retail client"
---

# Phase 82: Other Class Rows Verification Report

**Phase Goal:** Forever warlocks, shamans, priests, paladins and hunters are offered reminders for their maintained self buffs, with exclusive buffs grouped so any one up hides the others
**Verified:** 2026-11-09
**Status:** passed (code-trace; in-game items deferred to Phase 85 per the orchestrator's instruction)
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Warlock armors grouped; shaman shields grouped; priest Inner Fire 10 min, Shadowform no timer, Shadowguard only if known | VERIFIED | Providers.lua rows `MetaReminderRow(11735, 30)`, `(696, 30)`, `(10432, 10)`, `(408510, 10)`, `(10952, 10)`, `(15473, 0)`, `(19312, 10)`; groups `MetaReminderGroup(11735, 696)` and `(10432, 408510)` in the Forever block. `minutes > 0 and minutes*60 or nil` makes 15473 timerless (same as the retail 465 row). Shadowguard knownID = 19312; `ns:SpellKnownState` walks the Forever rank family, and `ns:MetaReminderSuggestionKeys` offers a row only when it is known (fallback false), so only a priest who knows a Shadowguard rank is offered it |
| 2 | Paladin: one Devotion Aura (10293) row hidden by any Devotion/Retribution/Concentration/resistance aura; hunter: one Hawk (25296) row hidden by Monkey/Cheetah/Pack/Wild/Beast, never Viper/Falcon | VERIFIED | `MetaReminderRow(10293, 0)` + 22-ID one-way group (465 rank 1 only inside the block); `MetaReminderRow(25296, 0)` + `MetaReminderGroup(25296, 13163, 5118, 13159, 20043, 20190, 13161)`. 34074 and 469145 appear nowhere in Providers.lua. Alternatives are folded into the aura watch list by Core.lua (~1670) through `ns:CastRuleFamily(altID)`, so any listed aura satisfies the row |
| 3 | Amplify/Dampen grouped with all ranks; Shadow Protection hidden by Prayer of Shadow Protection or lower ranks; no detection/tracking skill | VERIFIED | `MetaReminderGroup(10170, 10174, 1008, 8455, 10169, 604, 8450, 8451, 10173)`; `MetaReminderGroup(10958, 976, 10957, 27683)`; gate confirms no detection/tracking IDs in the table; header names MREM-17 as dropped |
| 4 | Demonic Sacrifice 18788, 120 min, watches 18789, hidden by 18790/18791/18792 | VERIFIED | `MetaReminderRow(18788, 120, nil, nil, nil, { auraID = 18789 })` is the last new row; `ns:ApplyMetaReminderDef` copies `def.auraID` onto the entry; the watch list starts from the detailed aura family (BuffEngine `ns:DetailedAuraID`) and adds the alternatives; `MetaReminderGroup(18788, 18790, 18791, 18792)` is the last call in the block. castID defaults to 18788, so a click casts it |
| 5 | Retail: no new reminder, existing ones unchanged | VERIFIED | All 13 new rows have no `client` opt, so `MetaReminderRow` returns early when `ns.CLIENT_IS_FOREVER` is false (never registered, never offered). All 7 group calls sit inside `if ns.CLIENT_IS_FOREVER then`. Phase 82 diff on Providers.lua: 66 additions, 0 deletions; the gate confirms every baseline row and both helper bodies byte-identical |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | 13 Forever rows + 7 Forever-block group calls + header note | VERIFIED | Present, substantive, registered at load (TOC loads Core.lua before Providers.lua, so `ns.CLIENT_IS_FOREVER` is set) |
| `.planning/phases/82-other-class-rows/82-check-rows.js` | Source gate | VERIFIED | Ran: "all checks passed", exit 0 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Forever-block group calls | `metaReminderDefsBySpellID` | block placed after all rows | WIRED | Gate: "the block sits after every MetaReminderRow call" |
| `{ auraID = 18789 }` | entry.auraID | `ns:ApplyMetaReminderDef` | WIRED | `if entry.auraID ~= def.auraID then entry.auraID = def.auraID end` |
| def.alternatives | aura watch list | Core.lua reminder watch rebuild | WIRED | Alternatives' rank families appended to the combined list stored as `satisfied[key]` |
| rows | Suggested offer | `ns:MetaReminderSuggestionKeys` | WIRED | Iterates META_REMINDER_DEFS, offers known rows |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase gate | `node .planning/phases/82-other-class-rows/82-check-rows.js` | all checks passed, exit 0 | PASS |
| Formatting | `stylua --check .` | clean | PASS |
| Line endings | `git ls-files --eol Providers.lua` | `w/crlf attr/text eol=crlf` | PASS |
| Diff scope | `git log 7451564..HEAD -- Core.lua ReminderClick.lua Providers.lua` | Phase 82 commits touch Providers.lua only (Core/ReminderClick changes are 81-01's 227430b) | PASS |

### Probe Execution

Not applicable: no `probe-*.sh` declared or present for this phase.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| MREM-08 | 82-01 | SATISFIED | Rows 11735/696 at 30 min, mutual group |
| MREM-09 | 82-01 | SATISFIED | Rows 10432/408510 at 10 min, mutual group |
| MREM-10 | 82-01 | SATISFIED | 10952 at 10 min; 15473 at 0 (no timer) |
| MREM-11 | 82-01 | SATISFIED | 10293 at 0, one-way group of all paladin aura ranks; 465 never a Forever row |
| MREM-12 | 82-01 | SATISFIED | 25296 at 0, one-way group; no Viper/Falcon |
| MREM-13 | 82-01 | SATISFIED | 18788 at 120 min, auraID 18789, group with 18790-18792 |
| MREM-14 | 82-01 | SATISFIED | 19312 at 10 min, known-spell rule gates the offer |
| MREM-15 | 82-01 | SATISFIED | 10170/10174 at 10 min, group with all ranks |
| MREM-16 | 82-01 | SATISFIED | 10958 at 10 min, group with 976, 10957, 27683 |
| MREM-17 | — | DROPPED (user, 2026-11-09) | No row; header records the decision |

No orphaned requirements.

### Anti-Patterns Found

None. No TBD/FIXME/XXX/TODO in the Phase 82 diff; no comment inside a multi-line expression (no CRCRLF).

Info only: all new rows carry "(unverified in game)", by design until Phase 85.

### Human Verification Required

Listed in frontmatter `human_verification`; all deferred to Phase 85 (Forever Testing Pass), which is the milestone's in-game check. Highest-risk items: Water Shield's reused ID 408510 and Demonic Sacrifice's cast/aura split.

### Gaps Summary

No gaps. Every roadmap criterion and requirement is met in code; the remaining uncertainty is live aura ID behaviour, which only the Phase 85 in-game pass can settle.

---

_Verified: 2026-11-09_
_Verifier: Claude (gsd-verifier)_
