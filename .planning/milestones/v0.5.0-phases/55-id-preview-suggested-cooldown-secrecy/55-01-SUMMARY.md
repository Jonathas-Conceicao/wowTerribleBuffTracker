---
phase: 55-id-preview-suggested-cooldown-secrecy
plan: 01
subsystem: ui
tags: [tooltip, secrecy, secret-values, wow-addon, guarded-reads]

# Dependency graph
requires:
  - phase: 27.1 (TOOL-01)
    provides: the global spell/aura ID tooltip post-call this plan adds a line to
  - phase: 22 (Display unification)
    provides: ns:ShowBuffTooltip, the shared tooltip handler this plan extends
provides:
  - ns:SpellAuraSecrecy(spellID), ns:SecrecyLine(level), ns:SecrecyExplanation(level), ns:SecrecyWarns(level) — guarded secrecy-level read and its prebuilt strings
  - ns:SuggestedCooldown(spellID) — ADD-05 fallback chain (GetSpellBaseCooldown, then GetSpellCharges().cooldownDuration)
  - ns:SpellPreview(spellID) — ADD-04 name/icon for a spell, or nil when the client does not know it
  - the secrecy line on the global TOOL-01 tooltip line and on ns:ShowBuffTooltip's unresolved-ID branch
affects: [55-02, 55-03, 56, 57]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Capability-checked secrecy tables (SECRECY_LABELS/SECRECY_LINES/SECRECY_EXPLANATIONS) built once at load from a section-local spec array, keyed by Enum.SecrecyLevel member name"
    - "Shared ns helpers placed above TOOL-01 in Core.lua, deliberately not calling the guarded-read locals declared further down the file (upvalue order trap)"

key-files:
  created: []
  modified:
    - Core.lua
    - Display.lua

key-decisions:
  - "No bare secrecy-label getter added: nothing in this phase calls one, since both the tooltip line and the future badge read off the prebuilt line/explanation instead — the label table stays section-local"
  - "The TOOL-01 post-call is the single source of the secrecy line for any tooltip that resolves through SetSpellByID (including every TBT tile); ns:ShowBuffTooltip only adds its own line in the unresolved-ID branch, where TOOL-01 never runs, avoiding a double print"

patterns-established:
  - "Guarded spell-info reads (secrecy, suggested cooldown, preview) consolidated as ns methods instead of re-derived per call site"

requirements-completed: [SECR-01, SECR-02]

# Metrics
duration: ~25min
completed: 2026-09-28
---

# Phase 55 Plan 01: ID Preview, Suggested Cooldown & Secrecy — Shared Helpers Summary

Added six guarded `ns` helpers (secrecy level/line/explanation/warns, suggested cooldown, spell preview) to Core.lua and wired the secrecy line into TOOL-01's global tooltip post-call and into `ns:ShowBuffTooltip`'s unresolved-ID branch, so every game tooltip and every TBT tile now shows an "Aura secrecy: ..." line beside the spell/aura ID with no double print and no error on a client lacking the API.

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-28T13:26:37Z
- **Tasks:** 2/2 completed
- **Files modified:** 2 (Core.lua, Display.lua)

## Accomplishments

- Six shared, capability-checked `ns` helpers (`ns:SpellAuraSecrecy`, `ns:SecrecyLine`, `ns:SecrecyExplanation`, `ns:SecrecyWarns`, `ns:SuggestedCooldown`, `ns:SpellPreview`) added to Core.lua, placed above TOOL-01 per the file-local upvalue order trap, with secrecy label/line/explanation tables built once at load from `Enum.SecrecyLevel`
- SECR-02: the global TOOL-01 tooltip post-call now appends one "Aura secrecy: ..." line under the Spell ID / Aura spell ID line, for every spell and aura tooltip in the game
- SECR-01 (tooltip half): TBT tile tooltips whose spell resolves get the same line for free through `SetSpellByID` → TOOL-01; TBT tiles whose spell the client cannot resolve get their own secrecy line from `ns:ShowBuffTooltip`'s unresolved-ID branch, since TOOL-01 never fires there
- Both edits are pure insertions — no existing line in either file was removed or altered

## Task Commits

Each task was committed atomically:

1. **Task 1: Shared spell-info helpers on ns (secrecy, suggested cooldown, preview)** - `c919e32` (feat)
2. **Task 2: Secrecy line in the TOOL-01 post-call and in ShowBuffTooltip's unresolved branch** - `6465c1f` (feat)

**Plan metadata:** commit pending (docs: complete plan)

## Files Created/Modified

- `Core.lua` - new "SPELL INFO HELPERS (Phase 55)" section above TOOL-01 (six `ns` helpers, secrecy tables built once at load); TOOL-01 post-call gains the secrecy line right after the ID line
- `Display.lua` - `ns:ShowBuffTooltip`'s `not spellResolves` branch gains its own secrecy line, right after its own "Spell ID: " line

## Decisions Made

- Followed the plan's exact helper contracts and fallback chains (ADD-05's `GetSpellBaseCooldown` → `GetSpellCharges().cooldownDuration` → nil; ADD-04's `GetSpellInfo` table/name/icon guards) with no deviation
- Kept all gate-sensitive strings ("Aura secrecy", `SafeNumber`, `SafeString`, `SpellName(`, bare `SpellAuraSecrecy`) out of every comment, describing the helpers and the line in prose instead, per the plan's gate-hygiene hazard

## Deviations from Plan

None - plan executed exactly as written. Both task verification gates (stylua, function-count, section-order, upvalue-avoidance, literal-string-count, CRLF/CRCRLF checks, pure-insertion diff check) passed on the first attempt with no auto-fixes needed.

## Known Stubs

None. Both helpers and both tooltip integrations are fully wired; no placeholder or empty-value stub was introduced.

## Verification Results

- `stylua --check Core.lua Display.lua` — exits 0
- Each of the six `^function ns:<Name>(` lines appears exactly once in Core.lua
- `-- SPELL INFO HELPERS (Phase 55)` banner precedes `function ns:SpellPreview(`, which precedes `if TooltipDataProcessor` (section sits above TOOL-01)
- No non-comment line in the helper section references the guarded-read locals declared further down the file
- The helper section contains `C_Secrets.GetSpellAuraSecrecy`, `Enum.SecrecyLevel`, `GetSpellBaseCooldown` and `cooldownDuration`
- The literal `"Aura secrecy: "` appears on exactly one non-comment line in Core.lua (built once at load)
- `git ls-files --eol Core.lua Display.lua` shows `w/crlf` for both; `git diff --numstat` shows real byte counts (not `-`) for both; the CRCRLF node check exits 0 on both
- TOOL-01 block contains `tooltip:AddLine(secrecyLine` exactly once, positioned after `"Aura spell ID: "` and before `"Base spell ID: "`
- TOOL-01 block contains no `Aura secrecy` literal on a non-comment line
- `ns:ShowBuffTooltip` references `SpellAuraSecrecy` on exactly one non-comment line, inside the `not spellResolves` branch only (no double print on a resolved spell)
- `git diff 5d7201e -- Core.lua Display.lua` removes or rewrites no existing line (pure insertion), confirmed after both tasks
- `node scripts/migrate-dryrun.js --selftest` — 7/7 cases pass, unaffected by this plan's changes
- **Human verification still required** (deferred to Plan 03's checklist, no WoW client available here): hovering an action button/spellbook/buff shows the secrecy line in the same grey as the ID line; a resolved TBT tile shows exactly one secrecy line; an unresolved TBT tile shows "Spell ID: N" followed by the secrecy line; a client without `C_Secrets.GetSpellAuraSecrecy` / `Enum.SecrecyLevel` shows no line and no Lua error

## Issues Encountered

None.

## User Setup Required

None — this plan's output is code only, consumed by Plans 02-03 and Phases 56-57; no new configuration, migration or manual step is introduced.

## Next Steps

- Plan 02 wires `ns:SpellPreview` and `ns:SuggestedCooldown` into the Add/Edit dialog's live preview row and duration-field suggestion
- Plan 03 adds the "secret?" badge (SECR-03) using `ns:SecrecyWarns` / `ns:SecrecyExplanation`, and carries the phase's human-verification checklist (including the items listed above)
