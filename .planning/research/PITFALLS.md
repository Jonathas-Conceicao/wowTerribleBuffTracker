# Pitfalls Research

**Domain:** WoW addon provider abstraction layer over existing timer system
**Researched:** 2026-04-18
**Confidence:** HIGH — derived from direct codebase analysis, not general survey

---

## Critical Pitfalls

### Pitfall 1: SavedVariables Schema Break from Key Type Change

**What goes wrong:**
The current `trackedBuffs` table uses mixed key types: numeric spellIDs for user spells, and string keys (`"lust"`, `"trinket"`, `"pot"`) for meta-buffs. If providers introduce a new canonical key type — say, wrapping everything in a string or renaming keys during construction — existing SavedVariables entries at the old key will become orphaned. The migration path silently produces duplicate or missing entries and users see their tracked buffs disappear after upgrade.

**Why it happens:**
The instinct when adding a provider is to normalize the key format for uniformity. A provider constructor that maps `spellID -> "spell_12345"` or renames `"trinket"` to `"meta_trinket"` will break lookups in `trackedBuffs[key]`. The schema migration code in `InitBuffEngine` only runs numeric-key fixups — it has no guard for string key renames.

**How to avoid:**
Providers must be constructed from existing SavedVariables at runtime WITHOUT modifying the persisted keys. The `trackedBuffs` keys are the ground truth; providers read from them, never rename them. If a provider needs an internal identifier, it carries that as an instance field distinct from the DB key. Schema version 3 is terminal for v0.2.4 unless a concrete migration is written and tested.

**Warning signs:**
- Any code path where a provider writes back to `trackedBuffs` using a key it generated internally.
- A migration block that iterates `trackedBuffs` and calls `trackedBuffs[newKey] = entry; trackedBuffs[oldKey] = nil`.
- `trackedBuffs["trinket"]` returning nil after upgrade while `trackedBuffs["meta_trinket"]` appears.

**Phase to address:**
Provider construction phase. Before any provider emits its first proc, verify it round-trips: `assert(ns.db.trackedBuffs[provider.key] ~= nil)`.

---

### Pitfall 2: Timer Identity Loss During Dual-Key Unification

**What goes wrong:**
`ns.activeTimers` is currently dual-keyed: meta-slot timers are stored under their numeric cast spellID (e.g. `1259633`) but retrieved in Display via `activeBarBySpell[timer.metaSlot]` (`"trinket"`). The `metaSlot` field on the timer bridges the gap. When providers introduce a unified `ActiveProc` shape, the temptation is to key `activeTimers` by provider key instead. If the migration forgets to re-index by both keys, the Display cancel scan (`ScanActiveTimersForCancellation`) stops finding timers by their spellID, allowing expired or cancelled procs to linger invisibly.

**Why it happens:**
The dual-key scheme feels like technical debt — "clean it up while we're here." But the dual-key exists because aura cancellation needs to look up timers by the actual cast spellID (`C_UnitAuras.GetPlayerAuraBySpellID(spellID)`) while Display layout uses the DB slot key. Collapsing to a single key breaks one of these lookups.

**How to avoid:**
`ActiveProc` must carry both a `procKey` (the DB slot key — string or numeric) and a `spellID` (the actual cast spell for aura lookups). `activeTimers` is keyed by `procKey`. Cancellation logic indexes by `procKey` but reads `proc.spellID` when calling `C_UnitAuras`. Display reads by `procKey`. This is a deliberate separation, not an accident to remove.

**Warning signs:**
- `ScanActiveTimersForCancellation` iterating `activeTimers` and calling `GetPlayerAuraBySpellID(k)` where `k` is the table key — this breaks for string keys like `"trinket"`.
- `activeBarBySpell` lookup misses in Display when a trinket proc is active.
- A timer shows on screen but is not cancelled when the buff drops.

**Phase to address:**
BuffEngine refactor phase. Write a unit assertion: after a trinket cast, confirm `ns.activeTimers["trinket"]` exists AND `ns.activeTimers["trinket"].spellID` equals the numeric cast spellID.

---

### Pitfall 3: Preview Mode Regression from Provider-Filtered Iteration

**What goes wrong:**
`StartAllPreviewTimers` currently iterates `ns.db.trackedBuffs` directly, producing one preview timer per entry. If preview is refactored to route through providers (calling `provider:GetPreviewInfo()` instead), any provider that filters its entries — for example, skipping entries whose DB key doesn't match its known spell set — will produce no preview timer for those entries. The CDM preview shows blank/missing slots.

**Why it happens:**
Provider `GetPreviewInfo()` is easy to implement for known-static entries (lust: always 40s, class icon) but hard to generalize for user-defined spells. Developers write `GetPreviewInfo()` that returns nil for unknown spellIDs as a "safe" default. Preview silently drops those entries.

**How to avoid:**
Preview must iterate `trackedBuffs` independently of provider dispatch. Each entry produces a preview timer using its stored `duration` and a resolved icon, regardless of which provider will handle its real casts. Providers are not involved in preview generation — `GetPreviewInfo()` is only used by CDM tab display (icon, label, tooltip), not by `StartAllPreviewTimers`. The existing `StartAllPreviewTimers` implementation handles this correctly and should be preserved verbatim.

**Warning signs:**
- `StartAllPreviewTimers` calling `provider:GetPreviewInfo()` and using the return value to decide whether to create a timer.
- CDM Suggested section shows a provider slot but the preview timer is absent.
- `duration = 0` sentinel for trinket/pot causes preview to create a zero-length timer (already guarded in current code — verify guard survives refactor).

**Phase to address:**
BuffEngine refactor phase. After wiring providers, open CDM and verify all non-hidden `trackedBuffs` entries produce visible bars/icons in preview.

---

### Pitfall 4: Aura Cancellation Regression from Source Field Loss

**What goes wrong:**
`ScanActiveTimersForCancellation` branches on `timer.source`: `"cast"` triggers `GetPlayerAuraBySpellID(spellID)`, `"debuff"` triggers the lust-family multi-check. If the `ActiveProc` unification drops the `source` field (or renames it), all timers fall through to no-op and cancellation stops working. Buffs that drop early (cancelled by dispel, boss mechanic, etc.) linger on screen until they naturally expire.

**Why it happens:**
`source` is a runtime-only discriminator that was added specifically for the lust path. When normalizing to `ActiveProc`, the refactor may decide `source` is an implementation detail the provider should handle internally, and omit it from the normalized shape. But `ScanActiveTimersForCancellation` lives in BuffEngine, not in providers, so it needs the discriminator on the proc.

**How to avoid:**
`ActiveProc` must include a `cancelMode` field (or equivalent) that tells the cancellation sweep how to check for early termination. Values: `"cast"` (check aura by `proc.spellID`), `"debuff"` (check lust-family by `proc.lustBuffID`), `"meta"` (no aura check — meta-slot timers are cast-originated but use `proc.spellID` directly). If the provider abstraction is meant to own cancellation, add a `provider:ShouldCancel(proc)` method, but do not silently drop the check.

**Warning signs:**
- `ScanActiveTimersForCancellation` has no `timer.source` branch and always returns `shouldCancel = false`.
- Lust timer survives after Sated debuff drops.
- Cast-originated timer survives after buff is dispelled in a M+ run.

**Phase to address:**
BuffEngine refactor phase, cancellation sweep migration. Run `/tbt debug` and verify "Cancelled N timer(s)" prints when a buff drops mid-timer.

---

### Pitfall 5: Combat Lockdown Violation in Provider Construction

**What goes wrong:**
`RefreshMetaIcons` is combat-gated (`InCombatLockdown()` guard) because it calls `GetInventoryItemID` and `C_Item.GetItemCount` — both restricted in combat. If provider construction or re-initialization is triggered by an event that fires in combat (e.g. `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_AURA`), and a provider constructor calls these APIs, the client gets a Lua error and potentially a taint that propagates to CDM's secure UI.

**Why it happens:**
Provider initialization feels like a one-time setup. Developers write provider constructors that call `RefreshMetaIcons` to "warm up" state. When `UNIT_SPELLCAST_SUCCEEDED` fires mid-fight and the event handler reconstructs providers (e.g., lazy init on first trigger), the inventory APIs are called in combat.

**How to avoid:**
Provider constructors must be pure: they only read from already-resolved in-memory state (`ns.metaAtRest`, `TRINKET_SPELLS`, `POT_SPELLS`). The combat-gated scan (`RefreshMetaIcons`) remains the sole entry point for inventory resolution, called only from `StartPreview` (CDM open, always out of combat). Provider `OnTrigger()` reads `ns.metaAtRest` for icon, not the raw inventory APIs.

**Warning signs:**
- A provider `Init()` or constructor calling `GetInventoryItemID`, `C_Item.GetItemCount`, or `GetItemInfo` directly.
- Lua error "attempt to call forbidden function" during combat.
- CDM action buttons becoming non-interactive after a combat sequence (taint indicator).

**Phase to address:**
Provider construction phase. Add `assert(not InCombatLockdown(), "provider construction in combat")` at the top of any provider Init that touches item APIs — or remove those calls entirely from Init.

---

### Pitfall 6: Event Handler Ordering Bug — Lust Before Secret Gate

**What goes wrong:**
The current `OnUnitAura` handler deliberately checks Sated debuffs BEFORE the `ShouldAurasBeSecret()` gate. This ordering is load-bearing: in M+ (where auras are secret), lust is still detected via the Sated debuff (which is never secret). If the provider refactor moves lust detection into a generic `OnUnitAura` dispatch that applies the secret gate first, lust timers stop starting in M+.

**Why it happens:**
When routing events through providers, the natural pattern is: gate the event, then fan out to interested providers. Moving the gate above all provider dispatch breaks the lust provider's special case. The comment `-- LUST-01: Detect Sated-family debuffs BEFORE secret gate` in `BuffEngine.lua` documents this but is easy to miss during refactor.

**How to avoid:**
The UNIT_AURA dispatch must preserve two-phase ordering:
1. Pre-gate: iterate providers with `eventInterest.preGate == true`, pass full `updateInfo`. LustProvider is the only pre-gate provider.
2. Apply `ShouldAurasBeSecret()` gate.
3. Post-gate: iterate remaining UNIT_AURA providers.

Alternatively, keep the lust check monolithic in `OnUnitAura` and only route non-lust aura events through providers. Do not refactor the lust check into a generic dispatch path unless the two-phase structure is explicitly preserved.

**Warning signs:**
- LustProvider receiving `updateInfo.addedAuras` only after the secret gate — check by adding a print inside LustProvider and verifying it fires in M+.
- The secret gate check appearing before any `for _, provider in ipairs(providers)` loop.
- `ns.SATED_DEBUFF_TO_LUST` lookup moved inside a post-gate branch.

**Phase to address:**
Event routing phase. After wiring UNIT_AURA dispatch, enter a M+ (or simulate via `/tbt debug` + manual aura injection) and verify lust timer starts.

---

### Pitfall 7: Metatable GC Pressure from Per-Proc Object Construction

**What goes wrong:**
If `ActiveProc` is implemented as a class with a metatable (`setmetatable({}, ActiveProc)`), every proc creation allocates a new userdata/table pair. In hot paths — `OnSpellCastSucceeded` firing on every player cast, `GetActiveTimers` called every 50ms — repeated proc construction and abandonment drives GC pauses. WoW's Lua GC is tuned for minimal allocation; churn here causes frame hitches.

**Why it happens:**
Object-oriented provider patterns from other languages translate naturally to metatables in Lua. `ActiveProc:new(...)` looks clean. The cost is invisible until GC runs.

**How to avoid:**
`ActiveProc` is a plain table with no metatable. Fields are set directly: `local proc = { icon = ..., duration = ..., label = ..., expiresAt = ... }`. `ns.activeTimers` stores these plain tables. For `GetActiveTimers`, the existing reusable `result` table is wiped and refilled each call — do NOT allocate a new `result = {}` inside the function. The existing `wipe()` pattern in Display is the reference.

**Warning signs:**
- `setmetatable` calls inside `OnTrigger()` or `GetActiveTimers()`.
- A `result = {}` allocation inside `GetActiveTimers` (currently correct — but fragile under refactor).
- Lua GC metrics spiking (visible with `/dump collectgarbage("count")`).

**Phase to address:**
BuffEngine proc lifecycle phase. Code review: grep for `setmetatable` in BuffEngine.lua and Display.lua — any hit is a bug.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `TRINKET_SPELLS`/`POT_SPELLS` in BuffEngine instead of moving to providers | No file split needed | TrinketProvider and PotProvider can't be self-contained; adding new meta-types requires BuffEngine edits | Acceptable for v0.2.4; revisit if a 4th meta-type is added |
| Inline lust pre-gate logic instead of provider `preGate` flag | Avoids two-phase dispatch complexity | Lust special-casing stays in BuffEngine core, not in LustProvider | Acceptable; document the reason explicitly |
| Shared `SHARED_LUST_BUFFS` and `SATED_DEBUFF_TO_LUST` remain module-level in BuffEngine | No indirection | LustProvider is not self-contained | Acceptable; these tables are stable and small |
| Preserve existing `ns.activeTimers` key scheme (no unification) | Zero migration risk | Dual-key indexing persists as implementation complexity | Acceptable indefinitely — the dual-key serves real purposes |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CDM tab icon resolution (CDMTab.lua) | Duplicating `GetSuggestedAtRestIcon` / `ResolveSuggestedSpellID` chains in both CDMTab and Display after refactor | Extract a single `ns:ResolveDisplayIcon(key)` that both files call; providers expose `GetPreviewInfo()` for CDM, Display reads `proc.icon` directly |
| `SetBuffSection` side-effects | Refactoring `SetBuffSection` to go through providers — providers then need to update DB, which they should not own | `SetBuffSection` stays in BuffEngine and writes `ns.db.trackedBuffs[key].section` directly; providers are stateless and do not own DB writes |
| Preview + real timer coexistence | `StartAllPreviewTimers` wipes `savedPreviewTimers` before merging real timers back — if provider `OnTrigger` fires during preview setup, it writes to `ns.activeTimers` before the merge, and the merge overwrites it | The existing save/restore pattern must be preserved exactly; providers must not write to `ns.activeTimers` from outside `BuffEngine` dispatch |
| `metaIconsDirty` flag | Flag currently cleared at end of `UpdateDisplay` — if Display is split across provider-specific render paths, the flag may be cleared before the second path reads it | Clear `metaIconsDirty` once, after all render paths have consumed it, at the bottom of the unified `UpdateDisplay` |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Provider lookup table rebuilt every `OnSpellCastSucceeded` | Cast lag; frame hitch on every spell | Build `spellID -> provider` dispatch map once at init; treat it as read-only at runtime | Immediate — `OnSpellCastSucceeded` fires frequently in combat |
| `ipairs(ns.SUGGESTED_BUFFS)` inside `UpdateDisplay` hot path | Frame hitch every 50ms | Cache the `suggested.key -> getCDMIcon` lookup at init; do not linear-scan SUGGESTED_BUFFS in the render loop | At ~10+ tracked buffs with meta-slots |
| `C_Spell.GetSpellInfo` called per frame in `UpdateDisplay` | API call overhead; label flicker | Current code already dirty-checks `bar.spellID ~= slot.spellID` before refreshing label — preserve this guard after refactor | Immediate if guard is lost |
| `pairs(ns.db.trackedBuffs)` in `UpdateDisplay` for slot building | Allocation + hash traversal every 50ms | Current code already wipes and refills `barSlots`/`buffSlots` module-level tables — preserve `wipe()` pattern | At 20+ tracked buffs |

---

## "Looks Done But Isn't" Checklist

- [ ] **UserSpellProvider:** Verify it handles `section == "hidden"` guard — a user buff in hidden section must not produce a proc on cast.
- [ ] **TrinketProvider:** Verify shared-slot overwrite: two different trinket casts back-to-back, only the second timer survives in `ns.activeTimers["trinket"]` (keyed by `"trinket"`, not by cast spellID).
- [ ] **LustProvider:** Verify UNIT_AURA pre-gate ordering in M+ simulation — lust timer must start when `ShouldAurasBeSecret()` returns true.
- [ ] **Aura cancellation:** Verify `ScanActiveTimersForCancellation` still finds timers by `procKey` and reads `proc.spellID` for the aura API call.
- [ ] **Preview:** Open CDM, verify all non-hidden entries show timer bars/icons. Close CDM, verify real timers are restored.
- [ ] **Display unification:** Confirm zero `if timer.metaBuff then` or `if type(timer.spellID) == "string" then` branches remain in `UpdateDisplay` after refactor.
- [ ] **CDMTab icon:** Confirm CDMTab icon frames call a single shared resolver — no inline `GetSuggestedAtRestIcon` / `ResolveSuggestedSpellID` chains duplicated from Display.
- [ ] **Schema version:** Confirm `CURRENT_SCHEMA_VERSION` is NOT incremented unless a concrete migration block is written. v0.2.4 makes no DB shape changes.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Schema break from key rename | HIGH | Write a v4 migration that detects renamed keys and moves entries back; must handle partial upgrades where some entries were renamed and some were not |
| Timer identity loss | MEDIUM | Revert `activeTimers` keying to dual-key scheme; restore `metaSlot` field on all meta procs |
| Preview regression | LOW | Restore `StartAllPreviewTimers` to direct `trackedBuffs` iteration; remove provider routing from preview path |
| Aura cancellation regression | LOW | Restore `source`/`cancelMode` field on `ActiveProc`; restore branch logic in `ScanActiveTimersForCancellation` |
| Combat lockdown violation | MEDIUM | Remove inventory API calls from provider constructors; move to `RefreshMetaIcons` call site only; may require `/reload` to clear taint |
| Event handler ordering bug | LOW | Re-read `-- LUST-01` comment; move Sated debuff check above the `ShouldAurasBeSecret()` gate |
| GC pressure from metatables | LOW | Remove `setmetatable` from proc construction; use plain tables; verify with GC count baseline |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| SavedVariables schema break | Provider construction | `assert(ns.db.trackedBuffs[provider.key] ~= nil)` for every provider; no schema version bump |
| Timer identity loss | BuffEngine proc lifecycle | After trinket cast: `ns.activeTimers["trinket"].spellID == numericCastSpellID` |
| Preview regression | BuffEngine refactor | Open CDM, count visible preview entries vs non-hidden `trackedBuffs` entries |
| Aura cancellation regression | Cancellation sweep migration | `/tbt debug` + cast a buff + remove it manually + verify "Cancelled" print |
| Combat lockdown violation | Provider construction | No `InCombatLockdown`-restricted APIs in provider `Init` or `OnTrigger` |
| Event handler ordering | Event routing | Simulate M+ aura secrecy; verify lust timer starts; lust check is pre-gate |
| GC pressure | BuffEngine proc lifecycle | Grep for `setmetatable` in BuffEngine and Display; zero hits required |

---

## Sources

- Direct codebase analysis: `BuffEngine.lua`, `Display.lua`, `Core.lua`, `CDMTab.lua`
- WoW Lua API constraint: `GetInventoryItemID`, `C_Item.GetItemCount` restricted in combat lockdown
- WoW Lua GC behavior: plain tables are allocation-free when reused with `wipe()`; metatables add GC pressure
- Existing code comments: `-- LUST-01`, `-- D-07`, `-- D-11`, `-- AURA-02` — all document load-bearing ordering decisions
- Schema migration history: `InitBuffEngine` v0->v3 migration chain in `BuffEngine.lua`

---
*Pitfalls research for: SpellProvider abstraction layer over WoW addon timer system*
*Researched: 2026-04-18*
