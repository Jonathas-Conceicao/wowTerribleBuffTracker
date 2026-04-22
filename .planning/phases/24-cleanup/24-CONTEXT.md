# Phase 24: Cleanup - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Final cleanup and release-prep for v0.2.4 SpellProvider Refactor. Delete orphaned pre-refactor shims and dead exports, stylua pass, write v0.2.4 CHANGELOG, verify CI/packaging is correct, perform targeted hot-path audit. No refactors — scope is strictly housekeeping, matching the Phase 16 pattern ("no refactors at end of milestone").

</domain>

<decisions>
## Implementation Decisions

### Dead-Code Removal Scope
- **D-01:** Grep-gated full sweep. Rule: if no external reader exists, delete it. Applies to 3 named shims (`ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo`, `ns:ResolveSuggestedSpellID` in BuffEngine.lua) plus any `ns.*` export that has zero consumers — including `ns.TRINKET_FALLBACK_ORDER` / `ns.POT_FALLBACK_ORDER` (scout confirmed zero external readers; local arrays in Providers.lua stay, only the namespace exports are removed). Every deletion verified by grep before the diff.
- **D-02:** Rename `ns:RefreshMetaIcons` → `ns:RefreshProvidersAtRest`. Single call-site update in `CDMTab.lua:24`. Name reflects post-refactor architecture (iterates `ns.providers`, calls each `provider:RefreshAtRest()`).
- **D-03:** Scrub-stale-refs comment policy. After shim deletion, remove now-dangling "Phase N will remove this shim" / "Relocated from X in Phase Y" comments. Preserve comments that document current non-obvious invariants (e.g., "Combat-gated for PITFALL-5"). Git log retains history.
- **D-04:** Targeted hot-path audit. Spot-check the three v0.2.4-touched paths: Display bar/icon rendering (per-widget icon cache), `OnUnitAura` dispatch, `ScanActiveTimersForCancellation`. Verify no new per-frame allocations vs. pre-refactor baseline. Any findings feed the CHANGELOG performance note (D-09). Time-boxed — not a full addon-wide audit.

### Pending Todos
- **D-05:** Close the Evoker Fury of the Aspects cancellation todo (`2026-04-22-fury-of-the-aspects-cancellation-bug-evoker-lust.md`) as solved. User confirmed in-game that cancellation works correctly; no code change required. Move to `.planning/todos/done/` with a note that reflects the runtime verification.
- **D-06:** Close the M+ Lua errors todo (`2026-04-22-mplus-lua-errors-secret-values-during-lust.md`) as solved. User reports the errors were caused by an unrelated addon-integration issue, not TBT. Move to `.planning/todos/done/` with that note.

### CHANGELOG & Release Prep
- **D-07:** v0.2.4 CHANGELOG entry is minimal. One-liner: "Internal file reworking — no user-visible changes." No feature bullet list.
- **D-08:** Performance note appended only if the D-04 audit finds a measurable improvement (or regression). Specific wording decided post-audit, during execution — not locked now.
- **D-09:** Delete untracked `pots_info.csv` and `trinket_info.csv` at repo root. Remove the "Source: trinket_info.csv" / "Source: pots_info.csv" comments in `Providers.lua:117,140` to eliminate dangling references.
- **D-10:** CI/packaging verified as-is — no changes needed. `.toc` already includes `Providers.lua` (added Phase 17); `CDMTab.lua` loads via `<Script file="CDMTab.lua"/>` in CDMTab.xml:3; `.pkgmeta` ignore list is complete; `.github/workflows/release.yml` generates `RELEASE_NOTES.md` from CHANGELOG.md top section before BigWigs runs.
- **D-11:** Standard stylua pass across all Lua files. Zero formatting deltas on exit.
- **D-12:** `CURRENT_SCHEMA_VERSION` stays at 3. Verified during scout; no schema migration in v0.2.4 per REQUIREMENTS.md "Out of Scope".

### Release Order (reaffirmed from existing memory)
- **D-13:** Phase 24 does NOT tag anything. Release sequence after Phase 24 completes:
  1. `/gsd:complete-milestone` squash-merges `milestone/v0.2.4-spell-provider-refactor` → `main`
  2. User checks out `main`
  3. User runs `./scripts/release.bat 0.2.4`

### Claude's Discretion
- Exact CHANGELOG wording (one-liner + any D-08 performance note)
- Order of cleanup tasks within the phase (shim removal before/after comment scrub, etc.)
- Whether comment scrub happens in the same diff as the shim delete or a follow-up pass
- Exact phrasing of the "closed as solved" notes on the two todo files

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & scope
- `.planning/REQUIREMENTS.md` — DISP-04 is the last outstanding requirement for v0.2.4; all others complete
- `.planning/ROADMAP.md` §Phase 24 — cleanup success criteria and deps
- `.planning/PROJECT.md` — milestone goal, validated requirements log

### Prior cleanup phases (pattern reference)
- `.planning/phases/11-cleanup/11-CONTEXT.md` — v0.2.1 cleanup pattern (broader scope with refactor)
- `.planning/phases/16-cleanup/16-CONTEXT.md` — v0.2.3 cleanup pattern (release-prep only; locked "no refactors" decision D-01)
- `.planning/phases/06-cleanup/06-01-PLAN.md` — v0.2.0 cleanup execution template

### Release artifacts
- `CHANGELOG.md` — needs v0.2.4 entry per D-07/D-08
- `TerribleBuffTracker.toc` — uses `@project-version@` placeholder; no manual bump
- `.pkgmeta` — BigWigs Packager config; ignore list verified complete (D-10)
- `.github/workflows/release.yml` — CI extracts top CHANGELOG section to RELEASE_NOTES.md before BigWigs packaging
- `scripts/release.bat` — tag + push; runs on main, not on milestone branch

### Pending todos (both to be closed as solved)
- `.planning/todos/pending/2026-04-22-fury-of-the-aspects-cancellation-bug-evoker-lust.md` — per D-05
- `.planning/todos/pending/2026-04-22-mplus-lua-errors-secret-values-during-lust.md` — per D-06

### Process docs
- `CLAUDE.md` — stylua workflow, "cleanup phase" requirements (review hot paths, release scripts)

</canonical_refs>

<code_context>
## Existing Code Insights

### Confirmed dead symbols (grep-gated, zero external readers)
- `BuffEngine.lua:39` — `ns:GetAtRestMetaIcon(key)` shim
- `BuffEngine.lua:48` — `ns:GetAtRestMetaInfo(key)` shim
- `BuffEngine.lua:133` — `ns:ResolveSuggestedSpellID(key)` shim
- `Providers.lua:171` — `ns.TRINKET_FALLBACK_ORDER` export (local array stays, used internally)
- `Providers.lua:172` — `ns.POT_FALLBACK_ORDER` export (local array stays, used internally)

### Rename (D-02)
- `BuffEngine.lua:26` — `ns:RefreshMetaIcons` → `ns:RefreshProvidersAtRest`
- `CDMTab.lua:24` — single call-site update

### Stale comments to scrub (D-03, post-delete)
- `BuffEngine.lua:16-18` — multi-line note citing "Relocated to Providers.lua in Phase 18/20/22"
- `BuffEngine.lua:25, 35-38, 44-47, 127-132` — "Phase N will remove this shim" comments on the soon-deleted functions
- `Providers.lua:41, 117, 140, 162, 166, 192, 225, 292, 559` — assorted Phase-N references, including the two "Source: X.csv" lines (D-09)

### Untouched (preserved as-is)
- Internal use of `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` locals in `Providers.lua:308, 322, 396, 403, 415`
- `ns.SUGGESTED_KEYS` — active and correct (introduced Phase 23)
- `ns.providers`, `ns:GetDisplayInfoForKey`, `ns:DispatchEventToProviders` — post-refactor public API; no cleanup

### Hot-path audit targets (D-04)
- `Display.lua` — per-widget `cachedSpellID` / `cachedIcon` change-detection introduced Phase 22; verify no per-frame table allocation
- `BuffEngine.lua:OnUnitAura` / `ns:DispatchEventToProviders` — dispatcher-first pattern from Phase 19; verify no closure/table churn per event
- `BuffEngine.lua:ScanActiveTimersForCancellation` — `aliveBuffs` iteration from Phase 22; already uses only primitive reads

### Release/packaging state (verified clean)
- `.toc` 7-line file list includes `Providers.lua` (since Phase 17); `CDMTab.lua` loads via `CDMTab.xml:3`
- `.pkgmeta` ignores `.gitignore`, `.pkgmeta`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, `LICENSE`, `scripts`, `*.png`, `RELEASE_NOTES.md`
- CI workflow: `BigWigsMods/packager@v2`, tag-triggered, extracts first `##` section of CHANGELOG.md into `RELEASE_NOTES.md`

</code_context>

<specifics>
## Specific Ideas

- User quote (this phase): "No details, only say it's a internal file reworking, and mention performance change if we have any."
- User quote (this phase): "we can ignore the need to fix evoker lust, it seems to be working correctly now"
- User quote (this phase): M+ Lua errors were "related to integration with other addons, can be marked as solved"
- Phase 16 precedent still applies: keep the cleanup phase tight — no surprise refactors

</specifics>

<deferred>
## Deferred Ideas

- Full data-storage rework / icon-resolution unification beyond provider boundary — still deferred per Phase 16 D-01 (user intent for a future milestone)
- Any broader addon-wide hot-path audit beyond the three touched paths — out of scope; targeted check only
- Commenting the hardcoded `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` with their CSV source lineage — CSVs are being deleted, source-of-truth is now the Lua arrays themselves

### Reviewed Todos (not folded)
None — both pending todos are closed as solved (D-05, D-06), not deferred.

</deferred>

---

*Phase: 24-cleanup*
*Context gathered: 2026-04-22*
