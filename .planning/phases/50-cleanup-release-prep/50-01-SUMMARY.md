---
phase: 50-cleanup-release-prep
plan: 01
subsystem: ui
tags: [wow-addon, lua, secret-values, dirty-check, cooldown-manager]

# Dependency graph
requires:
  - phase: 48.1-dispel-type-border
    provides: "ApplyDispelBorder and the SECRET_ATLAS_KEY sentinel, with the always-re-set trade deferred to this plan"
provides:
  - "ApplyDispelBorder keyed on a non-secret cooldownID identity, stopping the per-pass SetAtlas re-issue for an unchanged entry while the atlas is secret"
  - "Confirmed verdict that the pandemic icon/bar FX split is justified divergence, not duplication"
affects: [51-forever-full-review, 52-retail-full-review]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Widget dirty-check stamps keyed on a provably-plain identity (cooldownID) rather than a value that may be secret, sanitised with issecretvalue() before any comparison"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "ApplyDispelBorder's fourth parameter (identity) is sanitised to nil via issecretvalue() before any comparison, per the standing project rule and D-04"
  - "The dirty check re-issues SetAtlas on three conditions: plain key changed, identity changed (pooled-widget reuse hazard, D-05), or identity unreadable (fail open to the old always-set behaviour) — not just the old key-changed check"
  - "The new _dispelID stamp is cleared in the exact same branch that clears _dispelKey, so both existing pool resets (Display.lua bar and icon paths) reach it with no changes to the resets themselves"
  - "Pandemic icon/bar FX split confirmed as justified divergence per source inspection; left untouched (Task 3)"

patterns-established:
  - "A second, non-secret identity stamp beside a value-derived cache key, to give a dirty check a safe answer when the underlying value is a secret — reusable for any future TBT render-path field mirrored from a CDM secret"

requirements-completed: []

# Metrics
duration: ~20min
completed: 2026-09-26
---

# Phase 50 Plan 01: Dispel-border dirty check Summary

**`ApplyDispelBorder` now keys its per-pass dirty check on the mirrored entry's non-secret `cooldownID` instead of always re-issuing `SetAtlas` while the border's atlas is secret, closing the trade Phase 48.1 deferred.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-09-26T00:40:00Z (approx)
- **Completed:** 2026-09-26T00:59:38Z
- **Tasks:** 3 completed (2 code tasks + 1 read-only confirmation task)
- **Files modified:** 1 (Display.lua)

## Accomplishments
- `ApplyDispelBorder` gained a fourth `identity` parameter and a second widget stamp `widget._dispelID`, sanitised with `issecretvalue()` before any comparison, replacing the `or key == SECRET_ATLAS_KEY` always-re-set clause with an identity-aware dirty check
- Both live call sites (`RenderBarContainer`, `RenderIconContainer`) now pass `slot.cooldownID` / `entry.cooldownID` as that identity; both pool resets are untouched and still reach the branch that clears the new stamp
- Confirmed via source inspection that the pandemic icon/bar FX split (`EnsurePandemicIconFX`/`EnsurePandemicBarFX`) is genuine justified divergence, not duplication — no code changed

## Task Commits

Each task was committed atomically:

1. **Task 1: Give ApplyDispelBorder a non-secret identity stamp** - `a7fd247` (feat)
2. **Task 2: Pass the entry's cooldownID from the two live call sites** - `b2ce65c` (feat)
3. **Task 3: Confirm the pandemic icon/bar FX split is justified divergence** - no commit (read-only confirmation, recorded below; `git diff` proves zero pandemic-related lines touched across this plan)

**Plan metadata:** (this SUMMARY's own commit, made after this file)

## Files Created/Modified
- `Display.lua` - `ApplyDispelBorder` widened to a 4-parameter identity-stamped dirty check (Task 1); both live call sites updated to pass `cooldownID` (Task 2)

## Pandemic FX split (Task 3)

Checked against current source, `Display.lua:600-749`:

1. **Parent.** `EnsurePandemicIconFX` parents to `icon:GetParent()` (`Display.lua:616`), with the comment explaining `RenderIconContainer` hides TBT's pooled icon for an engine-drawn merged aura, so an FX parented to the icon would be invisible in the mainstream case. `EnsurePandemicBarFX` parents to `bar` itself (`Display.lua:658`). **Holds.**
2. **Template.** Icon uses `CooldownPandemicFXTemplate` (`Display.lua:621`); bar uses `CooldownPandemicBarFXTemplate` (`Display.lua:658`). **Holds.**
3. **Anchor target and offsets.** Icon anchors to the icon's own rect at `-6`/`+6` (`Display.lua:632-633`), citing Blizzard's `CooldownViewer.lua:2129-2133`. Bar anchors to `bar.statusBar` at `-9`/`+10` (`Display.lua:669-670`), citing `CooldownViewer.lua:2353-2358`. **Holds** — different anchor target, different offsets, different cited source lines.
4. **Frame level source.** Icon: `parent:GetFrameLevel() + 11` (`Display.lua:638`). Bar: `bar.statusBar:GetFrameLevel() + 1` (`Display.lua:674`). **Holds.**

**Overall verdict: justified divergence — not unified.** All four checked divergences hold against the source and its own comments; nothing contradicts what the code already asserts about itself.

`SetPandemicShown` (`Display.lua:685-695`) is confirmed as the already-shared half: both `ApplyPandemicIcon` (`Display.lua:727`) and `ApplyPandemicBar` (`Display.lua:748`) call the same dirty-checked toggle. `ApplyPandemicIcon`'s extra scale/alpha matching (`Display.lua:718-725`) exists only because the icon FX is parented to the container rather than being a true child of the icon (a direct consequence of divergence 1), not because of duplicated logic.

No pandemic-related line was added or removed anywhere in this plan: `git diff -U0 73f260b3011ccc8e35e400ca7191050cce00483e HEAD -- Display.lua | grep '^[-+]' | grep -c 'Pandemic'` → `0`.

## Decisions Made
- Followed D-04/D-05 exactly: the cache key is `cooldownID`, never the atlas, and the pooled-widget hazard precedent (`ApplyCooldownSlot`'s `_cdGen`/`_cdKey` clearing shape) was replicated for `_dispelID` rather than inventing a new shape
- Task 3 required no code change since all four divergences held against source; recorded the verdict here rather than unifying on a confirmed-true premise

## Deviations from Plan

None - plan executed exactly as written. Both code tasks matched their specified concrete shape; Task 3's expected outcome ("leave it alone") held.

## Issues Encountered

None.

## Self-Check: PASSED

- FOUND: Display.lua
- FOUND: .planning/phases/50-cleanup-release-prep/50-01-SUMMARY.md
- FOUND commit: a7fd247
- FOUND commit: b2ce65c
- FOUND commit: 911b63f

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `ApplyDispelBorder`'s dirty check is live ahead of Phases 51 (Forever) and 52 (retail), so both in-game review passes verify it for free per D-03's design — no gate of its own needed in this plan
- Nothing here proves a border still renders correctly; this project has no test runner and the only runtime is the game client. Phases 51/52 must specifically watch: a dispel-type border appearing and clearing correctly in combat, and a border NOT persisting in the wrong colour after a container re-sorts (the exact hazard `_dispelID` exists to prevent)
- No blockers. `README.md`, `CHANGELOG.md`, `Core.lua`, `Providers.lua`, `MergeMode.lua` and `.planning/REQUIREMENTS.md` were not touched by this plan

---
*Phase: 50-cleanup-release-prep*
*Completed: 2026-09-26*
