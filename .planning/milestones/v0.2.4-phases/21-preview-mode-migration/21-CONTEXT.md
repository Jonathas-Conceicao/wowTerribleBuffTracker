# Phase 21: Preview Mode Migration - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewrite `StartAllPreviewTimers` and `ClearAllTimers` to use the **additive preview** pattern. Preview procs live in a separate `ns.previewTimers` table; real procs remain in `ns.activeTimers`. Preview fills only slots with no active real proc. `ns:GetActiveTimers` merges both tables with real procs winning priority per key. Fixes both the trinket/pot 0-second preview bug (LIFE-03) AND the pre-existing mid-CDM real cast loss bug discovered in Phase 20 verification.

**In scope:**
- Create `ns.previewTimers = {}` (new separate storage)
- Rewrite `StartAllPreviewTimers`: skip slots with active real procs; use `ns:GetDisplayInfoForKey(key)` as sole data source; write to `ns.previewTimers` (not `ns.activeTimers`)
- Rewrite `ClearAllTimers`: `wipe(ns.previewTimers)`; no snapshot/restore
- Delete `savedPreviewTimers` local in BuffEngine.lua
- Delete `ns.previewActive` flag (no remaining callers after OnUnitAura guard removed)
- Delete `OnUnitAura` line: `if ns.previewActive then return end`
- Rewrite `ns:GetActiveTimers()`: merge `ns.activeTimers` + `ns.previewTimers` with real-priority, sort by expiry, filter expired
- Human verification of: trinket/pot preview shows correct durations; mid-preview real cast displays correctly; CDM close preserves real procs; preview doesn't double-up when sections rebuild

**Out of scope (phase boundary):**
- Display.lua / CDMTab.lua consumer migrations (Phases 22-23)
- Tooltip consolidation (Phase 22)
- Orphan removal of shim wrappers — `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` stay until Phase 24
- Changes to provider GetDisplayInfo or RefreshAtRest implementations (Phase 20 scope, already shipped)

</domain>

<decisions>
## Implementation Decisions

### Storage Separation

- **D-01:** Create new `ns.previewTimers = {}` table at BuffEngine module scope. Separate from `ns.activeTimers`. No shared state.
- **D-02:** `ns.activeTimers` holds ONLY real procs (source="cast" or "debuff"). No preview procs ever written to it.
- **D-03:** `ns.previewTimers` holds ONLY preview procs. No `source` field (or we may omit it entirely — cosmetic).
- **D-04:** Table separation provides identity — no need for explicit `isPreview = true` flag or `source = "preview"` marking. The table an entry lives in IS its kind.

### Merge Priority

- **D-05:** Real procs in `ns.activeTimers` ALWAYS win over preview procs in `ns.previewTimers` for the same key. Confirmed by user: "running timers are the priority; if we DO have a preview running, and a trinket is used, it should show the actual proc instead."
- **D-06:** Merging happens inside `ns:GetActiveTimers()` (the read API Display uses). Iterate preview first, then overlay active. Same-key collisions resolve to activeTimers' entry. Filter expired. Sort by remaining time (existing behavior).

### Preview Data Source

- **D-07:** `StartAllPreviewTimers` uses `ns:GetDisplayInfoForKey(key)` as the SOLE source of icon, label, duration, spellID. No direct reads of `entry.label` or `ns:ResolveSuggestedSpellID` from the caller.
- **D-08:** User decision: "provider should own everything, this should be cleaner in code as well. We wanna have a straightforward logic there, specially outside of Provider." Provider internals (e.g., `UserSpellProvider.GetDisplayInfo`) still read `entry.label` for user customization — that's provider-internal concern, not caller's problem.

### StartAllPreviewTimers Final Shape

- **D-09:** New implementation:
  ```lua
  function ns:StartAllPreviewTimers()
      wipe(ns.previewTimers)
      local now = GetTime()
      for key, entry in pairs(ns.db.trackedBuffs) do
          if entry.section ~= "hidden" then
              -- Skip if real proc already running (D-05 priority preserved at insertion time)
              local real = ns.activeTimers[key]
              if not (real and real.expiresAt > now) then
                  local info = ns:GetDisplayInfoForKey(key)
                  if info then
                      ns.previewTimers[key] = {
                          key = key,
                          spellID = info.spellID, -- numeric, for tooltip/display
                          icon = info.icon,
                          label = info.label,
                          duration = info.duration,
                          expiresAt = now + info.duration,
                          startedAt = now,
                          section = entry.section,
                          layoutOrder = entry.layoutOrder,
                          -- NO source field, NO lustBuffID, NO castSpellID — preview-only
                      }
                  end
              end
          end
      end
      if ns.UpdateDisplay then ns:UpdateDisplay() end
  end
  ```
- **D-10:** `spellID` field on preview proc is numeric (from `info.spellID`). This lets Display's tooltip handler use `GameTooltip:SetSpellByID(proc.spellID)` uniformly without distinguishing preview vs real.

### ClearAllTimers Final Shape

- **D-11:** New implementation:
  ```lua
  function ns:ClearAllTimers()
      wipe(ns.previewTimers)
      if ns.UpdateDisplay then ns:UpdateDisplay() end
  end
  ```
- **D-12:** No snapshot, no restore, no flag flip. Real procs in `ns.activeTimers` untouched.

### Deletions

- **D-13:** Delete `savedPreviewTimers` local at BuffEngine top of file. All references disappear.
- **D-14:** Delete `ns.previewActive` flag. Remove its declaration at top of BuffEngine.lua.
- **D-15:** Delete the `if ns.previewActive then return end` line from `OnUnitAura` (currently blocks `ScanActiveTimersForCancellation` during preview). With separate tables, the scan naturally ignores previews (they're in `ns.previewTimers` which the scan doesn't iterate).
- **D-16:** Verify no other callers read `ns.previewActive` anywhere in the codebase before deletion. Plan task must include repo-wide grep.

### GetActiveTimers Rewrite

- **D-17:** `ns:GetActiveTimers()` MUST merge both tables and apply priority. Implementation:
  ```lua
  function ns:GetActiveTimers()
      local now = GetTime()
      local result = {}

      -- 1. Preview entries first (filter expired)
      for key, proc in pairs(ns.previewTimers) do
          if proc.expiresAt > now then
              result[key] = proc
          else
              ns.previewTimers[key] = nil -- lazy cleanup
          end
      end

      -- 2. Real active entries override previews for same key
      for key, proc in pairs(ns.activeTimers) do
          if proc.expiresAt <= now then
              ns.activeTimers[key] = nil -- lazy cleanup
          else
              result[key] = proc
          end
      end

      -- 3. Flatten to sorted list (by expiresAt ascending, shortest first)
      local sorted = {}
      for _, proc in pairs(result) do
          table.insert(sorted, proc)
      end
      table.sort(sorted, function(a, b) return a.expiresAt < b.expiresAt end)
      return sorted
  end
  ```
- **D-18:** Callers of `ns:GetActiveTimers()` (Display.lua primarily) see no interface change — still get a sorted list. Merge logic is internal.

### ScanActiveTimersForCancellation Preservation

- **D-19:** `ScanActiveTimersForCancellation` stays unchanged. It iterates `ns.activeTimers` only — previews are now in a separate table and invisible to it. The old `not ns.previewActive` guard in OnUnitAura becomes unnecessary.
- **D-20:** No preview entry ever has `source = "cast"` or `source = "debuff"`, so even if a future bug leaked a preview into `ns.activeTimers`, the scan's branch logic would skip it (neither branch matches).

### Mid-Preview Real Cast (the bug we're fixing)

- **D-21:** Scenario walkthrough (user confirmed expected behavior):
  1. User opens `/tbt` → `StartAllPreviewTimers` fills `ns.previewTimers["trinket"]` (preview proc)
  2. User casts a trinket mid-CDM → `TrinketProvider:OnTrigger` writes `ns.activeTimers["trinket"]` (real proc)
  3. `ns:GetActiveTimers()` merge → real proc wins for key "trinket" → Display shows real timer
  4. User closes CDM → `ClearAllTimers` wipes `ns.previewTimers` only → real proc stays → continues counting to completion
- **D-22:** This fix REQUIRES separate tables. The old single-table wipe+restore pattern couldn't handle this because it snapshotted at CDM-open time and restored at CDM-close time — any real cast in between was lost.

### Section Rebuilds

- **D-23:** CDMTab calls `ns:StartAllPreviewTimers()` on every section rebuild (not just initial CDM open). The NEW StartAllPreviewTimers wipes `ns.previewTimers` each call but NEVER touches `ns.activeTimers` — real procs are fully protected from rebuilds. Matches user intent.

### Claude's Discretion

- Whether to add a defensive nil check on `info = ns:GetDisplayInfoForKey(key)` return (provider might legitimately return nil for unknown keys)
- Exact field set on preview proc — the example shows a sensible minimum; planner may add/remove fields based on what Display expects
- Whether to preserve any debug-log prints tied to preview start/end (low priority)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Research
- `.planning/research/SUMMARY.md` — milestone synthesis
- `.planning/research/PITFALLS.md` — PITFALL-4 (preview regression) — now RESOLVED BY this phase

### Prior phase context
- `.planning/phases/20-getpreviewinfo-dispatch-helper/20-CONTEXT.md` — ns:GetDisplayInfoForKey API that Phase 21 consumes
- `.planning/phases/19-lustprovider-unit-aura-dispatch/19-CONTEXT.md` — LUST-01 preserved by architecture; provider-internal previewActive guard removed
- Phase 20 VERIFICATION identified the mid-CDM real-cast-loss bug Phase 21 fixes

### Project docs
- `CLAUDE.md` — stylua after Lua edits
- `.planning/REQUIREMENTS.md` — LIFE-03 (preview non-zero durations for all buff types including trinket/pot)

### Code files to read
- `BuffEngine.lua` — read FULLY. Key targets:
  - Top locals: `savedPreviewTimers` (line ~9), `ns.previewActive` declaration (line ~5)
  - `ns:StartAllPreviewTimers` (~line 295-363)
  - `ns:ClearAllTimers` (~line 365-381)
  - `ns:GetActiveTimers` (~line 275 area) — needs merge logic
  - `ns:OnUnitAura` — has `if ns.previewActive then return end` guard to delete
  - `ScanActiveTimersForCancellation` — VERIFY it doesn't read ns.previewActive or ns.previewTimers
- `Providers.lua` — read briefly. Confirm no provider reads `ns.previewActive` (Phase 19 D-11 locked this but verify).
- `Core.lua` — read briefly. Verify no `ns.previewActive` reads outside BuffEngine.
- `CDMTab.lua` — DO NOT modify. Verify `StartPreview` calls `ns:StartAllPreviewTimers()` and `ns:ClearAllTimers()` unchanged (function names stay).
- `Display.lua` — DO NOT modify. Verify it calls `ns:GetActiveTimers()` and consumes the returned sorted list uniformly (no distinction between preview and real inside Display).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:GetDisplayInfoForKey(key)` from Phase 20 — returns `{ icon, label, duration, spellID }`. Sole data source for preview content.
- Provider dispatch already handles all 4 buff types uniformly.

### Established Patterns (from Phases 17-20)
- Dumb dispatcher, self-governing providers
- Namespace exports for cross-file table access
- Separate state stores for distinct concerns (e.g., Phase 19 split lust data colocated with provider)
- Minimal cache / single source of truth (Phase 20 D-13)

### Integration Points
- CDMTab.lua's `StartPreview` — function name stays; internal behavior of `StartAllPreviewTimers` changes
- Display.lua's consumption of `ns:GetActiveTimers()` — interface unchanged; internal merge logic added

### Preserved Functions
- `ns:GetDisplayInfoForKey` (Phase 20)
- `ns:RefreshMetaIcons` thin wrapper (Phase 20)
- All 4 providers' methods
- `ScanActiveTimersForCancellation` (core logic unchanged; only OnUnitAura guard deleted)
- Core.lua event registration
- Schema version 3
- Display.lua, CDMTab.lua — zero edits in Phase 21

### Behavior Changes (user-facing)
- Trinket/pot preview bars show REAL durations (20s/30s/etc.) instead of 0-second (LIFE-03 fix)
- Mid-CDM real casts persist after CDM close (user-identified bug fixed as side effect)
- Preview doesn't overwrite active procs (already locked in Phase 19; now enforced architecturally)

</code_context>

<specifics>
## Specific Ideas

- User explicitly rejected the "absence of source field" and "explicit source=preview" approaches in favor of **separate tables**. Rationale: cleaner boundary, `ScanActiveTimersForCancellation` naturally ignores previews without guard branches.
- User locked **real-priority merge** with explicit language: "running timers are the priority; if we DO have a preview running, and a trinket is used, it should show the actual proc instead."
- User locked **provider-owned data**: "provider should own everything, this should be cleaner in code as well. We wanna have a straightforward logic there, specially outside of Provider." No DB-vs-provider merging at caller level.
- User locked **delete previewActive flag entirely**: stale debt from the old wipe-restore hack. No justification to keep it post-refactor.

</specifics>

<deferred>
## Deferred Ideas

- Display.lua migration (Phase 22, DISP-01) — consumes new merged `ns:GetActiveTimers` output uniformly
- CDMTab.lua migration (Phase 23, DISP-02) — may need inspection of ghost-icon drag code paths
- Tooltip consolidation (Phase 22, DISP-03)
- Shim removal (Phase 24, DISP-04) — ns:ResolveSuggestedSpellID et al.
- Rename `ns:RefreshMetaIcons` → something clearer (Phase 24)

</deferred>

---

*Phase: 21-preview-mode-migration*
*Context gathered: 2026-04-21*
