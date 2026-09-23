---
phase: 42-cleanup
plan: 03
subsystem: config-ui
tags: [wow-addon, lua, cleanup, cdm-tab, new-container-dialog, no-behaviour-change]

# Dependency graph
requires:
  - phase: 36-user-containers
    provides: CONT-04 New Container dialog, its two mutually exclusive checkbox pairs, ApplyCategory and dialog.ResetChoices
provides:
  - AddExclusiveCheck(parent, anchorTo, yOffset, text, checked) — one builder for the dialog's four checkbox+label blocks
  - WireExclusivePair(first, second, onSelect) — one statement of the mutually-exclusive-pair rule, onSelect(false) for the first box and onSelect(true) for the second
affects: [43-forever-end-to-end]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Callback polarity chosen to fit the existing callee: WireExclusivePair's onSelect takes
       false for the first box and true for the second precisely so ApplyCategory(isSpells) can be
       passed by name, with no wrapper closure between the click and the call."
    - "Asymmetry stays at the call site. The Icons/Bars pair is symmetric; Buffs/Cooldowns is not
       (Cooldowns also forces Icons, disables Bars and greys its label). Only the symmetric part
       was extracted; the asymmetry stayed in ApplyCategory rather than being parameterised into
       the helper — 42-CONTEXT.md D1."

key-files:
  created: []
  modified:
    - CDMTab.lua (AddExclusiveCheck, WireExclusivePair, four construction blocks and four OnClick handlers replaced by six calls)

key-decisions:
  - "Anchors stay explicit at each call site rather than becoming a table of specs iterated in a
     loop. Cooldowns anchors under Buffs and Bars under Icons; that chain sets the dialog's
     spacing and is the one thing a reader must check, so making it implicit would cost more
     than the duplication does."
  - "Both WireExclusivePair calls stay textually where their SetScript pairs were — Icons/Bars
     above ApplyCategory, Buffs/Cooldowns below it. The helper is a module-level local and is in
     scope at both points, so nothing needed to move, and not moving it keeps the diff a straight
     substitution and rules out any question about upvalue capture."
  - "The label locals buffsLabel, spellsLabel and iconsLabel keep their bindings even though only
     barsLabel is read, per the plan's explicit instruction that every returned value keeps its
     existing binding. Flagged below as the one thing worth a second look."
  - "ApplyCategory, dialog.ResetChoices and createBtn are untouched. The persisted category key is
     still the literal \"spells\" — renaming it is explicitly deferred (42-CONTEXT.md Deferred Ideas)."

patterns-established:
  - "Grep-count acceptance checks that count a shared literal must account for unrelated uses of
     that literal elsewhere in the file. See Deviations — the plan's UICheckButtonTemplate
     threshold was set as if the file contained only the four occurrences the task removes."

requirements-completed: []

# Metrics
duration: 9min
completed: 2026-09-22
---

# Phase 42 Plan 03: Unify the New Container Dialog's Checkbox Pairs Summary

**The New Container dialog's two mutually exclusive checkbox pairs now share one construction helper and one wiring helper instead of four copied blocks and four copied `OnClick` handlers — a pure, behaviour-preserving substitution in code that runs once, at dialog construction.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-09-22
- **Completed:** 2026-09-22
- **Tasks:** 2 (2 commits)
- **Files modified:** 1 (`CDMTab.lua`)
- **Net:** 48 insertions, 50 deletions across both commits

## Accomplishments
- `AddExclusiveCheck(parent, anchorTo, yOffset, text, checked)` added as a module-level local above `CreateContainerDialog`, returning the checkbox and its label. The four construction blocks — Buffs, Cooldowns, Icons, Bars — became four one-line calls.
- `WireExclusivePair(first, second, onSelect)` added beside it, stating the pair rule once: a click checks the box itself and unchecks its partner. The four `OnClick` handlers became two calls.
- `ApplyCategory` is passed **by name** to the Buffs/Cooldowns call. No wrapper closure, because the callback's boolean polarity was chosen to match `ApplyCategory(isSpells)` exactly.
- The asymmetry between the two pairs was deliberately **not** extracted (see below).
- `stylua` (no flags, repo root) run after each edit; `stylua --check .` exits 0; `git ls-files --eol CDMTab.lua` still reports `i/lf w/crlf attr/text eol=crlf`, so there is no line-ending churn in the diff.

## Task Commits

1. **Task 1: one helper builds the New Container dialog's checkboxes** — `6303f7d` (refactor) — 21 insertions, 32 deletions
2. **Task 2: one helper wires both mutually exclusive checkbox pairs** — `bd34973` (refactor) — 27 insertions, 18 deletions

**Plan metadata:** not committed — this SUMMARY.md is intentionally left uncommitted, following Phase 41's precedent; summaries are committed together at phase close-out.

## Files Created/Modified
- `CDMTab.lua` — new module-level locals `AddExclusiveCheck` and `WireExclusivePair` between `CreateAddDialog` and `CreateContainerDialog`; inside `CreateContainerDialog`, four `CreateFrame`/`SetSize`/`SetPoint`/`SetChecked` + `CreateFontString` blocks replaced by four calls, and four `SetScript("OnClick", ...)` handlers replaced by two calls.

Each call's arguments, checked by eye against the plan's table:

| call | parent | anchor | offset | text | checked |
|------|--------|--------|--------|------|---------|
| `buffsCheck, buffsLabel` | `dialog` | `categoryLabel` | `-4` | `"Buffs"` | `true` |
| `spellsCheck, spellsLabel` | `dialog` | `buffsCheck` | `-2` | `"Cooldowns"` | `false` |
| `iconsCheck, iconsLabel` | `dialog` | `kindLabel` | `-4` | `"Icons"` | `true` |
| `barsCheck, barsLabel` | `dialog` | `iconsCheck` | `-2` | `"Bars"` | `false` |

## The Five-State Walkthrough

There are no automated tests and nothing here can be exercised in game until Phase 43, so the
correctness argument is made by reading. All five reachable states of the dialog:

1. **Open.** `dialog.ResetChoices` is untouched: it sets Buffs checked, Cooldowns unchecked, Icons
   checked, Bars unchecked, then calls `ApplyCategory(false)`, which enables Bars and sets its
   label to `1, 1, 1`. **Unchanged** — this plan does not touch `ResetChoices` at all, and the
   initial `SetChecked` values passed to `AddExclusiveCheck` (`true`, `false`, `true`, `false`)
   match the four literals they replaced.

2. **Click Cooldowns.** Previously: `spellsCheck`'s own handler did `self:SetChecked(true)`,
   `buffsCheck:SetChecked(false)`, `ApplyCategory(true)`. Now: `spellsCheck` is `second` in
   `WireExclusivePair(buffsCheck, spellsCheck, ApplyCategory)`, whose second handler does
   `self:SetChecked(true)`, `first:SetChecked(false)` — i.e. `buffsCheck` — then `onSelect(true)`,
   i.e. `ApplyCategory(true)`. `ApplyCategory` is untouched, so Icons is still forced checked,
   Bars unchecked and disabled, `barsLabel` greyed to `0.5, 0.5, 0.5`. **Statement-for-statement
   identical, in the same order.**

3. **Click Buffs.** Previously `buffsCheck`'s handler ran `ApplyCategory(false)`. Now `buffsCheck`
   is `first`, and `first`'s handler calls `onSelect(false)`. Bars is re-enabled and `barsLabel`
   goes back to `1, 1, 1`. Icons/Bars checked state is deliberately left as it was — that is what
   `ApplyCategory`'s `else` branch does today, and it was not modified. **Unchanged.**

4. **Click an already-checked box, either pair.** The helper's handlers begin with
   `self:SetChecked(true)`, which is what defeats `UICheckButtonTemplate`'s built-in toggle, then
   uncheck the partner. Both directions of both pairs go through the same two-statement body, so a
   pair still can never have both boxes off. **Unchanged.**

5. **Reopen after creating a Cooldowns container.** `dialog.ResetChoices` restores Buffs + Icons
   and calls `ApplyCategory(false)`, so Bars is enabled and un-greyed again. **Unchanged** — this
   is the state the plan's WATCH-FOR warning is about, and it survives untouched precisely because
   the asymmetric behaviour was left in `ApplyCategory` rather than being pulled into the helper.

**`createBtn` reads confirmed untouched:** `barsCheck:GetChecked() and "bar" or "icon"` and
`spellsCheck:GetChecked() and "spells" or "buffs"` are byte-identical to before, and the persisted
category key is still the literal `"spells"`.

**Ordering confirmed untouched:** `WireExclusivePair(iconsCheck, barsCheck)` still sits above
`ApplyCategory`'s definition and `WireExclusivePair(buffsCheck, spellsCheck, ApplyCategory)` still
sits below it; `errorLabel` still anchors to `barsCheck`. `ApplyCategory` is a `local function`
declared before the second call, so passing it by name captures the assigned function, not `nil`.

## What Was Deliberately NOT Extracted

- **The Buffs/Cooldowns asymmetry.** Picking Cooldowns must also force Icons, disable Bars and grey
  its label, because a Cooldowns container is icon-only. That is `ApplyCategory`'s whole job, and it
  stayed there: `WireExclusivePair` expresses only the part that is character-identical between the
  two pairs (check self, uncheck partner) and hands the difference to an optional callback that the
  Icons/Bars call simply does not pass. Per 42-CONTEXT.md D1 — extract what is identical, leave
  what differs at the call site rather than parameterising it away.
- **`dialog.ResetChoices`.** It sets all four boxes directly and calls `ApplyCategory(false)`. It
  looks like a fifth copy of the idiom and is not: it is a bulk reset with no partner relationship
  and no `OnClick`, and it is the thing that stops a previous Cooldowns choice leaving Bars
  disabled. Collapsing it into the helpers would have put the dialog's reset behaviour behind a
  click-handler abstraction for no gain.
- **The four anchors, into a spec table.** Explicitly forbidden by the plan and agreed with on
  reading: the anchor chain (`spellsCheck` under `buffsCheck`, `barsCheck` under `iconsCheck`) is
  what sets the dialog's vertical spacing, and a loop would make it implicit.
- **The `rankCheck` and `mergeCheck` checkboxes.** Both use `UICheckButtonTemplate` with a similar
  label, but neither is half of an exclusive pair — `rankCheck` is a standalone toggle in the Add
  dialog and `mergeCheck` is the addon-wide Merge Mode toggle with a different parent and its own
  anchoring. Out of this plan's scope, and folding them into `AddExclusiveCheck` would mean
  parameterising away the very thing the helper's name asserts.
- **The explanatory comment above `categoryLabel`.** Kept exactly where it is. It carries reasoning
  (why `UICheckButtonTemplate` rather than a dropdown, why category is asked before kind), not
  description, and it is still accurate after the extraction.

## Deviations from Plan

**1. [Criterion reconciliation, not a Rule 1-4 fix] Task 1's `UICheckButtonTemplate` threshold is unsatisfiable as written**

- **Found during:** Task 1 verification
- **Issue:** The plan's automated check is
  `test "$(grep -c 'UICheckButtonTemplate' CDMTab.lua)" -lt 4`, with the rationale "four became one
  inside the helper". But the literal appears **8 times** in the file before the change, not 4: the
  four dialog checkboxes, plus `rankCheck` (Add dialog), `mergeCheck` (Merge Mode toggle), and two
  occurrences inside unrelated explanatory comments. Removing four and adding one leaves **5**, so
  `-lt 4` can never pass without deleting code this plan must not touch.
- **Fix:** None applied to the code. The check's *intent* — that the number of
  `UICheckButtonTemplate` construction sites dropped because four became one — is satisfied and was
  verified directly: the count went 8 → 5, and of the 5 remaining exactly one is inside
  `AddExclusiveCheck`, two are `rankCheck`/`mergeCheck` (both out of scope) and two are comments.
- **Files modified:** none
- **Verification:** `grep -n 'UICheckButtonTemplate' CDMTab.lua` — 5 hits, enumerated above. The
  plan's other three Task 1 checks all pass as written:
  `grep -c 'local function AddExclusiveCheck'` = 1, `grep -c 'AddExclusiveCheck('` = 5
  (definition + four calls), `grep -c 'barsLabel'` = 3. All Task 2 checks pass as written:
  `grep -c 'local function WireExclusivePair'` = 1, `grep -c 'WireExclusivePair('` = 3,
  `grep -c 'WireExclusivePair(buffsCheck, spellsCheck, ApplyCategory)'` = 1.

---

**Total deviations:** 1 (an unsatisfiable acceptance threshold, reconciled by verifying its intent — no code change)
**Impact on plan:** None on behaviour. Both tasks landed exactly as specified.

## Issues Encountered

- **`python` is not on PATH in this environment** (only the Microsoft Store stub). Edits were made
  with `node`, reading and writing `CDMTab.lua` as UTF-8 with literal `\r\n` in every pattern and
  replacement, so CRLF was preserved by construction rather than by luck. Confirmed afterwards with
  `git ls-files --eol CDMTab.lua` (`i/lf w/crlf attr/text eol=crlf`, unchanged) — not with
  `grep -c $'\r'`, which lies here because Git Bash opens files in text mode (learned in 42-01).

## Known Stubs

None.

## User Setup Required

None.

## Next Phase Readiness

- `CDMTab.lua` is `stylua --check .` clean and parses; a syntax error could not have survived it.
- Nothing in this plan is exercisable in game before Phase 43. The five-state walkthrough above is
  the complete correctness argument and is what Phase 43's manual pass should re-confirm: open the
  New Container dialog, click Cooldowns (Bars must grey and disable), click Buffs (Bars must come
  back), click a checked box in each pair (it must stay checked), then create a Cooldowns container
  and reopen the dialog (Buffs + Icons, Bars enabled).
- The remaining candidates from 42-CONTEXT.md's duplication list — `ns.EnsureContainerSettings`
  defaults vs the settings popup's control list, the pooled-widget reset blocks in
  `RenderIconContainer`, and `MergeMode.lua`'s twice-written filter loop — are untouched by this
  plan and independent of it.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*
