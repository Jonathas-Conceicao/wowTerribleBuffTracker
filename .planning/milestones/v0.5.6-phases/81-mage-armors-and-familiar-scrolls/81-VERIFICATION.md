---
phase: 81-mage-armors-and-familiar-scrolls
verified: 2026-11-09T00:00:00Z
status: passed
score: 4/4 must-haves verified (code trace; in-game confirmation is Phase 85 by design)
overrides_applied: 0
human_verification:
  - test: "Forever mage: with no armor up, Frost, Ice and Mage Armor reminders show (each only if known); cast any one armor"
    expected: "Every armor reminder hides while any one of 7301, 10220, 22783 is up; 30 min timer starts on the cast"
    why_human: "Aura presence and ID behaviour on the live Forever client cannot be checked without the game"
  - test: "Forever mage who knows Comprehend Scroll 1296017: no familiar up, then use a Rat, Frog or Cat scroll"
    expected: "One familiar reminder shows; any tier's aura (1302303, 1302285, 1296202) hides it and the 60 min timer starts on the scroll use. Arcane Intellect and the armors are unaffected"
    why_human: "Research rates 'scroll cast spell ID = aura ID' MEDIUM; only the live cast event proves the timer starts from the cast path"
  - test: "Out of combat, click the familiar reminder with several scroll tiers in the bags at various levels; then empty the bags of scrolls"
    expected: "Click uses Cat (lvl 25+), else Frog (16+), else Rat (5+); after a bag change the choice is redone; with no usable scroll the icon shows and a click does nothing"
    why_human: "Secure item-use attribute behaviour (type1=item, item='item:<id>') on the Forever client"
  - test: "Click any other reminder on Forever and retail, in and out of combat"
    expected: "Out of combat it casts its spell; in combat nothing; an unknown spell gets no click"
    why_human: "Secure click behaviour needs the live client"
---

# Phase 81: Mage Armors and Familiar Scrolls Verification Report

**Phase Goal:** A Forever mage is reminded of a missing armor and a missing familiar, and clicking the familiar reminder uses the best scroll in the bags
**Verified:** 2026-11-09
**Status:** passed (code trace; the in-game items below belong to Phase 85)
**Re-verification:** No, initial verification

Judged at commit `227430b` (Phase 81's last code commit). The working-tree `Providers.lua` no longer
equals 227430b: Phase 82 committed `f2d9416` (and later work) on top of it. So the gate was run against
a `git archive 227430b` snapshot through its own `--root` option, with the baseline lookup pinned to
227430b's history (see Probe Execution).

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | Forever mage is offered Ice Armor (10220) and Mage Armor (22783), 30 min each; any of Frost, Ice, Mage Armor up hides every armor reminder | VERIFIED | `MetaReminderRow(10220, 30)` and `MetaReminderRow(22783, 30)` right after Frost Armor (no `client` opt = Forever only). `MetaReminderGroup(7301, 10220, 22783)` inside the `if ns.CLIENT_IS_FOREVER` block gives each row the other two as `alternatives` (RALT-01 path, unchanged). No Molten Armor row |
| 2 | Mage who knows Comprehend Scroll is offered one familiar reminder, 60 min; any tier hides it; any scroll starts its timer; not grouped with AI or armors | VERIFIED (code) | `MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = ... })`: knownID 1296017 gates the load, castID false. `MetaReminderGroup(1302303, 1302285, 1296202)` alone in its call (gate check: no AI/armor ID in it). Cast path: a cast of 1302303 starts the row directly (metaReminder side), 1302285/1296202 through `ns.alternativeKeysBySpell` (alternatives side, Providers.lua ~425). Whether the scroll's cast ID equals the aura ID is an in-game item |
| 3 | Out of combat, click uses highest-tier usable scroll (Cat 277493@25, Frog 277483@16, Rat 275069@5); re-picked after a bag change; no usable scroll = icon with no click | VERIFIED (code) | `PickUseItem` walks the ordered list (never sorted), level test before `pcall(C_Item.GetItemCount)`, `issecretvalue` guards, returns `"item:<id>"`. Called only from `Flush`, which opens with the `InCombatLockdown()` deferral. `Place` writes `type1="item"`, `item`, clears `spell`, on change only. Core.lua `BAG_UPDATE_DELAYED` branch now calls `ns:MarkReminderClicksDirty()`. No scroll: `castName` is nil (castID false) and `itemAttr` nil, so no overlay and no skip/retry; the icon itself is drawn by Display.lua independently |
| 4 | Every other reminder's click unchanged on both clients | VERIFIED (code) | `ns:ReminderUseItems` returns nil for any row without `useItems` (only the Forever familiar row has one), so `actionType="spell"` and `spellAttr=castName`. `CreateOverlay` seeds `_actionType="spell"`, so a spell overlay never rewrites type1; a pooled overlay reused from the familiar is reset to spell and its `item` cleared. `ReminderCastID`, `ReminderCastUnit`, `MetaReminderGroup`, the WR-05 known check and every line outside CreateOverlay/PickUseItem/Place/Flush are byte-identical to the Phase 80 baseline (gate) |

**Score:** 4/4 truths verified by code trace

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `Providers.lua` | rows, groups, `useItems` opt, `ns:ReminderUseItems` | VERIFIED | Present at 7451564/227430b; only the expected lines added vs d62021a |
| `ReminderClick.lua` | PickUseItem, item-aware Place/Flush | VERIFIED | Substantive, called from Flush |
| `Core.lua` | one dirty mark in BAG_UPDATE_DELAYED | VERIFIED | Single added line beside `ReconcileTrackedItemCounts` |

### Key Link Verification

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| `MetaReminderRow` opts | `def.useItems` | `useItems = opts and opts.useItems or nil` | WIRED |
| `ReminderClick.Flush` | `ns:ReminderUseItems` | `local useItems = entry and ns:ReminderUseItems(entry)` | WIRED |
| `Flush` | `Place` | `Place(overlay, icon, castName, itemAttr, unit)` | WIRED |
| `BAG_UPDATE_DELAYED` | `Flush` | `ns:MarkReminderClicksDirty()` -> `C_Timer.After(0, FlushFromTimer)`; combat-deferred to `PLAYER_REGEN_ENABLED` | WIRED |
| Display reminder icon | overlay | `icon._clickKey` stamped when the reminder is drawn as missing (gate == true) | WIRED (pre-existing) |

### Behavioral Spot-Checks

No Lua interpreter or game on this machine; behaviour is covered by the source gate and the in-game items.

### Probe Execution

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| `81-check.js` (as committed, against 227430b snapshot) | `node 81-check.js --root <snapshot>` | 7 FAIL, all from the baseline lookup picking Phase 82's commit `f2d9416` (which already contains Phase 81's lines plus Phase 82's rows) | Baseline artifact, not a code defect |
| `81-check.js` with baseline lookup pinned to `227430b` history (baseline d62021a / 5f91355 / d62021a) | `node check81-pinned.js --root <snapshot>` | 69 ok, 0 FAIL, exit 0 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| MREM-07 | 81-01 | SATISFIED | Truth 1 |
| MREM-18 | 81-01 | SATISFIED (in-game pending Phase 85) | Truth 2 |
| CLICK-07 | 81-01 | SATISFIED (in-game pending Phase 85) | Truths 3, 4 |

No orphaned requirements: REQUIREMENTS.md maps only these three IDs to Phase 81. All item and spell IDs
match `research/FOREVER-REMINDERS.md` §11 (Wowhead `/forever/` sources).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | - | No TBD/FIXME/XXX/TODO/HACK added in the phase's diff | - | - |
| `81-check.js` | 23 | Baseline = last non-81 commit at HEAD; Phase 82 committing after 81 makes the unpinned gate fail at HEAD | Info | Gate is no longer re-runnable as-is; pass a fixed rev if it is ever re-run |
| `ReminderClick.lua` | PickUseItem | No re-pick on level-up alone (deliberate: the gate asserts no PLAYER_LEVEL_UP hook); the pick refreshes on the next bag change or any other flush | Info | Matches the roadmap wording ("after a bag change") |

### Human Verification Required

Listed in the frontmatter; all four belong to the Phase 85 Forever testing pass. The rows keep
"(unverified in game)" until then.

### Gaps Summary

None. Every code-traceable criterion holds at 227430b. The open points are live-client behaviour
(scroll cast ID = aura ID, secure item use on Forever), which Phase 85 owns.

---

_Verified: 2026-11-09_
_Verifier: Claude (gsd-verifier)_
