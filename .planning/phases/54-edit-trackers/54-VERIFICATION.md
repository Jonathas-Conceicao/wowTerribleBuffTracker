---
phase: 54-edit-trackers
verified: 2026-09-28T12:50:53Z
status: human_needed
score: 5/5 roadmap success criteria verified statically (in-game confirmation pending)
overrides_applied: 0
human_verification:
  - test: "Edit entry visibility (retail and Forever). In /tbt, right-click a user buff tile and a user cooldown tile, then Lust, trinket, pot, a racial buff, a racial cooldown and a bag-item tile"
    expected: "User buff and user cooldown tiles show 'Edit' just above the divider before 'Remove'. None of the built-in tiles (including the racial cooldown) show 'Edit'"
    why_human: "MenuUtil context menu rendering needs a live client"
  - test: "Prefilled edit dialog. Click Edit on a user buff tile, then on a user cooldown tile"
    expected: "Titles read 'Edit Buff Tracker' / 'Edit Cooldown Tracker', the button reads 'Save', Spell ID and Duration are prefilled (a 120 s tracker shows '2m'). On Forever only, 'Cover all ranks' matches the saved value. On retail there is no checkbox"
    why_human: "Frame layout and text need a live client"
  - test: "Duration-only edit. Change only the duration, Save, cast the spell, then do a real logout to character select and back (not /reload)"
    expected: "The next cast uses the new duration, and the value is still there after logout/login. One 'Updated ...' chat line appears"
    why_human: "Needs cast events and SavedVariables persistence"
  - test: "Spell ID edit. Start a timer/cooldown on a tracker, then Edit it to a different spell ID of the same kind and Save. Cast the old spell, then the new spell. Log out and back in"
    expected: "The tile stays in the same container at the same position with the new spell's icon. The running timer/cooldown for the old ID disappears. Casting the old spell starts nothing, and casting the new spell starts the tracker. The change survives logout/login"
    why_human: "Needs live cast dispatch, rendering and persistence"
  - test: "Duplicate rejection. In Edit and in Add, type an ID already tracked as the same kind. On the Cooldowns tab also try an ID tracked as a racial cooldown. Then re-enter the edited tracker's own ID"
    expected: "Save/Add disables and red 'Already tracked as a buff' / 'Already tracked as a cooldown' appears. The existing tracker is unchanged. Re-entering the tracker's own ID is accepted and Save re-enables"
    why_human: "Live-validation UI needs a live client"
  - test: "Add dialog regression (both flavours). Open '+'"
    expected: "Opens empty with Add disabled. '2min' shows the s/m hint. Tab cycles boxes and Enter confirms. A new tracker lands in Not Displayed. Forever shows 'Cover all ranks' checked by default. Retail shows no checkbox, and its red hint now sits below the Duration box"
    why_human: "Visual layout; the dialog was rebuilt around the field walker"
  - test: "Remove-then-re-add. Start a cooldown, remove that tracker mid-cooldown, then re-add the same spell ID as a cooldown"
    expected: "The re-added tracker shows ready. It does not inherit the old cooldown"
    why_human: "Needs live cooldown state"
  - test: "Dismissal. With the Edit dialog open, switch Buffs/Cooldowns tabs, close the CDM, and press Escape (one at a time), then reopen Edit on the same tracker"
    expected: "Each action closes the dialog and saves nothing. Reopening shows the saved values, not the abandoned edit"
    why_human: "Needs a live client"
  - test: "DECISION (not a defect): on a character with a racial, add that racial's spell ID fresh on the Cooldowns tab, and separately Edit an existing user cooldown to that same ID"
    expected: "Fresh add creates a racial cooldown (metaSkillCd) with no Edit entry. The edited tracker stays a user cooldown (userCd) that still offers Edit. The user decides whether to keep this or unify it in a later phase"
    why_human: "Product decision recorded in 54-01-SUMMARY"
---

# Phase 54: Edit Trackers Verification Report

**Phase Goal:** A player can change any input of a user-defined tracker after creating it, spell ID included, without deleting and re-adding it
**Verified:** 2026-09-28T12:50:53Z
**Status:** human_needed
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths (ROADMAP success criteria, merged with the PLAN must_haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | You can open an edit dialog from any user buff or user cooldown tile. Built-in meta tiles offer none | VERIFIED (static) | CDMTab.lua:386-419: the tracked-tile menu captures `trackerKey = self.spellID` (the tracker key, CDMTab.lua:1094/1102) and adds `CreateButton("Edit")` only when `ns:IsEditableTracker(entry)` is true. BuffEngine.lua:739-741 returns true only for `trackerType == USER_BUFF or USER_CD`. It reads the kind field, not the key shape, so metaSkill, metaSkillCd, metaItem and userItem get no entry. The Suggested-tile menu returns earlier (CDMTab.lua:384). The entry sits before `CreateDivider()` and "Remove" |
| 2 | The dialog opens prefilled (spell ID, duration, and cover-all-ranks on Forever). A change takes effect on the next cast and survives logout | VERIFIED (static), persistence needs a human | `OpenForEdit` (CDMTab.lua:1686-1721) re-checks editability, sets `ctx.kind = entry.trackerType`, and runs each field's `reset` then `prefill(state, entry)`. The prefills read the real entry fields `entry.spellID` (1286), `entry.duration` through `FormatDuration` (1329-1334; maxLetters raised so nothing is truncated) and `entry.coverAllRanks == true` (1380). Save goes to `ns:UpdateTrackedBuff(ctx.editingKey, values.spellID, values.duration, values, dialog.fieldEntryKeys)` (1640-1641). That writes to `ns.db.trackedBuffs` (the SavedVariables table), sets `entry.duration`, copies the non-engine field keys (BuffEngine.lua:1025-1033), and calls `RebuildRankIndex` (which rebuilds the cast index, Core.lua:924). The cast path reads `entry.duration` fresh on every cast (Providers.lua:182) |
| 3 | A spell ID change keeps the container and position, shows the new icon, drops the old timer/cooldown, and the next cast of the new spell starts it | VERIFIED (static) | BuffEngine.lua:1011-1023: when the key changes it calls `ClearTrackerRuntimeState(oldKey)`, which clears `activeTimers`, `previewTimers`, `cooldownStarts`, `cooldownOverrides` and `ReleaseProc` (procPool/aliveBuffsPool/displayInfoPool) and marks cooldowns dirty (785-794). The SAME entry table moves to `TrackerKey(kind, spellID)`, so `section` and `layoutOrder` travel with it, and `spellID`, `key` and `label` are updated. `PreallocateProc(newKey)` follows. Then `RebuildRankIndex` rebuilds `buffKeyBySpell`/`cooldownKeyBySpell` (Core.lua:870-905, 924) and rank families, and `MarkTrackersDirty`, `MarkCooldownsDirty` and `UpdateDisplay` run. The dialog then calls `RefreshTBTSections` and `StartAllPreviewTimers`. The icon comes from `GetDisplayInfoForKey(newKey)`, which reads `entry.spellID` (Providers.lua:206, 231). `keyToProvider` is a static meta-key map, so no per-tracker registry goes stale |
| 4 | An ID already tracked as the same kind is rejected with a message and the tracker is left unchanged | VERIFIED (static) | `ns:FindTrackerConflict(kind, spellID, exceptKey)` (BuffEngine.lua:752-778) checks the buff namespace, or the cooldown namespace including userCd/metaSkillCd collisions. `exceptKey` stops a tracker from conflicting with itself. The live validate in the spellID field (CDMTab.lua:1291-1301) disables confirm and returns "Already tracked as a buff/cooldown", and the error label shows it (1578-1580). The engine repeats the check before writing anything (1002-1009). On refusal the confirm handler shows the reason and keeps the dialog open (1642-1645). Add refuses the same way (BuffEngine.lua:864-874), which fixes the silent-overwrite bug |
| 5 | Add and Edit share one field definition, so one new table entry appears in both with no second change | VERIFIED (static) | `TRACKER_FIELDS` (CDMTab.lua:1262-1389) is the only place fields are declared. The walker (1461-1480) builds each available def, records `entryKey` into `fieldEntryKeys`, and adds any `state.editBox` to the Tab/Enter ring. `Layout`, `ValidateAll`, `RefreshState`, the confirm read loop (1615-1620), `OpenForAdd` (reset loop) and `OpenForEdit` (reset+prefill loop) all iterate `fieldStates` without naming a field. For persistence, Add copies every non-`ENGINE_OWNED` key from `opts.fields` (BuffEngine.lua:885-891), and Update copies every non-`ENGINE_OWNED` key in `fieldKeys` (1026-1033). A new def with `entryKey = "foo"` is therefore built, laid out, validated, prefilled, read and persisted in both modes with no other edit. The confirm handler names only `values.spellID`/`values.duration`, which the contract documents as positional engine arguments |
| 6 | (PLAN 54-01) `ns:RemoveTrackedBuff` clears cooldownStarts/cooldownOverrides | VERIFIED | BuffEngine.lua:944 calls `ClearTrackerRuntimeState(key)` |
| 7 | (PLAN 54-01) metaSkillCd and every other built-in kind are refused by UpdateTrackedBuff | VERIFIED | BuffEngine.lua:983-985 |
| 8 | (PLAN 54-03) Dismissed by DismissTBTDialogs and by Escape, and closing clears the edit context | VERIFIED (static) | `UISpecialFrames` insert (CDMTab.lua:1414). `DismissTBTDialogs` hides `ns.tbtAddDialog` (2365-2372). `OnHide` runs `wipe(ctx)` (1726-1728) |

**Score:** 5/5 roadmap truths and all PLAN truths verified statically. In-game confirmation is pending.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BuffEngine.lua` | UpdateTrackedBuff, FindTrackerConflict, IsEditableTracker, ClearTrackerRuntimeState, SpellLabel, TrackerKindWord; Add opts.fields plus duplicate rejection | VERIFIED | All present (717-1083) and substantive, and called from CDMTab.lua and from Add/Remove |
| `CDMTab.lua` | FormatDuration, TRACKER_FIELDS, field-agnostic CreateAddDialog, OpenForAdd/OpenForEdit, Edit menu entry | VERIFIED | 1203-1731, 386-419, 2019, 2042 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| UpdateTrackedBuff | ClearTrackerRuntimeState(oldKey) | only when the key changes, before the move | WIRED (BuffEngine.lua:1015) |
| RemoveTrackedBuff | ClearTrackerRuntimeState(key) | replaces the inline clear | WIRED (944) |
| Add/Update | FindTrackerConflict | cast index plus direct key probe | WIRED (864, 1002) |
| spellID field validate | FindTrackerConflict(ctx.kind, ..., ctx.editingKey) | live, on every keystroke | WIRED (CDMTab.lua:1296) |
| confirm (add) | AddTrackedBuff opts.fields | `fields = values` | WIRED (1623-1627) |
| confirm (edit) | UpdateTrackedBuff(ctx.editingKey, ...) | values plus fieldEntryKeys | WIRED (1640-1641) |
| addSquare OnMouseUp | OpenForAdd() | | WIRED (2042) |
| context menu "Edit" | ns.tbtAddDialog.OpenForEdit(trackerKey) | gated on IsEditableTracker | WIRED (409-412) |
| UpdateTrackedBuff | cast index plus rank index | RebuildRankIndex → RebuildCastIndex | WIRED (1067-1071, Core.lua:924) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Edit dialog prefill | spellID/duration/coverAllRanks | `ns.db.trackedBuffs[key]`, read in OpenForEdit | Yes | FLOWING |
| Save | values → entry | UpdateTrackedBuff writes to the SavedVariables table | Yes | FLOWING |
| Tile icon after an ID change | icon | GetDisplayInfoForKey → entry.spellID → GetSpellIcon | Yes | FLOWING |
| Next cast | cdKey/ownerKey | cooldownKeyBySpell/buffKeyBySpell, rebuilt after the move | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Lua parses and is formatted | `stylua --check BuffEngine.lua CDMTab.lua` | exit 0 | PASS |
| Line endings | `git ls-files --eol` | both `w/crlf attr eol=crlf` | PASS |
| Migration self-test (phase gate) | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (7 cases)` | PASS |
| Phase scope | `git diff --stat 991ac2f HEAD` | only BuffEngine.lua, CDMTab.lua and .planning changed | PASS |
| Hot paths untouched | diff hunk headers | BuffEngine hunks start after GetActiveTimers ends; none fall in OnSpellCastSucceeded/Scan/OnUnitAura | PASS |
| In-game behaviour | none | no client | SKIP → human |

### Probe Execution

No probes are declared for this phase, and it is not a migration/tooling phase. SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| EDIT-01 | 54-03, 54-04 | SATISFIED (static) | Truth 1 |
| EDIT-02 | 54-01, 54-03, 54-04 | SATISFIED (static) for spell ID, duration and cover all ranks | Truth 2. REQUIREMENTS.md:137 states the "every detailed-tracking option" part is met through EDIT-03 and verified in Phases 56-57 |
| EDIT-03 | 54-02, 54-03, 54-04 | SATISFIED (static) | Truth 5 |
| EDIT-04 | 54-01, 54-02, 54-03, 54-04 | SATISFIED (static) | Truths 3 and 4 |

Every ID in the PLAN frontmatter is accounted for. REQUIREMENTS.md maps no other ID to Phase 54, so there are no orphans.

### CONTEXT decisions honoured

- The Edit entry is in the context menu before the Remove divider, and only for userBuff/userCd. Racial cooldowns are excluded, and the kind is read from the kind field: yes.
- One frame in two modes, titled "Edit Buff/Cooldown Tracker" with "Save", prefilled, and covered by DismissTBTDialogs: yes.
- Commit semantics: in place when the ID is unchanged; otherwise the record moves, section/layoutOrder are kept, the label is re-derived, all runtime state including cooldownStarts/cooldownOverrides is cleared, and PreallocateProc, RebuildRankIndex, MarkTrackersDirty, RefreshTBTSections and StartAllPreviewTimers run. One chat line: yes.
- Duplicate rejection in Edit and Add, plus the Remove cooldown-state fix: yes.
- No InCombatLockdown guard: yes, matching the decision.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| BuffEngine.lua / CDMTab.lua | none | TBD/FIXME/XXX | none | No debt markers |
| BuffEngine.lua | 1026-1033 with CDMTab.lua:1617 | A field whose `visible()` is false at Save time is not read, and UpdateTrackedBuff then writes `nil` over that entry key | Info (Phases 55-57) | No field defines `visible()` today, so this is not a current defect. Once Phases 56-57 add conditionally hidden detailed-tracking options, an edit clears any option hidden at Save time. That is fine if "hidden means not applicable" is the intended meaning. If not, those phases should skip hidden fields in `fieldKeys` rather than nil them |

### Human Verification Required

The frontmatter `human_verification` list holds the 9 in-game items. They mirror the 54-04-SUMMARY checklist, which is deployed to `_retail_` and `_classic_beta_`. Run each one on both Midnight retail and the Forever beta, and use a real logout/login (never `/reload`) for the persistence items.

### Gaps Summary

The code shows no defects. Every data path traces to real sources:
- The prefill reads the entry's real fields.
- Save writes only through `ns:UpdateTrackedBuff`.
- A key move clears all old-key runtime state, carries the same entry table, and rebuilds both the cast index and the rank index.
- The shared field walker names no field, so a new `TRACKER_FIELDS` entry reaches both modes and is persisted by both engine functions without other edits.

Status is `human_needed` only because the behaviour can be confirmed only in-game.

---

_Verified: 2026-09-28T12:50:53Z_
_Verifier: Claude (gsd-verifier)_
