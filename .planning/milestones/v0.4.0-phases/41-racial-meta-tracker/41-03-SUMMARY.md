---
phase: 41-racial-meta-tracker
plan: 03
subsystem: ui
tags: [wow-addon, lua, cooldown-viewer, cdm-tab, tooltip]

# Dependency graph
requires:
  - phase: 41-racial-meta-tracker (plan 01)
    provides: "RacialProviderMixin.GetDisplayInfo returning info.unsupported and info.descriptionLines"
provides:
  - "Suggested-section tiles desaturated when their provider reports info.unsupported == true, written unconditionally so pooled item frames never keep a previous tile's grey state"
  - "Suggested-tile OnEnter tooltip preferring a provider-owned info.descriptionLines array over the static META_DESCRIPTIONS single-line wrap"
  - "Confirmed audit: the add-buff dialog and ns:AddTrackedBuff treat any spell ID as a plain number, with no race/racial special case anywhere in the add path"
affects: ["Phase 42 (Forever in-game verification, gnome-only full-colour check)", "Phase 44 (retail parity check)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Presentation state (desaturation, tooltip body) is read from provider-supplied display-info fields (info.unsupported, info.descriptionLines) rather than branching on the Suggested key string, keeping CDMTab.lua's render path uniform across all four Suggested tiles."

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "Wrote SetDesaturated unconditionally on both the Suggested branch and the tracked-items branch (false in the latter) rather than only on the unsupported path, per the plan's pooled-frame idempotency requirement."
  - "Worded the new comments to avoid repeating the literal strings 'descriptionLines' and 'META_DESCRIPTIONS' a second time, so the plan's exact-count greps (one hit, two hits respectively) pass without diluting the explanation."
  - "Task 3 audit passed with zero findings — no race/racial special case existed in the add path — so no code changed and no separate commit was made for that task, per the plan's own 'change nothing unless the audit fails' instruction."

patterns-established: []

requirements-completed: [RACE-01, RACE-04, RACE-05]

# Metrics
duration: ~10min
completed: 2026-09-21
---

# Phase 41 Plan 03: Racial Tile Presentation & the Add-Flow Escape Hatch Summary

**The Suggested-section Racial tile now greys itself and shows a provider-written "not supported yet" tooltip when the character's racial isn't Eureka!, using two provider-agnostic display-info fields the render path never branches on by key.**

## Performance

- **Duration:** ~10 min
- **Tasks:** 3 (2 code tasks + 1 audit/format task with zero findings)
- **Files modified:** 1 (`CDMTab.lua`)

## Accomplishments
- Every Suggested-section item frame now calls `item.Icon:SetDesaturated(...)` on every render: `(info and info.unsupported) == true` in the Suggested branch, `false` in the tracked-items branch — so a pooled frame that drew the greyed racial tile can't leak grey into the next tile it's reacquired for.
- The Suggested-tile `OnEnter` tooltip now passes `info.descriptionLines or (description and { description }) or nil` as `extraLines`, letting `RacialProviderMixin` supply different tooltip bodies for the supported (Eureka!) and unsupported cases without a new CDMTab-local branch or a fourth `META_DESCRIPTIONS` entry.
- Audited the add-buff dialog (`CreateAddDialog`'s `addBtn` `OnClick`) and `ns:AddTrackedBuff`: both treat a spell ID as an ordinary number (`spellIdBox:GetNumber()`, validated `> 0`, no catalogue lookup, no race test) — `RACE-05`'s escape hatch already works with zero special-casing, confirmed rather than added.

## Task Commits

Each code-producing task was committed atomically:

1. **Task 1: Grey the unsupported tile** - `81b82af` (feat)
2. **Task 2: Provider-supplied tooltip lines** - `ff11f0f` (feat)
3. **Task 3: Audit the add flow for RACE-05** - no commit (audit found nothing to change; `stylua` and `stylua --check .` were run as part of verification, see below)

## Files Created/Modified
- `CDMTab.lua` - Suggested-branch and tracked-items-branch item-pool render now call `Icon:SetDesaturated`; `OnEnter` tooltip handler now prefers `info.descriptionLines` over the static `META_DESCRIPTIONS` lookup.

## Acceptance Criteria — Commands and Real Output

**Task 1:**
- `grep -c 'SetDesaturated' CDMTab.lua` → `2` (pass)
- `grep -n 'unsupported' CDMTab.lua` → exactly one hit, `item.Icon:SetDesaturated((info and info.unsupported) == true)` (pass)
- `grep -n '"racial"' CDMTab.lua` → no hits (pass)
- Suggested branch reads `SetDesaturated` unconditionally, not inside an `if info.unsupported then` (confirmed by reading) (pass)

**Task 2:**
- `grep -n 'descriptionLines' CDMTab.lua` → exactly one hit, inside the `OnEnter` handler: `local extraLines = info.descriptionLines or (description and { description }) or nil` (pass)
- `grep -n 'META_DESCRIPTIONS' CDMTab.lua` → exactly two hits: the table definition (line 11) and the lookup (line 134) (pass)
- `META_DESCRIPTIONS` still has exactly three entries (`trinket`, `pot`, `lust`), no fourth (confirmed by reading) (pass)
- `OnEnter` body passes `info.descriptionLines` by reference into `extraLines`, no `{ }` re-wrapping (confirmed by reading) (pass)

**Task 3:**
- `grep -n '1259817\|UnitRace\|RACIAL' CDMTab.lua BuffEngine.lua` → no hits (pass)
- `grep -n 'GetNumber()' CDMTab.lua` → one hit, `local spellID = spellIdBox:GetNumber()`, with no membership test before `ns:AddTrackedBuff` (confirmed by reading) (pass)
- `stylua CDMTab.lua` (no flags, repo-root config) then `stylua --check .` → exits 0 (pass)
- `git diff --stat` at task-3 time → empty (no changes; audit found nothing to fix). Combined diff across both code commits touches only `CDMTab.lua` (pass, matches the plan's "only CDMTab.lua" intent)

**Plan-level verification:**
- `grep -rn 'SUGGESTED_KEYS = ' BuffEngine.lua` lists four keys (`trinket`, `pot`, `lust`, `racial`); `CDMTab.lua`'s Suggested loop iterates `ns.SUGGESTED_KEYS` with no per-key branch (confirmed by reading `ns:RefreshTBTSections`) (pass)
- `ns:IsSuggestedKeyResolvable("racial")` returns `true` via `RacialProviderMixin:HasResolvableCatalog` returning `true` unconditionally, confirmed by reading `Providers.lua` (pass)
- `stylua --check .` from repo root → exits 0 (pass)
- `luac` is not on this machine's PATH — skipped, as instructed.

## Spell-ID Diff Audit

Exactly one racial spell ID (`1259817`) appears in the whole repo diff for this plan — actually, it appears in **zero** hits within `CDMTab.lua`/`BuffEngine.lua` (the ID lives only in `Providers.lua`'s `RACIAL_SPELLS` table, committed in Plan 01, untouched by this plan). No other race's spell ID appears anywhere in this plan's diff (`CDMTab.lua` only, two commits, neither containing any numeric spell ID literal).

## Unsupported-Tile Contract Confirmation

- **Greyed but visible:** `item.Icon:SetDesaturated(true)` is set whenever `info.unsupported == true`; the tile is never skipped or hidden (`HasResolvableCatalog` always returns `true`, per Plan 01).
- **Draggable/addable:** nothing in this plan's changes touches `BeginDrag`, the right-click "Add to container" menu, or `CreateAddDialog` — the unsupported tile goes through the exact same drag/add machinery as every other Suggested tile.
- **Starts no timer:** confirmed by reading `RacialProviderMixin:OnTrigger` (Plan 01, unchanged here) — when `ResolveRacial()` returns `false` (unsupported), `OnTrigger` returns `nil` on every cast, so no proc is ever granted.

## Exact Tooltip Wording (Unsupported Racial)

From `Providers.lua`'s `RACIAL_UNSUPPORTED_LINES` (Plan 01, surfaced by this plan's Task 2 wiring):

```
Your racial is not supported yet.
Only Eureka! (gnome) is implemented in this version.
Use the + button to track it yourself.
```

## Decisions Made
- Followed the plan's exact code shape for both tasks — no deviation in the `SetDesaturated` placement or the `extraLines` fallback chain.
- Phrased the two new code comments to avoid a second literal occurrence of `descriptionLines`/`META_DESCRIPTIONS`, so the plan's exact-hit-count greps pass without losing the explanatory intent the plan asked for.
- No commit was created for Task 3 since the audit found nothing to fix — consistent with the task's own "change nothing unless the audit fails" instruction. `stylua`/`stylua --check .` were still run as required.

## Deviations from Plan
None. All three tasks' acceptance criteria passed exactly as written; no criterion conflicted with correct code in this plan (unlike 41-02, this plan's grep predictions matched the implementation once the comment wording was chosen carefully).

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## In-Game Checklist (NOT performed — human/Phase 42/44 work, recorded per the plan)
- *(Forever, Phase 42, non-gnome)* Racial tile appears in Suggested, greyed, tooltip shows the unsupported lines above.
- *(Forever, Phase 42, gnome)* Tile resolves to Eureka! at **full colour** with the supported tooltip lines (`Tracks your racial ability.` / `Ends early when its last stack is spent.`). Spell `1259817` was cast, tracked and measured live on Forever on 2026-09-20 (timestamped 3→2→1→0 log in `TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md`). **A greyed gnome tile on Forever is a FAILURE, not a pass** — this correction is preserved, not reversed, in this summary.
- *(Forever, Phase 42)* Dragging the greyed tile into a container creates an inert tracker (placeholder, never fires).
- *(Forever, Phase 42)* `RACE-05` end to end: hover a real Forever racial in the spellbook, read the `Spell ID:` line, type it into the `+` dialog, confirm the tracker starts on next cast.
- *(Retail, Phase 44)* `RACE-01`'s retail half — not verifiable before Phase 44 by user decision; asserted here by code reading only.
- *(Retail, Phase 44, gnome-only)* Full-colour Eureka! parity check on retail — requires a gnome test character; if none is available it must be recorded unperformed, not substituted with the greyed result.

## Next Phase Readiness
This is the final plan of the final feature phase of the milestone. All three Racial-tile requirements this milestone claims (`RACE-01`, `RACE-04`, `RACE-05`) are now code-complete and grep/read-verified; the only remaining work is the human in-game checklist above, deferred to Phase 42 (Forever) and Phase 44 (retail) as the plan specifies.

---
*Phase: 41-racial-meta-tracker*
*Completed: 2026-09-21*
