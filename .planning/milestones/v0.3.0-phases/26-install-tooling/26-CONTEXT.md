# Phase 26: Install Tooling - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous run — user unavailable, all decisions at Claude's discretion and flagged for review)

<domain>
## Phase Boundary

A single, argument-free `scripts/install.bat` deploys the shared addon file set and both flavor TOCs to every WoW client actually present on the machine, skipping absent ones and failing loudly when none are found.

Requirements owned: INST-01, INST-02, INST-03, INST-04.

**Not this phase:** the TOC split itself (Phase 25), packaging or release changes (Phase 29 — not in this run), any Lua change (Phase 27).

</domain>

<decisions>
## Implementation Decisions

### Client discovery

- **D-01:** WoW root stays `%PROGRAMFILES(x86)%\World of Warcraft`, matching today's script, but becomes overridable via a `%TBT_WOW_ROOT%` environment variable if set. Cheap, and covers a non-default install without adding an argument (INST-01 requires argument-free operation).
- **D-02:** Enumerate a fixed list of known flavor directories under the root and install to each that exists:
  `_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`, `_classic_`, `_classic_era_`, `_classic_ptr_`
  Verified present on this machine today: `_retail_`, `_beta_`, `_ptr_`, `_classic_beta_`. **`_classic_beta_` is the Forever beta** (product `wow_classic_beta`, build `1.60.1.x`) — confirmed via `.build.info` and `.flavor.info` during milestone research.
- **D-03:** Use a fixed list rather than globbing `_*_` directories. A glob would pick up any future or unrelated folder shape; the fixed list is auditable and trivially extended. `FTOOL-02` already tracks adding a `_forever_` entry if Forever gets its own product folder at GA.
- **D-04:** Do not attempt to detect *which* flavor a folder is and copy only its TOC. Both TOCs go to every client — the client selects its own by suffix. This is what research concluded and it keeps the script flavor-agnostic.

### Failure behavior

- **D-05:** An absent flavor directory is skipped silently — no warning, no nonzero exit (INST-02). Most users have one or two clients; warning about the other five would be noise.
- **D-06:** Track an installed-count. If it is zero after the loop, print a clear diagnostic naming the root that was searched and `exit /b 1` (INST-03). This is the one loud failure.
- **D-07:** Print one line per successful install target so the user can see where it landed. Keep the existing friendly closing line about `/reload`.

### File list

- **D-08:** Keep an **explicit** file list rather than globbing `*.lua *.xml *.toc *.blp`. Rationale: the repo root contains emacs lock files of the form `.#Display.lua`, which **would match a `*.lua` glob** and get copied into the addon folder. An explicit list cannot be fooled by editor droppings.
- **D-09:** The list grows from 9 entries to 10 — `TerribleBuffTracker.toc` is replaced by `TerribleBuffTracker_Mainline.toc` **and** `TerribleBuffTracker_Camelot.toc` (INST-04).
- **D-10:** Define the file list **once** at the top of the script and iterate it per client, rather than repeating nine `copy` lines per target. This is the "unify repeated behavior" that Phase 30's cleanup criterion would otherwise flag, done correctly the first time.
- **D-11:** Known and accepted: this list is hand-maintained and is the third of three file lists in the repo (TOC load list = 6 entries, this list = 10, packaged zip = `.pkgmeta` ignore-driven). They are **not** interchangeable — `CDMTab.lua` is in this list but deliberately absent from the TOC, because it loads via `<Script file="CDMTab.lua"/>` inside `CDMTab.xml`. Do not "reconcile" them.

### Scope discipline

- **D-12:** `scripts/release.bat` is not touched here. Phase 25 adds the TOC guard invocation to it; this phase only changes `install.bat`.
- **D-13:** Phase 25's `scripts/check-toc.ps1` may optionally be invoked from `install.bat` in **warn-only** mode (per Phase 25's D-12), but this is explicitly optional — if it complicates the batch logic, skip it. The authoritative guard lives at the pre-tag gate.

### Claude's Discretion

The entire phase was auto-discussed. D-01 (`%TBT_WOW_ROOT%` override) and D-02 (which flavor folders to target) are the two worth a human glance — see Deferred Questions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope
- `.planning/ROADMAP.md` — Phase 26 goal and its four success criteria
- `.planning/REQUIREMENTS.md` — INST-01..04 exact wording
- `.planning/PROJECT.md` — Context section records the Forever install path and interface number

### Depends on
- `.planning/phases/25-toc-split-retail-regression-gate/25-CONTEXT.md` — D-01/D-02 fix the two TOC filenames this script must copy; read before assuming names
- `scripts/check-toc.ps1` — created by Phase 25; only relevant if D-13's optional warn-only hook is implemented

### Code
- `scripts/install.bat` — the file being rewritten; current form hardcodes `_retail_` and repeats nine `copy /Y` lines
- `scripts/release.bat` — reference for the established `if errorlevel 1 ... exit /b 1` failure idiom used in this repo

### Environment facts (verified 2026-09-18)
- `C:\Program Files (x86)\World of Warcraft\` contains `_retail_`, `_beta_`, `_ptr_`, `_classic_beta_`
- `_classic_beta_\.flavor.info` → `wow_classic_beta`; `.build.info` → `1.60.1.69893` — this is the Forever beta

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/install.bat` already computes `%~dp0..\` as SOURCE — keep that.
- `scripts/release.bat` demonstrates the repo's batch conventions: `@echo off`, `setlocal enabledelayedexpansion`, `if errorlevel 1 (...) exit /b 1`.

### Established Patterns
- CLAUDE.md's workflow says `./scripts/install.bat` runs after every change to deploy — so this script runs constantly and must stay fast and quiet on the happy path.
- The current script creates the destination with `if not exist "%DEST%" mkdir "%DEST%"` — preserve that per target.

### Integration Points
- Output lands at `<root>\<flavor>\Interface\AddOns\TerribleBuffTracker\`.
- Nothing else in the repo calls `install.bat`; it is a developer convenience, not part of CI.

</code_context>

<specifics>
## Specific Ideas

- The user chose "Install to both, always" over a flavor argument and over a separate `install-forever.bat`, with the stated reason that it is the simplest possible change and keeps `./scripts/install.bat` working exactly as it does today. Argument-free operation is therefore a hard constraint, not a preference — D-01's env-var override exists precisely so a non-default install path does not force an argument.

</specifics>

<deferred>
## Deferred Ideas

- **A dedicated `_forever_` entry** — `FTOOL-02`, for if Forever gets its own product folder at GA rather than piggybacking `_classic_beta_`.
- **Deriving the copy list from the TOC** — tempting, but the TOC deliberately omits `CDMTab.lua` and the `.blp` icon, so it cannot be the single source of truth. Not worth solving.

</deferred>

<deferred_questions>
## Deferred Questions for Human Review

1. **D-02 — flavor folder list.** Installing to `_ptr_` and `_beta_` (Midnight PTR/beta) as well as `_retail_` and `_classic_beta_`. Harmless — the client just flags out-of-date if the interface differs — and matches INST-01's "every client present". Say if you would rather it only ever touch `_retail_` and the Forever folder.
2. **D-01 — `%TBT_WOW_ROOT%` override.** A small addition beyond the literal requirement, added so a non-default WoW install does not force an argument the requirement forbids. Trivial to drop if unwanted.

</deferred_questions>

---

*Phase: 26-Install Tooling*
*Context gathered: 2026-09-18 (autonomous)*
