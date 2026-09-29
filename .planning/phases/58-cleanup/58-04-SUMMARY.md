---
phase: 58-cleanup
plan: 04
subsystem: whole phase
tags: [cleanup, gates, hot-path, dead-code, release-scripts, deploy, uat]
requires: [58-01, 58-02, 58-03]
provides:
  - "Whole-phase gate results, hot-path audit, dead-code sweep, duplication and release-script reviews"
  - "58-HUMAN-UAT.md: 11-item smoke checklist for Forever and Midnight retail"
affects: [59, 60]
tech-stack:
  added: []
  patterns: []
key-files:
  created: [.planning/phases/58-cleanup/58-04-SUMMARY.md, .planning/phases/58-cleanup/58-HUMAN-UAT.md]
  modified: [.planning/STATE.md]
decisions:
  - "No audit defect found, so no fix commit"
  - "release.bat, install.ps1 and .pkgmeta unchanged: nothing broken (user decision: no check scripts wired into release)"
metrics:
  duration: "~20 min"
  completed: 2026-09-29
---

# Phase 58 Plan 04: Whole-phase gates, audit and deploy Summary

Every earlier task gate passes on the final tree. The milestone's tick, UNIT_AURA and UNIT_SPELLCAST_SUCCEEDED paths build no table, closure or string per call. Neither dead-code probe flags anything. The release scripts are reviewed and unchanged. The build is deployed, and an 11-item smoke checklist covers both clients.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | b65972d | docs(58-04): whole-phase gates, hot-path audit and cleanup review |
| 2 | (the commit that adds 58-HUMAN-UAT.md) | docs(58-04): deploy, smoke HUMAN-UAT and STATE for Phase 58 |

## Gate results

All nine earlier task gates were run verbatim, in order, on the final tree (HEAD c843462 plus this plan's docs). The one exception is 58-01 Task 1, whose `{ node -e '...' || f "the rename changed more than the six names"; } && ` clause was dropped. That clause is the be7ca11 reverse-mapping snapshot proof, which later plans legitimately invalidate, and it passed when 58-01 Task 1 was committed.

```
58-01-t1-noproof: ok
58-01-t2: ok
58-01-t3: ok
58-02-t1: ok
58-02-t2: ok
58-02-t3: ok
58-03-t1: ok
58-03-t2: ok
58-03-t3: ok
```

The historical gates that now fail by design were left alone: 57.4-01's metaReminder branch assertion (after 58-01), the 57.4-03 T1 scope freeze, and the 57.5-03 T2 all-pending UAT check.

## Hot-path audit

Static scan first. For each per-event body, comments are stripped and the scan counts `{`, a nested `function`, and `..`:
- `ns:ReminderGate`, `ns:ReminderShowsIn`, `ns:RefreshAuraStates`, `ReadWatchedAura`, `ns:QueueCastAuraRecheck`, `RunCastAuraRecheck`, `ns:GetActiveTimers`, `ns:OnUnitAura`, `ns:ApplyEndOnCast`, `UserSpellProviderMixin:OnTrigger`, `ns:ResolveCastOwner`, `ns:StartReminderFromCast`, `ns:StartCooldownFromCast` and `ns:IsTrackerLoaded` all score 0 / 0 / 0.
- The only hits are in `ns:ScanActiveTimersForCancellation` (debug labels), `ns:FillUserBuffProc` (the label fallback) and `ns:SpellKnownState` (the string `"function"` in a `type()` check). All three are explained below.

"Milestone" means the function did not exist at 9934b20 (checked with `git show 9934b20:<file>`).

| Function | Milestone? | Per-call cost |
|----------|------------|---------------|
| `ns:ReminderGate` | yes (57, renamed 58) | Per reminder slot per render: `ns:IsReminderEntry` (one table index) and two hash reads. No allocation. |
| `ns:ReminderShowsIn` | yes (57, renamed 58) | Per container per tick: a numeric loop over `ns.reminderKeys` with one `tracked[key]` read and a ReminderGate call each; returns at the first shown reminder. No allocation, no `pairs()` over the DB. |
| `ns:GetActiveTimers` | pre-milestone; the lazy reminder expiry was added | Wipes and refills the module-level `activeTimerSet` / `activeTimerList` (pre-milestone). The milestone's branch: when a reminder's timer is past `expiresAt` it is removed, `ns.auraState[key] = false`, and `ns:QueueCastAuraRecheck()` is queued (coalesced, see below). A reminder proc never reaches `activeTimerSet`. The `table.sort(..., ByExpiry)` is pre-milestone. |
| `ns:OnUnitAura` | pre-milestone; the refresh call was added | Reads `isFullUpdate` through `issecretvalue`, calls `ns:RefreshAuraStates(fullUpdate)`, then the pre-milestone cancellation scan. Debug prints only under `ns.debugLogging`. No allocation. |
| `ns:RefreshAuraStates` | yes (57/57.2) | Returns at once when there are no reminders or `ShouldAurasBeSecret()` is true. Otherwise it wipes the two module-level memo tables, then runs a numeric loop over the reminders with a numeric loop over each watch list. Proc start uses the pooled `ns:FillUserBuffProc`. One `ns:UpdateDisplay` only when something changed. No table built. |
| `ReadWatchedAura` | yes (57.2-05) | The per-call aura memo: `refreshAuraMemo` / `refreshReadableMemo` are wiped once per `RefreshAuraStates` call, so each watched ID is read at most once per call through `ns:ReadPlayerAura`. The aura table returned by the game API is the API's own allocation; the memo is what bounds it. |
| `ns:ScanActiveTimersForCancellation` | pre-milestone | Its only table is the debug-only `cancelledLabels` (created lazily, only on a cancellation; the `..` / `table.concat` are inside the `ns.debugLogging` print). Present at 9934b20; left as is. |
| `UserSpellProviderMixin:OnTrigger` | pre-milestone; milestone added the cooldown, reminder, metaReminder, cross-spell and alternatives sides | Per namespace: two table reads on a miss via `ns:ResolveCastOwner`. The cross-spell and alternatives sides each do one table lookup on a miss and a numeric loop over a prebuilt array on a hit. No table, closure or string on the cast path. |
| `ns:ResolveCastOwner` | yes (58) | Two table reads per namespace on a miss, four at most. No allocation (the gate rejects `{` and `function(` in its body). |
| `ns:StartReminderFromCast` | yes (57.2-05/57.4) | Guard, then the pooled proc refill (`ns:FillUserBuffProc`) and one `ns:QueueCastAuraRecheck`. No allocation. |
| `ns:StartCooldownFromCast` | yes (57.4) | `ns:ResolveCastOwner`, then `GetTime()` into `ns.cooldownStarts`, an override write, and `MarkCooldownsDirty`. No allocation. |
| `ns:FillUserBuffProc` | yes (57.2-05; extracted from OnTrigger) | Proc from the pool (`ns:AcquireProc`), and `aliveBuffs` from prebuilt family tables or the pooled `ns:AcquireAliveBuffs`. Its `"Spell " .. tostring(entry.spellID)` label fallback runs only for an entry with no label. The same concatenation existed before the milestone as `"Spell " .. tostring(ownerKey)` (Providers.lua:174 at 9934b20), so it is recorded as pre-existing and left. |
| `ns:QueueCastAuraRecheck` / `RunCastAuraRecheck` | yes (57.2-05 / 57.4 CR-01) | The per-cast re-check timer: one flag (`castRecheckPending`), one due time (`castRecheckDueAt`) and one file-scope callback. A burst of casts moves the due time and schedules at most one pending `C_Timer.After`; a callback that fires early reschedules itself for the remainder. No closure is built per cast. |
| `ns:IsTrackerLoaded` | yes (57.3) | The known-state cache: the per-frame read is one hash lookup (`ns.trackerLoaded[key] ~= false`). |
| `ns:SpellKnownState` | yes (57.3) | Rebuild time and the dialog hint only, never per frame or per cast. Walks spell, base, override and the cached rank family in one numeric loop with no table built. Since 58-03 the family comes from `ns:CastRuleFamily`'s cache. |
| `ns:ApplyEndOnCast` | yes (57) | One numeric loop over the prebuilt `endKeys` array; no allocation. |

No new per-call allocation and no redundant per-frame work from this milestone was found, so no fix commit was made.

## Dead-code sweep

The two probes (scratch `deadcode.sh`) were run against `git diff 9934b20..HEAD -- '*.lua'`. Comments were stripped with `sed 's/--.*$//'`.

```
== probe (a): ns-level names added by the milestone, code refs across all Lua (<=1 flagged)
(a) names checked: 105, flagged: 0
== probe (b): file-locals added by the milestone, code refs in own file (<=1 flagged)
(b) names checked: 353, flagged: 0
```

The only flag the probes found at planning was the FindTrackerConflict metaReminder branch, which is a branch rather than a name and was removed in 58-01 (a8be1f4).

- `ns:CooldownKindFor` has 3 code references. It is migration-only and kept for the v8 migration (CONTEXT).
- `WireExclusivePair` (CDMTab.lua) has one caller and predates the milestone, so it stays.
- Confirmed gone:
  - `ns.loadRankFamilies`: no Lua reference outside the one "formerly" note (Core.lua).
  - Providers.lua's local `SameIDList` / `CopyIDList`: none.
  - The two inline radio generators: `CreateRadio(` has one code call site, inside `SetupRadioMenu`.

Probe limit: (b) counts name occurrences file-wide, so a milestone local whose name is common elsewhere in the same file could hide. The per-function reading above covers the hot paths.

## Duplication review

What 58-03 unified:
- the Forever rank-family cache (the load rule now reads `ns:CastRuleFamily`);
- the base/override pair (`BaseAndOverride`);
- the ID-list compare and copy (`ns:SameIDList` / `ns:CopyIDList`);
- the "direct ID, then rank index" cast lookup for cooldowns, user reminders and metaReminders (`ns:ResolveCastOwner`);
- the radio-menu generator (`SetupRadioMenu`);
- the Config reminder-row literals (`ROW_BTN_W` / `ROW_GAP`).

58-01 removed the dead conflict branch.

Still duplicated, and why it stays:
- **The buff side of OnTrigger.** It keeps its own direct-then-rank lookup, and the skip rule repeats its two lookups. Both predate the milestone (PROJECT.md "No refactors during cleanup phases").
- **`ns:ResolveRankFamily` steps 1 and 4** keep their own base/override seeds, and the TOOL-01 tooltip keeps `RelatedID`. Both are pre-milestone.
- **The SPELLS_CHANGED branch and RunLoadRefresh** share their `ns:RebuildRankIndex()` / `ns:MarkCooldownsDirty()` lines. They blame to 9934b20, and the plan checker dropped them from scope.
- **The Suggested-tile loops** for items, SUGGESTED_KEYS and racial buffs are pre-milestone. `PlaceSuggestedKeyTile` (57.4) already unified the milestone's two (racial cooldowns and metaReminders), and no further copy was found.
- **`ns:ReminderGate` and `ns:ReminderShowsIn`** both call `ns:IsReminderEntry`. That is one extra table index per reminder, not duplicated logic, so it is left.

## Release scripts review

CONTEXT says to change nothing unless broken. Nothing is broken and nothing was changed. `git diff 9934b20..HEAD` touches none of `scripts/install.bat`, `scripts/install.ps1`, `scripts/release.bat`, `.pkgmeta` or `.github`.

| Check | Result |
|-------|--------|
| install.ps1 derives the file set from the TOC load list | yes: every non-`#`, non-blank TOC line (Core, BuffEngine, Providers, MergeMode, EditModeFrames, Config, Display, CDMTab.xml) plus the TOC itself |
| follows CDMTab.xml to CDMTab.lua | yes: regex over `file="..."` in every loaded XML |
| adds the `## IconTexture:` BLP | yes: matches `tbt_icon_64x64.{blp,tga}` |
| fails on a missing file | yes: `exit 1` with "references X, which does not exist" |
| prunes stale files | yes: removes any file in the deployed folder not in the set |
| dev version in the deployed TOC only | yes: `@project-version@` is replaced in the written copy; the repo TOC is never modified |
| install.bat | thin wrapper forwarding to install.ps1 |
| release.bat main-branch guard | yes: refuses a non-main branch unless `TBT_ALLOW_BRANCH=1` |
| release.bat tags and pushes only | yes: `git tag -a`, then `git push origin main <tag>` |
| release.bat runs no check script | yes: no `aura-read-gate` / `migrate-dryrun` (declined by the user 2026-09-29) |
| .pkgmeta ignores dev files | yes: `scripts`, `tools`, `.planning`, `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `.github`, `.gitattributes`, `stylua.toml`, `*.png`, `RELEASE_NOTES.md`, `.gitignore`, `.pkgmeta`, `LICENSE` |

## Review follow-ups

| Item | Source | Phase 58 outcome |
|------|--------|------------------|
| 57.2 WR-05 (visibility* names mean reminders) | 57.2 REVIEW | Renamed to reminder* (58-01, 6550e34) |
| 57.2 IN-02 (Config row literals) | 57.2 REVIEW | Named constants ROW_BTN_W / ROW_GAP (58-03, 692883e) |
| 57.2 IN-03 (Display's private combat flag) | 57.2 REVIEW | Left: predates the milestone |
| 57.2 IN-04 | 57.2 REVIEW | Left: arises only from corrupt data; a sort would change the JS mirror's result order |
| 57.2 IN-05 ("In Combat" on a reminders container) | 57.2 REVIEW | Option kept; stale notes corrected (58-02, 30b16cf) |
| 57.2-05 WR-05 part 3 (login chat line) | 57.2 REVIEW | Left: user decision |
| 57.2-05 IN-03 (reminder header; redraw skip) | 57.2 REVIEW | Header split (58-03, 3b44b04); redraw skip left (couples the two sides) |
| 57.3 IN-06 (GetBaseSpell static override data) | 57.3 REVIEW | Left: needs the in-game check in 57.3 UAT item 26 (BaseAndOverride makes the same calls) |
| 57.4 IN-01 (unreachable metaReminder conflict branch) | 57.4 REVIEW | Removed (58-01, a8be1f4) |
| 57.4 IN-03 | 57.4 REVIEW | Left: user decision |
| 57.5 IN-01 (hold while unreadable across the set) | 57.5 REVIEW | Left: DTRK-06 by design |
| STATE: base/override lookup duplicated in Core.lua | STATE.md | Unified: BaseAndOverride and the shared family cache (58-03, 230c6f2) |
| STATE: wire aura-read-gate.js into release | STATE.md | Declined by the user 2026-09-29; STATE.md marked (58-02) |

## Deploy

`timeout 300 ./scripts/install.bat` from the repo root, exit code 0:

```
Deploying 11 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua, BuffEngine.lua, Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua, Display.lua, CDMTab.xml, CDMTab.lua, tbt_icon_64x64.blp
Deployed version: v0.4.1-280-gb65972d-dirty-dev
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
Done! /reload in WoW to load the addon.
```

"-dirty" comes from the user's own uncommitted `.gitignore` change, which this phase never touches. The TOC did not change, so a /reload picks the build up. Item 1 of the UAT (fresh install) needs a full client restart.

## Whole-phase gates

The Task 2 gate covers:
- `stylua --check .` from the repo root;
- every Lua/XML/TOC file `w/crlf`, with one CR per line, no CRCR, and none binary to git since be7ca11;
- aura-read-gate PASS (selftest 30 cases) and migrate-dryrun selftest (12 cases);
- no old reminder name;
- no commit touching CHANGELOG.md or .gitignore;
- no check script in release.bat;
- the UAT, deploy and STATE checks, and nothing left uncommitted.

It printed ok after the Task 2 commit.

## Deviations from Plan

- **Scratch folder:** `scratchpad\p58\exec\` (orchestrator instruction), not `exec-58-04\`.
- **58-01 T1 gate variant:** built by dropping exactly the plan-named clause (918 characters) into `gate-58-01-t1-noproof.sh`. The original gate file is kept.
- **Dead-code probe script:** the first version wrote an intermediate file to `/tmp` by mistake. The file was deleted and the probe rewritten to keep everything in memory. The output above is from the clean version.

## Known Stubs

None.
