# Deferred Items -- Phase 46

Out-of-scope discoveries logged per the executor's scope-boundary rule (only auto-fix what the
current task's own changes touch; log everything else here rather than fixing it).

## 1. CRLF->LF blind spot on three prior-wave SUMMARY.md files — RESOLVED 2026-09-24

**Resolved by the orchestrator** immediately after 46-04 returned. `rm <file> && git checkout HEAD
-- <file>` applied to all three; `git ls-files --eol` now reports `w/crlf` for every `.md` in the
phase directory, and `git status --short` is empty. No commit was produced, exactly as predicted —
the index was already `i/lf` for all three, so the committed content was never wrong; only the
working-tree materialization was. Logging it rather than fixing it in-plan was the right call: the
files were outside 46-04's declared `files_modified`.

The detail below is kept because the root cause recurs for every `.md` an agent writes directly to
disk, and the next phase will hit it again.


- **Found during:** 46-04, Task 1 (S2 sweep, extended past the plan's own literal `<verify>` command
  to every `.md` in the phase directory per the acceptance criteria text).
- **Files:** `46-01-SUMMARY.md`, `46-02-SUMMARY.md`, `46-03-SUMMARY.md`.
- **Symptom:** `git ls-files --eol` reports `w/lf` for all three, while every other `.md` in the
  phase directory reports `w/crlf`.
- **Root cause:** `core.autocrlf` is `true`; `.gitattributes` pins `eol=crlf` for `*.lua`/`*.xml`/
  `*.toc`/`*.bat`/`*.ps1` only. `.md` falls under the bare `* text=auto`, so the LF->CRLF conversion
  only happens when git actually re-materializes the working-tree file (a fresh checkout, or
  `rm <file> && git checkout HEAD -- <file>`). These three were written directly to disk by their
  respective wave's executor and committed as-is, without an intervening checkout, so they never
  picked up the conversion.
- **Verified fix exists and is safe:** `46-04-SUMMARY.md` hit the identical symptom the moment it
  was written in this same plan. `rm <file> && git checkout HEAD -- <file>` corrected it --
  `git status --short` and `git diff --stat` were both empty before and after, confirming the fix
  is byte-identical in content (line endings only) and entirely invisible to git (no index change,
  nothing to commit).
- **Why not applied to the three prior files here:** they are not in this plan's declared
  `files_modified` (`.planning/phases/46-item-catalogue-suggested-tiles/46-VALIDATION.md` only).
  Per the executor's scope boundary, an out-of-scope discovery is logged, not fixed, even when a
  safe fix is known.
- **Suggested follow-up:** run `rm <file> && git checkout HEAD -- <file>` on all three, from the
  repo root, then confirm with `git ls-files --eol` and `git status --short` (expect no change to
  report). No commit will be produced since the fix is invisible to git.
