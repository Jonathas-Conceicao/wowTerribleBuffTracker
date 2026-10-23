---
phase: 76-buff-duration-on-bag-items
verified: 2026-10-22T00:00:00Z
status: passed
score: 18/18 must-haves verified (5/5 roadmap success criteria)
overrides_applied: 0
deviations:
  - item: "auraID and endOnCast are hidden, not greyed, in a bag item's dialog"
    detail: "76-CONTEXT says every existing field shows greyed. The plan hides these two through visible() because a bag item never had either value: it has no aura ID of its own, and ns:ApplyEndOnCast only handles USER_CD. A hidden field is not read, so nothing is written. Recorded for the user to accept or reject. Not a gap."
  - item: "Portrait icon falls back to ns:ItemDisplayInfo(itemID).icon when the entry has no iconOverride (76-02)"
    detail: "Runs at edit time only and never on a render path. This is an addition to the plan, not a regression."
deferred_to_phase_78:
  - "A bag item moved out of Suggested shows Edit in its right-click menu. A Suggested item tile does not."
  - "The dialog is titled 'Edit Item Tracker' and opens on Advanced. The portrait shows the item's icon and name, with the item tooltip on hover."
  - "Spell ID (empty), Duration (the item cooldown), Cover all ranks (Forever only) and Load (Always) are greyed and not editable, labels included."
  - "The checkbox starts off and the Aura ID and Duration start empty. Ticking it blocks Save until both are filled. Unticked, Save works."
  - "Save prints 'Updated <item> (item, buff Ns)'. The item stays in its section with its count and cooldown, and reopening the dialog shows the saved values."
  - "Using the item with its buff on shows the yellow buff countdown on the item's own icon with the count kept, then the item cooldown."
  - "Clicking the aura off (out of combat, after the cast grace) ends the buff early. A secret read never ends it. Using the item again restarts it. A hidden item starts nothing."
  - "The icon shows the item texture and the item tooltip during the buff and in the CDM-settings preview."
  - "/reload and logout/login keep the item's buff settings, and the item cooldown refresh leaves the typed duration alone."
  - "userCd, userBuff and reminder dialogs look as before (the Aura ID still follows the Spell ID)."
---

# Phase 76: Buff Duration on Bag Items Verification Report

**Phase Goal:** A player can give a bag item they track its buff, without being able to change anything else about the item tracker
**Verified:** 2026-10-22
**Status:** passed (code-level). In-game checks are deferred to the Phase 78 retail pass by user decision.
**Re-verification:** No. This is the first verification.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | A bag item tracker moved out of Suggested has an Edit entry. Its dialog shows the item's existing fields with their values, greyed out and not editable. | VERIFIED (with recorded deviation) | `ns:IsEditableTracker` adds `or ns:IsBagItemEntry(entry)` (BuffEngine.lua:1039-1048). The tracked-tile menu gates Edit on it (CDMTab.lua:440). `NotItemField` is set as `enabled` on spellID, duration, coverAllRanks and load (CDMTab.lua:1935, 2085, 2186, 2308, 2576). Each of those states carries `label`, so `ApplyFieldEnabled` greys the label and disables the box, check or dropdown (CDMTab.lua:1748-1785). Duration prefills `FormatDuration(entry.duration)`. Load prefills `ns:TrackerLoad`, which returns ALWAYS for metaItem. auraID and endOnCast are hidden rather than greyed (see Deviations). |
| SC2 | In that dialog only the buff checkbox, the Aura ID (empty by default) and the Duration can be changed, under the same save rule as a spell's buff. | VERIFIED | `CarriesCooldownBuff` admits META_ITEM (CDMTab.lua:1921). buffAuraID passes `follows = ctx.kind ~= META_ITEM`, so `followsSpell` is false at reset and prefill (CDMTab.lua:1640, 1655). The box therefore starts empty and never copies the Spell ID. With the box ticked, `requiredMessage` "Enter the buff's Aura ID" and buffDuration's "Enter the buff duration" block Save (ValidateAll skips `enabled == false` only). Unticked, the buff fields are greyed and not validated, and the greyed General fields are not validated either, so Save works. On the engine side, `ns:UpdateTrackedBuff` returns `ns:UpdateTrackedItemBuff(oldKey, fields)` before the "Invalid spell ID" check (BuffEngine.lua:1420-1422). That path writes only buffEnabled, buffAuraID and buffDuration (1344-1346). It never re-keys and never touches `entry.duration`, and it refuses a ticked buff without an Aura ID or Duration (1335-1342). |
| SC3 | A Suggested item tile still has no Edit entry. | VERIFIED | The `sectionName == "suggested"` branch (CDMTab.lua:381-404) builds only "Add to ..." buttons and returns before the tracked-tile menu. That branch is unchanged. |
| SC4 | With an item's buff on, using the item starts its buff timer alongside the item's cooldown, ends it early only on a readable aura-gone read, and the icon shows the buff look then the cooldown. | VERIFIED (code) | `MetaItemBagProviderMixin:OnTrigger` calls `ns:StartCooldownBuffFromCast(key, entry)` after `ns:RefreshTrackedItemCooldowns()` and `MarkCooldownsDirty`, and every path returns nil (Providers.lua:1775-1820). `StartCooldownBuffFromCast` applies the hidden, bar-container and buff-off refusals and sets `proc.itemID` (Providers.lua:224-266). aliveBuffs is the pooled `{typedAuraID}`. The only early end is `ns:ScanActiveTimersForCancellation`, which requires `allReadable` and honours the cast grace (BuffEngine.lua:1704-1740). The live-timer branch draws the item's icon with `ApplyCachedIcon(icon, timer.spellID, entry.iconOverride)` and the yellow look with `ApplySwipeLook(icon, slotEntry and CooldownBuffDuration(entry) ~= nil)`, keeps the count (`ApplySlotCount`), and hands back to `ApplyCooldownSlot` when the timer ends (Display.lua:1717-1795). |
| SC5 | An item's buff settings survive logout and login, and the item's cooldown refresh never overwrites the typed buff duration. | VERIFIED (code) | The buff keys live on the saved entry inside the `TerribleBuffTrackerDB.trackedBuffs` table. No migration or schema bump is needed (CURRENT_SCHEMA_VERSION stays 12, and ENGINE_OWNED is unchanged). No code strips unknown keys: a grep for buffEnabled/buffAuraID/buffDuration writers outside CDMTab finds only `UpdateTrackedItemBuff`. `SeedItemTracker` (Providers.lua:1552-1590) and `RefreshTrackedItemCooldowns` (1596-1617) write only `entry.duration` and `ns.cooldownStarts[key]`. `CooldownBuffDuration` reads `entry.buffDuration`, never `entry.duration`. `AddSuggestedTracker` on an existing key only calls `ns:SetBuffSection` (CDMTab.lua:154-157), so the entry table and its buff keys survive a move. |

### Plan must-haves (merged)

| # | Truth (plan) | Status |
|---|--------------|--------|
| 01-1 | IsEditableTracker is true for a bag item and false for Trinket, Pot, Lust and metaReminder | VERIFIED. `IsBagItemEntry` requires a numeric itemID, which Trinket and Pot do not have. |
| 01-2 | A bag item's save writes only the three buff keys and never re-keys | VERIFIED (BuffEngine.lua:1322-1371) |
| 01-3 | Buff off ends a running buff, a changed Duration ends it, and an Aura ID change repoints the running buff (one shared helper) | VERIFIED. `ns:ApplyCooldownBuffEdit` (1379-1393) is called from both edit paths. |
| 01-4 | Using the item starts the buff at the cooldown refresh, under the item key. Off, hidden or bar container starts nothing. | VERIFIED |
| 01-5 | An early end only comes through the cancellation scan on a readable read, with no new aura read | VERIFIED. The aura-read gate passes with an unchanged allowlist. |
| 01-6 | The icon and tooltip are the item's during the buff and the preview | VERIFIED. Preview proc carries `itemID` (BuffEngine.lua:1674). `ShowBuffTooltip` item arm (Display.lua:352-357). |
| 02-1 | A moved item has Edit and a Suggested tile does not | VERIFIED |
| 02-2 | Title is "Edit Item Tracker", opens on Advanced, portrait shows item icon, name and tooltip | VERIFIED (CDMTab.lua:2640, 3103, 3120-3124, preview item arm 2030-2052) |
| 02-3 | Non-buff fields are greyed with their labels, Load reads Always, Spell ID is empty | VERIFIED |
| 02-4 | Checkbox starts off, Aura ID empty and non-following, Duration empty | VERIFIED |
| 02-5 | Ticked requires both fields; unticked Save works | VERIFIED |
| 02-6 | Save routes to UpdateTrackedItemBuff | VERIFIED. The confirm handler is unchanged (CDMTab.lua:3044). |
| 02-7 | User-kind dialogs are unchanged | VERIFIED. `NotItemField` is always true for user kinds. buffAuraID `follows` is true for USER_CD, and auraID and castID pass no `follows`. The Load prefill mapping matches the old if/else for user kinds. |

**Score:** 5/5 roadmap criteria and 13/13 plan truths verified.

### Required Artifacts

| Artifact | Expected | Status |
|----------|----------|--------|
| BuffEngine.lua | `UpdateTrackedItemBuff`, `ApplyCooldownBuffEdit`, widened `IsEditableTracker`, preview itemID | VERIFIED. Present, substantive and wired. |
| Providers.lua | OnTrigger starts the buff, `proc.itemID` | VERIFIED |
| Display.lua | `ApplyCachedIcon(icon, timer.spellID, entry.iconOverride)` in the live-timer branch | VERIFIED |
| CDMTab.lua | `NotItemField`, widened `CarriesCooldownBuff`, `follows` hook, portrait item arm, title, Advanced-first open | VERIFIED |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `ns:UpdateTrackedBuff` | `ns:UpdateTrackedItemBuff` (before the spell ID check) | WIRED |
| `MetaItemBagProviderMixin:OnTrigger` | `ns:StartCooldownBuffFromCast(key, entry)` (after the refresh) | WIRED |
| `activeTimers[metaItem:<id>]` | RenderIconContainer live-timer branch via `ApplyCachedIcon` | WIRED |
| Right-click menu | `ns.tbtAddDialog.OpenForEdit` via `IsEditableTracker` | WIRED |
| Confirm handler | `ns:UpdateTrackedBuff(ctx.editingKey, ...)` and then `UpdateTrackedItemBuff` | WIRED |
| spellID, duration, coverAllRanks and load | `ApplyFieldEnabled` via `enabled = NotItemField` | WIRED (4 sites) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Status |
|----------|------|--------|--------|
| Item buff icon | `ns.activeTimers[key]` | UNIT_SPELLCAST_SUCCEEDED, then `itemUseSpellToID`, then OnTrigger, then StartCooldownBuffFromCast, with duration from saved `entry.buffDuration` | FLOWING |
| Dialog buff fields | saved `entry.buffEnabled`, `buffAuraID` and `buffDuration` | prefill from the saved entry, read, UpdateTrackedItemBuff, saved entry | FLOWING |
| Portrait | `entry.iconOverride` and `entry.label` | written by AddSuggestedTracker at creation | FLOWING |

### Behavioral Spot-Checks and Probes

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Aura-read gate | `node scripts/aura-read-gate.js` | AURA-READ GATE PASS (1 read in 1 allowlisted reader) | PASS |
| Gate selftest | `node scripts/aura-read-gate.js --selftest` | 30 cases PASS | PASS |
| Migrate dry-run selftest | `node scripts/migrate-dryrun.js --selftest` | 13 cases PASS | PASS |
| Formatting | `stylua --check .` | exit 0 | PASS |
| Line endings | `git ls-files --eol` on the 4 Lua files, and a grep for `\r\r` | all `w/crlf`, 0 CRCRLF | PASS |
| Plan task gates (76-01 T1, T2 and 76-02 T1, T2) | re-run against current source | all 4 print PASS | PASS |

No Lua interpreter is installed, so nothing could be run at runtime. Runtime behaviour is deferred to Phase 78.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| BUFFCD-05 | 76-01, 76-02 | SATISFIED (code). In-game check in Phase 78. | SC1 and SC2 |
| BUFFCD-06 | 76-02 | SATISFIED (code). In-game check in Phase 78. | SC3 |
| BUFFCD-07 | 76-01 | SATISFIED (code). In-game check in Phase 78. | SC4 |

REQUIREMENTS.md maps BUFFCD-05, -06 and -07 to Phase 76, and every one appears in a plan's `requirements`. No requirement is orphaned.

### Anti-Patterns Found

No TBD, FIXME, XXX, TODO, HACK or PLACEHOLDER was added in the phase diff (0c1e44e..HEAD). No stubs were found. OnTrigger and StartCooldownBuffFromCast stay allocation-free: the proc and aliveBuffs come from pools, and `ns.CONTAINERS` is walked with ipairs.

| File | Note | Severity |
|------|------|----------|
| BuffEngine.lua `UpdateTrackedItemBuff` | When unticked it writes `buffAuraID` and `buffDuration` as read, the Phase 74 "kept but no effect" rule. A hand-edited `buffEnabled = true` with no Aura ID gets an empty pooled watch list, so it never ends early and never errors. | Info |

### Deviations (for the user)

1. **auraID and endOnCast are hidden, not greyed, for a bag item.** 76-CONTEXT says every existing field shows greyed. The plan hides these two because an item never had a value for either: it has no aura ID of its own, and the cast rule (`ns:ApplyEndOnCast`) only handles USER_CD. A second, empty "Aura ID:" beside the buff's own Aura ID could also mislead. Hidden fields are not read, so nothing is written either way. If you would rather see them greyed, the change is to swap `visible` for `enabled = NotItemField` on both defs.
2. **Portrait icon fallback.** When an entry has no `iconOverride`, the portrait uses `ns:ItemDisplayInfo(itemID).icon`. This runs at edit time only.

### Deferred to Phase 78 (in-game, retail, by user decision)

1. A bag item moved out of Suggested shows Edit. A Suggested item tile does not.
2. The dialog is titled "Edit Item Tracker", opens on Advanced, and shows the item's icon, name and tooltip.
3. Spell ID (empty), Duration (the item cooldown), Cover all ranks (Forever only) and Load (Always) are greyed and not editable, labels included.
4. The checkbox starts off and the Aura ID and Duration start empty. Ticking it blocks Save until both are filled. Unticked, Save works.
5. Save prints "Updated <item> (item, buff Ns)" and changes nothing else (section, count and cooldown stay). Reopening shows the saved values.
6. Using the item with its buff on shows the yellow buff countdown on the item's own icon with the count kept, then the item cooldown.
7. Clicking the aura off (out of combat, after the cast grace) ends the buff early. A secret read never does. Using the item again restarts it. A hidden item starts nothing.
8. The item texture and item tooltip show during the buff and in the CDM-settings preview.
9. /reload and logout/login keep the settings, and later item cooldown refreshes leave the typed buff duration alone.
10. userCd, userBuff and reminder dialogs are unchanged (the Aura ID still follows the Spell ID).

### Gaps Summary

There are no code gaps. Every roadmap success criterion and plan must-have is backed by code that exists, is substantive and is wired. The data flows from the saved entry through the dialog and the item-use path to the icon. The two deviations above are design choices recorded for the user, not failures. Runtime and visual confirmation is deferred to the Phase 78 retail pass.

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
