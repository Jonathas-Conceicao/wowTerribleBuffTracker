# Phase 80: Forever Group Block, Group Buffs and Rank Coverage - Context

**Gathered:** 2026-11-09
**Status:** Ready for planning
**Mode:** Autonomous kickoff. Every decision below was made by the user during `/gsd-new-milestone`
or at the autonomous kickoff, or follows directly from one; nothing is left open.

<domain>
## Phase Boundary

Data-only changes to the built-in class-buff reminder table in `Providers.lua`:

- one `if ns.CLIENT_IS_FOREVER then … end` block for every Forever group call;
- group buffs, Greater Blessings and every rank another player can apply, listed as alternatives
  for the existing Forever rows;
- Blessing of Salvation (1038) and Blessing of Light (19979) removed, with an internal note.

Retail behaves exactly as before. No matching, watch, cast or click code changes.

</domain>

<decisions>
## Implementation Decisions

### Scope rule (user, 2026-11-09, binding on every phase)
- "I don't want anything to work differently than it already does (other than the mage familiar
  scrolls)". Rows and groups are data through the existing `MetaReminderRow` / `MetaReminderGroup`.
  `MetaReminderGroup` itself is not modified.
- Every Forever ID comes from `.planning/research/FOREVER-REMINDERS.md` (§12.2/§12.3), is WoW
  Forever's own, never Classic's. Links are `https://www.wowhead.com/forever/spell=<id>`.

### The Forever block (RALT-04)
- Every Forever group call lives in one `if ns.CLIENT_IS_FOREVER then … end` block after the rows.
  The existing blessings call moves into it. The retail Devotion call
  `MetaReminderGroup(465, 317920, 32223)` stays outside, unchanged.
- Reason, in a comment above the block: 21562, 1459, 1126, 6673 and 465 are Forever ranks **and**
  retail row IDs, so an ungated call would give retail rows Forever alternatives.

### Group buffs and ranks (RALT-05/06/07)
- Use research §12.3's calls verbatim for the existing rows: Arcane Intellect (+ ranks, Arcane
  Brilliance), Fortitude (+ ranks, Prayer), Divine Spirit (+ ranks, Prayer of Spirit), Mark of the
  Wild (+ ranks, Gift), Thorns (ranks), Battle Shout (ranks), Trueshot Aura (ranks), Blood Pact
  (6307, 7804, 7805, 11766 only), and the one blessings call (Kings, Might, Wisdom + their ranks +
  Greater Kings 25898, Might 25782/25916, Wisdom 25894/25918).
- Leave 1038 and 19979 out of the blessings call. Blood Pact's extra data IDs (7871-7873,
  11768-11769, 20318-20321, 20397) are **not** added.
- The armor, class-row and familiar groups belong to Phases 81-82, which add them inside this block.
- Update the table's header comment. The "Deliberately NOT here: group versions … do not count"
  bullet is reversed by the user's 2026-11-09 decision, and the comment must say so.

### Removed blessings (MREM-06)
- Delete the 1038 and 19979 rows. A placed one becomes an orphan through the existing WR-02 path
  (greyed, "no longer offered", no data deleted), exactly as Sanctuary (20914) did in 57.5.
- Add an internal note beside the existing Sanctuary note naming what was removed from Forever, so
  it can be restored if Blizzard brings it back: Blessing of Salvation (1038; Greater 25895),
  Blessing of Light (19979; Greater 25890) and Revoker (a blessing the user says existed only on
  Forever for a while; no ID recorded). They are kept out of the public `docs/REMINDERS.md`
  (Phase 83).

### Claude's Discretion
- Formatting of the multi-line calls. Keep comments out of the middle of an expression: stylua
  writes CRCRLF there (memory: stylua doubles CR on comments in expressions). Put per-group
  comments on the line above each call.
- Verification method. There is no Lua interpreter on this machine, so verify by code trace:
  - on retail the block is skipped;
  - every ID in the block is from §12.3;
  - `stylua .` is clean;
  - `git ls-files --eol Providers.lua` still shows CRLF.

</decisions>

<code_context>
## Existing Code Insights

- `Providers.lua` ~1066-1200: `MetaReminderRow`, `MetaReminderGroup`, the rows, the blessings group
  and the retail rows. `MetaReminderGroup` gives each listed ID **that has a row** the others as
  alternatives; IDs without a row act as one-way alternatives. A second call naming an ID
  overwrites its earlier alternatives.
- `ns:ApplyMetaReminderDef` re-applies defs at every `ns:RebuildCastIndex`, so no migration is
  needed.
- `ns.CLIENT_IS_FOREVER` (Core.lua ~844) is the one sanctioned flavour answer, licensed per row
  and per group by the 2026-09-30 Key Decision.
- Research §12.4: listing a row's own ranks as alternatives is safe. The cast path skips an
  alternative that is the reminder it already started (Providers.lua 436-438), and the watch list
  removes duplicates.

</code_context>

<specifics>
## Specific Ideas

- After each phase that changes Lua, run `stylua .` and `./scripts/install.bat` (user preference).

</specifics>

<deferred>
## Deferred Ideas

- Weapon-enchant reminders: backlog 999.29.
- Blood Pact's extra IDs: only if an in-game ID tooltip shows one on the player.

</deferred>
