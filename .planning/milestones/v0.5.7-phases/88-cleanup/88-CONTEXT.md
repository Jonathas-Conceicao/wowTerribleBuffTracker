# Phase 88: Cleanup - Context

**Gathered:** 2026-11-10
**Status:** Ready for planning
**Mode:** Autonomous kickoff; standing CLAUDE.md cleanup rule.

<domain>
## Phase Boundary

CLEAN-02: clean only what this milestone (Phases 86-87) introduced. Pre-existing code is protected
by PROJECT.md's "No refactors during cleanup phases" decision.

</domain>

<decisions>
## Implementation Decisions

- Review `git diff main...HEAD -- '*.lua' scripts/` for unused locals, dead branches, and
  duplication the milestone added; unify only that.
- Hot paths touched: the load refresh in `Core.lua` and the `BAG_UPDATE_DELAYED` re-mark. No new
  per-frame work, no allocation per call (no table or string built per refresh).
- Suggested offer: the item-count read happens only when the offer list is built, not per frame.
- `stylua .` from the repo root leaves no diff; `git ls-files --eol` shows CRLF intact for touched
  `.lua` files and no change to touched `.md` files' endings.
- Release scripts (`scripts/release.bat`, `.github/workflows/release.yml`, `.pkgmeta`,
  `scripts/install.ps1`) are unchanged or checked; the TOC load list is unchanged.
- `node scripts/reminders-doc-check.js`, its `--selftest`, `node scripts/aura-read-gate.js` (and its
  `--selftest`) pass.

### Claude's Discretion
- Everything inside the rules above.

</decisions>

<code_context>
## Existing Code Insights

Phase 86-87 summaries list the touched files and functions.

</code_context>

<specifics>
## Specific Ideas

None.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
