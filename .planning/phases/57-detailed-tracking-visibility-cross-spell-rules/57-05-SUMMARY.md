---
phase: 57-detailed-tracking-visibility-cross-spell-rules
plan: 05
subsystem: buff-engine
tags: [wow-addon, lua, node, cdm-tab, visibility, cross-spell-rules, static-analysis, deploy]

# Dependency graph
requires:
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 01
    provides: "ns.endKeysBySpell, ns:RebuildDetailedRuleIndex, ns:ApplyEndOnCast, the cross-spell cast-path side effect this plan's gate confirms still holds"
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 02
    provides: "ns.auraState/ns.visibilityKeys/ns.visibilityAuraID, ns:VisibilityGate/ns:VisibilityShowsIn, ns:RefreshAuraStates, ns:FillUserBuffProc, the aura-driven start this plan's gate confirms still holds"
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 03
    provides: "the four Display.lua VisibilityGate/VisibilityShowsIn call sites this plan's gate confirms still holds"
  - phase: 57-detailed-tracking-visibility-cross-spell-rules
    plan: 04
    provides: "the visibility selector and endOnCast dialog fields, TRACKER_FIELDS order, the CreateAddDialog hash this plan's gate confirms still holds"
provides:
  - "whole-phase gate closure: every plan's own gate re-run on the final tree in one pass (selftests, aura-read gate, CreateAddDialog hash, exact five-file diff scope, a caller for every new ns helper, allocation-free cast/render paths, no OnUpdate added, TRACKER_FIELDS order, stylua, CRLF)"
  - "performance and cleanup review of the phase's full diff since 0459903"
  - "a build deployed to every WoW client folder present"
  - "an ordered 15-item in-game checklist (retail AND Forever) covering DTRK-03 and DTRK-05"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Whole-phase gate re-runs every plan's own verify assertions against the final tree in one pass rather than trusting each plan's individually-passing gate to still hold after later plans land"

key-files:
  created: []
  modified: []

key-decisions:
  - "No fix commit needed -- every whole-phase gate assertion passed on the first run against the tree left by 57-01..04, so this plan's only artifact is its own SUMMARY.md"

patterns-established: []

requirements-completed: [DTRK-03, DTRK-05]

# Metrics
duration: ~25min
completed: 2026-09-28
---

# Phase 57 Plan 05: Whole-Phase Gates, Review, Deploy & Checklist Summary

**Every whole-phase gate (selftests, aura-read gate, byte-identical CreateAddDialog, exact five-file diff scope, ten-helper caller proof, allocation-free cast/render paths, TRACKER_FIELDS order) passed on the first run against the tree 57-01..04 left, so this plan found no defect to fix; it records the CLAUDE.md performance/cleanup review, deploys to all four local WoW client folders, and writes the 15-item retail+Forever in-game checklist for DTRK-03 and DTRK-05.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-28
- **Tasks:** 2 completed
- **Files modified:** 1 (this SUMMARY only; no source fix required)

## Accomplishments

- Ran the full whole-phase automated gate from 57-05-PLAN.md Task 1 against the tree at `HEAD` (base `0459903`): `node scripts/migrate-dryrun.js --selftest` (7/7), `node scripts/aura-read-gate.js` (`AURA-READ GATE PASS`), `node scripts/aura-read-gate.js --selftest` (`AURA-READ SELFTEST PASS (30 cases)`) -- all green on the first attempt.
- `CreateAddDialog`'s body hash confirmed unchanged: `64e38633612791cb7e1ea41902b75ae45c18167b`.
- Non-planning diff vs `0459903` is exactly `BuffEngine.lua CDMTab.lua Core.lua Display.lua Providers.lua` -- nothing else touched by the phase.
- All ten new `ns` helpers (`RebuildDetailedRuleIndex`, `ApplyEndOnCast`, `RefreshAuraStates`, `VisibilityGate`, `VisibilityShowsIn`, `ReadableAuraTiming`, `StartUserBuffFromAura`, `FillUserBuffProc`, `SyncVisibilityChecks`, `ParseSpellIDList`) have at least one non-comment caller outside their own definition (call counts: 1, 1, 5, 6, 2, 2, 1, 2, 6, 3).
- `UserSpellProviderMixin:OnTrigger` and the six BuffEngine.lua hot-path helpers (`ApplyEndOnCast`, `RefreshAuraStates`, `VisibilityGate`, `VisibilityShowsIn`, `ReadableAuraTiming`, `StartUserBuffFromAura`) each contain zero `{` (no table literal) between their `function` and `end` lines -- the cast, render and refresh paths stay allocation-free.
- Zero `OnUpdate` added anywhere in the phase's Lua diff.
- `TRACKER_FIELDS` order proven: `spellPreview < spellID < secrecyBadge < duration < detailed < auraID < keepOnAuraLoss < visibility < endOnCast`.
- `stylua --check` clean on `BuffEngine.lua CDMTab.lua Core.lua Display.lua Providers.lua`; CRLF gates pass on all five (`git ls-files --eol` reports `w/crlf`, no `\r\r\n` and no bare `\n` in any).
- `./scripts/install.bat` deployed to all 4 WoW client folders present on this machine (retail, PTR, beta, classic_beta). No drift beyond the committed files afterward (`.gitignore`'s pre-existing user edit untouched, never staged).

## Task Commits

This plan's work produced no source-code changes (every gate passed against the tree left by 57-01..04; no defect was found to fix), so there is a single commit for both tasks' combined output:

1. **Tasks 1+2: Whole-phase gates, performance/cleanup review, deploy, in-game checklist** - (this SUMMARY's own commit; no code change)

_Plan metadata commit intentionally NOT made by this executor -- the orchestrator owns STATE.md/ROADMAP.md per its instructions._

## Files Created/Modified

- `.planning/phases/57-detailed-tracking-visibility-cross-spell-rules/57-05-SUMMARY.md` - this document (gate results, review, deploy output, checklist)

## Decisions Made

- Combined both tasks into one commit since neither required a source-code edit: the plan's own acceptance criteria only require a fix commit "if the review finds a defect," and this review found none. Splitting an empty Task 1 commit from a Task 2 commit would create a commit with no diff.

## Performance and Cleanup Review

Reviewed `git diff 0459903 -- BuffEngine.lua CDMTab.lua Core.lua Display.lua Providers.lua` (the whole phase's diff across five files) per CLAUDE.md's post-commit standing instruction, plus 57-01..04's own SUMMARY.md deviation/decision notes:

**(a) Cast path -- `UserSpellProviderMixin:OnTrigger`, Providers.lua:139-247:** the cross-spell side effect (Providers.lua:201-210) is one `ns.endKeysBySpell[spellID]` lookup; on a miss `endKeys` is `nil` and the `if endKeys then` block is skipped entirely, costing one failed table lookup. On a hit, the skip-rule lookups (`ns.buffKeyBySpell[spellID]`, `ns.rankIndex[spellID]`) are the same two lookups the buff side already makes below, then `ns:ApplyEndOnCast` (BuffEngine.lua:1187) walks `endKeys` with `for i = 1, #endKeys do` -- a numeric loop, zero `pairs`/`ipairs`, zero `{`. The cast-evidence write (Providers.lua:243-245, `if ns.visibilityAuraID[ownerKey] then ns.auraState[ownerKey] = true end`) is a single table write gated on a single table read. `ns:FillUserBuffProc` (Providers.lua:89-136) was verified byte-for-byte behaviour-identical to the pre-phase inline block: `git show 0459903:Providers.lua` (its old lines 165-211) contains the exact same `aliveBuffs`/`proc.*` assignment sequence, now shared by the cast path and Plan 02's aura-driven start. Zero table constructors in either `OnTrigger` or `FillUserBuffProc` (gate-verified: 0 `{` in `OnTrigger`; `FillUserBuffProc` was included in the same brace-free confirmation since it produces `proc` via the pre-existing pooled `ns:AcquireProc`, never a literal).

**(b) UNIT_AURA path -- `ns:RefreshAuraStates`, BuffEngine.lua:1448-1525:** the one-length-check early-out is line 1450 (`if #keys == 0 then return end`), before any other work. The combat and secret early-outs (`InCombatLockdown()` line 1455, `C_Secrets.ShouldAurasBeSecret()` line 1458) both run before any aura read. Every read goes through `ns:ReadPlayerAura` (lines 1478, 1491) -- no other aura API is named in the function. The redraw at the end (lines 1522-1524) is gated on the single `changed` boolean, set only when a cached state actually flipped (line 1503) or the aura-driven start fired (line 1518) -- never unconditionally. Zero `{` in the function body. The aura-driven start (lines 1506-1519) is the documented hybrid: `previous ~= true or ns:ReadableAuraTiming(seenAura, now) ~= nil` -- fires on the edge to present (typed duration, via `ns:FillUserBuffProc`'s `proc.duration = entry.duration` default) OR whenever the aura's own timing is readable (which re-arms the exact expiration every refresh). `ns:StartUserBuffFromAura` (BuffEngine.lua:1426-1443) itself re-checks `InCombatLockdown()` at line 1427, so the guard exists twice on the path (the caller's early-out plus the callee's own), and the comment at lines 1434-1436 states why it cannot restart-loop: once `expirationTime` passes, `ns:ReadableAuraTiming`'s `expirationTime > now` test (BuffEngine.lua:1418) fails and the branch stops re-arming on its own -- confirmed by inspection, no timer or OnUpdate drives it.

**(c) Render path -- Display.lua:** exactly one `ns:VisibilityGate` call per slot at each of the four call sites: `SlotDraws` (line 94), the icon per-slot chain (line 2015 in `RenderIconContainer`'s branch walk, line 2363 in the placeholder-condition branch), and the bar path's `showPlaceholders`/timers-only loops (line 2027). `ns:VisibilityShowsIn` appears exactly twice, both in container-activity checks (`hasActiveTimers` line 1982, `hasActiveIcons` line 2304). The reminder-append loop (lines 2038-2047) walks only `ns.visibilityKeys` (line 2038), never `pairs(ns.db.trackedBuffs)`. `git diff 0459903 -- Display.lua` introduces zero new `{` (gate-verified against the whole five-file set). "Always" is confirmed a no-op path: `SlotDraws` line 98's `if gate == true then return true end` never fires for an always-mode entry because `ns:VisibilityGate` (BuffEngine.lua:1365-1367) returns `nil` the instant `entry.detailed` or `entry.visibility` isn't `"present"`/`"absent"`, and a `nil` gate falls through Display.lua's unchanged pre-phase return expression at every one of the four sites.

**(d) Rebuild -- `ns:RebuildDetailedRuleIndex`, Core.lua:957-1049:** allocates fresh `byTrigger`/`keys`/`auraIDs` tables per rebuild (line 962, 966-967) -- allowed, rebuild-time only. `ns.auraState` is invalidated only for keys whose watched ID actually changed, checked in both directions (lines 1037-1046) before the new watch tables publish (lines 1047-1048). Trigger-expansion cost, per flavour, confirmed by reading the branch directly:
  - **Retail** (`not ns.CLIENT_HAS_SPELL_RANKS`, Core.lua:994-1005): runs exactly two guarded lookups per trigger ID (`RelatedSpellID(C_Spell and C_Spell.GetBaseSpell, triggerID)` line 998, `RelatedSpellID(C_Spell and C_Spell.GetOverrideSpell, triggerID)` line 1002) and zero spellbook scans per rebuild. `ns:ResolveRankFamily` is textually unreachable on this branch -- it is called only inside the `if ns.CLIENT_HAS_SPELL_RANKS then` arm (line 991), and the retail `else` arm (lines 994-1005) never names it.
  - **Forever** (`ns.CLIENT_HAS_SPELL_RANKS`, Core.lua:986-993): checks `ns.endRuleFamilies[triggerID]` first (line 989); a warm cache answers with zero scans. `ns:ResolveRankFamily` (line 991) runs only on a cache miss, once per distinct trigger ID, then the result is cached (line 992) -- bounded by `MAX_CAST_RULE_IDS = 8` (CDMTab.lua), the dialog's per-tracker cap on `entry.endOnCast`.
  - The wipe points that force that one-scan-per-ID cost are `PLAYER_ENTERING_WORLD` (Core.lua:1316, unconditional `wipe(ns.endRuleFamilies)`) and the out-of-combat branch of `SPELLS_CHANGED` (Core.lua:1415-1417, `if not InCombatLockdown() then wipe(ns.endRuleFamilies) end`). An **in-combat** `SPELLS_CHANGED` rebuild takes neither wipe, so every trigger ID already cached from before combat answers from `ns.endRuleFamilies` with zero scans, exactly matching the plan's requirement.

**(e) Dead code / duplication introduced by this phase:** the two-line "base/override `RelatedSpellID` lookup" pattern (Core.lua:998-1005, retail's cross-spell trigger expansion) duplicates the same two lookups that already exist inside `ns:ResolveRankFamily`'s own seed step (Core.lua:734, 738) and scan step (Core.lua:826, 830) -- three near-identical instances of `RelatedSpellID(C_Spell and C_Spell.GetBaseSpell, id)` / `GetOverrideSpell` now exist in Core.lua, two pre-existing (Phase 56) and one added by this phase. This is a genuine unification candidate (a small `ExpandBaseOverride(id)` local helper both call sites could share), but per PROJECT.md's "No refactors during cleanup phases" decision and this phase's own deviation rules, it is listed here for the milestone's cleanup phase rather than refactored now -- the retail branch deliberately avoids calling `ns:ResolveRankFamily` itself (that function may scan the spellbook on some paths), so unifying it needs a shared leaf helper, not a shared caller. No other duplication or dead code was found: all ten new `ns` helpers are called (gate-verified above), and none of the four Display.lua `VisibilityGate` call sites duplicate logic -- each is the single local `gate` read the plan's established pattern requires at that site.

**(f) Known behaviour to record:** see "## Known behaviour" below.

No hot-path allocation, redundant per-frame work, or dead code was found to fix. Nothing was fixed under Rules 1-3; PROJECT.md's "No refactors during cleanup phases" decision leaves pre-existing code (everything outside this phase's own diff) untouched.

## Known behaviour

- **The skip rule (Plan 01):** `ns:ApplyEndOnCast` never ends the key the same cast is about to (re)start -- `startingCdKey`/`startingBuffKey` are the same two lookups the buff/cooldown sides already make, so if B also starts A, A is skipped rather than ended-then-restarted or left half-reset (BuffEngine.lua:1177-1180, 1196).
- **The double-redraw case (Plan 01):** a single cast that both ends one detailed tracker (via the cross-spell rule) and starts another (its own buff/cooldown) calls `ns:UpdateDisplay()`/`ns:MarkCooldownsDirty()` once for each side -- two redraws instead of one. Documented as rare and intentionally not special-cased (BuffEngine.lua:1182-1186).
- **Cast evidence writes the cache (Plan 02):** the tracker's own cast is treated as proof its aura went up -- `OnTrigger` writes `ns.auraState[ownerKey] = true` for any visibility-gated key, even before the next `UNIT_AURA`/`RefreshAuraStates` cycle confirms it (Providers.lua:240-245).
- **A cross-spell end marks absence unconditionally (Plan 02):** "aura A clears when you cast B" marks every visibility-gated buff the rule lists absent whether or not its timer was actually running -- an aura cast by someone else, or one that already expired on its own, is still gone the instant B is cast (BuffEngine.lua:1204-1213). By contrast, an aura that merely drops on its own in combat does **not** get this treatment: `ns:RefreshAuraStates`'s combat early-out (BuffEngine.lua:1455-1457) means the cached state simply holds until combat ends and a real read is possible again (DTRK-06).
- **The hybrid aura start (Plan 02):** a "present" tracker's timer starts from an aura sighting on the edge to present (typed duration) OR whenever the aura's own timing is freshly readable (which re-arms to the exact expiration every refresh, including after a sighting has already started the tracker once) -- BuffEngine.lua:1506-1519.
- **"Expired but aura still up" (Plan 02):** when `ns:StartUserBuffFromAura`'s typed-duration proc expires but the aura is still readably present, the next `ns:RefreshAuraStates` pass finds `ns.activeTimers[key] == nil` again and `ns:ReadableAuraTiming` readable, so it restarts to the aura's *real* remaining expiration (not another typed-duration guess) rather than staying stuck on the old countdown. If the timing is not readable at that moment, `ns:VisibilityGate` still reports `present == true`, so Display draws the idle "present" icon rather than a stale sweep, until the next readable moment restarts the timer for real.
- **Edit applies from the next rebuild, which is immediate (Plan 01/04):** a rule (`entry.endOnCast`, `entry.visibility`) edited on a running tracker takes effect from the dialog's own Save, because Save calls `ns:RebuildCastIndex()` (CDMTab.lua:224), which calls `ns:RebuildDetailedRuleIndex()` (Core.lua:946) as its last statement -- there is no separate "next cast" delay the way a running proc's *duration* has (that precedent, from Phase 54's IN-02, does not apply to the cross-spell/visibility rules themselves, only to a proc already in flight retaining whatever `aliveBuffs`/duration it started with).

## Deviations from Plan

None - every whole-phase gate assertion in both tasks passed on the first run against the tree left by 57-01..04. No fix commit was needed.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Deploy Output

```
Deploying 11 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua, BuffEngine.lua, Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua, Display.lua, CDMTab.xml, CDMTab.lua, tbt_icon_64x64.blp
Deployed version: v0.4.1-105-geff01ef-dirty-dev
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
Done! /reload in WoW to load the addon.
```

`git status --porcelain -- '*.lua' '*.xml' '*.toc'` was empty after deploy -- no drift beyond the already-committed source. The pre-existing working-tree edit to `.gitignore` was never staged or touched by this plan.

## In-game checklist

Run on retail AND Forever with `/console scriptErrors 1`. The build above is already deployed to every WoW client folder found on this machine. No TOC change this phase, so `/reload` loads the code for every item below except the one marked **logout**, which needs a REAL logout/login, never `/reload`.

1. Cooldowns tab dialog: "Detailed tracking" appears; checked, it shows the aura ID, "Show this tracker:" (Always checked) and "Resets when you cast:", and no "End when the aura is lost". Buffs tab: the same plus "End when the aura is lost", and the box reads "Ends when you cast:".
2. Cast-rule box: type two known IDs -- two icons; add `999999999` -- a red question mark; type `12,,3` or letters -- Save disabled with "Use spell IDs separated by commas"; nine IDs -- "At most 8 spell IDs"; the tracker's own spell ID -- "Remove this tracker's own spell ID".
3. "Always" unchanged: an existing tracker and a new detailed one left on Always behave exactly as before in a container with "hide when inactive" on and off.
4. "Only while the aura is up" (buff, icon container with hide-when-inactive on): hidden while the aura is missing; cast it -- the timer shows; click the aura off out of combat -- it hides.
5. "Present" from another player: out of combat, have a party member cast a buff you track in "present" mode (for example Arcane Intellect / Power Word: Fortitude / Mark of the Wild) with no timer running -- the tracker starts from the sighting; its sweep matches the aura's real remaining time when readable, otherwise the typed duration.
6. "Only while the aura is missing" (buff): while the aura is missing a full-colour icon with no sweep and no timer shows, even with hide-when-inactive on; cast the buff -- the reminder disappears at once (also in combat); on a bar container the reminder is the idle bar.
7. Frozen in combat (DTRK-06): with an "absent" tracker hidden (aura up), enter combat and let the aura drop or click it off -- the reminder does NOT appear until combat ends, then appears; the same freeze for a "present" tracker whose aura drops in combat. In an M+ key or with a Contextual-secret aura, the state never flips while unreadable.
8. Cooldown visibility: a detailed cooldown tracker in "present" / "absent" mode draws its cooldown slot only while the condition holds; "Always" still always shows it.
9. Cross-spell end (DTRK-05): buff A with "Ends when you cast:" B -- cast A, then B -- A's timer ends at once; repeat in combat, and (retail) in an M+ key.
10. Cross-spell reset: cooldown A with "Resets when you cast:" B -- cast A (cooldown runs), cast B -- A shows ready at once; in combat too.
11. Ranks/overrides: Forever -- list rank 1 of B and cast a higher rank of B (or the reverse): the rule fires; retail -- list a spell with a talent override and cast the overridden version: the rule fires.
12. Skip rule (Forever only): on buff tracker A with "Cover all ranks" ON, list a different RANK of A's own spell in "Ends when you cast:" (the exact own ID is rejected by the dialog) -- casting that rank restarts A rather than ending it, because with "Cover all ranks" the rank resolves to A's own key and the skip rule applies. Then turn "Cover all ranks" OFF and Save, cast A's own spell so its timer runs, and cast that rank: the rank no longer starts A, so it is not skipped -- the cast ENDS A (A's timer disappears at once).
13. Edit prefill: Edit a tracker with a mode and a rule -- the mode box and the ID text reappear as saved; uncheck Detailed and Save -- it behaves as simple (Always, no rule fires); Edit again and re-check Detailed -- the old mode and rule are still there (WR-02).
14. **logout** Persistence: after a real logout/login (never /reload), items 4, 6, 9 and 10's settings are still set and behave the same; at login with the aura already up, a "present" tracker starts from it and an "absent" one stays hidden.
15. No Lua error across all items on both flavours.

## Next Phase Readiness

- Phase 57 is code-complete, gated end to end, reviewed, and deployed. DTRK-03 and DTRK-05 both have their implementation gated; the 15-item checklist above is the human's remaining action before the phase can be marked verified.
- The duplication candidate noted in "(e)" above (the base/override `RelatedSpellID` lookup, now three near-identical instances in Core.lua) is a specific, scoped target for the milestone's cleanup phase, per CLAUDE.md's GSD Workflow rule to unify behaviour a milestone itself introduced.
- No blockers.

## Self-Check: PASSED

- FOUND: `.planning/phases/57-detailed-tracking-visibility-cross-spell-rules/57-05-SUMMARY.md`
- All gate commands re-run above against the live tree (not asserted from memory): `migrate-dryrun.js --selftest`, `aura-read-gate.js`, `aura-read-gate.js --selftest`, the `CreateAddDialog` hash, the byte-identical-scope check, the ten per-helper caller counts, the `OnTrigger`/hot-path `{` counts, the `OnUpdate` grep, the `TRACKER_FIELDS` order awk, `stylua --check`, the CRLF/CRCRLF checks, and `install.bat`'s own output -- all passed/matched as recorded above.

---
*Phase: 57-detailed-tracking-visibility-cross-spell-rules*
*Completed: 2026-09-28*
