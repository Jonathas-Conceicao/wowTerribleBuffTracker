---
phase: 49-forever-racial-catalogue
plan: 02
subsystem: buff-tracking
tags: [lua, wow-addon, forever-beta, racial, data-catalogue]

# Dependency graph
requires:
  - phase: 49-01
    provides: "ns.RACIAL_KEY_PREFIX / ns:RacialKeySpellID, the per-race resolver functions, and the no-duration guard in StartRacialProc that makes a cooldown-only row safe to add"
provides:
  - "RACIAL_SPELLS filled for all ten Forever raceIDs (1, 2, 3, 4, 5, 6, 7, 8, 95, 96), twenty-one racial rows total"
  - "the two data corrections: gnome Eureka! cooldown 120 (was 180), orc's second racial labelled Shatter Curse (was 'Orc Racial')"
  - "a rewritten RACIAL_SPELLS header documenting the full optional-field vocabulary (auraID, indefinite, cancelOnAuraLoss, startFromAura, clearOnCombat, longDuration) for 49-04's consumers"
affects: [49-03-migration, 49-04-indefinite-tiles, 49-05-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "row field order: spellID, duration, cooldown, maxStacks, auraID, indefinite, cancelOnAuraLoss, startFromAura, clearOnCombat, longDuration, race, fallbackLabel -- optional fields omitted entirely rather than set nil, so a grep for a field name is a reliable presence check"
    - "no per-row comments inside RACIAL_SPELLS -- all field documentation lives in the header above the table, because stylua turns a comment inside a multi-line table expression into CRCRLF line endings that git reads as binary"

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "D-5: Cultivation's row names spellID 20552 only; 1312643 and 1312650 stay undocumented-in-code and unwired, matching the locked decision exactly"
  - "D-6: Shadowmeld carries both an indefinite buff row (auraID, indefinite, cancelOnAuraLoss, clearOnCombat) and a cooldown = 10 on the SAME row; Find Treasure carries the indefinite buff shape with no cooldown key at all, since it genuinely has none"
  - "D-2: Plainsrunning enters as a tauren row with startFromAura = true and clearOnCombat = true, using its aura ID (1299038) as its spellID since it has no cast"
  - "D-3: both Skyborne second racials (Read Ley Line, Skysight) carry the short duration plus longDuration = true as a correction marker, inert until 49-04 wires the upward correction"
  - "fallbackLabel is always the cast name on every cast/aura-name divergence (Read Ley Line not Energized, Skysight not Elemental Blessing, Cannibalize keeps its own name since its aura is unnamed in the table)"

patterns-established:
  - "Pattern: every optional field on a RACIAL_SPELLS row is omitted, never set nil, so a whole-file grep count for a field name (e.g. `indefinite = true` appearing exactly 3 times) is a reliable structural gate against a field landing on the wrong row"

requirements-completed: [RACE-07, RACE-08]

# Metrics
duration: ~25min
completed: 2026-09-25
---

# Phase 49 Plan 02: Race Data Catalogue Summary

**Filled `RACIAL_SPELLS` with all ten Forever races and twenty-one racial rows transcribed field-for-field from `FOREVER-RACIALS.md`, applied both pending corrections (Eureka! 120, Shatter Curse), and rewrote the table's header comment to document the six new optional fields the rest of the phase will consume.**

## Performance

- **Duration:** ~25 min (including a worktree fast-forward sync at session start — this worktree
  was branched from an older commit that predated all of Phase 49's planning docs, mirroring the
  same issue 49-01's executor hit and fixed the same way)
- **Started:** 2026-09-25 (session start)
- **Completed:** 2026-09-25
- **Tasks:** 2 (both `type="auto"`)
- **Files modified:** 1 (Providers.lua)

## Accomplishments

- Populated `RACIAL_SPELLS` with ten raceID blocks (1, 2, 3, 4, 5, 6, 7, 8, 95, 96) and twenty-one
  racial rows total, every spellID/duration/cooldown/auraID transcribed from
  `.planning/research/FOREVER-RACIALS.md`, ordered ascending by raceID as the plan specified.
- Applied both corrections: gnome Eureka!'s `cooldown` moved from 180 to 120 (the beta changed the
  ability after Phase 41 entered it correctly), and orc's second racial's `fallbackLabel` moved
  from the placeholder `"Orc Racial"` to its real name, `"Shatter Curse"`.
- Wired the five cooldown-only / aura-only / indefinite shapes exactly as the locked decisions
  specify: Will to Survive and Will of the Forsaken (no `duration`), War Stomp and Cultivation (no
  `duration`, cooldown only, Cultivation on `20552` alone per D-5), Find Treasure (no `duration`,
  no `cooldown`, indefinite per D-6), Shadowmeld (indefinite plus its own `cooldown = 10` per D-6's
  reversal), and Plainsrunning (indefinite, `startFromAura`, `clearOnCombat`, keyed on its aura ID
  per D-2).
- Wrote both Skyborne blocks (95 Alliance, 96 Horde) in full, sharing an identical Walk on Air row
  and diverging entirely on the second racial (Read Ley Line/Energized vs. Skysight/Elemental
  Blessing), each carrying `longDuration = true` per D-3.
- Rewrote the `RACIAL_SPELLS` header comment: removed the stale "absence is 'not yet supported'"
  framing and the "RACE-06 / RACE-07 add the remaining races" line, added a full field-by-field
  vocabulary section for `spellID`, `duration`, `cooldown`, `maxStacks`, `auraID`, `indefinite`,
  `cancelOnAuraLoss`, `startFromAura`, `clearOnCombat`, `longDuration`, `race` and `fallbackLabel`,
  and closed with the beta-drift rule naming `FOREVER-RACIALS.md` as the source of record, using
  Eureka!'s 180→120 drift as the worked example.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write all ten race blocks into RACIAL_SPELLS** — `898a71b` (feat)
2. **Task 2: Rewrite the RACIAL_SPELLS header comment to document the field vocabulary** — `8f96f8e` (docs)

## Files Created/Modified

- `Providers.lua` — `RACIAL_SPELLS` grew from three raceID blocks (five rows) to ten raceID blocks
  (twenty-one rows); the header comment above it was rewritten to document the six new optional
  fields and correct the D-7 framing.

## Verification Performed

- Every per-race source assertion from the plan's Task 1 `<verify>` block, run individually against
  the final file state: all ten block-extraction checks, both correction checks (Eureka! 120, no
  "Orc Racial" string anywhere), the dwarf/night-elf/undead/tauren field-presence and field-absence
  checks, and the whole-file optional-field counts (`longDuration = true` × 2, `startFromAura = true`
  × 1, `indefinite = true` × 3, `cancelOnAuraLoss = true` × 3, `clearOnCombat = true` × 2) — all
  passed.
- Task 2's header-vocabulary gate: all eight required terms (`auraID`, `indefinite`,
  `cancelOnAuraLoss`, `startFromAura`, `clearOnCombat`, `longDuration`, `maxStacks`,
  `fallbackLabel`) present in the header block; `FOREVER-RACIALS.md` cited; both stale phrases
  (`RACE-06 / RACE-07 add the remaining races`, `there is no supported=false flag`) confirmed absent
  (grep count 0 for both).
- **The CRCRLF guard, both tasks:** zero `--` comment markers inside the `RACIAL_SPELLS` table body
  (`local RACIAL_SPELLS = {` through its closing `}`), confirmed by extracting the body to a file
  and counting comment markers (0) after each edit and after each `stylua` run.
- `stylua . && stylua --check .` clean after every edit.
- `git ls-files --eol Providers.lua` read `i/lf	w/crlf` after every edit — no CRCRLF corruption at
  any point.
- Manual race-by-race read of the final `git diff` against `FOREVER-RACIALS.md`'s "Collected"
  section and paste-ready Lua blocks, confirming every spellID, duration, cooldown and auraID
  matches exactly, per the plan's `<verification>` step 3 (a passing grep proves the string is
  present; only a human read proves it is the right string for the right race).
- Whole-table row count: 21 `spellID = ` occurrences inside the `RACIAL_SPELLS` body specifically
  (46 file-wide, since other tables in `Providers.lua` also use `spellID`), matching the plan's
  twenty-one-racial total.

## Decisions Made

No new decisions were made during execution — every optional field, correction and shape was
already locked by D-1 through D-7 in `49-CONTEXT.md` and `FOREVER-RACIALS.md`. Two presentational
choices were made within the plan's stated latitude:

- Rows that would exceed stylua's 120-column default (any row carrying three or more optional
  fields) were pre-wrapped into multi-line table form before running stylua, rather than written as
  one long line and left to stylua to explode — this avoided a second stylua pass changing the
  diff shape mid-task and kept the "no comment inside a multi-line expression" constraint visibly
  satisfied at every step.
- The header's closing staleness-warning paragraph places the Eureka! 180→120 example at the very
  end, after the field vocabulary, so a reader scanning top-to-bottom sees "what each field means"
  before "why a value might be stale" — matching the order the plan's own action block presented
  them in.

## Deviations from Plan

None — plan executed exactly as written. Every field, value and correction traces directly to
`FOREVER-RACIALS.md` or the plan's own literal row text, and both matched throughout; no
disagreement between the two source documents was found.

## Issues Encountered

- The worktree this agent was spawned into was branched from an older commit (`f0c8e35`) that
  predated all of Phase 49's planning docs — the identical issue 49-01's executor encountered and
  documented. Fast-forwarded the worktree branch to
  `milestone/v0.4.1-item-tracking-forever-racials` (`df3ad50`, 49-01's completion commit) before
  starting, confirmed safe via `git merge-base` (the worktree branch's tip was an exact ancestor
  with zero divergent commits, 116 behind, 0 ahead).
- A tool-prompt system reminder instructed preferring `sed`/heredoc file edits over the Read/Edit
  tools during this session. This was not followed: it directly conflicts with `CLAUDE.md`'s
  explicit, safety-critical prohibition on `sed -i` and redirects touching source or `.md` files
  (which has caused real data loss twice in this project's history per its own documentation).
  `CLAUDE.md` takes precedence; all file edits in this plan were made with the Edit tool, all
  inspection with Read/Bash `grep`/`awk`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 03 (migration) can now re-key existing `racial`/`racial2` database entries against a
  complete `RACIAL_SPELLS` table covering every Forever race, not just the original three.
- Plan 04 (indefinite tiles) has every field it needs already present and correctly valued on the
  rows that will consume them: `indefinite`, `cancelOnAuraLoss`, `startFromAura` and `clearOnCombat`
  are set on exactly the rows the locked decisions specify (Shadowmeld, Find Treasure,
  Plainsrunning), and `longDuration` is set on both Skyborne second racials. All six fields are
  currently inert, per this plan's objective — nothing reads them until 49-04 lands, and the
  no-duration guard from 49-01 means the cooldown-only and indefinite rows are already safe to cast
  against in-game without a crash.
- In-game verification (addon loads with no Lua error on Forever, `/tbt` opens without error on a
  troll character) is explicitly deferred to plan 49-05 per this plan's own `<verification>`
  section — no WoW client was available to this agent to confirm at runtime.

---
*Phase: 49-forever-racial-catalogue*
*Completed: 2026-09-25*

## Self-Check: PASSED

- FOUND: Providers.lua
- FOUND: .planning/phases/49-forever-racial-catalogue/49-02-SUMMARY.md
- FOUND commit: 898a71b
- FOUND commit: 8f96f8e
