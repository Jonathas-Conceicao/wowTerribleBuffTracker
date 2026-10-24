# Phase 77: Cleanup - Audit

**Scope:** code changed by Phases 73-76 only. Milestone base `3377a8e`
(`git diff --stat 3377a8e..HEAD -- . ':!.planning'`: BuffEngine.lua, CDMTab.lua, CLAUDE.md, Core.lua,
Display.lua, Providers.lua, scripts/install.ps1, tools/TBTProbe/*). Everything older is protected by
PROJECT.md's "No refactors during cleanup phases" Key Decision.

Every "has no reader" count below is tree-wide and non-comment:
`cat *.lua *.xml *.toc scripts/*.js | grep -v '^\s*--' | grep -c <name>` (a count of 1 is the
definition alone).

## Findings

| # | Item | Location | Proof (command -> result) | Verdict |
|---|------|----------|---------------------------|---------|
| 1 | `ns:CooldownBuffAuraID` has no caller since Phase 74 review CR-01 (4aea96f) replaced its only call with `ns:CooldownBuffAliveBuffs` | Core.lua:768-778 (comment + body); stale comment CDMTab.lua:1879 | non-comment tree-wide count -> `1` (the definition). `grep -n CooldownBuffAuraID *.lua` -> `CDMTab.lua:1879` (comment: "runtime readers are ... `ns:CooldownBuffAuraID`") and `Core.lua:773` (definition). `git grep -c CooldownBuffAuraID 3377a8e -- '*.lua'` -> nothing, so the milestone introduced it | remove (function + its 4-line comment); reword the CDMTab.lua comment to name `ns:CooldownBuffDuration` and `ns:CooldownBuffAliveBuffs` (with `ns:CooldownBuffTypedAuraID`) |
| 2 | Stale `ns:IsBagItemEntry` comment: says it is "narrower than ns:IsCooldownSlotEntry, which also answers true for trinket/pot" | Core.lua:592-593 | `grep -n "narrower than" Core.lua` -> `592`. Read against the bodies (Core.lua:580-596): both require `type(entry.itemID) == "number"` on the META_ITEM arm, and Trinket/Pot carry no numeric itemID, so both answer false for them. IsCooldownSlotEntry is wider only through its `USER_CD` arm | reword (comment only) |
| 3 | Stale Providers.lua cooldown-buff header: lists "an edit that turns the buff off (ns:UpdateTrackedBuff)" as an end | Providers.lua:213-214 | `grep -n "turns the buff off (ns:UpdateTrackedBuff)" Providers.lua` -> `214`. `grep -n "ns:ApplyCooldownBuffEdit(" BuffEngine.lua` -> `1392` (in `ns:UpdateTrackedItemBuff`), `1424` (definition), `1562` (in `ns:UpdateTrackedBuff`). The edit-time end is `ns:ApplyCooldownBuffEdit`, run by both commits, and it also ends a running buff whose Duration changed (BuffEngine.lua:1432-1433) | reword |
| 4 | Three milestone-added comment lines over 105 columns (tab width 4) | Providers.lua cooldown-buff header ("now, keeping the cast grace. ... On ns, so declaration order cannot make it nil.", 108); Providers.lua UserSpellProviderMixin:OnTrigger cooldown side ("can end on a readable aura loss. The cast is still not a timer, ...", 131); CDMTab.lua ApplyFieldEnabled header ("per-field code. The 0.5 grey and the white restore are the house convention, copied from the New Container", 110) | `git diff -U0 3377a8e -- BuffEngine.lua Core.lua Providers.lua Display.lua CDMTab.lua \| grep '^+[^+]' \| tr -d '\r' \| expand -t4 \| awk 'length($0) > 105'` -> those three comment lines plus one code line (`local placeholder = entry.label == nil or ...`, CDMTab.lua, stylua-formatted code, not a comment, out of this finding) | reword (re-wrap to ~100 columns, words unchanged) |
| 5 | `ns:StartCooldownBuffFromCast` walks `ns.CONTAINERS` with `ipairs` on every qualifying cast to find `entry.section`'s def | Providers.lua `ns:StartCooldownBuffFromCast` | `grep -n CONTAINER_BY_KEY Core.lua` -> `168`/`170` (built from ns.CONTAINERS), `280` (`ns:RegisterContainerDef` adds), `288` (`ns:UnregisterContainerDef` removes), so the keyed twin is always in step. `254`: "hidden"/"suggested" are reserved keys never registered, so a nil def refuses exactly as the loop's not-found case | fix (one `ns.CONTAINER_BY_KEY[entry.section]` read) |
| 6 | IN-03: end-of-save steps duplicated in `ns:UpdateTrackedItemBuff` and `ns:UpdateTrackedBuff` (ApplyCooldownBuffEdit, chat line, MarkTrackersDirty, MarkCooldownsDirty, UpdateDisplay) | BuffEngine.lua | both bodies added/changed by Phases 74/76 (`git diff 3377a8e..HEAD -- BuffEngine.lua`, hunks at +1313 and +1560) | unify -> `ns:FinishTrackerEdit` (plan 77-02) |
| 7 | `buffDuration` field is a copy of the duration field's build/reset/prefill/read/validate, and `buffAuraID`'s `follows` closure repeats `NotItemField` | CDMTab.lua (field list, ~2470-2560) | `follows = function(ctx) return ctx.kind ~= ns.KIND.META_ITEM end` at CDMTab.lua:2516-2518 is `NotItemField`'s body; the buffDuration row mirrors the duration row | unify -> shared duration-box helpers, `follows = NotItemField` (plan 77-02) |
| K1 | `ApplySlotCount`'s second `type(spellID) ~= "number"` guard | Display.lua:1113-1116 | Phase 75 review IN-02 skipped with a reason: the guard sits inside the `_cntGen`/`_cntKey` stamp gate; hoisting it adds ungated per-tick work | keep |
| K2 | Three stamp-clearing sets: `ClearCooldownStamps`, the live-timer branch's own-buff handover, `ApplySwipeLook`'s nils | Display.lua:859, ~1733-1745, 898 | read: each clears a different subset (full clear on another tracker; sweep + user-cd stamps keeping the count on own-buff handover; sweep stamps only on a look change). 75-REVIEW traces each. Merging changes which stamps survive a handover | keep |
| K3 | `ns:IsCooldownSlotEntry(entry) and ns:CooldownBuffDuration(entry)` pairs | BuffEngine.lua:1705 (`StartAllPreviewTimers`), `ns:ApplyCooldownBuffEdit`, Providers.lua `ns:StartCooldownBuffFromCast`, Display.lua `RenderIconContainer` | each is one expression; RenderIconContainer reuses its `slotEntry` local. A helper adds a call and removes no logic | keep |
| K4 | `ns:IsCooldownSlotEntry`'s META_ITEM arm repeats `ns:IsBagItemEntry` | Core.lua:580-596 | `git grep -c "IsCooldownSlotEntry\|IsBagItemEntry" 3377a8e -- Core.lua` -> 5: both predate the milestone | keep (protected) |
| K5 | Buff timer start/end unification | Providers.lua, BuffEngine.lua | every start goes through `ns:StartCooldownBuffFromCast` (non-comment count 3: definition + the userCd and bag-item callers); every edit-time end through `ns:ApplyCooldownBuffEdit` (count 3: definition + both commits) | keep (already unified) |

### Sweep for anything else the milestone added

File-level names the milestone added (`git diff 3377a8e..HEAD -- BuffEngine.lua CDMTab.lua Core.lua Display.lua Providers.lua`),
non-comment tree-wide counts: `ApplyCooldownBuffEdit` 3, `CooldownBuffAliveBuffs` 3,
`CooldownBuffAuraID` **1**, `CooldownBuffDuration` 6, `CooldownBuffTypedAuraID` 4, `FillUserBuffProc` 5,
`StartCooldownBuffFromCast` 3, `UpdateTrackedItemBuff` 2, `ApplyFieldEnabled` 2, `ApplySlotCount` 3,
`ApplySwipeLook` 3, `BuffFieldEnabled` 3, `CarriesCooldownBuff` 4, `NotItemField` 5. Only
`CooldownBuffAuraID` is unused (finding 1).

Saved keys: `buffEnabled` (10), `buffAuraID` (10), `buffDuration` (16). Writers: the dialog rows
(`entryKey = "buffEnabled"` / `"buffDuration"`, `buffAuraID` through `BuildFollowSpellIDField`'s id)
feeding the fieldKeys loop of `ns:UpdateTrackedBuff`, and `ns:UpdateTrackedItemBuff`
(BuffEngine.lua:1384-1390). Runtime readers: `ns:CooldownBuffDuration` (buffEnabled, buffDuration)
and `ns:CooldownBuffTypedAuraID` (buffAuraID). All live.

Proc and icon fields: `proc.itemID` (written Providers.lua:255, read Display.lua:352), `_auraLook`
(3), `_cntGen` (3), `_cntKey` (3), `itemTooltipProc` (3: built, filled, read by the hover),
`shownItemID` (3: reset, compared, written). All have a writer and a reader. No new finding.

## Hot-path review

| Path | Verdict | Reason |
|------|---------|--------|
| RenderIconContainer, live-timer branch | no change | `slotEntry` computed once and reused for the handover, the icon and the look; the handover gate is two compares on the steady path; `ApplySlotCount` is a stamp compare; `ApplySwipeLook` one compare; `ns:CooldownBuffDuration` is field reads only. No allocation |
| RenderIconContainer, cooldown-slot branch | no change | `ns:IsCooldownSlotEntry` runs only when the timer branch did not (the elseif chain is exclusive), so it is never evaluated twice per icon |
| ApplyCooldownSlot | no change | `ApplySwipeLook(icon, false)` is one compare; the `_cdKey ~= entry.key` reset of `_userCdState`/`_userCdGrey` is one compare; `ApplySlotCount` is stamped |
| ApplyUserCooldown | no change | body not changed by the milestone; ApplySwipeLook and the key-change reset only nil its stamps on a handover |
| ApplySwipeLook | no change | stamped on `_auraLook`; literal colour numbers; secret-safe boolean compare |
| ApplySlotCount | no change | stamped on `_cntGen`/`_cntKey`; its duplicate sanitise kept (K1, 75 IN-02) |
| ApplyCachedIcon use in the timer branch | no change | same stamp compares as ApplyCooldownSlot's; the per-tick SetTexture predates the milestone |
| ns:StartCooldownBuffFromCast | fixed | the `ipairs(ns.CONTAINERS)` walk becomes one `ns.CONTAINER_BY_KEY` read (finding 5). Pooled proc and pooled aliveBuffs allocate nothing. Its own UpdateDisplay plus the dispatcher's redraw for a returned buff proc can mean two redraws on one cast, accepted with the same documented trade as `ns:StartReminderFromCast`. `ns:QueueCastAuraRecheck` coalesces through `castRecheckPending` |
| MetaItemBagProviderMixin:OnTrigger | no change | one-hash-lookup early-out (`itemUseSpellToID[spellID]`) unchanged; the entry lookup is reused; the buff start runs only on a catalogued item use |
| UserSpellProviderMixin:OnTrigger, cooldown side | no change | one extra ns call only when a cooldown resolved (`if cdKey`) |
| ns:ScanActiveTimersForCancellation interplay | no change | not changed by the milestone; a cooldown-buff proc carries aliveBuffs (family or pooled list) and castAt from `ns:FillUserBuffProc`, so the cast grace holds. The debug-only label table predates the milestone |
| ns:RefreshAuraStates | no change | not changed by the milestone; walks `ns.reminderKeys` only, built in `ns:RebuildDetailedRuleIndex` from `ns:IsReminderEntry(entry)` entries, so a userCd or metaItem key is never in it. No interplay |
| Not hot paths (recorded for completeness) | no change | `ns:StartAllPreviewTimers` runs once when the preview opens; `ns:UpdateTrackedItemBuff`, `ns:ApplyCooldownBuffEdit`, `ns:UpdateTrackedBuff` run at edit time |

## Scripts review

Plan 77-02. No script was changed: the review found no defect the milestone introduced.
`scripts/release.bat` was read only and never run.

| Check | Command | Result | Verdict |
|-------|---------|--------|---------|
| CLAUDE.md Architecture list | `git diff --name-status 3377a8e -- . ':!.planning'` | M BuffEngine.lua, CDMTab.lua, CLAUDE.md, Core.lua, Display.lua, Providers.lua, scripts/install.ps1, tools/TBTProbe/TBTProbe.toc, tools/TBTProbe/install-probe.bat; the only A is `tools/TBTProbe/DurationProbe.lua`, inside the already-listed `tools/TBTProbe/`. No file was removed or repurposed | no change |
| install.ps1 flavour list | `grep -n flavors scripts/install.ps1` | `$flavors` holds `'_forever_'` (line 29) and no `'_classic_beta_'`; that one-word swap is the whole install.ps1 diff since 3377a8e | no change. Phase 73 review WR-01 (a stale TBT copy in `_classic_beta_` is no longer updated) stays declined by user decision; IN-01/IN-02 stay as written. The stale `_classic_beta_` copy is on the Phase 78 checklist |
| install.ps1 fixture deploy | temp dir with `_forever_` and `_retail_`, `TBT_WOW_ROOT="$(cygpath -w "$FIX")" powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1` | 23 TOC-derived files deployed to both folders; both hold `TerribleBuffTracker.toc` and `Core.lua`; `find -name DurationProbe.lua` finds nothing; the deployed TOC reads `## Version: v0.5.2-54-g1d206cb-dev` (0 `@project-version@`), the repo TOC still holds `@project-version@` | pass |
| install.bat | read | still `powershell ... -File "%~dp0install.ps1" %*` then `exit /b %errorlevel%`; unchanged since 3377a8e | no change |
| release.bat | read only (never run) | refuses a branch other than main unless `TBT_ALLOW_BRANCH=1`, tags `v<version>` with `git tag -a`, pushes `origin main` plus the tag; `git diff --quiet 3377a8e -- scripts/release.bat` succeeds | no change |
| .pkgmeta | read | ignores `scripts`, `tools`, `.planning`, `Media/Source`, `"*.png"`, the docs (CHANGELOG.md, CLAUDE.md, README.md, LICENSE) and `.github`; one `package-as`, so packaging covers the one TOC; unchanged since 3377a8e | no change |
| .github/workflows/release.yml | `git diff --quiet 3377a8e -- .github` | unchanged | no change |
| TerribleBuffTracker.toc | `git diff --quiet 3377a8e -- TerribleBuffTracker.toc` | unchanged; the shipped load list is the same | no change |
| aura-read-gate | `node scripts/aura-read-gate.js` and `--selftest` | `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`; `AURA-READ SELFTEST PASS (30 cases)` | pass |
| migrate-dryrun | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (13 cases)`. `CURRENT_SCHEMA_VERSION = 12` at both 3377a8e and HEAD (BuffEngine.lua:78), so no live dry-run is needed | pass |
| stylua and line endings | `stylua --check .`; `git ls-files --eol '*.lua' \| grep -v w/crlf`; `grep -l $'\r\r' *.lua` | clean; every tracked `.lua` is `w/crlf`; no `\r\r` | pass |

## Deferred to Phase 78

In game, Midnight retail:

- Add and Edit a cooldown, a buff and a reminder: the Duration box still shows, prefills,
  validates and saves as before (shared duration-box helpers, plan 77-02).
- A cooldown's and a bag item's buff Duration box still validates ("Enter the buff duration")
  and saves.
- A bag item's buff Aura ID still starts empty and never follows (`follows = NotItemField`).
- The edit chat lines read as before (`ns:FinishTrackerEdit`): "Updated <label> (<kind>, ID:
  <ids>, <n>s)." for a spell, "Updated <label> (item, buff <n>s|off)." for a bag item.
- A cooldown with its buff on, in an icon container, still starts its buff on cast.
- The stale TBT copy in `_classic_beta_` (Phase 73 WR-01, declined) is still noted.
