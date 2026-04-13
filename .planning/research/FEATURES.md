# Feature Research: Trinket & Pot Meta-Trackers

**Domain:** WoW addon — shared-slot cooldown meta-trackers with dynamic icon resolution
**Researched:** 2026-04-11
**Milestone:** v0.3.0
**Confidence:** HIGH (lust pattern already proven; APIs verified in Midnight docs)

---

## Context and Constraints

This milestone adds two meta-tracker slots to the Suggested section, following the lust pattern
(string key, shared-slot overwrite, `metaBuff = true`). The core mechanics are already validated:

- `UNIT_SPELLCAST_SUCCEEDED` fires reliably for player casts with a non-secret spellID
- `GetTime()` + known duration drives timers; no aura data needed during tracking
- String-keyed entries (`"lust"`, now `"trinket"` / `"pot"`) hold one timer across all member spellIDs
- `StartLustTimer` pattern: look up entry by string key, overwrite existing timer unconditionally

**New constraint:** At-rest icon (no timer active) must reflect the currently equipped trinket or
currently held damage pot, not a hardcoded spell icon. Icon must be scanned from equipped gear or
bags. Scan is safe only out-of-combat (`C_Container.GetContainerItemInfo` and
`GetInventoryItemTexture` return honest values out of combat; their status in combat under Midnight
is unknown and should be treated as suspect per CLAUDE.md guidance).

**Known-safe APIs (MEDIUM confidence — verified via Warcraft Wiki; Midnight status not explicitly
restricted in patch notes):**
- `GetInventoryItemTexture("player", slotID)` — returns fileID of equipped item icon; slot 13 =
  Trinket1, slot 14 = Trinket2
- `GetInventoryItemID("player", slotID)` — returns itemID of equipped item
- `C_Container.GetContainerItemInfo(bagID, slotIndex)` — returns table with `iconFileID`,
  `itemID`; bagIDs 0–4 for main bags
- `C_Item.GetItemIconByID(itemID)` — returns fileID from item cache; requires item to have been
  seen in session

---

## Table Stakes

Features users expect. Missing these makes the milestone feel incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Trinket meta-tracker in Suggested section | Users expect TBT to cover the trinket on-use cooldown like it covers lust | LOW | Follows lust pattern exactly: string key `"trinket"`, `metaBuff = true`, shared-slot overwrite |
| Damage pot meta-tracker in Suggested section | Combat potion is always a shared-slot item; tracking it alongside lust and trinket is the complete raid toolkit | LOW | Same pattern: key `"pot"`, all season damage pot spellIDs in a lookup table |
| Shared-slot overwrite (newest cast wins) | Trinkets and pots share a slot — players swap trinkets and still use pots mid-pull; old timer must not persist | LOW | `ns.activeTimers["trinket"] = newTimer` unconditionally on any member spellID cast, identical to `StartLustTimer`'s non-restart-guard removal |
| At-rest icon shows the equipped trinket icon | A generic sword icon while no trinket timer is active would confuse users about which trinket is tracked | MEDIUM | Scan `GetInventoryItemTexture("player", 13)` and slot 14; if no scan result yet, fall back to question mark. Resolved icon stored in SUGGESTED_BUFFS definition |
| At-rest icon shows the bag-held damage pot icon | Players swap pots between pulls; static hardcoded icon becomes wrong after loot | MEDIUM | Scan bags 0–4 via `C_Container.GetContainerItemInfo`; match `itemID` against known pot item IDs; store first match icon |
| Active timer icon shows the specific cast spell | When the trinket or pot is actively cooling down, the icon should reflect the actual proc spell, not the item | LOW | Same as lust: `icon = ns:GetSpellIcon(spellID)` in the timer table, where `spellID` is the member spell that fired |
| Active icon reverts to resolved at-rest icon on expiry | After timer expires, icon returns to equipped trinket / held pot icon | LOW | Timer cleanup already wipes `ns.activeTimers["trinket"]`; display reads from the resolved icon stored in the SUGGESTED_BUFFS definition |
| Scan triggers on CDM settings open, out-of-combat | Users open settings to configure — this is the natural safe moment to refresh which trinket is equipped | LOW | Hook into existing CDM tab open handler; gate on `not InCombatLockdown()`; update resolved icon in `ns.SUGGESTED_BUFFS` entry |

---

## Differentiators

Features that improve correctness or UX beyond the baseline.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Scan both trinket slots, use non-nil result | Player may have only one on-use trinket; scanning both slots ensures the icon doesn't silently stay nil | LOW | Check slot 13 first, then 14; first non-nil with a known member spellID wins, otherwise fall back to first non-nil equipped trinket icon regardless |
| Detect trinket swap via PLAYER_EQUIPMENT_CHANGED | Trinket is swapped between pulls; icon should refresh without requiring CDM open | LOW | Register `PLAYER_EQUIPMENT_CHANGED` in Core.lua; call icon-refresh function when `slotID == 13 or slotID == 14` |
| Detect bag change via BAG_UPDATE_DELAYED | Pot count changes as player picks up consumables mid-raid; icon should stay current | LOW | Register `BAG_UPDATE_DELAYED`; trigger pot scan out of combat |
| Nil-safe icon fallback at display time | If resolved icon is nil (scan hasn't run yet, or no eligible item found), display renders question mark rather than erroring | LOW | `ns:GetSpellIcon` already returns 134400 for nil; apply same guard to resolved item icons |
| getCDMSpellID for CDM icon uses equipped trinket's active spell | CDM Suggested section icon should show what the active spell looks like, not the item | LOW | `getCDMSpellID` in the SUGGESTED_BUFFS entry returns a representative spell from the TRINKET_SPELLS map based on currently equipped item |
| Preview timer uses resolved icon | Preview mode should show realistic icon, not question mark | LOW | `StartAllPreviewTimers` already calls `ResolveSuggestedSpellID`; also expose `resolvedIcon` field on SUGGESTED_BUFFS entries for preview path |

---

## Anti-Features

Features to explicitly not build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Aura-based cancellation for trinket/pot timers | Trinket procs and potions are combat-only; aura fields are secret in combat — same constraint that blocked this for lust | Timer runs to natural expiry; the fixed duration approach is already validated for lust |
| Scanning bags in combat | `C_Container.GetContainerItemInfo` is unverified as secret-safe in combat; CLAUDE.md mandates fail-safe usage of suspect APIs | Gate all bag/inventory scans on `not InCombatLockdown()` |
| Per-spellID individual timer entries for trinket members | If each trinket spell gets its own DB entry, users see a grid of trinket icons in Not Displayed rather than one shared slot | Use one string-keyed entry (`"trinket"`) with a membership lookup table, identical to lust |
| Auto-discovering which trinket spells exist this season | Scope creep; item → spell relationships must be manually curated and updated each patch | Maintain `TRINKET_SPELLS` and `POT_SPELLS` static tables in BuffEngine.lua |
| User-editable duration per member spell | Trinket and pot durations are fixed per spell; user editing creates error surface and UI complexity | Hardcode durations in the member spell tables; one duration per entry |
| Tracking healing pots, utility pots, or flasks | Out of scope per PROJECT.md; distinct cooldown categories, not damage optimization | Only damage pots share the combat-potion slot relevant to DPS meta |
| Scanning bank or reagent bank for pot icons | Player can't use bank items in combat; icon from bank is misleading | Scan bags 0–4 only |

---

## Feature Dependencies

```
Trinket meta-tracker timer (StartTrinketTimer)
  └── requires ── SUGGESTED_BUFFS["trinket"] entry in BuffEngine.lua
        └── requires ── TRINKET_SPELLS lookup table (spellID → {itemID, duration})

Pot meta-tracker timer (StartPotTimer)
  └── requires ── SUGGESTED_BUFFS["pot"] entry in BuffEngine.lua
        └── requires ── POT_SPELLS lookup table (spellID → duration)

Dynamic icon resolution (ResolveTrinketIcon, ResolvePotIcon)
  └── requires ── scan triggers (CDM open, PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE_DELAYED)
  └── requires ── resolved icon stored on SUGGESTED_BUFFS entry (new field: resolvedIcon)

Active timer icon (icon field on ns.activeTimers["trinket"])
  └── requires ── StartTrinketTimer sets icon = ns:GetSpellIcon(castSpellID)
  └── reverts via ── display reads resolvedIcon from SUGGESTED_BUFFS when timer absent

Shared-slot overwrite
  └── requires ── OnSpellCastSucceeded routes TRINKET_SPELLS member to StartTrinketTimer
  └── enhancement of ── existing activeTimers["trinket"] = newTimer pattern (no guard check)

Existing lust pattern (dependency, already built)
  └── StartLustTimer → StartTrinketTimer / StartPotTimer are direct analogs
  └── SUGGESTED_BUFFS registry → extend with two new entries
  └── ResolveSuggestedSpellID → extend to handle "trinket" and "pot" keys with resolvedIcon
```

**Dependency on existing lust implementation:**
- `ns.SUGGESTED_BUFFS` registry is the correct extension point; trinket and pot entries follow the
  same `{ key, label, duration, metaBuff, getCDMSpellID }` shape
- `StartLustTimer` is the direct behavioral model; `StartTrinketTimer` and `StartPotTimer` are
  structurally identical except: (a) no `lustBuffID` on the timer (no aura-based cancellation),
  (b) no restart-guard (overwrite is always allowed for shared-slot semantics)
- `OnSpellCastSucceeded` routing: currently only checks `ns.db.trackedBuffs[spellID]`; trinket/pot
  member spells are NOT in the DB, so routing must check TRINKET_SPELLS and POT_SPELLS tables
  first, before the DB lookup, similar to how lust detection bypasses the DB via UNIT_AURA

---

## MVP Definition

### Launch With (v0.3.0)

- [ ] `TRINKET_SPELLS` lookup table with 9 season trinkets (spellID → {itemID, duration})
- [ ] `POT_SPELLS` lookup table with 4 damage pots (spellID → duration)
- [ ] SUGGESTED_BUFFS entries for `"trinket"` and `"pot"` (key, label, duration, metaBuff,
      getCDMSpellID, resolvedIcon field)
- [ ] `StartTrinketTimer(spellID)` and `StartPotTimer(spellID)` functions in BuffEngine.lua
- [ ] `OnSpellCastSucceeded` routing: check TRINKET_SPELLS and POT_SPELLS before DB lookup
- [ ] `ResolveTrinketIcon()` and `ResolvePotIcon()` — scan equipped slots / bags, return fileID
- [ ] Scan trigger: CDM tab open, gated on `not InCombatLockdown()`
- [ ] Active timer icon = cast spell icon; reverts to resolvedIcon on expiry (display already does
      this since it reads from timer.icon while active)

### Add After Validation (v0.3.x)

- [ ] `PLAYER_EQUIPMENT_CHANGED` hook for trinket icon refresh — trigger when player frequently
      swaps trinkets mid-raid
- [ ] `BAG_UPDATE_DELAYED` hook for pot icon refresh — if players report stale pot icons

### Future Consideration (v1+)

- [ ] Aura-based early cancellation for trinket/pot if Blizzard whitelists those spellIDs — same
      pattern as lust debuff detection but requires spellIDs to be non-secret in combat
- [ ] Item-based duration lookup (query `C_Item` at setup time) rather than hardcoded table, if
      item data becomes reliably accessible

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Trinket meta-tracker timer | HIGH | LOW (lust pattern exists) | P1 |
| Pot meta-tracker timer | HIGH | LOW (same pattern) | P1 |
| Shared-slot overwrite | HIGH | LOW (remove restart guard) | P1 |
| Active icon = cast spell | MEDIUM | LOW (already done in lust) | P1 |
| At-rest icon from equipped trinket | MEDIUM | MEDIUM (new scan code) | P1 |
| At-rest icon from bag pot | MEDIUM | MEDIUM (bag scan) | P1 |
| Revert icon on expiry | MEDIUM | LOW (display reads resolvedIcon) | P1 |
| PLAYER_EQUIPMENT_CHANGED hook | LOW | LOW | P2 |
| BAG_UPDATE_DELAYED hook | LOW | LOW | P2 |

---

## Competitor Feature Analysis

| Feature | TrinketTracker (Midnight) | Potion Tracker | TBT v0.3.0 Approach |
|---------|--------------------------|----------------|----------------------|
| Equipped trinket detection | Auto-detects slots 13/14 at startup | N/A | Scan on CDM open + equipment change |
| On-use spell tracking | Reads cooldown info from slot | Tracks by spellID | UNIT_SPELLCAST_SUCCEEDED + known duration |
| In-combat behavior | Caches out-of-combat, avoids secret APIs | Unknown | Same: all scans gated on out-of-combat |
| Shared slot semantics | N/A (separate bar per trinket) | Single slot | Single string-keyed entry, overwrite |
| CDM integration | Standalone display, not CDM-integrated | Standalone | CDM Suggested section, drag-to-section |
| Active vs at-rest icon distinction | Not observed | Not observed | Active = cast spell; at-rest = item icon |

TBT's differentiator is CDM integration and the unified Suggested-section UX. The shared-slot
overwrite pattern is a deliberate design choice competitors don't implement because they track per
item, not per slot.

---

## Icon Resolution Technical Notes

**Trinket icon scan (out of combat only):**
```lua
-- Slot 13 = Trinket0Slot, Slot 14 = Trinket1Slot
local itemID1 = GetInventoryItemID("player", 13)
local itemID2 = GetInventoryItemID("player", 14)
-- Match against TRINKET_ITEM_IDS set; first match wins for getCDMSpellID
-- Fall back to GetInventoryItemTexture("player", 13) for raw icon if no match
local icon = GetInventoryItemTexture("player", 13) or GetInventoryItemTexture("player", 14)
```

**Pot icon scan (out of combat only):**
```lua
-- Scan bags 0-4; match itemID against POT_ITEM_IDS set
for bag = 0, 4 do
  for slot = 1, C_Container.GetContainerNumSlots(bag) do
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info and POT_ITEM_IDS[info.itemID] then
      return info.iconFileID
    end
  end
end
```

**Confidence:** MEDIUM. `GetInventoryItemID` and `GetInventoryItemTexture` are documented as available in Midnight 12.0.1 (not listed as restricted in patch 12.0.0 API changes). `C_Container.GetContainerItemInfo` is documented and returns `iconFileID`; no Midnight-specific restriction found. All calls must be guarded by `not InCombatLockdown()` per CLAUDE.md fail-safe guidance.

---

## Confidence Assessment

| Claim | Confidence | Source |
|-------|------------|--------|
| UNIT_SPELLCAST_SUCCEEDED spellID is always non-secret | HIGH | CLAUDE.md validated constraint; existing lust/cast tracking |
| String-keyed shared-slot timer pattern works | HIGH | Lust implementation (v0.2.1, in production) |
| `GetInventoryItemID("player", 13/14)` available in Midnight | MEDIUM | Warcraft Wiki (not restricted in 12.0.0 API changes page) |
| `GetInventoryItemTexture("player", slotID)` available in Midnight | MEDIUM | Warcraft Wiki; listed as supporting version 12.0.1 |
| `C_Container.GetContainerItemInfo` returns honest values out of combat | MEDIUM | Warcraft Wiki; Midnight restrictions appear combat-focused |
| `InCombatLockdown()` is correct gate for scan safety | HIGH | Standard WoW addon pattern; CLAUDE.md constraint |
| Trinket slots are 13 and 14 | HIGH | Warcraft Wiki InventorySlotID; GetInventorySlotInfo("Trinket0Slot"/"Trinket1Slot") |
| StartTrinketTimer needs no restart guard (overwrite semantics) | HIGH | Explicit requirement from milestone context; unlike lust which guards against restart |

---

## Sources

- [C_Container.GetContainerItemInfo — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerItemInfo)
- [GetInventoryItemID — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetInventoryItemID)
- [GetInventoryItemTexture — Wowpedia](https://wowpedia.fandom.com/wiki/API_GetInventoryItemTexture)
- [InventorySlotID — Warcraft Wiki](https://warcraft.wiki.gg/wiki/InventorySlotID)
- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [TrinketTracker (Midnight) — CurseForge](https://www.curseforge.com/wow/addons/trinkettracker-midnight)
- [Potion Tracker — CurseForge](https://www.curseforge.com/wow/addons/potion-tracker)
- Blizzard UI Source (local): `CooldownViewerItemData.lua` — `GetSpellTexture` icon resolution chain
- Blizzard UI Source (local): `CooldownViewerSettings.lua` — `GetTextureFileID` usage
- Existing TBT implementation: `BuffEngine.lua` — lust pattern (StartLustTimer, SUGGESTED_BUFFS, SATED_DEBUFF_TO_LUST)

---

*Supersedes: v0.2.1 feature research (aura-based timer cancellation)*
*Researched: 2026-04-11 for milestone v0.3.0*
