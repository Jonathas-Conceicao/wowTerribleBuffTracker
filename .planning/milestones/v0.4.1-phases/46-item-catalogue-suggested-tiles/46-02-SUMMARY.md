---
phase: 46-item-catalogue-suggested-tiles
plan: 02
subsystem: ui
tags: [wow-addon, lua, c_item, cooldown-manager, event-dispatch, secret-values]

# Dependency graph
requires:
  - phase: 46-item-catalogue-suggested-tiles
    plan: 01
    provides: ns.ITEM_KEY_PREFIX, ns:ItemKeyItemID, ns:RefreshItemCatalogue and its five accessors
provides:
  - "ns:ItemDisplayInfo(itemID) -- pooled { icon, label, duration, spellID } for an item: key"
  - "item: branch in ns:GetDisplayInfoForKey, placed before the CooldownKeySpellID reject"
  - "BAG_UPDATE registration + dirty-flag dispatch branch in Core.lua"
  - "ns:RequestItemCatalogueRebuild() -- CDMTab.lua's per-frame-coalesced rebuild consumer"
affects: [46-03-suggested-tile-render, 47-tracker-creation-from-tile]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Late-binding through ns.<FieldName> for cross-file forward references (Providers.lua calling into CDMTab.lua, which loads after it) -- same idiom as ns:RacialCooldownSeed"
    - "C_Timer.After(0, ...) + a scheduled-flag guard as the per-frame burst coalescer for a dirty-flag rebuild"
    - "Event handler sets a dirty flag only; a separate consumer (gated on ns.configOpen) decides whether/when to act"

key-files:
  created: []
  modified:
    - Providers.lua
    - Core.lua
    - CDMTab.lua

key-decisions:
  - "Task 2's flavour-token baseline was 3, not the plan's assumed 1 (three non-comment lines make up the single licensed v0.4.0 buildInterfaceVersion/isForeverBuild check). Per the plan's own contingency clause (\"If the baseline count differs from 1, record the pre-edit baseline in the SUMMARY and assert equality instead\"), asserted post-edit count == 3, which held."
  - "ns:ItemDisplayInfo treats absence from BOTH ns:ItemCatalogueIcon and ns:ItemCatalogueCount as catalogue-absence (returns nil) -- the plan's own phrasing named ns:ItemCatalogueIcon specifically alongside itemID absence; using both accessors is the closest literal reading and is self-consistent with the catalogue builder, which only ever populates icon/count together with adding the itemID to the ID list."
  - "ns:RequestItemCatalogueRebuild is exposed via a plain field assignment (ns.RequestItemCatalogueRebuild = RequestItemCatalogueRebuild) rather than function ns:RequestItemCatalogueRebuild(...) syntax, matching the plan's own exact phrasing (\"Expose that local function on the namespace as...\") and satisfying the verify gate's alternation pattern."

requirements-completed: [ITEM-01, ITEM-10]

# Metrics
duration: 3min
completed: 2026-09-24
---

# Phase 46 Plan 02: Scan Trigger, Dirty Flag & item: Key Dispatch Summary

**Wires Plan 01's bag-derived catalogue to its three integration points -- CDM-open scan, a `BAG_UPDATE`-driven dirty flag coalesced to one rebuild per frame, and an `item:` branch in `ns:GetDisplayInfoForKey` that resolves an item's own icon/label instead of falling through to `UserSpellProvider` -- nothing renders yet.**

## Performance

- **Duration:** ~3 min (three tasks, each single-pass)
- **Started:** 2026-09-24T07:59:38-03:00 (first commit)
- **Completed:** 2026-09-24T08:01:27-03:00 (last commit)
- **Tasks:** 3/3 completed
- **Files modified:** 3

## Accomplishments

- `ns:ItemDisplayInfo(itemID)` added to `Providers.lua`: reads the catalogue's icon/count caches, guards `C_Item.GetItemNameByID`'s return `issecretvalue()`-then-`type()`, and returns a pooled table via `ns:AcquireDisplayInfo` -- zero allocation on the render/hover path, `spellID` always nil, `duration` always 0 (cooldown reads are Phase 47)
- `ns:GetDisplayInfoForKey` learns the `item:` namespace: the `ns:ItemKeyItemID(key)` branch sits before the `ns:CooldownKeySpellID` reject, so an `item:` key can never fall through to `UserSpellProvider` and be misread as a spellID (46-RESEARCH.md Pitfall 4)
- `BAG_UPDATE` registered through the existing `TryRegisterEvent` capability helper in `Core.lua`, beside the other bag-family events; its dispatch branch calls `ns:MarkItemCatalogueDirty()` and nothing else -- no rebuild from the event handler
- `StartPreview` (`CDMTab.lua`) now calls `ns:RefreshItemCatalogue()` unconditionally, after `ns:RefreshProvidersAtRest()` and before `ns:RefreshTBTSections()`, so the cache is warm before Suggested draws
- `ns:RequestItemCatalogueRebuild()` added to `CDMTab.lua`: coalesces a `BAG_UPDATE` burst into at most one `C_Timer.After(0, ...)` rebuild per frame, gated on `ns.configOpen`, and wired from `Providers.lua`'s `ns:MarkItemCatalogueDirty()` through a guarded `ns.RequestItemCatalogueRebuild` field (late-binding idiom, since `Providers.lua` loads before `CDMTab.lua`)

## Task Commits

Each task was committed atomically:

1. **Task 1: Teach ns:GetDisplayInfoForKey the item: key** - `810f520` (feat)
2. **Task 2: Register BAG_UPDATE and dirty-flag the catalogue in Core.lua** - `ed1a4c5` (feat)
3. **Task 3: Scan on CDM open and coalesce the dirty rebuild in CDMTab.lua** - `10d380d` (feat)

**Plan metadata:** committed alongside this summary.

## Files Created/Modified

- `Providers.lua` -- added `ns:ItemDisplayInfo(itemID)` beside Plan 01's catalogue block; extended `ns:GetDisplayInfoForKey` with the `item:` branch; extended `ns:MarkItemCatalogueDirty()` to late-bind into `ns:RequestItemCatalogueRebuild`
- `Core.lua` -- registered `BAG_UPDATE` via `TryRegisterEvent`; added the `elseif event == "BAG_UPDATE" then ns:MarkItemCatalogueDirty() end` dispatch branch adjacent to `BAG_UPDATE_COOLDOWN`
- `CDMTab.lua` -- `StartPreview` gained one `ns:RefreshItemCatalogue()` call; added the `itemCatalogueRebuildScheduled` flag, `RequestItemCatalogueRebuild()`, and `ns.RequestItemCatalogueRebuild` exposure

## Decisions Made

- **Task 2 flavour-token baseline.** The plan's automated gate asserted the post-edit non-comment flavour-token count equals `1`, but the pre-edit baseline measured `3` (the single licensed `buildInterfaceVersion`/`buildVersionIsNumber`/`isForeverBuild` check spans three lines, each independently matching the grep pattern). The plan's own acceptance criteria anticipated this ("If the baseline count differs from 1, record the pre-edit baseline in the SUMMARY and assert equality instead"), so the baseline (3) was recorded and equality was asserted against it instead -- post-edit count is still 3, confirming Task 2 added no second flavour check.
- **`ns:ItemDisplayInfo`'s catalogue-absence test.** Implemented as "return nil when both `ns:ItemCatalogueIcon(itemID)` and `ns:ItemCatalogueCount(itemID)` are nil" rather than adding a new membership accessor. The catalogue builder (Plan 01) only ever adds an itemID to the ID list together with attempting both icon and count reads, so an itemID genuinely absent from the catalogue has neither cached, while an itemID present but with one field unreadable at scan time (e.g. a secret count) still resolves correctly via the other.

## Deviations from Plan

### Rule 3 equivalent -- documented gate anomaly (not auto-fixed, not edited)

**1. Task 1's whole-file line-order verify assertion is a false negative caused by an unrelated pre-existing text collision.**

- **Found during:** Task 1 verification.
- **What the gate does:** `test "$(grep -n 'ItemKeyItemID' Providers.lua | head -1 | cut -d: -f1)" -lt "$(grep -n 'CooldownKeySpellID(key)' Providers.lua | head -1 | cut -d: -f1)"` -- a whole-file, first-occurrence-anywhere comparison.
- **The problem:** `Providers.lua` already contained the literal substring `CooldownKeySpellID(key)` at line 185, inside `UserSpellProviderMixin:GetDisplayInfo` (`spellID = ns:CooldownKeySpellID(key)`) -- code that predates this phase entirely and is unrelated to the ordering property the gate is trying to test. `grep -n ... | head -1` always picks up this line 185 occurrence, which sits far above where `ns:GetDisplayInfoForKey` is even defined (~line 1260). Since the new `ItemKeyItemID` branch necessarily lives *inside* `ns:GetDisplayInfoForKey` (which is defined after `UserSpellProviderMixin`, because it references the `UserSpellProvider` local that does not exist yet at line 185), no compliant implementation can ever place its line number below 185. The plan's own `46-RESEARCH.md` code example (`Dispatch extension point`) recommends the exact same branch structure that was implemented here, and would produce this identical false negative.
- **What was verified instead:** the actual load-bearing property -- that inside `ns:GetDisplayInfoForKey`, the `ns:ItemKeyItemID(key)` branch (line 1270) sits before the `if not ns:CooldownKeySpellID(key) then` reject (line 1280) -- was confirmed directly by reading the function body (see command output in this session). This is the property 46-RESEARCH.md Pitfall 4 and the threat register's T-46-05 actually care about, and it holds.
- **Action taken:** implemented the code exactly as specified (matching 46-RESEARCH.md's own recommended pattern) and did **not** edit the plan's verify command, per the executor's standing instruction to stop-and-report rather than weaken a gate believed to be wrong. Flagging this here for human review rather than silently treating the gate as passed.
- **Files affected:** `Providers.lua` (no change beyond the planned edit; this is a verification-command issue, not a code issue).
- **Commit:** `810f520`.

No other deviations. Every other automated assertion in all three tasks' verify gates passed as written, including `stylua --check .` and `git ls-files --eol` on all three touched files.

## Issues Encountered

None beyond the gate anomaly documented above.

## User Setup Required

None -- no external service configuration required.

## Known Stubs

None. `ns:ItemDisplayInfo` and the `item:` dispatch branch are fully functional against the existing catalogue; the scan trigger and dirty-flag coalescing are live. Nothing in this phase boundary renders a tile yet (Plan 03's explicit scope), which is a documented "not yet wired to the render path" state, not a stub.

## Threat Flags

None. All new API-read surface (`C_Item.GetItemNameByID`'s return) was already enumerated in the plan's `<threat_model>` (T-46-07) and mitigated as specified (`issecretvalue()` before `type()`, degrading to the `"Item " .. itemID` fallback label). No new network endpoint, auth path, file-access pattern, or schema change was introduced.

## Next Phase Readiness

- `ns:ItemDisplayInfo(itemID)` and the `item:` branch in `ns:GetDisplayInfoForKey` exist with the exact shapes Plan 03 needs for tile icon/tooltip resolution.
- `ns:RequestItemCatalogueRebuild()` (file-local in `CDMTab.lua`, exposed as `ns.RequestItemCatalogueRebuild`) is the coalescing consumer Phase 47 and Plan 03 should reuse rather than invent a second one.
- The catalogue is live: opening the CDM rebuilds it before Suggested is drawn, and a `BAG_UPDATE` burst while the CDM is open produces at most one rebuild on the next frame (zero while closed).
- `AddSuggestedTracker` (`CDMTab.lua`) remains byte-unchanged, confirmed by `git diff` across this plan's three commits -- an `item:` key still no-ops through it, exactly as 46-RESEARCH.md Pitfall 3 documents as accepted, in-scope-for-Phase-47 behaviour.
- No blockers for Plan 03. The one open item is the documented gate anomaly above, which needs no code change -- only awareness that the ordering property it intends to test must be verified by reading `ns:GetDisplayInfoForKey` directly rather than trusting the whole-file grep comparison.

---
*Phase: 46-item-catalogue-suggested-tiles*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `Providers.lua`
- FOUND: `Core.lua`
- FOUND: `CDMTab.lua`
- FOUND: `.planning/phases/46-item-catalogue-suggested-tiles/46-02-SUMMARY.md`
- FOUND: commit `810f520` (Task 1)
- FOUND: commit `ed1a4c5` (Task 2)
- FOUND: commit `10d380d` (Task 3)
