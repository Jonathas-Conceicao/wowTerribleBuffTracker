# Phase 20: GetDisplayInfo + Dispatch Helper - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Collapse the provider display-info contract from two methods (`GetPreviewInfo` + `GetAtRestInfo`) into a single unified method (`GetDisplayInfo`), export a namespace-level dispatch helper (`ns:GetDisplayInfoForKey`) that routes a provider key to the right provider via type dispatch, and pull PROV-F3 scope forward — migrating the at-rest icon cache and refresh logic out of BuffEngine into each meta-provider via a new `RefreshAtRest()` method.

**In scope:**
- Collapse base mixin contract: `GetPreviewInfo(key)` + `GetAtRestInfo(key)` → single `GetDisplayInfo(key) → { icon, label, duration, spellID }`
- Add `SpellProviderBaseMixin:RefreshAtRest()` with no-op default
- Implement `GetDisplayInfo` on all 4 providers with REAL durations (fixes trinket/pot 0-second preview bug)
- Export `ns:GetDisplayInfoForKey(key)` in Providers.lua using local `keyToProvider` lookup table
- Move at-rest cache from `ns.metaAtRest` (BuffEngine) into TrinketProvider/PotProvider instance state
- Move inventory-scan logic out of `ns:RefreshMetaIcons` into TrinketProvider:RefreshAtRest + PotProvider:RefreshAtRest
- Move `FindSpellByItemID` helper into Providers.lua (provider-local or module-local)
- `ns:RefreshMetaIcons` becomes thin wrapper iterating `ns.providers` and calling each `RefreshAtRest()` — CDMTab callsite unchanged
- Update REQUIREMENTS.md PROV-04 from `ns.GetPreviewInfoForKey` → `ns.GetDisplayInfoForKey`

**Out of scope (phase boundary):**
- Migrating Display.lua consumers (keeps using existing resolution chains until Phase 22)
- Migrating CDMTab.lua consumers (Phase 23)
- Rewriting `StartAllPreviewTimers` for additive-preview (PITFALL-4 / LIFE-03 — Phase 21)
- Removing now-redundant helpers `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` (Phase 24 cleanup once consumers migrated)

</domain>

<decisions>
## Implementation Decisions

### Base Mixin Contract Changes

- **D-01:** Collapse `GetPreviewInfo(key)` and `GetAtRestInfo(key)` into a single `GetDisplayInfo(key)`. Return shape: `{ icon=number, label=string, duration=number, spellID=number }`. Callers that don't need `duration` ignore it.
- **D-02:** Rationale: `duration` is the only field unique to preview. At-rest is preview minus duration. One method, one concept, one caller contract.
- **D-03:** Add `SpellProviderBaseMixin:RefreshAtRest()` — no-op default. Meta-providers override with inventory-scan logic. Kept as a method (not a standalone function) so it's provider-extensible and testable per-provider.

### Return Shape (GetDisplayInfo)

- **D-04:** `spellID` field is always NUMERIC. For string-keyed providers (trinket/pot/lust), provider resolves to its concrete at-rest spell:
  - Trinket: resolved equipped trinket's buff spellID (or first CSV fallback)
  - Pot: resolved bag pot's buff spellID (or first CSV fallback)
  - Lust: class-aware resolved lustSpellID (via `ns.CLASS_LUST_SPELL[playerClass]` or `GetHunterLustSpell()` for hunters)
  - UserSpell: the key itself (numeric)
- **D-05:** `duration` is the REAL duration — never the v0.2.3 sentinel `0`:
  - Trinket/Pot: resolved spell's duration from `TRINKET_SPELLS[spellID].duration` / `POT_SPELLS[spellID].duration`
  - Lust: `40` (constant)
  - UserSpell: `ns.db.trackedBuffs[spellID].duration`
- **D-06:** `icon` is the resolved icon — uses provider's cached at-rest icon for meta-providers (populated by `RefreshAtRest`), or `ns:GetSpellIcon(spellID)` for lust/user-spells.
- **D-07:** `label` preference order:
  - Trinket/Pot: `C_Spell.GetSpellInfo(resolvedSpellID).name` → fallback to static label (e.g., "Trinket", "Damage Pot")
  - Lust: `C_Spell.GetSpellInfo(lustSpellID).name` → fallback to "Lust / Heroism"
  - UserSpell: `ns.db.trackedBuffs[key].label`

### Dispatch Helper

- **D-08:** `ns:GetDisplayInfoForKey(key)` exported from Providers.lua. **Type dispatch** (hardcoded by design) using a local `keyToProvider` lookup table:
  ```lua
  local keyToProvider = {
      trinket = TrinketProvider,
      pot = PotProvider,
      lust = LustProvider,
  }
  function ns:GetDisplayInfoForKey(key)
      if type(key) == "string" then
          local p = keyToProvider[key]
          return p and p:GetDisplayInfo(key) or nil
      end
      return UserSpellProvider:GetDisplayInfo(key)
  end
  ```
- **D-09:** Table is LOCAL to Providers.lua — not on ns. Future meta-providers update the table here, not at call sites. Reviewer sees the map in one place.
- **D-10:** O(1) lookup. No iteration. Trade-off: helper is coupled to provider inventory — acceptable given providers are rare additions and table lives next to them.
- **D-11:** Dispatch helper does NOT add `OwnsKey(key)` method to the base mixin. Providers remain with exactly 4 methods (GetEventInterests, OnTrigger, GetDisplayInfo, RefreshAtRest).

### At-Rest Cache Migration (PROV-F3 pulled in)

- **D-12:** Move out of BuffEngine.lua:
  - `ns.metaAtRest` (table with `trinket` and `pot` sub-entries) — deleted entirely
  - `FindSpellByItemID` helper — moves into Providers.lua (module-local; shared by Trinket and Pot)
  - Inventory-scan logic inside `ns:RefreshMetaIcons` — moves into Trinket/Pot provider methods
  - Trinket's `GetAtRestMetaIcon`/`GetAtRestMetaInfo` wrappers — logic folded into provider `GetDisplayInfo` (see D-16 below)
- **D-13:** Each meta-provider owns its at-rest cache as instance state. **Cache is minimal — only `{ spellID, duration }`**:
  ```lua
  TrinketProvider.atRest = { spellID = nil, duration = nil }
  PotProvider.atRest = { spellID = nil, duration = nil }
  ```
  **Icon and label are DERIVED on-demand** in `GetDisplayInfo` via `ns:GetSpellIcon(spellID)` and `C_Spell.GetSpellInfo(spellID).name`. Single source of truth — spellID is the primary key; display fields are derivations. Eliminates redundant cache data and potential staleness.
  (UserSpell and Lust don't need at-rest cache — they resolve fresh each call.)
- **D-14:** Each meta-provider implements `RefreshAtRest()` with its own scan. **Writes only `{ spellID, duration }` to its cache** (no icon, no label):
  - TrinketProvider: scans `INVSLOT_TRINKET1` / `INVSLOT_TRINKET2` via `GetInventoryItemID`, reverse-lookup via `FindSpellByItemID(TRINKET_SPELLS, ...)`, falls back to `TRINKET_FALLBACK_ORDER`. Writes resolved `spellID` + its `duration` from TRINKET_SPELLS entry.
  - PotProvider: scans bags via `C_Item.GetItemCount`, reverse-lookup via `FindSpellByItemID(POT_SPELLS, ...)`, falls back to `POT_FALLBACK_ORDER`. Writes resolved `spellID` + its `duration` from POT_SPELLS entry.
  - LustProvider: `RefreshAtRest()` no-op (class-aware lookup is always-fresh, not cached)
  - UserSpellProvider: `RefreshAtRest()` no-op
- **D-15:** `ns:RefreshMetaIcons()` stays in BuffEngine.lua as a thin wrapper:
  ```lua
  function ns:RefreshMetaIcons()
      if InCombatLockdown() then return end       -- combat gate stays at entry
      for _, provider in ipairs(ns.providers) do
          provider:RefreshAtRest()
      end
  end
  ```
  CDMTab's `StartPreview` callsite unchanged. Name retained for backwards compatibility in Phase 20; rename deferred to Phase 24 cleanup.
- **D-16:** Inside TrinketProvider:GetDisplayInfo / PotProvider:GetDisplayInfo:
  1. Read `self.atRest.spellID` and `self.atRest.duration` from cache
  2. Derive `icon = ns:GetSpellIcon(self.atRest.spellID)` (returns 134400 fallback if spell info unavailable)
  3. Derive `label = C_Spell.GetSpellInfo(self.atRest.spellID).name` (fallback to static "Trinket"/"Damage Pot")
  4. Return `{ icon, label, duration = self.atRest.duration, spellID = self.atRest.spellID }`
  5. If cache is unpopulated (first call before RefreshAtRest), return sane fallback: use first CSV entry's spellID/duration, derive icon/label from that.

### Combat-Lockdown Safety

- **D-17:** `RefreshAtRest()` assumes the CALLER has combat-gated. `ns:RefreshMetaIcons` wrapper enforces this. Providers MUST NOT be called mid-combat from a restricted context.
- **D-18:** If a future caller invokes `provider:RefreshAtRest()` directly (bypassing the wrapper), the provider defensively bails on `InCombatLockdown()` too. Double guard — cheap.
- **D-19:** PITFALL-5 preserved: `GetDisplayInfo` (the runtime path) does NOT call inventory APIs. Only `RefreshAtRest` does.

### What Phase 20 Does NOT Change

- **D-20:** Display.lua — UNTOUCHED. Still uses existing resolution chains (`ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` via namespace). These stay as thin backwards-compat shims OR keep the existing wrapper form in BuffEngine pointing at provider methods. Planner decides implementation; behavior is: Display.lua grep matches the same names until Phase 22.
- **D-21:** CDMTab.lua — UNTOUCHED. Same reasoning as Display.lua. Migration is Phase 23.
- **D-22:** `StartAllPreviewTimers` — UNTOUCHED. Still iterates `ns.db.trackedBuffs` and writes preview procs with `entry.duration` (which remains 0 for trinket/pot — the bug that Phase 21 fixes via LIFE-03).
- **D-23:** `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` helpers — preserved in BuffEngine.lua as shims that delegate to provider-backed resolution OR remain original until Phase 24 cleanup. Planner picks concrete implementation.

### Backwards-Compat Shims (Provisional)

- **D-24:** Since Display/CDMTab still call `ns:GetAtRestMetaIcon(key)` and `ns:GetAtRestMetaInfo(key)` and `ns:ResolveSuggestedSpellID(key)`, and since `ns.metaAtRest` is being deleted in favor of provider-owned caches, the planner must ensure these wrappers continue to return the right data. **Shims MUST call through `provider:GetDisplayInfo(key)`** (since cache is minimal — icon/label are derived inside GetDisplayInfo, not cached):
  - `ns:GetAtRestMetaIcon(key)` → `local info = ns:GetDisplayInfoForKey(key); return info and info.icon or 134400`
  - `ns:GetAtRestMetaInfo(key)` → `local info = ns:GetDisplayInfoForKey(key); return info and { icon = info.icon, spellID = info.spellID, duration = info.duration } or nil`
  - `ns:ResolveSuggestedSpellID(key)` → `local info = ns:GetDisplayInfoForKey(key); return info and info.spellID or nil` (replaces the old SUGGESTED_BUFFS closure read for meta-keys; for non-meta string keys, falls through to old logic if any)
  - Shims MUST NOT read `provider.atRest` directly — that's internal state. They go through the public `GetDisplayInfo` API.
- **D-25:** All three shims are scheduled for removal in Phase 24 once Display.lua (Phase 22) and CDMTab.lua (Phase 23) migrate to `ns:GetDisplayInfoForKey`.

### REQUIREMENTS.md Update

- **D-26:** Update PROV-04 in REQUIREMENTS.md:
  - Old: `ns.GetPreviewInfoForKey(key) dispatch helper returns preview info for any provider key...`
  - New: `ns.GetDisplayInfoForKey(key) dispatch helper returns display info (icon, label, duration, spellID) for any provider key — single call site replaces all duplicated icon resolution chains`
  - Mark PROV-04 complete in traceability once Phase 20 ships.

### Claude's Discretion

- Exact Lua style for provider instance-state init (module-level local vs mixin-local field)
- Whether to call `RefreshAtRest` once at addon load for initial population (or rely on first `StartPreview` to populate)
- Whether `FindSpellByItemID` is a top-level local in Providers.lua or an upvalue inside TrinketProvider/PotProvider's method scope
- Shim implementation style for D-24 (direct `provider.atRest` read vs calling `provider:GetDisplayInfo`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research
- `.planning/research/SUMMARY.md` — milestone synthesis
- `.planning/research/PITFALLS.md` — PITFALL-4 (preview regression), PITFALL-5 (combat lockdown on RefreshAtRest)

### Prior phase context
- `.planning/phases/19-lustprovider-unit-aura-dispatch/19-CONTEXT.md` — lust provider shape, data hybrid-move pattern
- `.planning/phases/18-trinketprovider-potprovider-buffengine-dispatch/18-CONTEXT.md` — trinket/pot mixin patterns, data relocation precedent

### Project docs
- `CLAUDE.md` — stylua after Lua edits, combat lockdown discipline
- `.planning/REQUIREMENTS.md` — PROV-04 (needs rename per D-26)

### Code files
- `Providers.lua` — extension target. Current 4 providers all live here. Base mixin contract is where the GetDisplayInfo + RefreshAtRest decisions land.
- `BuffEngine.lua` — read FULLY: `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo`, `ns:ResolveSuggestedSpellID`, `ns.metaAtRest`, `ns:RefreshMetaIcons`, `FindSpellByItemID`, `SUGGESTED_BUFFS` entries with `getCDMSpellID`/`getCDMIcon` closures
- `CDMTab.lua` — DO NOT modify. Grep for `ns:RefreshMetaIcons()` call site in StartPreview to verify the thin-wrapper still resolves correctly.
- `Display.lua` — DO NOT modify. Grep for `GetAtRestMetaIcon`, `GetAtRestMetaInfo`, `ResolveSuggestedSpellID` calls to verify shim behavior post-phase.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 17/18/19)
- `SpellProviderBaseMixin` + `CreateFromMixins` — base for all 4 providers
- `TRINKET_SPELLS`, `POT_SPELLS`, `TRINKET_FALLBACK_ORDER`, `POT_FALLBACK_ORDER`, `SATED_DEBUFF_TO_LUST`, `SHARED_LUST_BUFFS`, `CLASS_LUST_SPELL`, `GetHunterLustSpell` — already in Providers.lua, ns.* exports
- `ns:GetSpellIcon(spellID)` wrapper — available in BuffEngine for icon lookups
- `C_Spell.GetSpellInfo(spellID).name` — label resolution pattern
- `INVSLOT_TRINKET1`, `INVSLOT_TRINKET2` WoW globals
- `GetInventoryItemID(unit, slot)`, `C_Item.GetItemCount(itemID)`, `C_Item.GetItemIconByID(itemID)` WoW APIs
- `InCombatLockdown()` WoW API

### Established Patterns
- Static data + ns.* export for cross-file access (Phase 18/19 pattern)
- Provider owns its data; ns wrapper iterates providers for uniform orchestration (consistent with how `ns:DispatchEventToProviders` iterates)
- `FindSpellByItemID(spellTable, itemID)` reverse-lookup — currently local to BuffEngine, moves to Providers.lua

### Integration Points
- `CDMTab.StartPreview` calls `ns:RefreshMetaIcons()` — the wrapper stays, so callsite unchanged
- `SUGGESTED_BUFFS` entries have `getCDMSpellID` / `getCDMIcon` closures in BuffEngine — those read `ns.metaAtRest` today. After Phase 20 they must read via provider (or via the `ns:GetAtRestMetaIcon` shim). Planner picks cleanest approach.

### Preserved Functions (plan must NOT touch)
- Display.lua, CDMTab.lua (zero edits in Phase 20)
- `StartAllPreviewTimers`, `ClearAllTimers` (PITFALL-4)
- All four providers' OnTrigger methods (only new method added, existing ones untouched)
- Core.lua
- TerribleBuffTracker.toc load order
- CURRENT_SCHEMA_VERSION = 3

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose **type dispatch** over iteration+OwnsKey ("type dispatch is fine — keep it simple"). Helper uses local keyToProvider table; no OwnsKey method added to base mixin.
- User explicitly chose **full PROV-F3 move** — pulling the RefreshAtRest migration forward into Phase 20 rather than deferring to v0.3+. Justification: providers are THE owners of their data; keeping the refresh logic in BuffEngine splits provider semantics across files.
- User explicitly chose **collapse to GetDisplayInfo** — a single method replacing both GetPreviewInfo and GetAtRestInfo. Return shape includes duration; callers ignore when not needed.
- Single-spellID return field (D-04) — provider returns its resolved concrete numeric spell even for string keys, so downstream tooltip code (`GameTooltip:SetSpellByID`) can use `previewInfo.spellID` uniformly.
- **Minimal cache (D-13)** — user explicitly chose `{ spellID, duration }` cache over `{ icon, spellID, duration }`. Rationale: spellID is the primary key; icon and label are derivations. Caching icon is redundant data that could go stale. `GetSpellInfo` call cost on display refresh is negligible (~20-60 calls/sec per at-rest placeholder). Single source of truth beats micro-optimization.

</specifics>

<deferred>
## Deferred Ideas

- **Display.lua migration** — Phase 22 (DISP-01, DISP-03). Zero changes in Phase 20.
- **CDMTab.lua migration** — Phase 23 (DISP-02). Zero changes in Phase 20.
- **StartAllPreviewTimers additive-preview rewrite** — Phase 21 (LIFE-03, PITFALL-4).
- **Removal of `ns:ResolveSuggestedSpellID` / `ns:GetAtRestMetaIcon` / `ns:GetAtRestMetaInfo`** — Phase 24 cleanup (DISP-04). They remain as shims until consumers migrate.
- **Rename `ns:RefreshMetaIcons` → `ns:RefreshAllProviderCaches`** — Phase 24 cleanup. CDMTab callsite already uses the old name; rename is cosmetic and deferred.
- **Initial `RefreshAtRest` at addon load** — Claude's Discretion; planner picks whether to trigger once at ADDON_LOADED (out of combat only) or rely on first StartPreview.

</deferred>

---

*Phase: 20-getpreviewinfo-dispatch-helper*
*Context gathered: 2026-04-21*
