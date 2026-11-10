# Phase 89: Testing Pass - Context

**Gathered:** 2026-11-10
**Status:** Ready (no plans: testing pass by the user)
**Mode:** Same shape as Phase 85.

<domain>
## Phase Boundary

VER-16: the user checks in game what they can reach. No code is planned; fixes found here are made
in this phase and recorded in `89-SUMMARY.md`.

</domain>

<decisions>
## Implementation Decisions

- Deploy with `./scripts/install.bat` before the check.
- Forever: Well-Rested offered with the bag and not offered without; click uses the bag; the
  reminder on a character without the bag shows and a click does nothing, no Lua error; the
  reminder hides once Well-Rested is up.
- Paladin: the aura reminders on whichever client is reachable; any aura up hides them all.
- Rows confirmed lose "(unverified in game)"; rows not checked keep it, and the verification status
  in `.planning/research/REMINDERS-NOT-INCLUDED.md` is updated.
- Untested rows ship and get fixed on community feedback (user decision, v0.5.6).
- After the pass: draft the CHANGELOG.md entry at the top (insert only, never rewrite), then wait for
  the user to edit it and run `/gsd-complete-milestone` (user's v0.5.6 flow).

</decisions>

<code_context>
## Existing Code Insights

None needed.

</code_context>

<specifics>
## Specific Ideas

None.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
