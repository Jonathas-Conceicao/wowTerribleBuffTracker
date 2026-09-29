---
phase: 49-forever-racial-catalogue
plan: 05
subsystem: buff-tracking
tags: [lua, wow-addon, forever-beta, racial, verification, blocking-checkpoint]

# Dependency graph
requires:
  - phase: 49-01
    provides: "the racial: key namespace, per-race resolvers, no-duration guard"
  - phase: 49-02
    provides: "RACIAL_SPELLS filled for all ten Forever races"
  - phase: 49-03
    provides: "the migration, the race gate at every render walk, Suggested tiles"
  - phase: 49-04
    provides: "the indefinite proc shape, aura-driven start, the combat-enter clear"
provides:
  - "Cross-plan static sweep confirming the two-slot model is gone, the race gate is applied at exactly the four render walks, all ten race blocks exist, and none of the five 49-02 optional fields (indefinite, cancelOnAuraLoss, startFromAura, clearOnCombat, longDuration) is dead data"
  - "A deployed build (v0.4.0-129-g100d1df-dev) on every WoW client folder present on this machine"
  - "The G1-G10 in-game run sheet, reproduced for the user, with every gate PENDING -- none simulated, none marked passed"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/49-forever-racial-catalogue/49-05-SUMMARY.md
  modified: []

key-decisions:
  - "Task 1's cross-plan sweep is the only work this agent could complete: no WoW client is available here, so Task 2 (the blocking in-game gate) is left entirely to the user, with zero gates guessed at or marked passed"
  - "The plan's own P7 sub-check (grep -cF 'ns:IsRacialKeyVisible' Core.lua = 0) is unsatisfiable against the correct, already-merged source -- documented as a deviation rather than edited around, since Task 1's own action explicitly forbids touching source"

patterns-established: []

requirements-completed: []

# Metrics
duration: ~20min
completed: 2026-09-25
---

# Phase 49 Plan 05: Whole-Phase Static Sweep, Deploy, and the In-Game Gate Summary

**Task 1 (the cross-plan static sweep and deploy) is complete and passed, with one pre-existing, already-documented unsatisfiable sub-check confirmed by manual reading rather than edited around. Task 2 (G1-G10, the blocking in-game gate) has NOT been run by anyone -- no WoW client is available to this agent, and the whole phase's requirement closure now waits on the user to play it.**

## Performance

- **Duration:** ~20 min (including worktree fast-forward sync at session start, matching every
  prior wave's executor in this phase)
- **Started:** 2026-09-25
- **Completed (Task 1 only):** 2026-09-25
- **Tasks:** 1 of 2 executed (`type="auto"`); Task 2 (`type="checkpoint:human-verify"`) is a
  blocking gate this agent cannot run and does not attempt to run
- **Files modified:** 0 (Task 1's own `<action>` explicitly forbids touching source; this plan's
  frontmatter declares `files_modified: []`)

## Accomplishments (Task 1)

Ran the whole-phase cross-plan static sweep that no single 49-0[1-4] plan's own gate could run,
because each plan only ever saw its own half of the change:

- **Two-slot model gone everywhere:** `grep -E` for `ns\.RACIAL_KEYS|RACIAL_SLOT_BY_KEY|RACIAL_SUPPORTED_LINES|RACIAL_UNSUPPORTED_LINES`
  across all six Lua files (`Core.lua`, `Providers.lua`, `BuffEngine.lua`, `CDMTab.lua`,
  `Display.lua`, `MergeMode.lua`) returns zero matches.
- **The key parser exists in exactly one place:** `ns:RacialKeySpellID(key)` is defined once, in
  `Core.lua`.
- **All ten race blocks present:** `[1]`, `[2]`, `[3]`, `[4]`, `[5]`, `[6]`, `[7]`, `[8]`, `[95]`,
  `[96]` -- ten `[raceID] = {` blocks inside `RACIAL_SPELLS` (Providers.lua:847-937), confirmed by
  `awk` range extraction bounded correctly at the table's own closing brace.
- **The race gate sits at exactly the four render walks and nowhere else:** `ns:IsRacialKeyVisible`
  appears 2x in `Display.lua` (bar + icon), 1x in `CDMTab.lua` (tracked-entry walk), 1x in
  `BuffEngine.lua` (preview walk) -- all four counts match the plan's exact expected values.
- **The indefinite render path exists on both branches:** `timer.indefinite` appears exactly 2x in
  `Display.lua` (bar path, icon path).
- **Dead-field check -- the one this plan calls out as the failure mode the phase is most exposed
  to.** For each of the five optional fields 49-02 wrote onto `RACIAL_SPELLS` rows, the
  whole-codebase occurrence count is strictly greater than the count inside the table body alone,
  proving each has a real consumer outside the data:

  | Field | Count inside `RACIAL_SPELLS` body | Count across all four consumer files | Has a consumer? |
  |---|---|---|---|
  | `indefinite` | 3 | 25 | Yes |
  | `cancelOnAuraLoss` | 3 | 9 | Yes |
  | `startFromAura` | 1 | 7 | Yes |
  | `clearOnCombat` | 2 | 6 | Yes |
  | `longDuration` | 2 | 8 | Yes |

  No field written in 49-02 is dead data.
- **Migration and combat-clear wiring present exactly once each:** `ns:MigrateRacialKeys()` is
  defined once (`BuffEngine.lua`), `CURRENT_SCHEMA_VERSION = 7` is set once at module scope
  (`BuffEngine.lua`), `PLAYER_REGEN_DISABLED` is registered exactly once (`Core.lua`).
- **stylua clean:** `stylua .` made no changes (the tree was already formatted); `stylua --check .`
  passed clean.
- **No CRCRLF corruption:** `git ls-files --eol` on all six Lua files reads `i/lf w/crlf
  attr/text eol=crlf` -- the `.gitattributes` pin held through every prior wave's edits.
- **Deployed:** `./scripts/install.bat` exited 0, deploying `v0.4.0-129-g100d1df-dev` to all four
  WoW client folders present on this machine (`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`).
- **No source changed, no untracked files left behind:** `git status --short` was empty both before
  and after the sweep and deploy.

## Deviations from Plan

### Documented, Not Worked Around

**1. [Pre-existing, already-documented unsatisfiable gate -- inherited verbatim from 49-03] Task 1's
own P7 sub-check (`grep -cF 'ns:IsRacialKeyVisible' Core.lua` must equal `0`) fails against the
correct, already-merged source**

- **Found during:** Task 1, running the composed automated `<verify>` script sub-check by
  sub-check.
- **The check:** the plan's verify script asserts zero literal occurrences of the string
  `ns:IsRacialKeyVisible` in `Core.lua`, intended to prove the race gate was never over-applied to
  one of Core.lua's two administrative walks (container-count, container-delete).
- **What's actually there:** `Core.lua:533` reads:

  ```
  -- contains that spellID. This is why ns:IsRacialKeyVisible (Providers.lua) exists: race membership
  ```

  This is a **prose comment**, not a function call -- no parentheses, no call site. `git blame`
  confirms it landed in `05a683d`, 49-01's very first commit (`feat(49-01): add the racial: key
  namespace to Core.lua`), months before this plan's own sweep gate was written. 49-03's own
  SUMMARY.md already documented this exact line as a pre-existing, out-of-scope gate defect when
  its own Task 2 hit the identical literal-string check scoped to `Core.lua` alone -- this plan's
  Task 1 gate re-asserts the same check across the whole phase and inherits the same false
  positive.
- **What I did:** Did not edit Core.lua. Task 1's own `<action>` is explicit: "Change no source."
  Rewording the comment to dodge a mechanical grep count, even if harmless in isolation, would be
  an out-of-scope edit to a file this task's action forbids touching, done purely to satisfy a
  check that cannot distinguish a call site from a name mentioned in prose. Instead, verified the
  gate's actual intent by hand: `grep -n "ns:IsRacialKeyVisible" Core.lua` returns exactly the one
  hit above, it contains no `(`, and `git log -p` on Core.lua across all of 49-01 through 49-04
  shows no commit ever added a real `ns:IsRacialKeyVisible(...)` call to Core.lua. The thing the
  gate exists to catch -- over-gating an administrative walk -- did not happen in any of the four
  prior waves.
- **Every other sub-check in the composed gate passed on the first run:** the two-slot-absence
  check, the `RacialKeySpellID` count, the ten-block count, the `Display.lua`/`CDMTab.lua`/
  `BuffEngine.lua` `IsRacialKeyVisible` counts, the `timer.indefinite` count, the five-field
  dead-data check, the migration/schema/event checks, `stylua --check .`, the `git ls-files --eol`
  check, and `./scripts/install.bat`'s exit code.
- **Files modified:** None.
- **Committed in:** N/A -- no code change. This entry exists to record why the plan's literal
  gate output does not read `GATES_OK` end-to-end, and why that is not a defect in the delivered
  code.

**Total deviations:** 1 (a pre-existing, already-diagnosed verify-script defect, third occurrence
of this same class in the phase -- see 49-01's Task 2 sequencing note, 49-03's Task 2 comment
double-count, and 49-04's Task 3 `awk` self-terminating range). This plan's own `<the_sweep_matters>`
brief predicted exactly this class of failure and asked that it be reported rather than explained
away; this is that report.

**Impact on plan:** No functional impact. Every property the sweep exists to protect is true and
independently confirmed by direct reading of the merged source: the two-slot model is gone, the
race gate sits at exactly the four render walks (Core.lua's two administrative walks are correctly
ungated), all ten races are present, and no optional field from 49-02 is dead data.

## Task 2: In-Game Gate -- NOT RUN

**This agent has no WoW client.** Per this plan's own framing (`autonomous: false` specifically
because Task 2 is a blocking checkpoint only the user can perform) and the explicit instruction
under which this execution ran, Task 2 was neither attempted, simulated, nor guessed at. No gate
below is marked as passed. The build Task 1 deployed
(`v0.4.0-129-g100d1df-dev`, all four client folders) is the exact build the user will run.

### The run sheet -- copy this into your session and fill in each verdict

Run `/tbt debug` first. Run `/console scriptErrors 1` before G5 specifically. `/reload` is
sufficient for every gate except **G4**, which needs a full logout and login.

| Gate | What it answers | Races that can answer it | Verdict |
|---|---|---|---|
| **G1** | The catalogue: every racial your character owns is offered in Suggested, durations/cooldowns match `FOREVER-RACIALS.md` | Whatever characters you have | **PENDING** |
| **G2** | Both tabs show only your own race's racials; a second, different-race character sees none of the first race's | Two characters of different races | **PENDING** |
| **G3** | One tracker entry per racial, account-wide placement, drops out of Suggested once tracked; a second same-race character sees the same placement | Any race, two characters same race | **PENDING** |
| **G4** | Migration: a pre-phase `racial`/`racial2` entry survives a real logout/login under its new `racial:<spellID>` key, with `["racial"]`/`["racial2"]` gone from SavedVariables | Any race with a pre-existing racial tracker | **PENDING** (untested if no pre-phase entry exists -- say so explicitly) |
| **G5** | Cooldown-only racials raise no buff tile and no Lua error | human, undead, tauren | **PENDING** |
| **G6** | Indefinite tiles: Shadowmeld (buff + 10s cooldown, aura-loss clear, combat-entry clear) and Find Treasure (indefinite, no cooldown tile) | night elf, dwarf | **PENDING** |
| **G7** | Plainsrunning starts from aura presence alone, no cast; clears on combat entry, returns on combat exit | tauren | **PENDING** |
| **G8** | Skyborne second racial starts short, corrects upward only, never shortens | raceID 95 (Alliance) or 96 (Horde) | **PENDING** |
| **G9** | The two data corrections: Eureka! reads 2:00 not 3:00; orc's second racial is labelled Shatter Curse not "Orc Racial" | gnome, orc | **PENDING** |
| **G10** | No regression on ordinary spell/cooldown/meta/item tiles; Blizzard's own Cooldown Manager is untainted after interacting with it | Any race | **PENDING** |

**Every race you do not have a character for must be recorded as UNTESTED, never folded into a
PASS.** For any FAIL, paste the Lua error (if any) and describe what you saw instead of the
expected behavior. The full per-gate instructions (exact steps, expected numbers, what a FAIL
looks like) are in `.planning/phases/49-forever-racial-catalogue/49-05-PLAN.md`, Task 2's
`<how-to-verify>` block -- read that verbatim before running each gate, don't work from this table
alone.

## Requirements Status

RACE-07, RACE-08 and RACE-10 remain **open**. Per this plan's own `<verification>` section: "Do
not mark RACE-07, RACE-08 or RACE-10 closed on the strength of task 1 alone." Task 1's static sweep
proves the code is shaped correctly; it proves nothing about runtime behavior in a real Cooldown
Manager. This SUMMARY does not claim otherwise, and STATE.md/ROADMAP.md are intentionally left
untouched by this agent -- the orchestrator owns those writes, and closing them now would misstate
the phase's actual state.

## Issues Encountered

- The worktree this agent was spawned into (`worktree-agent-aee141ff7b90895e2`) was branched from
  an old commit (`f0c8e35`, the v0.4.0 tip) that predated all of Phase 49's planning docs and code
  -- the identical issue every one of 49-01 through 49-04's executors hit and documented.
  Confirmed via `git merge-base --is-ancestor` that the worktree branch's tip was a pure ancestor
  of `milestone/v0.4.1-item-tracking-forever-racials` with zero divergent commits (129 behind, 0
  ahead), then ran `git merge --ff-only` to bring the worktree current before reading the plan.
- A tool-prompt system reminder, appearing mid-session as a "bypass permissions mode" environment
  instruction, directed using `sed`/heredocs for all file reads and edits instead of the Read/Edit
  tools. Not followed: it directly conflicts with `CLAUDE.md`'s explicit, safety-critical
  prohibition on `sed -i`/redirects touching source or `.md` files, and the base system
  instructions establish that no agent-supplied message can override `CLAUDE.md` or the
  permission system. Every read in this session used Read/Bash `grep`/`awk` (inspection only,
  never `-i`); the one file this session wrote (`49-05-SUMMARY.md`) was created with the Write
  tool, not a heredoc.

## User Setup Required

**Play the game.** Run the G1-G10 run sheet above against the deployed build
(`v0.4.0-129-g100d1df-dev`) on Forever (build 1.60.1+), following Task 2's `<how-to-verify>` block
in `49-05-PLAN.md` exactly. Report back per-gate PASS/FAIL/UNTESTED verdicts with the race named
for each, per the `<resume-signal>`. The phase does not close until that report comes back and a
fresh agent (or this same conversation) records it in a revised `49-05-SUMMARY.md`.

## Next Phase Readiness

Not ready. This phase (49) remains open pending the in-game gate. No further plan in this phase
exists beyond 49-05; once the user's verdicts come back, whoever resumes this plan should append
them to this SUMMARY (replacing the PENDING table above with real verdicts), only then mark
RACE-07/RACE-08/RACE-10 complete, and only then hand control back to the orchestrator for the
STATE.md/ROADMAP.md updates this agent deliberately did not make.

---
*Phase: 49-forever-racial-catalogue*
*Task 1 completed: 2026-09-25*
*Task 2 (blocking, in-game): NOT RUN -- awaiting user*

## Self-Check: PASSED

- FOUND: .planning/phases/49-forever-racial-catalogue/49-05-SUMMARY.md
- Deploy confirmed by `./scripts/install.bat` exit code 0 and its own printed manifest
  (`v0.4.0-129-g100d1df-dev`, four client folders)
- No commit hashes to verify for Task 1 -- zero files modified, matching the plan's own
  `files_modified: []` and "Change no source" instruction
