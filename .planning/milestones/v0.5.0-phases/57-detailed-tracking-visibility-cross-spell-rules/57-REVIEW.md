---
phase: 57-detailed-tracking-visibility-cross-spell-rules
reviewed: 2026-09-28T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - Core.lua
  - BuffEngine.lua
  - Providers.lua
  - Display.lua
  - CDMTab.lua
findings:
  critical: 0
  warning: 3
  info: 7
  total: 10
status: issues_found
---

# Phase 57: Code Review Report

**Reviewed:** 2026-09-28
**Depth:** deep
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Scope: `git diff 02d6f37..HEAD -- '*.lua'`. I read the full current code around every hunk and traced these paths: OnTrigger → ApplyEndOnCast / FillUserBuffProc → DispatchEventToProviders; UNIT_AURA → OnUnitAura → RefreshAuraStates → StartUserBuffFromAura → ScanActiveTimersForCancellation; every RebuildRankIndex / RebuildCastIndex / RebuildDetailedRuleIndex call site (add, update, remove, migration, world entry, SPELLS_CHANGED, CDM drop); GetActiveTimers' lazy expiry; ApplyUserCooldown; and both render functions' branch chains against SlotDraws.

Tool results: `node scripts/aura-read-gate.js` PASS (10 reads in 3 allowlisted readers), `--selftest` PASS (30 cases), `node scripts/migrate-dryrun.js --selftest` PASS (7 cases). All five files are `w/crlf`. CreateAddDialog's text is byte-identical between `02d6f37` and HEAD (same SHA-1 on both extracts).

These parts are sound:

- **Aura-driven start.** It runs out of combat only, because RefreshAuraStates returns early in combat and StartUserBuffFromAura checks again. It cannot double-start, because it requires `ns.activeTimers[key] == nil`. The hybrid condition cannot loop: a proc started from real timing sets `expiresAt = expirationTime`, and once that time passes, ReadableAuraTiming's `expirationTime > now` test closes the path. An edge fires once because the state becomes `true`. The start reads only through `ns:ReadPlayerAura`, and GetPlayerAuraBySpellID matches an aura from any caster. The visibility list and the scan's aliveBuffs agree for every entry shape, so the scan cannot cancel a timer the refresh would restart on the next event.
- **Secret values.** ReadableAuraTiming calls `issecretvalue` on both fields before any `type()` check or comparison.
- **Cross-spell rules.**
  - Skip rule: it uses the same `buffKeyBySpell`/`rankIndex` and `cdKey` lookups as the two start sides.
  - Buff ends vs cooldown resets: a buff end calls UpdateDisplay itself, and a cooldown reset calls MarkCooldownsDirty. ApplyUserCooldown re-reads `cooldownStarts` every tick, so the reset shows at once.
  - The `auraState = false` write is a sibling of the timer clear, not nested inside it.
  - `endKeysBySpell` is replaced wholesale on every rebuild path.
  - The retail branch never calls ResolveRankFamily.
  - The Forever cache is wiped at PLAYER_ENTERING_WORLD, and at SPELLS_CHANGED only out of combat.
  - ParseSpellIDList rejects empty tokens, non-digits, 0 and values over 2^31-1, and it enforces the cap of 8 distinct IDs.
  - The dialog rejects the tracker's own spell ID.
- **Hot paths.** Nothing is allocated on the cast, render or UNIT_AURA paths, and no new `pairs()` runs per frame. The render path makes no aura reads.
- **Upvalue order and closures.** `RelatedSpellID` is declared above RebuildDetailedRuleIndex. `MAX_CAST_RULE_IDS`, `ns:SyncVisibilityChecks` and `ns:ParseSpellIDList` are declared above TRACKER_FIELDS. The visibility field's `state` table is created before its three OnClick closures. Every cross-file helper is an `ns` method that is only called at event time.
- **Dialog.** The three visibility boxes stay exclusive, and SetChecked fires no OnClick, so there is no recursion. `endOnCast`'s read returns a fresh array, and its prefill joins a copy of the saved one. Hidden children are not validated and not read, so their saved values persist (WR-02). `keepOnAuraLoss` is still buff-only.
- **Simple and hidden trackers.** A tracker switched back to simple leaves `visibilityKeys`, and the rebuild clears its `auraState`. A hidden-section tracker never gets an aura start and never counts toward container activity.

The defects are in how the display uses the cache. A gated-off icon leaves a hole in non-centred grids. The cache watches the wrong ID set for Forever cover-all-ranks trackers. In combat, the cache stays frozen even after the tracker's own timer has proved the state wrong.

## Warnings

### WR-01: A gated-off icon leaves an empty cell in every non-centred grid, including all cooldown containers

**File:** `Display.lua:2320-2323, 2375, 2438-2441, 2656`

**Issue:** The visibility gate hides a slot's widget (line 2438), but the slot stays in `slots`. The non-centred layout places icons by raw `slotIndex` through `ns:GridSlotPlacement` (line 2375), and the container is sized from `#slots` (line 2656). A slot hidden by its visibility mode therefore still takes its cell. Only the centred path compacts through SlotDraws, and centred is a buff-container option only (`ns:GetContainerCategory(def) == "buffs"`), so cooldown containers never use it.

Failure scenario:

1. A cooldown container holds A, B and C. B is a detailed cooldown tracker set to "Only while the aura is up".
2. Out of combat, B's aura is missing.
3. The grid draws A, an empty cell, then C, and the container keeps its three-cell size.

Cooldown slots were previously "always shown", so a cooldown grid never had holes before this phase. The same thing now happens in buff containers with "hide when inactive" off, where every slot used to draw a placeholder. The bar path does not have this problem, because it drops gated-off entries from `slots` (lines 2016-2019).

**Fix:** Filter at slot-build time, the same way the bar path does. This keeps the chain, SlotDraws and sizing consistent, and it allocates nothing:

```lua
if entry.section == def.key and ns:IsRacialKeyVisible(dbKey) then
	if ns:VisibilityGate(dbKey, entry) ~= false or ns.configOpen or iconEditing then
		entry.key = dbKey
		table.insert(slots, entry)
	end
end
```

`iconEditing` must be computed before this loop. It already is, at line 2305. The `gate == false` branch at line 2438 then becomes unreachable and can go.

### WR-02: Visibility watches a single ID for a cover-all-ranks tracker without an aura ID, and for every cooldown, so a Forever down-rank flips the state to "absent"

**File:** `Core.lua:976`, `BuffEngine.lua:1474-1498`, `Core.lua:1138-1147`

**Issue:** RefreshAuraStates checks the whole rank list only when `ns.detailedRankFamilies[key]` exists. RebuildRankIndex builds that list only for a USER_BUFF that has both "Cover all ranks" and an aura ID. In every other case the cache reads the single ID `ns:DetailedAuraID(entry) or entry.spellID`. The timer does not work this way: FillUserBuffProc gives a cover-all-ranks tracker with no aura ID `aliveBuffs = ns.rankFamilies[ownerKey]`, which holds every rank. As a result the scan and the cache disagree about the same aura.

Failure scenario on Forever: a detailed buff tracker for the max rank, with "Cover all ranks" on, no aura ID, and visibility set to "absent".

1. The player casts rank 2. OnTrigger starts the timer and writes `auraState = true`, so the reminder hides.
2. At the next out-of-combat UNIT_AURA, `ReadPlayerAura(maxRankID)` returns readable and absent, and the state becomes `false`.
3. The "absent" reminder now shows while the rank 2 buff is up, and the scan keeps the timer alive because rank 2 is in aliveBuffs.

With "present" mode instead, the running timer is hidden. The aura-driven start also never fires for an aura from a lower rank.

Cooldown trackers have the same gap even when they do have an aura ID, because `detailedRankFamilies` is USER_BUFF-only (Core.lua:1138).

This is the same failure 56-REVIEW WR-04 fixed for cancellation. 57-CONTEXT's "Otherwise the watched list is ... as before" covers only the aura-ID case, so the user should confirm the change.

**Fix:** In RefreshAuraStates, fall back to the shared cast family, which is also the aura list on Forever. Both arrays are read-only and prebuilt, so nothing is allocated:

```lua
local list = ns.detailedRankFamilies[key]
if list == nil and entry.coverAllRanks and ns:DetailedAuraID(entry) == nil then
	list = ns.rankFamilies[key]
end
```

Also, either extend the `detailedRankFamilies` build to USER_CD, or record that cooldown visibility watches exactly one ID.

### WR-03: In combat, the frozen cache contradicts the tracker's own timer: "present" keeps an idle icon after the buff ends, and "absent" never reminds

**File:** `BuffEngine.lua:1455-1457`, `Providers.lua:240-245`, `BuffEngine.lua:716-722, 1326-1330`

**Issue:** The player's own cast writes `auraState = true`. In combat, nothing can write `false` again except a cross-spell rule, because RefreshAuraStates returns on `InCombatLockdown()` before reading anything.

Failure scenario A ("present", the common case):

1. The player casts the tracked buff in combat. The timer runs and the icon shows.
2. The timer expires, or ScanActiveTimersForCancellation cancels it. The scan only checks `ShouldAurasBeSecret()`, so it can read in combat whenever that is false, and it proves the aura is gone.
3. `VisibilityGate` still returns `true`, so the placeholder branch draws a full-colour idle icon for the rest of the fight, even under "hide when inactive". An "always" tracker would have hidden it. The scan and the cache now disagree after a real, readable read.

Failure scenario B ("absent", the main use of a reminder):

1. The player casts the buff in combat, and the reminder hides.
2. The buff runs out mid-fight. The reminder does not come back until PLAYER_REGEN_ENABLED, which is exactly when the player no longer needs it.

57-CONTEXT's rule is "an unreadable read keeps the last known state ... frozen until a real read is possible". A readable read, or the tracker's own timer ending, is not an unreadable read.

**Fix:** Move the `InCombatLockdown()` guard so that it covers only the aura-driven start, and let the cache refresh behind the same gates the scan uses. ReadPlayerAura already returns `readable = false` for any hidden aura, so an unreadable read still keeps the last state (DTRK-06 holds by construction), and there is still no read per frame. For Midnight, where combat reads are usually secret, also decide whether a visibility-gated key's timer ending (lazy expiry at BuffEngine.lua:721, or a cancellation at :1330) should write `auraState[key] = false`. That is one table write and allocates nothing. The same-cast skip and cast-evidence rules are unaffected. This is a user decision, because it relaxes "frozen".

## Info

### IN-01: Detailed settings on a racial cooldown are saved but never used, and the tracker cannot be edited

**File:** `BuffEngine.lua:887, 920-925`

**Issue:** The Cooldowns tab now offers Detailed tracking. For a racial spell ID, AddTrackedBuff mints `META_SKILL_CD` through `ns:CooldownKindFor`, and it copies `detailed`, `visibility`, `auraID` and `endOnCast` onto the entry. Every runtime gate requires `USER_CD` (RebuildDetailedRuleIndex, VisibilityGate, ApplyEndOnCast), and `ns:IsEditableTracker` refuses `META_SKILL_CD`. The settings therefore do nothing, and the user cannot change them.

**Fix:** Hide the detailed children when the typed spell ID is a racial (check `ns:IsRacialSpellID(spell.editBox:GetNumber())` in `DetailedModeOffered`'s callers). Alternatively, drop the detailed keys in AddTrackedBuff when `kind ~= ctx.kind`.

### IN-02: Out of combat, the next UNIT_AURA undoes a cross-spell end if the aura is still readable

**File:** `BuffEngine.lua:1204-1213, 1509-1519`

**Issue:** ApplyEndOnCast sets `auraState = false`. If A's aura is still present at the next out-of-combat UNIT_AURA, the edge `previous ~= true` fires and StartUserBuffFromAura restarts A. That is correct when the aura really persists. It can also happen when B's own UNIT_AURA arrives before A's removal is processed. The next event then cancels A again, unless "End when the aura is lost" is off, in which case the restarted timer survives.

**Fix:** None is required. If in-game testing shows it, suppress the aura start for a key for one render interval after ApplyEndOnCast ends it.

### IN-03: The cached state is not invalidated when the watched list changes but the aura ID does not

**File:** `Core.lua:1037-1046`

**Issue:** The invalidation compares only `visibilityAuraID`. Turning "Cover all ranks" on or off changes the watched list (`detailedRankFamilies`) with the same single ID, so an in-combat edit keeps a state that was read against the old list until combat ends.

**Fix:** Also clear `auraState[key]` in the Save path (UpdateTrackedBuff) whenever `coverAllRanks` is among the read keys and has changed.

### IN-04: A misfiled cooldown's gate keeps a bar container visible while it draws nothing

**File:** `BuffEngine.lua:1387-1401`, `Display.lua:1982, 2040-2046`

**Issue:** `VisibilityShowsIn` does not exclude cooldown-slot entries. The bar reminder loop does exclude them (`not ns:IsCooldownSlotEntry(entry)`). A USER_CD filed in a bar container with a `true` gate therefore keeps that container shown under "hide when inactive" with nothing in it.

**Fix:** Pass the container kind in, or add `and not ns:IsCooldownSlotEntry(entry)` when the caller is RenderBarContainer.

### IN-05: A cooldown's "present" or "absent" mode with a blank aura ID watches the cooldown spell's own aura

**File:** `Core.lua:976`, `CDMTab.lua:2126-2129`

**Issue:** Most cooldown spells apply no aura with their own ID. For those, "Only while the aura is up" hides the cooldown permanently once the first out-of-combat read lands, and "absent" is the same as "always". The dialog gives no hint.

**Fix:** When `ctx.kind == USER_CD` and the mode is not "always", require an aura ID in the visibility field's validate, or show a hint.

### IN-06: An aura reapplied by someone else does not refresh a running aura-started timer

**File:** `BuffEngine.lua:1514`

**Issue:** The start requires `ns.activeTimers[key] == nil`. If the aura is extended while the timer runs, the old countdown stays until it expires, and only then does the tracker restart to the real remaining time. This is documented in 57-05 as expected, and it cannot loop.

**Fix:** Optional. Re-arm when the readable `expirationTime` differs from `proc.expiresAt` and the proc was aura-started.

### IN-07: A trailing comma is rejected as malformed input

**File:** `CDMTab.lua:1380-1409`

**Issue:** `"123,"` parses to an empty last token, so Save turns off and the dialog shows "Use spell IDs separated by commas" at the moment the user types the separator for the next ID. The error is correct, but it flashes during normal typing.

**Fix:** Strip one trailing comma from `compact` before splitting: `compact = compact:gsub(",$", "")`.

## Fix Outcomes

Applied 2026-09-28 by gsd-code-fixer (`--auto`, fix scope: all). The orchestrator settled the review's "user decision" notes before the run. One atomic commit per finding, on the milestone branch. After the fixes:

- `node scripts/aura-read-gate.js` passes (10 reads in 3 allowlisted readers), and `--selftest` passes 30 cases.
- `node scripts/migrate-dryrun.js --selftest` passes 7 cases.
- `stylua --check .` is clean.
- All five source files are `w/crlf` with numeric numstat.
- CreateAddDialog still hashes to `64e38633612791cb7e1ea41902b75ae45c18167b`.
- `{` counts are 0 in OnTrigger and in the six render/aura helpers, and no added line names OnUpdate.
- `scripts/install.bat` redeployed to every client folder.

| Finding | Outcome | Commit |
|---|---|---|
| WR-01 | Fixed | `f7a07ac` |
| WR-02 | Fixed: the 56 WR-04 "check both" rule, extended to no-aura-ID trackers and cooldowns | `fe67a00` |
| WR-03 | Fixed: frozen only while unreadable, plus timer-end evidence. Needs in-game verification | `65cd91f` |
| IN-01 | Fixed (engine side) | `cfcdac0` |
| IN-02 | Documented, no change | none |
| IN-03 | Fixed | `dc1f710` |
| IN-04 | Documented, no change | none |
| IN-05 | Fixed | `d8cba5f` |
| IN-06 | Documented, no change | none |
| IN-07 | Fixed | `7810b8b` |

- **WR-01.** RenderIconContainer now drops a tracker whose `ns:VisibilityGate` is `false` while it builds `slots`, just as the bar path does, unless the settings or Edit Mode are open. The grid, SlotDraws and the container size therefore see only drawn entries. The chain's `gate == false` branch could no longer be reached, so it is gone. The filter reuses the existing per-container list and allocates nothing. What remains: `cooldownSlotCounts` still counts a gated-off cooldown as activity, so under "hide when inactive" a container holding only gated-off cooldowns stays shown but empty. It draws nothing, so this was left alone.
- **WR-02.** `ns:RebuildVisibilityWatch` (Core.lua) runs at both exits of `ns:RebuildRankIndex`, after the family tables are final. It builds `ns.visibilityWatch[key]` for each visibility key:
  - with an aura ID, `ns.detailedRankFamilies[key]`. That table is now built for USER_CD as well as USER_BUFF, and the cast path never looks a cooldown key up in it.
  - without an aura ID on a "Cover all ranks" tracker, `ns.rankFamilies[key]`.
  - otherwise no entry, and the single `ns.visibilityAuraID[key]` applies.

  `ns:RefreshAuraStates` makes one lookup per key. Every list is a shared read-only array from the rebuild, and nothing is built per event. The scan and the cache now watch the same set.
- **WR-03.** `ns:RefreshAuraStates` no longer returns on `InCombatLockdown()`. It runs behind the scan's own `ShouldAurasBeSecret` gate, so a readable `ns:ReadPlayerAura` answer updates the state in combat too, and an unreadable one still leaves it untouched (DTRK-06). Only the aura-driven start stays out of combat.
  - A start that comes due in combat is parked in `ns.auraStartPending`. The rebuild prefills a boolean for every visibility key, so UNIT_AURA only overwrites and never inserts. The parked start runs at the first out-of-combat refresh (PLAYER_REGEN_ENABLED). Without this, recording the present edge in combat would have lost the start.
  - A running timer or a readable absence clears the parked start.
  - A visibility-gated tracker's timer ending also writes `auraState[key] = false`, whether by lazy expiry in `ns:GetActiveTimers` or by a scan cancellation. This mirrors the cast-evidence write, so "present" no longer leaves a stale idle icon and "absent" shows its reminder mid-fight. It costs one lookup per expiry and no allocation.

  For in-game verification: if the typed duration is shorter than an aura that is still up, the expiry marks the aura absent, and the next readable UNIT_AURA flips it back to present. For a "present" tracker, that edge restarts it out of combat. When the aura's timing is readable, the restart uses the real expiration. An aura with no readable timing (for example duration 0) re-arms with the typed duration at the next UNIT_AURA after each expiry. Check that this reads as intended.
- **IN-01.** The engine-side option was chosen as the smaller and clearer fix. `ns:AddTrackedBuff` drops `detailed`, `auraID`, `keepOnAuraLoss`, `visibility` and `endOnCast` when the minted kind is not editable (`ns:IsEditableTracker`, which covers metaSkillCd). `coverAllRanks` is not a detailed setting and is kept. Hiding the dialog fields instead would have meant threading the typed spell ID into the `detailed` field's `visible` and into `ns:DetailedChildShown` for every child. The dialog still offers Detailed on a racial ID, and those settings are simply not saved.
- **IN-02 (no change).** A restart only happens when the aura still reads as present, which is correct when the aura really persists. The race the review describes corrects itself at the next UNIT_AURA for any tracker that cancels on aura loss. Choosing a suppression window without in-game evidence would be guesswork, which is the same reasoning 56 IN-04 used. After WR-03, an edge seen in combat only parks the start, and PLAYER_REGEN_ENABLED reads the aura again before starting, so combat adds no new path.
- **IN-03.** `ns:RebuildVisibilityWatch` compares each key's old and new watch list by content, not by identity, because every rebuild allocates fresh family arrays. It clears `ns.auraState[key]` when they differ. An unchanged list, as after an in-combat SPELLS_CHANGED, keeps its state. The existing aura-ID invalidation in `ns:RebuildDetailedRuleIndex` still covers an ID change and a key leaving the set.
- **IN-04 (no change).** This needs a cooldown filed in a bar container, which "cooldowns are icons, never bars" already treats as misfiled, and the bar path skips drawing it. The only effect is an empty container kept shown under "hide when inactive". An empty container draws nothing, and only Edit Mode renders its box. The fix would change `ns:VisibilityShowsIn`'s contract for both of its callers.
- **IN-05.** On the Cooldowns tab, the visibility field's `validate` refuses "up" or "missing" until the aura ID box holds a number. It shows "Enter the aura ID to show a cooldown by aura". The spell's own ID is accepted when typed on purpose. The aura ID state is captured at build, like the master checkbox. Validation runs on every keystroke, so typing an aura ID clears the error at once. An existing cooldown saved with a mode and no aura ID must get one, or be switched to Always, before an edit can save.
- **IN-06 (no change).** 57-05 already documents this as expected. It cannot loop, and the tracker returns to the real remaining time once the old countdown ends. Re-arming would need an "aura-started" flag on the pooled proc and an expiry comparison on every UNIT_AURA. That should wait until in-game testing shows it matters.
- **IN-07.** `ns:ParseSpellIDList` skips empty tokens. "123," and "123, " parse to `{ 123 }`, and text that holds only separators returns nil and stores no rule, like blank input. Bad tokens, the range check and the cap of 8 are unchanged.

---

_Reviewed: 2026-09-28_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
