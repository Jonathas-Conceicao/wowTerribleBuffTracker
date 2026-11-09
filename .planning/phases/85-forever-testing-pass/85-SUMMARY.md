# Phase 85: Forever Testing Pass — summary

**Date:** 2026-11-09. **Requirement:** VER-15 (closed).

## In-game results (user)

- Pass: Ice Armor, Mage Armor and the armor group; the familiar reminder and its scroll click.
  Their "(unverified in game)" comments were removed in `Providers.lua`.
- Not tested: every other v0.5.6 row. User decision: they ship as is and get fixed on community
  feedback. Open risks are listed in `.planning/research/REMINDERS-NOT-INCLUDED.md`.

## Changes from the review

- **Shadowform (15473) dropped.** A form like a druid's, not a reminder. The row is gone; a placed
  one becomes an orphan (greyed, "no longer offered"). Note kept in the Providers.lua header.
- **`docs/REMINDERS.md` restructured.** Two sections, Forever and Retail, each one table with a
  Class column, sorted by class. The verified column and the Not included table were removed from
  the doc and kept internally in `.planning/research/REMINDERS-NOT-INCLUDED.md`.
- **`scripts/reminders-doc-check.js` updated** to the new format: one table per section, sorted by
  class, Class cell checked against the row's comment, no `###` headings, no Verified column, no
  Not included section. Check passes (131 Forever IDs, 15 retail IDs, 38 rows); selftest 46 cases.
- **CHANGELOG.md:** a v0.5.6 draft entry added at the top for the user to edit before the merge.
