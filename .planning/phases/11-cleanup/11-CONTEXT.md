# Phase 11: Cleanup - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Hot-path audit, dead code removal, stylua pass, and release preparation for v0.2.1. Per CLAUDE.md: clean up unused variables, unify repeated behavior, review hot paths, check release scripts.

</domain>

<decisions>
## Implementation Decisions

### Cleanup Scope
- **D-01:** SC-1 (recentlyCast cleanup) is N/A — grace period was not implemented, no recentlyCast table exists.
- **D-02:** SC-2 (zero-allocation scan) is already satisfied — cancelledLabels only allocates under debugLogging AND cancellation. Hot path is zero-allocation.
- **D-03:** Run stylua on all Lua files, fix any formatting issues.
- **D-04:** Update CHANGELOG.md with v0.2.1 features. Update release scripts if needed.
- **D-05:** Review all files modified in v0.2.1 for dead code, unused variables, and redundant patterns.
- **D-06:** The meta-buff string-key icon/label resolution pattern (iterating SUGGESTED_BUFFS to find getCDMSpellID) is repeated in 5+ places across BuffEngine.lua, CDMTab.lua, and Display.lua. Consider extracting a shared helper like `ns:ResolveSuggestedSpellID(key)` to DRY this up.

### Preview Buff Preservation
- **D-07:** Preview must NOT overwrite running buffs. `StartAllPreviewTimers` currently wipes `ns.activeTimers = {}` and replaces everything. Fix: save active timers before preview, merge preview timers on top, and restore real timers on `ClearAllTimers` instead of wiping. Opening/closing CDM should not lose active buff tracking.

### Claude's Discretion
- All cleanup decisions are Claude's discretion — this is a technical housekeeping phase.

</decisions>

<canonical_refs>
## Canonical References

No external specs — cleanup is driven by CLAUDE.md guidelines and code inspection.

### Files to Review
- `BuffEngine.lua` — New v0.2.1 code (aura detection, lust tracking, scan)
- `CDMTab.lua` — Suggested section, meta-buff rendering
- `Display.lua` — String-key icon/label resolution
- `Core.lua` — Event registration changes
- `CHANGELOG.md` — Needs v0.2.1 entry
- `scripts/release.bat` — Verify it works for v0.2.1

</canonical_refs>

<code_context>
## Existing Code Insights

### Repeated Pattern to DRY
The "resolve suggested spellID for string key" pattern appears in:
- `BuffEngine.lua:StartAllPreviewTimers` (icon + label)
- `BuffEngine.lua:StartLustTimer` (icon + label)
- `CDMTab.lua:OnEnter tooltip` (tracked entry + suggested entry)
- `CDMTab.lua:RefreshTBTSections` (section icon)
- `CDMTab.lua:BeginDrag` (ghost icon)
- `Display.lua:bar rendering` (fallback icon + label)
- `Display.lua:icon rendering` (fallback icon)
- `Display.lua:bar tooltip` + `icon tooltip`

A shared `ns:ResolveSuggestedSpellID(key)` returning the numeric spellID would eliminate all these loops.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard cleanup approaches.

</specifics>

<deferred>
## Deferred Ideas

None — preview buff preservation moved into this phase (D-07).

</deferred>

---

*Phase: 11-cleanup*
*Context gathered: 2026-04-04*
