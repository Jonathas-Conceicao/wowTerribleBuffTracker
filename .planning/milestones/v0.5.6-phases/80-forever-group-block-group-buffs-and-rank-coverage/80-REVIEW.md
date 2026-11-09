---
phase: 80-forever-group-block-group-buffs-and-rank-coverage
reviewed: 2026-11-09T12:00:00Z
depth: deep
files_reviewed: 1
files_reviewed_list:
  - Providers.lua
findings:
  critical: 0
  warning: 0
  info: 4
  total: 4
status: issues_found
---

# Phase 80: Code Review Report

**Reviewed:** 2026-11-09
**Depth:** deep (diff `385e42c..9992176 -- Providers.lua`, traced into Core.lua, BuffEngine.lua, CDMTab.lua)
**Files Reviewed:** 1
**Status:** issues_found (INFO only)

## Summary

Commits e884fd8 and 9992176 change only data and comments in `Providers.lua`: they remove the
1038/19979 rows, delete the old blessings call, and add one `if ns.CLIENT_IS_FOREVER then ... end`
block with nine `MetaReminderGroup` calls. I found no correctness defect. What I checked:

- **ID collisions and overwrites.** No ID appears twice anywhere in the block. I extracted every
  numeric ID and ran `uniq -d`, which printed nothing. Each Forever row (1459, 10938, 27841, 9885,
  9910, 25289, 20906, 11767, 20217, 25291, 25290) is named in exactly one call, so no row's
  alternatives get overwritten by a second call. On Forever, the one call outside the block,
  `MetaReminderGroup(465, 317920, 32223)`, finds no 465 row (it is `client = "retail"`), so it
  does nothing there. 7301 and 25780 are in no group, as before.
- **The calls match research §12.3.** All nine calls are §12.3's, verbatim, with 1038/19979
  dropped from the blessings call as Q1 = remove required.
- **Retail is unchanged.** `ns.CLIENT_IS_FOREVER` is set in Core.lua (~844), which the TOC loads
  before Providers.lua, so the gate reads a real value. On retail the block never runs. The
  deleted blessings call only ever named Forever rows, so it did nothing on retail before this
  phase either. The retail rows 1459 (`both`), 21562, 1126, 6673 and 465 have the same
  alternatives as before: none, except 465's own Devotion call, which did not change.
- **A row listing its own ranks as alternatives is safe.** When the player casts a rank they
  know, the cast resolves to the row through `ns:ResolveCastOwner` (metaReminderKeyBySpell /
  rankIndexMetaReminder). The alternatives loop then skips `altKey == metaReminderKey`
  (Providers.lua 436-438), so the reminder starts only once. `IndexFamily` (Core.lua ~1495)
  adds each key once per ID, and `RebuildReminderWatch` (Core.lua ~1660) de-duplicates with
  `ListContains`. `ns:CastRuleFamily` never returns nil for a positive ID, because
  `ResolveRankFamily` always seeds the ID itself. So ranks and group spells the player has not
  learned still reach the watch list as single IDs, which is the point of RALT-07. Blood Pact's
  alternatives resolve without the pet book: the family is just the ID. That is correct for
  aura IDs, and the player never casts them.
- **Orphans (1038/19979).** `ns:IsOrphanMetaReminder` (Core.lua 681) is true once the def is
  gone, and the load pass (Core.lua ~1331) sets `loaded = false`. So a placed entry is never
  indexed or watched, and its tile says "no longer offered". `ns:ApplyMetaReminderDef` returns
  early for an orphan, so the stale saved `alternatives` list on such an entry is kept, which
  matches the no-deletion rule. It is never read. The remaining Kings/Might/Wisdom entries get
  their saved lists (which still name 1038/19979) rewritten on the next rebuild, because
  `ns:SameIDList` sees different contents. `RebuildReminderWatch` then clears their auraState and
  points any running timer's `aliveBuffs` at the new list.
- **Durations.** An alternative-started timer uses the row's own duration. Research §4 puts every
  group buff and Greater Blessing on Forever at 60 min, which matches the rows. When a Greater
  Blessing is cast on another class, the paladin does not receive it, so the reminders start
  wrongly at first. `QueueCastAuraRecheck` in `ns:StartReminderFromCast` (Providers.lua 318)
  corrects that, as it already does for single-target blessings.
- **Line endings.** `git ls-files --eol Providers.lua` shows `i/lf w/crlf attr/text eol=crlf`.
  There is no comment inside the multi-line expression, so the stylua CRCRLF trap is avoided.

The four findings are all about comments or latent traps.

## Narrative Findings (AI reviewer)

## Info

### IN-01: Core.lua comment on ns.alternativeKeysBySpell still describes the five-blessing group

**File:** `Core.lua:1121-1126`
**Issue:** "One-to-many, because the five paladin blessings each list the other four." After
Phase 80 there are three blessing rows, and each lists 18 others: the other two rows, the Might
and Wisdom ranks, and the Greater Blessings. This phase made the comment stale, though the
file is outside its diff.
**Fix:** "One-to-many, because the blessing reminders (and every Forever group call) list each
other's IDs."

### IN-02: BuffEngine.lua refreshAuraMemo comment still says "five blessing reminders"

**File:** `BuffEngine.lua:1883-1884`
**Issue:** "the five blessing reminders' watch lists share the same IDs". This is stale for the
same reason. The reasoning behind the memo still holds, and is now stronger: three rows share
about 22 IDs.
**Fix:** "the blessing reminders' watch lists share the same IDs".

### IN-03: The Forever block comment does not say that a second call overwrites

**File:** `Providers.lua:1201-1206`
**Issue:** The block comment tells Phases 81-82 to add their groups inside this block. It
explains one-way versus mutual, but not research §2.4's trap: `MetaReminderGroup` *assigns*
`def.alternatives = others` and never appends. So a row named in two calls silently keeps only
the last call's list. The function's own doc comment (Providers.lua ~1148) does not say this
either. Nothing in the block triggers it today. But the next two phases append to this exact
block, and Phase 81's paladin-aura call names 465. The comment cites 465 as a reason for the
gate, yet no current call uses it, which could lead a reader to think 465 already has a group
here.
**Fix:** Add one line to the block comment: "A row may be named in only one call; a second call
naming it replaces its alternatives." Optionally mark 465 as being "for the Phase 81 aura call".

### IN-04: Latent cap mismatch, 18 built-in alternatives against the editor's 8-ID limit

**File:** `Providers.lua:1228-1248`, `CDMTab.lua:1353,1386`
**Issue:** The blessing rows now carry 18 alternatives. `ns:ParseSpellIDList` rejects more than
`MAX_CAST_RULE_IDS = 8`. This is harmless today, because `ns:IsEditableTracker` keeps
class-buff reminders out of the edit dialog (CDMTab.lua 440, 3094). If a built-in ever becomes
editable, or gets copied into a user reminder, its prefilled "Also satisfied by" box would fail
validation and disable Save for every field. Research §12.4's note that "the edit popup ...
lists every ID with an icon" for a built-in blessing is wrong for the current code: no
built-in opens that popup.
**Fix:** No code change in this phase. Record the constraint next to `IsEditableTracker` or in
the Phase 83 docs, so a future "edit built-in" feature does not ship blocked.

---

_Reviewed: 2026-11-09T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
