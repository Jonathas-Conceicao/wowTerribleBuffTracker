# Phase 24: Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 24-cleanup
**Areas discussed:** Dead-code removal scope, Todo folding, CHANGELOG framing, CSVs & misc release prep

---

## Dead-Code Removal Scope

### Gray-area multi-select

| Option | Description | Selected |
|--------|-------------|----------|
| Dead-code removal scope | Shims + ns.FALLBACK_ORDER exports + RefreshMetaIcons rename + stale comments | ✓ |
| Todo folding | Evoker Fury cancel bug + M+ Lua errors (blocked) | ✓ |
| CHANGELOG framing | Terse internal note vs. highlight derivative fixes | ✓ |
| CSVs & misc | Untracked CSV source data + hot-path audit scope | ✓ |

**User notes:** "we can ignore the need to fix evoker lust, it seems to be working correctly now"

### Sweep aggressiveness

| Option | Description | Selected |
|--------|-------------|----------|
| Grep-gated full sweep (Recommended) | Delete ALL symbols with zero external readers — 3 shims + ns.FALLBACK_ORDER exports + any other unread ns.* | ✓ |
| Conservative (named items only) | Only the 3 shims named in ROADMAP success criteria | |
| Full sweep + comment scrub | Option 1 + scrub stale Phase-20/22/23 lifecycle comments | |

### RefreshMetaIcons rename

| Option | Description | Selected |
|--------|-------------|----------|
| Rename to ns:RefreshProvidersAtRest (Recommended) | Accurate post-refactor name; one call-site update in CDMTab.lua:24 | ✓ |
| Keep the name | Leave as ns:RefreshMetaIcons | |
| You decide | Claude picks | |

### Stale comment policy

| Option | Description | Selected |
|--------|-------------|----------|
| Scrub stale refs post-delete (Recommended) | Remove now-dangling comments after shim delete; keep load-bearing invariant notes | ✓ |
| Keep all phase refs | Leave comments as historical markers | |
| Scrub everything phase-numbered | Nuclear — delete every Phase-N reference | |

### Hot-path audit scope

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted check (Recommended) | Spot-check Display render, OnUnitAura dispatch, ScanActiveTimersForCancellation — the three v0.2.4-touched paths | ✓ |
| Full audit | Every OnUpdate / tick / per-event path | |
| Skip | No new hot paths introduced | |

---

## Todo Folding

### Evoker Fury of the Aspects cancellation

| Option | Description | Selected |
|--------|-------------|----------|
| Close it (mark done) (Recommended) | Move to done/ with runtime-verification note | ✓ |
| Fold minimal verify step | Add smoke test task to Phase 24 | |
| Delete the todo file | Discard | |

**Rationale:** User confirmed in-game that cancellation is working — no code change required.

### M+ Lua errors during lust

| Option | Description | Selected |
|--------|-------------|----------|
| Defer — leave in pending (Recommended) | Todo stays put; not blocking v0.2.4 release | |
| Fold — add defensive guards now | Belt-and-suspenders issecretvalue() sweep | |
| Fold — block the release on it | Hold milestone until error text captured | |
| Other (user free-text) | Close as solved — was an addon-integration issue, not TBT | ✓ |

**User notes:** "close it, it was related to integration with other addons, can be marked as solved"

---

## CHANGELOG Framing

| Option | Description | Selected |
|--------|-------------|----------|
| Terse + derivative fixes (Recommended) | One-line summary + short Fixes section for bug fixes that shipped as side-effects | |
| Terse only | "Internal architecture refactor — no user-visible changes" | |
| Full technical detail | Bullet every provider/abstraction change | |
| Other (user free-text) | "No details, only say it's a internal file reworking, and mention performance change if we have any. We can discuss that in detail after we do the analysis" | ✓ |

**Rationale:** CHANGELOG wording is decided AFTER the D-04 hot-path audit so any measurable perf delta can be accurately reported (or omitted if none). Final wording locked during execution, not planning.

---

## CSVs & Misc Release Prep

### Untracked CSV files

| Option | Description | Selected |
|--------|-------------|----------|
| Commit them to repo (Recommended) | They're referenced in Lua "Source:" comments; BigWigs ignores non-Lua | |
| Add to .gitignore | Local-only + remove dangling "Source:" comments | |
| Delete them | Not needed; remove "Source:" comments to match | ✓ |

### Release order

| Option | Description | Selected |
|--------|-------------|----------|
| Squash-merge → main → release.bat (Recommended) | /gsd:complete-milestone squash-merges, then release.bat 0.2.4 on main | ✓ |
| Different order | User changes flow this time | |

---

## Additional Check (User Request)

**Question:** Are any new v0.2.4 files setup on CI for packaging and in `.toc`?

**Finding:** All clean — no packaging changes needed.

- `.toc` includes `Providers.lua` (added Phase 17), plus unchanged `Core.lua`, `BuffEngine.lua`, `EditModeFrames.lua`, `Display.lua`, `CDMTab.xml`
- `CDMTab.lua` loads via `<Script file="CDMTab.lua"/>` in `CDMTab.xml:3` — correct pattern, not a .toc miss
- `.pkgmeta` ignore list is complete; `RELEASE_NOTES.md` is generated by CI from CHANGELOG top section before BigWigs runs
- `.github/workflows/release.yml` uses `BigWigsMods/packager@v2`, tag-triggered — no updates needed

---

## Claude's Discretion

- Exact CHANGELOG wording (pending D-04 audit outcome)
- Within-phase task ordering (shim delete vs. comment scrub sequencing)
- "Closed as solved" note wording on the two todo files
- Whether the CSV deletions land in the same plan as the shim deletes or a separate housekeeping plan

## Deferred Ideas

- Full data-storage rework / broader icon-resolution unification — still deferred per Phase 16 D-01 (future milestone)
- Addon-wide hot-path audit beyond the three v0.2.4-touched paths — out of scope
- Re-documenting CSV lineage for the hardcoded FALLBACK_ORDER arrays — CSVs are being deleted; Lua arrays become source-of-truth
