# Phase 58: Cleanup - Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Process phase with no requirements. It cleans up the code this milestone introduced (Phases 53 to
57.5) before the Forever and retail review passes:
- unify the duplication the milestone introduced;
- audit the hot paths (tick, UNIT_AURA, UNIT_SPELLCAST_SUCCEEDED);
- remove dead code and unused definitions;
- confirm stylua is clean and every Lua file is CRLF;
- review the release scripts.

Code that predates the milestone is **not** refactored (PROJECT.md "No refactors during cleanup
phases"; CLAUDE.md GSD Workflow). The user adds three named decisions, below.

</domain>

<decisions>
## Implementation Decisions

### Reminder internal names (user decision)
- **Rename** the Phase 57 "visibility" runtime to reminder names. It now serves only reminders,
  and the names clash with the container Visibility setting:
  - `ns.visibilityKeys` → reminder name
  - `ns.visibilityAuraID` → reminder name
  - `ns.visibilityWatch` → reminder name
  - `ns:RebuildVisibilityWatch` → reminder name
  - `ns:VisibilityGate` → e.g. `ns:ReminderGate`
  - `ns:VisibilityShowsIn` → e.g. `ns:ReminderShowsIn`
  - any other name whose "visibility" means reminder
- It is a pure rename with no behaviour change. Update every caller and comment. The container
  Visibility setting (`cs.visibility`, the Edit Mode dropdown) keeps its name. Prove it with a gate:
  no old name remains in Lua (comments included, except history notes that say "formerly"), and
  `scripts/aura-read-gate.js` and `migrate-dryrun.js --selftest` still pass. If
  `aura-read-gate.js` allowlists a renamed reader, update the allowlist in the same commit.
- This lifts the 57.2 "no broad renames" instruction. That instruction protected untested code;
  57.2–57.5 are now tested in game.

### Release safety checks (user decision)
- **Leave `scripts/release.bat` alone.** Do not wire `aura-read-gate.js` or `migrate-dryrun.js`
  into it. They stay as tools the phases run. The release-script review still happens: read
  install.bat and release.bat against the current file set, but change nothing unless something is
  broken.

### Docs (user decision; CHANGELOG.md is never touched)
- **CLAUDE.md, stylua line:** correct the instruction. A bare `stylua` exits with "error: no files
  provided"; the working form is `stylua .` from the repo root, which picks up `stylua.toml`. Keep
  the history note, and edit only that rule's wording.
- **CLAUDE.md, Architecture list:** update it to the current file set:
  - add Providers.lua, MergeMode.lua and Config.lua, and anything else in the TOC;
  - add scripts/aura-read-gate.js and scripts/migrate-dryrun.js;
  - keep the existing style of one line per file.
  Read the TOC and the files for each one-line description.
- **REQUIREMENTS.md:** reword ADD-07 and DTRK-01 from "Simple/Detailed" to "General/Advanced".
  Mark requirement text that later decisions superseded (e.g. DTRK-01's "switch", and REM-02's
  "no duration" wording if still present), with a short "Superseded/revised 2026-09-29" note. The
  requirement IDs don't change.
- Everything else under .planning is maintained as usual.

### Claude's Discretion
- **Reminders container "In Combat" option: KEEP IT** (user correction, 2026-09-29). Reminders
  do work partially in combat. When a reminder has a known duration and its timer runs out
  mid-combat, the icon shows and reminds the user mid-combat (the 57.2-05 behaviour). "In Combat"
  is therefore a valid setting for a reminders container. The earlier notes that say it "can never
  show anything" are stale. Correct them where they still exist: the 57.2 REVIEW IN-05 note, the
  57.2-05 SUMMARY "Known behaviour", the 57.2 UAT, STATE.md, and any code comment. Don't change
  the option.
- The new names, and which duplicated helpers to unify.

### Named cleanup targets carried in STATE.md / reviews
- The base/override lookup that was duplicated in Core.lua: check whether 57.5's
  `ns:CastRuleFamily` and cache already unified it, and finish the job.
- The Suggested-tile code paths for racial cooldowns and metaReminders (57.4 added a shared
  `PlaceSuggestedKeyTile`; check for any leftover duplication).
- Dead code:
  - `ns:CooldownKindFor` (migration-only since 2026-09-29, keep for v8);
  - `WireExclusivePair` (one caller; pre-milestone, so leave it unless the milestone introduced it);
  - anything the 57.x reviews left unused.
- Hot paths: confirm the per-cast re-check timer, the aura memo and the known-state cache don't
  allocate per event or per frame.
- Old phase-plan gates that fail by design (the 57.4-03 T1 scope freeze and the 57.5-03 T2
  all-pending UAT check) are historical. Leave them alone; don't "fix" them.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `CLAUDE.md`: project rules (stylua, CRLF, CHANGELOG, cleanup scope)
- `.planning/PROJECT.md`: Key Decisions, including "No refactors during cleanup phases"
- `.planning/ROADMAP.md` "### Phase 58: Cleanup": success criteria
- `.planning/STATE.md`: named cleanup targets and review follow-ups
- `.planning/phases/57.2-buff-reminders-category/57.2-REVIEW.md` (WR-05, IN-05) and the 57.3,
  57.4 and 57.5 REVIEW.md files: skipped or deferred findings
- `scripts/aura-read-gate.js`, `scripts/migrate-dryrun.js`: gates that must keep passing
- `scripts/install.bat`, `scripts/release.bat`: reviewed, not changed unless broken

</canonical_refs>

<code_context>
## Existing Code Insights
- The reminder runtime to rename lives in Core.lua (the index and watch builders), BuffEngine.lua
  (VisibilityGate, VisibilityShowsIn, RefreshAuraStates), Display.lua (callers) and CDMTab.lua (if
  any).
- Rank and cast families: `ns:CastRuleFamily` and its cache (57.5 WR-04), `ns:ResolveRankFamily`,
  `ns.rankFamilies` and `ns.detailedRankFamilies`.
- Suggested tiles: `PlaceSuggestedKeyTile` (CDMTab.lua), `ns:RacialCooldownKeys` and
  `ns:MetaReminderSuggestionKeys` (Providers.lua).
</code_context>

<specifics>
## Specific Ideas
None beyond the decisions above.
</specifics>

<deferred>
## Deferred Ideas
- Wiring the check scripts into release.bat was declined for now (user decision, 2026-09-29).
</deferred>

---

*Phase: 58-cleanup*
*Context gathered: 2026-09-29*
