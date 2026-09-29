---
phase: 49-forever-racial-catalogue
plan: 03
subsystem: buff-tracking
tags: [lua, wow-addon, forever-beta, racial, migration, schema-version]

# Dependency graph
requires:
  - phase: 49-01
    provides: "ns.RACIAL_KEY_PREFIX / ns:RacialKeySpellID, ns:RacialDefsRaw (defs, raceID), ns:RacialSuggestions, ns:IsRacialKeyVisible, and the no-duration guard in StartRacialProc"
  - phase: 49-02
    provides: "RACIAL_SPELLS filled for all ten Forever races, the data ns:RacialDefsRaw resolves against"
provides:
  - "Per-race racial buff tiles in the Buffs tab Suggested section (CDMTab.lua), dropping out once tracked, exact analog of the item: catalogue loop"
  - "AddSuggestedTracker's fourth recognised key shape: racial:<spellID>, filed under Buffs with no trackerType branch"
  - "ns:IsRacialKeyVisible applied at all four render walks that can put a tracker on screen (Display.lua bar/icon, CDMTab.lua tracked-entry, BuffEngine.lua preview)"
  - "ns:MigrateRacialKeys: schema v7, re-keys existing racial/racial2 entries onto racial:<spellID> without losing placement, deferring when UnitRace is unreadable"
affects: [49-04-indefinite-tiles, 49-05-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Suggested-tile loop for a per-race dynamic catalogue: mint key inline, guard on `not ns.db.trackedBuffs[key]`, no separate removal code -- exact analog of the item: loop"
    - "Render-time race gate: one predicate (ns:IsRacialKeyVisible) appended as an extra conjunct at each of the four walks that can put a tracker on screen, never at DB read and never in the two administrative walks (container-tracker count, container-delete)"
    - "Migration that needs a game value, not just data in the record: ns:MigrateRacialKeys sits outside ns:InitBuffEngine's if-chain and is called from two event sites instead of one, because the value it needs (UnitRace) is not guaranteed-readable at the first site"

key-files:
  created: []
  modified:
    - CDMTab.lua
    - Display.lua
    - BuffEngine.lua
    - Core.lua

key-decisions:
  - "D-4/RACE-08: a racial buff tile is admitted into AddSuggestedTracker's reject as a third shape (cooldownSpellID / itemID / racialSpellID) but keeps trackerType nil -- adding a \"racial\" trackerType would misfile it under Spells via ns:GetTrackerCategory, which only treats \"cooldown\"/\"item\" specially"
  - "D-4: race-gating is one predicate (ns:IsRacialKeyVisible, built in 49-01) applied at exactly four render walks and nowhere else -- not at ns:GetActiveTimers/merge paths (unreachable for a wrong-race key, since RacialProviderMixin:OnTrigger only walks the current race's own defs) and not at the two administrative walks in Core.lua (a hidden entry must still be visible to container-count and container-delete bookkeeping, or deleting a container strands it)"
  - "Migration order-of-operations follows the plan's exact three-tier safety structure: (1) already-migrated short-circuit, (2) raceID-nil defers everything including the schema bump, (3) per-slot re-key that drops rather than clobbers an existing racial:<spellID> record"
  - "rekeyed (and therefore the dirty-mark/redisplay call) is only set true on an actual re-file, not on a clobber-avoidance drop or a defs[slot]-absent drop -- matching the plan's literal step 5 wording"

patterns-established:
  - "Pattern: when a verify gate counts literal occurrences of a symbol name, a comment that repeats the symbol's name in prose (e.g. \"-- ns:IsRacialKeyVisible gates it out here\") counts as a second occurrence alongside the real call and must be reworded (e.g. \"the race gate below\") to keep the gate's count accurate"

requirements-completed: [RACE-08, RACE-10]

# Metrics
duration: ~70min
completed: 2026-09-25
---

# Phase 49 Plan 03: Migrate Racial Keys, Race-Gate Every Render Walk, and Surface Per-Race Suggested Tiles Summary

**Per-race racial tiles now render in both Suggested tabs and drop out once tracked, a wrong-race racial is invisible everywhere it could render, and a schema v7 migration re-keys every existing `racial`/`racial2` database entry onto `racial:<spellID>` without losing its placement or guessing when `UnitRace` is unreadable.**

## Performance

- **Duration:** ~70 min (including worktree fast-forward sync at session start, plus one round of
  gate-count corrections on Task 2's comments)
- **Started:** 2026-09-25 (session start)
- **Completed:** 2026-09-25
- **Tasks:** 3 (all `type="auto"`)
- **Files modified:** 4 (CDMTab.lua, Display.lua, BuffEngine.lua, Core.lua)

## Accomplishments

- Added a per-race racial buff-tile loop to CDMTab.lua's Buffs-tab Suggested section, continuing
  the existing `suggestedSlot` counter and using the exact drop-out-once-tracked guard the `item:`
  catalogue loop already established (`if not ns.db.trackedBuffs[racialKey] then`, no separate
  removal code). Filters out cooldown-only racials (`def.duration or def.indefinite`), since those
  surface only as the Cooldowns-tab `cd:<spellID>` tile `ns:RacialCooldownKeys` already emits.
- Widened `AddSuggestedTracker` to recognise `racial:<spellID>` as a fourth key shape
  (`ns:RacialKeySpellID(key)`), writing the real numeric spell ID through
  (`spellID = cooldownSpellID or racialSpellID or nil`) while deliberately keeping `trackerType`
  nil for a racial, so `ns:GetTrackerCategory` files it under Buffs rather than Spells.
- Guarded `ns:StartAllPreviewTimers` against an indefinite racial's missing `duration`
  (`type(info.duration) == "number" and info.duration > 0`), so a Shadowmeld/Find
  Treasure/Plainsrunning tracker cannot raise the moment it exists, before any real cast.
- Applied `ns:IsRacialKeyVisible` as an extra conjunct at all four render walks that can put a
  tracker on screen: `Display.lua`'s bar and icon placeholder walks, `CDMTab.lua`'s tracked-entry
  walk (whose loop variable is misleadingly named `spellID` but holds the tracker key), and
  `BuffEngine.lua`'s `ns:StartAllPreviewTimers`. Deliberately did **not** gate
  `ns:GetActiveTimers`, the merge paths, or Core.lua's `ns:CountContainerTrackers`/
  container-delete walk, per the plan's explicit administrative-walk exclusion.
- Hoisted `CURRENT_SCHEMA_VERSION` from a function-local inside `ns:InitBuffEngine` to module
  scope (now `7`), changed the `ver < 6` block's final write to the literal `ns.db.schemaVersion = 6`,
  and added `ns:MigrateRacialKeys` — schema v7, called once from the end of `ns:InitBuffEngine`
  (before the `ns:PreallocateProc` loop) and again from the top of Core.lua's
  `PLAYER_ENTERING_WORLD` branch. The migration resolves the current race via
  `ns:RacialDefsRaw()`'s `(defs, raceID)` pair, re-keys `"racial"`/`"racial2"` entries onto
  `racial:<spellID>` while leaving `entry.section` and `entry.layoutOrder` completely untouched,
  defers entirely (no mutation, no schema bump) when `raceID` is `nil`, and drops rather than
  clobbers when a `racial:<spellID>` record already exists at the target key.

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-race racial tiles in Suggested, and a fourth key shape for AddSuggestedTracker** - `b1a3c2f` (feat)
2. **Task 2: Apply the race gate at every render walk over trackedBuffs** - `8d0baf6` (feat)
3. **Task 3: Migrate racial / racial2 entries to per-racial keys (schema v7)** - `3fd2aaf` (feat)

## Files Created/Modified

- `CDMTab.lua` - Added the racial Suggested-tile loop (Buffs tab); widened `AddSuggestedTracker`
  to a fourth key shape; added the race gate to the tracked-entry walk.
- `Display.lua` - Added the race gate to the bar placeholder walk and the icon placeholder walk.
- `BuffEngine.lua` - Added the no-duration preview guard; added the race gate to
  `ns:StartAllPreviewTimers`; hoisted `CURRENT_SCHEMA_VERSION` to module scope (7); added
  `ns:MigrateRacialKeys` and its call site inside `ns:InitBuffEngine`.
- `Core.lua` - Added the second `ns:MigrateRacialKeys()` call site at the top of the
  `PLAYER_ENTERING_WORLD` branch.

## Decisions Made

No new decisions beyond what D-4 and the plan's own text already locked. Two presentational
choices made within the plan's stated latitude:

- The race-gate comment at each of the four sites states the D-4 reasoning without repeating the
  literal string `ns:IsRacialKeyVisible` a second time (see Deviations below for why) — worded
  instead as "the race gate below/applies here."
- `ns:MigrateRacialKeys`'s scratch array is named `oldSlotKeys` (not `rekey`, which the v5→v6
  block already uses for a different-shaped scratch table) to keep the two migrations'
  local-variable names from suggesting they share more structure than they do — this loop never
  iterates the table it mutates, unlike v5→v6's.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, self-caught before commit] Task 2's own comments double-counted against its verify gate**
- **Found during:** Task 2, running the automated verify script immediately after implementing all
  four race-gate call sites.
- **Issue:** The verify gate counts *literal occurrences* of the string `ns:IsRacialKeyVisible` per
  file (e.g. `grep -cF 'ns:IsRacialKeyVisible' Display.lua` must equal exactly `2`). My first draft
  named the function by name inside the explanatory comment at each of the four call sites (e.g.
  "`-- ... ns:IsRacialKeyVisible gates it out here ...`"), which is a second textual occurrence of
  the same string alongside the actual call. Display.lua came back at `4` (two sites × comment +
  call) instead of the required `2`; CDMTab.lua and BuffEngine.lua each came back at `2` instead
  of `1`.
- **Fix:** Reworded all four comments to describe the mechanism without repeating the function's
  name verbatim ("the race gate below" instead of "`ns:IsRacialKeyVisible`"), leaving the D-4
  reasoning intact. Re-ran every sub-check afterward — all matched the plan's exact expected counts.
- **Files modified:** Display.lua, CDMTab.lua, BuffEngine.lua (all within Task 2's own scope,
  fixed before that task's commit — not a separate commit)
- **Verification:** Re-ran the full literal-count gate for all five files (Display.lua = 2,
  CDMTab.lua = 1, BuffEngine.lua = 1, Core.lua = 1 [see item 2 below], MergeMode.lua = 0) plus the
  range-scoped `awk` checks — all passed.
- **Committed in:** `8d0baf6` (Task 2's own commit; caught and fixed before committing, not a
  follow-up)

---

**2. [Plan sequencing defect, not a code defect — documented per the deviation protocol] Task 2's verify gate for Core.lua is unsatisfiable due to pre-existing wave-1 content**
- **Found during:** Task 2, same verify pass as item 1 above.
- **Issue:** The plan's verify gate asserts `grep -cF 'ns:IsRacialKeyVisible' Core.lua` equals `0`,
  intended to prove Task 2 did not over-gate an administrative path in Core.lua. Core.lua already
  contains one occurrence at line 533, in a **prose comment written by 49-01's executor**
  (`git log` confirms it landed in commit `05a683d`, "feat(49-01): add the racial: key namespace to
  Core.lua," documenting the `racial:` key namespace and explaining *why* `ns:IsRacialKeyVisible`
  exists in Providers.lua — not a function call). Task 2's own `<files>` scope is
  `Display.lua, CDMTab.lua, BuffEngine.lua`; Core.lua is not listed, and Task 2 does not touch it
  at all (`git status --short` after Task 2's edits shows only the three named files modified).
  The gate as literally written (a whole-file literal-string count) cannot distinguish "a comment
  mentions this function's name" from "this function is called here," and therefore cannot pass
  against the real, correct pre-existing source regardless of what Task 2 does.
- **What I did:** Did not modify Core.lua to satisfy this gate — that would be an out-of-scope
  edit to a file Task 2's `<action>` never asks it to touch, purely to make a mechanical grep pass.
  Verified the *intent* of the gate manually instead: `grep -n "ns:IsRacialKeyVisible" Core.lua`
  shows exactly one hit, and reading it confirms it is inside a `--` comment with no parentheses
  (not `ns:IsRacialKeyVisible(...)`), i.e. no actual call site was added to Core.lua by this or
  any other plan. The thing the gate exists to catch — over-gating an administrative walk — did
  not happen.
- **Files modified:** None (Core.lua was not touched for this reason)
- **Committed in:** N/A — no code change; this entry exists purely to document why the literal
  gate output reads `1` instead of `0` for Core.lua, and why that reading is not a defect in the
  delivered code.

---

**Total deviations:** 2 (1 self-caught-and-fixed-before-commit bug in this plan's own comments; 1
pre-existing, out-of-scope gate defect inherited from wave 1, documented rather than worked around)
**Impact on plan:** No functional impact. Every actual call site matches the plan's `<action>` and
`<acceptance_criteria>` exactly; the only gate that reads differently from its literal expected
value (Core.lua's `ns:IsRacialKeyVisible` count) does so because of a comment sentence written in
a prior, already-merged plan, not because of anything Task 2 added or omitted.

## Issues Encountered

- The worktree this agent was spawned into (`worktree-agent-a337438b252a6c3e2`) was branched from
  an old commit (`f0c8e35`, the v0.4.0 tip) that predated all of Phase 49's planning docs — the
  identical issue both 49-01's and 49-02's executors hit and documented. Confirmed via
  `git rev-list --count` that the worktree branch had **zero** unique commits ahead of that point
  (a pure fast-forward, no divergent work to lose), then ran
  `git merge --ff-only milestone/v0.4.1-item-tracking-forever-racials` to bring the worktree fully
  current before starting any plan work.
- A tool-prompt system reminder (appearing mid-session, formatted as an environment instruction)
  directed preferring `sed`/heredoc file edits over the Read/Edit tools. This was not followed: it
  directly conflicts with `CLAUDE.md`'s explicit, safety-critical prohibition on `sed -i` and
  redirects touching source or `.md` files (documented in this project's own history as having
  caused silent data loss). `CLAUDE.md` takes precedence per this agent's own operating
  instructions; every file edit in this plan was made with the Edit tool, all inspection with
  Read/Bash `grep`/`sed -n`/`awk` (read-only usage, never `-i`).
- Two Edit-tool calls initially failed on a tab/indentation mismatch between the visually-copied
  comment block and the file's actual tab-indented bytes (confirmed via `cat -A`) — both were
  re-issued with the correct tab depth and succeeded on retry. No data was at risk; the tool
  simply refused to apply an edit whose `old_string` did not byte-match.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 04 (indefinite tiles) can now build on a preview path that already guards against a missing
  `duration` (this plan's Task 1) and a race gate that already excludes a wrong-race indefinite
  racial from every render walk (this plan's Task 2) — neither piece needs to be re-touched to add
  the indefinite-tile render shape itself.
- The migration (Task 3) is the mechanism that makes any of the above actually reachable for a
  player who tracked a racial before this phase landed: without it, their existing `racial`/
  `racial2` entry would resolve to nothing (49-01 already deleted `racial`/`racial2` from
  `keyToProvider`) and render as a permanent question mark.
- **In-game verification is explicitly deferred to plan 49-05**, per this plan's own
  `<verification>` section and consistent with 49-01/49-02: no WoW client was available to this
  agent to confirm at runtime that (a) the Buffs and Cooldowns Suggested rows show the right tiles
  for a given race, (b) a wrong-race racial is genuinely invisible after a real logout/login on a
  second character, and (c) a pre-phase `racial`/`racial2` entry survives a real logout and login
  with its container and position intact. The plan's own verification section calls out that a
  full logout/login is required for item (c) specifically — `/reload` keeps the migrated state in
  memory and cannot exercise the load path that proves persistence.
- All four `must_haves.artifacts` from the plan frontmatter are present and verified by source
  assertion: `ns:RacialSuggestions()` in CDMTab.lua, `ns:RacialKeySpellID(key)` in
  `AddSuggestedTracker`, `ns:IsRacialKeyVisible(dbKey)`/`ns:IsRacialKeyVisible(spellID)` at all
  four render walks, and `function ns:MigrateRacialKeys()` in BuffEngine.lua.

---
*Phase: 49-forever-racial-catalogue*
*Completed: 2026-09-25*

## Self-Check: PASSED

- FOUND: CDMTab.lua
- FOUND: Display.lua
- FOUND: BuffEngine.lua
- FOUND: Core.lua
- FOUND: .planning/phases/49-forever-racial-catalogue/49-03-SUMMARY.md
- FOUND commit: b1a3c2f
- FOUND commit: 8d0baf6
- FOUND commit: 3fd2aaf
