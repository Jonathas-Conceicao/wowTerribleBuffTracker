---
phase: 64-retail-class-buff-reminder-suggestions
verified: 2026-09-30T00:00:00Z
status: human_needed
score: 8/8 must-haves verified in code
overrides_applied: 0
gaps: []
human_verification:
  - test: "Forever: open the Reminders tab Suggested section for each class"
    expected: "Offer unchanged from v0.5.0. No 6673, 465, 21562 or other retail rows appear; Arcane Intellect still offered; each paladin blessing casts its own buff on the player; Blood Pact has no click"
    why_human: "Client flavour and spellbook state only exist in game (Phase 66, Forever first)"
  - test: "Retail Mage: Suggested offer"
    expected: "Arcane Intellect offered; Arcane Familiar offered only with talent 205022 known; the two rows do not collide"
    why_human: "Needs the live spellbook and talent state"
  - test: "Retail, each class: Suggested offer"
    expected: "Each class offers only the rows it knows (Priest PW:Fortitude, Druid Mark of the Wild and Symbiotic Relationship, Warrior Battle Shout, Shaman Skyfury, Evoker Blessing of the Bronze and Source of Magic, Paladin Devotion Aura)"
    why_human: "Spell-known resolution is game state"
  - test: "Mark of the Wild ID 102046 (review IN-03)"
    expected: "Confirm with TBT's ID tooltip that 102046 is the castable retail spell (the published ID is 1126). If not, change the row BEFORE anyone places it, because the key metaReminder:<spellID> is saved. Recorded as a human check, not a gap: 102046 matches the user's own data verbatim"
    why_human: "Live game spell data outranks the source dump and the user's table"
  - test: "Placed Symbiotic Relationship / Blessing of the Bronze"
    expected: "Each hides when its own aura 474754 / 381748 is on the player, not the cast ID"
    why_human: "Aura reads in game"
  - test: "Placed Devotion Aura"
    expected: "Shows only while none of 465, 317920 (Concentration) or 32223 (Crusader) is up; no timer, no lead window"
    why_human: "Aura state in game"
  - test: "Arcane Familiar only placed, cast Arcane Intellect"
    expected: "Reminder hides once aura 210126 appears (a 1459 cast starts only the Arcane Intellect row); the passive talent 205022 is not in the watch list (review CR-01 fix: retail is not rank-covering)"
    why_human: "Whether the aura reads correctly can only be seen in game"
  - test: "Click Symbiotic Relationship / Source of Magic with a friendly target selected"
    expected: "The cast lands on that target. Every other reminder (including Arcane Familiar and Arcane Intellect) still casts on the player with a friendly target selected. No ADDON_ACTION_BLOCKED"
    why_human: "Secure click behaviour needs the game client"
  - test: "Retail, in combat: SPELLS_CHANGED during combat"
    expected: "No reminder is hidden or re-pointed mid-fight (review WR-01 fix keeps rank families off retail)"
    why_human: "Runtime event behaviour"
---

# Phase 64: Retail Class-Buff Reminder Suggestions Verification Report

**Phase Goal:** On retail, each class is offered the class-buff reminders it can cast, while Forever's offer and behaviour stay exactly as they were.
**Verified:** 2026-09-30
**Status:** human_needed (all code-level truths verified; in-game checks deferred to Phase 66 by design)
**Re-verification:** No, initial verification

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every row declares its client; an off-client row is never registered (one point) | VERIFIED | `MetaReminderRow(..., opts)` at Providers.lua:1556 computes `client = opts and opts.client or "forever"` and returns before registering unless both / forever-on-Forever / retail-on-retail. Unregistered rows are orphans through `ns:IsOrphanMetaReminder`. |
| 2 | The client check reads only `ns.CLIENT_IS_FOREVER`; no new interface comparison | VERIFIED | Providers.lua:1558 reads `ns.CLIENT_IS_FOREVER == true`. Grep finds no `buildInterfaceVersion` or `GetBuildInfo` in Providers.lua or ReminderClick.lua. Core.lua `buildInterfaceVersion` count is still 3. PROJECT.md:394 records the Key Decision. |
| 3 | Forever rows unchanged; Arcane Intellect tagged both | VERIFIED | `git diff d9c7faf` removes exactly one MetaReminderRow line (1459), now `{ client = "both" }`. The other 13 Forever rows and the blessings group line are byte-identical. |
| 4 | Retail rows, IDs and durations match the CONTEXT table | VERIFIED | Providers.lua:1618-1626. Arcane Familiar `(210126, 60, 205022, nil, 1459)`, key metaReminder:210126, distinct from 1459. PW:Fortitude 21562/60, Mark of the Wild 102046/60 (verbatim), Symbiotic 474750 with aura 474754/60, Battle Shout 6673/60, Skyfury 462854/60, Blessing of the Bronze 364342 with aura 381748/60, Source of Magic 369459/60, Devotion 465 with 0 minutes (duration nil, permanent). Order puts Mage first. |
| 5 | A per-row aura ID is applied to placed entries | VERIFIED | `ns:ApplyMetaReminderDef` writes `entry.auraID = def.auraID` on change only (Providers.lua:1725). No more forced nil. |
| 6 | Devotion Aura is satisfied by 317920 / 32223, with only Devotion as a row | VERIFIED | `MetaReminderGroup(465, 317920, 32223)` at Providers.lua:1630. No rows exist for those two IDs. |
| 7 | `ns:ReminderCastUnit` answers nil for the two ally rows and "player" otherwise; the overlay leaves unit unset for them | VERIFIED | Providers.lua:1684 returns nil only for a metaReminder whose def has `allyCast` (set on 474750 and 369459 only). ReminderClick.lua: CreateOverlay no longer writes `unit`; `Place(overlay, icon, castName, unit)` writes it when `overlay._unit ~= unit`; Flush passes `ns:ReminderCastUnit(entry)` (line 163). Flush's InCombatLockdown guard is kept. |
| 8 | Review fix state: `coverAllRanks` is forced only where `ns.CLIENT_HAS_SPELL_RANKS`; the Suggested offer has no blanket gate | VERIFIED | Providers.lua:1721-1724 `covers = ns.CLIENT_HAS_SPELL_RANKS == true or nil`. Core.lua:838 sets `CLIENT_HAS_SPELL_RANKS = isForeverBuild`, so Forever behaviour is unchanged. `MetaReminderSuggestionKeys` has no `CLIENT_IS_FOREVER` reference. The Arcane Familiar watch list on retail is its single aura 210126. |

**Score:** 8/8 verified in code.

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| MREM-04 | 64-01 | SATISFIED in code (in-game pending) | Arcane Intellect (both) and Arcane Familiar rows (talent 205022, aura 210126, casts 1459, 60 min) |
| MREM-05 | 64-01, 64-02 | SATISFIED in code (in-game pending) | The other seven retail rows, Devotion alternatives, per-client tag, ally-cast target |

No orphaned requirements: REQUIREMENTS.md maps only MREM-04 and MREM-05 to Phase 64, and both are claimed. The checkboxes and traceability rows are still "Pending"; the orchestrator updates them.

## Key Links

| From | To | Status |
|------|----|--------|
| MetaReminderRow | ns.CLIENT_IS_FOREVER | WIRED. Core.lua loads before Providers.lua. |
| ApplyMetaReminderDef | `entry.auraID = def.auraID` | WIRED |
| Flush | ns:ReminderCastUnit | WIRED, ReminderClick.lua:163 |
| CDMTab Suggested | ns:MetaReminderSuggestionKeys | WIRED; the per-row registration replaces the old gate |

## Anti-Patterns

No TBD, FIXME or XXX markers were introduced in the phase diff (the review contained none). `git ls-files --eol` shows w/crlf on Providers.lua, Core.lua, CDMTab.lua and ReminderClick.lua. The gates (stylua, aura-read, migrate-dryrun) were not re-run here; the SUMMARYs claim PASS.

## Accepted / Noted Items

- IN-02 (an unreadable build number registers retail rows): accepted by the review resolution, not a gap.
- IN-03 (Mark of the Wild 102046 vs the published 1126): recorded as a human check above.
- Update 2026-10-01 (Phase 65): the user's in-game check showed 102046 is a same-named spell no druid knows; the row became the druid's spell 1126 in `f2d4209` before anyone placed it. Lightning Shield (Shaman, 192106, 60 minutes, retail) was added after the review in `a793fe9`.

## Gaps Summary

None. Every must-have is verified against the final code, including the post-review state. The in-game checks above are the Phase 66 deferrals, so the status is `human_needed`.

_Verified: 2026-09-30_
_Verifier: Claude (gsd-verifier)_
