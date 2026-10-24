# Phase 77: Cleanup - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning
**Mode:** Process-only phase; context front-loaded for the autonomous run (73-77)

<domain>
## Phase Boundary

The milestone's mandated cleanup pass (CLAUDE.md "GSD Workflow"): clean up unused variables and
definitions, unify repeated behaviour **this milestone introduced** into shared functions, review hot
paths, and check release and install scripts. No requirements of its own.

</domain>

<decisions>
## Implementation Decisions

### Scope
- Only code changed by Phases 73-76. `PROJECT.md`'s "No refactors during cleanup phases" protects
  everything older (settled 2026-09-18) — the two rules are complementary.
- Likely unification targets: buff field handling across spell and item dialogs, buff timer
  start/end across the userCd and bag-item cast paths, swipe colour/state switching.
- Hot paths: `Display.lua` render tick (`RenderIconContainer`, `ApplyCooldownSlot`,
  `ApplyUserCooldown`, any new buff-state helper), the cast handlers in `Providers.lua`, and
  `ns:RefreshAuraStates`. Written verdict per path: no per-tick allocation, no redundant game calls,
  dirty checks where a value can be stamped.
- Dead code: anything introduced and left unreferenced; stale comments; `ns.*` fields nobody reads;
  saved keys never written.
- Scripts: `scripts/install.ps1` / `install.bat` (now `_forever_`), `scripts/release.bat`, `.pkgmeta`,
  `scripts/aura-read-gate.js` and `scripts/migrate-dryrun.js` self-tests; `stylua .` clean.
- CLAUDE.md "Architecture" list updated if any file was added/removed/repurposed.
- Re-verify every "lost its only reader" claim with a tree-wide grep before deleting (v0.5.2 lesson:
  `ns.SPELL_CATEGORY_COMBAT_POTION`).

### Claude's Discretion
- Findings ordering and plan split.

</decisions>

<code_context>
## Existing Code Insights

- Earlier cleanup phases: v0.5.2 Phase 71, v0.5.1 Phase 65 — same mandate.

</code_context>

<specifics>
## Specific Ideas

- In-game checks deferred to Phase 78.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
