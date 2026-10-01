---
phase: 54-edit-trackers
plan: 04
subsystem: infra
tags: [wow-addon, lua, cdm-tab, buff-engine, gates, deploy, cleanup]

# Dependency graph
requires:
  - phase: 54-edit-trackers (plan 01)
    provides: "ns:UpdateTrackedBuff, ns:FindTrackerConflict, ns:ClearTrackerRuntimeState, ns:IsEditableTracker, ns:TrackerKindWord, ns:SpellLabel (BuffEngine.lua)"
  - phase: 54-edit-trackers (plan 02)
    provides: "TRACKER_FIELDS field-definition contract, field-agnostic CreateAddDialog, OpenForAdd (CDMTab.lua)"
  - phase: 54-edit-trackers (plan 03)
    provides: "dialog.OpenForEdit, the confirm handler's edit branch, OnHide's wipe(ctx), the context-menu Edit entry (CDMTab.lua)"
provides:
  - "Whole-phase gate results: migrate-dryrun selftest, out-of-scope-file diff, five-function hot-path byte-identity, dead-code sweep, new-helper call-site audit, duplication/performance/upvalue review, stylua/CRLF checks -- all green"
  - "One found-and-fixed gate defect: a documentation comment double-counted the label-derivation duplication check (see Deviations)"
  - "A deployed build (v0.4.1-41-ge862e04-dirty-dev) on every WoW client folder present on this machine, including Midnight retail and the Forever beta"
  - "The ordered in-game checklist covering all nine HUMAN must_haves, for the user to run at the end of this autonomous run"
affects: [55]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Whole-phase gate discipline: every hot-path function diffed byte-for-byte against the phase's pre-planning commit (991ac2f), not just reviewed by eye, before a phase is considered closed"

key-files:
  created:
    - ".planning/phases/54-edit-trackers/54-04-SUMMARY.md"
  modified:
    - "BuffEngine.lua - reworded ns:SpellLabel's header comment so it no longer names the C_Spell.GetSpellInfo API literally, which had pushed the phase's label-derivation duplication grep count to 3 against a base of 2 (no second implementation existed; the comment itself was the extra match)"

key-decisions:
  - "The C_Spell.GetSpellInfo duplication gate's over-count was a comment mentioning the API name in prose, not a second call site -- fixed per the plan's own instruction to treat 'a comment' as an in-scope Task 1 fix, rather than treated as a gate to relax or skip"

requirements-completed: [EDIT-01, EDIT-02, EDIT-03, EDIT-04]

# Metrics
duration: ~5min
completed: 2026-09-28
---

# Phase 54 Plan 04: Edit Trackers - Whole-Phase Gates, Cleanup Review and Deploy Summary

**Every whole-phase gate (migrate-dryrun selftest, hot-path byte-identity, dead-code sweep, duplication/performance/upvalue review, stylua/CRLF) passes with one found-and-fixed comment-only defect, and the phase is deployed to every WoW client folder present, including Midnight retail and the Forever beta.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-09-28T09:44:03-03:00 (previous plan-doc commit, ecb0be0)
- **Completed:** 2026-09-28T12:50:00Z
- **Tasks:** 2/2 completed
- **Files modified:** 2 (BuffEngine.lua fix; this SUMMARY.md)

## Accomplishments
- Ran every whole-phase gate specified in Task 1 and recorded command + output below; all pass.
- Found and fixed one gate defect: a documentation comment on `ns:SpellLabel`'s header named the game API (`C_Spell.GetSpellInfo`) in prose, pushing the label-derivation duplication grep to 3 matches against the phase base's 2. No second implementation existed. Reworded the comment; the gate now matches base exactly.
- Confirmed the phase diff is confined to `BuffEngine.lua` and `CDMTab.lua`: every other file the plan lists (`Core.lua`, `Providers.lua`, `Display.lua`, `MergeMode.lua`, `EditModeFrames.lua`, `Config.lua`, `CDMTab.xml`, `TerribleBuffTracker.toc`, `scripts/`) is byte-identical to `991ac2f`.
- Confirmed all five named hot-path functions (`ns:OnSpellCastSucceeded`, `ns:GetActiveTimers`, `ns:ScanActiveTimersForCancellation`, `ns:OnUnitAura`, `ns:StartAllPreviewTimers`) are byte-identical to `991ac2f` -- the phase's edit-dialog and engine-move work added zero per-frame or per-event cost to any of them.
- Confirmed no dead code from the phase: none of `ResetFields`, `RefreshAddState`, `spellIdBox`, `durationBox`, `opts.coverAllRanks`, `existingEntry` remain anywhere in the Lua source, and all six new `ns` helpers (`TrackerKindWord`, `SpellLabel`, `IsEditableTracker`, `FindTrackerConflict`, `ClearTrackerRuntimeState`, `UpdateTrackedBuff`) have at least one caller beyond their own definition.
- Deployed the build with `./scripts/install.bat` to all four WoW client folders present on this machine (`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`) -- both Midnight retail and the Forever beta are covered.
- Wrote the nine-item ordered in-game checklist below, covering every HUMAN `must_haves` truth in the plan, including the "known inconsistency" decision item phrased as a question for the user.

## Task Commits

Each task was committed atomically:

1. **Task 1: Whole-phase gates plus performance and cleanup review** - `e862e04` (fix) -- the one comment-only gate fix found during the review; every other gate passed with no code change needed
2. **Task 2: Deploy with install.bat and write the in-game checklist** - (this SUMMARY's commit, docs)

## Files Created/Modified
- `BuffEngine.lua` - reworded `ns:SpellLabel`'s header comment to stop naming `C_Spell.GetSpellInfo` literally (Task 1 gate fix)
- `.planning/phases/54-edit-trackers/54-04-SUMMARY.md` - this file (Task 2)

## Gate Results (Task 1, command + output)

**1. `node scripts/migrate-dryrun.js --selftest`**
```
SELFTEST PASS v0.4.1 -> v8
SELFTEST PASS second login is a no-op
SELFTEST PASS unreadable race defers v7 and v8
SELFTEST PASS pre-v7 -> v8 after race resolves
SELFTEST PASS comparator can fail
SELFTEST PASS no racial slot: unreadable race does not defer v7/v8
SELFTEST PASS WoW-written file (arrays, comments, escapes), pre-v4 -> v8
SELFTEST PASS (7 cases)
exit=0
```

**2. `git diff --stat 991ac2f -- Core.lua Providers.lua Display.lua MergeMode.lua EditModeFrames.lua Config.lua CDMTab.xml TerribleBuffTracker.toc scripts`**
```
(empty)
```

**3. Hot-path byte-identity** (`diff` of each function's base body against current, for `OnSpellCastSucceeded`, `GetActiveTimers`, `ScanActiveTimersForCancellation`, `OnUnitAura`, `StartAllPreviewTimers`):
```
=== OnSpellCastSucceeded ===             diff exit=0
=== GetActiveTimers ===                  diff exit=0
=== ScanActiveTimersForCancellation ===  diff exit=0
=== OnUnitAura ===                       diff exit=0
=== StartAllPreviewTimers ===            diff exit=0
```
All five print nothing -- byte-identical to `991ac2f`.

**4. Dead code from this phase**
```
grep -nE "ResetFields|RefreshAddState|spellIdBox|durationBox|opts\.coverAllRanks|existingEntry" *.lua
(no output, exit=1)
```
Every new helper has a caller beyond its own definition line:
- `ns:TrackerKindWord` -- BuffEngine.lua:870,873,903,1004,1008,1042,1056; CDMTab.lua:1298
- `ns:SpellLabel` -- BuffEngine.lua:841,1021
- `ns:IsEditableTracker` -- BuffEngine.lua:983; CDMTab.lua:409,1688
- `ns:FindTrackerConflict` -- BuffEngine.lua:864,1002; CDMTab.lua:1296
- `ns:ClearTrackerRuntimeState` -- BuffEngine.lua:944,1015
- `ns:UpdateTrackedBuff` -- CDMTab.lua:1641 (the Save click)

**5. Duplication introduced by this phase**

Label derivation (`C_Spell.GetSpellInfo`): **found over base on first pass** -- current count 3 vs. base count 2. Investigated: line 517 (`ns:GetSpellIcon`, pre-existing/unrelated) and line 728 (inside `ns:SpellLabel`, the real derivation) were the two genuine call sites; the third match was `ns:SpellLabel`'s own header comment naming the API in prose ("C_Spell.GetSpellInfo's name when resolvable"). Fixed by rewording the comment to "the game's resolved spell name when resolvable" -- no code change, no logic duplicated. Re-run: `grep -c "C_Spell.GetSpellInfo" BuffEngine.lua` = 2, matching base exactly. Commit `e862e04`.

Runtime-state clear list (`cooldownOverrides[`): exactly two matches -- line 468 (the frozen v8 migration, pre-existing) and line 789 (inside `ns:ClearTrackerRuntimeState`, the phase's one shared clear site). No duplication.

**6. Performance review**

`RefreshState` call sites (`grep -n "RefreshState(" CDMTab.lua`): three, all off the hot path --
- CDMTab.lua:1466, inside a field's `OnTextChanged`-style build callback (fires on keystroke, not per-frame)
- CDMTab.lua:1670, inside `OpenForAdd` (fires once per dialog open)
- CDMTab.lua:1712, inside `OpenForEdit` (fires once per dialog open)

No `RefreshState` call inside an `OnUpdate` handler. `ns:FindTrackerConflict`'s string concatenation (`"Already tracked as a " .. ns:TrackerKindWord(...)`) occurs only inside the four call sites listed in check 4/5 above -- all dialog-input or Add/Update-call paths, never a hot path. `ns:UpdateTrackedBuff` is reached from exactly one site, the Save click (CDMTab.lua:1641).

`grep -n "OnUpdate" CDMTab.lua`: 7 matches, identical count to base (`git show 991ac2f:CDMTab.lua | grep -c "OnUpdate"` = 7). No new `OnUpdate` site from this phase.

**7. Upvalue order**

- CDMTab.lua: `FormatDuration` (line 1203) < `TRACKER_FIELDS` (line 1262) < `CreateAddDialog` (line 1391) -- correct order.
- BuffEngine.lua: `ENGINE_OWNED` (line 802) < `function ns:AddTrackedBuff` (line 829) -- correct order.

**8. Formatting and line endings**
```
stylua --check BuffEngine.lua CDMTab.lua
exit=0
git ls-files --eol BuffEngine.lua CDMTab.lua
i/lf    w/crlf  attr/text eol=crlf    BuffEngine.lua
i/lf    w/crlf  attr/text eol=crlf    CDMTab.lua
```
Both `w/crlf` as required. CRCRLF node check (search for `\r\r\n` byte sequence): both files CLEAN.

## Deploy Result (Task 2)

```
./scripts/install.bat
Deploying 11 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua,
BuffEngine.lua, Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua, Display.lua,
CDMTab.xml, CDMTab.lua, tbt_icon_64x64.blp
Deployed version: v0.4.1-41-ge862e04-dirty-dev
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
Done! /reload in WoW to load the addon.
exit=0
```

The `-dirty-dev` suffix reflects the pre-existing, out-of-scope `.gitignore` working-tree edit noted in this plan's hazards -- not anything this plan touched. `_retail_` is Midnight retail; `_classic_beta_` is the Forever beta. Both are deployed.

`git status --porcelain -- '*.lua' '*.xml' '*.toc' | grep -vE '(BuffEngine|CDMTab)\.lua$'` printed nothing both before and after the deploy -- no source file outside the two the phase touched was modified, and `.gitignore` was never staged (`git diff --cached --name-only` never contains it).

## In-Game Checklist

Read this once before starting:

- **No client restart needed.** The TOC did not change this phase -- `/reload` (or opening the CDM fresh) is enough to pick up the new Lua.
- **Logout/login, never `/reload`, is the persistence proof.** Several items below say "survives logout/login" -- that means a real logout to the character-select screen and back in (or fully closing and reopening the client), not `/reload`. `/reload` keeps saved data in memory and cannot catch a write-but-never-persisted bug.
- **Test on both flavours.** Midnight retail and the Forever beta both need a pass. "Cover all ranks" exists only on Forever (`ns.CLIENT_HAS_SPELL_RANKS`) -- retail never shows that checkbox, by design.
- Every item below opens the CDM's TBT tab (`/tbt`) unless noted.

1. **Edit entry visibility.** Right-click a user-created buff tile and a user-created cooldown tile -- both show an **Edit** entry in the context menu. Right-click Lust, a trinket tile, a pot tile, a racial buff tile, a racial cooldown tile, and a bag-item tile -- **none** show Edit.
2. **Edit dialog opens prefilled.** Click Edit on a user buff tile -- dialog titles itself **"Edit Buff Tracker"** with a **Save** button, spell ID and duration prefilled from the tracker (e.g. a 120-second tracker shows `2m` in the Duration box). Repeat on a user cooldown tile -- titles itself **"Edit Cooldown Tracker"**. On Forever only, confirm **"Cover all ranks"** reflects the tracker's saved value.
3. **Duration-only edit takes effect and persists.** Edit a tracker, change only the duration, click Save. Cast the tracked spell -- the new duration is used. Log out to character select and back in (never `/reload`) -- the new duration is still there.
4. **Spell ID edit moves the tile correctly.** Edit a tracker, change the spell ID to a different spell of the same kind (buff or cooldown), click Save. Confirm: the tile stays in the same container at the same position, now showing the new spell's icon; if a timer/cooldown was running for the old ID it disappears; casting the old spell no longer starts anything; casting the new spell starts the tracker. Log out and back in -- the change is still there.
5. **Duplicate rejection.** In Edit (or Add), type a spell ID already tracked as the same kind -- Save/Add disables and the dialog shows **"Already tracked as a buff"** or **"Already tracked as a cooldown"** in red; the existing tracker is unchanged. On the Cooldowns tab, also try an ID already tracked as a racial cooldown -- refused the same way. Then, while still editing a tracker, re-enter that tracker's *own* current ID -- it is accepted (Save re-enables), since it isn't a conflict with itself.
6. **Add dialog regression check.** Open Add (the "+" square) -- opens empty with Add disabled. Type `2min` in Duration -- the `s`/`m` hint shows. Tab moves between boxes; Enter confirms. A new tracker lands in Not Displayed. On Forever, "Cover all ranks" is checked by default; on retail, no checkbox appears at all. On retail specifically, confirm the red validation hint now sits **below** the Duration box, not on top of it (dialog is 32px taller there than before this phase).
7. **Known inconsistency -- your call, not a bug report.** On a character with a racial: adding that racial's spell ID fresh on the Cooldowns tab creates a **racial cooldown** (no Edit entry). Editing an *existing* user cooldown to that same racial spell ID keeps it a **user cooldown** (Edit still works). Try both and tell Claude: keep this as-is, or unify the two paths in a later phase?
8. **Remove-then-re-add does not inherit a cooldown.** Start a cooldown on a tracked spell, remove that tracker mid-cooldown, then re-add the same spell ID as a new cooldown tracker -- it shows ready, not still counting down from the removed tracker's state.
9. **Dialog dismissal.** With the Edit dialog open: switch TBT tabs (Buffs ↔ Cooldowns) -- dialog closes. Close the CDM window -- dialog closes. Press Escape -- dialog closes. In every case, nothing is saved (re-open Edit on the same tracker afterward and confirm no partial edit stuck).

## Decisions Made
- Treated the label-derivation gate's over-count as a Task-1 in-scope fix (a comment reword), per the plan's own instruction that a gate failure should be fixed as "a comment, a dead line, or a misplaced declaration" before moving on -- not treated as a false alarm to wave through or as grounds to relax the gate itself.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in the gate's own accounting, not runtime code] Reworded a comment that double-counted the label-derivation duplication check**
- **Found during:** Task 1, check 5 (duplication review)
- **Issue:** `ns:SpellLabel`'s header comment named `C_Spell.GetSpellInfo` in prose, so `grep -c "C_Spell.GetSpellInfo" BuffEngine.lua` returned 3 against a phase-base count of 2, even though only one real call site exists inside `ns:SpellLabel` (the pre-existing `ns:GetSpellIcon` call is the other, unrelated to label derivation).
- **Fix:** Reworded the comment to "the game's resolved spell name when resolvable", removing the literal API-name string while keeping the same meaning.
- **Files modified:** BuffEngine.lua
- **Verification:** `grep -c "C_Spell.GetSpellInfo" BuffEngine.lua` now returns 2, matching the base count exactly; `stylua --check BuffEngine.lua CDMTab.lua` still exits 0; all other Task 1 gates re-run clean after the fix.
- **Committed in:** `e862e04`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 -- a documentation-only defect in the phase's own gate accounting, not a runtime bug)
**Impact on plan:** No behavioural code changed. The fix only affects a comment's wording; every hot-path and duplication gate is now green with no exceptions or waived checks.

## Issues Encountered
None beyond the one gate defect documented above, which was fixed within Task 1's own fix-and-continue allowance.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 54 (Edit Trackers) is code-complete and deployed: `BuffEngine.lua` and `CDMTab.lua` carry every edit-mode change across plans 54-01 through 54-04, every whole-phase gate is green, no hot-path function gained work, and no dead code from the phase remains. The build is live on every WoW client folder present, including Midnight retail and the Forever beta. What remains is entirely human verification -- the nine-item in-game checklist above, which the user runs at the end of this autonomous run. No code blockers exist for Phase 55 (live preview, auto-suggested cooldown, secrecy badge), which plan 54-02's `TRACKER_FIELDS` contract was explicitly built to receive as new field-definition entries with no dialog-code edit.

This executor did not update `.planning/STATE.md`, `.planning/ROADMAP.md`, or `.planning/REQUIREMENTS.md` -- those writes belong to the orchestrator per this plan's execution objective.

## Self-Check: PASSED

- FOUND: BuffEngine.lua
- FOUND: .planning/phases/54-edit-trackers/54-04-SUMMARY.md
- FOUND commit: e862e04 (Task 1)

---
*Phase: 54-edit-trackers*
*Completed: 2026-09-28*
