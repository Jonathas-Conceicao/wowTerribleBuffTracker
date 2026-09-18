---
phase: 12-schema-migration-data-tables
plan: 02
subsystem: ui
tags: [lua, wow-addon, cdm, suggested-buffs, meta-tracker, trinket, pot]

# Dependency graph
requires:
  - phase: 12-schema-migration-data-tables/01
    provides: "TRINKET_SPELLS/POT_SPELLS/TRINKET_ITEM_IDS/POT_ITEM_IDS defined on ns in BuffEngine.lua"
provides:
  - "ns.SUGGESTED_BUFFS[2]: trinket meta-tracker entry with duration=0 sentinel and getCDMIcon=nil placeholder"
  - "ns.SUGGESTED_BUFFS[3]: pot meta-tracker entry with duration=0 sentinel and getCDMIcon=nil placeholder"
  - "CDMTab Suggested render: nil-safe three-way icon fallback (cdmSpellID -> getCDMIcon -> 134400)"
  - "DATA-03 reconciliation: documented N/A in InitBuffEngine and REQUIREMENTS.md"
affects:
  - 13-timer-functions-cast-detection
  - 14-icon-resolution-caching
  - 15-display-integration-active-icon-switching

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SUGGESTED_BUFFS append pattern: ns.SUGGESTED_BUFFS[#ns.SUGGESTED_BUFFS + 1] = {...} after the literal block"
    - "Three-way icon fallback: cdmSpellID -> getCDMIcon() -> 134400 question-mark sentinel"
    - "getCDMIcon=nil as a Phase 14 placeholder field (enables nil-check without runtime error)"

key-files:
  created: []
  modified:
    - BuffEngine.lua
    - CDMTab.lua
    - .planning/REQUIREMENTS.md

key-decisions:
  - "getCDMSpellID returns nil (not 2825) for trinket/pot — the nil value is what triggers the getCDMIcon fallback path in CDMTab"
  - "getCDMIcon=nil is an explicit Phase 14 placeholder; the CDMTab nil guard is the bridge between current question-mark behavior and future real icon resolution"
  - "DATA-03 N/A: no schema migration needed — v3 stays terminal for v0.2.3 because v0.2.3 is the first release with these features (D-05 supersedes DATA-03)"
  - "Phase 12 ROADMAP success criterion 'schema version reads 4' is superseded by D-05: schema version reads 3 (terminal for v0.2.3) — recorded here for audit trail"

patterns-established:
  - "Pattern: getCDMSpellID returns nil to signal itemID-based entry; CDMTab checks truthiness before using"
  - "Pattern: getCDMIcon=nil placeholder field documents future wiring point without a runtime cost"

requirements-completed: [DATA-03]

# Metrics
duration: 10min
completed: 2026-04-13
---

# Phase 12 Plan 02: SUGGESTED_BUFFS Trinket/Pot Registration + CDMTab Nil Guard Summary

**Trinket and pot meta-trackers registered in ns.SUGGESTED_BUFFS with a nil-safe three-way icon fallback in CDMTab, making them visible in the CDM Suggested section as question-mark placeholders ready for Phase 14 icon resolution**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-13T06:30:00Z
- **Completed:** 2026-04-13T06:40:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Two new SUGGESTED_BUFFS entries (trinket, pot) appended to BuffEngine.lua with duration=0 sentinel and getCDMIcon=nil Phase 14 placeholder
- CDMTab Suggested render upgraded to three-way icon fallback: getCDMSpellID path (lust), getCDMIcon path (Phase 14 trinket/pot), 134400 question-mark default
- DATA-03 reconciled: InitBuffEngine now documents why v3 is terminal for v0.2.3; REQUIREMENTS.md traceability updated to N/A
- All files stylua clean; deployed to WoW via install.bat

## Task Commits

Each task was committed atomically:

1. **Task 1: Append trinket and pot entries to ns.SUGGESTED_BUFFS and document DATA-03 N/A** - `28de06f` (feat)
2. **Task 2: Add getCDMIcon nil fallback to CDMTab.lua Suggested render** - `fdd2bb3` (feat)
3. **Task 3: Update REQUIREMENTS.md to mark DATA-03 as N/A for v0.2.3** - `b94178a` (chore)

**Plan metadata:** (pending final commit)

## Files Created/Modified

- `BuffEngine.lua` - Appended trinket/pot SUGGESTED_BUFFS entries; added DATA-03 reconciliation comment in InitBuffEngine
- `CDMTab.lua` - Replaced single-line hardcoded icon resolution with three-way fallback in Suggested render loop
- `.planning/REQUIREMENTS.md` - DATA-03 marked [x] N/A with rationale; traceability table updated; footer dated 2026-04-13

## Decisions Made

- `getCDMSpellID` for trinket/pot returns `nil` (not a default like 2825) so the CDMTab render detects itemID-based entries via truthiness check rather than a new field type
- `getCDMIcon = nil` is an explicit placeholder field: explicit over implicit, documents the Phase 14 wiring point in BuffEngine itself
- Phase 12 ROADMAP success criterion "schema version reads 4" is superseded by D-05 (CONTEXT.md): schema version stays at 3, which is terminal for v0.2.3. Recorded here as an audit trail note.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

- `BuffEngine.lua` — `getCDMIcon = nil` in both trinket and pot SUGGESTED_BUFFS entries. This is an intentional Phase 12 placeholder; Phase 14 (`14-icon-resolution-caching`) will wire `ns:ResolveTrinketIcon()` and `ns:ResolvePotIcon()`. The stub does not block the plan's goal (entries appear in CDM Suggested section with 134400 question-mark fallback).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ns.SUGGESTED_BUFFS now has 3 entries (lust, trinket, pot) — Phase 13 CDM-01/CDM-02 can rely on these being present
- CDMTab Suggested render is nil-safe and Phase 14 ready: adding `getCDMIcon = function() return ns:ResolveTrinketIcon() end` in Phase 14 will immediately flow through to the icon without further CDMTab changes
- REQUIREMENTS.md traceability is clean: DATA-01, DATA-02 Complete; DATA-03 N/A; all others Pending
- No blockers.

---
*Phase: 12-schema-migration-data-tables*
*Completed: 2026-04-13*
