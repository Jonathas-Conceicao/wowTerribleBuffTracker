# Phase 71: Cleanup - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Mode:** Process-only phase; context front-loaded for the autonomous run (67-71)

<domain>
## Phase Boundary

The milestone's mandated cleanup pass (CLAUDE.md "GSD Workflow"): clean up unused variables and
definitions, unify repeated behaviour **this milestone introduced** into shared functions, review hot
paths (especially display refresh and the re-anchor placement pass), and check release and install
scripts. No requirements of its own.

</domain>

<decisions>
## Implementation Decisions

### Scope
- Only code changed by Phases 67-70. `PROJECT.md`'s "No refactors during cleanup phases" protects
  everything older (settled 2026-09-18) — read the two rules as complementary.
- Hot paths: `Display.lua` render tick (`RenderIconContainer`, `RenderBarContainer`, `SlotDraws`),
  `MergeReanchor.lua` placement and style application, `MergeMode.lua` shown-slot pass. No per-tick
  allocation, no redundant game calls, dirty checks where a value can be stamped.
- Dead code: anything left unreferenced by the racial removal (67) and the redraw-path removal (70),
  including stale comments naming deleted functions, `ns.*` fields nobody reads, and saved-data keys no
  longer written.
- Scripts: `scripts/install.ps1` (file set derived from the TOC), `scripts/release.bat`, `.pkgmeta`,
  `scripts/aura-read-gate.js` and `scripts/migrate-dryrun.js` self-tests; `stylua .` clean.
- CLAUDE.md "Architecture" list updated for any file added/removed/repurposed this milestone
  (`MergeReanchor.lua`).

- **Do NOT delete `ns.SPELL_CATEGORY_COMBAT_POTION`** (Core.lua). `70-04-PLAN.md` once listed it as a cleanup
  candidate; that was wrong — the Pot tracker still reads it at `Providers.lua` for its unresolved icon
  (Phase 70 review WR-01). Re-verify every "lost its only reader" claim with a tree-wide grep before deleting.
- Phase 70 review fixes already trimmed the dead merge-mirror fields (`linkedSpellIDs`, `hideAura`,
  `hasCharges`, `selfAura`) and split MergeReanchor.lua's OPEN ITEM block into Settled / Known limitations.

### Claude's Discretion
- Findings ordering and plan split.

</decisions>

<code_context>
## Existing Code Insights

### Established Patterns
- Earlier cleanup phases: v0.5.1 Phase 65 (3 plans), v0.5.0, v0.4.x — same mandate.

</code_context>

<specifics>
## Specific Ideas

- In-game checks deferred to Phase 72.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
