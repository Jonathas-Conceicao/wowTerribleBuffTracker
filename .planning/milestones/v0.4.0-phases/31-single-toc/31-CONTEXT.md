# Phase 31: Single TOC - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Collapse TBT's two flavour-suffixed TOCs into one `TerribleBuffTracker_Mainline.toc` declaring every
supported interface version, and remove the machinery that existed only to keep two TOCs in sync.

In scope: the TOC itself, `scripts/check-toc.ps1`, the `_Camelot` references in `install.bat`,
`release.bat`, `CLAUDE.md` and `.gitattributes`, and clearing orphaned TOCs out of the deployed client
folders so nothing stale loads.

Out of scope: packaging config (Phase 32), `install.bat`'s version substitution and pruning
(Phase 33), and **any retail verification at all** (Phase 44).
</domain>

<decisions>
## Implementation Decisions

### TOC Form
- Follow the pattern a shipping addon already uses on Forever:
  `_classic_beta_\Interface\AddOns\Platynator\Platynator.toc` declares
  `## Interface: 120100, 16001, 50504, 38001, 20506, 11509` in one file.
- **No `## AllowLoadGameType:` line.** The user checked and no addon they saw on Forever uses it.
  `tools/TBTProbe/TBTProbe.toc` did declare it and loaded on both clients, but Platynator is the
  pattern to match, and it does not.
- TBT's line becomes `## Interface: 120100, 16001` — retail first, matching Platynator's ordering
  (newest interface first).
- `## Notes:` widens from "WoW Midnight" to "WoW Midnight and WoW Forever" now that one file serves both.

### Verification Approach
- **No probe phase, no gate.** User decision 2026-09-20: trust the community information and the
  shipping-addon pattern, implement it directly, and fix anything that turns out not to work. A rollback
  here is one file and one `install.bat` run.
- The earlier framing of this phase — read `C_AddOns.GetAddOnMetadata(..., "Interface")` in-game with
  `_Camelot.toc` retained as rollback — was dropped for that reason.
- Retrospective note, settled from disk rather than in-game: `_classic_beta_` held **only**
  `TerribleBuffTracker_Camelot.toc` before this phase, so v0.3's Forever verification pass
  unambiguously ran against the Camelot TOC. The `TOC-02` ambiguity recorded in `999.3` is closed, and
  the v0.3 Forever pass stands.

### Flavour Scope
- **Forever only.** User decision 2026-09-20: no retail check happens anywhere in this milestone before
  Phase 44. `install.bat` still deploys to retail — it is simply not exercised there until the retail
  validation pass.

### Deployed Folder Hygiene
- The orphaned `TerribleBuffTracker_Camelot.toc` is removed from every client folder that held one,
  because the repo file it mirrors no longer exists.
- The pre-existing stale unsuffixed `TerribleBuffTracker.toc` in `_beta_` and `_ptr_` is **left alone** —
  that is `INST-07`/`INST-08` in Phase 33, and both clients are out of deployment scope anyway.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/TBTProbe/TBTProbe.toc` — the only multi-interface TOC TBT has ever shipped anywhere; loaded on
  both `_retail_` and `_classic_beta_` during the 2026-09-20 experiment session. Direct evidence the
  comma form is accepted.
- `.pkgmeta-mainline` is the surviving packaging config; it becomes `.pkgmeta` via `git mv` so history
  follows.

### Established Patterns
- Both TOCs already carried an identical file list, so there is nothing to reconcile — the Camelot file
  differed on `## Interface:` and `## Notes:` only, which `check-toc.ps1` enforced.
- `install.bat` uses an explicit `FILES` list rather than a glob, deliberately: `.#Display.lua` emacs
  lock files match `*.lua`.

### Integration Points
- `scripts/release.bat` invoked `check-toc.ps1` as a pre-tag gate; that call must go when the script does,
  or every release aborts.
- `.gitattributes` pinned `.pkgmeta-* text eol=lf`; the glob no longer matches anything.
- `CLAUDE.md`'s Key Constraints and Architecture sections both describe the two-TOC design as binding.
</code_context>

<specifics>
## Specific Ideas

The user supplied the exact reference to copy:
`C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Platynator\Platynator.toc`.
</specifics>

<deferred>
## Deferred Ideas

- `install.bat` deriving its file list from the TOC instead of duplicating it — `INST-09`, Phase 33.
- Pruning stale files and the leftover unsuffixed TOCs — `INST-07`/`INST-08`, Phase 33.
- Confirming the single TOC on retail — `VER-10`, Phase 44.
</deferred>
