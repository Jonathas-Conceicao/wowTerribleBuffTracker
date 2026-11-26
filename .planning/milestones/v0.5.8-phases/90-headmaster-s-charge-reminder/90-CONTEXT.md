# Phase 90: Headmaster's Charge Reminder - Context

**Gathered:** 2026-11-26
**Status:** Ready for planning
**Mode:** Smart discuss, autonomous: recommended answers auto-accepted (user decisions from the
v0.5.8 kickoff are binding; nothing below contradicts them)

<domain>
## Phase Boundary

A Forever-only built-in reminder for the Headmaster's Charge party buff
([18264](https://www.wowhead.com/forever/spell=18264), +20 Intellect, 15 min), from the staff
[13937](https://www.wowhead.com/forever/item=13937) (main hand, 10 min cooldown). Requirements
HCHG-01..04 and DOC-09. Nothing else changes (scope rule).

</domain>

<decisions>
## Implementation Decisions

### Row (HCHG-01)
- **D-01:** One `MetaReminderRow(18264, 15, ...)` in Providers.lua, client "forever" (the default),
  next to the Well-Rested row under "General". No cast spell (`castID = false`). The aura, from
  anyone's staff, hides it (the row's aura is the buff ID). Trailing comment carries
  "(unverified in game)" until Phase 92.

### Offer (HCHG-02) — user decision
- **D-02:** Suggested offers the row only while 13937 is equipped. Reuse Well-Rested's item-offer
  path: the row sets `offerItem = 13937` plus a new load-time flag saying the offer asks the
  equipped slot instead of the bags (for example `offerSlot = 16`). `ns:MetaReminderSuggestionKeys`
  branches: equipped-slot read for such a row, `ns:ItemInBags` otherwise.
- **D-03:** The equipped read is one guarded helper on `ns` (ns, not a file-local: see the upvalue
  order trap): `GetInventoryItemID("player", slot) == itemID`, pcall-guarded, `issecretvalue` first,
  false on any failure. Not per frame.
- **D-04:** The offer must follow equipping/unequipping while the CDM is open. Equipping a staff from
  the bags fires BAG_UPDATE, which already redraws through `ns:MarkItemCatalogueDirty`; the planner
  confirms that path covers PLAYER_EQUIPMENT_CHANGED too, and if not, adds the cheapest redraw
  trigger on PLAYER_EQUIPMENT_CHANGED (dirty flag, no per-frame work).

### Load rule (HCHG-03) — user decision
- **D-05:** Because the row carries `offerItem`, the existing SBAG-03 path in Core.lua (load reason
  and load decision) already loads it on every character with or without the staff. No load-rule
  code change; Never still applies.

### Click (HCHG-04) — user decision
- **D-06:** The click uses the main-hand slot: secure attribute `type=item`, `item="16"`. Blizzard's
  `SECURE_ACTIONS.item` → `SecureCmdItemParse("16")` → `UseInventoryItem(16)`
  (wow-ui-source `SecureTemplates.lua:418`, `ChatFrameUtil.lua:1197`). Never `item:13937`: for an
  equippable item not equipped, the secure action calls `C_Item.EquipItemByName`, which would equip
  the staff from the bags.
- **D-07:** The overlay is placed only while 13937 is in slot 16 (the D-03 helper). Otherwise no
  overlay: the click does nothing, raises no error.
- **D-08:** The overlay follows equipment changes: Core's PLAYER_EQUIPMENT_CHANGED branch calls
  `ns:MarkReminderClicksDirty()` while a shown reminder uses an item/slot
  (`ns.reminderItemClickActive`), the same gate the BAG_UPDATE_DELAYED branch uses. The flush is
  already coalesced and deferred in combat; a weapon swap in combat updates the overlay when combat
  ends (accepted).
- **D-09:** The `"16"` attribute string is built once at row load, like `useItems[i][3]`, so the
  flush allocates nothing.

### Doc (DOC-09)
- **D-10:** `docs/REMINDERS.md` Forever table, "General" class, next to Well-Rested: link to the
  spell and the item, "a click uses the equipped staff; offered while the staff is equipped; once
  placed it loads on every character", 18264, 15 min, alternatives none.
  `node scripts/reminders-doc-check.js` and `--selftest` pass.

### Claude's Discretion
- Field names on the row def, exact helper name, comment wording.

</decisions>

<canonical_refs>
## Canonical References

- `Providers.lua` — `MetaReminderRow` (~1149), Well-Rested row (~1248), `ns:MetaReminderOfferItem`,
  `ns:ReminderUseItems`, `ns:ItemInBags`, `ns:MetaReminderSuggestionKeys` (~1539-1560)
- `ReminderClick.lua` — `PickUseItem` (~60), Flush (~190-230), `ns.reminderItemClickActive`
- `Core.lua` — SBAG-03 load reason (~700) and load decision (~1350); PLAYER_EQUIPMENT_CHANGED /
  BAG_UPDATE_DELAYED branch (~2202)
- `docs/REMINDERS.md`, `scripts/reminders-doc-check.js`
- wow-ui-source `Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua:418`,
  `Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:1197`

</canonical_refs>

<code_context>
## Existing Code Insights

- Well-Rested (v0.5.7) is the template: item-offered, loaded everywhere, item click. This row
  differs only in where the offer looks (equipped slot vs bags) and what the click attribute is
  (slot "16" vs "item:<id>", gated on the item being equipped).
- `CLAUDE.md` constraints: no flavour fork, `issecretvalue` before comparison, no allocation in hot
  paths, `stylua .` after the task, CRLF kept (check `git ls-files --eol`).

</code_context>

<specifics>
## Specific Ideas

- Forever IDs and `wowhead.com/forever/` links only.

</specifics>

<deferred>
## Deferred Ideas

- Mark of the Dragon Lord, Heart of the Scale — out of scope (REQUIREMENTS.md).

</deferred>
