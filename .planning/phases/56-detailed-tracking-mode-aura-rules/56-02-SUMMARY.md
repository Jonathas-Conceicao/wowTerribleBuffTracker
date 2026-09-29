---
phase: 56-detailed-tracking-mode-aura-rules
plan: 02
subsystem: ui
tags: [wow-addon, cdm, lua, dialog, tracker-fields]

# Dependency graph
requires:
  - phase: 55-id-preview-suggested-cooldown-secrecy
    provides: ns:SpellPreview, ns:SpellAuraSecrecy, ns:SecrecyLine, ns:SecrecyExplanation, ns:SecrecyWarns, ns:SecrecyScopeNote, the spellPreview/secrecyBadge TRACKER_FIELDS entries this plan rewrites
provides:
  - "ADD-06: centered 50px CDM-styled portrait as the FIRST TRACKER_FIELDS entry"
  - "ns:RefreshIDPreview shared helper (portrait render logic, ready for Plan 03's aura ID row)"
  - "ns:BuildSecrecyBadge shared helper (badge art + tooltip, ready for Plan 03's aura ID row)"
  - "secrecyBadge re-anchored to the portrait's top-right corner"
  - "Rewritten 'Order is load-bearing' contract comment describing the update-time GetFieldState read"
affects: [56-03-aura-id-row, 56-04-whole-phase-gates]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Display-only TRACKER_FIELDS entries may read a sibling's state at UPDATE time (via dialog.GetFieldState inside update, receiving dialog as the 3rd arg) instead of only at build time, when the entry must sit ahead of the sibling it reads"
    - "Shared ns: helpers for cross-field UI logic (ns:RefreshIDPreview, ns:BuildSecrecyBadge) instead of duplicating render/tooltip logic per field"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "Kept the portrait's build function free of any dialog.GetFieldState call, deferring the Spell ID read to update(state, ctx, dialog) exactly as the plan required, so CreateAddDialog needed no edit and the portrait could move to the front of the array"
  - "ns:RefreshIDPreview and ns:BuildSecrecyBadge take the caller's already-declared state table as an explicit argument rather than constructing their own, preserving the closure-binding rule (state declared before SetScript) across a function-call boundary"

patterns-established:
  - "Shared ID-preview render (ns:RefreshIDPreview) and secrecy-badge builder (ns:BuildSecrecyBadge) on ns, callable by any TRACKER_FIELDS entry that owns an icon/name/hover triplet"

requirements-completed: [ADD-06]

# Metrics
duration: 25min
completed: 2026-09-28
---

# Phase 56 Plan 02: ADD-06 Portrait Redesign Summary

**Replaced Phase 55's 18px inline spell-preview row with a centered 50px CDM-styled portrait at the front of TRACKER_FIELDS, with the secret-aura badge moved onto its top-right corner and both the preview render and the badge builder factored into reusable `ns:` helpers.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-28T15:20:00Z (approx)
- **Completed:** 2026-09-28T15:47:00Z
- **Tasks:** 2
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments
- `PORTRAIT_SIZE = 50`, `CDM_ICON_MASK_ATLAS`, `CDM_ICON_OVERLAY_ATLAS` constants declared above `TRACKER_FIELDS`, matching Display.lua's `CreateTimerIcon` mask/overlay pattern and Blizzard's 50px `CooldownViewerEssentialItemTemplate` offsets (-9,8 / 9,-8)
- `ns:RefreshIDPreview(state, id)` extracted from the old `spellPreview.update`, keeping the unknown-ID retry, the `generation` bump (WR-01), the 32-bit tooltip clamp, and the IN-04 open-tooltip redraw, and adding a dimmed (`SetDesaturated(true)`, `SetAlpha(0.4)`) empty-slot placeholder so the 50px portrait never collapses to a bare border
- `spellPreview` moved to the FRONT of `TRACKER_FIELDS`, rebuilt as a 50px masked/overlaid portrait with a centered name label beneath it, reading the Spell ID box via `dialog.GetFieldState("spellID")` inside `update` (not `build`) — the only such call in the entry
- `ns:BuildSecrecyBadge(parent, state)` extracted from the old `secrecyBadge.build`, keeping the atlas-vs-text art decision and the three-line tooltip (`SecrecyLine`, `SecrecyExplanation`, `SecrecyScopeNote`)
- `secrecyBadge` re-anchored to `preview.hover, "TOPRIGHT"` with its frame level raised above the portrait so the two hover regions never fight
- Contract comment above `TRACKER_FIELDS` rewritten: the display-only paragraph now documents both the build-time and update-time forms of `GetFieldState`, and the "Order is load-bearing" paragraph documents the new spellPreview-first order and why secrecyBadge/duration still come after both

## Task Commits

Each task was committed atomically:

1. **Task 1: 50px CDM-styled portrait at the FRONT of TRACKER_FIELDS, via ns:RefreshIDPreview** - `37a028b` (feat)
2. **Task 2: Badge on the portrait corner via ns:BuildSecrecyBadge; contract comment rewritten** - `695d4b5` (feat)

**Plan metadata:** (this commit, following this summary)

## Files Created/Modified
- `CDMTab.lua` - new `PORTRAIT_SIZE`/`CDM_ICON_MASK_ATLAS`/`CDM_ICON_OVERLAY_ATLAS` constants, `ns:RefreshIDPreview`, `ns:BuildSecrecyBadge`, the portrait `spellPreview` entry moved to the front of `TRACKER_FIELDS`, the re-anchored `secrecyBadge` entry, and the rewritten order contract comment

## Decisions Made
- Followed the plan's specified implementation lean exactly: the portrait stays a `TRACKER_FIELDS` entry, reads the Spell ID box at UPDATE time, and `CreateAddDialog` is untouched (hash gate `64e38633612791cb7e1ea41902b75ae45c18167b` verified unchanged after every task)
- Placed both new shared helpers between `ns:RefreshIDPreview`... `ns:BuildSecrecyBadge` and the contract comment block, above `TRACKER_FIELDS`, so they are declared before `CreateAddDialog` per the upvalue-order hazard

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

One self-inflicted gate failure during Task 2: the required literal sentence `Keep spellPreview, spellID, secrecyBadge, duration in that order` was initially split across two comment lines by the prose draft, which the `grep -c` gate (single-line match) could not see. Fixed by keeping that clause on one comment line before re-running `stylua` and the verification gate; no code was affected.

## Performance/Cleanup Review (CLAUDE.md workflow)

Reviewed both commits for hot-path allocations, redundant per-frame work, dirty-check opportunities, and dead code, per the project's post-commit standing instruction. This plan touches only `CreateAddDialog`'s field-definition table, which runs on dialog build/open/keystroke, never on the addon's per-frame `OnUpdate` game loop. No new tables, closures, or strings are created beyond what Phase 55's code already allocated per change; `ns:RefreshIDPreview` and `ns:BuildSecrecyBadge` are compare-before-write and build-once respectively, same as the code they replaced. No dead code was left behind — the entire old 18px `spellPreview`/`secrecyBadge` build bodies were removed, not kept alongside. Nothing to flag.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `ns:RefreshIDPreview` and `ns:BuildSecrecyBadge` are ready for Plan 03's aura ID row to call directly, as designed
- The portrait and badge are implemented in code; the in-game visual check (retail and Forever) is deferred to Plan 04's whole-phase checklist, since no WoW client is available in this execution environment
- No blockers for Plan 03

---
*Phase: 56-detailed-tracking-mode-aura-rules*
*Completed: 2026-09-28*

## Self-Check: PASSED

All files and commits referenced in this summary were verified present on disk / in git log.
