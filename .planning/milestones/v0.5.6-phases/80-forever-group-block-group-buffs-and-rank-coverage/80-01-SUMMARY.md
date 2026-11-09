---
phase: 80-forever-group-block-group-buffs-and-rank-coverage
plan: 01
subsystem: reminders
tags: [forever, reminders, class-buffs, alternatives, data-only]
requires:
  - MetaReminderRow / MetaReminderGroup (Phase 57.5, unchanged)
  - ns.CLIENT_IS_FOREVER (Core.lua)
provides:
  - "One column-0 `if ns.CLIENT_IS_FOREVER then ... end` group block after every row (Phases 81-82 append inside it)"
  - "Group buffs, Greater Blessings and every research §12.3 rank as alternatives of the existing Forever rows"
  - "Blessing of Salvation (1038) and Blessing of Light (19979) rows retired, with an internal restore note"
affects: [Providers.lua reminder table]
tech-stack:
  added: []
  patterns: ["Forever-only group calls gated in one block at the end of the reminder table"]
key-files:
  created: []
  modified: [Providers.lua]
decisions:
  - "Block placed at the end of the table, after the retail Devotion group and before ns:MetaReminderDef, so it follows every row including those Phases 81-82 add"
  - "Header comment records the user's 2026-11-09 reversal: group versions count on Forever"
  - "Salvation/Light/Revoker recorded in an internal comment only, kept out of the public reminders doc"
metrics:
  duration: ~10 min
  completed: 2026-11-09
  tasks: 2
  files: 1
---

# Phase 80 Plan 01: Forever Group Block, Group Buffs and Rank Coverage Summary

On Forever, Arcane Brilliance, Prayer of Fortitude/Spirit, Gift of the Wild, the Greater Blessings and every rank research §12.3 lists now satisfy the matching class-buff reminder, through nine `MetaReminderGroup` calls in one `ns.CLIENT_IS_FOREVER` block; Salvation and Light are retired; retail is unchanged.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Retire Salvation and Light, record them, update the header comment | e884fd8 | Providers.lua |
| 2 | Add the Forever group block, stylua, gate, deploy | 9992176 | Providers.lua |

## What changed

- Rows `MetaReminderRow(1038, 60)` and `MetaReminderRow(19979, 60)` deleted (MREM-06). A placed one becomes an orphan via the existing WR-02 path; no migration.
- Header comment: the "group versions do not count" bullet is gone; a new paragraph says the user reversed it on 2026-11-09 (RALT-05/06/07). The totems bullet stays with its 2026-09-29 attribution.
- Internal note beside the Sanctuary note: Salvation (1038; Greater 25895), Light (19979; Greater 25890) and Revoker (no ID) removed from Forever, restorable, kept out of the public doc.
- Alternatives paragraph: one sentence saying the v0.5.6 group calls are Forever-only and live in one block (RALT-04).
- The ungated `MetaReminderGroup(20217, 25291, 25290, 1038, 19979)` and its comment removed; the blessings call moved into the block without 1038/19979.
- New block after `MetaReminderGroup(465, 317920, 32223)`: Arcane Intellect, Fortitude, Divine Spirit, Mark of the Wild, Thorns, Battle Shout, Trueshot Aura, Blood Pact (6307, 7804, 7805, 11766 only) and the one blessings call (19 IDs, split one per line by stylua). Every comment sits on its own line above its call.

## Verification

Gate `node .planning/phases/80-forever-group-block-group-buffs-and-rank-coverage/80-check-groups.js --exact`: exit 0, all 24 checks `ok`, "all checks passed" (CRLF with no CRCRLF; MetaReminderRow/MetaReminderGroup bodies identical to 5c0001e; every other row byte-identical; one block after every row; comment above names 21562, 1459, 1126, 6673, 465; no in-block trailing/in-expression comment; the nine calls exactly per §12.3; outside the block only the retail Devotion call; no forbidden IDs in code).

- `stylua .` then `stylua --check .`: clean.
- `git ls-files --eol Providers.lua`: `i/lf w/crlf attr/text eol=crlf`.
- `git diff --name-only` before the Task 2 commit: Providers.lua only. CHANGELOG.md untouched.
- `scripts/install.bat`: deployed to `_retail_`, `_ptr_`, `_beta_`, `_forever_`, `_classic_era_`.

Code trace:
- **Retail:** `ns.CLIENT_IS_FOREVER` is false, so the block is skipped; the only group call that runs is `MetaReminderGroup(465, 317920, 32223)`, as before. Every retail and `both` row line is byte-identical (gate row check). The removed ungated blessings call named only Forever rows, which are never registered on retail, so retail never saw it.
- **Forever:** the block runs after every `MetaReminderRow` call, so each row it names is in `metaReminderDefsBySpellID` when `MetaReminderGroup` reads it. Rank and group IDs without a row are one-way alternatives. A row's own ranks as alternatives start it once: the cast path skips an alternative that is the reminder it already started (Providers.lua 436-438), and the watch list removes duplicates (research §12.4).
- `ns:ApplyMetaReminderDef` re-applies `def.alternatives` at every `ns:RebuildCastIndex`, so existing saved reminders pick the alternatives up with no migration.
- In-game checks belong to Phase 85 (VER-15); rows keep their "(unverified in game)" comments.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- Providers.lua modified and committed (e884fd8, 9992176 present in `git log`).
- 80-01-SUMMARY.md written.
