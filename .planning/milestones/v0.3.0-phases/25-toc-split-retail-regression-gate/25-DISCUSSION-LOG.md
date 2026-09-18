# Phase 25: TOC Split & Retail Regression Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-18
**Phase:** 25-TOC Split & Retail Regression Gate
**Areas offered:** TOC divergence policy, Guard placement & language, Retail gate pass criteria, Forever load check (this phase or 28?)
**Areas discussed:** TOC divergence policy, Forever load check (this phase or 28?)

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| TOC divergence policy | What may differ between `_Mainline` and `_Camelot` beyond `## Interface:` | ✓ |
| Guard placement & language | Where the drift guard lives, when it fires, and what it is written in | |
| Retail gate pass criteria | What must be observed to call VER-01 passed; whether SavedVariables is explicitly checked | |
| Forever load check: this phase or 28? | Whether Phase 25 is a dual gate or retail-only | ✓ |

**Notes:** The two unselected areas were delegated to Claude's discretion and recorded as D-12 through D-15 in CONTEXT.md with explicit rationale, so the planner can refine rather than re-derive them.

---

## TOC divergence policy

### Q1 — How much may the two TOC files diverge?

| Option | Description | Selected |
|--------|-------------|----------|
| Interface only — byte-identical otherwise | Strictest; trivial exact-match guard. Cost: Notes keeps saying "for WoW Midnight" on Forever | |
| Interface + Notes | Each flavor gets an accurate AddOns-list description; guard excludes two allowlisted lines | ✓ |
| Interface + Notes + Category | Also allows per-flavor Category in case Forever rejects the retail taxonomy | |

**User's choice:** Interface + Notes
**Notes:** Category deliberately left identical despite the third option being available. Whether Forever accepts `Buffs & Debuffs, Combat` is unverified — logged as research question 1 rather than pre-emptively diverged.

### Q2 — What should each TOC's `## Notes:` line say?

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror the current phrasing | Keep existing voice, swap the game name only | ✓ |
| Drop the game name entirely | Both TOCs identical and accurate forever; Notes leaves the allowlist | |
| Mention the CDM dependency | Use the line to convey the hard Cooldown Manager requirement | |

**User's choice:** Mirror the current phrasing
**Notes:** Yields `...for WoW Midnight` on `_Mainline` (unchanged from today) and `...for WoW Forever` on `_Camelot`.

### Q3 — How should the two TOC files be produced from the existing one?

| Option | Description | Selected |
|--------|-------------|----------|
| `git mv`, then copy for Camelot | Preserves file history; copying prevents suffix-typo and CRLF drift | ✓ |
| Two fresh files, delete the old | Cleaner diff intent, but loses rename history and risks a hand-typed suffix | |
| You decide | Delegate the mechanics to the planner | |

**User's choice:** `git mv`, then copy for Camelot
**Notes:** Directly mitigates research pitfall 2 — a lowercase `_camelot.toc` is invisible on case-insensitive NTFS but fails on the Linux CI runner. `git ls-files` is the verification of record, not a Windows file browser.

---

## Forever load check: this phase or 28?

### Q1 — Where does the first "does it actually load on Forever?" check happen?

| Option | Description | Selected |
|--------|-------------|----------|
| Smoke-test in 25 — true dual gate | Proves the `_Camelot` suffix before Phases 26/27/29 build on it | ✓ |
| Existence only in 25, full load in 28 | Keeps Phase 25 offline; matches the roadmap's current criteria but leaves the suffix unproven | |
| Smoke-test in 25, move TOC-02 to 28 | De-risk early but sign the requirement off in 28 for tidier traceability | |

**User's choice:** Smoke-test in 25 — true dual gate
**Notes:** Resolves a genuine inconsistency in ROADMAP.md, where Phase 25's goal says the source set "loads correctly on both" but its success criterion 2 only required the Camelot TOC to exist. TOC-02 stays formally owned by Phase 25.

### Q2 — How deep should the Phase 25 Forever smoke-test go?

| Option | Description | Selected |
|--------|-------------|----------|
| Appears + loads, no Lua error | Narrowest check that proves the suffix; tolerates CDM/SavedVariables problems as Phase 28 findings | ✓ |
| Also require the load line and `/tbt` | Confirms init ran, but couples the gate to CDM being present on Forever | |
| You decide | Let the planner set the bar | |

**User's choice:** Appears + loads, no Lua error
**Notes:** Explicitly excluded from being Phase 25 failures: CDM unreachable or tab absent, SavedVariables not persisting (known beta defect on build `1.60.1.69893`), empty Trinket/Pot/Lust tiles. All are recorded for Phase 28 instead.

### Q3 — If the Forever smoke-test fails, what should the phase do?

| Option | Description | Selected |
|--------|-------------|----------|
| Stop and bring it to me | Halt, report diagnostics, let the user pick the next suffix | ✓ |
| Auto-try the documented fallbacks | Work through `_Vanilla`, then unsuffixed, until one loads | |
| Fall back to a single unsuffixed TOC | Abandon the split for Forever and defer it | |

**User's choice:** Stop and bring it to me
**Notes:** Both workaround options were explicitly rejected. Required diagnostics before asking: the suffix Blizzard's own TOCs use inside the live `_classic_beta_` client, `.flavor.info` contents, `C_AddOns.GetAddOnInfo("TerribleBuffTracker")` output, and the AddOns list state.

---

## Claude's Discretion

Delegated by declining the corresponding gray areas. Captured as decisions with rationale in CONTEXT.md so they are reviewable rather than implicit.

| Item | Default chosen | Rationale |
|------|----------------|-----------|
| D-12 Guard placement | `scripts/release.bat`, pre-tag, nonzero exit aborts | TOC-05 calls it a pre-tag guard; the real cost of drift is the packager hard-erroring the whole release at tag time. Blocking local deploys would be noise; CI catches it only after push. |
| D-13 Guard language | PowerShell `scripts/check-toc.ps1` called from `release.bat` | Batch cannot cleanly diff two bodies while excluding allowlisted lines. Standalone script stays CI-callable later. |
| D-14 Guard checks | Interface range regex per flavor; body diff excluding the two allowlisted lines, CRLF-insensitive; `.pkgmeta-<flavor>` cross-ignore check that no-ops while those files are absent | Covers pitfalls 2 and 3 directly and mechanically enforces the locked one-shared-file-list decision. |
| D-15 Retail gate criteria | AddOns list + load line + `/tbt` opens; SavedVariables continuity by reasoning, not a migration test | The rename touches only the TOC filename, never the folder name or `## SavedVariables:`, so the WTF path is unchanged. A dedicated test is not warranted. |
| D-16 DOC-01 placement | `CLAUDE.md` `## Style Reference` + `## Key Constraints`, kept terse | PROJECT.md already holds the fuller Forever context; CLAUDE.md should stay a quick-reference. |

---

## Deferred Ideas

- **Per-flavor `## Category:` strings** — pending research question 1. If Forever rejects the retail taxonomy, adding a third allowlisted divergence line is the user's call, not the planner's.
- **Guard invocation from CI** — the guard is a standalone script so CI can call it later; wiring belongs to Phase 29 or beyond.
- **A dedicated `_forever_` install path** — `FTOOL-02`, for if Forever gets its own product folder at GA instead of piggybacking `_classic_beta_`.

---

## Findings Surfaced During Scouting

Recorded here because they changed the shape of the discussion.

- **`CDMTab.lua` is not in the TOC** — it loads via `<Script file="CDMTab.lua"/>` inside `CDMTab.xml`. Three distinct file lists exist (TOC load list, `install.bat` copy list, packaged zip); TOC-03's "identical file list" means the two TOC bodies only.
- **The TOC is CRLF-encoded** — a naive body-diff guard on a Linux runner would trip over this, which is why D-14 requires a CRLF-insensitive comparison.
- **Repo-root noise is gitignored** — `TerribleBuffTracker.zip` and the emacs `#...#` autosave files are already covered by `.gitignore`; not a problem to fix.
