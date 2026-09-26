---
status: findings
phase: 47-item-tracking-cooldown-sharing
files_reviewed:
  - Providers.lua
  - Core.lua
  - CDMTab.lua
  - Display.lua
diff_base: 137d0a8..HEAD
counts:
  blocker: 1
  warning: 3
  info: 2
---

# Phase 47 Code Review — Item Tracking & Cooldown Sharing

Scope: `git diff 137d0a8..HEAD -- Providers.lua Core.lua CDMTab.lua Display.lua`. No refactors
proposed on pre-existing code; every finding below is about lines this diff added or changed.

## BLOCKER

### B1: The landed-use decrement mechanism (ITEM-06) is silently inert for the entire session until the player opens Blizzard's Cooldown Manager settings panel at least once

**Where:**
- `Providers.lua:926` — `local itemUseSpellToID = {}` is a file-local upvalue, populated only
  inside `ns:RefreshItemCatalogue` (`Providers.lua:941`).
- `Providers.lua:1440` — `ItemProviderMixin:OnTrigger` (the entire landed-use decrement + instant
  cross-item cooldown refresh mechanism) does `local itemID = itemUseSpellToID[spellID]; if itemID
  == nil then return nil end` — if the map is empty, every single landed use of every tracked item
  is silently a no-op for this provider, for the whole session.
- `CDMTab.lua:36` — `ns:RefreshItemCatalogue()` is called from `StartPreview()`, and `StartPreview`
  (`CDMTab.lua:27`) is called **only** from the `cdmWatcher:SetScript("OnUpdate", ...)` poll at
  `CDMTab.lua:1824`, which fires only when `CooldownViewerSettings:IsVisible()` transitions to
  true — i.e., only when the player opens Blizzard's own Cooldown Manager settings window (the
  window TBT's tab attaches to).
- `CDMTab.lua:53-66` (`RequestItemCatalogueRebuild`) is the only other caller of
  `ns:RefreshItemCatalogue`, and it early-returns unless `ns.configOpen` (`CDMTab.lua:54`) is
  already true — the same flag `StartPreview` alone sets.

**Issue:** `itemUseSpellToID` is a plain Lua local, rebuilt from scratch (`wipe`'d, `Providers.lua:946`)
every time `RefreshItemCatalogue` runs, and it is **never** persisted or pre-warmed at
`ADDON_LOADED`/`PLAYER_ENTERING_WORLD`. The only two call sites that fill it both require the
Blizzard Cooldown Manager settings window to have already been shown this session. A player who
logs in, reloads the UI, or zones without ever opening that specific settings panel will have an
empty `itemUseSpellToID` for the rest of the session. Every tracked item they created in a *prior*
session still renders correctly (icon, sweep — both driven by the persisted DB entry and the
stamped `ns.cooldownStarts`), but drinking a tracked potion or using a tracked item this session
does **nothing** through the fast path: no decrement, and no immediate cross-item cooldown refresh
(`ns:RefreshTrackedItemCooldowns()` at `Providers.lua:1460` is likewise never reached, since the
map lookup that gates it fails first).

This is not the documented "accepted gap" (two items sharing one use-spell, `Providers.lua:1000-1012`)
— it is a different, unacknowledged failure mode: **all** item tracking, not one colliding pair.

**Why it matters:** CONTEXT.md's locked decision text is explicit that the decrement is meant to be
the primary, always-on mechanism ("no overhead — this IS how we're gonna handle this"), with the
combat-end/bag-settle reconcile (`ns:ReconcileTrackedItemCounts`, `PLAYER_REGEN_ENABLED` handling at
`Core.lua:980-996`, `PLAYER_EQUIPMENT_CHANGED`/`BAG_UPDATE_DELAYED` handling at `Core.lua:1019-1026`)
positioned as absorbing *residual* drift, not as the only mechanism that ever runs. In practice, for
any session where the player never happens to open the Cooldown Manager settings panel, the
reconcile becomes the *sole* source of truth, and it is combat-gated (`InCombatLockdown()` check,
`Providers.lua:1138`) — meaning a potion drunk mid-fight shows a stale (one-too-high) count for the
rest of that fight, correcting only when `PLAYER_REGEN_ENABLED` fires. This directly contradicts
ITEM-06 ("count decreases only [and, implicitly, promptly] on a landed use") for what is likely to
be the common case, not an edge case — most play sessions do not involve opening addon config UI at
all.

**Fix:** Warm the catalogue (and therefore `itemUseSpellToID`) independent of `ns.configOpen`, e.g.
call `ns:RefreshItemCatalogue()` once from the existing `PLAYER_ENTERING_WORLD` handler
(`Core.lua:953`) or from `ADDON_LOADED` after `ns.db` is ready, the same way `ns:RebuildRankIndex()`
already runs unconditionally on world entry for the analogous rank-index problem. A full bag walk
once per load is the same cost `StartPreview` already accepts on every CDM open, so this is not a
new class of expense — only a new call site.

## WARNINGS

### W1: `ns:SeedItemTracker`'s guarded cooldown seed can be defeated by the same session-scoped gap as B1

**Where:** `Providers.lua:1070-1103` (`ns:SeedItemTracker`), called once from
`CDMTab.lua:189` (`AddSuggestedTracker`'s `if itemID then` block).

**Issue:** This one is not itself broken — it runs synchronously at tracker-creation time using a
direct `C_Item.GetItemCooldown`/`GetItemCount` read, not the use-spell map, so it is unaffected by
B1. Flagged only because it means a tracker's *initial* seed is always correct while a use that
happens *afterward, later in the same session* can silently fail to update it if B1 has not yet
been closed — i.e., B1 is the root cause and this is the second place its blast radius shows up
(cooldown side, not just count side, since `ns:RefreshTrackedItemCooldowns()`, `Providers.lua:1110`,
is unreachable from `OnTrigger` under the same condition). No separate fix needed beyond B1 —
recorded here so the fix for B1 is verified against both symptoms, not just the count one.

### W2: Redundant `ns:ReconcileTrackedItemCounts()` call from `PLAYER_EQUIPMENT_CHANGED`

**Where:** `Core.lua:1019-1026`. `PLAYER_EQUIPMENT_CHANGED` and `BAG_UPDATE_DELAYED` are handled by
the same `elseif` branch, and the new `ns:ReconcileTrackedItemCounts()` call (`Core.lua:1026`) fires
on both. `PLAYER_EQUIPMENT_CHANGED` has no relationship to consumable stacks — it fires on gear
swaps, not bag/item-count changes.

**Issue:** Not incorrect (the function is cheap and combat-gated), but every gear swap now also
walks `ns.db.trackedBuffs` and issues one `C_Item.GetItemCount` call per tracked item for no reason
connected to the event that triggered it. Minor, but it is duplicated work this phase introduced
that has no corresponding benefit — equipment changes do not affect consumable stack counts.

**Fix:** Move the `ns:ReconcileTrackedItemCounts()` call to only the `BAG_UPDATE_DELAYED` branch (the
event actually tied to bag content changes), not the shared `PLAYER_EQUIPMENT_CHANGED` case.

### W3: Collision-detection log line is unreachable in the common case where it would be most useful

**Where:** `Providers.lua:1000-1012`.

**Issue:** The collision print is gated on `ns.debugLogging`, which defaults to `false`
(`BuffEngine.lua:7`) and is a manual `/tbt` toggle. Because `RefreshItemCatalogue` only runs while
the CDM settings panel is open (see B1), a collision — two catalogued items resolving to the same
use-spell — can only ever be observed by a player who has debug logging on *and* has the CDM open
*at the exact moment* the colliding pair is first scanned together. This is a narrow window for a
diagnostic whose entire purpose is to catch a rare, hard-to-reproduce condition. Not a correctness
bug (the "last writer wins" behavior itself is unaffected and matches the accepted design), but the
diagnostic value of the log line is close to zero as wired. Low priority; noting for completeness
since B1's fix (warming the catalogue at load) would also fix this for free.

## INFO

### I1: `ApplyItemCount` always calls `SetText`/`Show` on every generation-gated pass, unlike its sibling

**Where:** `Display.lua:966-976` (`ApplyItemCount`), compare to `ApplyChargeCount`
(`Display.lua:920-936`), which caches `chargeCapable[spellID]` and only calls `SetShown`/pcall'd
`SetText` when the charge-capable state is known, and guards the text write in a `pcall`.

**Issue:** `ApplyItemCount` has no such caching or protection — it calls
`icon.chargeCount.Current:SetText(count)` and `icon.chargeCount:Show()` unconditionally whenever the
enclosing generation-gate fires, even if `count` is unchanged from the last time this same widget
drew this same entry. This is not a hot-path issue (the enclosing block is already gated on
`ns.cooldownGeneration`/`icon._cdKey` change, not per-frame), so it is not a performance defect —
just an inconsistency with the sibling function's style, worth noting since `count` is a plain
integer TBT itself computed and `SetText` on a plain number cannot fail, so the asymmetry causes no
bug, only a style drift within functions doing near-identical jobs.

### I2: `ns.itemTrackedCounts` prune loop runs on every reconcile even when nothing was deleted

**Where:** `Providers.lua:1159-1163` (`ns:ReconcileTrackedItemCounts`'s prune pass,
`Providers.lua:1137-1169`).

**Issue:** The second `pairs(itemTrackedCounts)` loop walks every entry in the tracked-count table on
every reconcile call (combat-end and every out-of-combat bag settle), regardless of whether any
tracker was actually removed since the last reconcile. Functionally correct (Lua permits clearing
existing fields mid-`pairs`, as the code comment notes) and the table is small (one entry per
tracked item, not per catalogued item), so this is not worth blocking on — flagged only as the kind
of "redundant work on an event that can fire often" item CLAUDE.md's cleanup-phase mandate asks to
watch for. A cheap alternative would be tracking removal at the point `RemoveTrackedBuff` runs
(`BuffEngine.lua`, out of this phase's diff) rather than re-deriving it here every time, but that
would touch pre-existing code this review is not scoped to change.

## Summary

The core mechanism — `ItemProviderMixin:OnTrigger` returning `nil` unconditionally
(`Providers.lua:1426-1465`), `issecretvalue()`-before-`type()` ordering on every new
`C_Item.GetItemCooldown`/`GetItemCount` read, the floor-at-zero decrement, the separate
`ns.itemTrackedCounts` store instead of the catalogue's own live-bag-walk cache, and all five
`trackerType == "cooldown"` render/category gates correctly widened to `"item"` — is sound and
matches the locked design in CONTEXT.md/RESEARCH.md closely, with no phantom-timer risk and no
secret-value type-confusion found anywhere in the diff.

The one BLOCKER (B1) is a real, easily-reproduced gap the research did not surface: the entire
landed-use fast path depends on a table that is only populated while Blizzard's Cooldown Manager
settings window happens to be open, which most play sessions will never trigger, silently degrading
ITEM-06/ITEM-05's "instant" behavior to "eventually, and only out of combat" for the whole session.

---
_Reviewed: 2026-09-24_
_Reviewer: adversarial code review (Phase 47 diff only)_

---

## Orchestrator Resolution — 2026-09-24

**B1 (use-spell map only populated while the CDM is open) — FIXED**, commit `f5dc170`. Confirmed
before fixing: `ns:RefreshItemCatalogue` was reachable only from `CDMTab.lua:36` (`StartPreview`)
and the `ns.configOpen`-gated rebuild at `:66`. The finding was exactly right, and it was the most
valuable output of this phase's entire review chain — the plan checker passed the plans, and the
verifier traced the landed-use chain forward and found it sound, because the defect is invisible
unless you trace *backwards* from `itemUseSpellToID` to ask who ever writes it.

Fix registers tracked items' use-spells from `ns.db.trackedBuffs` with no bag access, at three
points: tracker creation, `PLAYER_ENTERING_WORLD` (so a tracker restored from SavedVariables works
before the CDM is ever opened, and an item uncached at login is retried on zone-in), and the end of
`ns:RefreshItemCatalogue` — whose `wipe()` would otherwise drop tracked entries for an item no
longer in the bags, which is precisely the zero-stock case ITEM-09 exists to cover.

**W1 — RESOLVED BY THE SAME FIX.** Correctly filed as a second symptom of one root cause.

**W2 (`PLAYER_EQUIPMENT_CHANGED` triggers a consumable reconcile) — FIXED**, same commit. The
reconcile is now scoped to `BAG_UPDATE_DELAYED`; the two events share a dispatch branch, and a gear
swap cannot change how many consumables are in the bags.

**W3 (collision debug log unreachable) — RESOLVED BY THE B1 FIX** as far as tracked items go. The
log lives in the catalogue scan, so it still only runs on a catalogue rebuild; that is correct,
because a collision is a property of the *catalogue*, not of one tracked item.

**I1, I2 — ACCEPTED, NOT CHANGED.** Both are style/redundancy notes in `ApplyItemCount` and the
reconcile prune loop, and neither is a bug by the reviewer's own assessment. `ApplyItemCount`
deliberately mirrors the shape of the adjacent `ApplyChargeCount` it sits beside; changing it to be
marginally terser would make the pair read less alike for no behavioural gain.
