---
phase: 67-remove-racials
plan: 02
subsystem: ui
tags: [suggested-tiles, display, racials, lua]
requires: ["67-01"]
provides:
  - "Suggested sections without racial tiles on every client"
  - "AddSuggestedTracker limited to meta, metaItem and metaReminder keys"
  - "Providers.lua without the racial offer API"
  - "Display.lua without the stack-count display and the indefinite-timer branch"
affects: [67-03, 67-04, 67-05]
key-files:
  modified:
    - CDMTab.lua
    - Providers.lua
    - Display.lua
key-decisions:
  - "Only the READERS of proc.stacks and proc.indefinite were removed; the racial provider that writes them goes in Plan 04"
requirements-completed: [RACE-11, RACE-12]
duration: 20min
completed: 2026-10-10
---

# Phase 67 Plan 02: Racial Suggested offer and display paths Summary

The Buffs and Cooldowns tabs no longer offer racial tiles, AddSuggestedTracker only mints Lust/trinket/pot meta, bag-item and class-buff entries, and Display.lua draws no stack count and has no indefinite-timer branch.

## Tasks

| Task | Commit | Notes |
| ---- | ------ | ----- |
| 1. Racial Suggested tiles and offer API | e3e8462 | CDMTab.lua and Providers.lua |
| 2. Stack-count display and indefinite branch | 5deb17e | Display.lua |

## What changed

- CDMTab.lua: racial loops removed from the Cooldowns tab (bag items only) and the Buffs tab (SUGGESTED_KEYS only); `cooldownSpellID` and `racialSpellID` locals gone from AddSuggestedTracker; all racial comments reworded.
- Providers.lua: deleted `ns:RacialSuggestions`, `ns:RacialDefInList`, `ns:RacialCooldownKeys`, `ns:RacialCooldownSeed`, `ns.knownRacialDefs` and the known-list half of `ns:RebuildRacialLoadLists` (the `ns.racialDefsActive` half is intact); the racial seed branch in `UserSpellProviderMixin:GetDisplayInfo` is gone.
- Display.lua: `bar.stacks`, `bar._stacks`, `icon._stacks`, the bar and icon stack stamps and the `timer.indefinite` bar and icon arms removed. The merged-bar arm `elseif slot.isMerged and RelayMergedBar(bar, slot)` is kept (side effects).

## ClearCooldownStamps call sites (Task 2, step 8)

`ClearCooldownStamps` (still hides `icon.chargeCount`) is called under an `if icon._cdKey then` guard in the timer branch (Display.lua ~2526) and the placeholder branch (~2594). The remaining branch an icon can reach, the item-backed buff cooldown overlay, goes through `ApplyCooldownSlot`, and the final `icon:Hide()` branch hides the whole widget. A leftover charge count is therefore still cleared on every route out of the cooldown branch.

## Acceptance criteria

All met: `grep -c -i racial CDMTab.lua` 0; `CooldownKeySpellID|RacialKeySpellID|metaSkillCd` in CDMTab.lua 0; offer-API names in Providers.lua 0; `ns:ItemCatalogue()` 2 and `ns:MetaReminderSuggestionKeys()` 1 in CDMTab.lua; Display.lua `stacks` 0, `indefinite` 0, `racial|Shadowmeld|Eureka` 0, `icon.chargeCount:Hide()` 3, `RelayMergedBar(bar, slot)` 2; `stylua` exit 0 on all three files; all three `w/crlf`. No code hit for the removed offer names in any `.lua`.

## Remaining comment-only hits (for later plans)

- BuffEngine.lua lines 71-74: comment naming `ns:RacialSuggestions()` / `ns:RacialCooldownKeys()` (Plan 03 rewrites it).
- Core.lua ~3000: comment naming `ns:RacialCooldownSeed` and `Providers.lua:886`.
- Providers.lua ~1044: `ns:RacialCooldownKeys` inside the RACIAL_SPELLS header comment (goes with the catalogue in Plan 04/05).

## Deviations from Plan

None. During Task 2 one Edit mismatched on indentation and was redone; no behaviour effect.

## Deferred to Phase 72 (human, in-game)

On retail and Forever, open the CDM TBT tab: Buffs Suggested shows Lust, trinket, pot only; Cooldowns Suggested shows bag items only; Reminders still shows class buffs; a running buff bar and icon show no stack number; cooldown slots still show charge counts.

## Known Stubs

None.

## Self-Check: PASSED

Commits e3e8462 and 5deb17e exist; CDMTab.lua, Providers.lua and Display.lua modified; STATE.md and ROADMAP.md untouched.
