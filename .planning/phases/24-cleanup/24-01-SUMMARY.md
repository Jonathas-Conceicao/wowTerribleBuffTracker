---
phase: 24-cleanup
plan: 01
subsystem: cleanup
tags: [dead-code-removal, rename, comment-scrub, csv-deletion]

# Dependency graph
requires:
  - phase: 23-cdmtab-lua-unification
    provides: "ns:GetDisplayInfoForKey unified API; zero external readers of the three shims or the two FALLBACK_ORDER exports; CLASS_LUST_SPELL / GetHunterLustSpell demoted"
  - phase: 22-display-lua-unification
    provides: "proc.aliveBuffs data-driven cancellation; SHARED_LUST_BUFFS demoted to Providers.lua module-local; metaIconsDirty deleted"
provides:
  - "DISP-04 closure — three backwards-compat shims, two namespace exports, and one legacy public API name all removed"
  - "ns:RefreshMetaIcons renamed to ns:RefreshProvidersAtRest (def in BuffEngine.lua, sole call in CDMTab.lua)"
  - "pots_info.csv and trinket_info.csv deleted from repo root — Lua arrays in Providers.lua are now canonical source"
  - "Stale Phase-N migration-history comments scrubbed per D-03 (surgical, not blanket)"
affects: [24-02-audit, 24-03-stylua-release-prep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Grep-gated deletion: every dead-symbol removal verified by `grep -c` returning 0 across all Lua files before the diff"
    - "Comment scrub policy (D-03): remove migration-history (`Relocated from X in Phase Y`, `Phase N will remove this shim`, `replaces ns.SUGGESTED_BUFFS`); preserve current-state invariants (PITFALL-5, D-NN decision IDs, Combat-gated)"

key-files:
  created: []
  modified:
    - "BuffEngine.lua"
    - "Providers.lua"
    - "CDMTab.lua"
  deleted:
    - "pots_info.csv"
    - "trinket_info.csv"

key-decisions:
  - "Task 1 deleted three D-24 shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID) + their preceding 'Phase 24 will remove this shim' comment blocks + the tail-reference in StartAllPreviewTimers"
  - "Task 2 deleted the two ns.*_FALLBACK_ORDER exports while preserving the module-local arrays (still read at 3 call sites in Providers.lua); renamed RefreshMetaIcons -> RefreshProvidersAtRest and fixed all surrounding comments"
  - "Task 3 deleted both obsolete CSV files + their 'Source: X.csv' comment lines + 7 additional stale Phase-N migration-history comments identified by the final grep-gate sweep"
  - "Deviation (Rule 2 - auto-add missing critical) applied at BuffEngine.lua:16-18 where a NOTE comment was factually stale (claimed CLASS_LUST_SPELL/GetHunterLustSpell were 'still on ns.*' after Phase 23 already demoted them) — scrubbed to avoid misleading future readers"

patterns-established:
  - "Before/after grep counts in SUMMARY as machine-verifiable evidence: every dead symbol went from N to 0 across 6 Lua files"
  - "CSV-as-source-of-truth retirement: when Lua arrays are hand-maintained, deleting the CSV plus its 'Source: X.csv' comment prevents future drift"

requirements-completed: [DISP-04]

# Metrics
duration: 4min
completed: 2026-04-22
---

# Phase 24 Plan 01: DISP-04 Closure Summary

**Grep-gated deletion of three dead shims, two namespace exports, and two obsolete CSV source files plus renaming of the one remaining public API that still advertised the pre-refactor vocabulary — atomic closure of DISP-04, the final outstanding v0.2.4 requirement.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-22T03:48:35Z
- **Completed:** 2026-04-22T03:52:49Z
- **Tasks:** 3
- **Files modified:** 3 Lua files (BuffEngine.lua, Providers.lua, CDMTab.lua)
- **Files deleted:** 2 CSV files (pots_info.csv, trinket_info.csv)

## Accomplishments

- Deleted `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo`, `ns:ResolveSuggestedSpellID` — three Phase-20 D-24 backwards-compat shims whose last readers (Display.lua, CDMTab.lua) all migrated to `ns:GetDisplayInfoForKey` in Phases 22-23
- Deleted `ns.TRINKET_FALLBACK_ORDER` / `ns.POT_FALLBACK_ORDER` namespace exports; module-local arrays preserved intact and still read by the three internal call sites in `TrinketProvider:RefreshAtRest` / `PotProvider:RefreshAtRest` / fallback branches in `GetDisplayInfo`
- Renamed `ns:RefreshMetaIcons` → `ns:RefreshProvidersAtRest` (def in BuffEngine.lua, sole call in CDMTab.lua); the old name carried pre-refactor "meta icons" vocabulary that no longer described the actual behavior (iterate `ns.providers`, call each `provider:RefreshAtRest()`)
- Deleted `pots_info.csv` and `trinket_info.csv` at repo root — both were untracked Phase-17 source-of-truth files that have been obsolete since Phase 18 relocated the Lua arrays into Providers.lua; the "Source: X.csv" comments that pointed to them are also gone
- Scrubbed 8 additional stale Phase-N migration-history comments per D-03 (surgical — current-state invariants like PITFALL-5 and decision-ID references preserved)

## Task Commits

Each task was committed atomically with `--no-verify` (parallel-mode coordination with 24-02):

1. **Task 1: Delete three backwards-compat shims** — `dda4c4b` (refactor)
2. **Task 2: Delete FALLBACK_ORDER exports + rename RefreshMetaIcons** — `f772010` (refactor)
3. **Task 3: Delete CSV sources + scrub stale Phase-N comments** — `7793295` (chore)

## Files Created/Modified

- `BuffEngine.lua` — Deleted 3 shim functions + their preceding D-24 comment blocks; renamed `RefreshMetaIcons` -> `RefreshProvidersAtRest` and rewrote its preceding comment; scrubbed 3 NOTE lines (lines 16-18) that described relocations from prior phases and had become factually stale; scrubbed tail-reference comment in `StartAllPreviewTimers`; scrubbed `SUGGESTED_BUFFS` history reference. Net change: ~40 lines removed.
- `Providers.lua` — Deleted 2 `ns.*_FALLBACK_ORDER` export assignments; rewrote the preceding "Ordered fallback iteration" / "Namespace exports preserved" comment pair; renamed 2 "RefreshMetaIcons" references inside comments to the new name; rewrote doc comments at 5 locations (FindSpellByItemID, SATED_DEBUFF_TO_LUST, GetHunterLustSpell, GetDisplayInfoForKey, two "Source: X.csv" lines) to document current invariants without migration history.
- `CDMTab.lua` — Updated sole call site `ns:RefreshMetaIcons()` -> `ns:RefreshProvidersAtRest()` at line 24; updated the preceding comment to match.
- `pots_info.csv` — DELETED (was untracked).
- `trinket_info.csv` — DELETED (was untracked).

## Decisions Made

- **Task 1 grep-gate:** All three shim names returned exactly the expected hits (definitions + their immediate comment blocks + one tail-reference comment in `StartAllPreviewTimers`) across all 6 Lua files. Zero unexpected external callers. Safe to delete.
- **Task 2 rename scope:** Only 2 references exist post-rename: the function definition in BuffEngine.lua and the call site + surrounding comment in CDMTab.lua. Module-local `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` arrays preserved because they're still read by the provider `RefreshAtRest` and `GetDisplayInfo` methods (3 internal reads verified).
- **Task 3 surgical scrub:** The plan's Part C list (Providers.lua:192, 225, 559) was extended to cover 4 additional stale references that matched the pattern and appeared in the final grep-gate sweep: Providers.lua:117 ("Relocated from BuffEngine.lua in Phase 18"), Providers.lua:173-174 ("Relocated from BuffEngine.lua in Phase 20"), BuffEngine.lua:16-18 (three NOTE lines — one was actively wrong post-Phase-23), and BuffEngine.lua:32 ("replaces ns.SUGGESTED_BUFFS"). All scrubs surgical — no PITFALL-5 / D-NN / Combat-gated invariant comments touched.
- **No stylua run:** Per D-11 and the plan's scope boundary, stylua is deferred to Plan 24-03's single pass across the whole addon.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Scrubbed additional stale Phase-N comments beyond the plan's explicit Part C list**
- **Found during:** Task 3 (final grep-gate sweep)
- **Issue:** Plan Task 3 Part C only called out Providers.lua lines 192, 225, 559 for scrub, but the final verification grep (`Relocated from BuffEngine.lua in Phase`) identified 4 additional lines matching the D-03 pattern: Providers.lua:117 / 173-174, BuffEngine.lua:16-18, BuffEngine.lua:32. Leaving them in place would have failed the plan's own acceptance criterion `grep -c "Relocated from BuffEngine.lua in Phase" Providers.lua BuffEngine.lua returns 0 across both files`. BuffEngine.lua:17 was additionally factually wrong ("CLASS_LUST_SPELL, GetHunterLustSpell still on ns.* pending Phase 23 Plan 23-03 demotion" — that demotion already shipped in commit c0a0e03).
- **Fix:** Scrubbed the 7 additional stale references in the same Task 3 commit. All targets matched the D-03 pattern (migration history, not current-state invariants).
- **Files modified:** BuffEngine.lua, Providers.lua
- **Verification:** Final grep for `"will remove this shim\|will remove in Phase\|Relocated from BuffEngine.lua in Phase"` returns 0 across both files; sanity greps (`local TRINKET_SPELLS`, `local POT_SPELLS`, `local SHARED_LUST_BUFFS_LOCAL`) all still return 1 — data tables preserved.
- **Committed in:** `7793295` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - scope was broader than plan's explicit Part C list, but still within the plan's overall D-03 mandate and the plan's own acceptance criterion)
**Impact on plan:** Broader scrub necessary to satisfy the plan's own final-verification grep criterion. No scope creep beyond D-03 boundary — all targets were stale migration-history comments. Zero data-table, function-logic, or load-bearing-invariant comment changes.

## DISP-04 Grep-Gate Results (Post-Delete Evidence)

```
=== Dead symbols (all must be 0 across all 6 Lua files) ===

GetAtRestMetaIcon:      BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0
GetAtRestMetaInfo:      BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0
ResolveSuggestedSpellID:BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0
RefreshMetaIcons:       BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0
ns.TRINKET_FALLBACK_ORDER: BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0
ns.POT_FALLBACK_ORDER:     BuffEngine=0 Providers=0 CDMTab=0 Display=0 Core=0 EditModeFrames=0

=== Rename (D-02): RefreshProvidersAtRest — def=1 + call+comment=2 ===

BuffEngine.lua:1  (function definition)
CDMTab.lua:2      (call site + preceding comment)

=== Module-local arrays preserved ===

local TRINKET_FALLBACK_ORDER (Providers.lua): 1
local POT_FALLBACK_ORDER     (Providers.lua): 1
TRINKET_FALLBACK_ORDER[1] internal reads: 2
for _, itemID in ipairs(POT_FALLBACK_ORDER): 1

=== CSV files deleted ===

test ! -f pots_info.csv:    pots_info.csv: deleted
test ! -f trinket_info.csv: trinket_info.csv: deleted

=== Stale Phase-N comments scrubbed ===

'will remove this shim':                           BuffEngine=0 Providers=0
'Relocated from BuffEngine.lua in Phase':          BuffEngine=0 Providers=0
'Source: trinket_info.csv' or 'Source: pots_info.csv': Providers=0
'ns.SUGGESTED_BUFFS' straggler check:              all 5 files = 0
```

## Issues Encountered

None — execution was linear. The CSV files were untracked (filesystem-only presence), so Task 3's `git add` skipped them naturally; the filesystem `rm` was the single source of truth for their deletion.

## Coordination With Plan 24-02

Plan 24-02 runs in parallel and is strictly read-only (audits BuffEngine.lua / Providers.lua / Display.lua without modifying them). All three Task commits used `--no-verify` per the parallel-executor protocol; hook validation runs once after all agents complete. No cross-agent file conflicts — 24-02 commits only its audit markdown, not any Lua changes.

## Next Phase Readiness

- **Plan 24-03 ready:** Plan 24-03 now has a clean tree to run the single stylua pass across all Lua files (D-11) plus the v0.2.4 CHANGELOG entry, todo closures (D-05/D-06), and CI/packaging verification (D-10). No pending DISP-04 work remains.
- **DISP-04 closed:** All three success-criteria bullet groups satisfied (shim deletion, rename, CSV deletion + comment scrub). Requirement ready to check off in REQUIREMENTS.md.
- **Module-local preservation verified:** Trinket / Pot `RefreshAtRest` and `GetDisplayInfo` fallback paths still function — the arrays they read from are still present, just no longer namespace-exported.

## Self-Check

All claims verified below:

- **Files created/modified/deleted:**
  - `BuffEngine.lua` exists (modified): FOUND
  - `Providers.lua` exists (modified): FOUND
  - `CDMTab.lua` exists (modified): FOUND
  - `pots_info.csv` exists: MISSING (deleted as intended)
  - `trinket_info.csv` exists: MISSING (deleted as intended)
- **Commits exist (git log --oneline --all | grep -q <hash>):**
  - `dda4c4b` Task 1: FOUND
  - `f772010` Task 2: FOUND
  - `7793295` Task 3: FOUND

## Self-Check: PASSED

---
*Phase: 24-cleanup*
*Completed: 2026-04-22*
