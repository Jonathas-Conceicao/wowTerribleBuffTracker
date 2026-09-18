# Phase 16: Cleanup - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Release-prep only. Stylua pass, dead code removal, CHANGELOG entry, release.bat sanity check, verify clean package. No refactors — tech debt accumulated during Phase 13-14 hotfixing is deferred to the next milestone where the user plans a full data-storage rework.

</domain>

<decisions>
## Implementation Decisions

### Scope is release-prep only
- **D-01:** No code refactors. Explicit user decision: "I have some plans to fully rework this logic for next release. So let's avoid any major or minor refactors at the end of this milestone."
- **D-02:** Do NOT unify the duplicated icon resolution chain across CDMTab/Display/StartAllPreviewTimers — preserved as-is for the next milestone's rework.
- **D-03:** Do NOT deduplicate TRINKET_FALLBACK_ORDER / POT_FALLBACK_ORDER arrays vs derived sets — preserved as-is.
- **D-04:** Do NOT consolidate ns.metaIcons vs ns.metaAtRest — preserved as-is.
- **D-05:** metaIconsDirty flag, StartAllPreviewTimers source-field filtering, FindSpellByItemID loop — all preserved as-is.

### In scope for this phase
- **D-06:** Run `stylua` on all modified Lua files (standard per CLAUDE.md)
- **D-07:** Scan for and remove any leftover debug prints, `ns.debugLogging = true` overrides, commented-out code blocks from Phase 13/14 hotfixes
- **D-08:** Add CHANGELOG entry for v0.2.3 describing new features (trinket + pot meta-trackers, dynamic icon resolution, buff spell icon/tooltip for at-rest)
- **D-09:** Verify `release.bat` script works correctly (smoke test — no need to actually release)
- **D-10:** Update PROJECT.md validated requirements block to reflect v0.2.3 features
- **D-11:** Update .pkgmeta if needed (probably not)
- **D-12:** Increment .toc version to v0.2.3

### Claude's Discretion
- Exact CHANGELOG wording
- Order of cleanup tasks
- Whether to consolidate stylua+dead-code scan into one pass

</decisions>

<canonical_refs>
## Canonical References

### Release artifacts
- `scripts/release.bat` — tags and pushes release (GitHub Actions handles packaging)
- `.pkgmeta` — BigWigs Packager config
- `.github/workflows/release.yml` — BigWigs Packager action
- `TerribleBuffTracker.toc` — interface version / addon metadata

### Milestone artifacts
- `.planning/REQUIREMENTS.md` — 14 Complete, 2 N/A (DATA-03, ICON-06)
- `.planning/phases/12-15/*-SUMMARY.md` — feature summaries for CHANGELOG

### Process docs
- `CLAUDE.md` — workflow rules (stylua, install.bat, no COMBAT_LOG_EVENT_UNFILTERED)
- Prior milestone cleanup phases (Phase 6 for v0.2.0, Phase 11 for v0.2.1) as CHANGELOG style reference

</canonical_refs>

<code_context>
## Existing Code Insights

### Known tech debt (INTENTIONALLY DEFERRED)
- Duplicated icon resolution chain across 4+ call sites
- Dual cache tables (ns.metaIcons + ns.metaAtRest) with overlapping data
- Hardcoded fallback order arrays alongside derived item ID sets
- Subtle StartAllPreviewTimers source-field preservation logic

### Dead code scan targets
- Phase 13 added temporary debug prints in OnSpellCastSucceeded (removed in commit 568a73b — verify still gone)
- Check for any `print("TBT Debug` or `ns.debugLogging = true` leftovers
- Check for commented-out code blocks

### Release checklist
- stylua clean across all Lua files
- Version bump in .toc
- CHANGELOG entry
- release.bat dry run (or real tag push when user is ready)

</code_context>

<specifics>
## Specific Ideas

- User quote: "let's avoid any major or minor refactors at the end of this milestone"
- Data storage rework is its own upcoming milestone (noted in Phase 12 deferred ideas)

</specifics>

<deferred>
## Deferred Ideas

- Full data storage rework / icon resolution unification — next milestone
- Async icon retry (ICON-08 Future Requirement)
- All tech debt items listed in D-02..D-05

</deferred>

---

*Phase: 16-cleanup*
*Context gathered: 2026-04-13*
