---
created: 2026-09-21T00:00:00.000Z
title: Placeholder proc table allocates once per inactive slot per tick
area: display
files:
  - Display.lua
phase_hint: 42
---

## Problem

`RenderBarContainer` and `RenderIconContainer` both build a fresh table for every *inactive*
placeholder slot, every tick:

```lua
bar.proc = { spellID = info.spellID, label = info.label, key = slot.key }
```

`ns:UpdateDisplay` runs every 0.05s. The allocation is reached whenever `showPlaceholders` is true —
which is `not settings.hideWhenInactive or ns.configOpen or barEditing`. A player who turns off
"hide when inactive" therefore pays one table allocation per inactive tracker per tick, **in combat**.

This is pre-existing v0.3.0 behaviour, not introduced by Phase 35. What Phase 35 changed is the
multiplier: the two inline render blocks became four registry-driven container renders, so the same
code path can now fire across four containers instead of two. Phase 36 makes the container count
unbounded, which is what turns this from a rounding error into something worth fixing.

Found during the post-commit performance review required by `CLAUDE.md`, after Phase 35 Plan 04. The
sibling finding in the same review — two identical `table.sort` comparator closures allocated per
render — was fixed immediately by hoisting `ByLayoutOrder` to a module-level local, because that one
was milestone-introduced duplication and carried no behavioural risk. This one was not fixed, because
it is pre-existing code and `PROJECT.md`'s "No refactors during cleanup phases" decision protects it
from opportunistic rewriting mid-phase.

## Solution

Reuse a per-widget table instead of allocating a new one.

The care needed is in the *other* branch: when a timer exists, `bar.proc = timer` stores the live
timer table directly, and `OnEnter` reads `bar.proc` for the tooltip (D-19). So `bar.proc` is
sometimes a borrowed reference and sometimes an owned table — a naive "wipe and reuse `bar.proc`"
would wipe a live timer.

The shape that works: keep a separate owned table per widget, e.g. `bar._placeholderProc`, populate
it in place, and point `bar.proc` at it:

```lua
local p = bar._placeholderProc
if not p then
    p = {}
    bar._placeholderProc = p
end
p.spellID, p.label, p.key = info.spellID, info.label, slot.key
bar.proc = p
```

Verify afterwards that nothing retains `bar.proc` across frames expecting it to be immutable — grep
every read of `.proc` before committing.

## Scope note

This is exactly the kind of work `CLAUDE.md`'s cleanup mandate covers ("review hot paths, especially
game loop tick functions"). Do it in Phase 43, not earlier, and do it after Phase 36 has settled the
final container count so the fix is measured against the real multiplier.
