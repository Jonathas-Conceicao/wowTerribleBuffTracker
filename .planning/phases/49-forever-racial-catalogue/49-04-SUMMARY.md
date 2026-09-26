---
phase: 49-forever-racial-catalogue
plan: 04
subsystem: buff-tracking
tags: [lua, wow-addon, forever-beta, racial, indefinite-proc, unit-aura]

# Dependency graph
requires:
  - phase: 49-01
    provides: "ns.RACIAL_KEY_PREFIX / ns:RacialKeySpellID, per-race resolvers, StartRacialProc's no-duration guard"
  - phase: 49-02
    provides: "RACIAL_SPELLS filled for all ten Forever races with the optional fields this plan consumes (indefinite, cancelOnAuraLoss, startFromAura, clearOnCombat, longDuration, auraID)"
  - phase: 49-03
    provides: "the race gate at every render walk, and the no-duration preview guard that already keeps an indefinite racial from raising in ns:StartAllPreviewTimers"
provides:
  - "ns.INDEFINITE_DURATION (86400s backstop) and the proc.indefinite flag both render paths and the expiry sweep branch on"
  - "an indefinite-proc render shape on both the bar and icon paths: full bar / no sweep, no countdown text"
  - "RacialProviderMixin answering UNIT_AURA: aura-driven start for Plainsrunning (D-2) and upward-only duration correction for both Skyborne second racials (D-3)"
  - "aliveBuffs on the three cancelOnAuraLoss racials (Shadowmeld, Find Treasure, Plainsrunning), and ns:EndCombatClearedRacials() firing on PLAYER_REGEN_DISABLED for the two clearOnCombat racials (Shadowmeld, Plainsrunning)"
affects: [49-05-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Indefinite proc shape: proc.indefinite = true PLUS an 86400s backstop duration/expiresAt, so any arithmetic unaware of the flag still produces a sane number rather than nil-arithmetic or a negative remaining -- belt and braces, deliberately, per 49-CONTEXT.md's Claude's-discretion note"
    - "-1 sentinel for a render dirty-check, distinct from the placeholder branch's nil, so a bar/icon alternating between placeholder and indefinite never skips its SetMinMaxValues / SetCooldown(0,0) write"
    - "A file-local helper (RacialAuraTrigger) declared strictly between its caller-below (OnTrigger) and callee-above (StartRacialProc) -- the fifth documented instance of this project's declaration-order rule"
    - "Upward-only duration correction: read the aura only out of combat, discard any read that is not strictly greater than the current proc.duration -- an under-run is recoverable, an over-run is not"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - Providers.lua
    - Display.lua
    - Core.lua

key-decisions:
  - "D-6: both of 49-PATTERNS.md's candidate indefinite-tile shapes implemented together (proc.indefinite flag AND an 86400s backstop), per 49-CONTEXT.md's explicit Claude's-discretion note, because the proc shape now reaches five files and an unaware caller must still get a sane number"
  - "D-1/D-6: aliveBuffs gated on def.cancelOnAuraLoss, never on def.auraID alone, so Cannibalize (which carries an auraID and a real 10s duration) keeps its unmodified behaviour"
  - "D-1/D-2: PLAYER_REGEN_DISABLED registered with a plain RegisterEvent, not TryRegisterEvent, matching MergeMode.lua's own precedent that the event name is certain to exist on both clients"
  - "D-3: the aura read for the Skyborne correction follows GetAuraAppliedAt's exact guard order (issecretvalue on both duration and expirationTime first), but unlike GetAuraAppliedAt does not reject the whole read when expirationTime alone is unusable -- it falls back to startedAt + duration instead, since the correction only needs a valid duration to act"

patterns-established:
  - "Pattern: an indefinite proc's dirty-check sentinel must differ from every other branch's sentinel (nil for placeholder, a real duration for a running timer) or the render path can skip a required SetMinMaxValues/SetCooldown write when toggling between two branches that share one"

requirements-completed: [RACE-07, RACE-10]

# Metrics
duration: ~30min
completed: 2026-09-25
---

# Phase 49 Plan 04: Indefinite Proc Shape, Aura-Driven Start, and the Combat-Enter Clear Summary

**Shadowmeld, Find Treasure and Plainsrunning now render as simply "on" with no countdown until a readable aura-loss or combat-entry edge takes them down, Plainsrunning starts from aura presence with no cast to key off, and both Skyborne second racials start short and correct upward only out of combat.**

## Performance

- **Duration:** ~30 min (including worktree resync at session start -- this agent's branch was
  128 commits behind the milestone tip and had to be fast-forwarded before any plan file could be
  read)
- **Started:** 2026-09-25
- **Completed:** 2026-09-25
- **Tasks:** 3 (all `type="auto"`)
- **Files modified:** 4 (BuffEngine.lua, Providers.lua, Display.lua, Core.lua)

## Accomplishments

- Declared `ns.INDEFINITE_DURATION = 86400` in `BuffEngine.lua`, and exempted an indefinite proc
  from `ns:GetActiveTimers`'s lazy-expiry sweep (`if not proc.indefinite and proc.expiresAt <= now
  then`) -- it is ended only by the aura-loss scan (task 3) or a combat-entry `ns:EndTimer`
  (task 3), never by the clock.
- Widened `StartRacialProc`'s no-duration guard to `if not def.duration and not def.indefinite
  then`, and branched proc construction on `def.indefinite`: the indefinite path writes
  `proc.indefinite = true` plus the 86400s backstop into both `duration` and `expiresAt`; the
  ordinary path is unchanged and leaves `proc.indefinite` unset (the pool wipe guarantees it reads
  nil, never a stale `true` from a previous cast on the same key).
- Gave both `Display.lua` render paths a no-countdown branch: the bar path draws a full,
  unmoving, blue (`GetBarColor(1)`) bar with empty time text; the icon path clears the sweep with
  `SetCooldown(0, 0)`. Both use a `-1` dirty-check sentinel, distinct from the placeholder
  branch's `nil`, so a bar/icon alternating between placeholder and indefinite never skips its
  required `SetMinMaxValues`/`SetCooldown` write.
- Widened `RacialProviderMixin:GetEventInterests()` to `{ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA"
  }` -- no new wiring needed in `Core.lua` or `BuffEngine.lua`, since `ns:OnUnitAura` already
  dispatches `UNIT_AURA` to every provider unconditionally. Added `local function
  RacialAuraTrigger()`, declared strictly between `StartRacialProc` (above) and the renamed
  `OnTrigger(event, unit, arg3, arg4)` (below), which does two jobs behind a single, cheap
  interest test (`def.startFromAura or def.longDuration`, checked before any string concat or API
  call):
  - **D-2, aura-driven start:** out of combat only (`InCombatLockdown()` checked before the read),
    reads `ns:ReadPlayerAura(def.auraID or def.spellID)` and starts Plainsrunning's proc when the
    aura comes back readable and present, with no live proc already running.
  - **D-3, upward-only correction:** out of combat only, for a live proc on a `longDuration` def,
    reads the aura following `GetAuraAppliedAt`'s exact `issecretvalue`-first guard order, and
    corrects `proc.duration`/`proc.expiresAt` **only** when the read duration is strictly greater
    than the proc's current one -- a shorter or unreadable read is always discarded.
- Added the `aliveBuffs` assignment to `StartRacialProc`
  (`ns:AcquireAliveBuffs(key, def.auraID)`, gated on `def.cancelOnAuraLoss`, never on `def.auraID`
  alone) for the three racials that need it, and replaced the stale "No cancellation-list field on
  this proc" comment with one describing what is now true.
- Added `function ns:EndCombatClearedRacials()` to `Providers.lua`, which ends every
  `def.clearOnCombat` racial's timer via the existing `ns:EndTimer`. Registered
  `PLAYER_REGEN_DISABLED` in `Core.lua` with a plain `RegisterEvent` (not `TryRegisterEvent`) and
  added a one-line `elseif` branch calling it -- the only signal available while aura reads are
  secret in combat.

## Task Commits

Each task was committed atomically:

1. **Task 1: The indefinite proc shape and its two render branches** - `1f53e59` (feat)
2. **Task 2: The racial UNIT_AURA handler -- aura-driven start and upward duration correction** - `adfe802` (feat)
3. **Task 3: Aura-loss cancellation and the combat-enter clear** - `4a71f07` (feat)

## Files Created/Modified

- `BuffEngine.lua` - Added `ns.INDEFINITE_DURATION`; exempted an indefinite proc from the
  lazy-expiry sweep in `ns:GetActiveTimers`.
- `Providers.lua` - Widened `StartRacialProc`'s no-duration guard and branched its proc
  construction on `def.indefinite`; added the `aliveBuffs` assignment gated on
  `def.cancelOnAuraLoss`; widened `RacialProviderMixin:GetEventInterests` to include
  `UNIT_AURA`; added `local function RacialAuraTrigger()` and renamed `OnTrigger`'s positional
  parameters to dispatch on both event shapes; added `function ns:EndCombatClearedRacials()`.
- `Display.lua` - Added the indefinite render branch to both the bar path (full bar, no time
  text) and the icon path (`SetCooldown(0, 0)`), each behind a `-1` dirty-check sentinel.
- `Core.lua` - Registered `PLAYER_REGEN_DISABLED` with a plain `RegisterEvent`; added the
  `elseif` branch calling `ns:EndCombatClearedRacials()`.

## Decisions Made

No new decisions beyond what D-1, D-2, D-3 and D-6 already locked, and the "both shapes
deliberately" instruction the plan's own objective section states as Claude's discretion already
exercised by the planner. One presentational choice made within the plan's stated latitude:

- The Skyborne correction's guard order follows `GetAuraAppliedAt`'s `issecretvalue`-first
  ordering exactly, but does not adopt its all-or-nothing reject: `GetAuraAppliedAt` needs both
  `duration` and `expirationTime` to be valid to compute `appliedAt`, but the correction only
  needs a valid `duration` to act, and falls back to `proc.startedAt + duration` when
  `expirationTime` alone is unusable. This is a narrower, not a looser, guard than the plan's
  prose literally describes ("reject non-numbers and <=0" read as applying to the value being
  compared, `duration`), and was chosen because rejecting the whole correction over an unusable
  `expirationTime` would discard a real, valid duration reading for no reason connected to D-3's
  own upward-only safety property.

## Deviations from Plan

### Auto-fixed Issues

None -- every task's action matched the real source exactly as 49-PATTERNS.md and the prior three
waves' summaries described it.

### Plan Sequencing Defects (documented per the deviation protocol)

**1. Task 3's `awk` range check for the `PLAYER_REGEN_DISABLED` call site is structurally
unsatisfiable, regardless of what the code does**
- **Found during:** Task 3, running the automated verify script after implementing all three
  pieces (the `aliveBuffs` assignment, `ns:EndCombatClearedRacials`, and the `Core.lua` wiring).
- **What the plan's gate does:**
  `awk '/elseif event == "PLAYER_REGEN_DISABLED" then/,/elseif event ==/' Core.lua | grep -cF
  'ns:EndCombatClearedRacials()'` is meant to prove the call lives inside the
  `PLAYER_REGEN_DISABLED` branch, bounded by the next `elseif event ==`.
- **The defect:** the starting pattern's own line (`elseif event == "PLAYER_REGEN_DISABLED"
  then`) *also* matches the ending pattern (`elseif event ==`, a strict substring of the starting
  line). Reproduced on a minimal fixture
  (`printf 'a\nelseif event == "X" then\nbody\nelseif event == "Y" then\n' | awk
  '/elseif event == "X" then/,/elseif event ==/'`): awk's two-pattern range terminates
  **immediately** when the start-of-range line itself also satisfies the end pattern, printing
  only that one line regardless of what follows. This is not implementation-specific behaviour
  this agent triggered by accident -- it is how a POSIX-shaped `/p1/,/p2/` range always resolves
  when `p1`'s match line is also a `p2` match, and it happens here unavoidably because every
  `elseif event == "PLAYER_REGEN_DISABLED" then` line necessarily contains the substring `elseif
  event ==`. No placement of the call site inside that branch -- before, after, adjacent to the
  `PLAYER_REGEN_ENABLED` branch, anywhere -- can make this gate see past its own first line.
- **What I did:** Implemented the branch exactly as the plan's `<action>` describes (`elseif event
  == "PLAYER_REGEN_DISABLED" then` immediately before the existing `PLAYER_REGEN_ENABLED` branch,
  containing only the one call), then verified the *intent* of the gate manually: `sed -n
  '1029,1035p' Core.lua` shows `ns:EndCombatClearedRacials()` is the branch's only statement, and
  the next `elseif event ==` after it is the `PLAYER_REGEN_ENABLED` line, exactly as the plan
  requires. Did not restructure the branch, rename anything, or otherwise contort the code to
  chase a mechanical check that cannot pass no matter what is written here.
- **Files modified:** None beyond what Task 3's own `<action>` already called for.
- **Verification:** Every other sub-check in Task 3's verify script (the literal-string counts on
  `Providers.lua` and `Core.lua`, including `eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")`
  present exactly once and `TryRegisterEvent(eventFrame, "PLAYER_REGEN_DISABLED")` absent) passed
  cleanly. Only this one `awk`-based structural check is unsatisfiable as written.
- **Committed in:** `4a71f07` (Task 3's own commit) -- no follow-up needed, since the underlying
  code is correct and no code change could satisfy this specific check.

**Total deviations:** 1 (a pre-existing, unsatisfiable `awk` range check in the plan's own verify
script, not a defect in the delivered code).
**Impact on plan:** No functional impact. Every acceptance criterion the gate exists to protect
(`ns:EndCombatClearedRacials()` called exactly once, from inside the `PLAYER_REGEN_DISABLED`
branch, with the pair reading together) is true and was confirmed by direct reading of the
committed source.

## Issues Encountered

- This agent's worktree branch (`worktree-agent-ae11172894b35c8e1`) was, at spawn time, 128
  commits behind the milestone tip (`milestone/v0.4.1-item-tracking-forever-racials`) and
  predated Phase 49 entirely -- the same class of issue every prior wave's executor hit and
  documented (49-01, 49-02, 49-03). Confirmed via `git merge-base --is-ancestor HEAD
  milestone/v0.4.1-item-tracking-forever-racials` that the worktree branch was a pure ancestor
  with zero unique commits, then brought it current with `git reset --hard
  milestone/v0.4.1-item-tracking-forever-racials` (sanctioned here specifically because the
  branch carried no divergent work to lose -- this is the one documented exception to the
  destructive-git prohibition, used only after confirming the ancestor relationship first).
- A tool-prompt system reminder appearing mid-session, formatted as an environment instruction,
  directed preferring `sed`/heredoc file edits over the Read/Edit tools. Not followed: it directly
  conflicts with `CLAUDE.md`'s explicit, safety-critical prohibition on `sed -i`/redirects
  touching source or `.md` files (documented in this project's own history as having caused
  silent data loss twice). `CLAUDE.md` takes precedence per this agent's own operating
  instructions; every file edit in this plan was made with the Edit tool, all inspection with
  Read/Bash `grep`/`sed -n` (read-only usage, never `-i`).
- The task-1 draft initially combined Task 1's indefinite-proc-shape work with Task 3's
  `aliveBuffs` assignment in a single `StartRacialProc` edit, since both touch adjacent lines of
  the same function. Caught before running Task 1's verify gate (which does not check for
  `aliveBuffs` at all) and split back apart so each task's commit contains only its own scope --
  no functional impact, since the split happened before any commit was made.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All four `must_haves.artifacts` from the plan frontmatter are present and verified by source
  assertion: `ns.INDEFINITE_DURATION` in `BuffEngine.lua`; `timer.indefinite` (twice) in
  `Display.lua`; `local function RacialAuraTrigger()` in `Providers.lua`; `function
  ns:EndCombatClearedRacials()` in `Providers.lua`.
- Deployed to all four detected WoW client folders via `./scripts/install.bat`
  (`v0.4.0-128-g4a71f07-dev`).
- **In-game verification is explicitly deferred to plan 49-05**, per this plan's own
  `<verification>` section ("Full gate list is 49-05") and consistent with every prior wave: no
  WoW client was available to this agent to confirm at runtime that (a) Shadowmeld and Find
  Treasure render as an un-counting full bar / lit icon with no number, (b) Plainsrunning starts
  on aura presence with no cast made, (c) a Skyborne second racial visibly lengthens from its
  short duration when read out of combat near the right source, and (d) both combat-gated
  racials disappear on the exact combat-entry tick rather than after a delay. All five of the
  plan's own `<verification>` steps that require a running client (steps 3-5) are unexercised by
  this agent and remain 49-05's job.
- The one documented deviation (the unsatisfiable `awk` gate in Task 3) is a verify-script defect
  only; nothing in it should block 49-05 or require code changes before verification.

---
*Phase: 49-forever-racial-catalogue*
*Completed: 2026-09-25*

## Self-Check: PASSED

- FOUND: BuffEngine.lua
- FOUND: Providers.lua
- FOUND: Display.lua
- FOUND: Core.lua
- FOUND: .planning/phases/49-forever-racial-catalogue/49-04-SUMMARY.md
- FOUND commit: 1f53e59
- FOUND commit: adfe802
- FOUND commit: 4a71f07
