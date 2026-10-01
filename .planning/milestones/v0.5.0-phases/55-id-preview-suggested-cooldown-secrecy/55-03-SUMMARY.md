---
phase: 55-id-preview-suggested-cooldown-secrecy
plan: 03
subsystem: ui
tags: [wow-addon, lua, cdm-tab, add-dialog, field-definition, cooldown-suggestion, secrecy, deploy]

# Dependency graph
requires:
  - phase: 55-01
    provides: ns:SuggestedCooldown -- the guarded fallback-chain helper this plan's duration-field update hook calls
  - phase: 55-02
    provides: the spellID/spellPreview/secrecyBadge field pattern (dialog.GetFieldState at build, compare-before-write update guards) this plan's duration field follows
provides:
  - "duration TRACKER_FIELDS entry gains an update hook -- ADD-05's suggested cooldown, filling an empty or still-suggested Cooldowns-tab duration box as the spell ID is typed, never overwriting a typed or prefilled value"
  - "whole-phase gate closure: byte-identical CreateAddDialog, pure-insertion Core.lua/Display.lua, every new ns helper called at least once, stylua clean, migrate-dryrun selftest green"
  - "performance and cleanup review of the phase's full diff since 5d7201e"
  - "a build deployed to every WoW client folder present"
  - "an ordered 13-item in-game checklist (retail AND Forever) covering ADD-04, ADD-05, SECR-01, SECR-02, SECR-03"
affects: [56, 57]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A field's update hook may capture an earlier sibling's build-time state (state.source) and read its live widget value on every call, rather than re-deriving GetFieldState per update"
    - "Suggestion fields record 'what I last wrote' (state.suggestionText) before writing, so the same compare that guards SetText recursion also tells a later update apart the user's own typed text from the field's own prior suggestion"

key-files:
  created: []
  modified:
    - CDMTab.lua

key-decisions:
  - "None -- plan executed exactly as written, including the compare-before-write order (record suggestedForID/suggestionText BEFORE SetText) the recursion hazard requires"

patterns-established:
  - "Suggestion-vs-user-input disambiguation via a remembered 'last suggestion' string, applied here to duration and available to any future field that offers a game-derived starting value"

requirements-completed: [ADD-05, ADD-04, SECR-01, SECR-02, SECR-03]

# Metrics
duration: ~5min
completed: 2026-09-28
---

# Phase 55 Plan 03: ID Preview, Suggested Cooldown & Secrecy - Suggested Cooldown & Phase Close Summary

**Duration field gains a compare-before-write update hook that fills an empty Cooldowns-tab box with `ns:SuggestedCooldown`'s formatted result and follows the spell ID until the user types over it or it is prefilled by Edit; phase gated end to end, reviewed, deployed to every WoW client folder, with a 13-item retail+Forever checklist.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-09-28T13:31:00Z
- **Completed:** 2026-09-28T13:35:11Z
- **Tasks:** 2/2 completed
- **Files modified:** 1 (CDMTab.lua)

## Accomplishments

- ADD-05 implemented as the `duration` TRACKER_FIELDS entry's own `update(state, ctx)` hook: cooldown trackers only (`ctx.kind == ns.KIND.USER_CD`), reads the spell ID through `state.source` (captured at build via `dialog.GetFieldState("spellID")`, same pattern as `spellPreview`/`secrecyBadge`), and fills the box with `ns:SuggestedCooldown(id)`'s formatted result via `FormatDuration` only while the box is empty or still holds exactly the previous suggestion
- Recursion handled the way the hazard requires: `state.suggestedForID` and `state.suggestionText` are recorded before `state.editBox:SetText(newText)` is ever called, so the nested `RefreshState` pass `SetText`'s own `OnTextChanged` triggers returns at the very first compare
- A suggestion longer than the box's 6-letter limit is dropped (`newText = ""`) instead of being written and silently truncated into a different number; an ID with no reported cooldown clears a box that still held the previous suggestion back to empty, leaving manual entry
- `reset` and `prefill` both clear `suggestedForID`/`suggestionText`; `prefill` recording no suggestion text means a saved Edit value can never compare equal to a "previous suggestion" and is never overwritten
- `read` and `validate` are untouched -- the text in the box at Save, suggested or typed, is what is saved
- `CreateAddDialog` stays byte-identical (hash `64e38633612791cb7e1ea41902b75ae45c18167b`) across all three plans of the phase; the entire phase's behaviour lives in TRACKER_FIELDS entries
- Whole-phase gate run and passed: `migrate-dryrun.js --selftest` (7/7), the non-planning diff since `5d7201e` is exactly `CDMTab.lua Core.lua Display.lua`, `Display.lua` outside `ns:ShowBuffTooltip` is byte-identical to the phase base, `Core.lua`/`Display.lua` lost no line (pure insertion), every new `ns` helper (`SpellAuraSecrecy`, `SecrecyLine`, `SecrecyExplanation`, `SecrecyWarns`, `SuggestedCooldown`, `SpellPreview`) has at least one non-comment caller outside its own definition, `stylua --check` clean on all three files
- Performance and cleanup review over the phase's full diff since `5d7201e` found no defect and no dead code (see below)
- `./scripts/install.bat` run and deployed to all four WoW client folders present on this machine

## Task Commits

Each task was committed atomically:

1. **Task 1: Suggested cooldown as the duration field's update hook** - `16bc0dc` (feat)
2. **Task 2: Phase gates, performance and cleanup review, deploy, in-game checklist** - pending (this SUMMARY's own commit; no code change)

**Plan metadata:** commit pending (docs: complete plan)

## Files Created/Modified

- `CDMTab.lua` - `duration` TRACKER_FIELDS entry: `build` now captures and returns `source` (the spellID field's state); `reset`/`prefill` clear the two new suggestion-tracking fields; new `update` hook implements ADD-05's suggested cooldown. No other entry and no line of `CreateAddDialog` changed.

## Decisions Made

Followed the plan's exact hook order (compare ID first, then text, then compute and conditionally write) with no deviation. One editorial fix during self-review: the first draft's build-time comment on `duration` inaccurately described `source` as "read fresh... rather than captured once" when it is in fact captured once at build (matching `spellPreview`/`secrecyBadge`) and only the *editBox's number* is read live on each `update` call -- reworded before commit so the comment does not contradict the code it sits above.

## Deviations from Plan

None - plan executed exactly as written. Task 1's verification gate (stylua, function-count, section-scoped literal counts, `ns.KIND.USER_CD`/`GetFieldState` presence, `CreateAddDialog` hash, CRLF/CRCRLF checks) and Task 2's whole-phase gate (selftest, non-planning diff scope, pure-insertion check, per-helper caller check, stylua, install.bat, post-deploy status check) both passed on the first attempt; no auto-fix was needed.

## Performance and Cleanup Review

Reviewed `git diff 5d7201e -- Core.lua Display.lua CDMTab.lua` (506 lines) per CLAUDE.md's post-commit rule:

- **(a) TOOL-01 addition:** the secrecy line appended to the existing post-call creates no table, no closure and no string per tooltip -- `ns:SecrecyLine`/`ns:SpellAuraSecrecy` return a prebuilt string from a table built once at load, guarded by one `pcall`, and the result is passed straight to one `tooltip:AddLine`. `ns:ShowBuffTooltip`'s unresolved-ID branch mirrors the same shape.
- **(b) Compare-before-write on every update hook:** `spellPreview`, `secrecyBadge` and (this plan) `duration` all return at their first ID compare when the spell ID has not changed, so a Duration keystroke does no API call in any of the three fields (typing in Duration changes `state.editBox:GetText()` but not `state.source.editBox:GetNumber()`, so `duration`'s own `update` returns at its ID compare on line 1 of the hook before ever reading `GetText()` for a changed ID -- it still re-reads text on every call, which is a `GetText()` call, not an API call, and only proceeds to `ns:SuggestedCooldown` when the ID itself changed). The one intended exception, `spellPreview`'s unknown-ID retry, re-queries `ns:SpellPreview` once per dialog change only while `state.resolved` is falsy; the very next successful resolution sets `state.resolved = true`, and the hook's first compare (`id == state.shownID and state.resolved`) then short-circuits before any further call -- confirmed by inspection of the `update` body, no separate runtime harness available in this environment.
- **(c) No per-frame code changed:** no `OnUpdate` script was added or touched anywhere in the phase's diff (`grep -i OnUpdate` over the full diff returns nothing); `Display.lua` outside `ns:ShowBuffTooltip` is confirmed byte-identical to the phase base.
- **(d) No dead code:** every new `ns` helper (`SpellAuraSecrecy`, `SecrecyLine`, `SecrecyExplanation`, `SecrecyWarns`, `SuggestedCooldown`, `SpellPreview`) has at least one non-comment caller outside its own `function ns:` definition, confirmed by an explicit per-helper grep across `Core.lua`, `Display.lua` and `CDMTab.lua`.

No defect and no dead code introduced by this phase were found; nothing was fixed under Rules 1-3, and PROJECT.md's "No refactors during cleanup phases" decision leaves pre-existing code (everything outside this phase's own diff) untouched.

## Known Stubs

None. The duration field's suggestion is fully wired to `ns:SuggestedCooldown`; there is no placeholder, no hardcoded empty value flowing to a rendered field, and no "coming soon" text anywhere in this plan's change.

## Verification Results

- `stylua --check CDMTab.lua` (Task 1) and `stylua --check Core.lua Display.lua CDMTab.lua` (Task 2) both exit 0
- The `duration` entry (scoped between its own `id = "duration"` and the next `id = "..."`) contains exactly one non-comment `update = function` and exactly one non-comment `ns:SuggestedCooldown(`
- The `duration` entry checks `ns.KIND.USER_CD`, reads the ID through `GetFieldState("spellID")`, references `state.suggestionText` on 4 non-comment lines (reset, prefill, compare, assign) and `FormatDuration(` on 2 (prefill via the existing code path, and the new suggestion)
- The `duration` entry's `read` still ends in `return ParseDuration(text)`
- `CreateAddDialog`'s body hashes to `64e38633612791cb7e1ea41902b75ae45c18167b`, unchanged across all three plans of the phase
- `git ls-files --eol CDMTab.lua` reports `w/crlf`; `git diff --numstat CDMTab.lua` shows real byte counts; the CRCRLF (`\r\r\n`) node check exits 0
- `node scripts/migrate-dryrun.js --selftest` -- 7/7 cases pass
- `git diff --name-only 5d7201e -- . ':!.planning' ':!.gitignore'` lists exactly `CDMTab.lua Core.lua Display.lua`
- `Display.lua` outside `ns:ShowBuffTooltip` diffs empty against the phase base (byte-identical); `Core.lua`/`Display.lua` show zero removed non-context lines against the phase base (pure insertion)
- Every new `ns` helper has at least one non-comment caller outside its own definition (`SpellAuraSecrecy` x3, `SecrecyLine` x3, `SecrecyExplanation` x1, `SecrecyWarns` x1, `SuggestedCooldown` x1, `SpellPreview` x1)
- `./scripts/install.bat` exits 0 and reports 4 deployed-client lines (`_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`)
- `git status --porcelain -- '*.lua' '*.xml' '*.toc' | grep -vE '(Core|Display|CDMTab)\.lua$'` is empty -- no unexpected Lua/XML/TOC drift after deploy
- `.gitignore`'s pre-existing working-tree edit was never staged or committed by either task

## Issues Encountered

None.

## User Setup Required

None - this plan's code change is consumed entirely in-dialog; no new configuration, migration or manual step is introduced. The in-game checklist below is verification, not setup.

## In-game checklist (retail AND Forever)

Run on Midnight retail AND the Forever beta. The build is already deployed to every client folder found on this machine (see install.bat output above). A TOC was not changed this phase, so `/reload` is enough to load the code -- but persistence checks (items 4 and 13) need a REAL logout/login, never `/reload`.

1. **Live preview updates as typed** -- open Add on both the Buffs and the Cooldowns tab; typing a known spell ID updates the preview icon and name on every keystroke.
2. **Edit opens with its preview filled** -- Edit on an existing user tracker (either tab) opens with the preview already showing that tracker's spell.
3. **Unknown ID, no error** -- with `/console scriptErrors 1` set, type `999999999` in Add: the preview shows the 134400 question-mark icon and "Unknown spell"; hovering it shows "Unknown spell" and "Spell ID: 999999999"; no Lua error appears.
4. **logout** Fresh login (a real logout/login, not `/reload`), open Add and type an uncommon spell ID you have not looked at this session: the preview shows the spell's name, not "Unknown spell". If it first shows "Unknown spell", record whether it corrects after one further keystroke elsewhere in the dialog (for example in Duration) -- that is the retry path.
5. **Preview hover tooltip** -- hovering the preview row shows the game's own spell tooltip, with one Spell ID line and one "Aura secrecy: ..." line.
6. **Secrecy line exactly once** -- hover an action button, a spellbook spell, a buff out of combat, and a TBT tracker tile: each shows exactly one "Aura secrecy: ..." line, directly under the Spell ID / Aura spell ID line.
7. **Secrecy badge on a Contextual ID** -- type a Contextual-secrecy ID (Forever example: Eureka!, level 2, `TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md:511`) on BOTH the Buffs and the Cooldowns tab: the warning badge appears beside the preview with an explanatory hover tooltip; a Never-secret ID (for example a Sated debuff) shows no badge on either tab.
8. **Forever badge art** -- on Forever only, record whether the badge renders as the `transmog-icon-warning-small` atlas icon or falls back to the "(secret?)" text.
9. **Cooldowns tab suggestion follows the ID** -- a spell with a known cooldown pre-fills Duration as its ID is typed (e.g. 120 s shows as "2m"); changing the ID while the box is untouched updates the suggestion; typing your own value then changing the ID keeps your typed value; clearing the box back to empty then changing the ID refills it with the new ID's suggestion.
10. **No cooldown leaves the box empty** -- a spell the game reports no cooldown for leaves Duration empty, and Add stays disabled until a value is typed by hand.
11. **Buffs tab never pre-fills Duration** -- on the Buffs tab, typing any spell ID never fills or changes the Duration box.
12. **Edit keeps the saved duration** -- Edit a cooldown tracker and change its spell ID: the previously saved duration is kept in the box, not replaced by a suggestion for the new ID.
13. **logout** A typed-over suggestion survives -- on the Cooldowns tab, let a suggestion fill the box, then type your own value over it, Add/Save, and confirm the typed value (not the suggestion) is still there after a real logout/login.

## Known behaviour

A Duration the user retypes to exactly the text of the current suggestion (for example, clearing "2m" and typing "2m" again by hand) cannot be told apart from the suggestion itself -- `state.suggestionText` only remembers the last string the field itself wrote, not who wrote it. So changing the spell ID afterwards replaces that box with the new ID's suggestion, even though the "2m" was, in that one case, typed by the user. This follows CONTEXT's own rule that the suggestion follows the ID while the box "still holds the previous suggestion"; any other typed value -- one that does not happen to match the last suggestion's exact text -- is kept regardless of ID changes.

Separately, the dialog's live preview (Plan 02) retries a still-unknown spell ID on every later dialog change, not only when the ID itself changes -- checklist item 4 above is the human proof of this retry path in a real client, since caching behaviour for spells not yet seen this session cannot be reproduced without one.

## Next Phase Readiness

The phase (ID Preview, Suggested Cooldown & Secrecy) is code-complete and deployed: ADD-04, ADD-05, SECR-01, SECR-02 and SECR-03 all have their implementation gated and reviewed, `CreateAddDialog` remains byte-identical across all three plans (EDIT-03 held through the whole phase), and the 13-item checklist above is the human's remaining action before the phase can be marked verified. Phases 56-57 reuse `ns:SpellPreview`/`ns:SpellAuraSecrecy`/`ns:SecrecyWarns`/`ns:SecrecyExplanation` for the detailed-mode aura ID field; no blocker for that reuse was found in this review.

## Self-Check: PASSED

- FOUND: CDMTab.lua
- FOUND: .planning/phases/55-id-preview-suggested-cooldown-secrecy/55-03-SUMMARY.md
- FOUND commit: 16bc0dc (Task 1)

---
*Phase: 55-id-preview-suggested-cooldown-secrecy*
*Completed: 2026-09-28*
