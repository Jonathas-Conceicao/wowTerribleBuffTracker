---
phase: 86-sleeping-bag-reminder
verified: 2026-11-10T00:00:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
deferred:
  - truth: "In game: buff ID 429959 and its 120 min, the offer with and without the bag, the click unfurling the bag, the reminder on a character without the bag, the reminder hiding when the buff arrives"
    addressed_in: "Phase 89"
    evidence: "VER-16: 'on Forever, the Well-Rested offer with and without the bag, the click using the bag, the reminder on a character without the bag'"
---

# Phase 86: Sleeping Bag Reminder Verification Report

**Phase Goal:** A Forever player is reminded to rest in the Cozy Sleeping Bag, and a click puts the bag down
**Verified:** 2026-11-10
**Status:** passed
**Re-verification:** No (initial verification)

The source diff 38dac28..HEAD (commits ca251c6, f5c3356) was read line by line, along with the code
it depends on. The SUMMARY's claims were not relied on.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ROADMAP SC1 / SBAG-01: On Forever, a Well-Rested reminder keyed on 429959 (120 min) exists; on retail it is not registered | VERIFIED | Providers.lua:1233 `MetaReminderRow(429959, 120, nil, nil, false, { offerItem = 211527, useItems = { { 211527, 1 } } })`. There is no `client` opt, so `MetaReminderRow` (l.1149-1153) uses `"forever"` and returns early on retail. `castID = false` means no cast. No `MetaReminderGroup` call names it. The comment ends "(unverified in game)" |
| 2 | ROADMAP SC2 / SBAG-02: Suggested lists it only while 211527 is in the bags; every other row's offer is unchanged | VERIFIED | `OfferItemInBags` (Providers.lua ~1500) checks that the API exists, wraps `C_Item.GetItemCount` in pcall, then checks issecretvalue, type and `> 0`. It is declared above `ns:MetaReminderSuggestionKeys`, so it is an upvalue there. The branch runs only when `def.offerItem` is set. Every other row runs the unchanged `ns:ResolveSpellKnown(def.knownID, false) == true` |
| 3 | SBAG-02 (plan): the offer follows the bag with no new event hook | VERIFIED | CDMTab.lua:1045 calls `ns:MetaReminderSuggestionKeys()` on every `RefreshTBTSections`. Core.lua:2193-2201 sends BAG_UPDATE to `ns:MarkItemCatalogueDirty`, which sets the dirty flag. `RequestItemCatalogueRebuild` (CDMTab.lua:66-82) then runs `RefreshTBTSections` while `ns.configOpen`. No memo sits in front of the metaReminder list |
| 4 | ROADMAP SC3 / SBAG-03: once placed, it loads on every Forever character with or without the bag; Never still hides it | VERIFIED | Core.lua `RebuildTrackerLoad` has a new `elseif` after the orphan / ALWAYS / NEVER / non-number branches. For a metaReminder with `ns:MetaReminderOfferItem` it sets `loaded = true`, and `ResolveSpellKnown` is never reached. Only two places in the codebase ask `ResolveSpellKnown` for a load or offer: Core.lua:1367 and Providers.lua:1516. Both are now bypassed for this row. The row is shown while 429959 is missing by the existing generic aura-watch path; the buff ID itself is checked in game in Phase 89 |
| 5 | SBAG-03 (plan): `TrackerLoadReason` returns nil for the row after the Never check and never calls SpellLabel | VERIFIED | Core.lua ~700-709: the new branch sits after `LOAD_REASON_NEVER` and before the IN-02 `SpellLabel` branch |
| 6 | ROADMAP SC4 / SBAG-04: a click uses the bag when it is in the bags; without it, nothing happens and no Lua error is raised; the overlay follows the bag | VERIFIED | `ns:ReminderUseItems` returns `def.useItems`, whose third field is filled with `"item:211527"` at load. Flush (ReminderClick.lua 199-231): `ReminderCastID` returns nil because `def.castID == false`. `PickUseItem` returns `"item:211527"` at level 1 or higher with count > 0, otherwise nil, and then no overlay is placed and nothing is skipped. `sawItemReminder` then sets `ns.reminderItemClickActive`, which drives the BAG_UPDATE_DELAYED re-mark at Core.lua:2219. ReminderClick.lua has comment changes only |
| 7 | ROADMAP SC5: docs/REMINDERS.md lists the row with `/forever/` spell and item links, and the doc check passes | VERIFIED | A `| General | [Well-Rested](.../forever/spell=429959) ... [Cozy Sleeping Bag](.../forever/item=211527) ... | 429959 | 120 min | none |` row sits between Druid Thorns and Hunter Trueshot Aura. The doc check passes |
| 8 | No other row's load or offer changed | VERIFIED | Gate: "every baseline row byte-identical (38/38)" and "no code line removed or changed" in Providers.lua and Core.lua. ReminderClick.lua: "every code line identical to baseline" |
| 9 | Line endings and format are intact | VERIFIED | `git ls-files --eol`: all four files `w/crlf`. No CRCRLF. `stylua --check .` exits 0 |

**Score:** 9/9 truths verified

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | In-game check of buff 429959 (120 min), the offer with and without the bag, the click, the reminder hiding when the buff arrives | Phase 89 | VER-16 names the Well-Rested offer, the click and the character without the bag |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Providers.lua` | row, `def.offerItem`, `ns:MetaReminderOfferItem`, `OfferItemInBags`, offer branch | VERIFIED | All present and substantive; `function ns:MetaReminderOfferItem(spellID)` at l.1367 |
| `Core.lua` | load branch and nil reason | VERIFIED | Both use `ns.MetaReminderOfferItem and ns:MetaReminderOfferItem(entry.spellID)` (late-bound guard; Providers.lua loads after Core.lua) |
| `ReminderClick.lua` | header comment naming the sleeping bag; no code change | VERIFIED | Comment lines 6-8 only |
| `docs/REMINDERS.md` | Forever row | VERIFIED | Contains `forever/item=211527` |
| `86-check.js` | phase gate | VERIFIED | Run here: "all checks passed" |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ns:MetaReminderSuggestionKeys` | `OfferItemInBags` | `offered = OfferItemInBags(def.offerItem)` | WIRED | File-local declared above its caller |
| Core.lua `RebuildTrackerLoad` / `TrackerLoadReason` | `ns:MetaReminderOfferItem` | guarded late-bound call | WIRED | Accessor reads `metaReminderDefsBySpellID[spellID].offerItem` |
| Row `useItems` | ReminderClick Flush -> `ReminderUseItems` -> `PickUseItem` -> Place `"item"` | CLICK-07 path | WIRED | Field 3 `"item:211527"` is filled by `MetaReminderRow` at load |
| BAG_UPDATE | Suggested redraw | `MarkItemCatalogueDirty` -> `RequestItemCatalogueRebuild` -> `RefreshTBTSections` | WIRED | Only while the CDM is open; otherwise the next CDM open recomputes |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Suggested tiles (CDMTab.lua:1045) | `metaReminderSuggestionKeys` | `C_Item.GetItemCount(211527)` via `OfferItemInBags` | Yes (live API read at render) | FLOWING |
| Click overlay | `itemAttr` | `PickUseItem` -> `C_Item.GetItemCount` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase gate | `node .planning/phases/86-sleeping-bag-reminder/86-check.js` | "all checks passed", exit 0 (47 ok lines, 0 FAIL) | PASS |
| Doc/code agreement | `node scripts/reminders-doc-check.js` | `REMINDERS-DOC CHECK PASS (133 Forever IDs, 15 retail IDs, 39 rows)` | PASS |
| Doc check fixtures | `node scripts/reminders-doc-check.js --selftest` | `REMINDERS-DOC SELFTEST PASS (46 cases)` | PASS |
| Aura reads allowlisted | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)` | PASS |
| Formatting | `stylua --check .` | exit 0 | PASS |
| Line endings | `git ls-files --eol` (4 files) | all `w/crlf` | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared or relevant (not a migration/tooling phase). Skipped.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SBAG-01 | 86-01 | Well-Rested reminder on Forever, keyed on 429959, 120 min, not on retail | SATISFIED | Truth 1 |
| SBAG-02 | 86-01 | Offer only while the bag is in the bags; other offers unchanged | SATISFIED | Truths 2, 3, 8 |
| SBAG-03 | 86-01 | Loads on every Forever character; Never still applies; other load rules unchanged | SATISFIED | Truths 4, 5, 8 |
| SBAG-04 | 86-01 | Click uses the bag; no error without it; overlay follows the bag | SATISFIED | Truth 6 |

REQUIREMENTS.md maps exactly SBAG-01..04 to Phase 86, and all four appear in the plan. No requirement is orphaned. (The REQUIREMENTS.md checkboxes and traceability rows still say Pending; that bookkeeping belongs to the orchestrator.)

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Providers.lua | ~1500 | `OfferItemInBags` repeats the guarded `GetItemCount` read in ReminderClick.lua's `PickUseItem` | Info | Duplication introduced by this milestone. Phase 88 Cleanup (CLEAN-02) owns it; it does not block the goal |
| Providers.lua / Core.lua / ReminderClick.lua | - | TBD / FIXME / XXX | none found | - |

There is no hot-path cost. The bag read runs only when Suggested is drawn. The load branch adds one map read on the event-driven rebuild. The reason branch runs only on tooltip hover.

### Human Verification Required

None for this phase. The in-game checks (the buff ID, the offer with and without the bag, the click, the
reminder hiding when the buff arrives) are deferred to Phase 89 (VER-16) by design. The row keeps
"(unverified in game)".

### Gaps Summary

No gaps. Each roadmap success criterion and plan must-have is backed by substantive, wired code. The
change is confined to the one row that sets `offerItem`, and all of the gates listed above pass.

---

_Verified: 2026-11-10_
_Verifier: Claude (gsd-verifier)_
