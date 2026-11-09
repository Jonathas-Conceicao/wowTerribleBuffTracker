# Phase 84: Cleanup - Context

**Gathered:** 2026-11-09
**Status:** Ready for planning
**Mode:** Autonomous kickoff (standard cleanup phase, per CLAUDE.md)

<domain>
## Phase Boundary

The standard end-of-milestone cleanup, covering what Phases 80-83 introduced.

</domain>

<decisions>
## Implementation Decisions

- **Scope:** CLAUDE.md's cleanup mandate covers duplication and dead code that Phases 80-83
  introduced. PROJECT.md's "No refactors during cleanup phases" protects everything that predates
  the milestone.
- **Hot paths:** review what the new rows, groups and familiar click touch (the reminder aura
  refresh, `ReminderClick.lua`'s `Flush` and `Place`, the `BAG_UPDATE_DELAYED` branch). Give each a
  verdict and add no per-event allocation. The cosmetic costs in research §12.4 (more spellbook
  scans after a spellbook change, longer "Also satisfied by" rows) are noted, not optimised.
- **Checks:**
  - `stylua .` leaves no diff;
  - `git ls-files --eol` shows CRLF for every touched Lua file;
  - `node scripts/aura-read-gate.js` passes;
  - `node scripts/reminders-doc-check.js` passes, as does its `--selftest`;
  - the release scripts and `.pkgmeta` are reviewed.
- **Deploy:** run `./scripts/install.bat` at the end, ready for the user's Phase 85 test pass.

### Claude's Discretion
- Everything else in the cleanup.

</decisions>

<code_context>
## Existing Code Insights

Files touched this milestone: `Providers.lua`, `ReminderClick.lua`, `Core.lua` (one line),
`docs/REMINDERS.md`, `scripts/reminders-doc-check.js`, `.pkgmeta`, `CLAUDE.md`.

</code_context>

<specifics>
## Specific Ideas

None.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
