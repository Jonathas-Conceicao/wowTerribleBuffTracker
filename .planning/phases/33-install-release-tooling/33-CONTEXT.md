# Phase 33: Install & Release Tooling - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning

<domain>
## Phase Boundary

A deployed dev build is honest about what it is and what it contains, and `release.bat` cannot tag from
the wrong branch.

In scope: `scripts/install.bat`, a new `scripts/install.ps1`, `scripts/release.bat`.
Out of scope: the TOC (Phase 31), packaging (Phase 32), any retail verification (Phase 44).
</domain>

<decisions>
## Implementation Decisions

### Where the logic lives
- The deploy logic moves to **`scripts/install.ps1`**, with `install.bat` reduced to a wrapper that
  forwards to it. Batch cannot parse the TOC, follow XML includes and substitute a version without
  becoming unreadable, and all three are required here.
- `./scripts/install.bat` stays the documented entry point, unchanged for the caller — `CLAUDE.md` and
  the user's own habit both reference it.

### File set (INST-09)
Derived, never enumerated:
1. every non-directive, non-blank line of the TOC (the load list),
2. anything a `.xml` in that list references via `file="..."` (`CDMTab.xml` → `CDMTab.lua`),
3. the file named by `## IconTexture:`, resolved by extension since the TOC omits it,
4. the TOC itself.

A referenced file that does not exist is a hard error, preserving the old script's fail-fast behaviour.

### Version string (INST-05/INST-06)
- `git describe --tags --always --dirty` plus a literal `-dev` suffix.
- The `-dev` is unconditional. `git describe` on an exact tag returns just the tag, which sitting in a
  dev folder would read as a real release — worse than the raw keyword, which at least announces that
  it is unsubstituted.
- Substitution happens **into the deployed copy only**. The repo TOC keeps `@project-version@`; that
  keyword is what the packager expands for real releases and breaking it would break releases.
- Written without a BOM.

### Pruning (INST-07/INST-08)
- Anything in the deployed folder that is not in the derived set is deleted.
- Safe by construction: SavedVariables live under `WTF\`, never in the AddOns folder, so nothing a
  player owns is reachable.

### Branch guard (REL-01)
- `release.bat` refuses unless `HEAD` is on `main`, because it tags `HEAD` and then pushes `origin main`
  — from any other branch those two are different commits.
- `TBT_ALLOW_BRANCH=1` overrides, printing a warning.
- `main` rather than "any non-milestone branch", because the established workflow is to squash-merge the
  milestone branch into `main` and release from there.
</decisions>

<code_context>
## Existing Code Insights

### Established Patterns
- The old `install.bat` used an explicit `FILES` list rather than a glob on purpose: `.#Display.lua`
  emacs lock files match `*.lua`. Deriving from the TOC keeps that protection — a lock file is never in
  the TOC.
- Deploys to every client folder present, skips absent ones, exits non-zero naming the root when none
  are found. All preserved.

### Integration Points
- `CLAUDE.md`'s Architecture section describes `install.bat`; it gains `install.ps1` alongside.
</code_context>

<specifics>
## Specific Ideas

None.
</specifics>

<deferred>
## Deferred Ideas

None — the three pending tooling todos this phase resolves were all in scope.
</deferred>
