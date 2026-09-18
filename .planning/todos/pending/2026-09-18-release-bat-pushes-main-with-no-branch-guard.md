---
created: 2026-09-18
title: release.bat tags whatever HEAD it runs from but always pushes origin main
area: tooling
files:
  - scripts/release.bat
---

## Problem

`scripts/release.bat:23` creates the tag on whatever `HEAD` the script is invoked from
(`git -C "%SOURCE%" tag -a "%TAG%" -m "Release %VERSION%"`), but `scripts/release.bat:29`
unconditionally pushes `origin main "%TAG%"`. If the script is run from a feature/milestone
branch, it tags that branch's tip and pushes `main` in the same breath — the tag would point at
commits that were never merged into `main`, and the push of `main` itself would be a no-op only
if `main` happens to already be at the same commit locally, which it usually is not.

The project's own release rule (`CLAUDE.md` GSD Workflow: squash-merge the milestone branch to
`main` before running `release.bat`; never tag from the milestone branch) makes the script
correct *when followed*, but nothing in the script itself enforces or checks it. This repo is
currently sitting on `v0.3-wow-forever-compatibility`, exactly the branch where running
`release.bat` without first merging would create a real problem.

Verified by line number, 2026-09-18 (Phase 30 plan 30-04, D-19 review):
- `check-toc.ps1` invocation: line 17
- `if errorlevel 1` abort: line 18
- `git tag -a`: line 23
- `git push origin main "%TAG%"`: line 29

The guard ordering (check-toc before tag, non-zero exit aborts) is correct. The branch-safety
gap is separate and is what this todo tracks.

## Why Phase 30 did not fix it

Adding a branch check (e.g. refuse to run unless the current branch is `main`) is new behaviour
— a new guard `release.bat` does not have today — and Phase 30's review task (D-19/D-20) is
explicitly scoped to reading `release.bat` and `release.yml`, not modifying either. `30-CONTEXT.md`
and the plan's hard constraints both say findings from the review become todos, not
implementations. This is exactly that: a real finding, deliberately not acted on here.
