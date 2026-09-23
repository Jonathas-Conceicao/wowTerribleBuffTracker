# Phase 45: Documentation & Release Prep - Context

**Gathered:** 2026-09-23
**Status:** Ready for planning

<domain>
## Phase Boundary

The public-facing story — `README.md`, the CurseForge/Wago descriptions, and `CHANGELOG.md` —
made to match what v0.4.0 actually ships, written last and immediately before merge and release.

Covers DOC-02, DOC-03, DOC-04, DOC-05. Nothing in the addon's behaviour changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### CHANGELOG
- **D-01:** **Claude writes and commits the v0.4.0 entry.** The user reviews it afterwards and
  rewrites it into their own language. This is an explicit, informed override of CLAUDE.md's
  hands-off rule, given after being shown that this is the exact operation the rule was written
  about, and it is **scoped to this one entry** — the rule stands for everything else.
- **D-02:** **Append-only still binds absolutely.** The new section goes above `## v0.3.0` and
  every pre-existing line must stay byte-identical. `git diff` proves it. If the file does not
  look as expected, stop and ask rather than "fixing" it — a shorter or reworded existing entry is
  the user's deliberate edit, never a regression.
- **D-03:** Density matches v0.3.0's entry: `### New Features` / `### Fixes` / `### Known Issues`,
  roughly 10–15 short bullets, only what a player would notice. The user will prune further.
- **D-04:** Title is `## v0.4.0 — Cooldown Tracking and Full CDM View`, matching the milestone name
  in ROADMAP.md so the public entry and the planning docs agree.

### README
- **D-05:** **Full rewrite of Features and Usage** to describe the addon as it is now, including
  the `## Lust / Heroism Tracking` section. The current text describes a v0.2-era addon and never
  mentions cooldown trackers, the four base containers, user containers, Merge Mode or the
  settings panel. A new reader should get an accurate picture, not an archaeological one.
- **D-06:** **The Showcase images are left alone.** They still show real functionality. Do not
  remove them and do not block the release on new captures — Claude cannot take screenshots, and
  the user has chosen not to spend time on it now.
- **D-07:** DOC-02's substance: one download running on both Midnight retail and WoW Forever, with
  both interface versions named (120100 and 16001).

### Store copy (CurseForge / Wago)
- **D-08:** **No separate store-copy file, and no text handed over in chat.** Both sites take
  Markdown, and the user writes the descriptions themselves from the README. So **the README is
  the single source** and DOC-03 is satisfied by the README carrying the right content — including
  the Forever SavedVariables caveat, which is what stops a Forever user filing it against TBT.
- **D-09:** Nothing new is added to `.pkgmeta`; no new tracked file exists to ignore.

### Known issues
- **D-10:** Public copy carries **only what a player would hit and wonder about**:
  - Forever SavedVariables not persisting (already documented; keep, it is the client's bug)
  - Restricted content (M+/raid): a buff can keep showing until its typed duration runs out,
    because the aura cancellation scan is gated there
  - Charge counts can be blank in restricted content
- **D-11:** Deliberately **not** public, though all are real and recorded in the run sheets:
  merged debuffs needing a hostile target, a potion cooldown not resolving inside a key, an
  equipped item's cooldown going unreadable under restriction. These read as noise to a player and
  would not prompt a bug report.

### Corrections this phase must make
- **D-12:** **`PROJECT.md`'s racial statement is stale.** It says "v0.4.0 ships Eureka! alone;
  every other racial deferred". As of 2026-09-23 the addon ships Gnome (Eureka!), Troll
  (Berserking) and Orc (two racials), Forever-only, and offers racial cooldown tiles. Fix the line
  and make sure no public copy repeats the old claim.

### Claude's Discretion
- **DOC-05 / CDM comparative claims.** The user's answer was "do what you want, I'll review and
  clean up the text in detail later". Taking the safe reading: **make no comparative claims about
  what Blizzard's CDM does or does not track natively.** Describe what TBT does and stop there.
  Nothing then goes stale when Blizzard changes the CDM, and nothing needs re-verifying against a
  live client before each release — which is exactly what DOC-05 was written to prevent.
- **Exact wording throughout.** The user has said twice that they will rewrite the text in their
  own voice. Optimise drafts for being easy to prune rather than for polish.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Binding rules
- `CLAUDE.md` — the CHANGELOG rule in full, including the 2026-09-19 violation that produced it.
  D-01 overrides it for one entry only; the rest of the rule is untouched.
- `.planning/REQUIREMENTS.md` DOC-02 through DOC-05 — the four requirements this phase closes.
- `.planning/ROADMAP.md`, section "Phase 45" — goal and the four success criteria, including the
  byte-identical-diff test for the CHANGELOG.

### What actually shipped (source material for the copy)
- `.planning/testing/44-RETAIL-PASS.md` — the retail pass, the Merge Mode rework, and the table of
  what each slot shape draws its cooldown from. Its "Still on a fallback path" section is the
  honest limitations list.
- `.planning/testing/43-FOREVER-E2E-PASS.md` — the Forever pass, its features table, and the
  known issues carried forward.
- `.planning/PROJECT.md`, sections "Current Milestone" and "Key Decisions" — what v0.4.0 set out
  to do. Note D-12: the racial line in here is wrong and must be corrected.
- `.planning/MILESTONES.md` — the shape prior milestone entries take.

### Files being changed
- `README.md` — 96 lines; Features, Usage and Lust / Heroism Tracking all rewritten (D-05).
  Showcase and License untouched (D-06).
- `CHANGELOG.md` — 109 lines; append above `## v0.3.0` only (D-02).
- `TerribleBuffTracker.toc` — read-only here, but it is where the two interface versions are
  stated and the README must agree with it.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `README.md`'s existing Known Issues section already documents the Forever SavedVariables bug in
  the right tone — a client bug, nothing to do from the addon side. Reuse that framing for the new
  restricted-content entries rather than inventing one.
- `CHANGELOG.md`'s `### New Features` / `### Fixes` / `### Known Issues` heading trio is
  consistent across every prior entry. Follow it exactly.

### Established Patterns
- The addon is **one download, two interface versions** — `## Interface: 120100, 16001` in a
  single TOC. Any copy implying separate retail and Forever builds is wrong.
- Forever-only features exist and must be described as such: the "cover all ranks" checkbox, and
  as of 2026-09-23 the racial trackers and racial cooldown tiles.

### Integration Points
- `.pkgmeta`'s ignore list already excludes `.planning`, `.github`, `CLAUDE.md` and `README.md`
  from the packaged zip. D-08 adds nothing to it.
- `scripts/release.bat` tags and pushes; GitHub Actions packages. Docs must be committed before
  the tag, not after.

</code_context>

<specifics>
## Specific Ideas

- The user will paste the README's content into CurseForge and Wago themselves, in Markdown. Write
  the README so that is possible without editing — avoid repo-relative links and anything that
  only renders on GitHub, at least in the sections a store page would carry.
- Two rewrites are expected from the user afterwards (CHANGELOG and README wording). Draft for
  prunability.

</specifics>

<deferred>
## Deferred Ideas

- **Fresh screenshots** for the settings panel and Merge Mode — the Showcase is knowingly stale
  (D-06). Whenever the user feels like capturing them.
- **Repo-root hygiene before tagging** — `TerribleBuffTracker.zip`, `#CLAUDE.md#` and
  `#Display.lua#` are sitting in the working tree. Not this phase's scope, but worth a look before
  a release tag goes out.
- **Complete racial catalogue** — already recorded in PROJECT.md as a next-minor-milestone item.

</deferred>

---

*Phase: 45-Documentation & Release Prep*
*Context gathered: 2026-09-23*
