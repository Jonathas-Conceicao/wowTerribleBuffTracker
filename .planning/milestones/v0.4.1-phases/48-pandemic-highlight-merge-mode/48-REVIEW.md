---
status: findings
resolution: CR-01 and WR-01 fixed in dcdad37; IN-01 deferred to the cleanup phase
phase: 48-pandemic-highlight-merge-mode
reviewed: 2026-09-24
depth: standard
files_reviewed: 2
files_reviewed_list:
  - MergeMode.lua
  - Display.lua
findings:
  critical: 1
  warning: 1
  info: 1
  total: 3
---

# Phase 48: Code Review Report — Pandemic Highlight in Merge Mode

**Reviewed:** 2026-09-24
**Depth:** standard
**Files Reviewed:** 2 (`MergeMode.lua`, `Display.lua`)
**Core.lua:** confirmed byte-unchanged (`git diff 1c0ee24..HEAD -- Core.lua` is empty)
**Status:** findings

## Summary

The CDM no-taint rule (the highest-damage category in scope) holds throughout the diff: every
new touch of an `itemFrame` — `PandemicIcon`, `pandemicStartTime`, `pandemicEndTime` — is a plain
table-field read, nothing is written onto a CDM frame, nothing is parented into one, and
`viewer.pandemicIconPool` is never referenced. Every FX frame `Display.lua` creates is TBT-owned
from `CreateFrame` up. Both template instantiations are `pcall`-guarded and degrade to "no
highlight" with a sticky `_pandemicFailed` flag, satisfying PAND-05's no-retry-storm requirement.
Anchoring/frame-level values (`-6/+6` icon, `-9/+10` bar, `bar.statusBar:GetFrameLevel() + 1`)
match `PANDEMIC.md`'s citations exactly. No per-render allocation was found; FX frames are created
lazily and cached on the widget, and `ApplyPandemicIcon`/`ApplyPandemicBar` are dirty-checked.

One genuine correctness defect was found in the stamping function itself (`ReadPandemicState`),
directly in the area flagged as priority #2 in the review brief — the function's own comment
claims an "all-or-nothing" guarantee that the code does not actually provide. One quality
asymmetry was found in `Display.lua`'s trailing bar-pool clear. Everything else checked out.

## Critical Issues

### CR-01: `ReadPandemicState` can leave `entry.pandemicActive` and `entry.pandemicStart/Finish` in disagreement if the timestamp reads raise

**File:** `MergeMode.lua:775-797`

**Issue:** `ReadPandemicState` writes `entry.pandemicActive` (line 776) *before* reading
`itemFrame.pandemicStartTime` / `itemFrame.pandemicEndTime` (lines 784-785) and writing
`entry.pandemicStart` / `entry.pandemicFinish` (lines 792-793, or 795-796 on the guard-fail
branch). The function is called only as `pcall(ReadPandemicState, entry)`
(`MergeMode.lua:930`), and the surrounding comment at 772-774 explicitly anticipates "a future
client that made this read raise." If that happens — a raise on line 784 or 785, after line 776
has already executed — Lua does not roll back: `entry.pandemicActive` keeps its freshly-read
value for this pass, but `entry.pandemicStart`/`entry.pandemicFinish` are never reached and keep
whatever they held from the *previous* successful pass. The outer `pcall` stops the raise from
taking down the render pass (good), but it does nothing to stop this partial write — the comment
at lines 780-781 ("Stamped all-or-nothing... BOTH entry.pandemicStart and entry.pandemicFinish go
nil") is true only when the *value* is unreadable (secret/wrong type); it is false when the
*read itself* raises, which is the exact scenario the function's own comment says it is guarding
against.

Concretely: a merged entry finishes a pandemic window on pass N (fresh
`entry.pandemicStart`/`entry.pandemicFinish` recorded). On pass N+1, a new window opens —
`itemFrame.PandemicIcon` becomes non-nil so `entry.pandemicActive` correctly flips to `true` — but
the subsequent read of `pandemicStartTime`/`pandemicEndTime` raises. `entry.pandemicStart`/
`entry.pandemicFinish` are left holding pass N's stale, already-elapsed bounds. In
`ns:IsMergedEntryInPandemic` (`MergeMode.lua:786-793` in the new code, the `IsMergedEntryInPandemic`
function), the numeric route wins whenever both fields are non-nil: `now >= entry.pandemicStart
and now <= entry.pandemicFinish` — evaluated against the *stale, already-past* window — returns
`false` even though Blizzard is actively showing the highlight right now (`pandemicActive ==
true`). The highlight silently fails to show, and stays wrong until a pass where the read
succeeds again. The reverse (a stuck-true highlight past the true end of a window) is also
reachable by the same mechanism, just less likely given Blizzard's own end-of-window timing.

This is not hypothetical hand-wringing about Lua semantics — it is a direct violation of the
function's own stated contract, in exactly the code path priority #2 of this review asks to be
checked ("Confirm the pandemic stamp cannot raise out of its guard"), and it produces a
persistent, silently wrong render, not a crash — the harder kind of bug to catch in an addon with
no test runner.

**Fix:** Read both timestamps into locals and validate them *before* writing anything to `entry`,
so a raise on the read happens before any field on `entry` is touched this pass, and the existing
outer `pcall` then leaves last pass's values in place for *all three* fields consistently (not a
mix of fresh-and-stale) — or, cheaper, just reorder so the raise-prone reads happen first:

```lua
local function ReadPandemicState(entry)
	local itemFrame = ns.mergeItemFrames[entry.cooldownID]
	if not itemFrame then
		local wasActive = entry.pandemicActive == true
		entry.pandemicActive = false
		entry.pandemicStart = nil
		entry.pandemicFinish = nil
		LogPandemicStateChange(entry, wasActive, nil, nil)
		return
	end

	local wasActive = entry.pandemicActive == true

	-- Read everything that could conceivably raise BEFORE writing anything to entry, so a raise
	-- here leaves entry untouched this pass rather than partially updated.
	local iconPresent = itemFrame.PandemicIcon ~= nil
	local startTime = itemFrame.pandemicStartTime
	local endTime = itemFrame.pandemicEndTime

	entry.pandemicActive = iconPresent

	if
		not issecretvalue(startTime)
		and type(startTime) == "number"
		and not issecretvalue(endTime)
		and type(endTime) == "number"
	then
		entry.pandemicStart = startTime
		entry.pandemicFinish = endTime
	else
		entry.pandemicStart = nil
		entry.pandemicFinish = nil
	end

	LogPandemicStateChange(entry, wasActive, startTime, endTime)
end
```

This alone does not make the three writes atomic (a raise could still land between
`entry.pandemicActive = iconPresent` and the `entry.pandemicStart` writes), but it removes the
read-that-can-raise from between them — every remaining statement between the writes is a plain
local read/comparison, matching the same "field reads on secret tables don't raise, only some API
calls do" precedent already established elsewhere in this file (`aura.expirationTime`,
`MergeMode.lua:650-656`, which is guarded the same way after `ns:CanReadTable` and never itself
wrapped in an inner `pcall`). If full atomicity is wanted regardless, stage all three into locals
and assign to `entry` only after every read has completed:

```lua
	local newActive = itemFrame.PandemicIcon ~= nil
	local startTime = itemFrame.pandemicStartTime
	local endTime = itemFrame.pandemicEndTime
	local newStart, newFinish
	if not issecretvalue(startTime) and type(startTime) == "number"
		and not issecretvalue(endTime) and type(endTime) == "number" then
		newStart, newFinish = startTime, endTime
	end
	entry.pandemicActive = newActive
	entry.pandemicStart = newStart
	entry.pandemicFinish = newFinish
```

## Warnings

### WR-01: Trailing bar-pool clear does not stop the pandemic FX's animation lifecycle, unlike the icon path

**File:** `Display.lua:2021-2023` (bar trailing-hide loop) vs. `Display.lua:2347-2353` (icon's
explicit clear, added by this same phase)

**Issue:** When a container shrinks (`n < #pool`), the bar path's trailing-hide loop is:

```lua
-- Hide unused bars
for i = n + 1, #pool do
	pool[i]:Hide()
end
```

No `ApplyPandemicBar(pool[i], false)` call was added here, unlike the icon path a few hundred
lines below, which this same phase *did* add (`Display.lua:2347-2353`, with a comment explaining
exactly why: `pool[i]:Hide()` does not cascade to a container-parented FX). The bar's FX is a true
child of `bar` (per `EnsurePandemicBarFX`, `Display.lua:611-643`), so `bar:Hide()` correctly makes
it invisible — the visual outcome is fine. But `AnimateWhileShownTemplate` starts and stops its
`AnimationGroup` from the FX frame's *own* `Show`/`Hide` calls (per this phase's own comment at
`Display.lua:646-649`), not from an ancestor's visibility change. If `fx:Show()` was called on a
previous pass and the bar then becomes trailing, `fx:Hide()` is never called — the frame's own
shown flag stays `true`, its `OnShow`/`OnHide` handlers never re-fire, and the looping
scale/alpha (icon FX) or continuous rotation (bar FX) animation keeps running indefinitely on a
frame that is invisible only because its parent happens to be hidden, until that exact pooled bar
is reused for another rendered slot (which does correct it, via the unconditional
`ApplyPandemicBar` call at the top of the per-slot loop, `Display.lua:1888`) or the UI reloads.

This is the same "hangs off a container/parent that the entry stopped rendering into" class of
staleness the icon path was explicitly hardened against in this same diff — the bar path's
comment reasoning ("its FX is a true child of bar... needs no equivalent") only accounts for
render visibility, not for the animation lifecycle the surrounding comments themselves describe
as being driven purely by `Show`/`Hide` on the FX frame itself.

**Fix:** Mirror the icon path's explicit clear in the bar trailing-hide loop:

```lua
-- Hide unused bars
for i = n + 1, #pool do
	pool[i]:Hide()
	ApplyPandemicBar(pool[i], false)
end
```

## Info

### IN-01: Duplicated frame-level/offset magic numbers between `EnsurePandemicIconFX` and `EnsurePandemicBarFX`

**File:** `Display.lua:569-644`

**Issue:** `EnsurePandemicIconFX` and `EnsurePandemicBarFX` are structurally identical
(`icon.pandemicFX`/`bar.pandemicFX` cache check → `_pandemicFailed` check → `pcall(CreateFrame,
...)` → anchor with hardcoded offsets → `SetFrameLevel` → `Hide()`), differing only in the
template name, the anchor offsets (`-6/6` vs `-9/10`), the frame-level expression
(`parent:GetFrameLevel() + 11` vs `bar.statusBar:GetFrameLevel() + 1`), and which widget they
attach to. `parent:GetFrameLevel() + 11` in the icon path (`Display.lua:599`) is also not tied by
name to the `+ 10` used for merged-aura containers in `MergeMode.lua:1410` and `:1457`, which is
the value it is deliberately one level above per its own comment — a future change to that `+10`
would have to be remembered and mirrored here by hand.

**Fix:** Not urgent, and per this project's "no refactors during cleanup phases" decision this is
better addressed in the milestone's cleanup phase rather than here — noting it for that pass
rather than requesting a rewrite now. A small shared local helper taking
`(widget, templateName, failFlagKey, cacheKey, anchorFn, levelFn)` would remove the duplication if
taken up then; at minimum, naming the `10`/`11` pairing as a shared constant would remove the
implicit coupling between the two files.

---

_Reviewed: 2026-09-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
