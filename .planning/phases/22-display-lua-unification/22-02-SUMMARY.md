---
phase: 22-display-lua-unification
plan: 02
subsystem: ui
tags: [display, tooltip, icon-cache, proc-shape, cleanup]

# Dependency graph
requires:
  - phase: 22-01
    provides: "Normalized 9-field ActiveProc shape with always-numeric proc.spellID; no icon/source/castSpellID/lustBuffID fields"
provides:
  - "ns:ShowBuffTooltip(frame, proc) exported from Display.lua — single tooltip handler for bar + icon OnEnter (DISP-03)"
  - "Bar + icon layout loops unified via ns:GetDisplayInfoForKey + per-widget icon cache (bar/icon.cachedSpellID / cachedIcon)"
  - "Zero type-discriminating branches in Display.lua — DISP-01 satisfied"
  - "GetSuggestedAtRestIcon local helper deleted"
  - "ns.metaIconsDirty readers + clearer deleted from Display.lua"
affects: [22-03, CDMTab.lua-phase23]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-widget icon cache: frame.cachedSpellID / frame.cachedIcon keyed by numeric spellID — avoids redundant GetSpellIcon calls"
    - "Synthetic placeholder proc: {spellID, label, key} allocated cold-path only (not in 50ms hot path)"
    - "ns:ShowBuffTooltip as shared exported handler — CDMTab-ready for Phase 23"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "ns:ShowBuffTooltip uses type(proc.spellID) == 'number' guard matching D-18 contract — all procs are now numeric so branch is defensive only"
  - "Placeholder synthetic proc {spellID, label, key} allocated per render to preserve hover tooltip — acceptable cold-path allocation (not 50ms hot path)"
  - "Comment referencing deleted function names cleaned up to satisfy grep-based verification checks"

patterns-established:
  - "All four buff types rendered by a single codepath — no if/elseif chains on type or key format"
  - "Icon derivation always happens at Display time via ns:GetSpellIcon + per-widget cache; providers never compute icon textures"

requirements-completed: [DISP-01, DISP-03]

# Metrics
duration: ~3min
completed: 2026-04-21
---

# Phase 22 Plan 02: Display.lua Unification Summary

**Unified Display.lua to consume only the 9-field normalized ActiveProc shape: deleted GetSuggestedAtRestIcon helper and metaIconsDirty flag, consolidated two divergent OnEnter tooltip chains into a single ns:ShowBuffTooltip export, and introduced per-widget icon caches (cachedSpellID/cachedIcon) on bar and icon frames**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-21T21:43:09Z
- **Completed:** 2026-04-21T21:45:50Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Exported `ns:ShowBuffTooltip(frame, proc)` as a single unified tooltip handler (DISP-03), callable by CDMTab in Phase 23 without changes
- Rewrote both bar OnEnter and icon OnEnter handlers to delegate to `ns:ShowBuffTooltip(self, self.proc)` — eliminated ~50 lines of duplicated type-discriminating tooltip resolution
- Deleted `GetSuggestedAtRestIcon` local helper (14 lines) and all three `ns.metaIconsDirty` sites (2 readers + 1 clearer) from Display.lua
- Rewrote bar layout loop: single codepath using `ns:GetDisplayInfoForKey(slot.spellID)` for placeholder resolution; per-widget icon cache `bar.cachedSpellID / bar.cachedIcon`
- Rewrote icon layout loop: symmetric pattern with `icon.cachedSpellID / icon.cachedIcon`; `_lastStart` dirty-check preserved
- Stored `bar.proc = timer` (active) or synthetic `{spellID, label, key}` (placeholder) to give `ns:ShowBuffTooltip` data at hover time
- Zero `type(x) == "string"` discriminating branches remain in Display.lua — DISP-01 satisfied

## Task Commits

Each task was committed atomically:

1. **Task 1: Add ns:ShowBuffTooltip export + rewrite bar/icon OnEnter handlers** - `295396e` (feat)
2. **Task 2: Rewrite layout loops + delete GetSuggestedAtRestIcon + metaIconsDirty** - `8afa0ff` (feat)

## Files Created/Modified

- `Display.lua` — primary target: ~115 lines removed, ~50 lines added; net -65 lines; zero type-discriminating branches; per-widget icon cache added; ns:ShowBuffTooltip exported

## Lines Removed / Added Detail

| Removed | Lines | Description |
|---------|-------|-------------|
| GetSuggestedAtRestIcon local helper | 14 | D-23/D-27 |
| Bar OnEnter tooltip chain | ~25 | Replaced by ns:ShowBuffTooltip delegate |
| Icon OnEnter tooltip chain | ~25 | Replaced by ns:ShowBuffTooltip delegate |
| Bar layout loop old branch | ~35 | Replaced by unified GetDisplayInfoForKey path |
| Icon layout loop old branch | ~18 | Replaced by unified GetDisplayInfoForKey path |
| metaIconsDirty disjuncts (2) + clearer | 3 | D-25 |

| Added | Lines | Description |
|-------|-------|-------------|
| ns:ShowBuffTooltip function + comment block | ~18 | D-18/D-19 |
| Bar layout loop unified path + cache | ~22 | D-22/D-31 |
| Icon layout loop unified path + cache | ~28 | D-22/D-24 |

## New Frame Fields

- `bar.proc` — reference to active timer proc, or synthetic `{spellID, label, key}` for placeholder; nil when info unavailable
- `bar.cachedSpellID` — last resolved spellID for icon cache invalidation
- `bar.cachedIcon` — cached texture ID from `ns:GetSpellIcon(resolvedSpellID)` or 134400 fallback
- `icon.proc` — same as bar.proc but on icon frames
- `icon.cachedSpellID` — last resolved spellID for icon frames
- `icon.cachedIcon` — cached texture ID for icon frames

## Transient State Note

`ns.metaIconsDirty` writer in `CDMTab.lua:20` (`ns.metaIconsDirty = true`) is still present after this plan. Plan 22-03 deletes it. Leaving the writer in place while readers are already deleted is harmless — it writes to a field nobody reads.

## Decisions Made

- `ns:ShowBuffTooltip` uses `type(proc.spellID) == "number"` guard per D-18 contract. Since proc.spellID is always numeric post-Phase-22, this is purely defensive — the "Unknown" branch only fires if proc is nil (placeholder with no info available).
- Placeholder synthetic proc `{spellID, label, key}` is a small table allocated cold-path only (preview active or show-when-empty mode). Not in the 50ms hot path — acceptable per PITFALL-7.
- Comment block of `ns:ShowBuffTooltip` was cleaned of exact deleted function names to satisfy grep-based verification without functional impact.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

Minor: The `ns:ShowBuffTooltip` comment originally contained the exact names of the deleted functions (`ns:ResolveSuggestedSpellID` / `ns:GetAtRestMetaInfo`) as a "no longer needed" annotation. These matched the plan's verification `grep -q` checks. Resolved by rephrasing the comment to "no legacy meta-info fallback chains" without changing function behavior.

## Next Phase Readiness

- Plan 22-03 (CDMTab.lua 1-line edit: delete `ns.metaIconsDirty = true` at CDMTab.lua:20) is unblocked
- `ns:ShowBuffTooltip` is live and ready for CDMTab Phase 23 migration to call it
- Display.lua is fully type-agnostic — no remaining references to metaSlot, ResolveSuggestedSpellID, GetAtRestMetaIcon, GetAtRestMetaInfo, GetSuggestedAtRestIcon, or metaIconsDirty

---
*Phase: 22-display-lua-unification*
*Completed: 2026-04-21*
