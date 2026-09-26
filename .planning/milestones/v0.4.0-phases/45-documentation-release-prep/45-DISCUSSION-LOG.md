# Phase 45: Documentation & Release Prep - Discussion Log

**Date:** 2026-09-23
**Mode:** default (interactive)

Human reference only. Downstream agents read `45-CONTEXT.md`, not this file.

---

## Area: CHANGELOG authorship

**Q: Who writes the v0.4.0 CHANGELOG entry?**

Options presented:
- You write it, I don't touch the file — Claude hands over material only; zero risk to the
  append-only rule
- I draft it somewhere else, you paste it — user still owns every byte that lands in the file
- I append directly, you review the diff — fastest, but the exact operation the standing rule was
  written about

**Selected:** "You write it and commit it, I'll review and change things later to my own language"
— i.e. the third option, chosen with the risk stated.

**Note:** recorded in CONTEXT.md as an explicit, informed override scoped to this one entry.
Append-only still binds.

---

**Q: How deep should the entry go? (v0.3.0's entry is 12 lines; v0.4.0 is ~15 phases of work.)**

Options presented:
- Match v0.3.0's density — ~10-15 short bullets, only what a player notices
- Fuller grouped list — ~25-40 bullets grouped by feature area
- Headline features only — five or six bullets plus Known Issues

**Selected:** "match 0.3 density, but I'll also change it a lot later"

---

**Q: What should the entry be titled?**

Options presented:
- Cooldown Tracking and Merge Mode
- Cooldown Tracking and Full CDM View
- You decide

**Selected:** "Cooldown Tracking and Full CDM View" — matches the milestone name in ROADMAP.md.

---

## Area: README scope

**Q: How far does the README get reworked?**

Options presented:
- Rewrite it to describe the addon as it is now — biggest change, accurate picture
- Rework Features/Usage, leave the Lust section — less churn, structure still implies lust is the
  headline
- Append a v0.4.0 section — smallest diff, reads as layers of history

**Selected:** "Rewrite it to describe the addon as it is now"

---

**Q: Does the README need new screenshots?**

Options presented:
- Note what's needed, you capture them
- Leave the showcase alone
- Drop the stale ones

**Selected:** "Leave the showcase alone" — existing images still show real functionality.

---

## Area: Store copy location

**Q: Where should the CurseForge / Wago copy live?**

Options presented:
- A tracked file in the repo — reviewable, reusable, both sites identical by construction
- Just hand me the text — nothing committed, sites can drift
- Keep it in .planning — versioned but not shipped

**Selected:** "I'll handle that myself from the README, they use .md format"

**Consequence:** no store-copy artefact at all. The README becomes the single source, so it has to
carry the Forever SavedVariables caveat itself — that is how DOC-03 is met.

---

## Area: Known Issues refresh

**Q: Which of this milestone's limitations go public?**

Options presented:
- Only what a player would hit and wonder about
- Everything found this milestone
- You decide

**Selected:** "Only what a player would hit and wonder about"

---

**Q: DOC-05 says assert nothing unverified about what the CDM tracks natively. Make no
comparative claims at all?**

Options presented:
- No comparative claims — nothing to go stale, nothing to re-verify per release
- Claim only what I verify first — more useful to a reader, but has a shelf life

**Selected:** "do what you want, I'll review and cleanup the text in detail later anyways"

**Claude's discretion, exercised:** no comparative claims. Recorded in CONTEXT.md with the
reasoning, so it is visible rather than silent.

---

## Deferred Ideas

- Fresh screenshots for the settings panel and Merge Mode
- Repo-root hygiene before tagging (`TerribleBuffTracker.zip`, `#CLAUDE.md#`, `#Display.lua#`)
- Complete racial catalogue (already a next-minor-milestone item in PROJECT.md)

## Claude's Discretion Items

- DOC-05 comparative claims — resolved to "none", see above
- All exact wording, since the user has said twice they will rewrite it in their own voice

## Surfaced During Discussion

- `PROJECT.md`'s "v0.4.0 ships Eureka! alone" line is stale as of 2026-09-23 — Orc (two racials)
  and Troll Berserking also ship, plus racial cooldown tiles. Captured as D-12; this phase fixes
  it and must keep the public copy consistent with it.
