---
gsd_state_version: 1.0
milestone: none
milestone_name: ""
status: shipped
last_updated: "2026-09-19"
last_activity: 2026-09-19 — v0.3.0 milestone closed and archived; ROADMAP collapsed, REQUIREMENTS archived, PROJECT.md evolved
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-19)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** No milestone active. v0.3.0 shipped 2026-09-19 — start the next one with `/gsd-new-milestone`.

## Current Position

Milestone: none active.
Last shipped: **v0.3.0 WoW Forever compatibility**, 2026-09-19 — Phases 25-30 (27.1 inserted), 12 plans, 57 commits, 2 days.
Next phase number: **31** — phase numbering never restarts.

## Last Milestone at a Glance

TBT became a two-flavour addon: one shared Lua/XML source set loading on both Midnight retail
(Interface 120100) and the WoW Forever beta (Interface 16001), selected by two flavour-suffixed TOCs,
with no forked source file and zero flavour-detection tokens in any Lua file.

25 of 30 requirements closed. Verified in-game on Forever build `1.60.1.69913` and on Midnight retail,
both 2026-09-18.

Full record: `.planning/MILESTONES.md` (v0.3.0 entry), `.planning/milestones/v0.3.0-ROADMAP.md`,
`.planning/milestones/v0.3.0-REQUIREMENTS.md`.

## Deferred Items

Acknowledged and deferred at milestone close, 2026-09-19.

| Category | Item | Status |
|----------|------|--------|
| requirement | `DIST-03` — one tag produces two distinctly-named zips | open — needs a real tag push |
| requirement | `DIST-04` — each zip contains only its own flavour's TOC | open — needs a real tag push |
| requirement | `DIST-05` — both matrix jobs publish to one release without clobbering | open — needs a real tag push |
| requirement | `DIST-06` — each job's game-version tag is correct | open — needs a real tag push |
| requirement | `DIST-07` — `RELEASE_NOTES.md` correct when run once per matrix job | open — needs a real tag push |
| verification | Phase 29 `29-VERIFICATION.md` | `human_needed` — the five rows above are its open half |
| todo | `2026-09-18-install-bat-does-not-prune-stale-files.md` | pending — pruning is new behaviour outside `INST-01`…`04` |
| todo | `2026-09-18-pkgmeta-shared-ignore-list-can-drift.md` | pending — shared nine-line ignore block has no drift guard |
| todo | `2026-09-18-runtime-file-set-enumerated-three-places.md` | pending — `install.bat` `FILES` + both TOCs enumerate independently |
| todo | `2026-09-18-release-bat-pushes-main-with-no-branch-guard.md` | pending — tags whatever `HEAD` it runs from, always pushes `origin main` |

**`DIST-03`…`DIST-07` were deferred by explicit user decision, 2026-09-18:** *"do the impl and we will
test once we close the milestone and add any hotfix straight to main later if needed."* The checklist to
run at that time is the Deferred Verification table in
`.planning/phases/29-packaging-distribution/29-01-SUMMARY.md`.

**Two things to watch at that first release.** Read **both** matrix jobs' full CI logs rather than the
green check — the packager silently omits a game-version tag if a store's version list lacks it. And
check the two asset names: a trailing dash, or two identically-named zips, means `game_type` came out
empty and `-g` did not take.

## Accumulated Context

### Decisions

Full decision log lives in `.planning/PROJECT.md` (Key Decisions) and the v0.3.0 archive. Only the
constraints that outlive the milestone are repeated here:

- **One shared source set, no flavour fork.** The two TOCs may differ on `## Interface:` and `## Notes:`
  only; `scripts/check-toc.ps1` enforces it pre-tag. No flavour-forked Lua or XML file may exist.
- **No `WOW_PROJECT_ID` / `GetBuildInfo` / `IsTestBuild` branching.** Forever differences are handled as
  data-absence conditions with nil checks. This held end to end through v0.3 and is still binding.
- **`_Camelot` is case-sensitive**, and capitalisation is verified through `git ls-files`, never a
  Windows file browser.
- **Capability checks, not client-identity checks.** Guard on the API symbol existing, so a client
  lacking it degrades to a silent no-op rather than a load error.
- **`issecretvalue()` comes first**, before any comparison or concatenation — including on values
  returned from an API that already succeeded. `type()` reports `"number"` for a secret number, so a
  type check alone passes and gives false confidence.
- **Cleanup-phase scope:** `CLAUDE.md`'s "unify repeated behaviour" mandate covers duplication the
  milestone itself introduced; `PROJECT.md`'s "No refactors during cleanup phases" protects everything
  pre-existing. Settled by user decision 2026-09-18.

### Pending Todos

Four, all listed under Deferred Items above.

### Blockers/Concerns

- **Settings do not persist between sessions on the Forever beta.** A client-side bug, not TBT's: the
  file is written correctly on logout and is byte-identical to its `.bak`, but never read back on login.
  Other addons are affected identically. Nothing to fix or adapt to on the addon side —
  `Blizzard_ClientSavedVariables` exists on both flavours and no new TOC directive governs addon
  storage. Documented as a known issue in `CHANGELOG.md` and `README.md`. Retail is unaffected.
- **`/reload` does not test SavedVariables persistence** — the data survives in memory, so such a test
  cannot fail. Only logout→login exercises the load path. A v0.3 verification record asserting
  persistence was withdrawn for this reason; do not repeat the test design.
- **An engine-side global present on Midnight is not guaranteed on Forever.**
  `GetScaledCursorPositionForFrame` was absent and threw 53 errors in one drag session, from code that
  had shipped since v0.2.0. Worth a scan before assuming any engine global is safe cross-flavour.
- `install.bat` copies but never prunes, so a deployed folder still holds every file ever deleted from
  the repo — `ConfigUI.lua`, removed in v0.2.0, is still sitting in `_retail_`. Harmless today because
  nothing loads it, but it means a deployed folder is not a clean picture of the current source.
