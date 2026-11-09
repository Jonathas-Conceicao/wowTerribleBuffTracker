---
phase: 83-reminder-review-doc
reviewed: 2026-11-09T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - scripts/reminders-doc-check.js
  - docs/REMINDERS.md
  - Providers.lua
  - .pkgmeta
  - CLAUDE.md
findings:
  critical: 0
  warning: 7
  info: 6
  total: 13
status: issues_found
---

# Phase 83: Code Review Report

**Reviewed:** 2026-11-09
**Depth:** deep
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Diff reviewed: `c86be51..87a1bd5`. The changes to `Providers.lua` (comments only), `.pkgmeta`
(`docs` ignored) and `CLAUDE.md` (two Architecture lines) are correct. Nothing in them affects the
shipped addon.

`node scripts/reminders-doc-check.js` exits 0 on the current tree. The selftest passes all 27 cases.
On failure, and when it cannot read a file, it exits 1. I also ran the checker against mutated
copies of `Providers.lua` and the doc, kept in the scratchpad. It caught the following correctly:

- a multi-line `--[==[ ... ]] ... ]==]` comment that hides a row;
- a string holding `\"` and `--` inside opts;
- a nested `function` / `if` / `elseif` / `while` / `repeat ... until` placed inside the Forever block.

**The keyword-depth block finder is sound for nesting.** `elseif` never matches `\bif\b`, and
`for`/`while` balance through their `do`. Its weak points are *which* blocks it recognises (WR-03),
not how deep they nest.

**The main gap is false PASS results.** The check proves that the code and the doc hold the same
set of IDs per client. It does not prove that an ID sits in the right row, or that a row's group is
the one that actually applies at runtime. Two mutations returned `PASS` with exit 0, though the doc
was wrong about runtime behaviour:

- **WR-01:** a second group naming a row, which at runtime replaces that row's alternatives.
- **WR-02:** an alternative moved into another row's "Also satisfied by" cell.

**Doc correctness:** I checked a sample against the code and against Classic rank data, and all of
it matched:

- the Arcane Intellect, Fortitude, Mark of the Wild, Thorns, Battle Shout, Trueshot, Blood Pact and
  Shadow Protection rank lists;
- every Devotion, Retribution and resistance aura rank;
- the blessing ranks;
- the familiar items;
- the retail Devotion alternatives;
- every Duration and Verified cell.

A few durations are worth the human pass (IN-06).

## Warnings

### WR-01: A row named by two groups passes, though at runtime the second group replaces the first

**File:** `scripts/reminders-doc-check.js:341-356` (invariant stated at `Providers.lua:1244-1245`)
**Issue:** `MetaReminderGroup` overwrites `def.alternatives` (Providers.lua:1175). The header says
"a row ID appears in exactly one call here", but nothing enforces it. Test: adding
`MetaReminderGroup(7301, 1302285)` at the end of the Forever block gives
`REMINDERS-DOC CHECK PASS`, exit 0. Every ID is still linked somewhere. At runtime, though, Frost
Armor loses Ice Armor and Mage Armor as alternatives, and the doc still says it has them. This is
the drift the check exists to catch.
**Fix:** in `codeSets`, record per client which group first named each row. Report any later group
that names the same row:
```js
const groupOf = { forever: new Map(), retail: new Map() };
for (const c of live) {
  for (const id of g.ids.filter(id => isRow(code, c, id))) {
    if (groupOf[c].has(id)) {
      sets.problems.push(`row ${id} is in groups at lines ${groupOf[c].get(id)} and ${g.line} on ${CLIENT_LABEL[c]}; the later one REPLACES the earlier`);
    } else {
      groupOf[c].set(id, g.line);
    }
  }
}
```
Add a selftest case for it.

### WR-02: The "Also satisfied by" cell is never checked against the row's group

**File:** `scripts/reminders-doc-check.js:505-533`
**Issue:** For each row, the check looks at the class, the Spell link, Duration and Verified. It
never compares the alternatives cell with the group the row is actually in. Test: moving
Arcane Brilliance `23028` out of the Arcane Intellect line and into the Frost Armor line gives
`PASS`, exit 0. Two more wrong edits would also pass:

- writing `none` on a grouped row, as long as the IDs stay linked elsewhere in the section;
- writing the wrong "X group, below" reference.

For a doc meant for human review, the row-to-alternatives link is the main thing a reviewer reads.
**Fix:**
1. In `parseDoc`, keep the IDs linked in the cell at `cells[3]` for each row.
2. In `compare`, build the expected set for each row: the other IDs of the live group that names
   it, or empty.
3. Require one of:
   - the cell's links equal that set;
   - the cell says `none` when the set is empty;
   - the cell matches `/group, below$/`, and every ID of the set is linked in the class block that
     follows the table. Track the "### class" block's links for this.

### WR-03: The Forever block is found by its exact text; an `else` branch counts as Forever

**File:** `scripts/reminders-doc-check.js:176-201, 236`
**Issue:** The span runs from `if ns.CLIENT_IS_FOREVER then` to its matching `end`, so an `else`
branch is inside it. Test: `else MetaReminderGroup(6673, 99999)` is classified as Forever-only and
reported as "group 6673 names no row on Forever". The real problem is that the group is
retail-only. The finder also does not recognise these forms, so their groups are silently treated
as running on every client:

- `if ns.CLIENT_IS_FOREVER == true then`
- `if not ns.CLIENT_IS_FOREVER then`
- `local isForever = ns.CLIENT_IS_FOREVER; if isForever then`

Any of these can make the doc wrong while the check passes, as long as the IDs happen to be rows on
both clients.
**Fix:** when walking the keywords, stop the span at an `else` or `elseif` at depth 1. Then report
as a problem any `MetaReminderGroup` call that sits inside another `if`/`function`/`for`. A group
that is not at file top level and not directly in the Forever block cannot be classified
statically, so the check should say so loudly.

### WR-04: Non-literal arguments to groups, `auraID` and `useItems` are dropped silently

**File:** `scripts/reminders-doc-check.js:231, 269, 280-288`
**Issue:**
- A row with a non-literal ID fails loudly (line 243).
- A group does not. `integersIn` simply skips identifiers, so in `MetaReminderGroup(465, 317920,
  CRUSADER)` the third member disappears.
- `auraID = SOME_CONST` gives `auraID = null`, and `useItems = ITEMS` gives no items.

If the doc also omits the ID, the check passes, though the runtime watches an aura or alternative
the doc does not list. Hex literals (`0x...`) are skipped the same way.
**Fix:**
- Split the group arguments with `splitArgs` and require each one to match `^\d+$`; report any that
  does not.
- When `auraID =` or `useItems =` is present but the value is not a literal, report it, as is
  already done for `client =`.

### WR-05: CLI flags: an unknown or valueless flag runs the default gate and reports PASS

**File:** `scripts/reminders-doc-check.js:538-541, 882-886`
**Issue:**
- `node scripts/reminders-doc-check.js --selftst` (a typo) prints `REMINDERS-DOC CHECK PASS` with
  exit 0. A plan gate meant to run the selftest would pass without running it.
- `--code` with no value falls back to `Providers.lua` silently, so a gate pointed at a fixture
  checks the real file instead.

The project already records verify gates that pass silently as a known trap.
**Fix:**
- Reject unknown `--` arguments and exit 2.
- Have `argValue` fail when the flag is present but its value is missing or starts with `--`.

### WR-06: Verified is inferred from the word "unverified" anywhere on the line, and defaults to yes

**File:** `scripts/reminders-doc-check.js:301`
**Issue:** `row.verified` is `'yes'` unless the trailing comment contains `unverified`. This has two
consequences:

- A future row added without the annotation is published as "Verified in game: yes".
- A comment such as "was unverified until the Phase 85 UAT" flips a verified row to `unverified`.

So the doc's "yes" ends up meaning "nobody wrote unverified". It does not mean "checked in game".
**Fix:** require an explicit marker: `(unverified in game)` or `(verified in game <date>)`. Make
the missing marker a problem, or at least match only the exact `(unverified in game)` /
`, unverified)` forms used today.

### WR-07: A duplicate MetaReminderRow for the same ID and client is not detected

**File:** `scripts/reminders-doc-check.js:330-340, 508`
**Issue:** At runtime a duplicate row appends a second def to `META_REMINDER_DEFS`, and the second
one wins in `metaReminderDefsBySpellID` (Providers.lua:1157-1158). If the copy is identical, the
check passes. If it differs, the messages are misleading. Test: a second `696` row with a 60 min
duration reported "Duration "30 min", expected "60 min"" against the doc, when the real error is the
duplicate row.
**Fix:** in `parseCode` or `codeSets`, report any second row with the same `spellID` on an
overlapping client.

## Info

### IN-01: The "overall" union comparison is unreachable

**File:** `scripts/reminders-doc-check.js:484-497`
**Issue:** Take any key that is in `codeAll` but missing from `docAll`. It belongs to some
`sets[c]`, and it is absent from `doc.links[c]`, so the per-section loop has already reported it.
The reverse direction works the same way. Both loops can never fire, and `reported` exists only to
feed them.
**Fix:** delete lines 484-497 and the `reported` set. Or keep one comment explaining that the
per-section check covers the overall contract.

### IN-02: A "Not included" link to a group alternative or a useItems item passes

**File:** `scripts/reminders-doc-check.js:499-503`
**Issue:** Only `spell` links that match a row's `spellID` are flagged. Test: linking `1460` (an
Arcane Intellect alternative) in the Not included table gives PASS. This contradicts the Forever
section.
**Fix:** test the link against `sets.forever` and `sets.retail`, by key `${kind}:${id}`, instead of
`code.rows`.

### IN-03: Selftest coverage gaps

**File:** `scripts/reminders-doc-check.js:588-617, 668-871`
**Issue:**
- The fixtures have no multi-line or leveled (`--[==[`) block comment.
- No string has an escaped quote.
- There is no `if`/`else`/`elseif` or anonymous `function` inside the Forever block.
- There is no gate-level case: exit code, unreadable file, unknown flag.
- There is no duplicate group or duplicate row.

I tested the lexer and nesting cases manually and they pass. Without fixtures, though, a regression
there would not be caught.
**Fix:** add these as fixture cases, and add cases for WR-01, WR-03, WR-04 and WR-07 once those are
fixed.

### IN-04: The lexer ends a short string at a newline even after `\z`

**File:** `scripts/reminders-doc-check.js:87-96`
**Issue:** In Lua 5.2+, `"\z` followed by a line break continues the string onto the next line. The
lexer consumes only `\z` and then ends the string at the `\n`, so the rest of the string is read as
code. No such string exists in `Providers.lua` today.
**Fix:** when the escape is `z`, also skip the whitespace that follows it, line breaks included.

### IN-05: `W` is used in `parseDoc` but declared in the selftest section

**File:** `scripts/reminders-doc-check.js:417-419, 586`
**Issue:** It works only because `parseDoc` runs after the module body has finished. If `parseDoc`
is ever called at load time, it throws a TDZ `ReferenceError`.
**Fix:** move `const W = 'https://www.wowhead.com/';` up to the constants at lines 27-33.

### IN-06: Durations to look at in the human review pass (Phase 85)

**File:** `docs/REMINDERS.md:61, 77, 44` (from `Providers.lua:1189, 1217, 1186`)
**Issue:** The doc faithfully mirrors the code, but three values differ from Classic-era data:

| Row | Doc and code | Classic |
|---|---|---|
| Battle Shout 25289 | 3 min | 2 min |
| Demonic Sacrifice 18788 | 120 min | 30 min |
| Divine Spirit 27841 | 60 min ("per the user") | 30 min |

Forever may differ from Classic, so this is not a code finding. It only marks what to confirm in
game.

### Context notes, not findings

- `docs/REMINDERS.md` and the script are `w/lf`. `aura-read-gate.js` and `migrate-dryrun.js` are
  `w/crlf`. Both fall under `text=auto`, so this has no effect.
- The script reads both CRLF and LF input correctly.

---

_Reviewed: 2026-11-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
