# Phase 81: Mage Armors and Familiar Scrolls - Context

**Gathered:** 2026-11-09
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
or at the autonomous kickoff, or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

Forever mage reminders:

- Ice Armor and Mage Armor rows, grouped with the existing Frost Armor;
- one familiar-scroll reminder whose click uses the highest usable scroll in the bags.

The item click is the **only new behaviour in the whole milestone**. Every other reminder's click
stays exactly as it is.

</domain>

<decisions>
## Implementation Decisions

### Scope rule (user, 2026-11-09)
- Nothing works differently except the familiar click. Rows and groups are data. Forever IDs come
  from the research only; links use `wowhead.com/forever/`.

### Mage armors (MREM-07)
- `MetaReminderRow(10220, 30)` Ice Armor and `MetaReminderRow(22783, 30)` Mage Armor, each with a
  "(unverified in game)" comment. The existing Frost Armor 7301 row is unchanged.
- `MetaReminderGroup(7301, 10220, 22783)` goes inside Phase 80's Forever block. The rank family
  covers each armor's lower ranks (self-only buffs).
- Molten Armor is not added: it is not learnable on Forever.

### Familiar scrolls (MREM-18), per research §11.2
- `MetaReminderRow(1302303, 60, 1296017, nil, false, { useItems = { {277493, 25}, {277483, 16}, {275069, 5} } })`:
  - keyed on the Cat aura;
  - `knownID` is Comprehend Scroll 1296017, as Blood Pact uses Summon Imp;
  - `castID = false`, so there is no spell click;
  - the ordered `useItems` list is highest tier first and never sorted by ID. Each entry is
    `{itemID, minLevel}`.
- `MetaReminderGroup(1302303, 1302285, 1296202)` goes in the Forever block. Any tier hides it.
- The familiar is not grouped with Arcane Intellect or the armors.
- Using a scroll starts the timer through the existing `UNIT_SPELLCAST_SUCCEEDED` path (a Cat use
  through the row, Frog/Rat through `ns.alternativeKeysBySpell`). No new cast code.

### Item click (CLICK-07), per research §11.3
- `MetaReminderRow` copies `opts.useItems` into the def. A one-line accessor
  `ns:ReminderUseItems(entry)` sits beside `ns:ReminderCastID`: a map read with no allocation.
- `ReminderClick.lua` `Flush` (already out of combat only), for a def with `useItems` only, takes
  the first item with `C_Item.GetItemCount(id) > 0` and `UnitLevel("player") >= minLevel`. Guard the
  reads as the pot scan does: secret values and a missing API.
- `Place` writes `type1 = "item"` and `item = "item:<id>"` for the familiar overlay. Every other
  overlay gets exactly today's `type1 = "spell"` and `spell = <name>`. Each attribute is written
  only on change. `type1` is written in `Place` because overlays are pooled, and the other action
  attribute is cleared.
- Add one `ns:MarkReminderClicksDirty()` call to Core.lua's existing `BAG_UPDATE_DELAYED` branch.
  No `PLAYER_LEVEL_UP` hook: a level-up is picked up at the next bag change, zone or reload, which
  is the minimal version.
- No usable scroll means no overlay: the icon shows and a click does nothing. That is the same as
  today's "cast spell not known" outcome. No desaturation and no hiding.
- The combat state driver and all combat deferral are unchanged.

### Claude's Discretion
- Exact accessor names and where the item pick lives inside `Flush`.
- Mage rows keep "(unverified in game)" until Phase 85.

</decisions>

<code_context>
## Existing Code Insights

- `ReminderClick.lua`:
  - overlays are created with `type1 = "spell"` (~line 71);
  - `Flush` resolves `ns:ReminderCastID`, checks `ns:ResolveSpellKnown`, and places the overlay;
  - a `castID = false` row gets no overlay.
- `Providers.lua` 845-859: the pot provider's "first count > 0 wins" scan is the pattern to copy.
  Lines 1333-1339 handle item use-spell detection.
- `Core.lua` 2182-2196: the `BAG_UPDATE_DELAYED` branch.
- `Core.lua` 1343-1347 and `Providers.lua` 1318: `knownID` drives the load rule and the Suggested
  offer.

</code_context>

<specifics>
## Specific Ideas

- The user plays a Forever mage and tests these in Phase 85: each tier's buff ID, the click, whether
  a new tier replaces a lower one, and whether the familiar stacks with Arcane Intellect.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
