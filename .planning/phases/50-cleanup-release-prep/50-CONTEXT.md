# Phase 50: Cleanup & Release Prep - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Everything v0.4.1 built — generic item tracking, the pandemic highlight, the dispel-type border and
the Forever racial catalogue — gets the duplication **this milestone introduced** unified, its hot
paths audited, dead code swept, release scripts reviewed, and a CHANGELOG entry drafted. Process
phase: no requirements of its own, and the standing end-of-milestone mandate in `CLAUDE.md`.

**This phase is process-only. It ships no user-visible behaviour change except SC3**, which is an
internal render optimisation with no visual difference.

**It is not the release.** Phases 51 (Forever review) and 52 (retail review) follow it, and the
milestone is squash-merged to `main` before `release.bat` is ever run.

</domain>

<decisions>
## Implementation Decisions

### Scope — what this phase does NOT do

- **D-01: F-3 (the aura-icon swap for divergent racials) is OUT.** Deferred to the backlog as
  **999.8**. User decision, 2026-09-25: *"let's not do any of this icon swap from skill to aura on
  racials, note it in the backlog for later, I wanna finish this milestone faster and this raises
  too much questions and tests."*

  Recorded because the reversal is instructive, not because it is in doubt: F-3 was folded INTO this
  phase earlier the same day, on Claude's initiative rather than the user's, and that was wrong on
  its own terms — it is a user-visible behaviour change in a process phase, and gating its three
  rows needs an undead plus both Skyborne characters. **Do not re-fold it.** Its full scope was
  worked out before the reversal and is recorded in backlog 999.8 so it needs no re-discussion when
  it is picked up.

- **D-02: Speed is an explicit goal for the rest of this milestone.** The user asked to *"speed
  things up"*. Prefer the narrower option where two are defensible, and do not open new questions
  that need in-game answers.

### SC3 — the dispel-border dirty check

- **D-03: Implement it, and land it EARLY in the phase.** Not for the performance — the out-of-combat
  path already dirty-checks and sets nothing once settled, and only the in-combat secret path
  re-issues, for the one or two entries that actually carry a border. The reason for doing it now is
  **timing**: Phases 51 and 52 are two full review passes, so anything landing before them is
  verified for free and needs no gate of its own.

- **D-04: The cache key must be a NON-SECRET identity, not the atlas.** `ApplyDispelBorder`
  (`Display.lua:780`) currently collapses a secret atlas to the `SECRET_ATLAS_KEY` sentinel and
  re-sets on every pass because no secret may be compared against a stored value. The entry's
  `cooldownID` is the candidate — already proven plain, it is `ns.mergeItemFrames`' own key.

- **D-05: The pooled-widget hazard is the thing that makes this non-trivial, and it has a precedent
  in the same file.** A widget reused for a DIFFERENT entry across a container re-sort, where
  `dispelShown` never goes false, must not keep the previous entry's colour. `ApplyCooldownSlot`
  already solves the identical problem — `if icon._cdGen ~= ns.cooldownGeneration or icon._cdKey ~=
  entry.key then` clears its stamps (`Display.lua:1596`). Follow that shape rather than inventing one.

- **D-06: Bars and item-backed icons only.** The engine route (`AddDispelTypeTexture`) draws its own
  border and has no equivalent path.

### Release copy

- **D-07: NO README changes.** User decision, 2026-09-25. This overrides ROADMAP Success Criterion 5,
  which names README and the CurseForge/Wago copy alongside the CHANGELOG. The store copy is
  packaged from README and is therefore also unchanged — there is no separate store-copy file in
  the repo.

- **D-08: Draft the CHANGELOG entry; do NOT append it.** Hand the user a proposed entry to paste and
  edit themselves. `CLAUDE.md`'s standing rule is absolute and was destroyed once before, on
  2026-09-19: the file is hand-edited, append-only, never rewritten, and a diff against expectation
  is a deliberate edit rather than a bug.

### Claude's Discretion

The user did not select **Refactor boundary** for discussion, so the calls below are Claude's, made
under D-02 (prefer narrow) and the standing rule that cleanup covers duplication the milestone
introduced while `PROJECT.md`'s "No refactors during cleanup phases" protects everything older.

- **Three near-identical key parsers** — `ns:CooldownKeySpellID` (`Core.lua:493`, `cd:`),
  `ns:ItemKeyItemID` (`:519`, `item:`) and `ns:RacialKeySpellID` (`:546`, `racial:`). Two of the
  three are milestone-introduced; **`cd:` predates the milestone and is protected.** Default: unify
  only if it can be done without touching the `cd:` parser's behaviour; otherwise leave all three.
  A shared helper used by two of three is not obviously better than three clear five-line functions.
- **Three walks of the racial def list that each resolve one def by spellID** —
  `ns:RacialDefForSpellID`, `ns:RacialCooldownSeed` and `ns:ConditionalCooldown`
  (`Providers.lua:1068`, `:1137`, `:1176`). **All three are milestone-introduced**, so this is
  squarely in scope. The last two are `RacialDefForSpellID` plus a field test.
- **Pandemic FX is split icon/bar** (`EnsurePandemicIconFX`/`EnsurePandemicBarFX`,
  `ApplyPandemicIcon`/`ApplyPandemicBar`). The divergence is documented in the code — the bar FX is
  a true child of the bar and inherits scale and alpha, the icon FX does not. **Likely justified
  divergence rather than duplication; confirm before unifying, and leave it alone if the comment
  holds.**
- **`RACIAL_SUPPORTED_LINES` / `RACIAL_UNSUPPORTED_LINES` are ALREADY GONE.** REQUIREMENTS.md
  predicted they would become dead code when RACE-09 was closed; Phase 49 removed them. Do not go
  looking for them.

### Bookkeeping to correct in this phase

- **`.planning/REQUIREMENTS.md`'s traceability table is a phase stale.** It still reads *"RACE-07 —
  Data collected for all 10 races; implementation not started"* and *"RACE-10 — Not started"*, and
  RACE-07, RACE-08 and RACE-10 are all unticked. All three are implemented and gate-passed. Flagged
  to the user during discussion; no objection raised.
- **A leftover executor worktree exists** at `.claude/worktrees/agent-ad696cb1` (branch
  `worktree-agent-ad696cb1`, at `a3b1aa3`), still registered in `git worktree list`. Sweep it if it
  holds nothing unmerged.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### This phase's own definition
- `.planning/ROADMAP.md` § "Phase 50: Cleanup & Release Prep" — the five success criteria. **SC5 is
  narrowed by D-07 above: no README and no store-copy changes, CHANGELOG drafted not appended.**
- `CLAUDE.md` § "GSD Workflow" — the cleanup mandate this phase exists to satisfy.
- `CLAUDE.md` § "Workflow" — the CHANGELOG rules, and the `stylua` / `git ls-files --eol` rules that
  Success Criterion 4 turns into a gate.

### The SC3 deferral
- `.planning/REQUIREMENTS.md` § DISP, "Known trade, carried to Phase 50" — why `ApplyDispelBorder`
  re-issues `SetAtlas`, and why it was deferred rather than fixed in Phase 48.1.
- `Display.lua:770-813` — `SECRET_ATLAS_KEY` and `ApplyDispelBorder` itself, including the comment
  explaining why the secret cannot be the cache key.
- `Display.lua:1590-1600` — `ApplyCooldownSlot`'s stamp-clearing on `_cdKey ~= entry.key`, the
  precedent D-05 says to follow.

### The cleanup-scope collision
- `.planning/PROJECT.md` § Key Decisions, "No refactors during cleanup phases" — protects
  pre-existing code. Read together with `CLAUDE.md`'s mandate; they are complementary, and the
  reading was settled by user decision on 2026-09-18 (Phase 30) when they first collided.

### What the milestone built (for the CHANGELOG draft)
- `.planning/REQUIREMENTS.md` — ITEM-01..10, PAND-01..05, DISP-01..04, RACE-07/08/10, each with its
  in-game verdict. The source of truth for what actually shipped.
- `.planning/research/FOREVER-RACIALS.md` — the racial catalogue: 10 races, 21 racials, decisions
  D-1..D-7, findings F-1 (Shadowmeld's conditional cooldown, resolved), F-2 (Eureka!'s per-class
  charges, resolved) and F-3 (deferred to backlog 999.8).
- `.planning/research/PANDEMIC.md` — the pandemic highlight's read surface.

### The two shipped waivers (candidates for the CHANGELOG's known-issues note)
- Phase 49 **G8** — the Skyborne upward duration correction, never reproducible in game; both
  Skyborne second racials ship on their minimum duration.
- **F-2's priest branch** — a gnome priest's Eureka! spending a stack on a heal. The non-priest
  branch passed on a gnome mage, 2026-09-25.
- Precedent for how a known limitation is written up: the Forever SavedVariables bug, already
  documented in both `CHANGELOG.md` and `README.md`.

### Release mechanics
- `scripts/release.bat` and `.github/workflows/release.yml` — reviewed against what changed, per
  Success Criterion 4. **Not run in this phase.**
- Memory: squash-merge the milestone branch to `main` BEFORE running `release.bat`; never tag from
  the milestone branch.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ApplyCooldownSlot`'s stamp-clearing block** (`Display.lua:1596`) — the exact
  widget-changed-slots invalidation SC3 needs, already written and already shipped.
- **`ns:RacialDefForSpellID`** (`Providers.lua:1068`) — the one real lookup the other two racial
  walks reduce to.

### Established Patterns
- **Dirty-check stamps live on the widget, prefixed with `_`** (`_lastStart`, `_userCdState`,
  `_desat`, `_stacks`, `_dispelShown`, `_dispelKey`). SC3's new key follows this.
- **A secret is relayed, never read** — no comparison, concatenation, `tostring` or `nil` test
  against a secret. This is what forces SC3's key to be a separate non-secret identity.
- **`issecretvalue()` before `type()`**, always, including on APIs that cannot plausibly return a
  secret.
- **Module-level tables wiped with `wipe()`**, never reallocated, on anything the render path walks.

### Integration Points
- `ApplyDispelBorder` has four call sites (`Display.lua:2027`, `:2193`, `:2314`, `:2549`) — the bar
  path, the bar pool reset, the icon path, and the icon pool reset. **Both pool resets pass
  `(widget, nil, false)`**, which is what currently clears the stamps; any new stamp has to be
  cleared there too.

### Constraints that bound the work
- **No test runner exists and none is planned.** A static sweep proves shape, never behaviour.
- **`stylua` writes CRCRLF for a comment inside a multi-line expression**, turning the file binary to
  git — invisible to `file`, `grep` and `git diff`. Only `git ls-files --eol` catches it. SC4 makes
  this a gate.
- **A `local function` is an upvalue only to functions declared after it.** Hit five times in this
  project; put shared helpers on `ns`.

</code_context>

<specifics>
## Specific Ideas

- The user's framing of SC3 at the time it was deferred, and the reason it is named explicitly in
  the ROADMAP rather than left to a general hot-path sweep: it was deferred *deliberately rather
  than forgotten*, because the code had just been verified in game and was not worth destabilising
  the same day. That window has closed — it is now the safest possible moment, with two review
  passes immediately downstream.
- The CHANGELOG draft should describe four things, in the order the milestone built them: generic
  item tracking, the pandemic highlight, the dispel-type border, and the Forever racial catalogue.

</specifics>

<deferred>
## Deferred Ideas

- **999.8 — the aura-icon swap for divergent racials (F-3).** Written to the ROADMAP backlog during
  this discussion with its full scope, so it needs no re-discussion when picked up. See D-01.
- **G8 retest opportunity.** The user will be on a Skyborne character for nothing in this phase now
  that F-3 is out, so the opportunistic retest noted during discussion no longer has a free ride.
  G8 stays waived for this release.
- **`RACE-06` — retail racials.** Deferred again at this milestone's kickoff.
- **999.5 — cooldown icon grey through the GCD.** `todo.match-phase 50` returned zero matches, and
  REQUIREMENTS.md explicitly parks it pending a repro. **Not folded.**
- **`tools/TBTProbe/`** — 2,389 lines of probe scaffolding in the repo but not in the TOC or the
  zip. No decision taken on whether it stays; a cleanup phase is a plausible home, but it predates
  this milestone and is therefore protected by "No refactors during cleanup phases" unless the user
  asks.

</deferred>

---

*Phase: 50-cleanup-release-prep*
*Context gathered: 2026-09-25*
