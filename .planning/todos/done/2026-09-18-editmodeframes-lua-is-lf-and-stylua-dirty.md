---
created: 2026-09-18
title: EditModeFrames.lua is LF on disk and stylua --check dirty
area: code-hygiene
files:
  - EditModeFrames.lua
  - CDMTab.lua
resolves_phase: 30
---

## Problem

Two Lua files had a bare `stylua` run on them at some point, which reflowed them to LF while the
rest of the working tree is CRLF. Discovered during Phase 27.1 planning:

Verified directly via `git ls-files --eol *.lua` on 2026-09-18:

```
i/lf    w/crlf   BuffEngine.lua
i/lf    w/lf     CDMTab.lua          <- fixed during Phase 27.1
i/lf    w/crlf   Core.lua
i/lf    w/crlf   Display.lua
i/lf    w/lf     EditModeFrames.lua  <- OUTSTANDING
i/lf    w/crlf   Providers.lua
```

**Precision on the "dirty" part:** `stylua --check --line-endings Windows EditModeFrames.lua` does
report a diff, but it marks *every line from line 1 onward* — the signature of a whole-file
line-ending difference, not formatting problems. The file's formatting is fine. It is purely LF where
the rest of the tree is CRLF, so the fix is mechanical and carries no formatting risk.

`EditModeFrames.lua` was deliberately left alone during Phase 27.1 — out of scope, and touching it
would have widened that phase's diff for no reason.

## Why this is invisible to normal checks

`core.autocrlf=true` with no `.gitattributes` means every Lua file's index entry is `i/lf`. Converting
a file's line endings on disk therefore produces a **literally empty `git diff`**. Verified
empirically during Phase 27.1 planning: converting `CDMTab.lua` produced an empty `--numstat`.

Consequence: no git-based gate can detect a line-ending regression. The only reliable on-disk
assertion is:

```
git ls-files --eol <file> | grep -q "w/crlf"
```

This is why a bare `stylua Providers.lua` silently reflows 610 lines with no visible diff, and why
every Phase 27 / 27.1 plan mandates `~/.cargo/bin/stylua.exe --line-endings Windows <file>`.

## Solution

1. `~/.cargo/bin/stylua.exe --line-endings Windows EditModeFrames.lua` — fixes both the formatting
   dirt and the line endings in one pass.
2. Assert `git ls-files --eol` reports `w/crlf` for all six Lua files afterwards.
3. **Consider adding a `stylua.toml` with `line_endings = "Windows"`** so a bare `stylua` can no
   longer do this. That is the actual root-cause fix — every plan currently has to remember the flag,
   and a forgotten flag leaves no trace in a diff. A `.gitattributes` marking `*.lua text eol=crlf`
   would make the git layer honest too, but changing `.gitattributes` on an existing repo rewrites
   index state for every Lua file and should be a deliberate, isolated commit.

CLAUDE.md's standing rule is "always run `stylua` on Lua files after finishing a task" — that rule as
written is what produced this drift, since the bare invocation is the wrong one. Worth amending the
rule to name the flag, or adding the `stylua.toml` so the bare form is correct.

## Resolution

Closed 2026-09-18 by Phase 30 plan 30-01 Task 2.

The Solution section's step 1 as originally written — `stylua --line-endings Windows
EditModeFrames.lua` — was **superseded by step 3**, not executed as written. The order was
inverted deliberately: `stylua.toml` (pinning `line_endings = "Windows"` as its only setting)
landed first, and the `EditModeFrames.lua` conversion was then done with the **bare**
`stylua EditModeFrames.lua` invocation, on purpose. That inversion matters — it is the
difference between fixing one file and fixing the rule that broke it. The bare conversion
doubled as the proof that `stylua.toml` is actually discovered from the repo root; if the
file had come out `w/lf` afterward, plan 30-01 would have stopped and reported rather than
falling back to the flagged form.

Final `git ls-files --eol '*.lua'`, all six rows `w/crlf`:

```
i/lf    w/crlf  BuffEngine.lua
i/lf    w/crlf  CDMTab.lua
i/lf    w/crlf  Core.lua
i/lf    w/crlf  Display.lua
i/lf    w/crlf  EditModeFrames.lua
i/lf    w/crlf  Providers.lua
```

`CLAUDE.md`'s stylua rule was amended in Phase 30 plan 30-02 Task 1 (D-09): it now names
`stylua.toml` and states the bare invocation is correct, so the rule that produced this
drift no longer produces it.

This todo's own suggestion of a `.gitattributes` marking `*.lua text eol=crlf` was
**declined for Phase 30** under D-10, not forgotten: it would rewrite index state for
every Lua file and deserves its own deliberate, isolated commit rather than living inside
a cleanup phase. It remains open future work, now that this file is moving to `done/`.
