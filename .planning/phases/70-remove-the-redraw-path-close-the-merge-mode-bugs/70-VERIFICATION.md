---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
verified: 2026-10-10T00:00:00Z
status: human_needed
score: 5/5 requirements verified in source; in-game checks deferred to Phase 72
human_verification:
  - test: "STEAL-20: swap Arcane to Frost, look at a merged Frost Orb cell without /reload"
    expected: "Blizzard's own frame shows the correct charge count"
    why_human: "Needs live spec change and Blizzard frame rendering"
  - test: "STEAL-21: with another Frost Mage (Freezing) and another mage (Touch of the Magi) on the target, view a merged Essential row"
    expected: "No foreign debuff appears as the player's own; no cell overlaps"
    why_human: "Needs a second player in game"
  - test: "STEAL-22: be mind-controlled with Merge Mode on"
    expected: "No merged cell shows an aura it does not own; no one aura on every cell"
    why_human: "Needs a mind-control source; live game outranks the source snapshot"
  - test: "STEAL-23: Centered container, apply and expire merged buffs"
    expected: "Container re-centres as buffs come and go"
    why_human: "Visual and live"
  - test: "IN-03 (review fix): merged bars sit on their rows; Edit Mode placeholder still shows icon and name"
    expected: "No visual regression after the skipped per-tick writes"
    why_human: "Render-loop control-flow change, visual"
  - test: "Merge Mode on, toggle off, then on without /reload"
    expected: "Everything still works; frames return to Blizzard viewers"
    why_human: "Live behaviour"
---

# Phase 70: Remove the Redraw Path and Close the Merge Mode Bugs: Verification Report

**Phase Goal:** Re-anchoring is the only Merge Mode path; redraw machinery, `/tbt reanchor` toggle and saved flag gone; bugs 999.21-999.25 closed and checked; written whole-path review shows nothing can paint one aura or frame over every cell.
**Status:** human_needed (all source-checkable must-haves pass; no gaps)
**Re-verification:** No

## Requirements Coverage

All five IDs appear in PLAN frontmatter (70-01: 19/20/21/23; 70-02: 19; 70-03: 19/21/22; 70-04: 19; 70-05: 20/21/22/23) and in REQUIREMENTS.md (lines 45-58, traceability 117-121, still marked Pending/unchecked there). No orphaned IDs.

| Req | Status | Evidence |
|---|---|---|
| STEAL-19 | SATISFIED | `git grep` outside `.planning`/`tools`/CHANGELOG for all 26 deleted identifiers (AURA_UNITS, auraContainers, slotFilters, SyncEntryContainers, SendSlotFilters, SlotAllowed, RefreshTargetAssistable, RefreshMergeAuraGroups, PlaceMergeAura, RefreshMergeAuraUnits, DisableAuraGroups, mergeAuraGroupsActive, engineDrawsHere, ResolveMergedAuraTiming, TryResolveFromSpellID, SafeAuraCall, AuraSpellName, TARGET_AURA_FILTERS, RelayMergedBar, RelayMergedIconTime, MatchMergedTimeFont, mergedTime, ReadPandemicState, ReadDispelBorder, IsMergedEntryInPandemic, ApplyMergedAuraCooldown) returns nothing. No `EXPERIMENT (MergeReanchor` markers. No `reanchor` slash command in Core.lua. The only `mergeReanchorExperiment` references are the silent clear (`Core.lua:1891`, `ns.db.mergeReanchorExperiment = nil` on every load) and its dry-run mirror/selftest in `migrate-dryrun.js` (:489, :1545). `ApplyChargeCount`/`ApplyCooldownSlot` survive only for TBT's own non-merged trackers (merged arm precedes them at Display.lua:1609). |
| STEAL-20 | SATISFIED in source, live check deferred | Merged entries take the re-anchor arm and never reach `ApplyCooldownSlot`; cell is hidden so Blizzard's frame draws its own count. Spec events are in the mirror-rebuild lists (per review doc, spot-checked). |
| STEAL-21 | SATISFIED in source, live check deferred | `git grep` for `C_UnitAuras`/`GetAuraData`/`AuraUtil`/`UnitAura`/`sourceUnit` in shipped Lua: only `BuffEngine.lua:38` (`ReadPlayerAura`, player-only, by explicit spellID), a comment at Display.lua:873, and a tooltip-type enum in Core.lua:2408 (not an aura read). Nothing in MergeMode/MergeReanchor/Display reads auras. |
| STEAL-22 | SATISFIED in source, live check deferred | `70-MERGE-PATH-REVIEW.md` exists with pixel sources, an event-to-pixel table and 18 fan-out candidates (C1-C18), all CLOSED. Spot-checks below hold. No `UnitIsFriend/UnitCanAssist/UnitReaction/UnitIsCharmed/isFromPlayerOrPlayerPet` anywhere in shipped Lua. |
| STEAL-23 | SATISFIED in source, live check deferred | `SlotDraws` gates on `entry.cdmShown == true` for merged entries (Display.lua:89-93); centred placement uses a per-drawing-slot `drawnIndex` (review C18). |

## Spot-checks of 70-MERGE-PATH-REVIEW.md against code

- C2/C3 one-to-one invariant: `AttachMergedItem` (MergeReanchor.lua:471-525) matches the doc. The early return on `attachGen[id] == renderGen and cellByID[id] ~= cell` is at :480. The old cell is cleared in `idByCell`, the previous occupant is evicted from `cellByID`/`kindByID`/`settingsByID`/`labelByID`/`viewerByID`, and `cellByID[id] = cell; idByCell[cell] = id` are written together (:509-510). Claim holds (line numbers drifted a few lines after the review-fix round, content is unchanged).
- C12/C13: aura-API and reaction greps confirm the claim. `node scripts/aura-read-gate.js` reports PASS (1 read in 1 allowlisted reader).
- C11/off path: `IsMergeReanchorActive` still gates `PlaceItem` (:351), `PlaceAllMergedItems` (:441) and the Layout hook (:593).
- Display merged arm precedes the cooldown-slot arm (Display.lua:1609).

## Behavioral checks run

| Check | Result |
|---|---|
| `node scripts/aura-read-gate.js` | PASS (1 read, 1 reader) |
| `node scripts/aura-read-gate.js --selftest` | PASS (30 cases) |
| `node scripts/migrate-dryrun.js --selftest` | PASS (14 cases), includes prototype flag cleared silently with schema untouched |
| `stylua --check .` | OK |
| `git grep TBD/FIXME/XXX` in `*.lua`, `*.js` | none |
| `git status` | clean |

## Review-fix round (70-REVIEW-FIX.md)

All 8 findings are recorded as fixed. Spot-checked: the removed fields (`linkedSpellIDs`, `hideAura`, `hasCharges`, `selfAura`) leave no stale readers (grep is clean for the deleted identifiers). IN-03 changed render-loop control flow in `RenderBarContainer` and needs an in-game look (human item above).

## Anti-patterns

None blocking. `MergeReanchor.lua` remains in the TOC (:17); the decision to fold it into MergeMode.lua was not mandated.

## Gaps Summary

No source-level gaps. REQUIREMENTS.md checkboxes for STEAL-19..23 are still unticked and traceability says Pending. That is bookkeeping for the orchestrator, to be updated once the Phase 72 live checks land. Remaining work is the live-game checks listed in the frontmatter, deferred to Phase 72 by user decision.

_Verified: 2026-10-10_
_Verifier: Claude (gsd-verifier)_
