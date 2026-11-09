---
phase: 81-mage-armors-and-familiar-scrolls
plan: 01
subsystem: reminders
tags: [forever, reminders, mage, secure-click, CLICK-07]
requires:
  - Phase 80 Forever group block (`if ns.CLIENT_IS_FOREVER then` in Providers.lua)
provides:
  - Ice Armor 10220 and Mage Armor 22783 Forever rows, armor group with Frost Armor 7301
  - Familiar reminder row 1302303 (knownID 1296017, castID false, useItems) and its tier group
  - def.useItems + ns:ReminderUseItems(entry)
  - item click (type1 "item") for reminders that carry useItems; re-pick on BAG_UPDATE_DELAYED
affects: [Providers.lua, ReminderClick.lua, Core.lua]
tech-stack:
  added: []
  patterns: [ordered tier list walked first-match, guarded secure attribute writes on change only]
key-files:
  created: []
  modified: [Providers.lua, ReminderClick.lua, Core.lua]
decisions:
  - "Familiar reminder clicks an item (type1 item) picked from an ordered {itemID, minLevel} list; no usable scroll means no overlay and no retry skip"
  - "type1 now written in Place on change only; CreateOverlay seeds _actionType = spell so spell overlays never rewrite it"
metrics:
  duration: ~15 min
  completed: 2026-11-09
  tasks: 2
  files: 3
---

# Phase 81 Plan 01: Mage Armors and Familiar Scrolls Summary

Forever mages get Ice Armor and Mage Armor reminders that share one mutual-alternative group with
Frost Armor, plus one 60-min familiar reminder (any Cat/Frog/Rat tier hides it) whose click uses the
highest-tier scroll in the bags the player's level allows, through a `type1 = "item"` secure overlay
re-picked on every `BAG_UPDATE_DELAYED`.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Armor and familiar rows, group calls, useItems, ns:ReminderUseItems | 7451564 | Providers.lua |
| 2 | Item click in ReminderClick.lua, re-pick in Core.lua, stylua, gate, deploy | 227430b | ReminderClick.lua, Core.lua |

## Verification

- `node .planning/phases/81-mage-armors-and-familiar-scrolls/81-check.js`: **all checks passed**
  (exit 0; baselines Providers.lua d62021a, ReminderClick.lua 5f91355, Core.lua d62021a). Re-run
  after both commits: still passes.
- `node scripts/aura-read-gate.js`: `AURA-READ GATE PASS (1 reads in 1 allowlisted readers)`.
- `stylua .` then `stylua --check .`: clean.
- `git ls-files --eol Providers.lua ReminderClick.lua Core.lua`: all `w/crlf`.
- `./scripts/install.bat`: deployed `v0.5.5-23-g227430b-dev` to retail, ptr, beta, forever, classic_era.
- In-game checks (tier buff IDs, the click, tier replacement, Comprehend Scroll 1296017) belong to
  Phase 85; the three new rows keep "(unverified in game)".

## Code Trace (a)-(g)

**(a) Retail.** The three new rows have nil `client` (= forever), so `MetaReminderRow` returns before
building a def; both new group calls sit inside `if ns.CLIENT_IS_FOREVER then` and do not run. No def
has `useItems`, so `ns:ReminderUseItems(entry)` returns `def and def.useItems or nil` = nil for every
metaReminder and nil immediately for user reminders. In Flush `useItems` is nil, `itemAttr` is nil,
the branch condition reduces to `if castName then` as before. In Place, `actionType = "spell"` equals
the `_actionType` seeded by CreateOverlay (no type1 write), `spellAttr = castName` (the same `spell`
write-on-change as before), `_itemAttr` nil == `itemAttr` nil (no `item` write). Attributes are
byte-for-byte today's.

**(b) Forever, a non-familiar reminder** (e.g. Arcane Intellect, Frost Armor). Its def has no
`useItems`, so the path is identical to (a). The armor rows themselves have castID = their spell ID,
so they click-cast by name exactly like Frost Armor.

**(c) Familiar, level 30, Cat and Rat in the bags.** `ns:ReminderCastID` returns nil (castID false),
so `castName` is nil and the WR-05 check is skipped. `ns:ReminderUseItems` returns the
`{ {277493,25}, {277483,16}, {275069,5} }` list. PickUseItem: level 30 (not secret, a number);
entry 1: 30 >= 25, `GetItemCount(277493)` > 0, returns `"item:277493"`. Flush enters the branch on
`itemAttr`. Place on a fresh overlay: `actionType = "item"` differs from seeded `"spell"`, writes
type1 `"item"`; `spellAttr = nil`, `_castName` nil, so no spell write (no-op); `_itemAttr` nil ~=
`"item:277493"`, writes `item`. Unit is `"player"` from ns:ReminderCastUnit (not allyCast).

**(d) Level 20 holding only Cat and Frog scrolls.** Entry 1: 20 >= 25 fails, the count is never
read. Entry 2: 20 >= 16, `GetItemCount(277483)` > 0, returns `"item:277483"`.

**(e) No usable scroll.** PickUseItem returns nil after the loop; `castName` nil and `itemAttr` nil,
so no overlay is taken. `castID` is nil, so the `elseif castID then` skip does not fire: no skip, no
retry timer. The icon still shows; a click does nothing. The next BAG_UPDATE_DELAYED re-marks.

**(f) Scroll used in combat.** The use fires UNIT_SPELLCAST_SUCCEEDED (1302303 is the row key; Frog
and Rat start it through `ns.alternativeKeysBySpell`) with no new cast code. The bag change fires
BAG_UPDATE_DELAYED; Core.lua calls `ns:MarkReminderClicksDirty()`, which sets `dirty = true`,
`retrySpent = false`, and returns early on `InCombatLockdown()`. PLAYER_REGEN_ENABLED runs the
existing dirty flush, which re-picks out of combat. No secure write happens in combat.

**(g) Overlay reused from the familiar for a spell reminder.** The pooled overlay has
`_actionType = "item"`, `_castName = nil`, `_itemAttr = "item:..."`. Place with `itemAttr` nil:
`actionType = "spell"` differs, type1 back to `"spell"`; `spellAttr = castName` differs from nil,
`spell` set; `_itemAttr` differs from nil, `item` cleared to nil. The reverse reuse (spell overlay
to the familiar) clears `spell` to nil and sets `item` and type1 `"item"`.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: Providers.lua `function ns:ReminderUseItems(entry)`, ReminderClick.lua `local function PickUseItem(useItems)`, Core.lua `ns:MarkReminderClicksDirty()`
- FOUND: 7451564, 227430b
