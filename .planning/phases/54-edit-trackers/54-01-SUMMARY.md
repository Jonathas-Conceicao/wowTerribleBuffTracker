---
phase: 54-edit-trackers
plan: 01
subsystem: infra
tags: [buff-engine, tracker-edit, lua, wow-addon, naming-scheme]

# Dependency graph
requires:
  - phase: 53-naming-scheme-saved-data-migration
    provides: "ns.KIND, ns:TrackerKey, ns.buffKeyBySpell/ns.cooldownKeyBySpell, ns.cooldownStarts/ns.cooldownOverrides, ns:CooldownKindFor, ns:RebuildRankIndex/ns:RebuildCastIndex, the schema-v8 canonical <kind>:<id> key scheme, and WR-01's cast-index userCd-over-metaSkillCd preference"
provides:
  - "ns:UpdateTrackedBuff(oldKey, spellID, duration, fields, fieldKeys) -- edits a userBuff/userCd tracker in place or moves it to a new key, refusing same-slot duplicates and non-editable kinds"
  - "ns:FindTrackerConflict(kind, spellID, exceptKey) -- the shared dialog-path duplicate check used by both Add and Update"
  - "ns:ClearTrackerRuntimeState(key) -- the shared runtime-state clear (activeTimers/previewTimers/cooldownStarts/cooldownOverrides/proc pools) used by Remove and by an ID-changing Update"
  - "ns:IsEditableTracker(entry), ns:TrackerKindWord(kind), ns:SpellLabel(spellID) -- small shared predicates/helpers"
  - "ns:AddTrackedBuff opts.fields -- the dialog field-value pass-through contract (ENGINE_OWNED), replacing opts.coverAllRanks"
affects: [54-02, 54-03, 54-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One ENGINE_OWNED set gates both Add's entry-constructor copy loop and Update's field-copy loop, so a field added later to the dialog's shared definition needs no engine edit"
    - "Move-not-rebuild record edit: ns:UpdateTrackedBuff moves the SAME entry table onto its new key rather than constructing a new one, so section/layoutOrder travel with it -- same discipline as Phase 53's schema-v8 migration"
    - "A single ns:ClearTrackerRuntimeState(key) is now the one place that clears activeTimers/previewTimers/cooldownStarts/cooldownOverrides/proc pools for a key, called by both Remove and an ID-changing Update"

key-files:
  created: []
  modified:
    - "BuffEngine.lua - ns:TrackerKindWord, ns:SpellLabel, ns:IsEditableTracker, ns:FindTrackerConflict, ns:ClearTrackerRuntimeState, ENGINE_OWNED added above ns:AddTrackedBuff; ns:AddTrackedBuff rejects same-slot duplicates (was WR-01 reuse) and reads opts.fields; ns:RemoveTrackedBuff clears cooldownStarts/cooldownOverrides via the shared clear; ns:UpdateTrackedBuff added"

key-decisions:
  - "ns:AddTrackedBuff's WR-01 reuse branch (existingKey/existingEntry) is replaced with rejection via ns:FindTrackerConflict, per 54-CONTEXT's locked commit semantics -- this reverses WR-01's specific fix (which was 'reuse the existing key') in favour of 'refuse and leave the existing tracker untouched', while leaving WR-01's OTHER two mechanisms (Core.lua's ns:RebuildCastIndex userCd-over-metaSkillCd cast-index preference, and CDMTab.lua's Suggested-tile drag) completely unchanged, exactly as the plan's interfaces block specifies"
  - "ns:UpdateTrackedBuff keeps the tracker's existing kind (entry.trackerType) even when the new spellID is a racial spell, rather than re-deriving it through ns:CooldownKindFor -- see Known inconsistency below"

requirements-completed: [EDIT-02, EDIT-04]

# Metrics
duration: ~6min
completed: 2026-09-28
---

# Phase 54 Plan 01: Edit Trackers Engine Summary

**BuffEngine.lua gains a dedicated `ns:UpdateTrackedBuff` that edits a userBuff/userCd tracker in place or moves it to a new `<kind>:<id>` key, backed by two new shared helpers (`ns:FindTrackerConflict`, `ns:ClearTrackerRuntimeState`) that also close two found bugs: `ns:AddTrackedBuff` no longer silently overwrites an existing tracker, and `ns:RemoveTrackedBuff` now clears `ns.cooldownStarts`/`ns.cooldownOverrides`.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-09-28T09:23:29-03:00 (previous plan-doc commit)
- **Completed:** 2026-09-28T09:28:51-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 1

## Accomplishments
- `ns:TrackerKindWord(kind)`, `ns:SpellLabel(spellID)`, `ns:IsEditableTracker(entry)`, `ns:FindTrackerConflict(kind, spellID, exceptKey)` and `ns:ClearTrackerRuntimeState(key)` are new shared helpers on `ns`, placed above every caller in the file.
- `ns:AddTrackedBuff` now refuses a spell ID already tracked in the same slot (buff namespace, or cooldown namespace where `userCd`/`metaSkillCd` collide) instead of silently overwriting the existing tracker's section and order (54-CONTEXT "Found bug, fixed in this phase"). It returns `true, dbKey` on success or `false, reason` on refusal, and persists `opts.fields` (replacing `opts.coverAllRanks`) through the new file-local `ENGINE_OWNED` contract.
- `ns:RemoveTrackedBuff` now clears `ns.cooldownStarts`/`ns.cooldownOverrides` through `ns:ClearTrackerRuntimeState`, closing the gap where a removed-then-re-added cooldown tracker inherited a running cooldown.
- `ns:UpdateTrackedBuff(oldKey, spellID, duration, fields, fieldKeys)` is the one place the edit side-effect list lives: it edits a `userBuff`/`userCd` tracker's fields in place when the spell ID is unchanged, or moves the SAME entry table to `<kind>:<newID>` (carrying `section`/`layoutOrder` with it, re-deriving `label`, clearing every old-key runtime table, and calling `ns:PreallocateProc(newKey)`) when it changes. It refuses a same-slot duplicate and any non-`userBuff`/`userCd` kind without writing anything, and prints one chat line instead of a stop+start pair. `ns:RefreshTBTSections`/`ns:StartAllPreviewTimers` are deliberately left to the dialog (CDMTab.lua, next plan), noted only in the header comment above the function per this plan's checker advisory.

## Task Commits

Each task was committed atomically:

1. **Task 1: Shared engine helpers, Add duplicate rejection and opts.fields, Remove clears cooldown state** - `20c6040` (feat)
2. **Task 2: ns:UpdateTrackedBuff -- edit in place, or move the record to the new key** - `8249890` (feat)

**Plan metadata:** committed together with this SUMMARY (see below)

## Files Created/Modified
- `BuffEngine.lua` - `ns:TrackerKindWord`, `ns:SpellLabel`, `ns:IsEditableTracker`, `ns:FindTrackerConflict`, `ns:ClearTrackerRuntimeState`, file-local `ENGINE_OWNED`; `ns:AddTrackedBuff` (duplicate rejection, `opts.fields`, `return true, dbKey` / `return false, reason`); `ns:RemoveTrackedBuff` (shared runtime-state clear); new `ns:UpdateTrackedBuff`

## Decisions Made
- Reversed WR-01's specific "reuse the existing key" fix inside `ns:AddTrackedBuff` in favour of 54-CONTEXT's locked "refuse and leave unchanged" semantics, while leaving WR-01's other two mechanisms (`ns:RebuildCastIndex`'s userCd-over-metaSkillCd cast-index preference in Core.lua, and CDMTab.lua's Suggested-tile drag) completely untouched -- exactly as this plan's interfaces block specifies. This is not a re-introduction of the WR-01 bug: the cast index still prefers a user's own `userCd` tracker over a `metaSkillCd` twin, so an existing tracker is never shadowed; only the Add-dialog path changed from "silently reuse" to "refuse with a reason".
- `ns:UpdateTrackedBuff` keeps the tracker's existing `trackerType` on an ID change rather than re-deriving it through `ns:CooldownKindFor` -- see Known inconsistency below.

## Deviations from Plan

None - plan executed exactly as written. One self-caught issue during verification, not counted as a deviation: an early draft of `ns:UpdateTrackedBuff`'s body mentioned `ns:RefreshTBTSections`/`ns:StartAllPreviewTimers` inside a comment INSIDE the function body, which the plan's own checker advisory (and this plan's `<verify>` gate `RefreshTBTSections|StartAllPreviewTimers` count 0 inside the function) flags. Moved the note to the header comment above the function before committing; the gate was run and passed before the commit was made, so no incorrect state was ever committed.

## Issues Encountered

None. `stylua --check BuffEngine.lua` passed on the first formatting pass; `node scripts/migrate-dryrun.js --selftest` still prints `SELFTEST PASS (7 cases)` unchanged, confirming this plan touched nothing that script depends on.

## Known inconsistency (user to decide later)

An edited `userCd` tracker keeps kind `userCd` even when its new spell ID is a racial spell (so it stays editable), while `ns:AddTrackedBuff` still mints `metaSkillCd` for a racial spellID via `ns:CooldownKindFor` (so the same spell added fresh is a racial cooldown with no Edit entry, and would be refused as a duplicate of the edited `userCd`, since both share the cooldown slot). Kept deliberately by orchestrator decision during plan checking; 54-04's HUMAN checklist surfaces it so the user can decide.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`ns:UpdateTrackedBuff`, `ns:FindTrackerConflict`, `ns:ClearTrackerRuntimeState`, `ns:IsEditableTracker` and the `opts.fields`/`fields`+`fieldKeys` contract (`ENGINE_OWNED`) are all in place exactly as this plan's `<interfaces>` block specifies, ready for plan 54-02 (the shared field definition, EDIT-03) to build the dialog's field list against. Nothing is deployed to a WoW client yet -- 54-04 wires the CDMTab.lua Edit entry and deploys. No blockers. In-game behaviour (EDIT-01 through EDIT-04's UI half) is human verification, deferred to 54-04 per this plan's own `<verification>` note (no WoW client is available in this environment).

## Self-Check: PASSED

- FOUND: BuffEngine.lua
- FOUND: .planning/phases/54-edit-trackers/54-01-SUMMARY.md
- FOUND commit: 20c6040 (Task 1)
- FOUND commit: 8249890 (Task 2)

---
*Phase: 54-edit-trackers*
*Completed: 2026-09-28*
