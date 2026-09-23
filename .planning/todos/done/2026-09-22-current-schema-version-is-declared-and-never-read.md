---
created: 2026-09-22T00:00:00.000Z
title: CURRENT_SCHEMA_VERSION is declared and never read
area: buff-engine
files:
  - BuffEngine.lua
  - Core.lua
phase_hint: post-v0.4.0
---

## Problem

`BuffEngine.lua:82` declares a local that nothing reads:

```lua
local CURRENT_SCHEMA_VERSION = 5
local ver = ns.db.schemaVersion or 0
```

Every migration block in `ns:InitBuffEngine` writes its own literal instead —
`ns.db.schemaVersion = 1` at `:100`, `= 2` at `:113`, `= 3` at `:123`, `= 4` at `:138`, `= 5` at
`:167`. So the constant documents the current schema version rather than driving anything, and the
two can silently disagree: bumping the migration chain without bumping the constant, or the reverse,
produces no error and no diff anywhere else.

This is the **only** flag from the Phase 42 unused-local sweep, which covered **845 `local`
declarations across all seven Lua files** and found nothing else. See
`.planning/phases/42-cleanup/42-HOT-PATH-AUDIT.md` §3.3 for the sweep and its re-run recipe.

## Why Phase 42 did not fix it

Two independent reasons, either of which is sufficient:

1. **It predates the fence.** `git log -S'local CURRENT_SCHEMA_VERSION' -- BuffEngine.lua` puts its
   introduction in `d086429` (*v0.2.0 Config & Edit Mode Rework*), long before Phase 31. Phase 36
   (`0d34056`) only changed its value from `4` to `5`. ROADMAP criterion 3 is scoped to "added since
   Phase 31", and `PROJECT.md`'s no-refactor decision covers everything older.
2. **Deleting it would manufacture a comment liar.** `Core.lua:98` reads *"…no schema bump, which is
   why `CURRENT_SCHEMA_VERSION` does not move for this change"*. Remove the local and that comment
   names an identifier that does not exist — exactly the defect class plan 42-02 spent a whole plan
   removing under 42-CONTEXT.md **D4**.

## Solution sketch

**Do not delete it.** The defect is that the constant is not wired up, not that it is surplus. The
fix is one line:

```lua
-- in the final migration block, replacing the literal
ns.db.schemaVersion = CURRENT_SCHEMA_VERSION
```

Leave the earlier blocks writing their own literals — `ns.db.schemaVersion = 1` inside the `ver < 1`
block is a statement about *that* migration's endpoint, not about the current schema, and rewriting
those would be wrong.

Then the constant becomes the single place the current version is stated, which is what its name
already promises and what `Core.lua:98`'s comment already assumes.

**Why it needs a plan rather than a drive-by.** It is an edit to the database migration path. A
mistake there is not a rendering glitch — it mis-stamps a player's saved variables, and the wrong
stamp makes a future migration skip or re-run. It cannot be tested under `/reload` either: schema
migration only runs against a database loaded from disk, so real confirmation needs a logout→login,
which belongs to **Phase 44** (retail) — the Forever beta never reads saved variables back.
