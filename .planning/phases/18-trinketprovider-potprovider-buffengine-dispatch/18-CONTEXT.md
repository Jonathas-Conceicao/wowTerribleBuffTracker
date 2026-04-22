# Phase 18: TrinketProvider + PotProvider + BuffEngine Dispatch - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate trinket and pot cast detection out of `BuffEngine.OnSpellCastSucceeded` into dedicated SpellProviders (`TrinketProviderMixin` + `PotProviderMixin`), finalize the dispatch loop so BuffEngine's `OnSpellCastSucceeded` contains only a single dispatcher call (zero hardcoded branches), and establish `ns.activeTimers` as the single authoritative table with replace-on-reproc by stable slot key.

**In scope:**
- TrinketProviderMixin (new, separate concrete provider)
- PotProviderMixin (new, separate concrete provider)
- Move static data (`TRINKET_SPELLS`, `POT_SPELLS`, derived `*_ITEM_IDS`, `*_FALLBACK_ORDER`) from BuffEngine.lua into Providers.lua
- Update `ns.providers` priority order to `{ TrinketProvider, PotProvider, UserSpellProvider }` (LustProvider still missing — Phase 19)
- Remove trinket branch (branch 1) and pot branch (branch 2) from `OnSpellCastSucceeded`
- Update `ScanActiveTimersForCancellation` to read `castSpellID` from proc for cast-sourced cancellation check
- Update Display.lua lookup sites that currently use `metaSlot` field — switch to reading by string slot key directly
- Update CDMTab.lua lookups keyed by `metaSlot` or numeric castSpellID — switch to string slot key

**Out of scope (phase boundary):**
- LustProvider migration (Phase 19)
- `StartAllPreviewTimers` migration (PITFALL-4 — Phase 21)
- `ns.metaAtRest` cache and `ns:RefreshMetaIcons` relocation (PROV-F3, deferred to v0.3+)
- Display/CDMTab icon resolution chain unification (Phase 22/23)
- Tooltip consolidation (Phase 22)
- Provider-level RefreshCache() method (deferred)

</domain>

<decisions>
## Implementation Decisions

### Key Strategy
- **D-01:** Trinket/pot procs keyed by **stable string slot key** (`"trinket"`, `"pot"`), NOT by numeric castSpellID.
- **D-02:** ActiveProc carries `castSpellID` as a separate field (numeric, the actual cast spell) so `ScanActiveTimersForCancellation` can call `GetPlayerAuraBySpellID(proc.castSpellID)` for `source="cast"` procs.
- **D-03:** Reproc semantic becomes trivial overwrite: `ns.activeTimers["trinket"] = newProc` replaces the previous. Eviction loop (iterate + nil any matching metaSlot) is DELETED.
- **D-04:** `metaSlot` field is REMOVED from proc shape. Display and CDMTab lookups that read `timer.metaSlot` must be updated to read by slot key directly (`activeTimers["trinket"]`).

### Provider Factoring
- **D-05:** Separate mixins: `TrinketProviderMixin` and `PotProviderMixin` are independent concrete mixins — NOT a shared parameterized mixin.
- **D-06:** Rationale: trinkets may later need more complex setup (per-trinket edge cases, equipment hooks, cooldown integration). Keeping them separate leaves room to diverge without refactoring a shared parameterized base.
- **D-07:** Both mixins implement the same 4-method `SpellProviderBaseMixin` interface (GetEventInterests, OnTrigger, GetPreviewInfo, GetAtRestInfo).

### Data Location (Hybrid Move)
- **D-08:** Move into Providers.lua:
  - `TRINKET_SPELLS` table (spellID → {duration, itemID})
  - `POT_SPELLS` table
  - Derived `TRINKET_ITEM_IDS` / `POT_ITEM_IDS` sets
  - `TRINKET_FALLBACK_ORDER` / `POT_FALLBACK_ORDER` arrays
  - Each provider owns its data locally in the mixin scope (or provider-adjacent locals)
- **D-09:** KEEP in BuffEngine.lua for Phase 18:
  - `ns.metaIcons` / `ns.metaAtRest` caches
  - `ns:RefreshMetaIcons()` function
  - `ns:GetAtRestMetaIcon()` helper
  - `FindSpellByItemID()` local helper
- **D-10:** Rationale for hybrid: CDMTab.lua currently calls `ns:RefreshMetaIcons()` in StartPreview. Moving that function requires touching CDMTab — out of Phase 18 scope. Static data has no external callers except providers, so it moves cleanly.
- **D-11:** Providers reference `ns.TRINKET_SPELLS` / `ns.POT_SPELLS` etc. via the namespace — keep `ns.` exports on the static data so existing `ns.metaIcons` resolution in BuffEngine continues to work without change.

### Dispatch Semantics
- **D-12:** Dispatcher iterates ALL interested providers per event (current Providers.lua behavior preserved, no short-circuit).
- **D-13:** In practice no collisions exist — trinket/pot/user-spell IDs are disjoint — so iteration overhead is minimal (3 providers × 1 table lookup each).
- **D-14:** If a future provider needs to short-circuit, it can be handled via explicit priority check in the provider's OnTrigger (e.g., return nil if already handled). The dispatcher stays dumb.

### Cancellation Scan Update
- **D-15:** `ScanActiveTimersForCancellation` currently does `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` where `spellID` is the table key. After Phase 18 the key is `"trinket"` / `"pot"` (not a numeric spellID).
- **D-16:** Replace with: read `timer.castSpellID` for `source="cast"` procs. Fallback: if `castSpellID` absent (old-style numeric-key procs from UserSpellProvider), use the table key (which IS the spellID for those).
- **D-17:** UserSpellProvider already emits `proc.spellID == proc.key` (numeric). Add `castSpellID = spellID` to its proc shape for consistency so the cancellation scan has one code path.

### BuffEngine.OnSpellCastSucceeded After Phase 18
- **D-18:** Final shape is a single line:
  ```lua
  function ns:OnSpellCastSucceeded(spellID)
      ns:DispatchEventToProviders("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)
  end
  ```
  (or inlined at the event router in Core.lua — to be decided by planner, low importance)
- **D-19:** Zero event-specific branches remain. PROV-02 satisfied.

### Provider Registration Order
- **D-20:** `ns.providers = { TrinketProvider, PotProvider, UserSpellProvider }` — LustProvider added in Phase 19.

### Claude's Discretion
- Exact location of the locals (module-level vs inside the mixin table via Init) — planner may pick what reads clearest in Lua.
- Whether to include a one-line comment at BuffEngine's (now empty) `OnSpellCastSucceeded` pointing at Providers.lua for navigation aid.
- Decision on whether to inline `OnSpellCastSucceeded` into Core.lua's event router or keep the thin wrapper (cosmetic choice).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research
- `.planning/research/SUMMARY.md` — milestone-level synthesis, phase 18 recommendations
- `.planning/research/STACK.md` — CreateFromMixins pattern, dispatch table idioms
- `.planning/research/FEATURES.md` — four-buff-type comparison, key strategy pivot note
- `.planning/research/ARCHITECTURE.md` — 11-step migration order, integration points
- `.planning/research/PITFALLS.md` — critical pitfalls, especially PITFALL-2 (timer identity) and PITFALL-4 (preview regression)

### Project docs
- `CLAUDE.md` — stylua required after Lua edits, COMBAT_LOG_EVENT_UNFILTERED disabled, install.bat deploy
- `.planning/REQUIREMENTS.md` — PROV-02 (no hardcoded if/elseif in BuffEngine), LIFE-01 (single activeProcs table)

### Code files to read
- `Providers.lua` — current state, understand SpellProviderBaseMixin + UserSpellProviderMixin + DispatchEventToProviders
- `BuffEngine.lua` — branches 1 (trinket, ~lines 324-355) and 2 (pot, ~lines 358-389) to be removed; `ScanActiveTimersForCancellation` (~line 614) to be updated; static data tables (~lines 52-107) to be relocated
- `Display.lua` — find all reads of `timer.metaSlot` and the meta-slot lookup pattern; these must switch to reading by string slot key
- `CDMTab.lua` — find all reads of `timer.metaSlot` and any numeric castSpellID lookups for trinket/pot

### Phase 17 artifacts
- `.planning/phases/17-provider-skeleton-userspellprovider/17-SUMMARY.md`
- `.planning/phases/17-provider-skeleton-userspellprovider/17-VERIFICATION.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SpellProviderBaseMixin` (Providers.lua) — already defines the 4-method contract; Trinket and Pot mixins extend this via `CreateFromMixins(SpellProviderBaseMixin, {TrinketProviderMixin|PotProviderMixin})`
- `ns:DispatchEventToProviders` (Providers.lua) — already correctly installs returned procs into `ns.activeTimers[proc.key]` and calls `UpdateDisplay`. No dispatcher changes needed for Phase 18.
- `eventToProviders` map rebuild — Providers.lua builds it once at module load after `ns.providers` is set. Phase 18 just prepends new providers to `ns.providers` before the map is built.
- `ns:GetSpellIcon(spellID)`, `C_Spell.GetSpellInfo(spellID)` — already used by UserSpellProvider for icon/label resolution, reuse verbatim in TrinketProvider/PotProvider

### Established Patterns
- Proc shape from Phase 17: `{ key, icon, duration, label, expiresAt, source, startedAt, section, layoutOrder, spellID }` — TrinketProvider/PotProvider procs follow the same shape + `castSpellID` field for cancellation scan.
- Section/hidden guard: `if entry.section == "hidden" then return nil end` — copy from UserSpellProvider:OnTrigger.
- Combat gating: `RefreshMetaIcons` already uses `InCombatLockdown()` check — stays in BuffEngine.lua, providers don't touch inventory APIs.

### Integration Points
- Core.lua event router calls `ns:OnSpellCastSucceeded(spellID)` — does not change (BuffEngine wrapper still routes to dispatcher).
- `ns.activeTimers` is the shared state table — providers write via dispatcher, Display/CDMTab read.
- CDMTab's `StartPreview` still calls `ns:RefreshMetaIcons()` — untouched in Phase 18.

### Codebase Scan Requirements (plan must verify)
- All reads of `timer.metaSlot` in Display.lua and CDMTab.lua — must be located and migrated to string slot key lookup
- All reads of `ns.activeTimers[numericSpellID]` where the spellID is a trinket/pot cast ID — must be migrated to `ns.activeTimers["trinket"]`/`ns.activeTimers["pot"]`
- Any code that iterates `ns.activeTimers` and branches on `metaSlot` — the branching is no longer needed (key itself is the slot)

</code_context>

<specifics>
## Specific Ideas

- User wants trinket/pot providers to be separate (not parameterized shared) because **trinkets may need more complex setup logic later** (per-trinket edge cases). Don't share mixin code between them even if Phase 18 code would look nearly identical.
- User confirmed dispatcher "iterate all" is acceptable — no short-circuit even though it diverges from Phase 17 BuffEngine semantics. Disjoint IDs make the iteration safe.
- User approved hybrid data move — static tables go to Providers.lua now, cache/refresh stays put.

</specifics>

<deferred>
## Deferred Ideas

- **Provider-level RefreshCache() method** — moving `ns:RefreshMetaIcons` into trinket/pot providers as an instance method. Requires CDMTab call-site update. Deferred to v0.3+ per PROV-F3 (already in REQUIREMENTS.md Future section).
- **Inline OnSpellCastSucceeded into Core.lua event router** — cosmetic cleanup, no behavioral benefit. Low priority.
- **Shared MultiSpellProviderMixin** — rejected by user preference. If future meta-slots emerge (defensives, on-use utility items, etc.) and multiplication of near-identical mixins becomes painful, revisit in v0.3+.

</deferred>

---

*Phase: 18-trinketprovider-potprovider-buffengine-dispatch*
*Context gathered: 2026-04-19*
