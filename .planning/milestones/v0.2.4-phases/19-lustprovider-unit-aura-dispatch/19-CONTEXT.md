# Phase 19: LustProvider + UNIT_AURA Dispatch - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate lust detection from `BuffEngine.StartLustTimer` + inline `OnUnitAura` LUST-01 block into a dedicated `LustProviderMixin`. Register LustProvider in `ns.providers`. Route UNIT_AURA through the dispatcher. Rename the debug-log one-shot flag. Move lust-specific data tables alongside LustProvider following Phase 18 hybrid pattern.

**In scope:**
- LustProviderMixin (new, separate concrete provider, fourth and final registration)
- Move lust-specific data (`SATED_DEBUFF_TO_LUST`, `SHARED_LUST_BUFFS`, `CLASS_LUST_SPELL`, `GetHunterLustSpell` helper) from BuffEngine.lua into Providers.lua with `ns.*` exports preserved
- Update `ns.providers` order to `{ TrinketProvider, PotProvider, LustProvider, UserSpellProvider }` (final four — PROV-01 satisfied)
- Replace inline LUST-01 block in `OnUnitAura` with `ns:DispatchEventToProviders` call
- Delete `ns:StartLustTimer` from BuffEngine.lua (logic now lives in LustProvider:OnTrigger)
- Rename `ns.auraCheckBlocked` → `ns.secretGateLogged` and `ns:ClearAuraBlock` → `ns:ClearSecretGateLog` (update all call sites in Core.lua + BuffEngine.lua)
- Update `ScanActiveTimersForCancellation` to read `ns.SHARED_LUST_BUFFS` (was local, now namespace-exported)

**Out of scope (phase boundary):**
- Rewriting `StartAllPreviewTimers` to be fill-non-running (PITFALL-4 / LIFE-03 — Phase 21 scope)
- `GetPreviewInfo` / `GetAtRestInfo` semantics (Phase 20)
- Display/CDMTab icon resolution unification (Phase 22/23)
- Tooltip consolidation (Phase 22)

</domain>

<decisions>
## Implementation Decisions

### LustProvider Architecture

- **D-01:** `LustProviderMixin` is an independent concrete mixin extending `SpellProviderBaseMixin`. NOT shared with other providers. Follows the Phase 18 separate-mixins pattern (D-05 Phase 18).
- **D-02:** Lives in `Providers.lua` alongside TrinketProvider, PotProvider, UserSpellProvider. No new file.
- **D-03:** Registered in `ns.providers` at position 3 (before UserSpellProvider). Final order: `{ TrinketProvider, PotProvider, LustProvider, UserSpellProvider }` — satisfies PROV-01.

### Dispatcher Principles (locked, revised from earlier session)

- **D-04:** **Dispatcher is dumb and uniform.** `ns:DispatchEventToProviders` has NO gate logic, NO event-specific branching, NO awareness of secrets / isFullUpdate / previewActive. Same implementation as Phase 18.
- **D-05:** `BypassesSecretGate()` provider method — **DROPPED**. Earlier discussion proposed this; user rejected in favor of provider-internal safety. Dispatcher stays simple.
- **D-06:** Each provider owns its own safety logic internally — per-entry secret checks, preview guards (where applicable), no-restart guards. Shared safety is opt-in via helpers providers call, not dispatcher behavior.

### LustProvider Event Arg Shape

- **D-07:** Dispatcher passes raw UNIT_AURA args unchanged: `LustProvider:OnTrigger(event, unit, updateInfo)`. LustProvider iterates `updateInfo.addedAuras` internally.
- **D-08:** Provider returns either `nil` (no match) or a single ActiveProc (first Sated-matching aura, respecting no-restart guard). Does NOT return a list.

### LustProvider Gate Handling

- **D-09:** **NO top-level `C_Secrets.ShouldAurasBeSecret()` check inside LustProvider.** Sated debuff spellIDs are Blizzard-allowlisted as safe to read even when secrets are active. This is the original LUST-01 rationale.
- **D-10:** Per-entry `issecretvalue(aura.spellId)` defensive check stays — same as current BuffEngine code. Required in case the individual aura spellId is itself a secret value (opaque handle).
- **D-11:** **LustProvider does NOT check `ns.previewActive`.** Providers run normally during preview. Real procs fired during preview naturally overwrite preview placeholders via dispatcher write. This is a behavior change from v0.2.3 but matches all other providers (none check previewActive).

### No-Restart Guard (locked earlier, restated)

- **D-12:** No-restart guard lives inside `LustProvider:OnTrigger`. Implementation:
  ```lua
  local existing = ns.activeTimers["lust"]
  if existing and existing.expiresAt > GetTime() then
      return nil
  end
  ```
  Provider owns the rule. Dispatcher has no special "no-refresh" mode (would be over-engineered for one use case).

### ActiveProc Shape for Lust

- **D-13:** Lust proc carries the standard shape plus `lustBuffID` (numeric spellID of the actual lust buff, used by `ScanActiveTimersForCancellation` for `SHARED_LUST_BUFFS` group check). Field set:
  ```
  key = "lust"
  icon = ns:GetSpellIcon(lustSpellID)
  duration = 40
  label = C_Spell.GetSpellInfo(lustSpellID).name  (falls back to "Lust / Heroism")
  expiresAt = now + 40
  source = "debuff"
  lustBuffID = lustSpellID
  -- Preserve existing v0.2.3 fields for Display coexistence:
  spellID = "lust"
  startedAt = now
  section = entry.section or "bars"
  layoutOrder = entry.layoutOrder
  ```

### OnUnitAura Final Shape

- **D-14:** `OnUnitAura` after migration:
  ```lua
  function ns:OnUnitAura(updateInfo)
      ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo)
      -- Scan-only post-dispatch gates:
      if C_Secrets.ShouldAurasBeSecret() then
          if not ns.secretGateLogged then
              ns.secretGateLogged = true
              -- debug log
          end
          return
      end
      if updateInfo and updateInfo.isFullUpdate then return end
      if ns.previewActive then return end
      ns:ScanActiveTimersForCancellation()
  end
  ```
  Gates apply ONLY to the cancellation scan, not to provider dispatch.

### Flag Rename

- **D-15:** `ns.auraCheckBlocked` → `ns.secretGateLogged`. Purpose: one-shot debug log flag to prevent spamming "aura check blocked" messages every UNIT_AURA fire when in M+. The rename makes clear the flag is about secret-value logging, not a general gate.
- **D-16:** `ns:ClearAuraBlock` → `ns:ClearSecretGateLog`. Still called from `PLAYER_REGEN_ENABLED` and `ZONE_CHANGED_NEW_AREA` in Core.lua — resets flag so re-entering a secret context logs once again.
- **D-17:** Behavior of the flag is unchanged — purely a debug-log suppression mechanism. Still set to true on first `ShouldAurasBeSecret()` returning true in a session, cleared on combat-end/zone-change.

### Data Location (Hybrid Move, per Phase 18 precedent)

- **D-18:** Move from BuffEngine.lua to Providers.lua (alongside LustProvider):
  - `ns.SATED_DEBUFF_TO_LUST` (already namespace-exported; move verbatim)
  - `SHARED_LUST_BUFFS` — local in BuffEngine today; move to Providers.lua and export as `ns.SHARED_LUST_BUFFS` (NEW export)
  - `ns.CLASS_LUST_SPELL` (already namespace-exported; move verbatim)
  - `GetHunterLustSpell()` helper (local — move alongside CLASS_LUST_SPELL usage)
- **D-19:** KEEP in BuffEngine.lua for Phase 19:
  - `ScanActiveTimersForCancellation` (reads `ns.SHARED_LUST_BUFFS` via namespace after move)
  - `secretGateLogged` flag + `ClearSecretGateLog` function (infrastructure, not provider-specific)
- **D-20:** Rationale: matches Phase 18 hybrid split. Data colocated with its provider; cross-cutting infrastructure stays in BuffEngine.

### What BuffEngine Loses

- **D-21:** Delete from BuffEngine.lua entirely:
  - `ns:StartLustTimer` function (~lines 537-568) — logic moves to LustProvider:OnTrigger
  - Inline LUST-01 block in `OnUnitAura` (~lines 574-584) — replaced by dispatcher call
  - `SATED_DEBUFF_TO_LUST` table (if local — already on ns)
  - `SHARED_LUST_BUFFS` local table
  - `CLASS_LUST_SPELL` table (if local — already on ns)
  - `GetHunterLustSpell` helper

### Display Integration

- **D-22:** No Display.lua changes needed in Phase 19. Display already reads `timer.key or timer.spellID` after Phase 18. Lust procs emit both `key="lust"` and `spellID="lust"` for coexistence.

### Claude's Discretion

- Exact placement within Providers.lua (after PotProvider, before UserSpellProvider, matching ns.providers order)
- Whether to inline `GetHunterLustSpell` into a local within the LustProvider mixin, or keep as module-level local
- Debug log wording for the renamed `ClearSecretGateLog` (cosmetic)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research
- `.planning/research/SUMMARY.md` — milestone synthesis, phase 19 recommendations
- `.planning/research/STACK.md` — CreateFromMixins pattern
- `.planning/research/FEATURES.md` — 4-buff-type comparison, lust ordering constraint
- `.planning/research/ARCHITECTURE.md` — integration points
- `.planning/research/PITFALLS.md` — PITFALL-4 (preview regression), PITFALL-6 (LUST-01 ordering)

### Prior phase context
- `.planning/phases/18-trinketprovider-potprovider-buffengine-dispatch/18-CONTEXT.md` — D-01 to D-20 locked decisions (provider factoring, data location hybrid, dispatcher semantics, cancellation scan pattern)
- `.planning/phases/17-provider-skeleton-userspellprovider/17-01-SUMMARY.md` — base mixin contract

### Project docs
- `CLAUDE.md` — stylua required, COMBAT_LOG_EVENT_UNFILTERED disabled, install.bat deploy
- `.planning/REQUIREMENTS.md` — PROV-01 (all four providers), LIFE-02 (cancellation reads source/castSpellID/lustBuffID)

### Code files to read
- `Providers.lua` — extension target; understand existing mixins, dispatcher, eventToProviders map
- `BuffEngine.lua` — read FULLY: `StartLustTimer` (~537), `OnUnitAura` (~570), `ScanActiveTimersForCancellation` (read `SHARED_LUST_BUFFS`), data tables, flag usage
- `Core.lua` — event registration, `ns:ClearAuraBlock` call sites (PLAYER_REGEN_ENABLED, ZONE_CHANGED_NEW_AREA)
- `CDMTab.lua` — uses `ns.CLASS_LUST_SPELL` for Suggested section icon (grep for it; ensure namespace read still works after move)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SpellProviderBaseMixin` + `CreateFromMixins` pattern — LustProvider extends like the other three
- `ns:DispatchEventToProviders` — already correctly writes `ns.activeTimers[proc.key] = proc`, no changes needed
- `eventToProviders` map rebuild — picks up LustProvider automatically once registered and declaring `{ "UNIT_AURA" }`
- `C_Spell.GetSpellInfo(lustSpellID).name` for label fallback — same pattern as TrinketProvider/PotProvider

### Established Patterns (from Phases 17-18)
- Proc shape with both `key` and `spellID` for Display coexistence
- `source` field: `"cast"` for spell-triggered, `"debuff"` for aura-triggered (lust)
- No-restart guard pattern can reference Phase 18's reproc overwrite — lust is the inverse (DON'T overwrite if still active)
- Namespace export pattern for external readers (`ns.SHARED_LUST_BUFFS` mirrors Phase 18's `ns.TRINKET_SPELLS`)

### Integration Points
- Core.lua event router `UNIT_AURA` branch → calls `ns:OnUnitAura(updateInfo)` (unchanged)
- Core.lua `ns:ClearAuraBlock()` call sites in PLAYER_REGEN_ENABLED and ZONE_CHANGED_NEW_AREA handlers — must update to `ns:ClearSecretGateLog()`
- CDMTab.lua reads `ns.CLASS_LUST_SPELL` for the Suggested section's class-specific lust icon — verify namespace read still resolves after move

### Preserved Functions (plan must NOT touch)
- `OnUnitAura` signature (still receives updateInfo from Core.lua)
- `ScanActiveTimersForCancellation` core logic — only the `SHARED_LUST_BUFFS` reference changes from local to namespace
- `StartAllPreviewTimers`, `ClearAllTimers` (PITFALL-4 — Phase 21 territory)
- All Trinket/Pot/UserSpell provider code (locked in Phases 17-18)

</code_context>

<specifics>
## Specific Ideas

- User rejected dispatcher-level gate logic — providers are fully self-governing. Dispatcher stays "dumb and uniform" — this is a **hard architectural principle** carried forward from Phase 18 and reinforced in Phase 19 discussion.
- User wants preview-mode rewrite later: fill non-running, preserve running, don't overwrite active procs. Phase 19 prepares by removing the `previewActive` guard from lust detection; Phase 21 will implement the full additive-preview logic (LIFE-03 scope).
- `auraCheckBlocked` flag: it's ONLY about secret-gate debug logging, not a real gate. Rename to `secretGateLogged` so the name reflects reality.
- Lust data tables follow the same hybrid move pattern established in Phase 18 — colocation with provider, namespace exports preserved for external readers.

</specifics>

<deferred>
## Deferred Ideas

- **Full `StartAllPreviewTimers` rewrite to additive/preserve-running pattern** — Phase 21 / LIFE-03 scope. Phase 19 just removes the `previewActive` guard from LustProvider in anticipation.
- **Shared "gate-aware aura reader" helper for hypothetical future providers** — no such provider exists today. If needed in the future, extract at that time. Phase 19 does not build speculative infrastructure.
- **Delete `secretGateLogged` flag entirely** — considered. User opted to rename instead. Keep single-shot logging behavior for debug sanity.
- **Inline `OnSpellCastSucceeded` / `OnUnitAura` into Core.lua event router** — cosmetic cleanup, no behavioral benefit. Low priority, defer indefinitely.

</deferred>

---

*Phase: 19-lustprovider-unit-aura-dispatch*
*Context gathered: 2026-04-21*
