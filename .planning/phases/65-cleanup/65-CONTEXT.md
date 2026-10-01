# Phase 65: Cleanup - Context

**Gathered:** 2026-10-01
**Status:** Ready for planning

<domain>
## Phase Boundary

v0.5.1 ships without duplication, dead code or hot-path waste that this milestone (Phases 61-64 and
their follow-ups) added. It is a process phase: no requirements and no behaviour change a player could
notice, except the two small fixes named below (tooltip ownership, script error handling). Code that
predates the milestone stays untouched, per `PROJECT.md`'s "No refactors during cleanup phases" Key
Decision read together with CLAUDE.md's cleanup mandate.

</domain>

<decisions>
## Implementation Decisions

The user chose not to discuss any area ("all these items are things I think you can handle on your
own", 2026-10-01). Every decision below is Claude's, made against the roadmap success criteria, the
deferred review items and the carried-forward user decisions.

### Duplication the milestone introduced (unify)
- **D-01: castID / auraID field factory (63 review IN-06).** The Cast spell ID field in CDMTab.lua
  is a near-verbatim copy of the Aura ID field: build, reset, prefill, update, read, validate. The
  duplication is this milestone's, so fold both into one shared "follows the Spell ID" field
  builder. The Aura ID field's behaviour must not change at all: same labels, same preview text,
  same nil-means-follow, same validation. The Cast spell ID field keeps its one difference, an
  emptied box reads `false` and previews "No click action". Diff the two before writing the factory,
  so every difference becomes a parameter rather than being lost.
- **D-02: stamp-clear block (63 review IN-02).** Extract one `ClearClickStamp(icon)` in Display.lua
  that returns whether anything was cleared, and use it in all three places. Mind the upvalue-order
  trap: declare it above its first caller, or put it on `ns`.
- **D-03: spell-name resolvers (63 review IN-01): no change, close the item with the reason.**
  The three are not the same function. `ResolveCastName` (ReminderClick.lua) returns nil for an
  unreadable or empty name, which a cast attribute needs. `ns:SpellPreview` (Core.lua) substitutes
  "Spell N" and an icon. Core's file-local `SpellName` skips `CanReadTable` and the empty-string
  check. The two older ones predate the milestone and are protected. Moving `ResolveCastName`
  elsewhere would not remove a copy. Record the decision in 63-REVIEW.md's IN-01 resolution.
- **D-04:** look for any other duplication 61-64 introduced (for example the retail rows' option
  handling, the faction-suffix tab icon paths, the REM-05 lead-window checks) and unify it under the
  same rule. Pre-milestone code is not touched even when it looks similar.

### Small fixes deferred into this phase
- **D-05: tooltip ownership (63 review IN-05).** `OverlayOnLeave` hides `GameTooltip` only when
  `GameTooltip:IsOwned(self)`, matching the EditModeFrames hook.
- **D-06: install.ps1 empty directories (62 review IN-02).** After the prune loop, remove empty
  directories under the deployed addon folder, deepest first, so a renamed or emptied
  `Media/Textures` leaves nothing behind. Prove it with a real install, using a temporary probe
  texture deployed and then pruned, as Phase 62 did.
- **D-07: png2blp.js input checks (62 review IN-03).** A missing `Media/Source` goes through
  `fail()`. Duplicate output basenames are rejected. The full 8-byte PNG signature is checked.
  After the change, `node scripts/png2blp.js` must still leave `git status --short Media/` empty:
  the shipped BLPs regenerate byte-identical.

### Dead code and hot paths (roadmap criteria 2 and 3)
- **D-08:** remove what the milestone replaced: any leftover reference to `INV_Misc_Book_09`, the
  `GM-icon-settings` atlas and its fallback, the non-faction `icon_<name>` texture paths, and any
  orphaned BLP or PNG in `Media/` that no code reads. Also remove locals, constants or `ns` fields
  that 61-64 added and nothing reads any more.
- **D-09: hot-path audit.** Overlay placement runs only on login, Edit Mode exit, a container size
  change, a layout event and the single retry, never per frame or per tick. The REM-05 lead-window
  check in `GetActiveTimers` / `ns:ReminderInLead` allocates nothing per tick. The charge-count
  re-level runs only on a state change. Fix anything the milestone added that breaks this, and
  record anything pre-existing without changing it.

### Release and install scripts (roadmap criterion 4)
- **D-10:** review `scripts/install.bat`, `scripts/install.ps1`, `scripts/release.bat`, `.pkgmeta`
  and `.github/workflows/release.yml` end to end against `Media/Textures`. Carried forward from
  Phase 58 (user decision): `release.bat` is read but changed only if broken, and the two gate scripts
  are not wired into it.

### Docs
- **D-11: CLAUDE.md Architecture list.** Add `ReminderClick.lua`, `Media/Textures` (shipped BLPs)
  and `Media/Source` (PNG sources, not shipped), and `scripts/png2blp.js`, one line each in the
  existing style. Edit nothing else in CLAUDE.md.
- **D-12: Phase 64 bookkeeping.** 64-VERIFICATION.md and 64-REVIEW.md still describe Mark of the
  Wild as 102046. Add a note that it was changed to 1126 on 2026-10-01 (`f2d4209`). Do not rewrite
  history: append to the resolution. Lightning Shield (192106, `a793fe9`) was added after the review
  and needs a one-line mention in the same place.
- **D-13: CHANGELOG.md is never touched.** Carried forward, CLAUDE.md rule.

### Closing checks
- **D-14:** `stylua .` is clean. `git ls-files --eol` shows every touched file with its expected
  line endings (CRLF for Lua/XML/TOC/ps1/bat; .md files keep whatever they had). `node
  scripts/aura-read-gate.js` and `node scripts/migrate-dryrun.js --selftest` pass. Then a deploy
  with `./scripts/install.bat`. Never `sed -i` on `.planning/` or `.md` files.

### Claude's Discretion
- All of the above. The user delegated every area of this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Rules for cleanup scope
- `.planning/PROJECT.md`: the "No refactors during cleanup phases" Key Decision, and the per-client row tag decision
- `CLAUDE.md`: GSD Workflow cleanup mandate, Workflow rules (stylua, CHANGELOG, `sed -i`, `.gitattributes`)
- `.planning/ROADMAP.md` §"Phase 65: Cleanup": the four success criteria

### Deferred review items this phase closes
- `.planning/phases/63-clickable-reminders/63-REVIEW.md`: IN-01 (D-03), IN-02 (D-02), IN-05 (D-05), IN-06 (D-01)
- `.planning/phases/62-new-icons/62-REVIEW.md`: IN-02 (D-06), IN-03 (D-07)
- `.planning/phases/64-retail-class-buff-reminder-suggestions/64-REVIEW.md`: IN-02 accepted (no work), IN-03 superseded by `f2d4209` (D-12)

### Prior cleanup precedent
- `.planning/milestones/v0.5.0-phases/58-cleanup/58-CONTEXT.md`: release.bat stays as is, docs scope

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:SpellPreview` (Core.lua ~2487), Core's file-local `SpellName` (~2680), `ResolveCastName` (ReminderClick.lua:36): three resolvers that look alike but are not the same function (D-03)
- Aura ID and Cast spell ID fields in CDMTab.lua (~2300-2417 at 63 review time; line numbers have moved since)
- Stamp-clear sites in Display.lua: `ClearClickStamps` (~150), the per-icon else branch and the trailing-pool loop in the reminders render (~2758-2781 at review time)

### Established Patterns
- Module-level tables are wiped and reused, never reallocated per tick
- Lua file-local upvalue order trap: a local called from a function declared above it is nil. Use `ns` when in doubt
- Overlay writes happen out of combat only (`InCombatLockdown` guard, `PLAYER_REGEN_ENABLED` flush)

### Integration Points
- `ReminderClick.lua` loads after Display.lua (TOC order)
- `scripts/install.ps1` derives its file set from the TOC plus `Media/Textures`

</code_context>

<specifics>
## Specific Ideas

No specific requirements. Standard cleanup under the rules above.

</specifics>

<deferred>
## Deferred Ideas

- Backlog 999.19 (stack counts on custom trackers) and 999.20 (duration on the buff icon): not this milestone.
- 64 review IN-02 (an unreadable build number registers the wrong client's rows): accepted risk; revisit only if seen in game.

</deferred>

---

*Phase: 65-cleanup*
*Context gathered: 2026-10-01*
