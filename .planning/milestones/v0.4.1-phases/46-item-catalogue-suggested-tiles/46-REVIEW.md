---
status: findings
phase: 46-item-catalogue-suggested-tiles
reviewed: 2026-09-24T11:23:52Z
depth: deep
files_reviewed: 3
files_reviewed_list:
  - Core.lua
  - Providers.lua
  - CDMTab.lua
findings:
  blocker: 0
  warning: 1
  info: 1
  total: 2
---

# Phase 46: Code Review Report

**Reviewed:** 2026-09-24T11:23:52Z
**Depth:** deep (diff `93bba5b..HEAD` for `Core.lua`, `Providers.lua`, `CDMTab.lua`, cross-referenced
against every function each new call reaches)
**Files Reviewed:** 3
**Status:** findings

## Summary

The diff is small, disciplined, and gets the two riskiest details right on inspection:

- `GetItemInfoInstant`'s 7-value destructure (`Providers.lua:949`) is positioned correctly —
  `icon` at slot 5, `classID`/`subClassID` at 6/7 — matching the doc order exactly, not the
  probe's pcall-shifted indices RESEARCH warned about.
- Every new secret-eligible read (`GetContainerItemID`'s itemID, `GetItemInfoInstant`'s
  `classID`/`subClassID`/`icon`, `GetItemSpell`'s `useSpellID`, `GetItemCount`'s `count`,
  `GetItemNameByID`'s `name`) is guarded `issecretvalue()` **before** `type()`, including the one
  place a naive truthiness test would have been the trap (`useSpellID`, `Providers.lua:958-959`).

I also traced two things the review brief flagged as easy to get wrong and confirmed they are
**not** bugs, despite looking suspicious on a first pass:

- `CDMTab.lua:861-863`'s comment claims "no C_Container/C_Item call belongs on this render path,"
  but the render loop's `ns:GetDisplayInfoForKey(itemKey)` call does reach a live
  `C_Item.GetItemNameByID(itemID)` (`Providers.lua:1046`) on every render of every item tile. This
  looked like a violation of the phase's own locked principle until I checked
  `UserSpellProviderMixin:GetDisplayInfo` (`Providers.lua:213`) and `ns:GetSpellIcon`
  (`BuffEngine.lua:228-237`, pre-existing): the racial-cooldown tile path already calls
  `C_Spell.GetSpellInfo` live on every render through the identical `GetDisplayInfoForKey`
  dispatch. The comment's claim holds at the scope it actually means (no bag re-walk — that part
  is true, the bag walk only happens in `RefreshItemCatalogue`); a single per-item live lookup on
  render is consistent with, not a departure from, existing precedent. Not a finding.
- Pooled-frame discipline for `chargeCount` is correct: written or hidden on every tile every pass
  in the item loop (`CDMTab.lua:888-897`), and the pool's release callback
  (`CDMTab.lua:732-739`) additionally clears it on every `ReleaseAll()`, so a recycled frame from
  any other section/branch cannot leak a stale count into a fresh tile.
- The `BAG_UPDATE` → dirty-flag → `C_Timer.After(0)` coalescing path (`Core.lua:994-1002`,
  `CDMTab.lua:47-77`) cannot latch: `itemCatalogueRebuildScheduled` is unconditionally reset to
  `false` as the first line of the timer callback regardless of whether the CDM is still open or
  the catalogue is still dirty, so a closed-CDM race cannot leave it stuck `true`.

One real gap remains, found by comparing the new bag-walk's guard discipline against itself.

## Warnings

### WR-01: `GetContainerNumSlots`'s return is the one value in the new scan left unguarded

**File:** `Providers.lua:935-936`
**Issue:** `ns:RefreshItemCatalogue`'s discovery pass guards every other value it reads with
`issecretvalue()` before `type()` — the loop immediately below this one guards `id`
(`Providers.lua:937-939`), and the classification pass guards `classID`, `subClassID`,
`useSpellID`, `icon`, and `count`. `numSlots` is the sole exception:

```lua
for bag = 0, 5 do
    local numSlots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, numSlots do
```

`numSlots` is used directly as a `for` loop bound with no `issecretvalue()`/`type()` check. Both
46-RESEARCH.md's Secret Values section and the locked project rule treat "guard every new
`C_Item`/`C_Container` read" as unconditional, and this project has an existing precedent
(`Core.lua:1203`, `:1214`, `:1327`) of defensively wrapping sibling `C_Item` calls. If
`GetContainerNumSlots` ever returns a secret value in some restricted context this phase's
research explicitly could not rule out (RESEARCH's own Assumptions Log A2 only covers
`GetItemCount`/`GetItemInfoInstant`/`GetItemIconByID`, not this call), using it as a loop bound
raises a hard Lua error partway through the bag walk. Because the four catalogue tables are
already `wipe()`d at the top of the function and `itemCatalogueDirty = false` only runs at the very
end (`Providers.lua:978`), an error here leaves the catalogue **empty and permanently marked
dirty** — every subsequent `BAG_UPDATE` while the CDM stays open re-attempts the same scan and
re-throws the same error, rather than degrading gracefully the way every other guarded value in
this function does.

This is speculative — no measurement in RESEARCH says `GetContainerNumSlots` is ever secret — but
it is the one asymmetry in an otherwise fully-guarded function, and the failure mode (silently
empty Suggested list with recurring Lua errors, rather than a partial-but-populated catalogue) is
exactly the "silent hole" class of bug this project's CLAUDE.md and RESEARCH's Secret Values
section both call out.

**Fix:**
```lua
for bag = 0, 5 do
    local numSlots = C_Container.GetContainerNumSlots(bag)
    if not issecretvalue(numSlots) and type(numSlots) == "number" then
        for slot = 1, numSlots do
            local id = C_Container.GetContainerItemID(bag, slot)
            if not issecretvalue(id) and type(id) == "number" then
                itemCatalogueSeen[id] = true
            end
        end
    end
end
```

## Info

### IN-01: Every pooled tile in every section now carries a hidden charge-count subframe, not just Suggested/item tiles

**File:** `CDMTab.lua:208-213`, `CDMTab.lua:725-740`
**Issue:** `f.chargeCount` is added inside `CreateIconFrame`, which is the single frame
constructor `section.itemPool:CreateObjectPool` uses for **every** section built by
`BuildTBTSection` — tracked-buff tiles, tracked-cooldown tiles, and every user container's
tiles, not only the Suggested section's item tiles that actually need it. Each of those pools now
allocates an extra child `Frame` + `FontString` per tile it ever creates, and the shared release
callback (`CDMTab.lua:732-739`) unconditionally clears it on every tile in every section on every
`ReleaseAll()`, whether or not that section's tiles can ever show a count. This is bounded (one
extra pair of objects per distinct tile the pool has ever needed to create, not per render) and
therefore not a performance defect under this project's stated scope, but it is scope wider than
the feature needs — the count is only ever written for Suggested item tiles.
**Fix:** Not required. If revisited, the cleanest narrowing would be constructing `chargeCount`
lazily only in the item-tile branch (`CDMTab.lua:874` area) rather than unconditionally in the
shared `CreateIconFrame`, but this is a minor tidiness call, not a defect to block on.

---

_Reviewed: 2026-09-24T11:23:52Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

---

## Orchestrator Resolution — 2026-09-24

**WARNING (`Providers.lua:935-936`, unguarded `GetContainerNumSlots` loop bound) — FIXED**,
commit `26f070b`. The finding was correct and the traced failure mode was worse than the
asymmetry suggested: a raise lands after `wipe()` has emptied the catalogue but before
`itemCatalogueDirty` is cleared, so the catalogue would be left empty *and* permanently dirty,
and every subsequent `BAG_UPDATE` would re-enter and re-raise rather than degrade. An unreadable
bag now contributes zero rows for that pass. No measurement says this call is ever secret; it is
guarded anyway, because a loop bound is the worst possible place to make an exception to the
`issecretvalue`-before-`type` rule.

**INFO (`CDMTab.lua:208-213`, `725-740`, charge-count subframe on every pooled tile) — ACCEPTED,
NOT CHANGED.** The observation is accurate: every pooled tile in every section now carries a
`Frame` + `FontString` that only Suggested item tiles use. It is left as-is deliberately:

- **It is the established precedent, not a deviation.** `Display.lua:478-483` creates
  `frame.chargeCount` unconditionally on *every* display icon and hides it on creation, for the
  reason its own comment gives — a freshly pooled icon has no charge answer yet. The new code is a
  field-for-field copy of that, which is exactly what `46-CONTEXT.md` locked ("rather than
  inventing a second count style").
- **The alternative is worse.** Lazy creation would add a branch to the render path
  (`ns:RefreshTBTSections`, eleven call sites) to save a bounded, one-time allocation on pooled
  frames that are reused for the session.
- **The cost is bounded.** Tiles are pooled, so this is proportional to visible tiles, not to bag
  size or catalogue size, and nothing here allocates per render.

Re-raising this in Phase 50's cleanup would be a refactor of the pattern `Display.lua` already
established, which `PROJECT.md`'s "No refactors during cleanup phases" decision protects.
