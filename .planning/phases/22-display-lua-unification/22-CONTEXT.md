# Phase 22: Display.lua Unification + Proc Shape Cleanup - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Unify Display.lua to consume ONLY the normalized ActiveProc shape. Drop all type-specific branches, metaSlot fallbacks, and duplicated icon resolution chains. Export a shared tooltip handler (`ns:ShowBuffTooltip`). As the enabling cleanup, **simplify the proc shape itself**: collapse `castSpellID`/`lustBuffID`/string-`spellID` coexistence into a single numeric `proc.spellID`, add a unified `proc.aliveBuffs` list that replaces the two-strategy cancellation branch, drop `proc.source` and `proc.icon`. Display caches icons frame-local by spellID.

**In scope (single coherent unit of work):**
- Proc shape redesign (touches all 4 providers + StartAllPreviewTimers + ScanActiveTimersForCancellation)
- Display.lua unification (icon derivation, tooltip consolidation, layout-loop simplification, metaIconsDirty removal)
- `ns:ShowBuffTooltip(frame, proc)` exported from Display.lua (consumed by CDMTab in Phase 23)
- `ns.SHARED_LUST_BUFFS` demoted to provider-local (no `ns.*` export)
- Trivial CDMTab.lua edit (1 line: delete `ns.metaIconsDirty = true` setter)

**Out of scope (phase boundary):**
- CDMTab.lua full migration (Phase 23) — only the 1-line dirty flag setter is deleted
- Shim removal: `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` stay as thin wrappers until Phase 24 (CDMTab still uses them in Phase 22)
- `ns.CLASS_LUST_SPELL` / `ns.GetHunterLustSpell` exports — still read by CDMTab's Suggested section, stay until Phase 23 migrates that read to `ns:GetDisplayInfoForKey("lust")`
- `ns:RefreshMetaIcons` wrapper — still called by CDMTab StartPreview, stays
- `ns.metaIcons` texture-only cache (separate from `ns.metaAtRest` which was deleted in Phase 20) — verify scope, delete if truly orphaned

</domain>

<decisions>
## Implementation Decisions

### Proc Shape (normalized)

- **D-01:** Final proc shape, 9 fields:
  ```lua
  {
      key         = <string or num>,   -- stable DB slot identifier (table-lookup identity)
      spellID     = <numeric>,         -- THE spell — drives icon, tooltip, alive-check strategy
      duration    = <seconds>,
      expiresAt   = <num>,
      startedAt   = <num>,
      section     = <string>,          -- from DB entry
      layoutOrder = <num>,             -- from DB entry
      label       = <string>,          -- provider-resolved display name
      aliveBuffs  = { <num>, ... },    -- buff spellIDs — any present = alive, none present = cancel
  }
  ```
- **D-02:** Removed from proc shape entirely:
  - `icon` — derived at Display time via `ns:GetSpellIcon(proc.spellID)`, cached on Display frame by spellID
  - `source` — no longer needed (cancellation strategy is data-driven via `aliveBuffs`)
  - `castSpellID` — redundant; `proc.spellID` is the numeric cast/detected spell
  - `lustBuffID` — replaced by `aliveBuffs` list
  - `metaSlot` — already removed in Phase 18
- **D-03:** `proc.spellID` is ALWAYS numeric after Phase 22. The Phase 18/19 coexistence where trinket/pot/lust procs stored `spellID = "trinket"` (string) for Display legacy lookup is REMOVED. Display identifies procs by `proc.key` exclusively.

### Per-provider aliveBuffs Content

- **D-04:** UserSpellProvider: `aliveBuffs = { spellID }` — single element, the user's tracked spell
- **D-05:** TrinketProvider: `aliveBuffs = { spellID }` — single element, the cast trinket's spell
- **D-06:** PotProvider: `aliveBuffs = { spellID }` — single element, the cast pot's spell
- **D-07:** LustProvider: `aliveBuffs = SHARED_LUST_BUFFS_LOCAL[detectedLustSpellID]` — multi-element (e.g., `{ 32182, 1243972 }` for Heroism + Drums sharing Exhaustion)
- **D-08:** Preview procs (written by `StartAllPreviewTimers`): `aliveBuffs = nil` or omitted — previews are in `ns.previewTimers` (separate table per Phase 21), never touched by `ScanActiveTimersForCancellation` which iterates only `ns.activeTimers`. Even if accidentally iterated, defensive check (`if not timer.aliveBuffs or #timer.aliveBuffs == 0 then skip end`) prevents cancellation.

### Unified Cancellation Strategy

- **D-09:** `ScanActiveTimersForCancellation` collapses from two branches to one:
  ```lua
  function ns:ScanActiveTimersForCancellation()
      local cancelledCount = 0
      local cancelledLabels
      for key, timer in pairs(ns.activeTimers) do
          if timer.aliveBuffs and #timer.aliveBuffs > 0 then
              local anyPresent = false
              for _, buffID in ipairs(timer.aliveBuffs) do
                  if C_UnitAuras.GetPlayerAuraBySpellID(buffID) then
                      anyPresent = true
                      break
                  end
              end
              if not anyPresent then
                  ns.activeTimers[key] = nil
                  cancelledCount = cancelledCount + 1
                  -- debug log (existing pattern — add timer.label to cancelledLabels)
              end
          end
          -- No aliveBuffs = opaque, skip (defensive)
      end
      if cancelledCount > 0 then
          -- existing debug-log + UpdateDisplay call
      end
  end
  ```
- **D-10:** No branching on `timer.source`. No lookup of `SHARED_LUST_BUFFS` from BuffEngine. Strategy is baked into the proc at creation.
- **D-11:** Defensive check: if `aliveBuffs` absent or empty, treat proc as opaque and skip cancellation. Never cancel a proc we can't verify.

### SHARED_LUST_BUFFS Demotion

- **D-12:** `SHARED_LUST_BUFFS` — currently exported as `ns.SHARED_LUST_BUFFS` for BuffEngine's cancellation scan. After Phase 22, it becomes a **module-local** inside Providers.lua (no `ns.*` export). Only LustProvider reads it (at `OnTrigger` time, to populate `proc.aliveBuffs`).
- **D-13:** `SATED_DEBUFF_TO_LUST` — already only used inside LustProvider. Remains provider-local (no change).
- **D-14:** `CLASS_LUST_SPELL` + `GetHunterLustSpell` — still read by CDMTab's Suggested section. Remain exported (`ns.*`) until Phase 23 migrates CDMTab to use `ns:GetDisplayInfoForKey("lust")` (which returns the class-specific spellID via LustProvider). Demoted in Phase 24 cleanup.

### Icon Caching on Display Side

- **D-15:** Providers do NOT compute icon textures. Proc returns only numeric `spellID`.
- **D-16:** Display frames (bar + icon) cache their icon by spellID:
  ```lua
  -- Per bar/icon update:
  if frame.cachedSpellID ~= proc.spellID then
      frame.cachedIcon = ns:GetSpellIcon(proc.spellID)
      frame.cachedSpellID = proc.spellID
  end
  frame.icon:SetTexture(frame.cachedIcon)
  ```
- **D-17:** Cache invalidation happens automatically when `proc.spellID` changes. Since `proc.spellID` is now always numeric (no string coexistence), swapping equipped trinket A → B updates `ns.previewTimers["trinket"].spellID` (via next `StartAllPreviewTimers`) → Display cache check fires → new icon resolved. No flag-based invalidation needed.

### Tooltip Handler Consolidation

- **D-18:** Export `ns:ShowBuffTooltip(frame, proc)` from Display.lua:
  ```lua
  function ns:ShowBuffTooltip(frame, proc)
      GameTooltip_SetDefaultAnchor(GameTooltip, frame)
      if proc and proc.spellID then
          GameTooltip:SetSpellByID(proc.spellID)
      else
          GameTooltip:SetText("Unknown", 1, 1, 1)
      end
      GameTooltip:Show()
  end
  ```
- **D-19:** Display's bar `OnEnter` and icon `OnEnter` handlers both call `ns:ShowBuffTooltip(self, self.proc)` — the frames store a reference to their proc (or at least the fields needed).
- **D-20:** Hide side — consolidate into `ns:HideBuffTooltip(frame)` if both handlers need symmetric cleanup, OR leave inline (tooltips hide via `GameTooltip:Hide()` — single line, not worth a helper). Planner's call.
- **D-21:** `ns:ShowBuffTooltip` is CDMTab-ready — Phase 23 migrates CDMTab tooltip call sites to use this same helper. DISP-03 satisfied in Phase 22.

### Layout Icon Source

- **D-22:** Bar layout loop (currently ~line 475-494) and icon layout loop (currently ~line 649-657) — both collapse to:
  ```lua
  local info = ns:GetDisplayInfoForKey(slot.key)
  if frame.cachedSpellID ~= info.spellID then
      frame.cachedIcon = ns:GetSpellIcon(info.spellID)
      frame.cachedSpellID = info.spellID
  end
  frame.icon:SetTexture(frame.cachedIcon)
  frame.label:SetText(info.label)
  ```
- **D-23:** Delete `GetSuggestedAtRestIcon` local helper (Display.lua line ~87-97) entirely.
- **D-24:** No more `type(key) == "string"` branches, no more `ns.GetAtRestMetaIcon/GetAtRestMetaInfo/ResolveSuggestedSpellID` call chains in Display.lua.

### metaIconsDirty Flag Removal

- **D-25:** Delete `ns.metaIconsDirty` entirely. Writers and readers:
  - **Writer:** `CDMTab.lua:20` — `ns.metaIconsDirty = true` inside StartPreview → DELETE this one line
  - **Readers:** `Display.lua:475`, `Display.lua:649` — DELETE the disjunct `or (type(slot.spellID) == "string" and ns.metaIconsDirty)`
  - **Clearer:** `Display.lua:695` — `ns.metaIconsDirty = nil` → DELETE
- **D-26:** Rationale: with numeric `proc.spellID`, cache invalidation happens naturally via spellID-change detection in the Display frame cache. Flag is redundant.

### Display.lua Other Cleanup

- **D-27:** Delete the `GetSuggestedAtRestIcon` local helper (line ~87-97).
- **D-28:** Remove all `type(self.spellID) == "string"` branches in OnEnter handlers (lines ~175, 241). Tooltip handler `ns:ShowBuffTooltip` handles any `proc.spellID` uniformly.
- **D-29:** Preserve `wipe()` accumulator pattern in `UpdateDisplay` (barTimers, iconTimers, barSlots, buffSlots module-level locals) — no per-frame allocation.
- **D-30:** Preserve pool patterns (CreateObjectPool for bars and icons).
- **D-31:** Display still reads `proc.section`, `proc.layoutOrder`, `proc.label`, `proc.duration`, `proc.expiresAt`, `proc.spellID`, `proc.key` — all uniform across buff types now.

### StartAllPreviewTimers Update

- **D-32:** Phase 21's `StartAllPreviewTimers` writes procs with `{ key, spellID (numeric from info.spellID), icon, label, duration, expiresAt, startedAt, section, layoutOrder }`. Phase 22 changes:
  - REMOVE `icon` field write (Display derives it)
  - Preview procs do NOT get `aliveBuffs` field (they're not in `ns.activeTimers`, cancellation scan never sees them)
- **D-33:** Updated preview proc:
  ```lua
  ns.previewTimers[key] = {
      key = key,
      spellID = info.spellID,
      duration = info.duration,
      expiresAt = now + info.duration,
      startedAt = now,
      label = info.label,
      section = entry.section,
      layoutOrder = entry.layoutOrder,
  }
  ```

### Provider OnTrigger Changes

- **D-34:** All 4 provider OnTrigger methods change:
  - UserSpellProvider: proc = `{ key, spellID, duration, expiresAt, startedAt, section, layoutOrder, label, aliveBuffs = { spellID } }` — drop `icon`/`castSpellID`
  - TrinketProvider: `spellID = castSpellID` (numeric cast spell, was `"trinket"`); `aliveBuffs = { spellID }`; drop `icon`/`castSpellID` duplicate/`metaSlot`
  - PotProvider: same as Trinket pattern with "pot"
  - LustProvider: `spellID = lustSpellID` (numeric, was `"lust"`); `aliveBuffs = SHARED_LUST_BUFFS_LOCAL[lustSpellID]`; drop `icon`/`lustBuffID`
- **D-35:** Provider's OnTrigger does not call `ns:GetSpellIcon` anymore — icon derivation moves to Display side.

### ns.metaIcons Check

- **D-36:** Grep for `ns.metaIcons` (separate from `ns.metaAtRest` which was deleted in Phase 20). If no live readers remain, delete the declaration in Providers.lua. If CDMTab or other code still reads it, defer deletion to Phase 23/24.

### Claude's Discretion

- Exact name of the Providers.lua-local SHARED_LUST_BUFFS (can stay `SHARED_LUST_BUFFS` as a local)
- Whether to add a `ns:HideBuffTooltip(frame)` helper or leave hide inline
- Whether the bar/icon OnEnter handlers store the proc reference on the frame (`self.proc = proc`) vs reconstruct via `ns:GetDisplayInfoForKey(self.key)` at hover time — trade-off between memory and freshness
- Order of task execution in the plan (proc shape first, then Display? or interleaved?)

</decisions>

<canonical_refs>
## Canonical References

### Research
- `.planning/research/SUMMARY.md` — milestone synthesis
- `.planning/research/PITFALLS.md` — PITFALL-7 (GC pressure — wipe() accumulator must survive)

### Prior phase contexts
- `.planning/phases/21-preview-mode-migration/21-CONTEXT.md` — separate previewTimers table (D-01 to D-23)
- `.planning/phases/20-getpreviewinfo-dispatch-helper/20-CONTEXT.md` — ns:GetDisplayInfoForKey API
- `.planning/phases/19-lustprovider-unit-aura-dispatch/19-CONTEXT.md` — LustProvider + SHARED_LUST_BUFFS origin
- `.planning/phases/18-trinketprovider-potprovider-buffengine-dispatch/18-CONTEXT.md` — castSpellID pattern (now being removed)

### Project docs
- `CLAUDE.md` — stylua required, wipe() pattern for GC discipline, CDM template reference
- `.planning/REQUIREMENTS.md` — DISP-01 (zero type-specific branches), DISP-03 (shared tooltip handler)

### Code files
- `Display.lua` — read FULLY (primary target)
- `Providers.lua` — all 4 provider OnTrigger methods change
- `BuffEngine.lua` — StartAllPreviewTimers + ScanActiveTimersForCancellation both change
- `CDMTab.lua` — read but DO NOT modify except line 20 (delete `ns.metaIconsDirty = true`)
- `Core.lua` — verify no references to deleted fields

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:GetDisplayInfoForKey(key)` — Phase 20 API, used by layout loops for at-rest placeholders
- `ns:GetSpellIcon(spellID)` — used by Display to derive icons
- `C_Spell.GetSpellInfo(spellID).name` — label resolution (inside providers)
- `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` — cancellation scan aura check
- Frame pool patterns, wipe() accumulator pattern — preserved

### Grep-confirmed metaIconsDirty sites (from tool run)
- Writer: CDMTab.lua line 20
- Readers: Display.lua lines 475, 649
- Clearer: Display.lua line 695
- All to be deleted in Phase 22

### Integration Points
- CDMTab still calls `ns:ShowBuffTooltip` (added in Phase 22) in Phase 23 migration
- CDMTab still calls `ns:RefreshMetaIcons` (unchanged) and `ns:StartAllPreviewTimers` (simplified proc shape internally but same function signature)
- Core.lua: no changes expected

### Preserved Functions
- `ns:StartAllPreviewTimers` signature unchanged (only internal proc shape tweaked)
- `ns:ClearAllTimers` unchanged
- `ns:GetActiveTimers` unchanged (but returns procs with new shape)
- `ns:DispatchEventToProviders` unchanged
- `ns:RefreshMetaIcons` unchanged
- `ns:GetDisplayInfoForKey` unchanged
- All `SUGGESTED_BUFFS` structure in BuffEngine
- CURRENT_SCHEMA_VERSION = 3

### Behavior Expected (no user-facing changes)
- Display should look IDENTICAL to Phase 21 after this phase
- Bars render the same, icons render the same, tooltips show the same info
- Cancellation still cancels correctly (including lust with group check)

</code_context>

<specifics>
## Specific Ideas

- User locked the "provider returns spellID, Display caches icon" principle explicitly: "icon SHOULD be cached, but not from a providers prespective. Display should cache the icon for the proc it received. Providers shouldn't have to lookup UI elements."
- User drove the source field elimination by asking what it's used for and proposing the aliveBuffs generalization: "We should have a second field with a small list of possible spellids/buffs and any if NONE of these buffs are present we clear... for lust, where we can detect a proc and not be sure which of two or more buffs it cooresponds too, we return a list of 2 or 3 lust buffs which might actually be the lust we detected and only if NONE of those are present we clear."
- User flagged that lust constants should be provider-internal after this refactor — confirmed by SHARED_LUST_BUFFS demotion.

</specifics>

<deferred>
## Deferred Ideas

- CDMTab.lua full migration — Phase 23 (DISP-02). Phase 22 does the minimum 1-line touch for flag removal.
- Shim removal (`ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo`) — Phase 24 (DISP-04).
- `ns.CLASS_LUST_SPELL` + `ns.GetHunterLustSpell` demotion — Phase 23 (after CDMTab migrates to `ns:GetDisplayInfoForKey`).
- `ns:RefreshMetaIcons` rename/demotion — Phase 24 cleanup.
- Icon-cache bust on spec change (hunter swapping spec changes class-aware lust spell) — LustProvider:RefreshAtRest is already a no-op per Phase 20; relies on next CDM-open refresh. Edge case acceptable.

</deferred>

---

*Phase: 22-display-lua-unification*
*Context gathered: 2026-04-21*
