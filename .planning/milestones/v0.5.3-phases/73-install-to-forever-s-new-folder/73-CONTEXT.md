# Phase 73: Install to Forever's New Folder - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning
**Mode:** Infrastructure phase; context front-loaded for the autonomous run (73-77)

<domain>
## Phase Boundary

`scripts/install.ps1` deploys to `World of Warcraft\_forever_` instead of `_classic_beta_`, and
`CLAUDE.md` names the new folder and product. Requirement INST-11. Nothing else changes.

</domain>

<decisions>
## Implementation Decisions

### Facts (checked on disk 2026-10-22)
- `World of Warcraft\.build.info` lists Forever as product **`wowf`**, version **1.60.1.70532**;
  `_forever_\.flavor.info` reads `wowf`. Interface stays **16001**, so `TerribleBuffTracker.toc`
  (`## Interface: 120100, 16001`) does **not** change.
- `_forever_\Interface\AddOns\TerribleBuffTracker` already exists (a hand copy) — install.ps1's prune
  logic will treat it like any other target.
- `_classic_beta_` still exists on disk (product `wow_classic_beta`, the old Forever beta). The user
  asked to install to `_forever_` **instead of** `_classic_beta_`, so drop `_classic_beta_` from the
  list; do not delete anything already deployed there.

### Scope
- `scripts/install.ps1:29` — the `$flavors` list: replace `'_classic_beta_'` with `'_forever_'`. Keep
  the other entries as they are.
- `CLAUDE.md` "Key Constraints" bullet "One TOC, all flavours": name `World of Warcraft\_forever_`,
  product `wowf`, build 1.60.1.70532, instead of the `_classic_beta_` / `wow_classic_beta` /
  1.60.1.69913 wording. Keep the bullet's history sentence about superseding the two-TOC split.
- `tools/TBTProbe/install-probe.bat` already targets `_forever_` (done at kickoff, commit `fb95a3d`).
- Historical `.planning/` documents that mention `_classic_beta_` are records and stay untouched.

### Claude's Discretion
- Whether README.md needs a line (it currently names no install folder — grep before touching).

</decisions>

<code_context>
## Existing Code Insights

- `scripts/install.bat` forwards to `install.ps1`; `install.ps1` derives the file set from the TOC,
  substitutes a dev version into the deployed TOC only, and prunes files the repo no longer has.
- No Lua file references the install folder.

</code_context>

<specifics>
## Specific Ideas

- Verify by running `./scripts/install.bat` and confirming it reports `_retail_` and `_forever_` and
  no `_classic_beta_`.
- In-game checks deferred to Phase 78 (retail only; Forever servers down).

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
