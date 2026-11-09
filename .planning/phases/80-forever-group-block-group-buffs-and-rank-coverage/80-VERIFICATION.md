---
phase: 80-forever-group-block-group-buffs-and-rank-coverage
verified: 2026-11-09T00:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "On a Forever mage, have another player cast Arcane Brilliance (23028) or a higher Arcane Intellect rank (e.g. 10157 on a level-30 mage)"
    expected: "The Arcane Intellect reminder hides while the aura is up"
    why_human: "Aura readability (secret values) and the live aura ID can only be confirmed in game; Phase 85 (VER-15)"
  - test: "On Forever, receive Prayer of Fortitude / Prayer of Spirit / Gift of the Wild"
    expected: "The Fortitude / Divine Spirit / Mark of the Wild reminder hides"
    why_human: "In-game aura IDs; Phase 85"
  - test: "On a Forever paladin, receive a Greater Blessing (Kings 25898, Might 25782/25916, Wisdom 25894/25918)"
    expected: "Every blessing reminder hides"
    why_human: "In-game aura IDs; Phase 85"
  - test: "On Forever, with a Blessing of Salvation or Light reminder already placed, open the TBT tab"
    expected: "The tile is greyed, says no longer offered, saved data kept; Suggested no longer lists them"
    why_human: "UI rendering; Phase 85"
  - test: "On retail, check Arcane Intellect, Fortitude, Mark of the Wild, Battle Shout and Devotion Aura reminders"
    expected: "Behaviour unchanged; no 'Also satisfied by' alternatives beyond Devotion's 317920/32223"
    why_human: "Live client check; Phase 85"
---

# Phase 80: Forever Group Block, Group Buffs and Rank Coverage Verification Report

**Phase Goal:** On Forever, a group buff, a Greater Blessing or any rank of a class buff on the player hides its reminder, while every retail reminder behaves exactly as before
**Verified:** 2026-11-09
**Status:** passed (code trace; in-game confirmation is Phase 85 / VER-15 by design)
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (roadmap success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Forever: Arcane Brilliance 23028, Prayer of Fortitude 21562/21564, Prayer of Spirit 27681, Gift of the Wild 21849/21850 hide the matching reminder | VERIFIED | Providers.lua 1209-1215: `MetaReminderGroup(1459, ..., 23028)`, `(10938, ..., 21562, 21564)`, `(27841, ..., 27681)`, `(9885, ..., 21849, 21850)` inside the Forever block. Data flow traced below. |
| 2 | Forever: any blessing or Greater Blessing hides every blessing reminder | VERIFIED | Providers.lua 1228-1248: one call with 20217, 25291, 25290, Might ranks, Wisdom ranks, 25898, 25782, 25916, 25894, 25918. All three blessing rows (1176-1178) are in it, so each gets the other 18 IDs. |
| 3 | Forever: a rank the player does not know hides its reminder for every §12.3 row | VERIFIED | The nine calls match research §12.3 verbatim (gate checks 13-21; also compared by hand). Unknown ranks reach the watch list: `ns:CastRuleFamily` (Core.lua 1478) calls `ns:ResolveRankFamily`, whose first step `AddFamilyID(family, seen, spellID)` (Core.lua ~897) always includes the ID itself, so an unknown rank such as 10157 is never dropped. |
| 4 | Salvation 1038 / Light 19979 not offered; a placed one greyed "no longer offered"; internal note in Providers.lua | VERIFIED | Rows deleted (no `MetaReminderRow(1038`/`(19979`). Suggested iterates `META_REMINDER_DEFS` (Providers.lua 1373), so they are no longer offered. `ns:IsOrphanMetaReminder` (Core.lua 681) returns true when `MetaReminderDef(spellID) == nil`, giving `LOAD_REASON_ORPHAN` "no longer offered" (Core.lua 674); no deletion. Note at Providers.lua 1099-1104 names Salvation (1038; 25895), Light (19979; 25890) and Revoker. |
| 5 | Retail: every reminder unchanged, no alternative gained; all group calls in one `if ns.CLIENT_IS_FOREVER` block; `MetaReminderGroup` unchanged | VERIFIED | Single column-0 block at 1207-1249; `ns.CLIENT_IS_FOREVER` is false off Forever (Core.lua 844), so it is skipped. Only `MetaReminderGroup(465, 317920, 32223)` runs outside, as before. The removed ungated blessings call named only Forever rows (never registered on retail). Gate: `MetaReminderRow`/`MetaReminderGroup` bodies and every other row byte-identical to 5c0001e. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | Forever block (9 calls), 1038/19979 removed, header comment, removed-blessings note | VERIFIED | Diff vs 5c0001e touches only the reminder table (4 hunks, 1073-1249). Header no longer says group versions do not count; new paragraph records the 2026-11-09 reversal. |
| `80-check-groups.js` | Phase gate | VERIFIED | Ran in this process, exit 0. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Forever block | `metaReminderDefsBySpellID` | block sits after the last `MetaReminderRow` | WIRED | Gate check "block sits after every MetaReminderRow call"; read at 1199-1207. |
| `def.alternatives` | saved entry | `ns:ApplyMetaReminderDef` (Providers.lua 1358-1359) copies them at every rebuild | WIRED | No migration needed. |
| `entry.alternatives` | aura watch | `ns:RebuildReminderWatch` (Core.lua 1669-1688) appends each alternative's family | WIRED | |
| watch list | aura read | `ReadWatchedList` over `ns.reminderWatch[key]` (BuffEngine.lua 2004) -> `ns:ReadPlayerAura` -> `C_UnitAuras.GetPlayerAuraBySpellID` | WIRED | Secret-safe read; any present ID marks the reminder present. |
| `entry.alternatives` | cast start | `ns.alternativeKeysBySpell` (Core.lua 1561-1568) -> alternatives side of the cast path (Providers.lua 425-445) | WIRED | Skips keys this cast already started, so a row's own rank as alternative starts it once. |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Built-in reminder presence | `ns.reminderWatch[key]` | own rank family + `CastRuleFamily(altID)` for each alternative | Live `GetPlayerAuraBySpellID` reads | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase gate | `node .planning/phases/80-.../80-check-groups.js --exact` | 24 `ok`, "all checks passed", exit 0 | PASS |
| Formatting | `stylua --check .` | clean | PASS |
| Line endings | `git ls-files --eol Providers.lua` | `i/lf w/crlf attr/text eol=crlf` (gate: no CRCRLF) | PASS |
| Lua runtime | none available | no interpreter or game on this machine | SKIP (Phase 85) |

### Probe Execution

No probes declared for this phase; the gate script above is the phase's runnable check.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RALT-04 | 80-01 | Group calls Forever-only in one block; `MetaReminderGroup` unchanged | SATISFIED | Truth 5 |
| RALT-05 | 80-01 | Group buffs satisfy single-target reminders | SATISFIED | Truth 1 |
| RALT-06 | 80-01 | Greater Blessings join the blessings group | SATISFIED | Truth 2 |
| RALT-07 | 80-01 | Every rank satisfies its reminder (existing rows; Blood Pact extras excluded) | SATISFIED for the existing rows | Truth 3. New situational rows are Phase 82's. |
| MREM-06 | 80-01 | Salvation and Light retired with an internal note | SATISFIED | Truth 4 |

No orphaned requirements: REQUIREMENTS.md maps exactly these five IDs to Phase 80.

### Anti-Patterns Found

None. No TBD/FIXME/XXX in Providers.lua; no comments inside multi-line expressions in the block (gate check); no code outside the reminder table changed.

### Human Verification Required

Listed in frontmatter. All are in-game confirmations that belong to Phase 85 (VER-15) by the milestone's design, so they do not gate this phase.

### Gaps Summary

None. Every success criterion is met in code: the nine §12.3 calls are present verbatim inside one Forever-only block, unknown ranks and group buffs reach the aura watch list through unchanged existing code, Salvation and Light fall to the existing orphan path, and the retail path executes exactly the same group calls as before.

---

_Verified: 2026-11-09_
_Verifier: Claude (gsd-verifier)_
