# Pitfalls Research

**Domain:** WoW addon — CDM tab integration, Edit Mode movable elements, drag-and-drop buff management, aura-based timer cancellation, trinket/pot meta-trackers
**Researched:** 2026-03-28 (CDM/EditMode/DnD) | 2026-04-03 (aura cancellation v0.2.1) | 2026-04-11 (trinket/pot meta-trackers v0.3.0)
**Confidence:** HIGH (CDM/EditMode sourced from Blizzard UI source) | MEDIUM (aura section sourced from Warcraft Wiki + Cell addon PR + Midnight dev docs) | MEDIUM (v0.3.0 sourced from Warcraft Wiki API docs + Midnight dev forum + TrinketTracker Midnight addon analysis)

---

## v0.3.0 Milestone: Trinket and Pot Meta-Tracker Pitfalls

This section covers pitfalls specific to adding trinket and damage pot meta-tracker slots to the existing TBT timer system. These slots use shared-slot overwrite behavior (one key per tracker, not per spell), dynamic icon resolution from equipped gear and bag consumables, and `UNIT_SPELLCAST_SUCCEEDED` cast detection for known spellIDs.

---

### Meta-Tracker Pitfall 1: Source Marker Absent — Aura Scan Immediately Cancels Meta-Timer

**What goes wrong:**
Trinket and pot buffs are tracked under string meta-keys (`"trinket"`, `"pot"`) like the lust meta-buff under `"lust"`. When a timer is created at `ns.activeTimers["trinket"]`, the `ScanActiveTimersForCancellation` function iterates `ns.activeTimers` and checks each timer's `source` field. If the timer has no `source` field, or has `source = "cast"`, the scan calls `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` using the timer's `spellID` field — which is the string `"trinket"`, not a numeric spell ID. `GetPlayerAuraBySpellID` with a string argument produces a type error or silently returns nil (nil treated as "buff absent"), causing the meta-timer to be cancelled on the very first aura scan after it is started.

**Why it happens:**
The existing `OnSpellCastSucceeded` path stores `spellID = spellID` (the numeric cast spell ID) in the timer, which is safe for `source = "cast"` timers because the key and the aura lookup match. Meta-trackers use string keys but their aura lookup must use the actual buff spell ID — or must be routed through a source branch that bypasses the direct aura check. Developers copy the timer creation pattern from `OnSpellCastSucceeded` without adjusting the source marker, producing a timer that looks like a cast-sourced timer but has an unresolvable aura lookup.

**How to avoid:**
Assign `source = "meta"` (or a purpose-specific value like `source = "trinket"`) on all meta-tracker timers. Add a `source == "meta"` branch in `ScanActiveTimersForCancellation` that skips the aura check entirely — meta-trackers are cast-detection only; they have no corresponding aura to verify because trinket proc buffs and pot buffs are secret values in restricted contexts. The lust meta-tracker uses `source = "debuff"` with a `lustBuffID` field; trinket/pot timers need their own equivalent non-default source tag.

```lua
-- Timer creation for meta-trackers:
ns.activeTimers["trinket"] = {
    spellID = "trinket",
    castSpellID = actualSpellID,  -- the actual cast spell ID (for icon, label)
    source = "meta",              -- prevents aura scan cancellation
    expiresAt = now + duration,
    ...
}

-- In ScanActiveTimersForCancellation:
if timer.source == "meta" then
    -- meta-trackers are not verified against auras — skip
elseif timer.source == "cast" then
    -- existing aura check path
elseif timer.source == "debuff" then
    -- existing lust check path
end
```

**Warning signs:**
Meta-tracker timer appears on cast and vanishes within one event tick. Debug logging shows cancellation with label "trinket" or "pot" immediately after creation.

**Phase to address:**
Timer creation phase (first phase of v0.3.0). The source marker must be correct before any end-to-end testing.

---

### Meta-Tracker Pitfall 2: Overwrite Behavior Loses the Previous Timer on Re-Cast

**What goes wrong:**
The shared-slot design means `ns.activeTimers["trinket"]` is always overwritten on each new cast. If the player casts a trinket while a previous trinket timer is still running (possible with two different on-use trinkets, or a pot and a trinket sharing the same meta-key), the previous timer disappears with no warning and the display shows only the new timer. This is intentional per-spec — but the bug appears when the overwrite uses the wrong key or when the new timer's icon and label data comes from a stale cache.

A specific sub-case: if the player switches trinkets between pulls (unequips trinket A, equips trinket B), the icon cache for the meta-tracker slot was resolved for trinket A. The next cast of trinket B starts a timer with trinket A's icon unless the cache is invalidated on equip change.

**Why it happens:**
Icon resolution is done out of combat and cached. The equip event that would invalidate the cache (`UNIT_INVENTORY_CHANGED`) is not registered, so the cache is never refreshed after trinket swaps.

**How to avoid:**
Register `UNIT_INVENTORY_CHANGED` for "player" unit. On this event, call the icon resolution function for both trinket slots and for the pot bag scan. Do not allow resolution to run in combat (`InCombatLockdown()` returns true) — defer the refresh to after combat ends via `PLAYER_REGEN_ENABLED`. Cache the resolved icon per meta-key (e.g., `ns.metaIcons["trinket"]`) and use it as the idle-state display; switch to the active cast's spell icon when a timer is running.

```lua
-- Register:
eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")

-- Handler:
if not InCombatLockdown() then
    ns:RefreshMetaIcons()
else
    ns.metaIconRefreshPending = true  -- refresh on PLAYER_REGEN_ENABLED
end
```

**Warning signs:**
After a trinket swap (seen by equipping a different trinket), the idle icon in the CDM Suggested section shows the old trinket's icon. On cast, the timer icon is also wrong.

**Phase to address:**
Icon resolution phase. The pending-refresh pattern must be established before release.

---

### Meta-Tracker Pitfall 3: `GetInventoryItemID` Returns a Secret Value in Combat

**What goes wrong:**
`GetInventoryItemID("player", slotID)` is documented as returning the item ID for an equipped item. However, in Midnight (Interface 120000+), any API that queries inventory slot data during combat — particularly during Mythic+ or PvP — may return a secret value. Attempting to use the returned item ID as a table index (`ns.trinketIconCache[itemID]`) or pass it to `C_Item.GetItemInfo(itemID)` after it is received as a secret value will throw a Lua error or silently return nil from the downstream call.

The TrinketTracker Midnight addon explicitly documents this: "in combat, most APIs return secret values that cannot be used directly" and works around this by caching out of combat exclusively.

**Why it happens:**
The natural implementation calls `GetInventoryItemID` whenever the icon is needed — including on every CDM settings open during combat. This works in open world but errors in restricted contexts.

**How to avoid:**
Gate ALL inventory slot queries behind `InCombatLockdown()`. Never call `GetInventoryItemID` during combat. Use a pre-computed cache (`ns.metaIcons["trinket"]`) resolved out of combat, and serve that cache for display during combat. The cache should be populated on: addon load, `PLAYER_REGEN_ENABLED` if a refresh was pending, `UNIT_INVENTORY_CHANGED` when out of combat, and CDM settings open when out of combat.

Additionally, guard the return value with `issecretvalue()` as a fail-safe even when called out of combat, since Midnight's secret value restrictions can be applied to non-combat contexts in some zone types:

```lua
function ns:ResolveEquippedTrinketIcon(slotID)
    if InCombatLockdown() then return end
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID or issecretvalue(itemID) then return end
    local info = C_Item.GetItemInfo(itemID)
    if info then
        ns.metaIcons["trinket"] = info.iconFileDataID
    end
end
```

**Warning signs:**
Lua error: "attempt to index a Secret Value" originating from icon resolution code. Error occurs only when the CDM settings panel is opened during combat in Midnight.

**Phase to address:**
Icon resolution phase. The `InCombatLockdown()` gate and `issecretvalue()` guard must be present before any in-game testing.

---

### Meta-Tracker Pitfall 4: `C_Item.GetItemInfo` Returns nil for Uncached Items

**What goes wrong:**
`C_Item.GetItemInfo(itemID)` returns nil if the item has not been cached by the client. Trinkets and pots that the player has never had in their inventory (e.g., a trinket acquired just before the session, or a pot bought at the auction house mid-session) may not be in the client cache. Calling `GetItemInfo` immediately after `GetInventoryItemID` on a freshly equipped trinket returns nil, and the addon stores nil as the meta-icon — causing a broken or question-mark icon.

**Why it happens:**
`GetItemInfo` triggers a server request for uncached items but does not block — it returns nil immediately and fires `GET_ITEM_INFO_RECEIVED` when the data arrives. Code that does not handle the asynchronous case uses the nil return directly.

**How to avoid:**
After a nil return from `GetItemInfo`, register for `GET_ITEM_INFO_RECEIVED` and retry when the event fires with the matching item ID:

```lua
function ns:ResolveItemIcon(itemID, cacheKey)
    local info = C_Item.GetItemInfo(itemID)
    if info then
        ns.metaIcons[cacheKey] = info.iconFileDataID
        ns:RefreshDisplay()
        return
    end
    -- Item not cached — register for async callback
    ns.pendingItemIconRequests[itemID] = cacheKey
    -- GET_ITEM_INFO_RECEIVED handler resolves these
end
```

Alternatively, use `ItemMixin:ContinueOnItemLoad()` which provides a clean async pattern. The key constraint: never let the nil icon propagate to the display — fall back to the question-mark icon (texture ID 134400, already used in `GetSpellIcon`) until the real icon arrives.

**Warning signs:**
Meta-tracker slot shows question mark icon even when trinket is equipped. Resolves after a `/reload` once the item has been cached from that previous load.

**Phase to address:**
Icon resolution phase. The async fallback must be part of the initial implementation, not deferred.

---

### Meta-Tracker Pitfall 5: Bag Scan Finds Multiple Matching Pots — Wrong Icon Displayed

**What goes wrong:**
The damage pot bag scan iterates `C_Container.GetContainerItemInfo` across all bags looking for items matching the known damage pot item IDs. If the player has multiple different pot types in their bags (e.g., an older tier pot and the current season pot), the scan returns whichever it finds first (bag 0 slot 1 wins). The icon displayed may be for a pot the player cannot use (wrong level, wrong spec) or prefers not to use, even though a preferred pot is in a later bag slot.

**Why it happens:**
Bag scanning with `for bag = 0, NUM_BAG_SLOTS do for slot = 1, GetContainerNumSlots(bag) do` finds the first match. There is no priority ordering.

**How to avoid:**
Define an explicit priority order in the pot allowlist — either by item ID priority or by current season tier. The bag scan should iterate the allowlist from most-preferred to least-preferred item ID, and for each item ID check if it is present in any bag. This gives a deterministic result that matches player intent. If no preferred pot is found, fall back to question mark icon (not an arbitrary pot icon).

```lua
-- Ordered list, index 1 = highest priority
local POT_PRIORITY = { 12345, 23456, 34567 }  -- current season pots, high to low

local function FindBestPotIcon()
    for _, itemID in ipairs(POT_PRIORITY) do
        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == itemID then
                    return info.iconFileID
                end
            end
        end
    end
    return nil  -- no matching pot found
end
```

**Warning signs:**
Icon shows the wrong pot texture when multiple pot types are in bags. Players notice when they use consumable bags and the icon changes unexpectedly.

**Phase to address:**
Icon resolution phase — bag scan implementation must define priority order from the start.

---

### Meta-Tracker Pitfall 6: Bag Scan During Combat — `C_Container` APIs May Behave Unexpectedly

**What goes wrong:**
Unlike `GetInventoryItemID`, `C_Container.GetContainerItemInfo` is documented as `AllowedWhenUntainted` and is not in the same secret-value category as combat-restricted APIs. However, calling bag scans during combat can still produce unexpected behavior: item counts change mid-scan (pot is consumed mid-iteration), slot data returns stale results while loot or trading is in progress, and the scan itself adds overhead to an already-busy combat loop.

More critically, if the bag scan is triggered on `UNIT_INVENTORY_CHANGED` (which fires when items are consumed, picked up, or moved), and the trigger happens during combat because a pot was just used, the scan runs in combat and re-resolves the icon — which is exactly the moment when the old pot's icon should be replaced by the active-timer icon, not by a fresh bag scan that returns the next pot's icon.

**Why it happens:**
`UNIT_INVENTORY_CHANGED` fires in combat when a consumable is used. If the icon refresh is also triggered by this event, it creates a race: (1) cast detected → timer started with pot's icon; (2) inventory changed (pot count decreased) → bag scan runs → new icon set to remaining pot (or question mark if stack depleted) → overwrites the timer's icon or the display's cached icon.

**How to avoid:**
Separate the icon refresh trigger from combat events. Only refresh bag scan icons on `PLAYER_REGEN_ENABLED` (leaving combat) or on explicit CDM settings open. Do not trigger bag scan on `UNIT_INVENTORY_CHANGED` during combat. During an active timer, the display should show the active-timer icon (the spell icon of the cast that started the timer), not the bag scan icon — so the race window only affects the idle-state icon, which is hidden during an active timer anyway.

**Warning signs:**
Icon flickers between spell icon and item icon during an active pot timer. Bag scan runs every few seconds during combat (visible via debug logging).

**Phase to address:**
Icon resolution phase — event routing for `UNIT_INVENTORY_CHANGED` must explicitly exclude combat.

---

### Meta-Tracker Pitfall 7: Icon Transition on Timer Expiry — Stale Active Icon Persists

**What goes wrong:**
While a timer is active, the display shows the spell icon of the cast spell (the specific trinket or pot buff icon). When the timer expires, the display should revert to the idle icon (equipped trinket icon or bag pot icon). If `GetActiveTimers` removes the expired timer (setting `ns.activeTimers["trinket"] = nil`) but the display continues to use a cached icon reference from the timer object, the spell icon persists in the display until the next explicit refresh.

The display refresh cycle (`UpdateDisplay`) iterates `GetActiveTimers` for live timers and falls back to the DB entry for inactive slots. The DB entry must carry the resolved idle icon — if it was stored at drag-from-Suggested time (when no trinket context was known), it holds the generic icon. When the timer expires, the display reverts to this generic icon rather than the dynamically resolved equipped trinket icon.

**Why it happens:**
Icon resolution is a runtime concern but the DB entry (which provides the fallback) is set at buff-add time from the Suggested section data. The Suggested section definition in `ns.SUGGESTED_BUFFS` has a static `getCDMSpellID` function for lust, but trinket/pot have no parallel `getIdleIcon` function — so the CDM display falls back to the spell icon of the CDM spellID, not the dynamically resolved item icon.

**How to avoid:**
Extend the meta-tracker display path with a runtime idle icon resolver. The CDM display for string-keyed timers should call a `ns:GetMetaIdleIcon(key)` function that returns the current cached icon from `ns.metaIcons[key]`. This function is called when no active timer exists for the key, not when constructing the DB entry. The DB entry does not need to carry the icon — the display resolves it live at render time.

```lua
-- In Display.lua, when rendering a Suggested/meta slot with no active timer:
local idleIcon = ns:GetMetaIdleIcon(key) or ns:GetSpellIcon(resolvedSpellID)
```

**Warning signs:**
After a trinket timer expires, the CDM icon for the trinket slot shows the generic question mark or the spell icon rather than the equipped trinket's item icon.

**Phase to address:**
Display integration phase — the idle icon path must be defined when the display rendering for meta-trackers is first written.

---

### Meta-Tracker Pitfall 8: Preview Mode Starts Meta-Timer with Wrong Icon

**What goes wrong:**
`StartAllPreviewTimers` in `BuffEngine.lua` iterates `ns.db.trackedBuffs` and calls `ns:GetSpellIcon(resolvedID)` for each entry. For string-keyed meta-trackers (`"trinket"`, `"pot"`), `ResolveSuggestedSpellID(key)` returns the CDM display spell ID (e.g., a generic trinket spell). The preview timer icon is this spell's icon, not the dynamically resolved equipped trinket icon. This is cosmetically wrong but not a bug — the timer works correctly.

More seriously: if `StartAllPreviewTimers` is called in combat (unlikely but possible if a preview button is exposed in CDM settings), and the code path tries to resolve the meta icon dynamically, it may call `GetInventoryItemID` during combat.

**Why it happens:**
Preview mode was designed before meta-trackers existed. The icon resolution in `StartAllPreviewTimers` does not call `ns:GetMetaIdleIcon(key)`.

**How to avoid:**
In `StartAllPreviewTimers`, when the key is a string meta-key, check `ns.metaIcons[key]` first before falling back to the spell icon:

```lua
local icon
if type(spellID) == "string" and ns.metaIcons[spellID] then
    icon = ns.metaIcons[spellID]
else
    icon = ns:GetSpellIcon(resolvedID)
end
```

The CDM settings open event (which triggers icon resolution) should always run out of combat, so `ns.metaIcons` will be populated by the time preview is triggered.

**Warning signs:**
Preview mode shows generic trinket spell icon rather than the equipped trinket's item icon.

**Phase to address:**
Preview integration — update `StartAllPreviewTimers` when meta-trackers are first added, not deferred.

---

### Meta-Tracker Pitfall 9: UNIT_SPELLCAST_SUCCEEDED spellID Is Safe But Must Match Allowlist Exactly

**What goes wrong:**
`UNIT_SPELLCAST_SUCCEEDED` provides a `spellID` that is documented as `NeverSecret` — it is always a plain numeric value, never a secret value. This is the safe cast detection path for meta-trackers. However, the allowlist (the set of spell IDs that constitute "damage pot" or "on-use trinket") must match the exact spellIDs that appear in `UNIT_SPELLCAST_SUCCEEDED`, which is the on-use ability's spell ID, not the item's item ID.

The trap: many trinket items have multiple associated spells (the use-ability spell, the proc buff spell, and sometimes a shared cooldown trigger spell). Only the use-ability spell ID appears in `UNIT_SPELLCAST_SUCCEEDED`. If the allowlist uses item IDs or proc buff spell IDs instead of the use-ability spell IDs, no casts will ever match.

**Why it happens:**
Wowhead and warcraftlogs display item IDs prominently and buff spell IDs for aura tracking. The on-use ability spell ID is a third value not always shown in the same place. Developers copy an aura spell ID from a WeakAura and use it in the `UNIT_SPELLCAST_SUCCEEDED` allowlist.

**How to avoid:**
For each tracked trinket, verify the spell ID by casting the trinket in-game and using a debug print in the `UNIT_SPELLCAST_SUCCEEDED` handler to log the actual emitted spell ID. Cross-reference with Warcraft Wiki's spell pages where the ability is listed under "Spells" for the item. Do not use the item ID or the buff spell ID — use only the cast-event spell ID.

Document the distinction clearly in the allowlist:

```lua
-- Spell IDs here are the ON-USE ABILITY spell ID from UNIT_SPELLCAST_SUCCEEDED.
-- NOT the item ID. NOT the proc buff spell ID.
-- Verify each by casting in-game with debug logging active.
ns.TRINKET_SPELL_IDS = {
    [123456] = { duration = 20, label = "Trinket Name" },
}
```

**Warning signs:**
On-use trinket cast fires, debug logging shows `UNIT_SPELLCAST_SUCCEEDED` with a spellID, but no timer is started — the spell ID is not in the allowlist.

**Phase to address:**
Cast detection phase — spell ID verification must happen before allowlist is shipped.

---

### Meta-Tracker Pitfall 10: Schema Migration Collision — String Keys New to v0.3.0

**What goes wrong:**
`ns.db.trackedBuffs` uses numeric spell IDs as keys for user-added buffs and string keys for meta-buffs (`"lust"` since v0.2.1, `"trinket"` and `"pot"` new in v0.3.0). If a user has somehow created a tracked buff with the literal label-as-key `"trinket"` or `"pot"` (e.g., via a slash command or old migration artifact), the new meta-tracker DB entry will silently overwrite it.

The v2→v3 migration already handled the `"lust"` collision by checking `ns.db.trackedBuffs["lust"]` and removing it if it was auto-seeded. The same pattern is needed for `"trinket"` and `"pot"`.

**Why it happens:**
Each new string meta-key risks colliding with any user data stored under that key from a prior session. No schema version guards the new keys.

**How to avoid:**
Bump `CURRENT_SCHEMA_VERSION` to 4 in `BuffEngine.lua:InitBuffEngine`. Add a migration block for v3→v4 that checks `ns.db.trackedBuffs["trinket"]` and `ns.db.trackedBuffs["pot"]` — if they exist and were auto-seeded (e.g., `section == "hidden"`), remove them so the Suggested section can present them fresh. If the user has moved them to a visible section (user explicitly placed them), preserve the section but not any stale icon or spellID data.

**Warning signs:**
On first login after v0.3.0 update, trinket or pot meta-tracker slot is missing from CDM Suggested section, or is in an unexpected section. Check DB for pre-existing string keys.

**Phase to address:**
Data migration — must be the first phase of v0.3.0, before any runtime timer or display code.

---

### Meta-Tracker Pitfall 11: Two Trinket Slots, One Meta-Key — Which Cast Wins?

**What goes wrong:**
Players equip two trinkets (slots 13 and 14). If both trinkets are on-use and both spell IDs are in the allowlist, two near-simultaneous casts (macro: use trinket 1 then trinket 2) produce two `UNIT_SPELLCAST_SUCCEEDED` events. The second cast overwrites the timer started by the first, losing the first trinket's timer. The display shows the second trinket's remaining duration, not the longer of the two.

If the first trinket has a 20-second buff and the second has a 15-second buff, and the player casts both, the display shows 15 seconds when 20 seconds of the first buff remain.

**Why it happens:**
The shared-slot design (`ns.activeTimers["trinket"]`) inherently overwrites. The design assumes only one trinket is tracked at a time. This assumption is violated by two-trinket macros.

**How to avoid:**
On overwrite, compare expiry times and keep whichever expires later:

```lua
local existing = ns.activeTimers["trinket"]
if existing and existing.expiresAt > (now + duration) then
    -- existing timer expires later — do not overwrite
    return
end
-- otherwise overwrite (new cast or new cast expires later)
ns.activeTimers["trinket"] = { ... }
```

This "keep longest" policy ensures the display always shows the maximum remaining time, which is the correct behavior for a single-slot meta-tracker. Document this as explicit design: the slot shows the longest-running active trinket buff, not a specific trinket.

**Warning signs:**
After a two-trinket macro, the displayed timer is shorter than the longest-running trinket buff. Players notice the timer is wrong when they have two long-duration trinkets.

**Phase to address:**
Timer creation phase — the keep-longest guard should be implemented in the initial overwrite logic.

---

## Phase-Specific Warning Summary for v0.3.0

| Phase Topic | Pitfall | Mitigation |
|-------------|---------|------------|
| Data migration | String key `"trinket"`/`"pot"` collides with pre-existing user data | Schema v3→v4 migration checks and cleans these keys before any new runtime code runs |
| Cast detection | Allowlist uses wrong spell ID type (item ID or proc buff ID) | Verify each spell ID by casting in-game with debug logging; document the "use ability" ID distinction |
| Timer creation | Missing `source = "meta"` causes aura scan to cancel timer immediately | Assign `source = "meta"` on all meta-tracker timer entries; add `"meta"` branch in `ScanActiveTimersForCancellation` |
| Timer creation | Two-trinket macro overwrites the longer-running timer | Keep-longest overwrite: only replace if new timer expires later |
| Icon resolution | `GetInventoryItemID` called in combat returns secret value | Gate all inventory slot queries behind `InCombatLockdown()`; guard return with `issecretvalue()` |
| Icon resolution | `C_Item.GetItemInfo` returns nil for uncached item | Handle nil with `GET_ITEM_INFO_RECEIVED` async fallback; never store nil as the meta icon |
| Icon resolution | Bag scan finds multiple pot types — picks wrong one | Priority-ordered allowlist; scan most-preferred ID first |
| Icon resolution | `UNIT_INVENTORY_CHANGED` triggers bag scan during combat | Only refresh bag scan on `PLAYER_REGEN_ENABLED` or CDM open out of combat |
| Display | Expired timer leaves spell icon — does not revert to item icon | `GetMetaIdleIcon(key)` function resolves from `ns.metaIcons` cache at render time |
| Preview | Preview timer uses spell icon instead of equipped item icon | Check `ns.metaIcons[key]` first in `StartAllPreviewTimers` |
| Schema | New string keys not migrated — Suggested section shows wrong state | Schema v4 migration removes stale auto-seeded entries for `"trinket"` and `"pot"` |

---

## Integration Risks With Existing Aura Scan System

Trinket and pot timers integrate with the same `ScanActiveTimersForCancellation` loop that handles cast-sourced and debuff-sourced (lust) timers. Specific integration risks for meta-trackers:

| Risk | Source | Prevention |
|------|--------|------------|
| Meta-timer cancelled by aura scan | `source` field absent or `"cast"` causes `GetPlayerAuraBySpellID("trinket")` type error | Set `source = "meta"` and add bypass branch in cancellation scan |
| Meta-timer in preview saves/restores incorrectly | `savedPreviewTimers["trinket"]` holds preview timer; `ClearAllTimers` restores it as real | Preview meta-timers have no `source = "meta"` guard during restore — verify `ClearAllTimers` does not restore preview-only meta entries |
| Icon not updated when CDM settings open refreshes display | CDM settings open triggers display rebuild but meta icon not resolved yet (item not cached) | Ensure `GET_ITEM_INFO_RECEIVED` is handled and triggers display refresh after icon resolves |
| `issecretvalue` on timer's `castSpellID` if meta-timer stores the actual cast spellID | `castSpellID` field comes from `UNIT_SPELLCAST_SUCCEEDED` which is `NeverSecret` — safe | No guard needed for `castSpellID` specifically; but guard `GetInventoryItemID` result separately |
| `RefreshMetaIcons` called from `PLAYER_REGEN_ENABLED` while display is updating | Double `UpdateDisplay` in same frame | Set a `metaIconRefreshPending` flag and consolidate the refresh into the next display tick |

---

## Technical Debt Patterns (v0.3.0 additions)

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `issecretvalue()` guard on `GetInventoryItemID` result | Simpler icon resolution code | Lua error when CDM settings opened in combat in Midnight | Never |
| Use item ID as allowlist key instead of use-ability spell ID | Simpler map, matches Wowhead presentation | No casts ever match — meta-tracker never starts a timer | Never |
| Skip keep-longest overwrite logic | Simpler overwrite | Two-trinket macros show wrong timer duration | Acceptable only if spec explicitly documents single-trinket-only behavior |
| Trigger bag scan on every `UNIT_INVENTORY_CHANGED` including in combat | Always-fresh pot icon | Bag scan during combat; race with active-timer icon display | Never — gate behind `InCombatLockdown()` |
| Store nil into `ns.metaIcons` when item is uncached | Simpler error handling | Question mark icon persists permanently until reload once item is cached | Never — use `GET_ITEM_INFO_RECEIVED` fallback |
| Skip schema v4 migration for `"trinket"` and `"pot"` keys | Saves one migration block | Collision with any pre-existing user data under those keys | Never |

---

## "Looks Done But Isn't" Checklist (v0.3.0 additions)

- [ ] **Source marker:** All meta-tracker timers have `source = "meta"` AND `ScanActiveTimersForCancellation` has a `"meta"` bypass branch — verify by checking aura scan debug output after a trinket cast in M+
- [ ] **Combat icon gate:** `GetInventoryItemID` is never called when `InCombatLockdown()` is true — verify by adding a debug assertion
- [ ] **Async icon fallback:** `GET_ITEM_INFO_RECEIVED` is handled and triggers display refresh — verify by equipping a brand-new item and confirming icon appears within one event cycle
- [ ] **Bag scan priority:** Multiple pot types in bags produce the highest-priority pot's icon — verify by loading all season pot types in bags and confirming correct icon
- [ ] **Overwrite keeps longest:** Two quick trinket casts produce a timer showing the longer expiry — verify with two different-duration trinkets via macro
- [ ] **Icon revert on expiry:** After timer expires, display reverts to item icon (not spell icon, not question mark) — verify by waiting for timer to expire with equipped trinket
- [ ] **Schema migration:** `"trinket"` and `"pot"` keys absent from `ns.db.trackedBuffs` on fresh load; present and in correct section after user drags from Suggested — verify with DB inspection
- [ ] **Preview with meta-trackers:** Preview mode starts trinket/pot timers with correct item icons (not generic spell icons) — verify via `/tbt preview`

---

## Sources (v0.3.0 section)

- [UNIT_SPELLCAST_SUCCEEDED — Warcraft Wiki](https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED) — `spellID` parameter documented as `NeverSecret` (HIGH confidence — official wiki, current)
- [Blizzard Whitelists WoW Spells for Midnight Addons — Boosting Ground](https://boosting-ground.com/wow-boosting/news/blizzard-whitelists-spells-for-midnight) — spellID whitelist approach for Midnight addon detection (MEDIUM confidence — news summary of official dev post)
- [C_Item.GetItemInfo — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo) — nil on uncached item, async pattern with `GET_ITEM_INFO_RECEIVED`, iconFileDataID as 10th return (HIGH confidence — official wiki, current)
- [C_Container.GetContainerItemInfo — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerItemInfo) — `AllowedWhenUntainted`, returns `iconFileID` and `itemID`, nil on empty slot (HIGH confidence — official wiki, current)
- [TrinketTracker (Midnight) — CurseForge](https://www.curseforge.com/wow/addons/trinkettracker-midnight) — "in combat, most APIs return secret values; works around by caching out of combat" (MEDIUM confidence — published addon, implying real-world validation)
- [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes) — context-based secret restrictions (M+ active, PvP, encounter in progress); inventory/bag APIs not in combat-restricted category (MEDIUM confidence — official wiki, current)
- [Development clarification: Secret Values — Blizzard Forum](https://us.forums.blizzard.com/en/wow/t/development-clarification-maintaining-ui-accuracy-vs-secret-value-obfuscation-in-midnight/2243547) — combat-restricted vs non-restricted API categories; `issecretvalue` as guard pattern (MEDIUM confidence — official Blizzard post)
- [MidnightCheck — CurseForge](https://www.curseforge.com/wow/addons/midnightcheck) — "uses only aura reads, bag scans, and inventory APIs — none of which are restricted by Midnight's new secret value system" — implies bag/inventory APIs are generally unrestricted but context qualifications apply (LOW confidence — addon description, not authoritative documentation)
- [GET_ITEM_INFO_RECEIVED — Warcraft Wiki](https://warcraft.wiki.gg/wiki/GET_ITEM_INFO_RECEIVED) — event fires when server responds with uncached item data; standard async icon resolution pattern (HIGH confidence — official wiki, current)
- Existing `BuffEngine.lua` — `source = "debuff"` pattern on lust timers as precedent for meta-tracker source markers; `issecretvalue()` guard in `OnUnitAura` as precedent for secret value handling (HIGH confidence — first-party codebase)

---

*v0.3.0 pitfalls researched: 2026-04-11*

---

## v0.2.1 Milestone: Aura-Based Timer Cancellation Pitfalls

This section covers pitfalls specific to adding `UNIT_AURA`-based buff detection to the existing `UNIT_SPELLCAST_SUCCEEDED` timer system in WoW Midnight (Interface 120000+), where `COMBAT_LOG_EVENT_UNFILTERED` is disabled and aura data is subject to secret value restrictions.

---

### Aura Pitfall 1: Lua Error on Comparison Against Secret `spellId` Field

**What goes wrong:**
`C_UnitAuras.GetAuraDataByIndex` returns an `AuraData` table marked `SecretWhenUnitAuraRestricted`. During restricted contexts (Mythic+ in progress, PvP match in progress, encounter in progress), the `spellId` field inside that table is a secret value — a black-box that cannot be compared, indexed, or used in arithmetic by untainted addon code. Attempting `auraData.spellId == trackedSpellID` will throw a Lua error: "attempt to compare a Secret Value".

**Why it happens:**
The natural approach is to iterate auras and compare `spellId` values against `ns.db.trackedBuffs`. This works out-of-combat but silently fails (with a Lua error, not a graceful nil) in restricted contexts.

**Consequences:**
Uncaught errors in event handlers cause the entire event handler to abort. Subsequent `UNIT_AURA` events will keep triggering and keep erroring, producing console spam and potentially tainting the UI frame stack.

**Prevention:**
Before using `auraData.spellId` in any comparison or table lookup, guard with `issecretvalue()`:

```lua
local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
if not auraData then break end
if issecretvalue(auraData.spellId) then
    -- entire aura slot is restricted — set blocked flag and abort scan
    ns.auraCheckBlocked = true
    return
end
if ns.db.trackedBuffs[auraData.spellId] then
    -- buff is present, mark it seen
end
```

**Detection:**
Error in chat: `attempt to perform arithmetic/comparison on a Secret Value` originating from BuffEngine.lua aura scan loop. Occurs only during M+, PvP, or boss encounters — never in open world, making it hard to reproduce in casual testing.

**Phase to address:** v0.2.1 core implementation. This guard must be present before any aura scan logic ships.

---

### Aura Pitfall 2: `C_Secrets` API Functions Are the Preferred Restriction Check

**What goes wrong:**
Patch 12.0.0 added explicit query functions for the restriction state:
- `C_Secrets.ShouldUnitAuraIndexBeSecret(unit, index, filter)`
- `C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)`
- `C_Secrets.ShouldSpellAuraBeSecret(spellID)`

Addons that use only `issecretvalue()` after the fact (checking after reading) rather than querying these functions proactively may read a partially-constructed AuraData table, where some fields are secret and others are not. This produces inconsistent state: `auraInstanceID` is `NeverSecret` and always readable, but `spellId`, `duration`, and `expirationTime` may be secret simultaneously, leading to code that appears to work but has silent gaps.

**Why it happens:**
`issecretvalue()` is well-documented; `C_Secrets.*` functions are newer additions that many tutorials do not cover.

**Prevention:**
Use `C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL")` as the first check per aura index. If it returns true, skip the index entirely — do not read any fields. This avoids the per-field secret check cascade and is the pattern consistent with Blizzard's own internal code.

**Phase to address:** v0.2.1 core implementation.

---

### Aura Pitfall 3: False Positive Timer Cancellation from `isFullUpdate` During Zone Transitions

**What goes wrong:**
`UNIT_AURA` fires with `updateInfo.isFullUpdate = true` during zone transitions and instance loads. At this point, the aura list for "player" may be temporarily empty or partially populated — the game is in the middle of reconstructing the unit's state. If the addon interprets `isFullUpdate = true` + empty aura scan as "all buffs have been removed" and cancels active timers, it will cancel timers for buffs the player actually still has (e.g., a 1-hour food buff that persists across zones).

**Why it happens:**
The natural implementation is: "if isFullUpdate, scan all auras and cancel timers for any tracked buff not found." This is logically correct in steady-state but wrong during the transient empty-aura window after a zone change.

**Consequences:**
Every zone change or instance entry cancels all active timers incorrectly. Players who cast a buff before a dungeon entrance lose the timer as they enter.

**Prevention:**
`PLAYER_ENTERING_WORLD` fires after every loading screen. Suppress aura-driven cancellations for a short window after `PLAYER_ENTERING_WORLD` fires, or gate `isFullUpdate` scans behind a readiness flag that is only cleared once the player is confirmed in-world. The existing `ns.displayInitialized` pattern in `Core.lua` can be extended for this purpose. Additionally, register `PLAYER_ENTERING_WORLD` as a timer-pause trigger — suspend aura cancellation logic, not the timers themselves, until the world is stable.

A simpler approach: **never cancel timers on `isFullUpdate`**. Only cancel on explicit `removedAuraInstanceIDs` entries. Use `isFullUpdate` only for resetting the aura instance ID cache (not for timer cancellation).

**Detection:**
Timers disappear every time the player crosses a zone boundary or enters a dungeon, even when buffs were active.

**Phase to address:** v0.2.1 core implementation — cancellation logic must be written to handle `isFullUpdate` correctly from the start.

---

### Aura Pitfall 4: Race Condition Between `UNIT_SPELLCAST_SUCCEEDED` and `UNIT_AURA`

**What goes wrong:**
When a player casts a spell that refreshes or re-applies a tracked buff, two events fire in close sequence:

1. `UNIT_SPELLCAST_SUCCEEDED` — TBT creates/overwrites the timer in `ns.activeTimers[spellID]`
2. `UNIT_AURA` — TBT scans auras; if the new aura application has not yet appeared in the aura list (or `isFullUpdate` is true while the game re-builds the aura table), TBT may conclude the buff is absent and cancel the timer that was just started

This creates a race where the cast succeeds, a timer is created, and then the aura scan immediately cancels it.

**Why it happens:**
`UNIT_SPELLCAST_SUCCEEDED` and `UNIT_AURA` both fire within the same event dispatch cycle but their relative order is not guaranteed to be stable in all cases, particularly for spells with instant application. The aura table is not necessarily updated before `UNIT_AURA` fires — the event signals "something changed" but the change may not yet be reflected if the scan happens in the same tick.

**Prevention:**
After `UNIT_SPELLCAST_SUCCEEDED` creates a timer, set a short-lived grace period flag on that spell: `ns.recentlyCast[spellID] = GetTime() + 0.5`. In the `UNIT_AURA` cancellation handler, skip cancellation for any spell whose `recentlyCast` entry is still valid. This is a standard pattern used by WeakAuras and similar addons to absorb the cast-to-aura lag.

```lua
-- In OnSpellCastSucceeded:
ns.recentlyCast[spellID] = GetTime() + 0.5

-- In aura cancellation scan:
if ns.recentlyCast[spellID] and GetTime() < ns.recentlyCast[spellID] then
    -- grace period: skip cancellation for this spell
else
    ns.activeTimers[spellID] = nil
end
```

**Detection:**
A tracked buff timer appears for a fraction of a second then immediately disappears after casting the spell.

**Phase to address:** v0.2.1 core implementation. The grace period must be wired before cancellation logic is written.

---

### Aura Pitfall 5: Blocking Logic Must Survive UI Reload and Addon Re-Init

**What goes wrong:**
The planned design caches a "blocked" flag (`ns.auraCheckBlocked`) when secret values are detected. This flag is runtime-only (not persisted). After a `/reload` in the middle of an M+ run, the flag is cleared — the next `UNIT_AURA` event will attempt a scan without the block in place, hit a secret value, error, and then re-set the block. This is one spurious Lua error per reload during restricted content.

The same issue applies if `PLAYER_REGEN_ENABLED` fires and clears the block during a brief lull between pulls within the same M+ key — the key is still "active" even out of combat, so aura data remains secret.

**Why it happens:**
`PLAYER_REGEN_ENABLED` fires when combat drops, but M+ and PvP restrictions are keyed on whether the *instance/match* is active — not on combat state. Out-of-combat during M+ still has secret aura values.

**Prevention:**
Use the correct reset trigger. `PLAYER_REGEN_ENABLED` is appropriate for raid encounter detection but NOT for M+ or PvP. For a safe reset:
- Clear blocked flag on `ZONE_CHANGED_NEW_AREA` (leaving the instance entirely)
- Clear blocked flag on `PLAYER_ENTERING_WORLD` with `isLogin = true` or `isReload = true`
- Do NOT clear on `PLAYER_REGEN_ENABLED` unless the design is limited to encounter-only blocking

Alternatively: clear only on `ZONE_CHANGED_NEW_AREA` and keep the block for the entire instance duration. If aura data becomes readable again (e.g., after an encounter ends and the key hasn't started the next one), re-test on the next `UNIT_AURA` event by checking `issecretvalue` on the first readable field, and only clear the block when a successful non-secret read occurs.

**Detection:**
Intermittent Lua errors during M+ between pulls or after `/reload` mid-run.

**Phase to address:** v0.2.1 blocked-flag logic. Must be designed with correct event triggers before implementation.

---

### Aura Pitfall 6: Full Aura Scan Per Event Is a Performance Problem

**What goes wrong:**
`UNIT_AURA` fires very frequently — on every buff tick, proc, DEBUFF application to any unit that the player has registered, and on haste/modifier changes affecting duration. A naive implementation that iterates all aura slots (`C_UnitAuras.GetAuraDataByIndex` in a loop up to 40+ slots) on every event creates significant per-event CPU cost that compounds in large encounters.

**Why it happens:**
The simple approach: "on UNIT_AURA, loop all auras, check if tracked buffs are present." This works but ignores the incremental update data the event provides.

**Prevention:**
Use the `updateInfo` payload to avoid full scans:

1. If `updateInfo.removedAuraInstanceIDs` is present, only cancel timers whose cached `auraInstanceID` matches entries in that list. No full scan needed.
2. If `updateInfo.addedAuras` is present, skip — TBT does not start timers from aura events, only from `UNIT_SPELLCAST_SUCCEEDED`.
3. Only perform a full scan when `updateInfo.isFullUpdate == true` (and even then, only when not in a grace period or zone transition).

This requires maintaining a mapping: `ns.activeTimers[spellID].auraInstanceID` — populated when the aura is first seen after a cast succeeds. Without this cache, `removedAuraInstanceIDs` cannot be used efficiently.

**Phase to address:** v0.2.1 core implementation. The `auraInstanceID` cache design must be established before writing the event handler.

---

### Aura Pitfall 7: `GetAuraDataByAuraInstanceID` Returns nil for Removed Auras

**What goes wrong:**
The Warcraft Wiki documentation explicitly states: "GetAuraDataByAuraInstanceID will not work on removed aura InstanceIDs." If TBT tries to confirm a removal by calling `C_UnitAuras.GetAuraDataByAuraInstanceID` after receiving a `removedAuraInstanceIDs` entry, the call returns nil — which is correct behavior but may be misinterpreted as "buff not found therefore not tracked" in code that also handles "never existed" nil returns.

**Why it happens:**
Code that calls `GetAuraDataByAuraInstanceID` to validate before cancelling may incorrectly interpret the nil as an error state rather than confirmation of removal.

**Prevention:**
When `removedAuraInstanceIDs` entries arrive, look them up in a locally-maintained reverse map (`ns.auraInstanceToSpellID`) rather than re-querying the API. The reverse map is built as auras are observed via `addedAuras` in prior events. This cache must handle stale entries (from zone transitions where the full aura list resets).

**Phase to address:** v0.2.1 core implementation — establish the reverse-map pattern before writing removal logic.

---

### Aura Pitfall 8: Aura Instance ID Cache Becomes Stale After `isFullUpdate`

**What goes wrong:**
After `isFullUpdate = true`, all previous `auraInstanceID` values are invalid — aura instance IDs are re-assigned. If TBT's reverse map (`ns.auraInstanceToSpellID`) is not cleared on `isFullUpdate`, it will contain stale mappings. A subsequent `removedAuraInstanceIDs` entry containing an instance ID that was re-used for a *different* aura could cause incorrect timer cancellation.

**Why it happens:**
The cache is built incrementally and developers forget that `isFullUpdate` is a full reset signal, not an additive update.

**Prevention:**
On every `isFullUpdate`, wipe the entire `auraInstanceToSpellID` reverse map before rebuilding from the current aura list. This is the correct steady-state behavior: treat `isFullUpdate` as "start over."

**Phase to address:** v0.2.1 core implementation — document the wipe-on-isFullUpdate contract in a comment.

---

### Aura Pitfall 9: Registering `UNIT_AURA` for All Units Instead of Just "player"

**What goes wrong:**
`eventFrame:RegisterEvent("UNIT_AURA")` fires for any unit whose aura changes — including party members, raid members, pets, and focus targets. If TBT registers without filtering, the `UNIT_AURA` handler fires far more often than necessary (every party member's buff tick) and the `unitTarget` argument must be checked first. Missing this check causes full aura scans for non-player units, wasting CPU and potentially reading the wrong unit's aura list.

**Why it happens:**
`RegisterEvent` without `RegisterUnitEvent` does not filter by unit. The event fires globally.

**Prevention:**
Use `eventFrame:RegisterUnitEvent("UNIT_AURA", "player")` instead of `RegisterEvent("UNIT_AURA")`. This limits firing to player-unit aura changes only. The existing pattern in `Core.lua` uses `RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")` with a unit check inside the handler — for aura scanning, unit-scoped registration is cleaner and cheaper.

**Detection:**
`UNIT_AURA` handler fires many times per second during group content, far more than expected from personal buff changes alone.

**Phase to address:** v0.2.1 — use `RegisterUnitEvent` from the start, not `RegisterEvent`.

---

### Aura Pitfall 10: Buffs in Section "hidden" Should Not Trigger Aura Scan

**What goes wrong:**
`ns.db.trackedBuffs` contains entries for all tracked buffs, including those in the `"hidden"` section. When aura scanning determines a buff is absent and calls cancellation, it iterates all tracked buff spell IDs including hidden ones. For hidden buffs, `ns.activeTimers[spellID]` will already be nil (they are never started per `OnSpellCastSucceeded` which early-returns on `section == "hidden"`), so the cancellation is a no-op — but the check still happens. More critically, if the cancellation logic calls `ns:UpdateDisplay()` after removing any timer, and hidden buffs are included in the scan, a display refresh may fire unnecessarily.

**Why it happens:**
The scan logic iterates `ns.db.trackedBuffs` without filtering by section, mirroring the display logic that does filter.

**Prevention:**
Mirror the guard in `OnSpellCastSucceeded`:

```lua
for spellID, entry in pairs(ns.db.trackedBuffs) do
    if entry.section ~= "hidden" and ns.activeTimers[spellID] then
        -- check aura presence
    end
end
```

Only check auras for buffs that have active timers — no active timer means nothing to cancel. This is the simplest and most efficient filter.

**Phase to address:** v0.2.1 — include section guard in first pass of cancellation logic.

---

## Phase-Specific Warning Summary for v0.2.1

| Phase Topic | Pitfall | Mitigation |
|-------------|---------|------------|
| Event registration | `RegisterEvent` instead of `RegisterUnitEvent` fires for all units | Use `RegisterUnitEvent("UNIT_AURA", "player")` |
| Secret value detection | `spellId` comparison throws Lua error in M+/PvP/encounter | Guard with `issecretvalue()` + `C_Secrets.ShouldUnitAuraIndexBeSecret` before any comparison |
| Blocked flag reset | `PLAYER_REGEN_ENABLED` clears block during M+ out-of-combat lull | Reset on `ZONE_CHANGED_NEW_AREA`, not combat drop; or only on confirmed non-secret read |
| Zone transition | `isFullUpdate` with empty aura list cancels all timers on zone change | Suppress cancellation on `isFullUpdate` within `PLAYER_ENTERING_WORLD` window |
| Cast/aura race | New timer cancelled by aura scan that fires before aura appears | Grace period (`recentlyCast[spellID]`) of ~0.5s post-cast |
| Performance | Full aura loop per event in large raids | Use `removedAuraInstanceIDs` for targeted cancellation; full scan only on `isFullUpdate` |
| Instance ID cache | Stale instance IDs after `isFullUpdate` cause wrong cancellations | Wipe `auraInstanceToSpellID` cache on every `isFullUpdate` |
| Removed aura lookup | `GetAuraDataByAuraInstanceID` returns nil for removed auras | Use local reverse map, not API re-query, for removal confirmation |
| Hidden section buffs | Aura scan runs on hidden buffs with no active timers | Skip entries where `ns.activeTimers[spellID]` is nil |
| UI reload mid-restricted | Block flag cleared on reload; first post-reload event errors | Design block detection to be triggered by first secretvalue read, not state from previous session |

---

## Integration Risks With Existing `UNIT_SPELLCAST_SUCCEEDED` System

The two event systems must coexist without interfering. Specific integration risks:

| Risk | Source | Prevention |
|------|--------|------------|
| Timer cancelled immediately after cast | `UNIT_AURA` fires before aura list updates, sees buff absent | Grace period flag on `ns.recentlyCast[spellID]` after each cast |
| Timer reset to wrong duration by aura data | If future code tries to sync timer to `expirationTime` from aura, it overwrites the cast-based timer | Milestone scope: only cancel, never update duration from aura — enforce in code review |
| `UpdateDisplay` called twice per cast | Cast creates timer + calls `UpdateDisplay`; aura scan confirms buff present and also calls `UpdateDisplay` | Aura scan should NOT call `UpdateDisplay` when taking no action (buff confirmed present) |
| `ClearAllTimers` during preview conflicts with aura blocking logic | `StartAllPreviewTimers` creates fake timers; aura scan may cancel them immediately if blocked flag is set | Preview mode should bypass aura cancellation entirely — check `ns.previewMode` guard |

---

## Sources

**Aura cancellation section (v0.2.1):**
- [UNIT_AURA — Warcraft Wiki](https://warcraft.wiki.gg/wiki/UNIT_AURA) — event arguments, `isFullUpdate`, `addedAuras`, `removedAuraInstanceIDs` structure (MEDIUM confidence — current official wiki)
- [C_UnitAuras.GetAuraDataByIndex — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataByIndex) — `SecretWhenUnitAuraRestricted` classification, `auraInstanceID` NeverSecret status (MEDIUM confidence)
- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) — `C_Secrets.ShouldUnitAuraIndexBeSecret`, `C_Secrets.ShouldUnitAuraInstanceBeSecret`, `C_Secrets.ShouldSpellAuraBeSecret` additions; `SecretWhenUnitAuraRestricted` predicate documentation (MEDIUM confidence)
- [New UNIT_AURA Processing Optimizations — Blizzard Forum](https://us.forums.blizzard.com/en/wow/t/new-unitaura-processing-optimizations/1205007) — `isFullUpdate`, `updatedAuras` payload design rationale, early-out optimization pattern (HIGH confidence — official Blizzard post)
- [WoW 12.0.0 Compatibility PR #457 — enderneko/Cell](https://github.com/enderneko/Cell/pull/457) — real-world `issecretvalue()` guard patterns, per-field non-secret checks for `spellId`/`duration`/`expirationTime`, `IsAuraNonSecret()` helper pattern (MEDIUM confidence — peer-reviewed addon code)
- [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes) — `SecretWhenUnitAuraRestricted` context (M+ active, PvP match, encounter in progress) (MEDIUM confidence)
- [How to Track Specific Buffs in Midnight — spiritbloom.pro](https://spiritbloom.pro/blog/tracking-buffs-in-midnight) — real-world limitations of aura field access during secret contexts; aura count workarounds (LOW confidence — third-party guide)

**CDM/EditMode/DnD section (v0.2.0):**
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.lua`
- `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.xml`
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua`
- `Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua`
- `Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`
- `TerribleBuffTracker/Display.lua`
- `TerribleBuffTracker/Core.lua`

---

## v0.2.0 Pitfalls (CDM Tab / Edit Mode / Drag-and-Drop)

*These pitfalls were researched for the v0.2.0 milestone and remain valid for ongoing development.*

---

### Pitfall 1: CDM Settings Frame Not Initialized When Addon Loads

**What goes wrong:**
`CooldownViewerSettings` is a Blizzard frame loaded by `Blizzard_CooldownViewer`. If TBT accesses `CooldownViewerSettings` in `ADDON_LOADED` before that Blizzard addon has finished loading, all calls will hit nil and silently fail or error. Specifically, any attempt to call `CooldownViewerSettings:AddLayoutManager()` or access tab-related methods at startup will fail.

**Why it happens:**
TBT's `ADDON_LOADED` fires when TBT's own files are loaded, which may be before `Blizzard_CooldownViewer` completes. Addon load order within a session is not guaranteed.

**How to avoid:**
Register for and wait on `COOLDOWN_VIEWER_DATA_LOADED` before accessing CDM APIs. This event fires after `Blizzard_CooldownViewer` has fully initialized its layout managers and settings frame. All CDM-dependent initialization must be gated behind this event.

**Warning signs:**
- Lua error: "attempt to index global 'CooldownViewerSettings' (a nil value)" on login
- TBT tab never appears in CDM settings

**Phase to address:**
CDM tab integration phase (first phase). Gate initialization behind `COOLDOWN_VIEWER_DATA_LOADED` before writing any tab logic.

---

### Pitfall 2: Injecting Into CDM's `SetDisplayMode` System

**What goes wrong:**
CDM uses `CooldownViewerSettings:SetDisplayMode(mode)` to switch between its own built-in content panels (e.g., "spells", "auras"). If TBT attempts to call `SetDisplayMode("tbt")` or hook into this system to show TBT content, it will trigger an assertion in CDM's mode switching logic because `"tbt"` is not a recognized mode. CDM's tab system is designed for its own internal tabs.

**Why it happens:**
The natural instinct is to integrate with CDM's display switching to show/hide TBT content. The CDM source shows `SetDisplayMode` asserts on unknown mode strings.

**How to avoid:**
TBT manages its own content frame visibility. When the TBT tab button is selected, TBT shows its own content frame (parented to `CooldownViewerSettings`, not injected into CDM's display system). CDM's existing tabs are not modified — TBT's tab is purely additive.

**Warning signs:**
- Lua error: "Unknown mode" or assert failure in CDM code when TBT tab is clicked
- CDM built-in content (Spells, Auras panels) disappears when TBT tab is selected

**Phase to address:**
CDM tab integration phase — do not call `SetDisplayMode` with any TBT-specific mode string.

---

### Pitfall 3: Tab Button Must Be in the `TabButtons` `parentArray` — Requires XML

**What goes wrong:**
CDM's settings frame uses an XML `parentArray="TabButtons"` attribute to collect all tab button children into an array used by the tab selection logic. If TBT creates its tab button at runtime via `CreateFrame("Button", ...)` without the `parentArray` registration, the tab is not in the `TabButtons` array — `CooldownViewerSettings.TabButtons` will not include TBT's tab, so the "one tab selected at a time" logic will not deselect TBT's tab when another tab is chosen, and vice versa.

**Why it happens:**
Runtime `CreateFrame` cannot set `parentArray` — this is an XML-only attribute. Developers who avoid XML for simplicity miss this integration point.

**How to avoid:**
Define TBT's tab button in an XML file (e.g., `CDMTab.xml`) using `<Button parentArray="TabButtons" ...>`. This file must be included in the `.toc` and loaded before CDM settings is opened.

**Warning signs:**
- Multiple CDM tabs appear selected simultaneously
- Clicking away from TBT tab does not deselect it visually

**Phase to address:**
CDM tab integration phase — XML file and `.toc` entry must be added before writing any Lua tab logic.

---

### Pitfall 4: Edit Mode Registration Must Happen Before `EditModeManagerFrame:EnterEditMode`

**What goes wrong:**
`EditModeManagerFrameMixin:RegisterSystemFrame` simply appends to `self.registeredSystemFrames`. When Edit Mode is opened, `EnterEditMode` calls `secureexecuterange(self.registeredSystemFrames, callOnEditModeEnter)`. If TBT's frame calls `RegisterSystemFrame` after `EnterEditMode` has already run (e.g., because the user opened Edit Mode before TBT finished loading), TBT's frame will never receive `OnEditModeEnter` for that session.

Additionally, `EditModeSystemMixin:OnSystemLoad` calls `EditModeManagerFrame:RegisterSystemFrame(self)` — this only works if `EditModeManagerFrame` is already loaded. If CDM loads after TBT on some load order variation, this call hits nil.

**Why it happens:**
Addon load order is not guaranteed. TBT may complete loading before or after `Blizzard_EditMode` initializes `EditModeManagerFrame`.

**How to avoid:**
- In the XML template for TBT's Edit Mode frames, set `mixin="EditModeSystemMixin"` and include `<Scripts><OnLoad method="OnSystemLoad"/></Scripts>`. The `OnSystemLoad` method on `EditModeSystemMixin` is safe to call after the fact — it only fails if `EditModeManagerFrame` itself does not exist, which will not happen since it is a Blizzard frame.
- Also listen for `EditMode.Enter` via `EventRegistry` as a fallback to late-register or re-trigger setup.
- Do not attempt manual `RegisterSystemFrame` calls from Lua; rely on `OnSystemLoad` via the mixin.

**Warning signs:**
- TBT elements do not show selection handles in Edit Mode
- Dragging TBT elements in Edit Mode has no effect on position persistence

**Phase to address:**
Edit Mode integration phase. Test by entering Edit Mode before and after first login, and after `/reload`.

---

### Pitfall 5: Edit Mode Positions Stored Using Frame Name as Anchor Key

**What goes wrong:**
`ConvertToAnchorInfo` stores position as:
```lua
anchorInfo.relativeTo = relativeTo and relativeTo:GetName() or "UIParent";
```
If the TBT container frame has no name (created with `CreateFrame("Frame", nil, ...)`) the anchor stores `relativeTo = nil` which becomes `"UIParent"`. This is fine at first, but if TBT's frame is parented to a CDM viewer frame and that viewer has a globally unique name, anchoring to it works — however if the CDM viewer is ever recreated or nil on a reload, position restoration will fail silently (the frame will teleport to `UIParent`).

TBT currently creates `barContainer` and `iconContainer` as unnamed frames parented to CDM viewers. For Edit Mode, these must have global names so `GetName()` returns a stable, non-nil value.

**Why it happens:**
Developers create containers without names for encapsulation, not realising Edit Mode position serialization depends on `GetName()`.

**How to avoid:**
Give TBT's Edit Mode system frames stable global names (e.g., `"TBTBarContainer"`, `"TBTIconContainer"`). Parent them to `UIParent` for Edit Mode independence — decoupling from CDM viewers is a stated goal of this milestone. Anchoring to a CDM viewer frame will re-introduce the coupling that Edit Mode is meant to remove.

**Warning signs:**
- Position resets to UIParent default on every reload
- `/reload` loses position even after user saved via Edit Mode "Save Changes"

**Phase to address:**
Edit Mode integration phase. Name frames before writing any anchor persistence logic.

---

### Pitfall 6: Drag-and-Drop Cursor Frame Must Live at TOOLTIP Strata

**What goes wrong:**
Blizzard's drag cursor for CDM settings items uses:
```xml
<Frame name="CooldownViewerSettingsDraggedItemTemplate" frameStrata="TOOLTIP" ...>
```
If TBT's drag cursor frame is created at a lower strata (e.g., `HIGH` or `DIALOG`), it will render beneath the CDM settings window itself and appear invisible or partially clipped when dragging over the panel.

Additionally, the cursor frame must be parented to `GetAppropriateTopLevelParent()`, not to the CDM settings frame directly. Parenting to the CDM settings frame causes the cursor to be clipped by that frame's bounds and masked by its strata.

**Why it happens:**
Developers parent the cursor frame to the closest logical ancestor (the settings panel) and use a convenient strata like `DIALOG`. The Blizzard source is explicit that TOOLTIP strata + UIParent-level parent is the correct pattern.

**How to avoid:**
Use `frameStrata="TOOLTIP"` and parent to `GetAppropriateTopLevelParent()`. Set position via `GetScaledCursorPositionForFrame(topLevel)` in `OnUpdate`, exactly as `CooldownViewerSettingsDraggedItemMixin:OnUpdate` does.

**Warning signs:**
- Dragged icon is invisible or only visible outside the CDM settings window bounds
- Dragged icon renders behind the settings panel

**Phase to address:**
Drag-and-drop implementation phase.

---

### Pitfall 7: GLOBAL_MOUSE_UP Must Be Registered/Unregistered Per Drag Session

**What goes wrong:**
Blizzard's drag reorder system in CDM settings registers `GLOBAL_MOUSE_UP` at `BeginOrderChange` and unregisters at `EndOrderChange`/`CancelOrderChange`. If TBT registers `GLOBAL_MOUSE_UP` permanently (e.g., in `OnLoad`), it will fire on every mouse release across the entire UI — including clicks in chat, action bars, and other panels — causing spurious drag completion calls.

Conversely, if TBT never registers `GLOBAL_MOUSE_UP` and relies solely on `OnMouseUp` on the drop targets, the drag will fail to complete when the mouse is released over a non-TBT frame (which is the normal case during a drag).

**Why it happens:**
Developers either register the event too broadly or miss that `OnMouseUp` on individual frames only fires when the cursor is over that frame at release time.

**How to avoid:**
Mirror the CDM pattern exactly: register `GLOBAL_MOUSE_UP` on the settings frame at drag start, unregister at drag end. Use a single `OnUpdate` on the settings frame (not on each dragged item) to update cursor position.

**Warning signs:**
- Drag ends immediately when cursor leaves a buff item frame
- Drop targets register drops on random mouse releases unrelated to dragging

**Phase to address:**
Drag-and-drop implementation phase.

---

### Pitfall 8: Migration Must Not Overwrite Existing `trackedBuffs` Structure

**What goes wrong:**
The new milestone adds sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) and a display category per buff. If migration code overwrites or reinitialises `TerribleBuffTrackerDB.trackedBuffs` to add the `category` field, it may reset user-customised data (enabled/disabled state, custom labels) that was saved in v0.1.

A common mistake is checking `if not TerribleBuffTrackerDB` at the top of `ADDON_LOADED` and reinitialising the whole table — this silently nukes existing saves if the DB structure test is wrong.

**Why it happens:**
The `ADDON_LOADED` default initialisation block already exists in `Core.lua` and is easy to expand incorrectly. Adding a new top-level field check alongside the existing structure check is error-prone.

**How to avoid:**
Add a `schemaVersion` field to `TerribleBuffTrackerDB`. On load, if `schemaVersion` is absent or less than the current version, run a targeted migration: iterate existing `trackedBuffs`, add missing `category` fields with a default of `"trackedBuff"`, and set `schemaVersion`. Never wipe or reinitialise the whole table during migration.

**Warning signs:**
- All tracked buffs reset to defaults on first login after update
- User-configured enable/disable states are lost

**Phase to address:**
Data migration phase (should be the first phase of the milestone, before any UI work).

---

### Pitfall 9: Existing Display Anchors Break When Edit Mode Decouples Containers from CDM

**What goes wrong:**
`Display.lua` currently creates `barContainer` and `iconContainer` as children of CDM viewer frames:
```lua
barContainer = CreateFrame("Frame", nil, ns.cdmBarViewer)
barContainer:SetPoint("TOPLEFT", ns.cdmBarViewer, "BOTTOMLEFT")
```
When Edit Mode is added and these containers become independently movable (parented to `UIParent`), the existing `SnapshotSettings()` flow hooks CDM viewer layout events to re-anchor TBT bars. Those hooks will fire and attempt to reapply CDM-relative positions even though the containers are now UIParent-relative. The result is containers that teleport on CDM layout refresh.

**Why it happens:**
The Display.lua layout hooks were designed for a world where TBT anchors follow CDM. Edit Mode changes the fundamental assumption without removing the old hooks.

**How to avoid:**
When Edit Mode integration is added, audit every `HookViewerLayout` callback in `Display.lua`. Add a guard: if the container is in Edit-Mode-owned position (i.e., no longer CDM-relative), skip the CDM layout re-anchor. The CDM settings copy on fresh install (one-time) should still run but must be detected and skipped on subsequent loads.

**Warning signs:**
- Containers jump to CDM position on every CDM settings change after being moved in Edit Mode
- `SnapshotSettings` overwrites Edit Mode positions

**Phase to address:**
Edit Mode integration phase. Must be addressed before or during the phase that adds Edit Mode — not deferred.

---

### Pitfall 10: Removing ConfigUI.lua Without Updating the Slash Command

**What goes wrong:**
The `/tbt` slash command calls `ns:ToggleConfigUI()`. If `ConfigUI.lua` is removed or disabled without redirecting the slash command, players get a Lua error. If the CDM settings window is the replacement, the slash command should call `ShowUIPanel(CooldownViewerSettings)` or scroll/focus to the TBT tab.

Additionally, `UISpecialFrames` (Escape-to-close) registration in the old ConfigUI must be explicitly removed. If not removed, `UISpecialFrames` retains a reference to the destroyed/hidden frame and Escape key handling may error or silently fail for all UI panels.

**Why it happens:**
ConfigUI removal feels like a simple file deletion, but it has two integration points (slash command and UISpecialFrames) that are invisible during development and only surface in-game.

**How to avoid:**
Before removing ConfigUI.lua: (1) update the slash command handler in `Core.lua` to open CDM settings to the TBT tab, and (2) explicitly remove the ConfigUI frame from `UISpecialFrames` (or ensure the frame is never added if the file is excluded from the .toc).

**Warning signs:**
- `/tbt` produces "attempt to call nil value (field 'ToggleConfigUI')"
- Escape key stops working for all UI panels

**Phase to address:**
ConfigUI replacement phase (same phase as CDM tab integration).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `schemaVersion` field, just add new fields inline | Simpler migration code | Any future field addition risks collision with old field names; no way to detect already-migrated state | Never — schemaVersion is low cost, high safety |
| Parent drag cursor to CDM settings frame | Avoids `GetAppropriateTopLevelParent()` lookup | Cursor clips behind settings panel; invisible during drags | Never |
| Leave CDM layout hooks active after Edit Mode integration | Avoids conditional logic | Containers teleport on CDM refresh after user moves them | Never |
| Use `parentArray` trick without XML file | Avoids adding a .xml file to .toc | Tab not registered in `TabButtons`; mode switching breaks | Never — XML is required |
| Hardcode Edit Mode system enum value | Avoids investigating Enum namespace | Breaks on any Blizzard enum reshuffle | Acceptable only if protected by a nil check with graceful fallback |
| Skip `issecretvalue()` guard on aura spellId | Simpler aura scan loop | Lua error in every M+/PvP/encounter event, console spam, potential UI taint | Never |
| Use `PLAYER_REGEN_ENABLED` to clear aura block flag | Simple single-event reset | Block clears during M+ out-of-combat lulls; errors on next aura scan | Never — use zone change events |
| Full aura scan on every UNIT_AURA event | Simpler scan logic | CPU spike during large encounters; unnecessary work when only specific auras changed | Acceptable only as a temporary fallback behind an `isFullUpdate` guard |
| Skip `source = "meta"` on meta-tracker timers | Simpler timer creation | Aura scan calls `GetPlayerAuraBySpellID("trinket")` — type error or silent nil, timer cancelled immediately | Never |
| Call `GetInventoryItemID` without `InCombatLockdown()` guard | Simpler icon resolution | Lua error or secret value when CDM settings opened in combat | Never |
| Store nil from uncached `GetItemInfo` as the meta icon | Simpler error path | Question mark icon persists until reload; never resolves | Never — use `GET_ITEM_INFO_RECEIVED` |
| Use item ID or proc buff ID in cast detection allowlist | Matches Wowhead presentation | No casts ever match; meta-tracker never fires | Never — use the on-use ability spell ID from UNIT_SPELLCAST_SUCCEEDED |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CDM `SetupTabs` | Call `CooldownViewerSettings:SetDisplayMode("tbt")` to show TBT content | TBT tab shows/hides its own content frame; never injects into CDM's displayMode system |
| CDM tab `TabButtons` parentArray | Create tab with `CreateFrame` at runtime expecting auto-registration | Define tab in XML with `parentArray="TabButtons"` so it is populated during XML load |
| Edit Mode `OnSystemLoad` | Call `RegisterSystemFrame` manually from Lua after load | Use `mixin="EditModeSystemMixin"` in XML; `OnSystemLoad` calls `RegisterSystemFrame` at the right time |
| Drag cursor frame | Parent to settings panel at `HIGH` strata | Parent to `GetAppropriateTopLevelParent()` at `TOOLTIP` strata |
| `GLOBAL_MOUSE_UP` | Register permanently in `OnLoad` | Register only for the duration of a drag session |
| CDM data access | Access `CooldownViewerSettings:GetLayoutManager()` at `PLAYER_ENTERING_WORLD` | Gate behind `COOLDOWN_VIEWER_DATA_LOADED` |
| Edit Mode anchor serialization | Use unnamed (`nil`) frame names for containers | Give containers stable global names; `ConvertToAnchorInfo` uses `GetName()` |
| UNIT_AURA registration | `RegisterEvent("UNIT_AURA")` fires for all units | Use `RegisterUnitEvent("UNIT_AURA", "player")` to scope to player only |
| Aura secret value check | Compare `auraData.spellId` directly against tracked buff table | Guard with `issecretvalue(auraData.spellId)` before any comparison or table index |
| Aura cancellation on zone change | Cancel all timers when `isFullUpdate` fires after zone transition | Suppress cancellation during `PLAYER_ENTERING_WORLD` window; never cancel on `isFullUpdate` alone |
| Cast-to-aura ordering | Aura scan cancels timer immediately after `UNIT_SPELLCAST_SUCCEEDED` starts it | Grace period: skip cancellation for ~0.5s after cast succeeds |
| Aura block flag reset | Clear block on `PLAYER_REGEN_ENABLED` (combat drop) | Clear on `ZONE_CHANGED_NEW_AREA` or confirmed non-secret read; M+ is restricted out-of-combat too |
| Meta-tracker aura scan | Missing `source = "meta"` causes scan to call `GetPlayerAuraBySpellID` with string key | Set `source = "meta"`; add bypass branch in `ScanActiveTimersForCancellation` |
| Meta-tracker icon resolution | Call `GetInventoryItemID` in combat or without `issecretvalue()` guard | Gate behind `InCombatLockdown()`; wrap result in `issecretvalue()` check |
| Meta-tracker cast allowlist | Use item ID or proc buff spell ID instead of use-ability spell ID | Verify each spell ID in-game via `UNIT_SPELLCAST_SUCCEEDED` debug logging |
| Meta-tracker icon revert | Display uses stale spell icon after timer expiry | Render idle icon via `ns:GetMetaIdleIcon(key)` at display time, not at timer-creation time |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Running `SnapshotSettings()` inside CDM layout hooks after Edit Mode decouples containers | Containers teleport on every CDM change | Guard: skip CDM re-anchor if container is in Edit Mode position | Immediately after Edit Mode integration |
| `GLOBAL_MOUSE_UP` registered permanently | Drag completion fires on any mouse up across all UI | Register/unregister per drag session only | As soon as player clicks outside TBT UI during a drag |
| TBT tab `OnUpdate` running cursor tracking when no drag is active | Unnecessary work every frame | Set `OnUpdate` script only during drag; nil it at end | Low impact alone, but consistent with CDM's own pattern |
| Full aura scan on every `UNIT_AURA` event | CPU spike in raids; UNIT_AURA fires very frequently | Use `removedAuraInstanceIDs` for targeted removal; full scan only on `isFullUpdate` | Large group content with many buff changes per second |
| UNIT_AURA scanning non-hidden tracked buffs with no active timer | Extra iteration over entries that cannot produce a cancellation | Filter scan to `ns.activeTimers[spellID] ~= nil` first | Low cost per event but accumulates at high fire rate |
| Bag scan triggered by `UNIT_INVENTORY_CHANGED` during combat | Scan runs every time consumable is used; redundant during active timer | Gate bag scan on `PLAYER_REGEN_ENABLED` only; never in combat | Any combat with potion use |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| New buffs added via Suggested section land directly in a visible section | Users see unexpected bars/icons appear immediately | New buffs land in "Not Displayed" first; user explicitly promotes to Tracked Buffs or Tracked Bars |
| CDM settings copy runs on every login instead of once | User's manual CDM position overrides are reset each session | Set a `cdmSettingsCopied` flag in DB after first copy; skip on subsequent loads |
| TBT tab does not restore the previously selected CDM tab (Spells vs. Auras) when dismissed | Disorienting for users who were on the Spells tab | Cache `CooldownViewerSettings.displayMode` before showing TBT tab; restore it when TBT tab is deselected |
| Delete drop zone always visible | Clutters the UI for users not in a drag session | Only show delete zone when a drag is active |
| Aura cancellation silently removes timers without any feedback | User notices timers disappear but does not know why | This is intentional correct behavior; no feedback needed unless debug mode is active |
| Meta-tracker idle icon shows question mark or wrong spell after timer expiry | User confused by icon changing after buff ends | Resolve idle icon from `ns.metaIcons[key]` cache at render time; cache populated out of combat |
| Meta-tracker slot shows previous trinket's icon after trinket swap | Stale cached icon from pre-swap equipped item | Register `UNIT_INVENTORY_CHANGED`; refresh icon cache out of combat (defer to `PLAYER_REGEN_ENABLED` if in combat) |

---

## "Looks Done But Isn't" Checklist

- [ ] **CDM tab button:** Tab appears in the settings window AND clicking it shows TBT content AND deselecting it restores CDM scroll content AND `SetChecked` state matches selection — verify all four
- [ ] **Edit Mode elements:** Frames appear with selection handles AND dragging saves position AND `/reload` restores position AND "Reset Position" button works — verify all four
- [ ] **Drag-and-drop:** Drag picks up item AND cursor icon follows mouse across entire screen (not just within settings panel) AND dropping in a section updates the category AND cancelling (Escape/drop outside) restores original state — verify all
- [ ] **Migration:** Fresh install with no DB works AND existing v0.1 DB with tracked buffs is preserved AND all enabled/disabled states survive — verify all three scenarios
- [ ] **ConfigUI removal:** `/tbt` opens CDM to TBT tab AND Escape still closes UI panels AND no Lua error on `/tbt` — verify all three
- [ ] **CDM settings one-time copy:** Runs on fresh install AND does not run on second login AND does not run after user manually changes CDM settings — verify all three
- [ ] **Aura cancellation (v0.2.1):** Timers cancel correctly when buff expires early in open world AND no Lua errors occur in M+/PvP/encounter AND no timers cancelled during zone transitions AND cast grace period prevents immediate cancellation AND block flag correctly stays set for entire M+ key duration — verify all five
- [ ] **Meta-tracker source marker (v0.3.0):** Trinket and pot timers have `source = "meta"` AND aura scan does not cancel them AND no Lua errors from `GetPlayerAuraBySpellID` with string argument — verify in M+
- [ ] **Meta-tracker icon gate (v0.3.0):** `GetInventoryItemID` never called in combat AND no Lua errors when CDM settings opened in combat — verify with combat logging
- [ ] **Meta-tracker icon revert (v0.3.0):** After timer expiry, slot shows equipped item icon (not spell icon, not question mark) — verify by waiting for timer expiry with trinket equipped

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| COOLDOWN_VIEWER_DATA_LOADED timing missed | LOW | Add event listener; test with `/reload` in loaded game |
| Tab not in `TabButtons` array | MEDIUM | Restructure to use XML-defined tab; requires adding .xml file and .toc entry |
| Edit Mode positions lost on reload | MEDIUM | Add global frame names; re-test position persistence |
| Migration wiped user data | HIGH | No automated recovery; document in changelog; advise users to re-add tracked buffs |
| Slash command broken after ConfigUI removal | LOW | Re-wire `ns.ToggleConfigUI` to open CDM settings; 5-line fix |
| Drag cursor invisible | LOW | Change parent to `GetAppropriateTopLevelParent()` and strata to `TOOLTIP`; immediate fix |
| Lua error on aura spellId comparison in M+ | LOW | Add `issecretvalue()` guard before comparison; 2-line fix per comparison site |
| Timers cancelled on every zone transition | MEDIUM | Wrap `isFullUpdate` cancellation in `PLAYER_ENTERING_WORLD` suppression window; requires careful event ordering |
| Block flag clears mid-M+ causing errors | LOW | Replace `PLAYER_REGEN_ENABLED` reset trigger with `ZONE_CHANGED_NEW_AREA`; 2-line change |
| Timer disappears immediately after cast | LOW | Add grace period flag on `ns.recentlyCast[spellID]`; 5-line addition |
| Meta-timer cancelled immediately by aura scan | LOW | Add `source = "meta"` to timer creation and bypass branch in scan; 3-line fix |
| Lua error from inventory query in combat | LOW | Wrap `GetInventoryItemID` in `InCombatLockdown()` guard; 2-line fix |
| Question mark icon on uncached item | LOW | Add `GET_ITEM_INFO_RECEIVED` handler and retry logic; 10-line addition |
| Wrong pot icon from unordered bag scan | LOW | Reorder bag scan to use priority list; 5-line refactor |
| Stale icon after trinket swap | LOW | Register `UNIT_INVENTORY_CHANGED` and set pending refresh flag; 5-line addition |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CDM data not ready at load time | Phase 1: CDM tab integration | Test tab interaction before and after `COOLDOWN_VIEWER_DATA_LOADED` fires |
| Tab not in `TabButtons` parentArray | Phase 1: CDM tab integration | Confirm tab receives `SetChecked` state changes when other tabs are selected |
| `SetDisplayMode` asserts on unknown mode | Phase 1: CDM tab integration | Confirm TBT never calls `SetDisplayMode` with a non-CDM mode string |
| Edit Mode registration timing | Phase 2: Edit Mode integration | Enter Edit Mode before and after `/reload`; verify selection handles appear |
| Edit Mode anchor serialization (unnamed frames) | Phase 2: Edit Mode integration | Verify `GetName()` returns stable value; check `ConvertToAnchorInfo` output |
| CDM layout hooks conflicting with Edit Mode | Phase 2: Edit Mode integration | Move TBT container in Edit Mode, trigger CDM layout, confirm container does not teleport |
| Drag cursor strata and parent | Phase 3: Drag-and-drop | Drag item across entire screen including over non-TBT frames; cursor visible throughout |
| GLOBAL_MOUSE_UP scope | Phase 3: Drag-and-drop | Click chat, action bars during a drag; confirm spurious drops do not fire |
| Migration data integrity | Phase 0: Data migration (first) | Test with v0.1 DB snapshot; verify all fields preserved |
| ConfigUI removal side effects | Phase 1: CDM tab integration | Verify `/tbt`, Escape key, and no Lua errors after removal |
| Secret value Lua error on aura spellId | v0.2.1 Phase 1: Event registration + scan core | Test in M+ or PvP content; verify no Lua errors in chat |
| False cancellation on zone change | v0.2.1 Phase 1: Cancellation logic | Cast a buff, enter instance, confirm timer persists through loading screen |
| Cast-to-aura race condition | v0.2.1 Phase 1: Cancellation logic | Cast tracked spell, confirm timer persists for full duration |
| Block flag reset with wrong event | v0.2.1 Phase 1: Block flag logic | Test M+ key active out-of-combat; confirm block stays set |
| Full scan performance | v0.2.1 Phase 1: Scan optimization | Profile in 25+ player raid; confirm no frame time spike on aura changes |
| Aura instance ID cache stale after isFullUpdate | v0.2.1 Phase 1: Instance ID cache | Zone change, confirm reverse map is rebuilt cleanly |
| String key collision (`"trinket"`, `"pot"`) | v0.3.0 Phase 1: Schema migration | Inspect DB before and after update; verify clean key state |
| Missing `source = "meta"` on meta-timer | v0.3.0 Phase 2: Timer creation | Cast trinket in M+; confirm timer persists through next aura scan event |
| `GetInventoryItemID` in combat | v0.3.0 Phase 3: Icon resolution | Open CDM settings during combat; confirm no Lua errors |
| Uncached item nil icon | v0.3.0 Phase 3: Icon resolution | Equip brand-new trinket; confirm icon appears without reload |
| Bag scan finds wrong pot | v0.3.0 Phase 3: Icon resolution | Load multiple pot types in bags; confirm highest-priority pot icon shown |
| Timer overwrites longer-running expiry | v0.3.0 Phase 2: Timer creation | Cast two different-duration trinkets via macro; confirm longest timer shown |
| Idle icon not reverted after expiry | v0.3.0 Phase 4: Display integration | Wait for timer to expire; confirm item icon shown (not spell icon) |

---
*Pitfalls research for: WoW addon CDM tab integration, Edit Mode movable elements, drag-and-drop, aura-based timer cancellation (v0.2.1), trinket/pot meta-trackers (v0.3.0)*
*Last updated: 2026-04-11*
