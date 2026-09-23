---
phase: 42-cleanup
plan: 05
subsystem: display
tags: [wow-addon, lua, refactor, render-path, merge-mode, no-behaviour-change]

# Dependency graph
requires:
  - phase: 42-cleanup
    provides: 42-04's placeholder-proc per-widget table (bar._placeholderProc / icon._placeholderProc), already landed in both render functions
  - phase: 40-merge-mode
    provides: ns.mergeShownSlots mirror and the "appended after the sort" contract
provides:
  - MergedSlotsFor(def) — the single ns.mergeShownSlots read, returning merged, mergedCount
  - BuildActiveByKey(timers) — the single wipe-and-fill of the module-level activeByKey
  - AppendMergedSlots(merged, mergedCount) — the single mirror append into the module-level slots
  - ApplyCachedIcon(widget, spellID) — the single per-widget icon cache block
affects: [43-forever-end-to-end]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Character-identical-only extraction: two blocks are unified when they differ in nothing
       but a local's name; anything differing by a nil test, an argument order or a fallback
       value stays in its own function rather than being parameterised away (42-CONTEXT D1)."
    - "Multi-return helpers in the 20 Hz render path (MergedSlotsFor returns two values, not a
       table) so a once-per-container-per-tick helper allocates nothing."

key-files:
  created: []
  modified:
    - Display.lua (four new module-level helpers; nine call sites across ApplyCooldownSlot, RenderBarContainer and RenderIconContainer)

key-decisions:
  - "RenderIconContainer's timer-branch icon cache is deliberately NOT routed through
     ApplyCachedIcon: it lacks the `cachedIcon == nil` test and the 134400 fallback, so its
     equivalence rests on a reachability argument rather than on the text, and the timer path
     cannot be exercised in game before Phase 43."
  - "Every helper is called at each render function's EXISTING position. The bar path fills
     activeByKey before it builds slots, the icon path after it builds them and appends the
     mirror; aligning the two would be a behaviour change nothing here can test."
  - "The visibility gate, the slot build, the two timer branches, the sizing tails and the
     pool-hide tail are all left split — see the <not_unified> table reproduced below."

patterns-established:
  - "A deliberately-unshared block that looks like a fourth copy carries an inline comment
     naming the helper it does NOT use and why, so the next reader does not 'finish the job'."

requirements-completed: []

# Metrics
duration: 13min
completed: 2026-09-22
---

# Phase 42 Plan 05: Unify the Two Render Functions Summary

**Four module-level helpers replace the character-identical blocks shared by `RenderBarContainer` and `RenderIconContainer` — the mirror read, the timer index, the mirror append and the per-widget icon cache — with everything that merely *looks* similar deliberately left split and recorded.**

## Performance

- **Duration:** ~13 min
- **Completed:** 2026-09-22
- **Tasks:** 2 (one commit each, so the plan reverts on its own)
- **Files modified:** 1 (`Display.lua`)

## Accomplishments

### Task 1 — the mirror read, the timer index and the mirror append

Three blocks were character-identical between the two render functions and are now three
module-level locals defined immediately above `RenderBarContainer`:

- **`MergedSlotsFor(def)`** returns `merged, mergedCount` as **two return values, not a table** —
  it runs once per container per tick and must not allocate. `RenderIconContainer`'s long
  `mergeShownSlots`-not-`mergeSlots` comment moved onto the helper; both call sites now carry a
  two-line pointer to it. The load-bearing part of that comment (reading the CONFIGURED set
  instead of the SHOWN set is what once put a tracked debuff in TBT permanently) now exists in
  one place instead of one copy per function, where one copy can lose it.
- **`BuildActiveByKey(timers)`** wipes and fills the module-level `activeByKey`. Its comment
  records both the reason for the index (the stable provider key IS the slot identity — string
  for meta trackers, numeric for user spells, populated by every provider at `OnTrigger` time)
  and the reason the two call sites are not aligned.
- **`AppendMergedSlots(merged, mergedCount)`** appends into the module-level `slots` and carries
  the contract both call sites used to state: mirrored slots go in **after** the caller's sort,
  never sorted into it, which preserves the user's `layoutOrder` and the CDM's configured order
  with no `layoutOrder` to invent for a mirror entry. The bar call site keeps its own extra
  sentence — that the append happens *before* the example-slot check — because that reason is
  specific to the bar path.

### Task 2 — the per-widget icon cache

**`ApplyCachedIcon(widget, spellID)`** now holds the block that appeared verbatim in three
places, placed beside `ClearIconDesaturation` with the other per-widget helpers. The three
replaced sites and the spell local each passes:

| Site | Call |
|------|------|
| `ApplyCooldownSlot` | `ApplyCachedIcon(icon, spellID)` — immediately before `ApplyIconStyle(icon, settings)`, where the block sat |
| `RenderBarContainer` resolution block | `ApplyCachedIcon(bar, resolvedSpellID)` — immediately before `bar.label:SetText(resolvedLabel or "")`, where the block sat |
| `RenderIconContainer` placeholder branch | `ApplyCachedIcon(icon, resolvedSpellID)` — immediately before `ClearIconDesaturation(icon)`, where the block sat |

The bug-earned reasoning moved onto the helper: `cachedIcon == nil` is part of the **test**, not
belt-and-braces — a pooled frame starts with both cache fields nil, so a slot resolving to no
spell compared equal to a never-populated cache, skipped the block, and left `SetTexture(nil)`,
rendering the placeholder blank. `134400` is the question-mark fallback.

The fourth, similar-looking block (`RenderIconContainer`'s **timer** branch) was **not**
extracted, and now carries a four-line comment naming `ApplyCachedIcon` and saying why it does
not use it.

## Task Commits

1. **Task 1: share the mirror read, timer index and mirror append** — `0d5c70a` (refactor) — +60/−42
2. **Task 2: one helper for the per-widget icon cache** — `5a40c36` (refactor) — +27/−25

`git diff --name-only HEAD~2 HEAD` lists `Display.lua` and nothing else. `CHANGELOG.md` was not
touched. No file was deleted. `stylua` (no flags) ran from the repo root after each task and
`stylua --check .` exits 0; `git ls-files --eol Display.lua` still reports
`i/lf w/crlf attr/text eol=crlf`, i.e. no line-ending churn.

**Plan metadata:** not committed — this SUMMARY.md is intentionally left uncommitted per
orchestrator instructions.

## The `<not_unified>` table (reproduced verbatim from the plan)

Deliberately left in its own function. Each of these looks like duplication and is not
character-identical; per D1 the difference is left where it is rather than parameterised away.

| Block | Why it stays split |
|-------|--------------------|
| The visibility gate (`ShouldShow` → `container:Hide()` → `return` → `container:Show()`) | The `hasActive` expression differs substantially: the bar path is `#timers > 0 or mergedCount > 0`; the icon path adds `cooldownSlotCounts[def.key]` (a cooldown slot produces no timer, so a cooldowns-only container would hide forever) and `engineDrawsHere` (aura frames are children of the container, and TBT may not ask how many are visible). It is also an early return, which a helper cannot perform for its caller. |
| The slot build | The bar path branches on `showPlaceholders`, excludes `trackerType == "cooldown"` because "cooldowns are icons, never bars" is locked, and falls back to iterating `timers`. The icon path always walks `ns.db.trackedBuffs` and excludes nothing. Different shape, different predicate. |
| The timer branch of each | The bar branch drives `statusBar` min/max, `SetValue`, `GetBarColor`, `fillTexture`, `pip` and a formatted countdown; the icon branch drives `icon.cooldown:SetCooldown`, `chargeCount`, desaturation and `mergedTime`. Almost nothing in common beyond reading `timer`. |
| The container sizing tail | The bar path computes a 1-D height plus `barWidth`; the icon path computes a 2-D grid with `majorCount` / `minorCount` and an orientation swap. Different arithmetic. |
| The pool-hide tail (`for i = n + 1, #pool do pool[i]:Hide() end`) | Three lines, identical, but it has never drifted and extracting it would add a function call per container per tick in a 20 Hz loop for no drift protection. `ns:UpdateDisplay`'s superficially similar `for i = 1, #pool` loop is a different operation — hide *everything* this container last rendered, not just the tail — and is not a fourth copy. |
| `RenderIconContainer`'s timer-branch icon cache block | See Task 2. Lacks the `cachedIcon == nil` test and the `134400` fallback. Equivalence would rest on a reachability argument rather than on the text, and nothing can test it before Phase 43. |
| `ns.containerTooltipsShown[def.key] = settings.tooltipsShown` and `local pool = pools[def.key]` | One line each. A helper would be longer than the thing it replaced. |

Every row above was checked against the code as it stands after both commits; all seven are still
split, and none was touched by this plan.

## Ordering checks

The plan names three ordering facts that are behaviour if they move. All three hold (read back
out of the file after `stylua`, not merely out of the diff):

1. **`RenderBarContainer`: `BuildActiveByKey(timers)` is still called BEFORE the `wipe(slots)` /
   `showPlaceholders` block.** Confirmed — the call sits at the old `wipe(activeByKey)` position,
   under the unchanged `-- Build bar slots:` comment, with `local showPlaceholders = ...` and
   `wipe(slots)` immediately after it.
2. **`RenderIconContainer`: `BuildActiveByKey(timers)` is still called AFTER
   `table.sort(slots, ByLayoutOrder)` and after `AppendMergedSlots`.** Confirmed — the order in
   the file is `table.sort(slots, ByLayoutOrder)` → `AppendMergedSlots(merged, mergedCount)` →
   `BuildActiveByKey(timers)`.
3. **`RenderBarContainer`: `AppendMergedSlots` is still called BEFORE the
   `if barEditing and #slots == 0 then table.insert(slots, EXAMPLE_BAR_SLOT) end` check.**
   Confirmed — the call is the last statement before that `if`.

Plus Task 2's own ordering check: **`ApplyCooldownSlot` still runs `ApplyUserCooldown` BEFORE the
`icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~= entry.key` block**, which is what lets it
see `icon._lastStart` before that block nils it. Confirmed — `ApplyCachedIcon` replaced only the
cache block at the top of the function; `local userOwned = ApplyUserCooldown(icon, entry, now)`
still precedes the generation block.

## The three protected structures (42-CONTEXT D5)

| Structure | Check | Result |
|-----------|-------|--------|
| `ns:GridSlotPlacement` as the single source of grid arithmetic | `grep -c 'function ns:GridSlotPlacement' Display.lua` | 1, unchanged; not inlined, duplicated or specialised. `CenteredSlotPlacement` count unchanged at 3. |
| `entry.cdmShown` behind `ns.mergeShownSlots` | `grep -c 'ns.mergeSlots'` in the render path | Zero. `MergedSlotsFor` reads `ns.mergeShownSlots` and nothing else; no read was replaced with `ns.mergeSlots` or an aura query. |
| One aura container per merged entry per unit | `grep -c 'ns:PlaceMergeAura' Display.lua` | 1, unchanged. The call, its arguments and its `if anchor then` guard are byte-identical to before. |

## Grep evidence the duplication collapsed rather than being wrapped

| Assertion | Result |
|-----------|--------|
| `grep -c 'local function MergedSlotsFor' / 'BuildActiveByKey' / 'AppendMergedSlots' / 'ApplyCachedIcon'` | 1 each |
| `grep -v '^\s*--' Display.lua \| grep -c 'wipe(activeByKey)'` | 1 |
| `grep -v '^\s*--' Display.lua \| grep -c 'ns.mergeShownSlots'` | 1 |
| `grep -v '^\s*--' Display.lua \| grep -c '134400'` | 1 |
| `grep -v '^\s*--' Display.lua \| grep -c 'ns:GetSpellIcon(timer.spellID)'` | 1 (timer branch still present and un-rewritten) |
| `grep -c 'ApplyCachedIcon(' Display.lua` | 4 (1 definition + 3 call sites) |
| `stylua --check .` | exit 0 |

## Deviations from Plan

None to the code. Two plan-text defects found and worked around by verifying intent directly;
neither changed what was built.

**1. [Plan defect — wrong grep pattern] Task 1's three call-site counts forget that the
definition line also matches**

- **Found during:** Task 1 verification.
- **Issue:** The automated block asserts `grep -c 'MergedSlotsFor(def)' -eq 2`,
  `grep -c 'BuildActiveByKey(timers)' -eq 2` and
  `grep -c 'AppendMergedSlots(merged, mergedCount)' -eq 2`. Each helper's *definition* line
  (`local function MergedSlotsFor(def)` etc.) also matches its own pattern, because the plan's
  own prose fixes those exact parameter names. So the true count is **3** for each: one
  definition plus two call sites. This is the third occurrence in this phase of the same class
  of defect, and specifically the "count that forgot the definition line also matches" variant
  already flagged. Task 2's equivalent assertion (`ApplyCachedIcon(` = 4) *does* count the
  definition, so the plan is internally inconsistent rather than describing different code.
- **Resolution:** Not worked around in code — renaming a parameter to make a grep pass would be
  contriving the source to fit the check. Intent verified directly instead:
  `grep -n` shows `MergedSlotsFor` at line 1139 (definition), 1177 (bar) and 1397 (icon);
  `BuildActiveByKey` at 1152 (definition), 1195 (bar) and 1440 (icon);
  `AppendMergedSlots` at 1163 (definition), 1220 (bar) and 1438 (icon). One definition, two call
  sites, each in its function's original position. Every other assertion in both tasks passes
  exactly as written.
- **Files modified:** none.

**2. [Plan defect — internal contradiction, resolved in favour of the explicit task]
`ApplyCachedIcon` is a per-widget helper, which the plan's own constraints forbid**

- **Found during:** Task 2.
- **Issue:** `<constraints>` says "A helper ... that would add a call per *widget* per tick is
  not [acceptable]", and threat entry **T-42-12** asserts "Helpers are called once per container
  per tick, never per widget". `ApplyCachedIcon` is called once per rendered widget per tick, so
  both statements are false of the helper Task 2 mandates by name, with an explicit call-count
  assertion.
- **Resolution:** Built as Task 2 specifies. The constraint's target is a helper that *adds*
  per-widget work; `ApplyCachedIcon` replaces an existing inline block with a call at the same
  point, so the steady path gains one Lua call and loses nothing else, and the cache test it
  guards is unchanged. Recorded here rather than silently ignored, because T-42-12's wording no
  longer describes the file.
- **Files modified:** none.

## Issues Encountered

- **The abutting comment blocks were left alone.** The orchestrator flagged two comment blocks
  meeting with no blank line between them — the end of `RelayMergedBar`'s trailing note and the
  start of `MatchMergedTimeFont`'s header, now at lines 1065/1066 — and asked for the blank line
  *if it does not conflict with this plan's verification*. **It conflicts.** Verification item 2
  requires that `git diff Display.lua` touch only the four new helpers and their call sites, and
  names `MatchMergedTimeFont` and `RelayMergedIconTime` among the functions that must show **no**
  change. Inserting a line directly above `MatchMergedTimeFont`'s doc comment would put a hunk in
  that region and cost this plan its "revertible alone, diff is the whole guarantee" property for
  a whitespace fix. Left in place, unchanged, for the third plan running. It needs a plan of its
  own, or a line in a later plan's diff budget.
- No auto-fixes were needed. Nothing in either render function was found broken while reading.

## User Setup Required

None. `./scripts/install.bat` deployed the change to all four WoW client folders present
(`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`) as version `v0.3.0-158-g5a40c36-dev`.

## Next Phase Readiness

- **Nothing here has been exercised in game, by design.** 42-CONTEXT records that the 42/43 swap
  inverts the usual risk calculus: a regression introduced in this plan is caught by Phase 43,
  which has not run yet. This plan's guarantee is a reading argument plus the ordering and grep
  checks above, and nothing more.
- **The bar path is the one to watch in Phase 43.** It is the less-tested of the two and it took
  three of the nine call-site edits. Specific things worth a deliberate look: a bar container
  holding mirrored CDM bars (that both `MergedSlotsFor` and `AppendMergedSlots` still feed it,
  and that it never shows "Example Buff Name"); a bar placeholder whose key resolves to no spell
  (the question-mark texture, which is exactly the bug `ApplyCachedIcon`'s `cachedIcon == nil`
  test exists to prevent); and bar ordering under a custom `layoutOrder` with a mirror present.
- Icon-side checks worth repeating despite the lighter touch: a cooldowns-only container still
  shows (the visibility gate was not touched), and a merged buff icon still gets its sweep.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*

## Self-Check: PASSED

- `Display.lua` — present, `stylua --check .` exits 0.
- `.planning/phases/42-cleanup/42-05-SUMMARY.md` — present, uncommitted as instructed.
- Commit `0d5c70a` — present on `milestone/v0.4.0-cooldown-tracking-cdm-view`.
- Commit `5a40c36` — present on `milestone/v0.4.0-cooldown-tracking-cdm-view`.
- Working tree clean apart from the five uncommitted phase-42 summaries.
