# Phase 14: Icon Resolution + Caching - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire at-rest CDM and display icons for trinket/pot meta-slots to the player's actual equipped trinkets and bag consumables. Scan happens only when the player will see the result (CDM-related open events), not on equipment/bag change events. Scope includes fixing the current Bars/Buffs at-rest rendering which falls back to the wrong icon.

</domain>

<decisions>
## Implementation Decisions

### Cache and scan timing
- **D-01:** Cache shape — `ns.metaIcons = { trinket = textureID_or_nil, pot = textureID_or_nil }`. Module-level table, not persisted.
- **D-02:** Eager simple cache — Display/CDMTab only READ from `ns.metaIcons`, never scan inline. All scanning happens in one place (refresh function).
- **D-03:** Refresh trigger is piggy-backed onto the existing `StartPreview` code path in CDMTab.lua. This is the only refresh point — no event hooks on `PLAYER_EQUIPMENT_CHANGED` or `BAG_UPDATE_DELAYED`.
- **D-04:** ICON-06 (refresh on PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED) is dropped as N/A — player only sees CDM preview when settings open, refreshing otherwise wastes work. Update REQUIREMENTS.md traceability to mark ICON-06 N/A with rationale.

### Scanning logic
- **D-05:** Trinket scan — call `GetInventoryItemID("player", INVSLOT_TRINKET1)` and `INVSLOT_TRINKET2`; if either matches an itemID in `ns.TRINKET_ITEM_IDS`, resolve via `C_Item.GetItemIconByID(itemID)`. First match wins (slot 13 before slot 14).
- **D-06:** Pot scan — iterate `ns.POT_ITEM_IDS` and call `C_Item.GetItemCount(itemID)`; first itemID with count > 0 is the match. Resolve icon via `C_Item.GetItemIconByID(itemID)`.
- **D-07:** InCombatLockdown() guard — if in combat, skip scan entirely and leave `ns.metaIcons` as-is (stale values or nil). Never blank the cache because of combat gating.
- **D-08:** Fallback ordering when nothing equipped / in bags — iterate the CSV list (TRINKET_SPELLS / POT_SPELLS in insertion order) and pick the first itemID whose `C_Item.GetItemIconByID` returns a non-nil texture. If none resolve, cache stays nil and display falls back to 134400 (?-icon).
- **D-09:** Uncached icon handling — if `C_Item.GetItemIconByID` returns nil for the chosen itemID (equipped or fallback), do NOT recurse to next list entry. Store nil in cache; display resolves to 134400. This keeps the fallback behavior simple and matches user preference ("fallback should be ?-icon, not Bloodlust").

### Display integration
- **D-10:** Add new helper `ns:GetAtRestMetaIcon(key)` — returns `ns.metaIcons[key] or 134400`. Single lookup used by both Display (Bars/Buffs paths) and CDMTab (Suggested section via `getCDMIcon` field).
- **D-11:** Wire `SUGGESTED_BUFFS[trinket|pot].getCDMIcon = function() return ns:GetAtRestMetaIcon(key) end`. Existing CDMTab nil-fallback from Phase 12 then picks up the real icon.
- **D-12:** Fix Bars/Buffs render (Display.lua) — in the placeholder path (lines ~444-457 bar, ~596-603 icon), detect meta-slot entries (`type(slot.spellID) == "string"` with matching SUGGESTED_BUFFS entry) and call `ns:GetAtRestMetaIcon(slot.spellID)` instead of the current `GetSpellIcon(ResolveSuggestedSpellID(...))` chain that produces the Bloodlust fallback for trinket/pot.
- **D-13:** Lust path preserved — lust continues to use `ResolveSuggestedSpellID` + `GetSpellIcon` (class-aware Bloodlust variant). Meta-slot fix is gated on `getCDMIcon ~= nil` on the SUGGESTED_BUFFS entry.

### Hook point
- **D-14:** Call `ns:RefreshMetaIcons()` at the start of `StartPreview` in CDMTab.lua (before `StartAllPreviewTimers`). Single call site per decision. Covers ICON-05.

### Claude's Discretion
- Naming: `RefreshMetaIcons` vs `ResolveMetaIcons` vs `ScanMetaIcons`
- Helper function placement (BuffEngine.lua module-level alongside existing helpers)
- Whether to split trinket/pot resolution into separate functions or fold into one

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase artifacts
- `.planning/phases/12-schema-migration-data-tables/12-CONTEXT.md` — SUGGESTED_BUFFS design, getCDMIcon placeholder
- `.planning/phases/12-schema-migration-data-tables/12-02-SUMMARY.md` — CDMTab nil fallback already in place
- `.planning/phases/13-timer-functions-cast-detection/13-CONTEXT.md` — metaSlot pattern
- `.planning/research/SUMMARY.md` — API verification (GetInventoryItemID, C_Item.GetItemCount/GetItemIconByID)
- `.planning/research/STACK.md` — inventory APIs not secret-restricted
- `.planning/research/PITFALLS.md` — InCombatLockdown gate, nil icon from uncached items

### Existing code
- `BuffEngine.lua` lines 85-146 — TRINKET_SPELLS, POT_SPELLS, TRINKET_ITEM_IDS, POT_ITEM_IDS, SUGGESTED_BUFFS with `getCDMIcon = nil` placeholders
- `BuffEngine.lua` lines 202-225 — GetSpellIcon, ResolveSuggestedSpellID helpers
- `CDMTab.lua` line 1085 — StartPreview function (hook point for D-14)
- `CDMTab.lua` lines 723-730 — Suggested render nil-safe fallback (Phase 12) — already calls getCDMIcon
- `Display.lua` lines 440-458 — Bar placeholder path (to fix per D-12)
- `Display.lua` lines 596-603 — Icon placeholder path (to fix per D-12)

### WoW API (verified)
- `GetInventoryItemID("player", INVSLOT_TRINKET1|INVSLOT_TRINKET2)` — equipped trinket itemID
- `C_Item.GetItemCount(itemID)` — bag presence check, returns number
- `C_Item.GetItemIconByID(itemID)` — returns textureID or nil for uncached
- `InCombatLockdown()` — combat gate

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns.TRINKET_ITEM_IDS`, `ns.POT_ITEM_IDS` — derived sets ready for scan
- `ns.TRINKET_SPELLS`, `ns.POT_SPELLS` — ordered iteration via `pairs` (Lua doesn't guarantee order; may need to iterate by spell table keys in insertion order if fallback priority matters)
- `ns:GetSpellIcon(spellID)` — 134400 fallback pattern to mirror
- CDMTab Phase 12 nil-fallback — already calls `getCDMIcon` when spellID path returns nil

### Established Patterns
- Module-level tables wiped or nil'd for reusability
- `issecretvalue` guards when touching secret-risk APIs (not applicable here per research, but keep InCombatLockdown gate)
- Single-call-site refresh (StartPreview)

### Integration Points
- `StartPreview` in CDMTab.lua — insertion point for RefreshMetaIcons call
- `SUGGESTED_BUFFS[].getCDMIcon` field — currently nil, Phase 14 fills it
- Display.lua placeholder paths — currently produce ?-icon via `GetSpellIcon("trinket")` returning 134400 (user reported as Bloodlust earlier — possibly stale cache from previous lust in that slot, but regardless we route to GetAtRestMetaIcon)

</code_context>

<specifics>
## Specific Ideas

- "No point in updating on every equipment change when the player is not going to see the preview" — user rationale for dropping ICON-06
- "The questionmark icon should be our fallback (not the Bloodlust one we have right now)" — explicit fallback requirement
- Reuse the existing CDM preview trigger; don't add event registrations

</specifics>

<deferred>
## Deferred Ideas

- Async icon retry (GET_ITEM_INFO_RECEIVED) — explicitly deferred to future per REQUIREMENTS.md Future Requirements ICON-08
- Active timer icon switching (ICON-03, ICON-04) — Phase 15 scope
- Refreshing on equipment/bag change events — dropped as N/A (D-04)
- Data storage rework milestone — still noted for future

</deferred>

---

*Phase: 14-icon-resolution-caching*
*Context gathered: 2026-04-13*
