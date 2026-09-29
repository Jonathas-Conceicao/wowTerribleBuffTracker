---
phase: 56-detailed-tracking-mode-aura-rules
plan: 01
subsystem: buff-engine
tags: [lua, node, wow-addon, aura-tracking, static-analysis]

# Dependency graph
requires: []
provides:
  - "ns:DetailedAuraID(entry) and ns:CancelsOnAuraLoss(entry) runtime gates in BuffEngine.lua, gated on entry.detailed"
  - "UserSpellProviderMixin:OnTrigger aliveBuffs decision: opt-out -> nil, aura ID -> pooled list, else rank family / spellID"
  - "scripts/aura-read-gate.js: DTRK-06 static proof that every direct aura API call sits inside an allowlisted reader"
affects: [57-detailed-tracking-visibility-cross-spell-rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Runtime gates live on ns (ns:DetailedAuraID, ns:CancelsOnAuraLoss), never as file-locals, since Providers.lua calls them and Phase 57's visibility cache will too"
    - "Gates check entry.detailed first, never child-key presence, so hidden dialog fields' stale saved values cannot leak into simple-tracker behaviour"
    - "Static allowlist gate (node, CommonJS, --selftest) mirrors scripts/migrate-dryrun.js's shape: read real source at scan time, embedded fixtures for --selftest, expect() helper, PASS/FAIL count line"

key-files:
  created:
    - scripts/aura-read-gate.js
  modified:
    - BuffEngine.lua
    - Providers.lua

key-decisions:
  - "DetailedAuraID never returns entry.spellID -- the caller (OnTrigger, and Phase 57) decides the spellID fallback, keeping the gate a pure predicate"
  - "aura-read-gate.js's detection regex matches C_UnitAuras.\\w+ as a bare reference too (not just a call), since MergeMode.lua's SafeAuraCall pattern passes the function by value"
  - "Function-boundary tracking in the gate is column-0 only: nested pcall(function() ... end) closures inside CollectPlayerBuffs never affect the enclosing-function attribution, matching how the real files are indented"

requirements-completed: [DTRK-01, DTRK-02, DTRK-04, DTRK-06]

duration: 8min
completed: 2026-09-28
---

# Phase 56 Plan 01: Detailed Tracking Runtime Gates Summary

**Two allocation-free `ns` gates on `entry.detailed` drive `OnTrigger`'s aliveBuffs choice (aura ID beats rank family, opt-out leaves it nil), and a new node script statically proves no shipped Lua reads an aura outside the three allowlisted readers.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-09-28T12:35:00-03:00 (approx, first commit 12:35:51-03:00)
- **Completed:** 2026-09-28T12:39:09-03:00
- **Tasks:** 2 completed
- **Files modified:** 3 (2 modified, 1 created)

## Accomplishments
- `ns:DetailedAuraID(entry)` and `ns:CancelsOnAuraLoss(entry)` added to BuffEngine.lua, both gated on `entry.detailed` so a tracker switched back to simple behaves exactly like v0.4.1 even with stale `auraID` / `keepOnAuraLoss` keys saved (D-01).
- `UserSpellProviderMixin:OnTrigger`'s `aliveBuffs` assignment now: leaves it `nil` when the tracker opted out of aura-loss cancellation (D-04); otherwise prefers the detailed aura ID over the rank family (D-02, since `ns.rankFamilies` holds cast IDs, not auras); otherwise keeps the exact v0.4.1 expression. Zero new table constructors, zero aura reads added to the cast path.
- `scripts/aura-read-gate.js` created: scans the TOC's shipped file list (plus `CDMTab.lua`) for any direct `C_UnitAuras`/`UnitAura`/`UnitBuff`/`UnitDebuff`/`AuraUtil` reference, attributes each hit to its enclosing column-0 function, and fails the build if that function is not one of the three allowlisted readers (`ns:ReadPlayerAura`, `CollectPlayerBuffs`, `TryResolveFromSpellID`). It also independently asserts `ns:ReadPlayerAura` asks `ShouldSpellAuraBeSecret` before `GetPlayerAuraBySpellID`.
- `--selftest` covers the 6 cases the plan specified: a clean gated reader (0 violations), a bypass inside an un-allowlisted function (1 violation naming it), a comment-only line (0 hits), a fixture with the predicate line removed (predicate check fails independently of the allowlist), a vacuity guard against the real shipped tree (>= 1 allowlisted read, so an empty file list can never pass silently), and a read placed after a closed function's column-0 `end` (1 violation attributed to `(top level)`, proving the closed-function rule).

## Task Commits

Each task was committed atomically:

1. **Task 1: Detailed-mode runtime gates and the OnTrigger aliveBuffs assignment** - `58c52af` (feat)
2. **Task 2: DTRK-06 static proof -- scripts/aura-read-gate.js with --selftest** - `22d7cc5` (feat)

_Plan metadata commit intentionally NOT made by this executor -- the orchestrator owns STATE.md/ROADMAP.md per its instructions._

## Files Created/Modified
- `BuffEngine.lua` - Added `ns:DetailedAuraID(entry)` and `ns:CancelsOnAuraLoss(entry)` between `ns:AcquireAliveBuffs` and `ns:PreallocateProc`
- `Providers.lua` - `UserSpellProviderMixin:OnTrigger`'s `aliveBuffs` local is now assigned by an if/elseif chain instead of one expression; `proc.aliveBuffs = aliveBuffs` unchanged
- `scripts/aura-read-gate.js` - new node script, DTRK-06 static proof plus `--selftest`

## Decisions Made
- `DetailedAuraID` never returns `entry.spellID` — kept as a pure predicate so Phase 57 can compose `ns:DetailedAuraID(entry) or entry.spellID` without this plan pre-deciding that fallback.
- The gate script's detection regex treats a bare `C_UnitAuras.<Method>` reference (no trailing `(`) as a hit too, because `MergeMode.lua`'s `SafeAuraCall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)` passes the function by value rather than calling it directly — the plan's own regex already covered this, confirmed correct against the real file.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' automated verify gates passed on the first attempt with no auto-fixes required.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 57's visibility cache can call `ns:DetailedAuraID(entry)` and `ns:CancelsOnAuraLoss(entry)` directly; both are on `ns`, allocation-free, and safe from any call site.
- Any aura read Phase 57 adds must pass through `ns:ReadPlayerAura` or be added to `scripts/aura-read-gate.js`'s allowlist as a reviewed decision — running `node scripts/aura-read-gate.js` is now a standing check.
- No blockers. Plans 02-04 of Phase 56 (dialog fields, portrait redesign) are unaffected by and do not depend on this plan's runtime-only changes.
- In-game verification (a detailed buff tracker whose aura ID differs from its cast ID, and the opt-out checkbox behaviour) remains human-only — no WoW client is available in this environment. That verification belongs to whichever plan wires the dialog fields (Plan 03) and ships the full feature.

## Self-Check: PASSED

All created/modified files found on disk; both task commits (`58c52af`, `22d7cc5`) found in `git log`.

---
*Phase: 56-detailed-tracking-mode-aura-rules*
*Completed: 2026-09-28*
