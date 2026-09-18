---
phase: 14-icon-resolution-caching
plan: 02
subsystem: ui
tags: [lua, wow-addon, icon-resolution, cdm-tab, display, placeholder-fix, in-game-verification]

# Dependency graph
requires:
  - phase: 14-icon-resolution-caching
    plan: 01
    provides: ns.metaIcons, ns:RefreshMetaIcons, ns:GetAtRestMetaIcon, SUGGESTED_BUFFS getCDMIcon closures

provides:
  - CDMTab StartPreview triggers ns:RefreshMetaIcons before every preview (D-14, ICON-05)
  - Display.lua bar placeholder routes trinket/pot through GetSuggestedAtRestIcon helper (D-12)
  - Display.lua icon placeholder routes trinket/pot through GetSuggestedAtRestIcon helper (D-12)
  - Lust at-rest path preserved unchanged (D-13)
  - ICON-01, ICON-02, ICON-05, ICON-07 verified in-game

affects:
  - Phase 15 (active icon switching — at-rest baseline now correct)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GetSuggestedAtRestIcon file-local helper: linear scan of ns.SUGGESTED_BUFFS, returns nil for lust (getCDMIcon=nil), ns:GetAtRestMetaIcon(key) for trinket/pot"
    - "StartPreview-first hook: ns:RefreshMetaIcons() is the FIRST line of StartPreview — covers all call sites, not just cdmWatcher"
    - "metaIconsDirty flag: UpdateDisplay reads flag and triggers icon refresh without wiping real cast timers"
    - "Dual-index meta-slot: activeTimers keyed by both numeric spellID (cast detection, cancellation) and metaSlot string key (Display/CDMTab lookup)"

key-files:
  created: []
  modified:
    - CDMTab.lua
    - Display.lua
    - BuffEngine.lua

key-decisions:
  - "D-04 enforced: PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED hooks added during hotfix iteration were reverted — refresh on CDM open only"
  - "Tooltip/icon resolution uses buff spell (not item): item tooltips surface noisy ilvl/quality data; spell tooltip shows clean buff description"
  - "meta-slot timers dual-indexed by numeric spellID and metaSlot string key: hideWhenInactive and DB slot path both require string key; cancellation scan requires numeric spellID"
  - "StartAllPreviewTimers preserves source=cast/debuff timers on every call — not just first call"
  - "live-update hook uses UpdateDisplay + metaIconsDirty rather than StartAllPreviewTimers — avoids wiping real in-combat timers"

patterns-established:
  - "GetSuggestedAtRestIcon: nil-returning file-local helper keeps both Display call sites DRY and gate-free"
  - "Dual-index activeTimers entry: write both keys at creation, read string key for display, numeric key for aura cancellation"

requirements-completed:
  - ICON-05

# Metrics
duration: ~45min (including hotfix iteration and in-game verification)
completed: 2026-04-13
---

# Phase 14 Plan 02: CDMTab Hook + Display Placeholder Fix Summary

**CDMTab StartPreview now triggers ns:RefreshMetaIcons before every preview; Display.lua bar and icon placeholder paths route trinket/pot through GetSuggestedAtRestIcon (GetAtRestMetaIcon) instead of falling back to the Bloodlust/?-icon; verified in-game for ICON-01/02/05/07**

## Performance

- **Duration:** ~45 min (including 7 hotfix commits and in-game verification round)
- **Completed:** 2026-04-13
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint)
- **Files modified:** 3 (CDMTab.lua, Display.lua, BuffEngine.lua)

## Accomplishments

- Inserted `ns:RefreshMetaIcons()` as the first line of `StartPreview` in CDMTab.lua — covers all call sites (D-14, ICON-05)
- Added `GetSuggestedAtRestIcon` file-local helper in Display.lua: linear scan of `ns.SUGGESTED_BUFFS`, returns `ns:GetAtRestMetaIcon(key)` for trinket/pot, `nil` for lust so lust falls through unchanged (D-12/D-13)
- Fixed bar placeholder branch (lines ~444-457) to use `GetSuggestedAtRestIcon` before the `ResolveSuggestedSpellID` chain
- Fixed icon placeholder branch (lines ~601-608) to use `GetSuggestedAtRestIcon` before the `GetSpellIcon` chain
- Resolved 7 defects discovered during in-game verification (see Deviations)
- Human checkpoint approved: Suggested + Bars/Buffs HUD show resolved buff spell icon; lust preserved; real cast timer runs animated countdown bar in-combat/out-of-combat with CDM open or closed; icons refresh on CDM open (no event hooks)

## Task Commits

Each planned task was committed atomically:

1. **Task 1: Hook ns:RefreshMetaIcons into CDMTab StartPreview** - `d3b7b2f` (feat)
2. **Task 2: Fix Display.lua bar/icon placeholder paths** - `696575a` (feat)
3. **Task 3: Human-verify checkpoint** — in-game verification (no commit; approved by user)

### Hotfix Commits (deviation iteration during verification):

| Hash | Description |
|------|-------------|
| `c1b78f0` | fix: route meta-slot icons through GetAtRestMetaIcon in all render paths (CDMTab section + drag ghost + StartAllPreviewTimers) |
| `7852c78` | fix: item tooltip + correct duration/description + live CDM updates (cache reshaped to ns.metaAtRest {icon,itemID,duration}) |
| `28d2dba` | fix: resolve at-rest icon + tooltip to buff spell (not item) — item tooltips surfaced noisy ilvl/quality |
| `bed32a3` | fix: live-update hook replaced StartAllPreviewTimers with UpdateDisplay + metaIconsDirty flag; fixed placeholder icon cache for live swap |
| `16dfe5c` | fix: StartAllPreviewTimers preserves source=cast/debuff real cast timers on every call (not just first) |
| `20550f5` | fix: REMOVE PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED hooks — violated D-04 "no event hooks" decision |
| `1235344` | fix: index meta-slot timers by BOTH numeric spellID and metaSlot key (hideWhenInactive + DB slot paths) |

## Files Created/Modified

- `CDMTab.lua` — StartPreview hook for ns:RefreshMetaIcons; hotfixes for meta-slot icon routing in CDM section, drag ghost, StartAllPreviewTimers preservation, live-update hook
- `Display.lua` — GetSuggestedAtRestIcon helper + bar and icon placeholder path fixes; dual-index lookup for meta-slot timers
- `BuffEngine.lua` — cache reshaped to `ns.metaAtRest {icon, itemID, duration}`; tooltip/icon resolution switched to buff spell (not item); metaIconsDirty flag added; StartAllPreviewTimers real-timer preservation

## Decisions Made

- **D-04 re-enforced:** PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED event hooks were briefly added during hotfix iteration (7852c78) then explicitly reverted (20550f5) per user feedback. Icons refresh on CDM open only.
- **Spell tooltip over item tooltip:** Item tooltip exposed ilvl/quality clutter. Buff spell tooltip shows clean name + "TBT Duration: Xs" + category description. Implemented in 28d2dba.
- **Dual-index activeTimers:** Meta-slot timer entries written at both the numeric spellID (for aura scan cancellation) and the string metaSlot key (for Display/CDMTab hideWhenInactive and DB slot lookups). Implemented in 1235344.
- **StartAllPreviewTimers preserves real timers:** Every call checks `source == "cast"` or `source == "debuff"` and skips those entries — prevents preview from wiping an in-combat active timer. Implemented in 16dfe5c.
- **metaIconsDirty flag + UpdateDisplay:** Live CDM icon swap uses a dirty flag polled by UpdateDisplay rather than calling StartAllPreviewTimers, which would wipe real cast timers. Implemented in bed32a3.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CDMTab section + drag ghost + StartAllPreviewTimers not routed through GetAtRestMetaIcon**
- **Found during:** In-game verification (ICON-01/05 check)
- **Issue:** Only Display.lua placeholder paths were fixed in Task 2. CDMTab section render, drag ghost render, and the StartAllPreviewTimers icon assignment all still called the old GetSpellIcon Bloodlust fallback for trinket/pot slots.
- **Fix:** Routed all three CDMTab render paths through `GetAtRestMetaIcon`; removed Bloodlust fallback for meta-slot entries.
- **Files modified:** CDMTab.lua, BuffEngine.lua
- **Commit:** c1b78f0

**2. [Rule 1 - Bug] Tooltip showed item tooltip instead of buff spell tooltip**
- **Found during:** In-game verification (tooltip quality check)
- **Issue:** `ns.metaAtRest` stored only `{icon, itemID}`. CDM tooltip hook read itemID and called `C_Item.RequestLoadItemDataByID` / item tooltip API, which surfaced ilvl, quality, and item flavor text — noisy and confusing.
- **Fix:** Switched tooltip and icon resolution to buff spell (not item). Cache reshaped to `{icon, itemID, duration}`.
- **Files modified:** BuffEngine.lua, CDMTab.lua
- **Commit:** 28d2dba (preceded by intermediate 7852c78 which introduced item-tooltip logic, then reversed)

**3. [Rule 1 - Bug] live-update hook called StartAllPreviewTimers and wiped real cast timers**
- **Found during:** In-game verification (real cast timer test)
- **Issue:** The live icon swap path called `StartAllPreviewTimers`, which resets all preview timers including source=cast/debuff ones. Any active trinket/pot timer was lost when CDM was opened while a timer was running.
- **Fix:** Replaced the call with `UpdateDisplay()` + `metaIconsDirty = true` so icons refresh without touching active timers.
- **Files modified:** CDMTab.lua, BuffEngine.lua
- **Commit:** bed32a3

**4. [Rule 1 - Bug] StartAllPreviewTimers wiped real cast timers on repeated calls**
- **Found during:** Testing combat + CDM open flow
- **Issue:** StartAllPreviewTimers only preserved real timers on the first call (guarded by a `firstCall` flag). Closing and reopening CDM wiped real timers on the second call.
- **Fix:** Preserve source=cast/debuff timers on every call.
- **Files modified:** BuffEngine.lua
- **Commit:** 16dfe5c

**5. [Rule 3 - Blocking] PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE_DELAYED hooks introduced and then reverted**
- **Found during:** Hotfix iteration (7852c78 added them)
- **Issue:** Hooks were added to support live icon updates without requiring CDM open. User explicitly rejected this behavior — violates D-04 "no event hooks" decision from Phase 14 CONTEXT.
- **Fix:** Removed hooks entirely in 20550f5. CDM open remains the sole refresh trigger.
- **Files modified:** CDMTab.lua
- **Commit:** 20550f5

**6. [Rule 1 - Bug] Meta-slot timers not found by hideWhenInactive and DB slot paths**
- **Found during:** In-game verification (Bars/Buffs section visibility)
- **Issue:** `activeTimers` was keyed only by numeric spellID. Display.lua's `hideWhenInactive` check and CDMTab's DB slot path used the string metaSlot key (e.g. `"trinket"`, `"pot"`), so they never matched — timers were invisible or always shown incorrectly.
- **Fix:** Write both numeric spellID and string metaSlot key into `activeTimers` at timer creation; reads by either key both succeed.
- **Files modified:** BuffEngine.lua, Display.lua
- **Commit:** 1235344

---

**Total deviations:** 6 auto-fixed (all Rule 1 — bugs found during in-game verification)
**Impact on plan:** All fixes were correctness requirements for Phase 14's goal. Scope boundary respected — no pre-existing unrelated issues touched.

## Issues Encountered

- The hotfix cycle was longer than planned (~7 commits) because several render paths in CDMTab were not covered by the plan's Task 2 scope (which targeted only Display.lua). This was discovered only through in-game eyeballs.
- The item-vs-spell tooltip decision required one exploratory commit (7852c78) before the correct direction was confirmed by user feedback (28d2dba).

## User Setup Required

None — all changes auto-deploy via `scripts/install.bat`.

## Known Stubs

None — all Phase 14 icon resolution surfaces are wired. The at-rest icon path (GetAtRestMetaIcon) is fully functional. Active icon switching (cast spell icon during active timer, revert on expiry) is Phase 15 scope and is intentionally deferred.

## Next Phase Readiness

- Phase 15 (Display Integration + Active Icon Switching) can begin immediately
- The at-rest baseline (ns.metaAtRest, GetAtRestMetaIcon, Display placeholder paths) is correct and verified
- activeTimers dual-index (numeric + string key) is in place — Phase 15 cast-spell icon switching can use the numeric key directly
- No blockers

---

## Self-Check: PASSED

Files modified exist:
- CDMTab.lua — present (modified throughout hotfix series)
- Display.lua — present (Tasks 1+2 plus hotfix 1235344)
- BuffEngine.lua — present (multiple hotfixes)

Commits verified:
- d3b7b2f (Task 1 feat) — present
- 696575a (Task 2 feat) — present
- c1b78f0, 7852c78, 28d2dba, bed32a3, 16dfe5c, 20550f5, 1235344 — all present

---
*Phase: 14-icon-resolution-caching*
*Completed: 2026-04-13*
