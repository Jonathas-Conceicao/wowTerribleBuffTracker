---
phase: 48-pandemic-highlight-merge-mode
plan: 02
subsystem: ui
tags: [wow-addon, lua, cooldown-manager, secret-values, merge-mode, render]

# Dependency graph
requires:
  - phase: 48-pandemic-highlight-merge-mode/48-01
    provides: "entry.pandemicActive / entry.pandemicStart / entry.pandemicFinish stamps, and ns:IsMergedEntryInPandemic(entry, now)"
provides:
  - "EnsurePandemicIconFX(icon) / EnsurePandemicBarFX(bar) — pcall-guarded lazy 1:1 TBT-owned template instantiation"
  - "SetPandemicShown(widget, fx, active) — shared dirty-checked Show/Hide toggle"
  - "ApplyPandemicIcon(icon, active, settings) / ApplyPandemicBar(bar, active) — per-widget call-site entry points"
  - "One unconditional per-slot call site in RenderIconContainer and RenderBarContainer driving the highlight from Plan 01's resolver"
affects: [48-pandemic-highlight-merge-mode/48-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TBT-owned instantiation of a Blizzard virtual FX template by name, pcall-guarded, degrading to no highlight on failure — genuinely new surface, no prior TBT use of this shape"
    - "Container-parented decoration frame (icon FX) vs widget-parented decoration frame (bar FX), chosen per-widget based on whether the widget itself is ever hidden while still needing to show the decoration"
    - "Dirty-checked Show/Hide toggle driving an AnimateWhileShownTemplate-inherited frame with zero controller code"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "Icon FX parented to icon:GetParent() (the TBT container), not the icon itself — per 48-02-PLAN.md's load-bearing design decision, because RenderIconContainer hides TBT's own pooled icon for exactly the pandemic-relevant category (engine-drawn merged Tracked Buffs) and a highlight parented to a hidden icon would never be visible in that case"
  - "Bar FX parented to bar itself, matching Blizzard's own shape, because bars are never engine-drawn and RenderBarContainer always calls bar:Show() — no hidden-parent hazard for bars"
  - "Both render call sites resolve the pandemic state unconditionally, once per slot, before the existing branch chain — correct across every branch outcome without adding a second branch, and what clears a pooled widget's highlight when it stops being merged (D-05, S14)"
  - "The icon path's trailing unused-icon hide loop gained an explicit ApplyPandemicIcon(pool[i], false, settings) clear, because the icon FX hangs off the container and pool[i]:Hide() alone does not hide it — the one place the container-parenting choice costs something, per the plan's own instruction not to drop it"

patterns-established:
  - "A decoration frame's parent is chosen per-widget by asking 'is the widget itself ever hidden while the decoration should still show', not by defaulting to 'parent to the widget it decorates'"

requirements-completed: [PAND-01, PAND-02, PAND-03, PAND-05]

# Metrics
duration: ~20min
completed: 2026-09-24
---

# Phase 48 Plan 02: Pandemic Highlight Render Side Summary

**Two TBT-owned, pcall-guarded instances of Blizzard's `CooldownPandemicFXTemplate`/`CooldownPandemicBarFXTemplate` — icon FX parented to the container, bar FX parented to the bar and anchored to `bar.statusBar` with the `+1` frame-level bump — wired into `RenderIconContainer`/`RenderBarContainer` via one unconditional per-slot toggle each; no CDM frame is read, written or touched anywhere in this plan.**

## Performance

- **Duration:** ~20 min (estimate; exact start time not captured)
- **Completed:** 2026-09-24T13:23:53Z
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`Display.lua`)

## Accomplishments

- `EnsurePandemicIconFX(icon)` / `EnsurePandemicBarFX(bar)` lazily instantiate TBT's own `CooldownPandemicFXTemplate` / `CooldownPandemicBarFXTemplate` instance per widget, both `pcall`-guarded and stamping `_pandemicFailed` once on failure rather than retrying every tick (PAND-05, S10).
- Icon FX is parented to `icon:GetParent()` — the TBT container — per the plan's load-bearing design decision: `RenderIconContainer` hides TBT's own pooled icon for engine-drawn merged Tracked Buffs, which is exactly the pandemic-relevant category, so a highlight parented to the icon would never be visible in that case. Anchored to the icon's own rect with Blizzard's `-6/+6` offsets.
- Bar FX is parented to `bar` itself and anchored to `bar.statusBar` (TBT's structural equivalent of Blizzard's `cooldownItem.Bar`) with Blizzard's `-9/+10` offsets and `SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)` (S13), so the border renders in front of the bar fill rather than behind it.
- `SetPandemicShown` is the single dirty-checked `Show()`/`Hide()` toggle both `ApplyPandemicIcon`/`ApplyPandemicBar` call — `AnimateWhileShownTemplate` starts/stops its own animation purely from the frame's `Show`/`Hide`, so no controller code was written or needed.
- `RenderIconContainer` and `RenderBarContainer` each gained exactly one unconditional per-slot call (`entry.isMerged and ns:IsMergedEntryInPandemic(entry, now)` / `slot.isMerged and ns:IsMergedEntryInPandemic(slot, now)`), placed ahead of each function's existing branch chain, so a pooled widget reused by a non-merged slot clears any stale highlight the same way `bar._stacks`/`icon._cdKey` already do.
- The icon path's trailing unused-icon hide loop (`for i = #slots + 1, #pool do pool[i]:Hide() end`) gained an explicit `ApplyPandemicIcon(pool[i], false, settings)` clear, since the icon FX hangs off the container and is not hidden by `pool[i]:Hide()` alone — the one place the container-parenting choice costs something, and the plan's own instruction not to drop it.
- No CDM mixin method called, no CDM frame field written or reparented, `pandemicIconPool`/`SetupPandemicStateFrameForItem`/`itemFrame.PandemicIcon`/`IsInPandemicTime` never appear anywhere in `Display.lua`, `Core.lua` byte-unchanged (`wc -l` still `1367`, `git status --porcelain -- Core.lua` empty).
- Deployed via `./scripts/install.bat` to all four detected WoW client folders (retail, PTR, beta, classic beta) so Plan 03's in-game checkpoint has something to look at.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the two pcall-guarded pandemic FX frames and their dirty-checked toggles** - `2577829` (feat)
2. **Task 2: Wire the highlight into RenderIconContainer and RenderBarContainer** - `1b1cc9e` (feat)

## Files Created/Modified

- `Display.lua` - Added `EnsurePandemicIconFX`, `EnsurePandemicBarFX`, `SetPandemicShown`, `ApplyPandemicIcon`, `ApplyPandemicBar` (Task 1); added the `ApplyPandemicBar`/`ApplyPandemicIcon` call sites in `RenderBarContainer`/`RenderIconContainer` plus the trailing-hide-loop clear (Task 2)

## Decisions Made

- Followed the plan's load-bearing design decision exactly: icon FX parented to the container, bar FX parented to the bar, for the reasons the plan states (hidden-icon hazard vs. always-shown bar).
- `ApplyPandemicIcon` matches the icon's own `SetScale`/`SetAlpha` behind dedicated `_pandemicScale`/`_pandemicAlpha` dirty stamps, since the FX is container-parented and therefore does not inherit them the way a true child would; `ApplyPandemicBar` needs neither, since the bar FX is a true child of `bar`.
- Reworded two comments during Task 2 that initially contained the literal substring `GetTime()` inside prose explaining that no *new* `GetTime()` call was added — this self-defeated the plan's own `GetTime()`-count-zero gate for both render functions, the same class of self-inflicted gate collision 48-01's summary already documented for banned-identifier substrings. Fixed before committing, not as a follow-up.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Own explanatory comments self-defeated two of Task 2's zero-occurrence gates**
- **Found during:** Task 2 (running the task's `<verify><automated>` gate immediately after writing the code)
- **Issue:** My first draft of both call-site comments (`RenderIconContainer` and `RenderBarContainer`) explained "uses the render pass's own `now`, never a fresh `GetTime()` call" — which contains the literal substring `GetTime()` the plan's own gate greps for and requires to be absent from each function body.
- **Fix:** Reworded both comments to state the same fact without reproducing the literal token: "adds no clock read of its own."
- **Files modified:** `Display.lua`
- **Verification:** Re-ran the `GetTime()`-count-zero clause for both `RenderIconContainer` and `RenderBarContainer` individually; both report `0` as required.
- **Committed in:** `1b1cc9e` (Task 2) — fixed before the task's commit, not as a follow-up commit.

---

**Total deviations:** 1 auto-fixed (Rule 1 — self-inflicted gate collision in my own new comments, not in pre-existing code)
**Impact on plan:** Cosmetic-only; no behavior, guard order, anchor offset, or structural comment content changed. No scope creep.

## Issues Encountered

None. Every clause of both tasks' combined `<verify><automated>` commands passed as written after the one comment-wording fix above; no gate was reported as unsatisfiable this plan (unlike Plan 01's `SetLayoutData` finding, which does not recur here since this plan never mentions that identifier at all).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both FX creators, both toggles, and both render call sites are in place and stable for Plan 03 to gate in game (G1, G2, G3, G5 — G0/G4/G6 are Plan 01's/Plan 03's own territory).
- Deployed to all four detected WoW client folders via `./scripts/install.bat`; no TOC changed, so `/reload` is sufficient for Plan 03's checkpoint, no full client restart needed.
- No blockers for Plan 03 (consolidated sweep + in-game gates).

---
*Phase: 48-pandemic-highlight-merge-mode*
*Completed: 2026-09-24*
