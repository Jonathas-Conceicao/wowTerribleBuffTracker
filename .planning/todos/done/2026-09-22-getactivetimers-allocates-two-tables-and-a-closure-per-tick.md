---
created: 2026-09-22T00:00:00.000Z
title: ns:GetActiveTimers allocates two tables and a comparator closure on every tick
area: buff-engine
files:
  - BuffEngine.lua
phase_hint: post-v0.4.0
---

## Problem

`ns:GetActiveTimers` (`BuffEngine.lua:194-222`) is called once per tick from `ns:UpdateDisplay`
(`Display.lua:1704`), before the container loop. The tick is `UPDATE_INTERVAL = 0.05`, i.e. **20 Hz**,
and it runs in combat. Every call allocates three things unconditionally:

```lua
local result = {}                                  -- 1. a table
...
local sorted = {}                                  -- 2. a second table
for _, proc in pairs(result) do
    table.insert(sorted, proc)
end
table.sort(sorted, function(a, b)                  -- 3. a fresh closure
    return a.expiresAt < b.expiresAt
end)
return sorted
```

That is 60 tables and 60 closures per second, for a list whose contents usually did not change
between ticks.

The contrast with the render path is sharp and is the reason this is worth writing down.
`Display.lua:114-119` hoists `ByLayoutOrder` to module level with the comment *"so neither render
function allocates a closure per tick"*, and `Display.lua:102-110` records that the per-container
tables are constructed once and only ever `wipe()`d because *"a table constructor in any of them
would cost one allocation per container every `UPDATE_INTERVAL` seconds"*. The function feeding both
of those does exactly what they exist to prevent.

Found by the Phase 42 hot-path audit (`.planning/phases/42-cleanup/42-HOT-PATH-AUDIT.md`, finding
**H14** / §1c). **Not a bug** — nothing is incorrect, and the GC pressure has never been reported as
a symptom.

## Why Phase 42 did not fix it

The scope fence, not the cost.

- `ns:GetActiveTimers` dates from the initial commit; its `result` / `sorted` / inline-closure shape
  dates from `4cd64fc` (*v0.2.4 SpellProvider Refactor*). Both are far earlier than Phase 31, so
  `PROJECT.md`'s "No refactors during cleanup phases" protects it.
- 42-CONTEXT.md **D1** opened exactly two pre-milestone functions to refactoring —
  `RenderBarContainer` and `RenderIconContainer` — and explicitly did not generalise.
- Phase 42 ran *before* Phase 43's Forever end-to-end pass, so nothing changed in it can be tested.
  This function feeds every timer TBT draws; it is the worst possible thing to change blind.

## Solution sketch

All three allocations go away with module-level state and no interface change — `ns:GetActiveTimers`
would still return a sorted array, and `Display.lua` would not need to know:

1. Hoist `result` and `sorted` to module-level locals and `wipe()` them at the top of the function,
   the same contract `Display.lua`'s `slots` / `activeByKey` already use.
2. Hoist the comparator to a module-level `local function ByExpiry(a, b)`, mirroring `ByLayoutOrder`.

**The one thing to check before doing it.** The returned `sorted` array would become a shared table
that the next call wipes, where today each caller gets a fresh one. Confirm there is exactly one
caller and that it does not retain the array across ticks. Today `ns:UpdateDisplay` binds it to a
local `timers`, hands it to the render functions, and drops it — but the enumeration has to be
re-run, not assumed, and it should be written down the way 42-04's `.proc` reader enumeration was.
`ns.previewTimers` / `ns.activeTimers` are *not* affected: the function only reads and lazily prunes
them, and `result` holds borrowed references to the same proc tables either way.

Measure nothing first — the win is an allocation count, not a frame time, and it is provable by
reading.
