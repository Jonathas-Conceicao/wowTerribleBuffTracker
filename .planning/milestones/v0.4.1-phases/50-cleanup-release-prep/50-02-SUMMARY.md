---
phase: 50-cleanup-release-prep
plan: 02
subsystem: performance
tags: [wow-addon, lua, racials, hot-path, dirty-check, secret-values]

# Dependency graph
requires:
  - phase: 50-01
    provides: "ApplyDispelBorder's post-SC3 identity-stamped dirty check, read (not modified) during this plan's Part B audit"
provides:
  - "ns:RacialDefInList -- one shared def-by-spellID walk behind all three milestone-introduced callers"
  - "racialGateKeyIDs -- a session-long memo of the race-gate key parse, closing its per-render-pass string.match allocation"
  - "A recorded hot-path audit of all seven sites this milestone touched, with per-site verdicts"
affects: [51-forever-full-review, 52-retail-full-review]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared list-walk helpers take the list as a parameter rather than choosing one internally, so callers that must walk different lists for correctness (gated vs. ungated vs. raw) can still share the comparison logic"
    - "Memoise the parse of an immutable string, never the answer derived from mutable game state -- the parse is a pure function forever, the answer is not"

key-files:
  created: []
  modified:
    - Providers.lua

key-decisions:
  - "ns:RacialDefInList declared as `function ns:RacialDefInList(...)` on ns, never `local function` -- resolves at call time so declaration order cannot trigger this project's five-times-shipped upvalue-order bug"
  - "ns:RacialCooldownSeed keeps walking the flavour-gated ns:RacialSuggestions(), not the ungated ns:RacialDefsForPlayer() -- substituting the ungated list would start seeding racial cooldown tiles on retail, a behaviour change out of bounds for this phase"
  - "ns:IsRacialKeyVisible keeps walking the RAW list (ns:RacialDefsRaw()), never the resolved one -- visibility is race membership, not client spell data, and must not depend on a memo that can still be empty this session"
  - "The race-gate memo (racialGateKeyIDs) caches the PARSED KEY only, never the visibility ANSWER -- the parse is a pure function of the key string and can never go stale; the answer depends on UnitRace(\"player\"), which can be unreadable early in a session, so caching it could hide a race's racials for the rest of that session"
  - "Core.lua's three key parsers (cd:/item:/racial:) are left unified NOT: cd: predates this milestone and is protected by PROJECT.md's 'No refactors during cleanup phases', so at best a shared helper would serve two of three; and a prefix-parameterised helper either builds its Lua pattern per call (a fresh string on a path IsRacialKeyVisible walks once per tracked entry per render pass) or needs module-level pattern constants that buy nothing over three clear five-line functions. CONTEXT.md's default (unify only if cd: can be touched without behaviour change) does not clear here, so all three stay as they are"

patterns-established:
  - "ns:RacialDefInList(defs, spellID) as the canonical shared walk for 'resolve one def by spellID from a list' -- any future racial-list caller should route through it rather than adding a fourth copy"

requirements-completed: []

# Metrics
duration: ~6min
completed: 2026-09-26
---

# Phase 50 Plan 02: Racial def-lookup unification and hot-path audit Summary

**Three milestone-introduced walks of the racial def list collapsed into one `ns:RacialDefInList` shared helper on `ns`, and the race-render-loop's per-pass `string.match` capture allocation closed with a parse-only memo — with a recorded audit confirming no other milestone-introduced hot path needs a change.**

## Performance

- **Duration:** ~6 min (two task commits, ~22:06 to ~22:12 local)
- **Started:** 2026-09-26T01:06:17Z (approx, from worktree base commit)
- **Completed:** 2026-09-26T01:11:45Z
- **Tasks:** 2 completed
- **Files modified:** 1 (Providers.lua)

## Accomplishments
- `ns:RacialDefInList(defs, spellID)` added immediately above `ns:RacialDefForSpellID`, declared on `ns` (not a file-local) per the project's standing upvalue-order rule, with the comment explaining why
- `ns:RacialDefForSpellID`, `ns:RacialCooldownSeed` and `ns:IsRacialKeyVisible` all route through it now, each still walking the exact list it walked before (`RacialDefsForPlayer`, the gated `RacialSuggestions`, and the raw `RacialDefsRaw` respectively) — zero behaviour change
- `racialGateKeyIDs`, a module-level session-long memo, closes the confirmed avoidable allocation: `ns:IsRacialKeyVisible`'s `string.match`-based key parse now runs once per distinct DB key for the whole session instead of once per tracked entry per container per render pass (twenty times a second, from both `Display.lua` render loops)
- Seven hot-path sites this milestone touched were audited and recorded (table below); none met the bar for a further code change

## Task Commits

Each task was committed atomically:

1. **Task 1: Unify the three racial def-by-spellID walks behind ns:RacialDefInList** - `a0f0ba0` (refactor)
2. **Task 2: Audit this milestone's hot paths and close the race-gate allocation** - `09cf33f` (perf)

**Plan metadata:** (this SUMMARY's own commit, made after this file)

## Files Created/Modified
- `Providers.lua` - Added `ns:RacialDefInList` shared helper (Task 1); reduced `ns:RacialDefForSpellID`, `ns:RacialCooldownSeed` and `ns:IsRacialKeyVisible`'s def-matching to call it (Task 1); added `racialGateKeyIDs` module-level memo and wired `ns:IsRacialKeyVisible` to read/write it on the parse-miss path only (Task 2)

## The Core.lua key-parser decision (recorded per plan instruction)

**Decision: leave all three key parsers (`ns:CooldownKeySpellID` `Core.lua:493`, `ns:ItemKeyItemID` `:519`, `ns:RacialKeySpellID` `:546`) exactly as they are. No `Core.lua` change in this plan.**

Two reasons, both from the plan's own framing and CONTEXT.md's recorded default:

1. **`cd:` predates this milestone and is protected.** `ns:CooldownKeySpellID` shipped before RACE-10; `PROJECT.md`'s "No refactors during cleanup phases" Key Decision protects everything pre-existing, and `CLAUDE.md`'s cleanup mandate only covers duplication *this milestone introduced*. A shared helper here would serve at best two of the three parsers (`item:` and `racial:`, both milestone-introduced) — a helper used by two of three is not obviously better than three clear five-line functions, which is CONTEXT.md's own stated bar for this exact candidate.
2. **The performance case for unifying actually points the other way.** A prefix-parameterised helper either builds its Lua pattern string per call — which would be a fresh allocation on a path `ns:IsRacialKeyVisible` walks once per tracked entry per render pass, i.e. exactly the class of cost this same plan spent Task 2 closing — or it needs module-level pattern constants per prefix, which buy nothing over the three parsers as written today.

CONTEXT.md's recorded default ("unify only if it can be done without touching the `cd:` parser's behaviour; otherwise leave all three") does not clear given (1), so all three stay untouched. `git status --porcelain -- Core.lua` confirms zero lines touched.

## Hot-path audit (Part B, Task 2)

| Site | File:line | Frequency | Allocates? | Verdict |
|------|-----------|-----------|------------|---------|
| `ns:RefreshTrackedItemCooldowns` | `Providers.lua:1508` | Per landed item use (`BAG_UPDATE_COOLDOWN`) and per reconcile call — event-driven, not per-frame | No — iterates `ns.db.trackedBuffs` in place, writes into pre-existing module tables | Accepted as-is. Not a render-pass path; the function's own header comment already claims zero allocation and the source confirms it |
| `ItemProviderMixin:OnTrigger` | `Providers.lua:2085` (concat at `:2105`) | Per landed item use (`UNIT_SPELLCAST_SUCCEEDED`) — event-driven, not per-frame | Yes — `ns.ITEM_KEY_PREFIX .. itemID` allocates a fresh string | Accepted as-is, same shape as `ns:EndCombatClearedRacials`'s own accepted per-event concatenation. Confirmed the concat sits AFTER the `itemUseSpellToID[spellID]` hash-lookup guard (line 2099-2102), so an ordinary non-item cast never reaches it — the guard the function's own comment claims |
| `ns:ReconcileTrackedItemCounts` | `Providers.lua:1535` | Per event (`PLAYER_REGEN_ENABLED`, `PLAYER_EQUIPMENT_CHANGED`/`BAG_UPDATE_DELAYED`) — not per-frame | Minimal — writes into the pre-existing `itemTrackedCounts` table, no new table built | Accepted as-is. The `InCombatLockdown()` early return at the top of the function still holds — confirmed still the first statement in the function body |
| `ns:IsMergedEntryInPandemic` | `MergeMode.lua:927` | Per widget per render pass | No — touches no frame, no API, pure comparison of already-staged locals | Clean, no change. Function's own header comment ("allocates nothing") confirmed against source |
| `ReadPandemicState` | `MergeMode.lua:756` | Per merged entry per mirror refresh (called via `pcall` from `ns:RefreshMergeShownSlots`) | No — all three/four fields (`pandemicActive`, `pandemicStart`, `pandemicFinish`, `pandemicTrigger`) are staged into locals and committed together in one block (CR-01 discipline); no table built per pass | Clean, no change |
| `ApplyPandemicIcon` / `ApplyPandemicBar` / `SetPandemicShown` | `Display.lua:685-749` | Per widget per render pass | No — every path is dirty-checked on `_pandemicShown`/`_pandemicScale`/`_pandemicAlpha` widget stamps; the common case (inactive, no FX ever created) costs one field read | Clean, no change |
| `ApplyDispelBorder` (as Plan 50-01 left it) | `Display.lua:795` | Per widget per render pass | No — confirmed: `issecretvalue(identity)` runs before any comparison, `id`/`key` are compared with plain `~=`, no table or string is built in the shown-and-unchanged case | **Allocates nothing and compares no secret, after Plan 50-01.** The new `_dispelID` stamp is checked alongside the existing `_dispelKey`; no additional cost introduced |

**Note on the acceptance-criteria gate that carries no signal alone (per plan's own flag):** Task 2's gate `sed -n '/^function ns:IsRacialKeyVisible/,/^end$/p' Providers.lua | grep -c 'ns:RacialKeySpellID(key)'` reads `1` both before and after this task — the parse call appears exactly once in the function's source either way, since only its *reachability* (unconditional vs. memo-miss-only) changed, not its count. It is a defensive "the parse still exists exactly once, not duplicated" check, not proof that the memo was added. The real proof-of-work gate for Task 2 is `racialGateKeyIDs`'s count, which read `0` before this plan and `3` after (declaration, read, write) — that is the gate that actually demonstrates the memo exists and is wired in.

**No finding cleared the bar for further code change.** The bar (all three required): the allocation is on a per-render-pass/per-frame path; the fix is confined to code this milestone introduced; the fix cannot change observable behaviour. Sites 1-3 are per-event, not per-frame, so they were never in scope for a fix regardless of allocation. Sites 4-7 are per-frame but were already either allocation-free or already dirty-checked by prior plans (48/48.1/50-01) — nothing left to close.

## Decisions Made

See "The Core.lua key-parser decision" and the frontmatter `key-decisions` above; both are restated there rather than duplicated a third time.

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched their specified concrete shape; every acceptance-criteria gate in the plan passed on first run.

## Issues Encountered

None.

## Self-Check: PASSED

- FOUND: Providers.lua
- FOUND: .planning/phases/50-cleanup-release-prep/50-02-SUMMARY.md
- FOUND commit: a0f0ba0
- FOUND commit: 09cf33f

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- No behaviour change shipped by this plan (per its own objective) — Phases 51 and 52's in-game review passes need not specifically re-verify anything here beyond the general "nothing regressed" sweep
- `ApplyDispelBorder`'s dirty check (50-01) is confirmed clean in this plan's audit and needs no further attention
- No blockers. `Core.lua`, `Display.lua`, `MergeMode.lua`, `README.md`, `CHANGELOG.md` and `.planning/REQUIREMENTS.md` were not touched by this plan

---
*Phase: 50-cleanup-release-prep*
*Completed: 2026-09-26*
