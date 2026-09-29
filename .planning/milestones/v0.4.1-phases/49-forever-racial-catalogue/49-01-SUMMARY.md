---
phase: 49-forever-racial-catalogue
plan: 01
subsystem: buff-tracking
tags: [lua, wow-addon, forever-beta, racial, provider-pattern]

# Dependency graph
requires:
  - phase: 46-item-catalogue-suggested-tiles
    provides: "the item:<itemID> key namespace precedent this plan copies for racial:<spellID>"
  - phase: 47-item-tracking-cooldown-sharing
    provides: "ns:GetDisplayInfoForKey's dynamic-key branch ordering (item: before the cd: reject)"
provides:
  - "ns.RACIAL_KEY_PREFIX / ns:RacialKeySpellID (Core.lua): the racial: key namespace"
  - "ns:RacialDefsRaw / ns:RacialDefsForPlayer / ns:RacialSuggestions / ns:RacialDefForSpellID / ns:IsRacialKeyVisible (Providers.lua)"
  - "the no-duration guard in StartRacialProc, load-bearing for plan 02's cooldown-only racial rows"
  - "RacialProviderMixin dispatching per spellID key instead of two fixed slots"
affects: [49-02-race-data-catalogue, 49-03-migration, 49-04-indefinite-tiles, 49-05-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "racial:<spellID> key namespace, exact analog of item:<itemID> (Core.lua) -- prefix constant + anchored parser, no constructor, keys minted inline"
    - "O(1) reverse-ownership index (racialSpellOwners) built once at file load for a render-path membership predicate"
    - "raw vs. display-ready split (ns:RacialDefsRaw vs ns:RacialDefsForPlayer) so a render-time predicate never depends on a C_Spell-backed memo that can still be empty"

key-files:
  created: []
  modified:
    - Core.lua
    - Providers.lua
    - BuffEngine.lua

key-decisions:
  - "D-4/RACE-10: one tracker entry per racial, keyed racial:<spellID>, replacing the fixed racial/racial2 slots"
  - "D-7/RACE-09: obsolete -- RACIAL_SUPPORTED_LINES/RACIAL_UNSUPPORTED_LINES deleted as dead code, no replacement tooltip"
  - "ns:RacialDefsRaw returns (defs, raceID) rather than defs alone, so 49-03's migration can distinguish 'no racial here' from 'race unreadable'"
  - "The Forever offer gate (ns.CLIENT_IS_FOREVER) moved from BuffEngine.lua's SUGGESTED_KEYS append into ns:RacialSuggestions(), the single place both the buff and cooldown offer paths now read through"

patterns-established:
  - "Pattern: a render-time membership predicate (ns:IsRacialKeyVisible) reads the RAW def list, never the C_Spell-resolved one, so it cannot depend on a memo that may still be empty this session"
  - "Pattern: sticky memoisation of an immutable per-character fact (raceID) is kept separate from memoisation of a derived, spell-data-dependent list (the resolved defs), so an early unreadable call retries instead of poisoning a downstream cache"

requirements-completed: [RACE-07, RACE-10]

# Metrics
duration: ~65min
completed: 2026-09-25
---

# Phase 49 Plan 01: Racial Key Namespace and Per-Race Resolver Summary

**Replaced the two-slot `racial`/`racial2` racial model with a `racial:<spellID>` key namespace, five new `ns:` resolver functions, and a no-duration guard in `StartRacialProc` — the addressing and safety layer plans 02-05 build on.**

## Performance

- **Duration:** ~65 min (including worktree fast-forward sync, which was itself part of this session)
- **Started:** 2026-09-25T00:25:00-03:00 (approx, worktree sync)
- **Completed:** 2026-09-25T00:40:03-03:00
- **Tasks:** 3 (all `type="auto"`)
- **Files modified:** 3 (Core.lua, Providers.lua, BuffEngine.lua)

## Accomplishments
- Added the `racial:` key namespace to Core.lua (`ns.RACIAL_KEY_PREFIX`, `ns:RacialKeySpellID`), the fourth namespace in `ns.db.trackedBuffs` alongside bare-numeric buffs, `cd:` and `item:`.
- Replaced the fixed two-slot racial resolver (`RACIAL_SLOT_BY_KEY`, `ns.RACIAL_KEYS`, `ResolveRacial(slot)`) with five `ns:`-level accessors resolving per-race, per-spellID: `ns:RacialDefsRaw`, `ns:RacialDefsForPlayer`, `ns:RacialSuggestions`, `ns:RacialDefForSpellID`, `ns:IsRacialKeyVisible`.
- Deleted D-7's dead tooltip constants (`RACIAL_SUPPORTED_LINES`, `RACIAL_UNSUPPORTED_LINES`) and the now-unreachable `RacialProviderMixin:HasResolvableCatalog` RACE-01 override.
- Added the no-duration guard to `StartRacialProc` (`if not def.duration then return nil end`), which plan 02 depends on before any cooldown-only racial row (Will of the Forsaken, Will to Survive, War Stomp, Cultivation) can be entered without crashing on first cast.
- Rewrote `RacialProviderMixin:OnTrigger`, `ConsumeRacialStack` and `RacialProviderMixin:GetDisplayInfo` to dispatch per spellID key (`ns.RACIAL_KEY_PREFIX .. def.spellID`) instead of iterating two fixed slots.
- Added a racial branch to `ns:GetDisplayInfoForKey`, positioned before the `CooldownKeySpellID` reject (same ordering rule as the existing `item:` branch), so a `racial:` key cannot fall through to a permanent question-mark placeholder.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the racial: key namespace to Core.lua** - `05a683d` (feat)
2. **Task 2: Replace the two-slot racial resolver with per-race resolvers and delete D-7's dead code** - `4667ae2` (feat)
3. **Task 3: Rewrite RacialProviderMixin for per-key dispatch and add the no-duration guard** - `66ca5c8` (feat)

_Note: Tasks 2 and 3 were authored and verified together (see Deviations below), then split into two commits along the plan's task boundaries using `git apply --cached` on hand-partitioned hunks, so each commit's diff matches its task's declared file scope exactly._

## Files Created/Modified
- `Core.lua` - Added `ns.RACIAL_KEY_PREFIX` / `ns:RacialKeySpellID`, the fourth DB key namespace.
- `Providers.lua` - Replaced the two-slot racial resolver and `RacialProviderMixin` internals; added the no-duration guard; added a racial branch to `ns:GetDisplayInfoForKey`; deleted dead D-7 constants and the unreachable RACE-01 override.
- `BuffEngine.lua` - Removed the `ns.CLIENT_IS_FOREVER`-gated `SUGGESTED_KEYS` append for `"racial"`/`"racial2"` (offer now comes from `ns:RacialSuggestions()`); reworded the `ns:AcquireProc` pooled-table comment to record that setting `aliveBuffs` on a racial proc deliberately (plan 04) is safe.

## Decisions Made
- Key format: `racial:<spellID>` on the **cast** spellID (Claude's discretion per D-4), matching every existing comment's anticipation and staying stable across the two Skyborne races that share Walk on Air's spell ID.
- `ns:RacialDefsRaw` returns `(defs, raceID)` rather than `defs` alone specifically so plan 03's migration can tell "this race genuinely has no racial here" (raceID a real number, defs empty) from "UnitRace isn't readable yet" (raceID nil) — an empty table alone cannot carry that distinction.
- Deleted `racialRaceName` entirely (was only read by the old unsupported-placeholder branch this plan removes) rather than keeping it "just in case" — confirmed via full-codebase grep that nothing else referenced it.
- The Forever offer gate (`ns.CLIENT_IS_FOREVER`) was consolidated into `ns:RacialSuggestions()` alone, so both the Buffs-tab offer and the Cooldowns-tab offer (`ns:RacialCooldownKeys`) read through one gate instead of two separately-maintained ones.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 4-adjacent, but resolved without an architectural change - plan sequencing defect] Task 2's own `<verify>` gate is unsatisfiable at the Task 2 commit boundary**
- **Found during:** Task 2, immediately after implementing it in isolation and running its automated verify script.
- **Issue:** Task 2's verify script asserts `grep -c 'RACIAL_SLOT_BY_KEY' Providers.lua` equals `0` globally. Task 2's own scope (per its `<action>`) is explicitly limited to rewriting `Providers.lua:807-900` and does not touch `RacialProviderMixin:OnTrigger`/`ConsumeRacialStack`/`GetDisplayInfo` (lines ~1470-1590), which is Task 3's declared scope. Those functions still referenced `RACIAL_SLOT_BY_KEY`, `ns.RACIAL_KEYS`, `RACIAL_SUPPORTED_LINES` and `RACIAL_UNSUPPORTED_LINES` until Task 3 rewrote them. I confirmed this with a full-file grep before editing: every remaining reference to these four symbols, after Task 2's edit alone, sat inside the exact block Task 3 owns. This means the gate as literally written cannot pass until Task 3 also lands — it is not something Task 2 could have satisfied by itself, regardless of implementation quality.
- **Fix:** Implemented Task 2 and Task 3's code changes together (since they are genuinely interdependent — Task 3 fixes the stale references Task 2's deletions create), verified all of both tasks' gates cumulatively against the complete working tree (all passed), then split the combined diff into two commits along the plan's declared task/file-scope boundaries using `git diff` + manual hunk partitioning + `git apply --cached`, so each commit's file diff matches exactly what each task's `<files>` and `<action>` describe. This preserves per-task commit atomicity in the history while being honest that the two tasks' code cannot both independently pass their own gates in isolation — only cumulatively.
- **Files modified:** Providers.lua, BuffEngine.lua (both tasks, as scoped)
- **Verification:** Re-ran every sub-check from both Task 2's and Task 3's `<verify>` blocks against the final HEAD state after both commits — all passed (P1-P22, Q1-Q13 in this session's verification log). `stylua . && stylua --check .` clean; `git ls-files --eol` reports `i/lf`/`w/crlf` for all three touched files.
- **Committed in:** `4667ae2` (Task 2), `66ca5c8` (Task 3)

---

**Total deviations:** 1 (plan sequencing defect, not a code defect — documented per the deviation protocol's instruction to say so rather than silently work around it)
**Impact on plan:** No functional impact. The final code at HEAD after both commits matches the plan's `<action>` and `<acceptance_criteria>` exactly for both tasks. The only consequence is that Task 2's commit, taken in isolation, contains dangling references to deleted symbols inside the `RacialProviderMixin` block that Task 3's very next commit resolves — a normal and expected shape for a tightly-coupled two-commit refactor, not a functional regression, since the addon is never loaded against the Task-2-only commit in isolation.

## Issues Encountered
- The worktree this agent was spawned into was branched from an older commit (`f0c8e35`) that predated all of Phase 49's planning docs (they didn't exist on disk). Fast-forwarded the worktree branch to `milestone/v0.4.1-item-tracking-forever-racials` (`fe6a797`) before starting — a safe operation since the worktree branch's tip was an exact ancestor of the milestone branch with no divergent commits (confirmed via `git merge-base`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02 (race data catalogue) can now safely populate `RACIAL_SPELLS` for all ten races: the no-duration guard exists, so cooldown-only rows (Will of the Forsaken, Will to Survive, War Stomp, Cultivation) will not crash on first cast.
- Plan 03 (migration) has what it needs from `ns:RacialDefsRaw`'s `(defs, raceID)` return shape to distinguish "no racial" from "race unreadable" when re-keying existing `racial`/`racial2` database entries.
- **Known intermediate state, by design (documented in the plan itself):** `keyToProvider` no longer maps `"racial"`/`"racial2"`, and nothing yet mints `racial:<spellID>` keys into the database (that's plan 03's migration). A player who already tracks a racial will see a question-mark placeholder until plan 03 runs. This is expected and the plan explicitly instructs not to add a compatibility shim for it.
- In-game verification (addon loads with no Lua error, casting a racial starts the correct `racial:<spellID>` timer) is explicitly deferred to plan 49-05 per this plan's own Task 3 acceptance criteria — no WoW client was available to this agent to confirm at runtime.

---
*Phase: 49-forever-racial-catalogue*
*Completed: 2026-09-25*

## Self-Check: PASSED

- FOUND: Core.lua
- FOUND: Providers.lua
- FOUND: BuffEngine.lua
- FOUND: .planning/phases/49-forever-racial-catalogue/49-01-SUMMARY.md
- FOUND commit: 05a683d
- FOUND commit: 4667ae2
- FOUND commit: 66ca5c8
