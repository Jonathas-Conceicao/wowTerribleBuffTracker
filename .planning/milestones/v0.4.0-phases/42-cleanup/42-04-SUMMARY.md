---
phase: 42-cleanup
plan: 04
subsystem: display
tags: [wow-addon, lua, hot-path, render-loop, allocation, deduplication]

# Dependency graph
requires:
  - phase: 38-cooldown-slots
    provides: the pooled-widget cooldown stamps (_cdKey, _cdGen, _userCdState, _userCdGrey, _stacks) this plan's helper clears
  - phase: 40-merge-mode
    provides: the _mergedExpiry stamp whose asymmetric clearing is the reason it stays out of the helper
  - phase: 42-cleanup
    plan: 02
    provides: the comment-accuracy sweep this plan's new comment blocks are written against
provides:
  - ClearCooldownStamps(icon) — the single implementation of the pooled-widget cooldown-stamp reset
  - bar._placeholderProc / icon._placeholderProc — per-widget owned tooltip payload tables, allocated once per widget instead of once per tick
affects: [43-forever-end-to-end]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Guard stays at the call site, body moves into the helper: when the steady-path cost is a
       single nil test, folding the test into the extracted function converts it into a function
       call. ClearCooldownStamps documents this rule on itself."
    - "Owned-vs-borrowed field split: a widget field that is SOMETIMES a borrowed reference to
       live engine/DB state (bar.proc) is never reused as a buffer. The reusable table gets its
       own field (_placeholderProc) and the borrowed field is only ever REPOINTED, never wiped."
    - "Every field on every pass: a reused per-widget table assigns all of its fields
       unconditionally, because it outlives the slot that last filled it and a conditionally
       written field leaks the previous slot's value into the next one's tooltip."

key-files:
  created: []
  modified:
    - Display.lua (ClearCooldownStamps helper + two call sites; two placeholder-proc sites)
    - .planning/todos/done/2026-09-21-placeholder-proc-table-allocates-per-tick.md (moved from .planning/todos/)

key-decisions:
  - "The `if icon._cdKey then` guard was deliberately NOT folded into ClearCooldownStamps. The
     original comment promised 'one nil test per icon per frame, and nothing else'; moving the
     guard inside would have made that sentence false while appearing to tidy the code."
  - "icon._mergedExpiry = nil stays out of the helper. The timer branch clears it unconditionally
     further down; the placeholder branch has to clear it inside the guard because its
     entry.isMerged sub-branch owns the stamp. Collapsing the difference would either wipe a live
     merged sweep stamp or leave a stale one."
  - "_placeholderProc is a separate field rather than a reused bar.proc, per 42-CONTEXT.md D2 and
     the todo's approved sketch. bar.proc is sometimes a borrowed live ns.activeTimers table."
  - "The abutting comment blocks around MatchMergedTimeFont / RelayMergedIconTime (noted by 42-02)
     were NOT fixed here. They sit ~150 lines from the nearest edit, and the plan's own
     verification asserts the Display.lua diff touches only the two reset blocks, the two
     placeholder sites and the new helper."

requirements-completed: []

# Metrics
duration: 18min
completed: 2026-09-22
---

# Phase 42 Plan 04: Render-Path Deduplication and the Placeholder-Proc Allocation Summary

**One `ClearCooldownStamps` helper replaces the twice-carried seven-statement pooled-widget reset, and both placeholder branches now refill a per-widget `_placeholderProc` table in place instead of allocating a fresh tooltip payload for every inactive tracker on every 20 Hz tick.**

## Performance

- **Duration:** ~18 min
- **Completed:** 2026-09-22
- **Tasks:** 2, one atomic commit each
- **Files modified:** 1 Lua file, 1 todo moved

## Accomplishments

- `ClearCooldownStamps(icon)` added next to `ClearIconDesaturation` (Display.lua:743), holding the seven statements in their original order — the four stamp nils, then `chargeCount:Hide()`, then `cooldown:Clear()`, then `_stacks = nil`. Both `RenderIconContainer` branches call it under their existing `if icon._cdKey then` guard. `_userCdGrey = nil` now appears exactly once in executable code — the proof the duplication is gone rather than wrapped.
- The twelve-line explanation, previously copied verbatim at both sites, now lives once on the helper and additionally records the two things a future reader would otherwise be tempted to "finish": why the guard stays outside, and why `_mergedExpiry` stays out of the body.
- Both placeholder sites (`RenderBarContainer` at Display.lua:1256-1262, `RenderIconContainer` at Display.lua:1605-1611) now reuse a per-widget `_placeholderProc` table. 42-CONTEXT.md **D2** implemented as the todo sketched it.
- `.planning/todos/2026-09-21-placeholder-proc-table-allocates-per-tick.md` moved to `.planning/todos/done/` inside the same commit, contents unedited.

## Task Commits

1. **Task 1: one helper for the pooled-widget cooldown-stamp reset** — `62a6de2` (refactor)
2. **Task 2: reuse a per-widget table for the placeholder proc (D2)** — `c2b89b2` (perf; includes the todo move)

**Plan metadata:** not committed — this SUMMARY.md is intentionally left uncommitted per orchestrator instructions.

## The `.proc` reader enumeration

This is Task 2's real gate: the reuse is only safe if nothing retains a widget's `.proc` across
frames expecting it to be immutable. Full output of `grep -rn '\.proc\b' *.lua` across all seven
Lua files, taken **before** the change landed:

```
Display.lua:393:		ns:ShowBuffTooltip(self, self.proc)
Display.lua:508:		ns:ShowBuffTooltip(self, self.proc)
Display.lua:939:	icon.proc = entry
Display.lua:1221:			bar.proc = timer -- store for OnEnter tooltip (D-19)
Display.lua:1235:			bar.proc = slot
Display.lua:1241:				bar.proc = { spellID = info.spellID, label = info.label, key = slot.key }
Display.lua:1245:				bar.proc = nil
Display.lua:1473:			icon.proc = timer -- D-19: store for OnEnter tooltip
Display.lua:1546:				icon.proc = entry
Display.lua:1580:					icon.proc = { spellID = info.spellID, label = info.label, key = entry.key }
Display.lua:1582:					icon.proc = nil
```

Verdict per hit:

| Line | Kind | Verdict |
|------|------|---------|
| `Display.lua:393` | **READ** — bar `OnEnter`, `ns:ShowBuffTooltip(self, self.proc)` (D-19) | **Safe.** `ns:ShowBuffTooltip` (Display.lua:247-283) reads `proc.spellID`, `proc.label` and `proc.duration`, passes them to `GameTooltip` setters, and returns. It stores the table nowhere, captures it in no closure, and compares it to nothing. It runs synchronously on the mouse-over, so it always sees the current tick's values. |
| `Display.lua:508` | **READ** — icon `OnEnter`, identical handler | **Safe.** Same function, same argument shape, same reasoning. |
| `Display.lua:939` | WRITE — `ApplyCooldownSlot` borrows the DB entry | Untouched. Another *borrowed* reference, which is exactly why the reusable table needed its own field. |
| `Display.lua:1221` | WRITE — bar timer branch borrows the live `ns.activeTimers` table | Untouched and never wiped. This is the hazard: `RacialProviderMixin` mutates `proc.stacks` on this very table (`Providers.lua:857`). |
| `Display.lua:1235` | WRITE — bar merged branch borrows the mirror slot | Untouched and never wiped. |
| `Display.lua:1241` | WRITE — **changed by this plan** (bar placeholder) | Now `bar.proc = p`, repointing at the owned `bar._placeholderProc`. |
| `Display.lua:1245` | WRITE — `bar.proc = nil` else-branch | Untouched, per the plan. |
| `Display.lua:1473` | WRITE — icon timer branch borrows the live timer | Untouched and never wiped. |
| `Display.lua:1546` | WRITE — icon merged branch borrows the mirror entry | Untouched and never wiped. |
| `Display.lua:1580` | WRITE — **changed by this plan** (icon placeholder) | Now `icon.proc = p`. |
| `Display.lua:1582` | WRITE — `icon.proc = nil` else-branch | Untouched, per the plan. |

**Exactly two readers**, both `OnEnter` handlers, both synchronous, neither retaining. Nothing
anywhere compares two `.proc` values for identity (`grep` for `.proc ==` / `.proc ~=` returns
nothing) and nothing stores a `.proc` into another structure.

I did not trust the plan's list — I also ran `grep -rnw 'proc' *.lua` and `grep -rn "\[.proc.\]" *.lua`
to catch bracket access and local variables shadowing the concept. The wider grep turns up 40+
further hits, all of them **local variables named `proc`** in `BuffEngine.lua`, `Providers.lua`
and `CDMTab.lua`, never a widget field:

- `BuffEngine.lua:197-217` — `for key, proc in pairs(ns.activeTimers/previewTimers)`, building the
  per-tick result and sorted list. These are timer tables, not widget payloads. Unaffected.
- `Providers.lua:847-864` — `local proc = ns.activeTimers["racial"]`, then `proc.stacks = proc.stacks - 1`.
  This is the mutation that makes wiping `bar.proc` catastrophic, and is the strongest single
  argument for the separate field. Unaffected, because `bar.proc = timer` is still a plain repoint.
- `CDMTab.lua:129` and `CDMTab.lua:145-156` — the two `ns:ShowBuffTooltip` call sites outside
  `Display.lua`. Both construct their own tables (`{ spellID = self.spellID }` and a local `proc`
  literal) and neither reads a widget's `.proc`. Unaffected, as the plan said.
- `Core.lua:622`, `Core.lua:670`, and the remaining `Providers.lua` hits — comments about live procs
  holding references to `ns.rankFamilies` tables. No code. Worth noting only because they confirm
  the same invariant from the other side: the codebase already treats a live proc as something
  other code holds a reference into.

No site was found that retains a `.proc` across frames. Nothing to stop and report.

## The two-tick allocation walkthrough

Take one bar widget rendering an inactive tracker with "hide when inactive" off, so
`showPlaceholders` is true and the `else` branch at Display.lua:1239 runs on every tick.

**Tick 1 (first ever pass for this widget):**

1. `local p = bar._placeholderProc` — nil, because the pooled widget has never carried the field.
2. `if not p then p = {} ; bar._placeholderProc = p end` — **one table allocated, once, for the
   lifetime of this widget.**
3. `p.spellID, p.label, p.key = info.spellID, info.label, slot.key` — three field writes into a
   table that already has three hash slots after the first pass.
4. `bar.proc = p` — one pointer store.

**Tick 2 (0.05s later, same widget, same or different slot):**

1. `local p = bar._placeholderProc` — **non-nil.** One table read.
2. `if not p then ... end` — **one nil test, taken false. No allocation.**
3. Same three field writes, now pure in-place overwrites; the table's hash part is already sized,
   so there is no rehash either.
4. `bar.proc = p` — repointed at the same table.

**Tick 2 allocates nothing.** The old code allocated on every tick including tick 2, forever, per
inactive tracker, per container, in combat. The steady-path cost went *down*, which is the
direction the plan's "steady-path cost must not rise" constraint requires: a table constructor
(allocation + three hash inserts + eventual GC) became one nil test plus three overwrites.

The icon path at Display.lua:1601 is identical with `icon` / `entry.key` substituted.

## The borrowed-reference argument

The three non-placeholder writes to `.proc` are all still plain repoints, and none of them is
wiped anywhere:

- `Display.lua:1221` — `bar.proc = timer`, the live `ns.activeTimers` table.
- `Display.lua:1235` — `bar.proc = slot`, the MergeMode mirror slot.
- `Display.lua:939` / `Display.lua:1546` — `icon.proc = entry`, the DB entry / mirror entry.

`_placeholderProc` is read by exactly one branch (the placeholder branch of its own render
function) and written by exactly that branch. No timer branch, merged branch or cooldown branch
reads it, and nothing ever calls `wipe()` on it or on `.proc`. So a live timer can never be
observed through `_placeholderProc`, and `_placeholderProc` can never be mistaken for a timer.

The remaining cross-slot risk is a stale field, not a wiped timer: the table outlives the slot that
last filled it, so if `spellID`, `label` or `key` were assigned on only some paths, a widget moving
between slots would show the previous slot's tooltip. All three are assigned unconditionally on
every pass, and the comment at the bar site records the rule for anyone adding a fourth field —
notably `proc.duration`, which `ns:ShowBuffTooltip` reads when `opts.showDuration` is set and which
this table deliberately does not have. That is threat **T-42-07**, mitigated as the register planned.

## Files Created/Modified

All line numbers below are post-change.

- `Display.lua`
  - **724-751**: `ClearCooldownStamps(icon)` (definition at 743) and its consolidated comment,
    placed immediately after `ClearIconDesaturation` (717-722) with the other per-widget helpers and
    well above both call sites — a `local function` must be defined before its lexical use.
  - **1488-1492**: timer-branch call site. `if icon._cdKey then` guard retained at 1490.
  - **1546-1554**: placeholder-branch call site. Guard retained at 1548; the extra
    `icon._mergedExpiry = nil` retained inside the guard, after the call, at 1554.
  - **1241-1262**: `RenderBarContainer` placeholder proc now `bar._placeholderProc` (code at
    1256-1262, comment at 1241-1255).
  - **1601-1611**: `RenderIconContainer` placeholder proc now `icon._placeholderProc` (code at
    1605-1611, comment at 1601-1604).
- `.planning/todos/done/2026-09-21-placeholder-proc-table-allocates-per-tick.md` — moved via
  `git mv`, contents unedited. (Its own "Scope note" still says to do this in Phase 43; that was
  written before Phases 42 and 43 were swapped on 2026-09-22 and D2 supersedes it. The record of
  the swap lives in `STATE.md`, not in the todo.)

## Decisions Made

- **Guard stays outside the helper.** Discussed above; the original comment's promise
  ("One nil test per icon per frame, and nothing else") is now asserted on the helper itself so the
  next reader does not undo it.
- **`_mergedExpiry` stays outside the helper.** The asymmetry between the two branches is real and
  load-bearing, and the helper's comment now explains it at the one place both callers can see.
- **Did not fix 42-02's abutting comment blocks.** See Deviations.

## Deviations from Plan

None of Rules 1-4 fired. No bugs found, nothing blocking, no architectural question. Two
plan-vs-code mismatches were found in the plan's own `<verify>` assertions and are reported here
rather than worked around silently.

**1. [Plan defect — unsatisfiable verify assertion] Task 1's `ClearCooldownStamps(icon)` count**

- **Assertion:** `test "$(grep -c 'ClearCooldownStamps(icon)' Display.lua)" -eq 2`
- **Why it cannot pass:** `grep -c` counts matching *lines*, and the definition line
  `local function ClearCooldownStamps(icon)` contains the substring `ClearCooldownStamps(icon)`.
  The correct count for one definition plus two call sites is **3**, not 2. Same class of defect the
  phase has hit before (a previous plan asserted a count against an unescaped `.`).
- **Actual state:** `grep -cE '^\s+ClearCooldownStamps\(icon\)$'` → **2** (the two call sites), and
  `grep -c 'local function ClearCooldownStamps'` → **1**. The intent of the assertion is satisfied.
- **Not worked around:** I did not rename the helper or reshape the call to make the literal
  assertion pass.

**2. [Plan defect — unsatisfiable verify assertion] Task 2's `_placeholderProc` count**

- **Assertion:** `test "$(grep -c '_placeholderProc' Display.lua)" -ge 6`, glossed as "three per site".
- **Why it cannot pass:** the plan's own prescribed code shape (copied from the todo's approved
  sketch) mentions `_placeholderProc` exactly **twice** per site — `local p = bar._placeholderProc`
  and `bar._placeholderProc = p`. The third line of the idiom is `bar.proc = p`, which does not
  contain the string. Two sites × two mentions = **4**, by both `grep -c` and `grep -o | wc -l`.
- **Actual state:** 4. Adding two more mentions purely to satisfy the count would mean writing
  redundant code, so I left the idiom exactly as D2 approved it.
- **The other half of that assertion passes as written:**
  `grep -v '^\s*--' Display.lua | grep -c 'proc = { spellID'` → **0**. No table constructor is
  assigned to `.proc` in executable code any more.

**3. [Scope, not a deviation] 42-02's abutting comment blocks left alone**

The orchestrator note asked for a blank line between the block ending `-- else in this file.`
(Display.lua:1035 before this plan) and the `MatchMergedTimeFont` header beginning
`-- Make the relayed countdown look like...` — *if editing nearby*. The nearest edit in this plan is
~150 lines away in a different function, and the plan's own verification asserts the `Display.lua`
diff touches only the two reset blocks, the two placeholder sites and the new helper. Inserting the
line would have broken that assertion. **Still outstanding**, and cheap for whoever next edits
`RelayMergedIconTime` / `MatchMergedTimeFont`.

---

**Total deviations:** 0 behavioural. 2 plan-verify defects reported, 1 note deferred as out of diff scope.
**Impact on plan:** None. Both tasks landed exactly as specified.

## Verification Performed

| Check | Result |
|-------|--------|
| `stylua .` from repo root, no flags | ran after every Lua edit |
| `stylua --check .` | exits 0 |
| `git ls-files --eol Display.lua` | `i/lf w/crlf attr/text eol=crlf` — unchanged, no line-ending churn (the Git-Bash `grep -c $'\r'` trap avoided) |
| `git diff --name-only HEAD~2 HEAD` | `Display.lua` + the moved todo. **`CHANGELOG.md` not listed.** |
| `git rev-parse --abbrev-ref HEAD` | `milestone/v0.4.0-cooldown-tracking-cdm-view` — no branch created, renamed or switched |
| Diff read for load-bearing ordering | `ApplyUserCooldown` still runs before `ApplyCooldownSlot`'s generation block; no `C_Timer.After(0)` deferral touched; no container teardown touched |
| Diff read against D5 | `ns:GridSlotPlacement`, `CenteredSlotPlacement` and every `cdmShown` read are outside the diff entirely |
| `./scripts/install.bat` | deployed `v0.3.0-156-gc2b89b2-dev` to `_retail_`, `_ptr_`, `_beta_` and `_classic_beta_` |
| In-game exercise | **Not attempted, by design.** Phase 43's job. |

## Issues Encountered

None beyond the two verify-assertion defects reported above.

## User Setup Required

None.

## Next Phase Readiness

- The change is deployed to all four client folders and is in place for Phase 43's Forever
  end-to-end pass.
- **What Phase 43 should actually look at**, since neither change is observable when working
  correctly and both are only observable when broken:
  1. Turn **"hide when inactive" off** on a bar container and an icon container, hover an inactive
     placeholder, and confirm the tooltip names the right spell. Then reorder or delete a tracker so
     a pooled widget moves between slots, and hover again — a stale `spellID`/`label`/`key` would be
     the one way the table reuse could show itself.
  2. Let a **racial (Eureka!) or lust timer run**, hover its bar/icon, and confirm the tooltip is
     still correct — that is the borrowed-reference path the separate field exists to protect.
  3. Move a widget **from a cooldown slot to a buff slot** (e.g. hide a cooldown container while a
     buff is up) and confirm the icon drops its charge count, sweep and grey — the `ClearCooldownStamps`
     path.
  4. Same move **into a merged slot** and confirm the merged sweep still appears — the asymmetric
     `_mergedExpiry` clear.
- Nothing in this plan is verifiable before that pass, and nothing in it was made that could not be
  justified by reading.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*

## Self-Check: PASSED

- `Display.lua` — FOUND, contains `ClearCooldownStamps` (1 definition, 2 call sites) and `_placeholderProc` (4 occurrences, 2 per site)
- `.planning/todos/done/2026-09-21-placeholder-proc-table-allocates-per-tick.md` — FOUND
- `.planning/todos/2026-09-21-placeholder-proc-table-allocates-per-tick.md` — correctly ABSENT
- commit `62a6de2` — FOUND
- commit `c2b89b2` — FOUND
- `stylua --check .` — exits 0
