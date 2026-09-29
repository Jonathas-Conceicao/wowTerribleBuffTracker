---
phase: 57-detailed-tracking-visibility-cross-spell-rules
verified: 2026-09-28T00:00:00Z
status: human_needed
score: 4/4 roadmap success criteria verified statically (plus 24/24 plan must-haves); in-game confirmation pending
overrides_applied: 0
human_verification:
  - test: "Cooldowns tab Add/Edit: tick Detailed tracking. Then the same on the Buffs tab."
    expected: "Cooldowns: aura ID, 'Show this tracker:' (Always ticked), 'Resets when you cast:', and NO 'End when the aura is lost'. Buffs: the same plus 'End when the aura is lost', and the box reads 'Ends when you cast:'."
    why_human: "Dialog layout and labels are only observable in the client"
  - test: "Cast-rule box: two known IDs; then add 999999999; then '12,,3' or letters; then nine IDs; then the tracker's own spell ID"
    expected: "Two icons; a red-tinted question-mark icon for the unknown ID; Save disabled with 'Use spell IDs separated by commas'; 'At most 8 spell IDs'; 'Remove this tracker's own spell ID'"
    why_human: "Icon preview and Save-button state are UI behaviour"
  - test: "'Always' regression: an existing tracker and a new detailed tracker left on Always, in a container with hide-when-inactive on and off"
    expected: "Identical to pre-phase behaviour (VisibilityGate returns nil, every Display site falls through to its old expression)"
    why_human: "Render outcome needs the client"
  - test: "'Only while the aura is up' buff in an icon container with hide-when-inactive ON: aura missing, then cast it, then click it off out of combat"
    expected: "Hidden while missing; timer shows on cast; hides when clicked off"
    why_human: "Needs live UNIT_AURA and render"
  - test: "'Present' mode, aura cast by another player out of combat with no timer running (e.g. Arcane Intellect / Fortitude / Mark of the Wild)"
    expected: "Tracker starts from the sighting; sweep matches the aura's real remaining time when readable, otherwise the typed duration"
    why_human: "Requires a second player and a live aura"
  - test: "'Only while the aura is missing' buff, icon container with hide-when-inactive ON; then cast the buff (also in combat); then the same tracker in a bar container"
    expected: "Full-colour icon, no sweep, no number, while missing; disappears at once on cast, in combat too; on a bar container the reminder is the idle placeholder bar"
    why_human: "Visual look (full colour, no sweep) and hide-when-inactive bypass"
  - test: "Frozen in combat (DTRK-06): 'absent' tracker hidden (aura up), enter combat, let the aura drop / click it off; leave combat. Repeat for a 'present' tracker. Repeat in an M+ key or with a secret aura"
    expected: "Reminder does NOT appear until combat ends, then appears; 'present' tracker holds its shown state until combat ends; nothing flips while the aura is unreadable"
    why_human: "Combat lockdown and secret-aura restrictions exist only in the client"
  - test: "Detailed cooldown tracker in 'present' then 'absent' mode, with and without its aura up"
    expected: "Cooldown slot draws only while the condition holds; 'Always' still always shows it"
    why_human: "Render outcome"
  - test: "Cross-spell end (DTRK-05): buff A with 'Ends when you cast: B'. Cast A then B, out of combat, in combat, and (retail) in an M+ key"
    expected: "A's timer ends immediately every time"
    why_human: "Needs real UNIT_SPELLCAST_SUCCEEDED in combat and M+"
  - test: "Cross-spell reset: cooldown A with 'Resets when you cast: B'. Cast A, then B (also in combat)"
    expected: "A shows ready at once"
    why_human: "Needs live casts"
  - test: "Ranks/overrides: Forever -- list rank 1 of B and cast a higher rank (or reverse). Retail -- list a spell with a talent override and cast the overridden version"
    expected: "The rule fires in both cases"
    why_human: "Rank families and overrides come from the live spellbook"
  - test: "Skip rule (Forever): buff A with Cover all ranks ON listing another rank of A; cast that rank. Then Cover all ranks OFF, Save, cast A, then cast that rank"
    expected: "First case restarts A (skip rule); second case ends A at once"
    why_human: "Forever spellbook"
  - test: "Cross-spell end on a 'present' tracker whose aura is in fact still up (e.g. B does not really remove A), out of combat"
    expected: "Record what happens: the tracker hides on B, and the next UNIT_AURA out of combat re-reads the aura as up and restarts it. Confirm this is acceptable (it only occurs when the rule does not match the game)"
    why_human: "Depends on real event ordering between the cast and the aura removal"
  - test: "Edit prefill and WR-02: Edit a tracker with a mode and a rule; uncheck Detailed and Save; Edit again and re-check Detailed"
    expected: "Mode and IDs reappear as saved; while simple it behaves as Always with no rule firing; re-checking restores the old mode and rule"
    why_human: "Dialog round trip"
  - test: "Persistence: after a REAL logout/login (not /reload), check the settings of the trackers above; also log in with the aura already up"
    expected: "Modes and rules still set and behave the same; at login a 'present' tracker starts from the aura and an 'absent' one stays hidden"
    why_human: "SavedVariables are written only on logout"
  - test: "All of the above on retail AND on Forever with /console scriptErrors 1"
    expected: "No Lua error"
    why_human: "No Lua runtime or WoW client available to the verifier"
---

# Phase 57: Detailed Tracking — Visibility & Cross-Spell Rules Verification Report

**Phase Goal:** A detailed tracker can be shown always / only while its aura is present / only while it is absent, and other spells' casts can end it (buffs) or reset it (cooldowns), in combat too.
**Verified:** 2026-09-28
**Status:** human_needed
**Re-verification:** No, initial verification

Every link from the dialog to the saved entry, the rebuild-time indexes, the cast path, the aura-state cache and the four Display sites was traced in the source (not in the SUMMARYs). No defect that blocks the goal was found. There is no WoW client or Lua runtime here, so behaviour is proven only by static tracing. The in-game checklist is still needed.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | "Show always" (default) draws as today; "only while present" shows only while the aura is on the player; "only while absent" shows only while it is missing | VERIFIED (static) | `ns:VisibilityGate` (BuffEngine.lua:1361-1383) returns nil unless the entry is detailed, is USER_BUFF/USER_CD and has visibility "present"/"absent", and also returns nil for an unknown state. A nil gate falls through unchanged at every site. Consumed at SlotDraws (Display.lua:94-100), the icon chain hide branch (:2438), the placeholder branch `gate == true` (:2533), the bar placeholder filter (:2015-2016), the bar timers filter (:2027-2028), the bar reminder append (:2038-2050) and container activity through `ns:VisibilityShowsIn` (:1982, :2304). This is how an "absent" reminder bypasses hideWhenInactive. The cooldown slot is gated too, because the `gate == false` branch sits ahead of `IsCooldownSlotEntry` (:2438 before :2502) |
| 2 | While the aura cannot be read (combat, M+, secret), a visibility-driven tracker holds its last known state | VERIFIED (static) | `ns:RefreshAuraStates` (BuffEngine.lua:1448-1525) returns early on `InCombatLockdown()` (:1455) and on `C_Secrets.ShouldAurasBeSecret()` (:1458). It writes state only when `present ~= nil` (:1501), and an unreadable `ns:ReadPlayerAura` leaves `present` nil (:1479-1497). OnUnitAura calls it only after the secret gate and the isFullUpdate suppression (:1539-1564). It thaws at PLAYER_REGEN_ENABLED (Core.lua:1383). A SPELLS_CHANGED rebuild in combat keeps the cache, which is cleared only per key when the watched ID changes (Core.lua:1037-1046) |
| 3 | A detailed tracker listing B ends when B is cast, in and out of combat and in M+; a rank or override of B also ends it | VERIFIED (static) | Index: `ns:RebuildDetailedRuleIndex` (Core.lua:957-1049) indexes only `entry.detailed` USER_BUFF/USER_CD entries. It expands each trigger through base+override on retail (:997-1005) and through `ns:ResolveRankFamily` on Forever, cached in `ns.endRuleFamilies` (:986-993). The cache is wiped at PLAYER_ENTERING_WORLD (:1316) and on SPELLS_CHANGED out of combat (:1415-1417). ResolveRankFamily always includes the trigger itself (Core.lua:730). Cast path: `UserSpellProviderMixin:OnTrigger` (Providers.lua:201-210) does one lookup, then `ns:ApplyEndOnCast` (BuffEngine.lua:1187-1231), which clears activeTimers for buffs and cooldownStarts/cooldownOverrides plus MarkCooldownsDirty for cooldowns, and calls UpdateDisplay itself. Nothing on the path checks combat or reads an aura. Its only input is the cast's spellID, and dispatch (BuffEngine.lua:524-528, Providers.lua:2327) is ungated |
| 4 | Both options are editable from the edit dialog and survive logout/login | VERIFIED (static); persistence needs human | CDMTab.lua TRACKER_FIELDS `visibility` (:2041-2127) and `endOnCast` (:2129-2225) are shown under the detailed master on both tabs (`DetailedModeOffered` includes USER_CD, :1356-1358). The Save handler reads only shown fields (:2449-2459) and passes them to `ns:AddTrackedBuff` (field copy, BuffEngine.lua:920-926) or to `ns:UpdateTrackedBuff` (readKeys copy, :1087-1095). Neither key is in ENGINE_OWNED (:837-847). The values land on `ns.db.trackedBuffs[key]`, which lives in SavedVariables `TerribleBuffTrackerDB`. `ParseSpellIDList` returns a fresh array, and prefill joins a copy into the text box (:2169) |

**Score:** 4/4 roadmap truths verified statically. All 24 plan-frontmatter truths across 57-01 to 57-05 were also checked and hold (details below).

### Plan must-haves (merged)

| Plan | Truth | Status | Evidence |
|------|-------|--------|----------|
| 01 | Buff with endOnCast B loses its timer on B, in/out of combat | VERIFIED | BuffEngine.lua:1199-1203 |
| 01 | Cooldown with endOnCast B resets (starts + overrides cleared, dirty) | VERIFIED | BuffEngine.lua:1214-1219, 1225-1227 |
| 01 | Rank/override expansion (retail base/override only; Forever cached ResolveRankFamily) | VERIFIED | Core.lua:986-1006, 1316, 1415-1417 |
| 01 | Never ends a key the same cast starts | VERIFIED | Providers.lua:205-209, BuffEngine.lua:1196 |
| 01 | Simple tracker never indexed | VERIFIED | Core.lua:978-981 (`entry.detailed` gate); ApplyEndOnCast also rechecks `e.detailed` (:1198) |
| 01 | Cast path allocation-free | VERIFIED | Providers.lua:201-210 has one lookup, and ApplyEndOnCast is a numeric loop with no `{` |
| 02 | Cached state refreshed on UNIT_AURA, REGEN_ENABLED, world entry, after rebuild; never per frame | VERIFIED | BuffEngine.lua:1564; Core.lua:1383, 1359, 1100, 1170. No Display.lua call to RefreshAuraStates |
| 02 | Unreadable never changes state; unknown = always | VERIFIED | BuffEngine.lua:1455-1460, 1501; VisibilityGate :1375-1378 |
| 02 | Cover-all-ranks + aura ID watches detailedRankFamilies: any present means present, absent only if all are readable and absent | VERIFIED | BuffEngine.lua:1474-1489; Core.lua:1138-1147 |
| 02 | "Present" aura-driven start out of combat, including another player's aura | VERIFIED (static) | BuffEngine.lua:1509-1519 and StartUserBuffFromAura :1426-1443 (double InCombatLockdown guard). Reads use GetPlayerAuraBySpellID, which does not filter by caster |
| 02 | Own cast marks present; cross-spell rule marks listed gated buffs absent | VERIFIED | Providers.lua:243-245; BuffEngine.lua:1210-1213 |
| 02 | VisibilityGate is the one allocation-free predicate | VERIFIED | BuffEngine.lua:1361-1383 |
| 03 | Always is a no-op | VERIFIED | nil gate falls through at every site |
| 03 | Present hides while missing, shows while up | VERIFIED | see truth 1 |
| 03 | Absent reminder: full colour, no sweep, bypasses hideWhenInactive; idle bar on bar containers | VERIFIED (static) | Placeholder branch: `ClearIconDesaturation` (:2608), `cooldown:Clear()` (:2611-2614); VisibilityShowsIn keeps the container shown; bar append :2038-2050 |
| 03 | Cooldown with a mode draws only while the condition holds | VERIFIED | Display.lua:2438 precedes the cooldown branch; SlotDraws :95-97 |
| 03 | Edit Mode / open settings still show every tracker | VERIFIED | `ns.configOpen or iconEditing/barEditing` escape at :95, :2016, :2438 |
| 03 | Render path allocation-free | VERIFIED | No new `{` in the Display.lua diff; the reminder loop walks only `ns.visibilityKeys` |
| 04 | Cooldowns tab offers Detailed + aura ID + visibility + "Resets when you cast:", no keepOnAuraLoss | VERIFIED | CDMTab.lua:1356-1358, 2037-2039, 2161/2166 |
| 04 | Buffs tab visibility selector (Always default) + "Ends when you cast:" | VERIFIED | CDMTab.lua:2041-2127 |
| 04 | Parser: preview icons, unknown marked, rejects malformed / out of range / >8 / own ID | VERIFIED | CDMTab.lua:1380-1410, 2174-2221 |
| 04 | Saved on entry, prefilled from a copy, persisted | VERIFIED (static) | see truth 4 |
| 04 | Switching to simple keeps the hidden values; runtime ignores them | VERIFIED | Hidden fields are not read (:2455), so they are not written (BuffEngine.lua:1087-1095). Runtime gates: Core.lua:970/979, BuffEngine.lua:1365 |
| 05 | Whole-phase gates, review, deploy, checklist | VERIFIED | Gates re-run by the verifier (below); checklist present in 57-05-SUMMARY.md |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | ns.endKeysBySpell, ns.endRuleFamilies, ns.auraState, ns.visibilityKeys, ns.visibilityAuraID, `ns:RebuildDetailedRuleIndex` | VERIFIED | Declared at :880-902, defined at :957, called from RebuildCastIndex :946 |
| `BuffEngine.lua` | ApplyEndOnCast, RefreshAuraStates, VisibilityGate, VisibilityShowsIn, ReadableAuraTiming, StartUserBuffFromAura; hooks in OnUnitAura / ClearTrackerRuntimeState | VERIFIED | :1187, :1448, :1361, :1387, :1407, :1426; :1564; :822 |
| `Providers.lua` | `ns:FillUserBuffProc` shared; cross-spell side effect; cast evidence | VERIFIED | :89-136, :201-210, :243-245 |
| `Display.lua` | Gate at SlotDraws, icon chain, bar filter; VisibilityShowsIn in both activity tests | VERIFIED | see truth 1 |
| `CDMTab.lua` | visibility + endOnCast fields, ParseSpellIDList, SyncVisibilityChecks, widened DetailedModeOffered | VERIFIED | see plan 04 rows |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| Dialog Save | entry.visibility / entry.endOnCast | values/readKeys, then Add/UpdateTrackedBuff copy (not ENGINE_OWNED) | WIRED |
| Add/Update/Remove/SPELLS_CHANGED/world entry | RebuildDetailedRuleIndex | RebuildRankIndex, then RebuildCastIndex (:1068, :946) | WIRED |
| RebuildRankIndex (both exits) | RefreshAuraStates | Core.lua:1100, :1170 (guarded by displayInitialized) | WIRED |
| OnTrigger | ApplyEndOnCast | `ns.endKeysBySpell[spellID]` hit | WIRED |
| OnUnitAura | RefreshAuraStates, then ReadPlayerAura | BuffEngine.lua:1564, 1478/1491 | WIRED |
| StartUserBuffFromAura | FillUserBuffProc | BuffEngine.lua:1431 | WIRED |
| Display render sites | VisibilityGate / VisibilityShowsIn | 7 call sites | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| VisibilityGate | ns.auraState[key] | RefreshAuraStates (ReadPlayerAura), cast evidence (OnTrigger), cross-spell end (ApplyEndOnCast) | Yes | FLOWING |
| ApplyEndOnCast | endKeys | ns.endKeysBySpell, built from entry.endOnCast, written by the dialog | Yes | FLOWING |
| RefreshAuraStates | visibilityKeys / visibilityAuraID | RebuildDetailedRuleIndex from entry.visibility / DetailedAuraID | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Aura reads only through allowlisted readers | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (10 reads in 3 allowlisted readers)` | PASS |
| Gate self-test | `node scripts/aura-read-gate.js --selftest` | `AURA-READ SELFTEST PASS (30 cases)` | PASS |
| Migration dry-run self-test | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (7 cases)` | PASS |
| Formatting / parse (stylua parses every file) | `stylua --check` on the 5 files | exit 0 | PASS |
| Line endings | `git ls-files --eol` + node CRCRLF / bare-LF count | all `w/crlf`, 0 CRCRLF, 0 bare LF | PASS |
| Diff scope vs 0459903 | `git diff --stat 0459903 HEAD -- . ':!.planning'` | exactly BuffEngine, CDMTab, Core, Display, Providers | PASS |
| Runtime behaviour | no Lua runtime / WoW client | — | SKIP (human) |

### Probe Execution

Not applicable. This phase declares no probes, and there are no `scripts/*/tests/probe-*.sh` files.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DTRK-03 | 57-02, 57-03, 57-04, 57-05 | Show always (default) / only while present / only while absent | SATISFIED (static), needs human | Truths 1, 2, 4 |
| DTRK-05 | 57-01, 57-04, 57-05 | Spells whose cast ends it; works in combat | SATISFIED (static), needs human | Truth 3 |

REQUIREMENTS.md maps only DTRK-03 and DTRK-05 to Phase 57 (lines 138-139). Both are claimed by plans, and no requirement is orphaned. The CONTEXT's extension of DTRK-05 to cooldown resets is implemented as well (BuffEngine.lua:1214-1219).

### CONTEXT decisions honoured

| Decision | Honoured | Evidence |
|----------|----------|----------|
| Mode saved as `entry.visibility`, nil = always, runtime gated on `entry.detailed` | Yes | CDMTab read :2118-2121; VisibilityGate :1365 |
| Aura-driven start for "present" only, out of combat, USER_BUFF only (no start for cooldowns) | Yes | BuffEngine.lua:1509-1516 (`trackerType == USER_BUFF`), :1427 |
| "Absent" = full-colour icon, no sweep/timer, bypasses hideWhenInactive; bar = idle bar | Yes | see plan 03 rows |
| Cache never read per frame; frozen in combat; unknown = always | Yes | truth 2 |
| WR-04 "check both" list for cover-all-ranks + aura ID | Yes | BuffEngine.lua:1474-1489 |
| Cooldowns: aura ID for visibility only + mode + "Reset when you cast" | Yes | keepOnAuraLoss buff-only (:2038); Core.lua:976 uses DetailedAuraID for USER_CD |
| One box, labels "Ends when you cast:" / "Resets when you cast:", icon row, validation, fresh array | Yes | CDMTab.lua:2159-2221, 1380-1410 |
| Reverse index at rebuild time, detailed-with-rules only, rank/override expanded | Yes | truth 3 |
| Cast path allocation-free, side effect before the buff return, skip rule documented, redraw when no proc is returned | Yes | Providers.lua:193-210; BuffEngine.lua:1177-1231 |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase diff) | — | TBD/FIXME/XXX/TODO/HACK/OnUpdate | none found | — |
| Display.lua | 1982, 2300-2304 | `hasActiveTimers`/`hasActiveIcons` still count a running timer or cooldown slot that the gate then hides | Info | Under hideWhenInactive, a container whose only content is gated off stays shown with nothing in it. The container draws nothing outside Edit Mode, so this is cosmetic only |
| BuffEngine.lua | 1509-1519 | "Present" aura-driven start refires on the next out-of-combat UNIT_AURA if a cross-spell rule marked the aura absent but the aura is actually still up | Info | Occurs only when the user's rule does not match the game. Listed as a human check |
| BuffEngine.lua | 1514 | An aura-started "present" timer is not re-synced while it runs; a re-buff by another player extends the aura, but the timer restarts only after the proc expires and a later UNIT_AURA fires | Info | Between expiry and that event, the tracker shows the idle "present" icon rather than a timer |
| Providers.lua | 209 | Skip rule passes `cdKey` even when that cooldown is in section "hidden" and will not actually start | Info | A hidden cooldown is not drawn, so there is no visible effect |
| 57-05-SUMMARY.md | "Known behaviour" | States that dialog Save calls `ns:RebuildCastIndex()` at CDMTab.lua:224. That line is actually the CDM drag-drop path; dialog Save reaches the rebuild through `ns:UpdateTrackedBuff` / `ns:AddTrackedBuff`, then `ns:RebuildRankIndex` (BuffEngine.lua:1117 / :950), which also refreshes aura states | Info | The narrative is wrong, but the conclusion (rules apply immediately on Save) holds |

No blocker or warning anti-patterns found.

### Human Verification Required

The frontmatter `human_verification` list is the full checklist. It is 57-05-SUMMARY.md's 15 items, plus one verifier-added item (a cross-spell end on a "present" tracker whose aura is in fact still up). Every item must pass on retail AND on Forever with `/console scriptErrors 1`. Persistence needs a real logout/login, never `/reload`.

### Gaps Summary

No gaps. Every roadmap success criterion and every plan must-have traces to substantive, wired code:

- **Visibility:** the dialog field saves `entry.visibility`. The rebuild builds the watch list, the out-of-combat refresh caches the aura state, and the cache feeds `ns:VisibilityGate`, which gates all Display sites.
- **Cross-spell rules:** the dialog field saves `entry.endOnCast`. The rebuild builds a rank/override-expanded reverse index, and a one-lookup cast-path side effect ends buffs or resets cooldowns.

The status is `human_needed` only because runtime behaviour (combat freeze, M+, other players' auras, Forever ranks, real logout persistence, visual look) cannot be run here.

---

_Verified: 2026-09-28_
_Verifier: Claude (gsd-verifier)_
