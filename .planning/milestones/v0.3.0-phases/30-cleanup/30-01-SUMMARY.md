---
phase: 30-cleanup
plan: 01
subsystem: build-tooling
tags: [stylua, lua, dead-code, line-endings, grep-gate]

requires: []
provides:
  - Dead TRINKET_FALLBACK_ORDER array removed from Providers.lua, grep-gated
  - Repo-root stylua.toml pinning line_endings = "Windows"
  - EditModeFrames.lua converted to CRLF, matching the other five Lua files
affects: [30-02, 30-03, 30-04]

tech-stack:
  added: [stylua.toml]
  patterns: ["bare stylua invocation is now CRLF-correct by default"]

key-files:
  created: [stylua.toml]
  modified: [Providers.lua, EditModeFrames.lua]

key-decisions:
  - "TRINKET_FALLBACK_ORDER (Providers.lua:172-176, 5 lines including its two comments) deleted; POT_FALLBACK_ORDER untouched — it still drives the pot bag-scan ipairs loop"
  - "stylua.toml pins only line_endings = \"Windows\"; no other option set, to avoid reformatting all six Lua files"
  - "EditModeFrames.lua converted with the BARE stylua invocation (no --line-endings flag) — this is the D-08 proof that the config is discovered"

patterns-established:
  - "stylua.toml root-cause fix for the LF-drift class of bug: bare `stylua <file>` is now correct from any caller"

requirements-completed: []

duration: 15min
completed: 2026-09-18
---

# Phase 30 Plan 01: Dead code removal + stylua line-ending root-cause fix Summary

Removed the dead `TRINKET_FALLBACK_ORDER` array from `Providers.lua` and added a repo-root `stylua.toml` pinning `line_endings = "Windows"`, then used the bare `stylua` invocation to convert `EditModeFrames.lua` to CRLF — proving the config is actually read.

## Performance

- **Duration:** ~15 min
- **Tasks:** 2/2 completed
- **Files modified:** 3 (Providers.lua, stylua.toml created, EditModeFrames.lua)

## Accomplishments

- `TRINKET_FALLBACK_ORDER` reaches zero references across all `.lua`, `.toc` and `.xml` sources; `POT_FALLBACK_ORDER` unaffected
- `stylua.toml` created — the actual root-cause fix for the LF-drift bug that hit two files silently in the past with no git-diff trace
- All six Lua files are now `w/crlf` on disk, confirmed by `git ls-files --eol`, which is the only check that can see this class of change
- Flagless `stylua --check` is clean on all six Lua files, proving the config reproduces prior `--line-endings Windows` formatting exactly

## Task Commits

1. **Task 1: Grep-gated removal of the dead TRINKET_FALLBACK_ORDER array (D-04, D-05, D-06)** - `ddeedd3` (refactor)
2. **Task 2: stylua.toml root-cause fix, then bare-stylua CRLF conversion of EditModeFrames.lua (D-07, D-08, D-11)** - `81447d7` (chore)

## Files Created/Modified

- `Providers.lua` - Deleted 5 lines: the now-inaccurate shared header comment, Phase 27's marker comment, and the `TRINKET_FALLBACK_ORDER` declaration itself. `POT_FALLBACK_ORDER` and its own accurate comment survive untouched.
- `stylua.toml` - New repo-root config, `line_endings = "Windows"` as its only setting, with a comment block explaining the empty-git-diff root cause it fixes.
- `EditModeFrames.lua` - Converted CRLF via the bare `stylua` invocation. Produces an empty `git diff` by construction (see below) — the commit contains `stylua.toml` alone.

## Grep-Gate Evidence (D-06)

Before:
```
grep -c "TRINKET_FALLBACK_ORDER" Providers.lua   -> 1  (declaration only)
grep -c "POT_FALLBACK_ORDER" Providers.lua       -> 2  (declaration + ipairs consumer)
cat *.lua | grep -c "TRINKET_FALLBACK_ORDER"      -> 1
```

After:
```
cat *.lua | grep -c "TRINKET_FALLBACK_ORDER"                 -> 0
cat *.toc CDMTab.xml | grep -c "TRINKET_FALLBACK_ORDER"      -> 0
grep -c "POT_FALLBACK_ORDER" Providers.lua                   -> 2 (unchanged)
```

Providers.lua line count: 743 -> 738 (net -5, pure deletion, zero insertions — confirmed via `git diff --numstat`).

## Line-Ending Evidence (D-11)

Baseline `git ls-files --eol '*.lua'`:
```
i/lf  w/crlf  BuffEngine.lua
i/lf  w/crlf  CDMTab.lua
i/lf  w/crlf  Core.lua
i/lf  w/crlf  Display.lua
i/lf  w/lf    EditModeFrames.lua   <- only file at w/lf
i/lf  w/crlf  Providers.lua
```

Baseline per-file `stylua --line-endings Windows --check`:
- BuffEngine.lua, CDMTab.lua, Core.lua, Display.lua, Providers.lua: all clean (exit 0, zero-line diff). No file beyond EditModeFrames.lua needed formatting — the plan's contingent file list was not triggered.
- EditModeFrames.lua: diff marking every line from line 1 (the whole-file line-ending signature per planner finding 4, not a formatting problem).

Final `git ls-files --eol '*.lua'` (after Task 2):
```
i/lf  w/crlf  BuffEngine.lua
i/lf  w/crlf  CDMTab.lua
i/lf  w/crlf  Core.lua
i/lf  w/crlf  Display.lua
i/lf  w/crlf  EditModeFrames.lua
i/lf  w/crlf  Providers.lua
```

All six `w/crlf`. Flagless `stylua --check` on all six: clean.

## Planner Findings — Confirmed

1. **Confirmed.** `TRINKET_FALLBACK_ORDER` had exactly one reference (its own declaration); `POT_FALLBACK_ORDER` had exactly two (declaration + the `ipairs` loop at line 437, inside `PotProviderMixin:RefreshAtRest`).
2. **Confirmed.** Exactly five consecutive lines (172-176) came out: the shared header comment, the three-line Phase 27 marker, and the declaration. The two lines below (POT-specific comment + `POT_FALLBACK_ORDER` declaration) were left untouched and adjacent.
3. **Confirmed.** `git show --name-only --format= HEAD` after Task 2 lists `stylua.toml` alone. `git diff --numstat HEAD~1 HEAD -- EditModeFrames.lua` is empty, despite `git status --short` flagging the file as modified (an mtime artifact, not a content diff).
4. **Confirmed.** `EditModeFrames.lua`'s baseline diff marked every line from line 1 — the pure line-ending signature. The bare-invocation conversion was picked up correctly on the first attempt; the config did not need to be debugged. No fallback to `--line-endings Windows` was needed and none was used.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- FOUND: Providers.lua (738 lines, TRINKET_FALLBACK_ORDER absent, POT_FALLBACK_ORDER present twice)
- FOUND: stylua.toml (line_endings = "Windows", single setting)
- FOUND: EditModeFrames.lua (w/crlf)
- FOUND commit ddeedd3 (`git log --oneline --all | grep ddeedd3`)
- FOUND commit 81447d7 (`git log --oneline --all | grep 81447d7`)

<deferred_questions>
None.
</deferred_questions>
