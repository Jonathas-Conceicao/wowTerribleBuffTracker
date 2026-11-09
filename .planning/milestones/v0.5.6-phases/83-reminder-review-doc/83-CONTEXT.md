# Phase 83: Reminder Review Doc - Context

**Gathered:** 2026-11-09
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
or at the autonomous kickoff, or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

Three deliverables, and no addon behaviour change:

- `docs/REMINDERS.md`, a human-review list of every built-in reminder, Forever and retail;
- `scripts/reminders-doc-check.js`, which proves the doc and `Providers.lua` agree;
- a pointer comment on the reminder table, plus packaging and CLAUDE.md updates.

</domain>

<decisions>
## Implementation Decisions

### The doc (DOC-06)
- **Location:** `docs/REMINDERS.md`, in the repo, not shipped. Add `docs` to `.pkgmeta`'s ignore
  list.
- **Structure:** a short intro (what a reminder is, what "Also satisfied by" means, how to read the
  verified column), then a **Forever** section and a **Retail** section, each with one table per
  class.
- **Columns:** Spell (linked), Row ID, Duration, Exclusive group / also satisfied by (each ID
  linked), Verified in game (yes / unverified).
- **Links:**
  - Forever: `https://www.wowhead.com/forever/spell=<id>`, and `/forever/item=<id>` for the three
    familiar scrolls.
  - Retail: `https://www.wowhead.com/spell=<id>`.
  - No Classic links.
- **Content:** every existing and new row, including the `both` row (Arcane Intellect) under both
  clients and the retail-only alternatives (317920, 32223).
- **Verified status** comes from the row comments: the 57.4 UAT verified the Mage, Paladin and
  Warlock rows. Everything new is unverified until Phase 85.
- **Excluded candidates:** a final "Not included" table, one reason each, from research §6.
  Include the user's 2026-11-09 drop of tracking and detection skills, and the weapon enchants
  (backlog 999.29).
- **Kept out of this doc (MREM-06):** Salvation, Light and Revoker. They live only in the internal
  note in `Providers.lua`.

### The check script (DOC-07, user choice: script)
- **File:** `scripts/reminders-doc-check.js`, in the same style as `aura-read-gate.js` and
  `migrate-dryrun.js`: plain Node, no dependencies, with a `--selftest` that runs its own fixtures.
- **Code side:** parse `Providers.lua` for every `MetaReminderRow` first argument, every `auraID`
  and `useItems` ID, and every `MetaReminderGroup` ID. Ignore commented-out text, so the internal
  removed-blessings note is not counted.
- **Doc side:** collect every Wowhead ID in `docs/REMINDERS.md` outside the "Not included" section.
- **Result:** report IDs missing on either side; exit non-zero on any mismatch.
- **Pointer comment:** the reminder table's header comment points at `docs/REMINDERS.md` and at the
  script.
- **CLAUDE.md:** the Architecture list gains `docs/REMINDERS.md` and the script, one line each, in
  the existing style.

### Claude's Discretion
- Exact table formatting and intro wording. Plain, concise English: the user reviews it by hand.

</decisions>

<code_context>
## Existing Code Insights

- `scripts/aura-read-gate.js` and `scripts/migrate-dryrun.js` show the house style for check
  scripts, including `--selftest`.
- `.pkgmeta` already ignores `scripts`.

</code_context>

<specifics>
## Specific Ideas

- The user's goal: "a doc for human review with wowhead links to all recommended reminders (old and
  new) for Forever and Retail".

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
