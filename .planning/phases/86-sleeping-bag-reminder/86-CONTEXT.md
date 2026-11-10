# Phase 86: Sleeping Bag Reminder - Context

**Gathered:** 2026-11-10
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
(2026-11-10) or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

One new Forever-only reminder: Well-Rested (buff 429959), whose click uses the Cozy Sleeping Bag
(item 211527). Two row-specific behaviours are new and apply to this row only:

- the Suggested offer asks "is item 211527 in the bags", not "is a spell known";
- the load rule asks nothing (the row loads on every Forever character once placed).

Every other row's offer, load rule and click stay exactly as they are (user scope rule).

</domain>

<decisions>
## Implementation Decisions

### Scope rule (user, carried from v0.5.6)
- Nothing works differently except what SBAG-01..04 name. Forever IDs only; links use
  `wowhead.com/forever/`.

### The row (SBAG-01)
- Keyed on the buff 429959, 120 minutes, Forever only (default client tag; it sits with the
  Forever rows, not in the retail list). Comment ends "(unverified in game)".
- `castID = false` (no spell click), `useItems = { { 211527, 1 } }` (any level), reusing the familiar
  scroll click path (CLICK-07) unchanged: `PickUseItem`, `Place` writing `type1 = "item"`, and the
  `BAG_UPDATE_DELAYED` re-mark through `ns.reminderItemClickActive`.
- The bag only unfurls; Well-Rested arrives after a minute of rest and stacks to 3. The reminder
  hides when the aura appears (existing aura watch). No timer is started by the click, and stacks
  are not tracked (out of scope).
- No group: Well-Rested has no alternatives.

### Offer gated on the item (SBAG-02)
- A new load-time opt on `MetaReminderRow` (name at the planner's discretion, e.g.
  `offerItem = 211527`) marks the row as item-offered. `ns:MetaReminderSuggestionKeys` offers such a
  row only when a guarded `C_Item.GetItemCount(itemID)` read returns a readable number > 0 (pcall,
  `issecretvalue` check, missing API = not offered, as `PickUseItem` already does).
- The planner must check whether the Suggested list is memoised (e.g.
  `ns:IsSuggestedKeyResolvable`'s memo, "until the next SPELLS_CHANGED") and make sure the bag
  row's offer follows the item arriving or leaving at least by the next CDM open / Suggested
  refresh. It does not need to redraw live on every BAG_UPDATE.

### Load rule without a known spell (SBAG-03)
- For the item-offered row only, the "When known" load rule resolves to loaded (no
  `ResolveSpellKnown` call). The user's explicit Never still unloads it; Always still loads it;
  orphan handling unchanged.
- The tooltip load-reason path in `Core.lua` (~line 703, `TrackerLoadReason`) must not call
  `ns:SpellLabel` with a non-spell knownID; for this row it simply gives no "does not know" line.
- Reminders are account-wide (user decision): a character without the bag still shows the
  reminder while the buff is missing, and a click does nothing.

### Click (SBAG-04)
- Out of combat only (existing overlay rule). With the bag: uses it. Without: no overlay action, no
  Lua error, same as the familiar with no scroll. The game's own "item not ready" message on
  cooldown is acceptable.

### Review doc
- `docs/REMINDERS.md` Forever table gains the Well-Rested row with its `/forever/spell=429959` link
  and the item link `/forever/item=211527`, sorted by class (class cell: whatever the planner picks
  that the doc check accepts, e.g. "Any" or "General"; check `scripts/reminders-doc-check.js`'s class
  ordering and its row-comment class check, and extend the check minimally if it rejects a
  non-class row). `node scripts/reminders-doc-check.js` and `--selftest` pass.

### Claude's Discretion
- Exact opt name, comment wording, where the row sits in the Forever list.

</decisions>

<code_context>
## Existing Code Insights

- `Providers.lua` ~1145 `MetaReminderRow(spellID, minutes, knownID, petBook, castID, opts)`;
  `def.knownID = knownID or spellID`.
- `Providers.lua` ~1480 `ns:MetaReminderSuggestionKeys()` iterates `META_REMINDER_DEFS` and asks
  `ns:ResolveSpellKnown(def.knownID, false) == true`.
- `Providers.lua` ~1355 `ns:MetaReminderKnownID(spellID)`.
- `Core.lua` ~1330-1360 load refresh: `ns:ResolveSpellKnown(knownID, true)`; ~703 load-reason text.
- `ReminderClick.lua` ~58 `PickUseItem`, ~207 Flush's useItems branch, ~230
  `ns.reminderItemClickActive`.
- `Core.lua` ~2195 `BAG_UPDATE_DELAYED` re-mark.
- The familiar row (`MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = ... })`) is the
  closest analogue.

</code_context>

<specifics>
## Specific Ideas

- Item: https://www.wowhead.com/forever/item=211527 (1-hour cooldown).
- Buff: https://www.wowhead.com/forever/spell=429959 (2 hours, stacks to 3).

</specifics>

<deferred>
## Deferred Ideas

- Starting the timer on the click; stack tracking (out of scope).

</deferred>
