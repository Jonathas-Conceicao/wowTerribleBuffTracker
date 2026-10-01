---
phase: 56-detailed-tracking-mode-aura-rules
plan: 04
subsystem: ui
tags: [wow-addon, lua, node, cdm-tab, add-dialog, static-analysis, deploy]

# Dependency graph
requires:
  - phase: 56-01
    provides: "ns:DetailedAuraID / ns:CancelsOnAuraLoss runtime gates and scripts/aura-read-gate.js, gated by this plan"
  - phase: 56-02
    provides: "the 50px portrait and ns:RefreshIDPreview / ns:BuildSecrecyBadge helpers, verified byte-identical CreateAddDialog by this plan"
  - phase: 56-03
    provides: "the detailed / auraID / keepOnAuraLoss TRACKER_FIELDS entries this plan's gate confirms are the only non-planning diff alongside BuffEngine.lua, Providers.lua, scripts/aura-read-gate.js"
provides:
  - "whole-phase gate closure: byte-identical CreateAddDialog, pure-scope Lua diff (BuffEngine.lua, CDMTab.lua, Providers.lua, scripts/aura-read-gate.js only), every new ns helper called at least once, OnTrigger allocation-free, no OnUpdate added, TRACKER_FIELDS order proven, stylua clean, both selftests green"
  - "performance and cleanup review of the phase's full diff since 71ba060"
  - "a build deployed to every WoW client folder present"
  - "an ordered 13-item in-game checklist (retail AND Forever) covering DTRK-01, DTRK-02, DTRK-04, DTRK-06, ADD-06"
affects: [57-detailed-tracking-visibility-cross-spell-rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Whole-phase gate re-runs every plan's own verify assertions against the final tree in one pass (selftest, hash, scope diff, caller-per-helper, allocation-free hot path, order proof) rather than trusting each plan's individually-passing gate to still hold after later plans land"

key-files:
  created: []
  modified: []

key-decisions:
  - "No fix commit needed -- every whole-phase gate assertion passed on the first run against the tree left by 56-01..03, so this plan's only artifact is its own SUMMARY.md"

patterns-established: []

requirements-completed: [DTRK-01, DTRK-02, DTRK-04, DTRK-06, ADD-06]

# Metrics
duration: ~10min
completed: 2026-09-28
---

# Phase 56 Plan 04: Whole-Phase Gates, Review, Deploy & Checklist Summary

**Every whole-phase gate (selftests, byte-identical CreateAddDialog, exact four-file diff scope, six-helper caller proof, allocation-free OnTrigger, TRACKER_FIELDS order) passed on the first run against the tree 56-01..03 left, so this plan found no defect to fix; it records the CLAUDE.md performance/cleanup review, deploys to all four local WoW client folders, and writes the 13-item retail+Forever in-game checklist.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-09-28T15:53:54Z
- **Completed:** 2026-09-28T15:54:58Z
- **Tasks:** 2 completed
- **Files modified:** 1 (this SUMMARY only; no source fix required)

## Accomplishments

- Ran the full whole-phase automated gate from 56-04-PLAN.md Task 1 against the tree at `HEAD` (base `71ba060`): `node scripts/migrate-dryrun.js --selftest` (7/7), `node scripts/aura-read-gate.js` (`AURA-READ GATE PASS (8 reads in 3 allowlisted readers)`), `node scripts/aura-read-gate.js --selftest` (`AURA-READ SELFTEST PASS (6 cases)`) -- all green on the first attempt.
- `CreateAddDialog`'s body hash confirmed unchanged across all three coding plans: `64e38633612791cb7e1ea41902b75ae45c18167b`.
- `Display.lua`, `Core.lua`, `MergeMode.lua`, `EditModeFrames.lua`, `Config.lua`, `CDMTab.xml`, `TerribleBuffTracker.toc` all byte-identical to `71ba060` (`git diff --quiet` exits 0).
- Non-planning diff vs `71ba060` is exactly `BuffEngine.lua CDMTab.lua Providers.lua scripts/aura-read-gate.js` -- nothing else touched by the phase.
- All six new `ns` helpers (`DetailedAuraID`, `CancelsOnAuraLoss`, `RefreshIDPreview`, `BuildSecrecyBadge`, `DetailedModeOffered`, `DetailedChildShown`) have at least one non-comment caller outside their own definition.
- `UserSpellProviderMixin:OnTrigger` contains zero `{` (no table literal) between its `function` and `end` lines -- the cast path stays allocation-free.
- Zero `OnUpdate` added anywhere in the phase's Lua diff.
- `TRACKER_FIELDS` order proven: `spellPreview < spellID < secrecyBadge < duration < detailed < auraID < keepOnAuraLoss`.
- `stylua --check` clean on `BuffEngine.lua Providers.lua CDMTab.lua`; CRLF gates pass on all three (`git ls-files --eol` reports `w/crlf`, no `\r\r\n` present in any).
- `./scripts/install.bat` deployed to all 4 WoW client folders present on this machine (retail, PTR, beta, classic_beta). No drift beyond the committed files afterward (`.gitignore`'s pre-existing user edit untouched, never staged).

## Task Commits

This plan's work produced no source-code changes (every gate passed against the tree left by 56-01..03; no defect was found to fix), so there is a single commit for both tasks' combined output:

1. **Tasks 1+2: Whole-phase gates, performance/cleanup review, deploy, in-game checklist** - (this SUMMARY's own commit; no code change)

_Plan metadata commit intentionally NOT made by this executor -- the orchestrator owns STATE.md/ROADMAP.md per its instructions._

## Files Created/Modified

- `.planning/phases/56-detailed-tracking-mode-aura-rules/56-04-SUMMARY.md` - this document (gate results, review, deploy output, checklist)

## Decisions Made

- Combined both tasks into one commit since neither required a source-code edit: the plan's own acceptance criteria only require a fix commit "if the review finds a defect," and this review found none. Splitting an empty Task 1 commit from a Task 2 commit would create a commit with no diff, which the project's git hooks and the `task_commit_protocol`'s "stage task-related files" step do not support meaningfully for a no-op task.

## Performance and Cleanup Review

Reviewed `git diff 71ba060 -- BuffEngine.lua Providers.lua CDMTab.lua` (501 insertions / 172 deletions across the three files) per CLAUDE.md's post-commit standing instruction:

**(a) Cast path (`UserSpellProviderMixin:OnTrigger`, Providers.lua ~171-194):** the diff replaces one expression with an `if/elseif` chain that calls `ns:CancelsOnAuraLoss(entry)` and, when true, `ns:DetailedAuraID(entry)` -- both are plain field reads on `entry` with no table, closure, or string allocation (confirmed: both functions in BuffEngine.lua contain no `{`, `function() `, or string concatenation). The chosen branch either calls the pre-existing `ns:AcquireAliveBuffs` (pooled, unchanged) or reuses the pre-existing `fams[ownerKey] or ns:AcquireAliveBuffs(...)` expression verbatim. `UserSpellProviderMixin:OnTrigger` as a whole still contains zero `{` (gate-verified). The cooldown provider's `OnTrigger` (a separate mixin) is untouched -- confirmed by the diff touching only the buff mixin's line range.

**(b) Scan/render paths:** `Display.lua` is byte-identical to `71ba060` (gate-verified). `ScanActiveTimersForCancellation` (BuffEngine.lua ~1242-1251) is unchanged by this phase's diff and still returns immediately for any proc whose `timer.aliveBuffs` is `nil` or empty (`if timer.aliveBuffs and #timer.aliveBuffs > 0 then`) -- so an opted-out tracker (which Providers.lua now leaves with `aliveBuffs == nil`) costs the scan nothing beyond the one `if` check it already paid for every proc before this phase.

**(c) Dialog compare-before-write:** every new/changed field's `update` hook compares before writing. `ns:RefreshIDPreview` (CDMTab.lua ~1249) returns at `id == state.shownID and state.resolved` before doing any further work; its two call sites (portrait ~1523, auraID row ~1897) both feed it a `state` scoped to that field. The portrait's `secrecyBadge` and the `auraID` row's own badge both guard `SetShown`/badge rebuild behind `id == state.checkedID and gen == state.checkedGen` (portrait ~1605-1609; auraID row ~1901-1905) before doing any atlas/text decision. `grep -i OnUpdate` over the phase's added lines (`git diff 71ba060 ... | grep '^+' | grep -ci OnUpdate`) returns `0` -- no per-frame script was added anywhere in the phase.

**(d) Dead code:** each of the six new `ns` helpers (`DetailedAuraID`, `CancelsOnAuraLoss`, `RefreshIDPreview`, `BuildSecrecyBadge`, `DetailedModeOffered`, `DetailedChildShown`) has at least one non-comment caller outside its own definition (gate-verified per-helper: 1, 1, 2, 2, 2, 2 respectively). `ns:RefreshIDPreview` and `ns:BuildSecrecyBadge` are each called from exactly two sites -- the portrait (Plan 02) and the `auraID` row (Plan 03) -- confirming the Phase 55 preview/badge render logic now lives once in the shared helpers with no duplicate atlas decision or preview render left inline in either entry.

**(e) Phase 57 readiness:** `ns:DetailedModeOffered(ctx)` is a one-line `ctx.kind == ns.KIND.USER_BUFF` predicate Phase 57 widens to admit `ns.KIND.USER_CD` once cooldown children exist (the comment above it already documents this). `ns:DetailedAuraID(entry)` deliberately never falls back to `entry.spellID`, so Phase 57's cross-spell/visibility cache can compose `ns:DetailedAuraID(entry) or entry.spellID` without this plan having pre-decided that fallback. The `auraID` TRACKER_FIELDS entry's `visible` hook depends only on `ns:DetailedChildShown`, with no `USER_BUFF` restriction of its own, so Phase 57 can reuse it unchanged for the cooldown aura-ID-for-visibility field once `ns:DetailedModeOffered` is widened. `scripts/aura-read-gate.js`'s allowlist (`ns:ReadPlayerAura`, `CollectPlayerBuffs`, `TryResolveFromSpellID`) is the standing check any Phase 57 aura read must pass through or be added to as a reviewed decision.

No defect and no dead code were found. Nothing was fixed under Rules 1-3; PROJECT.md's "No refactors during cleanup phases" decision leaves pre-existing code (everything outside this phase's own diff) untouched.

## Known behaviour

- **Edit applies from the next cast:** editing a running tracker's aura ID, or its detailed/opt-out flags, does not retroactively change a proc already in flight -- `proc.aliveBuffs` is assigned once at `OnTrigger` time from the entry's fields as they read *at that cast*, and a live proc keeps whatever list it started with until it ends. The next cast of that spell re-reads the (now-edited) entry and gets the new behaviour. This matches Phase 54's IN-02 precedent (editing a running tracker's duration also applies from the next cast, not retroactively).
- **A typed aura ID equal to the spell ID saves as nothing:** the `auraID` field's `read` (Plan 03) stores nothing when the typed aura ID box is blank OR equal to the typed spell ID, per D-02 ("blank = same as spell"). Re-opening Edit on such a tracker therefore shows the aura ID box blank, not re-filled with the spell ID -- this is intentional, not data loss, since `ns:DetailedAuraID` already treats a missing `entry.auraID` as "use the spell ID" at runtime.

## Deviations from Plan

None - every whole-phase gate assertion in both tasks passed on the first run against the tree left by 56-01..03. No fix commit was needed.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Deploy Output

```
Deploying 11 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua, BuffEngine.lua, Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua, Display.lua, CDMTab.xml, CDMTab.lua, tbt_icon_64x64.blp
Deployed version: v0.4.1-81-g7bf2462-dirty-dev
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
Done! /reload in WoW to load the addon.
```

`git status --porcelain -- '*.lua' '*.xml' '*.toc'` was empty after deploy -- no drift beyond the already-committed source. The pre-existing working-tree edit to `.gitignore` was never staged or touched by this plan.

## In-game checklist (retail AND Forever)

The build above is already deployed to every WoW client folder found on this machine. No TOC change this phase, so `/reload` loads the code for every item below except the one marked **logout**, which needs a REAL logout/login, never `/reload`.

1. **Portrait (ADD-06)** -- Add on both tabs: a centered 50px icon under the title with the CDM mask and border, matching a TBT tracker icon side by side; the spell name centered beneath; no small row under the Spell ID box.
2. **Portrait states** -- an empty box shows a dimmed question mark and no name; `999999999` shows the question mark and "Unknown spell"; no Lua error with `/console scriptErrors 1`.
3. **Portrait hover** -- shows the game tooltip with one Spell ID line and one "Aura secrecy" line; a Contextual-secret ID puts the badge on the portrait's top-right corner, hovering it explains the level; on Forever record whether the badge is the atlas icon or the "(secret?)" text and that the text does not run off the dialog.
4. **Detailed switch (DTRK-01)** -- Buffs tab shows "Detailed tracking" unchecked; checking it shows "Aura ID (blank = same as spell):", its preview row and "End when the aura is lost" (checked), and the dialog grows; unchecking hides them and shrinks it; Tab skips the hidden aura box. The Cooldowns tab shows no Detailed checkbox.
5. **Aura ID preview (DTRK-02)** -- with the aura box blank the small preview shows the spell ID's own icon/name; typing a different ID shows that spell and its own badge (independent of the portrait badge).
6. **Simple unchanged** -- an existing (pre-phase) buff tracker and a new simple one start on the cast and end when the buff is clicked off out of combat, exactly as before.
7. **Aura ID fixes early end (DTRK-02)** -- pick a buff whose aura ID differs from its cast ID (hover the buff: the TOOL-01 "Aura spell ID" line shows it). As a simple tracker it ends at the first out-of-combat aura event; as detailed with that aura ID it keeps running while the aura is up and ends when the aura is clicked off out of combat.
8. **Opt-out (DTRK-04)** -- uncheck "End when the aura is lost", Save, cast, click the aura off -- the timer runs to its full duration. A new detailed tracker has the box checked.
9. **Never ended on an unreadable aura (DTRK-06)** -- with a detailed tracker running, enter combat and click the aura off (or use a secret/Contextual aura, or an M+ key) -- the timer is not ended while unreadable; after combat ends with the aura gone it ends at the next readable check.
10. **Edit prefill** -- Edit a detailed tracker: Detailed checked, aura ID and opt-out as saved. Uncheck Detailed and Save: it behaves as simple (item 6); Edit again and re-check Detailed -- the old aura ID and opt-out reappear (kept while hidden).
11. **logout** **Persistence** -- after a real logout/login, the detailed flag, aura ID and opt-out of items 7, 8 and 10 are still set and behave the same.
12. **Forever only** -- a detailed tracker with "Cover all ranks" and an aura ID follows the aura ID (not the rank family) for cancellation.
13. **Edit a running tracker's aura ID** -- the change applies from the next cast (see "Known behaviour" above).

## Next Phase Readiness

- Phase 56 is code-complete, gated end to end, reviewed, and deployed. DTRK-01, DTRK-02, DTRK-04, DTRK-06 and ADD-06 all have their implementation gated; the 13-item checklist above is the human's remaining action before the phase can be marked verified.
- Phase 57 (visibility modes, cross-spell rules) can build directly on this phase's six `ns` helpers and the `entry.detailed` / `entry.auraID` / `entry.keepOnAuraLoss` fields with no blocker found in this review -- see "(e) Phase 57 readiness" above for the specific extension points.
- No blockers.

## Self-Check: PASSED

- FOUND: `.planning/phases/56-detailed-tracking-mode-aura-rules/56-04-SUMMARY.md`
- All gate commands re-run above against the live tree (not asserted from memory): `migrate-dryrun.js --selftest`, `aura-read-gate.js`, `aura-read-gate.js --selftest`, the `CreateAddDialog` hash, the byte-identical-files check, the diff-scope check, the six per-helper caller counts, the `OnTrigger` `{` count, the `OnUpdate` grep, the `TRACKER_FIELDS` order awk, `stylua --check`, the CRLF/CRCRLF checks, and `install.bat`'s own output -- all passed/matched as recorded above.

---
*Phase: 56-detailed-tracking-mode-aura-rules*
*Completed: 2026-09-28*
