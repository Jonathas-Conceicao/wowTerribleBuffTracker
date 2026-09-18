# Phase 25: TOC Split & Retail Regression Gate - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the single `TerribleBuffTracker.toc` with two flavor-suffixed TOC files — `TerribleBuffTracker_Mainline.toc` (Interface 120100, Midnight retail) and `TerribleBuffTracker_Camelot.toc` (Interface 16001, WoW Forever) — sharing one unforked Lua/XML source set. Prove in-game that **both** clients load the addon from their respective TOC before any downstream phase builds on the split. Add a local drift guard over the TOC pair and the `.pkgmeta-<flavor>` files. Record the Forever API reference and install path in `CLAUDE.md`.

Requirements owned: TOC-01, TOC-02, TOC-03, TOC-04, TOC-05, VER-01, DOC-01.

**Not this phase:** `install.bat` multi-client support (Phase 26), the `Providers.lua` at-rest guard (Phase 27), the full 12-step Forever checklist (Phase 28), the `.pkgmeta` split and `release.yml` matrix (Phase 29). Phase 25 only *creates* the guard; the `.pkgmeta-<flavor>` files it validates do not exist until Phase 29, so the guard must tolerate their absence.

</domain>

<decisions>
## Implementation Decisions

### TOC divergence policy

- **D-01:** The two TOCs may diverge on **exactly two lines** — `## Interface:` and `## Notes:`. Everything else, the file list included, must be byte-identical.
- **D-02:** `## Notes:` mirrors the existing phrasing with the game name swapped:
  - `_Mainline.toc` → `Manual buff/cooldown timer tracking for WoW Midnight` (unchanged from today)
  - `_Camelot.toc` → `Manual buff/cooldown timer tracking for WoW Forever`
- **D-03:** `## Category: Buffs & Debuffs, Combat` stays **identical** in both files. Whether Forever accepts those category strings is unverified — see Research Questions. If it does not, that is a finding to report, not a licence to diverge a third line without asking.
- **D-04:** Rename mechanics: `git mv TerribleBuffTracker.toc TerribleBuffTracker_Mainline.toc` to preserve file history, then **copy** `_Mainline` to `_Camelot` and edit only the two allowlisted lines. Never hand-type the `_Camelot` suffix — copy it. Verify the committed filename's capitalisation with `git ls-files`, never a Windows file browser (NTFS is case-insensitive; the packager's glob and GitHub's Linux runner are not).
- **D-05:** Both TOCs are CRLF-encoded, matching the current file. The copy in D-04 preserves this for free; the drift guard must not be confused by it.

### Forever load gate

- **D-06:** Phase 25 is a **true dual gate**. Both of these must pass before Phase 26, 27 or 29 begins:
  1. A real retail client loads TBT from the renamed `_Mainline.toc` (VER-01)
  2. A real Forever beta client shows TBT in the AddOns list and loads it from `_Camelot.toc` (TOC-02)
- **D-07:** TOC-02 stays formally owned by Phase 25, not deferred to Phase 28. The suffix must be proven here.
- **D-08:** The Forever smoke-test bar is deliberately narrow — **appears in the AddOns list and loads with no Lua error at login.** It answers exactly one question: does the client read this TOC?
- **D-09:** The following are **explicitly NOT Phase 25 failures** and must be recorded for Phase 28 rather than treated as gate failures: CDM unreachable or the TBT tab absent; SavedVariables not persisting (a known defect on beta build `1.60.1.69893`); empty Trinket/Pot/Lust tiles. Do not couple the gate to CDM being present — a Forever CDM problem must not read as a TOC failure.
- **D-10:** Deploying to Forever for this smoke-test may be a **manual file copy**. Phase 25 must not wait on Phase 26's `install.bat` work.
- **D-11:** If the Forever smoke-test fails (TBT never appears), **stop the phase and report to the user.** Do not auto-try fallback suffixes and do not fall back to a single unsuffixed TOC. Collect and present first:
  - the suffix Blizzard's own TOC files use inside the live `_classic_beta_` client
  - `.flavor.info` contents for that install
  - `C_AddOns.GetAddOnInfo("TerribleBuffTracker")` output
  - the AddOns list state

  Then ask which suffix to try next.

### Claude's Discretion

The user declined to discuss these two areas and delegated them. Defaults chosen with rationale — the planner may refine but should not silently reverse.

- **D-12 (guard placement):** Put the drift guard in **`scripts/release.bat`, before the tag is created**, exiting nonzero to abort the release on failure. Rationale: it is a *pre-tag* guard per TOC-05, and a mismatch's real cost is the packager hard-erroring the whole release at tag time (PITFALLS #3). `install.bat` runs more often, but blocking a local deploy over a TOC mismatch is noise, and CI only catches it after the push. Optionally also invoke it from `install.bat` in warn-only mode.
- **D-13 (guard language):** Implement the guard as **PowerShell** (`scripts/check-toc.ps1`), invoked from `release.bat`. Rationale: batch cannot diff two file bodies while excluding allowlisted lines without real pain, and PowerShell is already present on the user's Windows machine. Keeping it a standalone script also makes it callable from CI later without a rewrite.
- **D-14 (guard checks):** Three assertions —
  1. `_Mainline.toc`'s `## Interface:` matches `^12[0-9]{4}$`; `_Camelot.toc`'s matches `^16[0-9]{3}$`
  2. the two TOC bodies are identical after excluding the `## Interface:` and `## Notes:` lines, compared CRLF-insensitively
  3. if `.pkgmeta-mainline` / `.pkgmeta-camelot` exist, each ignores exactly the other flavor's TOC

  Assertion 3 must **skip cleanly when those files are absent**, since they are not created until Phase 29.
- **D-15 (retail gate criteria):** VER-01 passes on: TBT present in the AddOns list, its normal load chat line printed, and `/tbt` opening the CDM settings window with the TBT tab. SavedVariables continuity is verified by **reasoning, not a migration test** — the rename touches only the TOC filename, never the addon folder name or `## SavedVariables: TerribleBuffTrackerDB`, so the `WTF` path is unchanged. A quick confirmation that previously-tracked buffs are still listed suffices; no dedicated test is warranted.
- **D-16 (DOC-01 placement):** Add the Forever reference to `CLAUDE.md`'s existing `## Style Reference` section alongside `wow-ui-source`, and add the flavor/interface/install-path facts to `## Key Constraints`. Keep it terse — `PROJECT.md` already holds the fuller context.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements

- `.planning/ROADMAP.md` — Phase 25 goal, dependencies, and the five success criteria this phase is judged against
- `.planning/REQUIREMENTS.md` — TOC-01…05, VER-01, DOC-01 exact wording; also the Out of Scope table, which forbids a rollback TOC and `WOW_PROJECT_ID` branching
- `.planning/PROJECT.md` — Key Decisions (locked split-TOC choice), Context (Forever interface / install path / game-type token), Constraints (cross-flavor, parity-only)

### Forever flavor mechanics — read before touching a TOC

- `.planning/research/STACK.md` — the `_Camelot` vs `_Vanilla` resolution with its five-source evidence chain, exact interface numbers, the re-derivation recipe for future beta builds, and the "what not to add" list
- `.planning/research/SUMMARY.md` §"Gating Question — Resolved" and §"Critical Pitfalls (ranked)" — the consolidated verdict and ranked risk list
- `.planning/research/PITFALLS.md` — pitfall 1 (the rename trap, highest consequence), pitfall 2 (`_Camelot` case-sensitivity: Windows dev vs Linux CI), pitfall 3 (interface drift and the packager's exact hard-error text)
- `.planning/research/ARCHITECTURE.md` — file topology for the split, and why no runtime flavor detection is needed

### Upstream source of truth

- `https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh` — authoritative on the `_Camelot` suffix regex (case-sensitive, capital C), the `16???` → `forever` interface mapping, and the `game_flavor` map
- `https://github.com/BigWigsMods/WoWUI` branch `forever-beta` — Forever UI source; `Interface/AddOns/Blizzard_CooldownViewer/Blizzard_CooldownViewer.toc` shows `## AllowLoadGameType: standard, camelot`
- `C:\Users\jonat\Repositories\wow-ui-source` branch `live` (12.1.0) — local Midnight UI source for comparison. **Read-only — never check out another branch or modify this working tree; the user works in it.**

### Files this phase modifies

- `TerribleBuffTracker.toc` — the file being split (CRLF; 6-entry load list; note `CDMTab.lua` is absent, see code_context)
- `scripts/release.bat` — gains the guard invocation (D-12)
- `CLAUDE.md` — DOC-01

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `TerribleBuffTracker.toc` is the sole artifact being forked. Its current header is complete and correct for retail — `_Mainline` needs no edit beyond the filename, and `_Camelot` needs only the two allowlisted lines changed.
- `scripts/release.bat` already uses a nonzero-exit failure pattern (`if errorlevel 1 ... exit /b 1`) after each git call. The guard invocation should follow that same shape.

### Established Patterns

**Three distinct file lists exist, and they are not interchangeable** — the single most important thing to get right for TOC-03/TOC-05:

| List | Contents | Who maintains it |
|---|---|---|
| TOC load list | 6 entries: `Core.lua`, `BuffEngine.lua`, `Providers.lua`, `EditModeFrames.lua`, `Display.lua`, `CDMTab.xml` | both TOCs, must stay identical |
| `install.bat` copy list | 9 files — adds `CDMTab.lua`, `tbt_icon_64x64.blp`, and the `.toc` | Phase 26 |
| packaged zip | everything not in `.pkgmeta` `ignore` | Phase 29 |

- **`CDMTab.lua` is NOT in the TOC.** It loads via `<Script file="CDMTab.lua"/>` inside `CDMTab.xml`. TOC-03's "identical file list" therefore means the two TOC bodies only — do not "fix" the TOC by adding `CDMTab.lua` to it, and do not expect the TOC list to match `install.bat`'s list.
- All Lua/XML files are shared and unforked. Nothing in this phase touches Lua.
- The TOC uses CRLF line endings and `## Version: @project-version@`, a packager substitution keyword that must survive into both files verbatim.

### Integration Points

- `.pkgmeta` currently has no TOC entry in its `ignore` list, so both new TOCs are packaged automatically — no `.pkgmeta` change is needed in Phase 25. The split into `.pkgmeta-mainline` / `.pkgmeta-camelot` is Phase 29's work.
- The guard's `.pkgmeta-<flavor>` assertion (D-14, item 3) is forward-looking and must no-op until Phase 29 creates those files.
- `.gitignore` already covers `*.zip` and emacs `#*` autosaves, so the stray `TerribleBuffTracker.zip` and `#CLAUDE.md#` files at repo root are untracked noise — leave them alone.

</code_context>

<specifics>
## Specific Ideas

- The user wants the `_Camelot` file **copied, not retyped** (D-04). This came from research pitfall 2: a lowercase `_camelot.toc` looks correct in Explorer and to `dir`, but fails a case-sensitive match in CI and very likely in the client. `git ls-files` is the verification of record.
- The Forever smoke-test is deliberately scoped to one question only (D-08). The user was clear that a CDM or SavedVariables problem on Forever must not be allowed to masquerade as a TOC suffix failure.
- On smoke-test failure the user wants to be **asked, not worked around** (D-11) — specifically rejecting both auto-trying `_Vanilla`/unsuffixed and falling back to a single TOC.

</specifics>

<deferred>
## Deferred Ideas

- **Per-flavor `## Category:` strings** — deferred pending research question 1. If Forever rejects `Buffs & Debuffs, Combat`, adding a third allowlisted divergence line is a decision for the user, not the planner (D-03).
- **Guard invocation from CI** — D-13 keeps the guard a standalone script so a future CI step can call it, but wiring that up belongs to Phase 29 or later, not here.
- **A dedicated `_forever_` install path** — `FTOOL-02` in REQUIREMENTS.md, for if Forever gets its own product folder at GA instead of piggybacking `_classic_beta_`.

</deferred>

<research_questions>
## Open Questions for the Researcher

1. **Does Forever accept `## Category: Buffs & Debuffs, Combat`?** Forever is Classic-inspired; the retail category taxonomy may not apply. An invalid Category is likely cosmetic (uncategorised in the AddOns list) rather than load-blocking, but confirm. Bears on D-03.
2. **Is `## IconTexture:` honoured on Forever?** The TOC points at `tbt_icon_64x64`. Cosmetic, but worth knowing before the smoke-test so a missing icon is not misread as a load problem.
3. **Does the live `_classic_beta_` client's own file tree confirm the `_Camelot` suffix?** Research established it from Blizzard's GitHub-mirrored TOCs and the wiki. Checking the installed client's actual Blizzard TOC filenames is the strongest available pre-flight confirmation, and is also the first diagnostic if the smoke-test fails (D-11).
4. **Has the Forever beta interface number moved past 16001?** PROJECT.md pins `16001` from build `1.60.1.69893`, and the user independently confirmed it. The beta is moving fast, so re-derive from the live `.build.info` at execution time rather than trusting the pinned value.

### Resolved 2026-09-18 — all four answered by observation

Recorded in `.planning/testing/FOREVER-TEST-PASS.md` ("Record while you're in there"), on build
`1.60.1.69913`. None of the four needed a code change.

1. **`## Category:` on Forever** → **accepted.** Sections show correctly in the AddOns list, so no third
   divergence line between the two TOCs is needed and D-03 holds as written.
2. **`## IconTexture:` on Forever** → **honoured.** The addon icon renders.
3. **`_Camelot` suffix confirmed from the live client tree** → **not needed.** Step 1 passed, so the
   suffix is confirmed empirically by the client actually loading the file — stronger evidence than
   inspecting Blizzard's own filenames would have been.
4. **Interface number moved past 16001?** → **no.** Re-derived from `.build.info` as `16001` from
   `1.60.1`. The build had moved (`69913` vs the pinned `69893`) but the interface had not. Note the
   drift guard asserts the `16xxx` range rather than the exact value, so a routine beta bump will not
   fail it.

</research_questions>

---

*Phase: 25-TOC Split & Retail Regression Gate*
*Context gathered: 2026-09-18*
