---
phase: 48-pandemic-highlight-merge-mode
plan: 01
subsystem: ui
tags: [wow-addon, lua, cooldown-manager, secret-values, merge-mode]

# Dependency graph
requires: []
provides:
  - "ReadPandemicState(entry) — pcall'd per-entry pandemic stamp read off ns.mergeItemFrames, called from ns:RefreshMergeShownSlots"
  - "ns:IsMergedEntryInPandemic(entry, now) — pure render-time resolver, numbers-win precedence over the boolean"
  - "entry.pandemicActive / entry.pandemicStart / entry.pandemicFinish — the three stamped fields Plan 02 renders from"
  - "ns.debugLogging-gated pandemic state-change log and /tbt merge per-entry pandemic dump"
affects: [48-pandemic-highlight-merge-mode/48-02, 48-pandemic-highlight-merge-mode/48-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-entry CDM state stamped as plain fields on TBT's own entry table, read only via a cached CDM item frame (ns.mergeItemFrames), never a mixin call, never a frame write"
    - "issecretvalue(v) before type(v), per field, all-or-nothing pair stamping so no consumer ever sees a half window"
    - "pcall wrapping a stamp added inside a wipe-then-refill pass, as a structural guarantee rather than an expected-failure guard"
    - "Debug dumps as new call sites of an existing flag (ns.debugLogging), never touching the protected block that owns it"

key-files:
  created: []
  modified:
    - MergeMode.lua

key-decisions:
  - "Followed 48-CONTEXT.md D-01 exactly: itemFrame.PandemicIcon ~= nil is the primary signal (frame reference, never secret); the guarded pandemicStartTime/pandemicEndTime pair is the refinement, all-or-nothing, numbers winning when both are readable"
  - "Read frame reference is reused for the debug log capture — no new global state added, previous entry.pandemicActive value captured locally before each overwrite"
  - "Debug dump's Enum.CooldownViewerAlertEventType capability check references C_CooldownViewer.GetValidAlertTypes exactly once in source (namespace-only existence guard, not a second reference to the function name), since pcall already degrades safely if the specific function is missing"

patterns-established:
  - "New CDM-adjacent reads always resolve the frame from an existing whitelisted cache (ns.mergeItemFrames), never add a new EnumerateActive walk"

requirements-completed: [PAND-03, PAND-04, PAND-05]

# Metrics
duration: ~25min
completed: 2026-09-24
---

# Phase 48 Plan 01: Pandemic Highlight Read Side Summary

**Pandemic state (boolean + guarded numeric window) stamped per merged entry off the cached CDM item frame, with a pure render-time resolver and two `/tbt debug` dumps answering PANDEMIC.md's five unknowns — nothing renders yet.**

## Performance

- **Duration:** ~25 min (estimate; exact start time not captured)
- **Completed:** 2026-09-24T13:14:49Z (last task commit)
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`MergeMode.lua`)

## Accomplishments

- `ReadPandemicState(entry)` reads `itemFrame.PandemicIcon` (primary, frame reference, unconditionally readable) and the guarded `pandemicStartTime`/`pandemicEndTime` pair (refinement, `issecretvalue()`-then-`type()`, all-or-nothing) off `ns.mergeItemFrames[entry.cooldownID]` — the cache `CollectShownCooldownIDs` already populates, so no new CDM surface was added.
- Stamped unconditionally for every merged entry inside `ns:RefreshMergeShownSlots`'s existing per-entry loop, under its own `pcall`, structurally justified the same way `pcall(ResolveMergedAuraTiming, entry)` already is (a raise mid-pass would empty every merged container until the next aura event).
- `ns:IsMergedEntryInPandemic(entry, now)` is the pure render-time resolver Plan 02 will consume: readable numbers win (`now >= start and now <= finish`), the boolean is the fallback — precedence never inverted, no frame touch, no API call, no allocation.
- Two `ns.debugLogging`-gated dumps, both new call sites of the existing flag: a state-change log inside `ReadPandemicState` (answers unknowns 1, 2, 5) and a per-entry pandemic row on `/tbt merge` including the `Enum.CooldownViewerAlertEventType.PandemicTime` capability check via `C_CooldownViewer.GetValidAlertTypes` (answers unknowns 3, 4).
- No CDM mixin method called, no CDM frame field written, `pandemicIconPool` never touched, `Core.lua` byte-unchanged (`wc -l` still 1367, `git status --porcelain -- Core.lua` empty).

## Task Commits

Each task was committed atomically:

1. **Task 1: Stamp the pandemic state in ns:RefreshMergeShownSlots and export the resolver** - `6c775e1` (feat)
2. **Task 2: Add the two ns.debugLogging-gated pandemic dumps** - `0bf65ae` (feat)

## Files Created/Modified

- `MergeMode.lua` - Added `ReadPandemicState`, `ns:IsMergedEntryInPandemic`, `LogPandemicStateChange`, the `pcall(ReadPandemicState, entry)` call site in `ns:RefreshMergeShownSlots`, and the pandemic debug block in `ns:PrintMergeDiagnostics`

## Decisions Made

- Guarded the `pandemicStartTime`/`pandemicEndTime` pair exactly as `MergeMode.lua:650-656` guards `aura.expirationTime`/`duration` — `issecretvalue()` first, then `type()`, per field, stamped all-or-nothing.
- Placed the pandemic stamp's `pcall` on its own line, not folded into `pcall(ResolveMergedAuraTiming, entry)`, per the plan's explicit instruction that widening that pcall's scope would make a raise in either half indistinguishable.
- In the debug capability check, guarded only `C_CooldownViewer` namespace existence before the `pcall`, not the specific `.GetValidAlertTypes` field, so the API name is referenced exactly once in source (the actual `pcall` call) — `pcall(nil, ...)` already degrades safely if that one field happens to be absent, so a second existence check would have been redundant and would have tripped the plan's own `GetValidAlertTypes`-count-equals-1 gate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Own explanatory comments self-defeated two of the plan's zero-occurrence gates**
- **Found during:** Task 1 and Task 2 (running each task's `<verify><automated>` gate immediately after writing the code)
- **Issue:** My first draft of `ReadPandemicState`'s header comment literally wrote out `viewer.pandemicIconPool` and `CheckSetPandemicAlertTriggerTime` in prose while explaining why those things are *not* touched — which is exactly the substring the plan's own `pandemicIconPool`/no-mixin-call gates grep for, so my own documentation tripped the checks meant to prove their absence. Separately, Task 2's `LogPandemicStateChange` header comment named `LogItemUse`/`LogPlayerCast` (Core.lua's protected functions) directly, tripping the D-04 zero-occurrence gate for those tokens even though nothing calls, wraps or relocates them. The capability-check block also referenced `C_CooldownViewer.GetValidAlertTypes` twice (once in an existence guard, once in the `pcall`), tripping the plan's exactly-one-occurrence gate for that function name.
- **Fix:** Reworded all four comments to describe the same facts without reproducing the literal banned identifiers (e.g. "the CDM-owned pool backing Blizzard's own pandemic frame is never touched, acquired or released" instead of naming `pandemicIconPool`; "neither calls, wraps, extends nor relocates any part of it" instead of naming `LogItemUse`/`LogPlayerCast`; dropped the redundant `C_CooldownViewer.GetValidAlertTypes` existence check in favor of a namespace-only guard, since `pcall` already degrades safely if the specific field is missing).
- **Files modified:** `MergeMode.lua`
- **Verification:** Re-ran every listed `grep -c`/`sed`-scoped gate from both tasks' `<verify><automated>` blocks individually; all now report the exact expected counts.
- **Committed in:** `6c775e1` (Task 1), `0bf65ae` (Task 2) — fixed before each task's commit, not as a follow-up commit.

---

**Total deviations:** 1 auto-fixed (Rule 1 — self-inflicted gate collisions in my own new comments, not in pre-existing code)
**Impact on plan:** Cosmetic-only; no behavior, guard order, or structural comment content changed. No scope creep.

## Issues Encountered

**One of Task 1's `<verify><automated>` sub-clauses is unsatisfiable by any plan-compliant implementation, and was reported rather than bent, per the plan's own `<verify_gates>` instruction.**

The combined command's clause
`test "$(grep -cE 'IsInPandemicTime|ShowPandemicStateFrame|HidePandemicStateFrame|CheckSetPandemicAlertTriggerTime|SetPandemicAlertTriggerTime|SetLayoutData' MergeMode.lua)" = "0"`
scans the whole file for six banned tokens and requires zero matches. `MergeMode.lua`'s own pre-existing header (`:18`, clause 4 of the no-taint rule: *"call C_CooldownViewer.SetLayoutData -- it would overwrite the player's live config"*) and a second pre-existing citation later in the file (originally `:1502`, now `:1651` after this plan's insertions) both already contain the literal substring `SetLayoutData` — confirmed via `git show HEAD:MergeMode.lua | grep -n SetLayoutData` against the commit that predates this plan's first commit (`1c0ee24`), i.e. before any of my edits. Both lines are the file's own documentation of the rule this whole phase is built around; `git diff | grep '^+' | grep -c 'SetLayoutData'` against my changes is `0` — nothing I added contributed to this.

Per `<the_single_most_important_constraint>` and the plan's own `<read_first>` for Task 1, this header is meant to be *read as the constraint*, not modified, and per the project's "no refactors during cleanup/protected phases" rule and the explicit `<verify_gates>` instruction ("do not delete pre-existing sanctioned code to satisfy it"), I did not touch either line. I instead isolated this clause, confirmed every other clause in both tasks' combined verify commands passes (see below), and am reporting it here rather than bending the code or the gate.

**Full verification performed:**
- Task 1's combined command, run exactly as written in `48-01-PLAN.md`, fails only on the `SetLayoutData`-family clause (confirmed by isolating that clause: `grep -cE '...SetLayoutData' MergeMode.lua` = `2`, both pre-existing). Every other clause in the same combined command — including S1, S2, S4–S9, S12, S14 and the flavour-token check — was re-run with that one clause removed and reports `ALL_OTHER_CLAUSES_OK`.
- Task 2's combined command, run exactly as written, passes in full (`GATES_OK`, exit 0) — it does not include the `SetLayoutData`-family clause.
- `stylua .` / `stylua --check .`, run twice each, idempotent and clean after every edit.
- `git ls-files --eol MergeMode.lua` reports `w/crlf` throughout.
- `Core.lua`: `wc -l` is `1367` and `git status --porcelain -- Core.lua` is empty — byte-unchanged.

This mirrors `48-VALIDATION.md`'s own stated pattern ("three gates broke earlier in this milestone because a whole-file grep matched pre-existing code it was never meant to see") — this is a fourth instance of the same class of gate-authoring gap, not a defect in the implementation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `entry.pandemicActive`, `entry.pandemicStart`, `entry.pandemicFinish`, and `ns:IsMergedEntryInPandemic(entry, now)` are all in place and stable for Plan 02 to consume for rendering — no interface changes needed on Plan 02's side.
- The unsatisfiable `SetLayoutData` sub-clause is scoped to Task 1's verify command only; Plan 02/03 should either scope any equivalent gate to the diff (`git diff <base>..HEAD -- <files> | grep '^+'`) or exclude the file's own header/footer line ranges, consistent with how `48-VALIDATION.md`'s S3 is already explicitly diff-scoped for the same reason.
- No blockers for Plan 02 (render wiring) or Plan 03 (consolidated sweep + in-game gates).

---
*Phase: 48-pandemic-highlight-merge-mode*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `MergeMode.lua`
- FOUND: `.planning/phases/48-pandemic-highlight-merge-mode/48-01-SUMMARY.md`
- FOUND: commit `6c775e1` (Task 1)
- FOUND: commit `0bf65ae` (Task 2)
