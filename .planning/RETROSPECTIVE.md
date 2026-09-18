# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v0.3.0 — WoW Forever compatibility

**Shipped:** 2026-09-19
**Phases:** 7 (25-30, with 27.1 inserted) | **Plans:** 12 | **Commits:** 57 | **Span:** 2 days

### What Was Built

- Two flavour-suffixed TOCs (`_Mainline` at 120100, `_Camelot` at 16001) over one shared Lua/XML source
  set, with `scripts/check-toc.ps1` as a pre-tag drift guard and `.gitattributes` closing the
  line-ending blind spot.
- Argument-free multi-client `install.bat` deploying to every WoW client folder present on the machine.
- Two flavour-pure release zips from one tag: `.pkgmeta-mainline` / `.pkgmeta-camelot` plus a serialised
  two-job matrix in `release.yml`.
- TOOL-01, a spell-and-aura-ID tooltip, and META-01, data-driven meta-tile hiding.
- Three Forever-only defects fixed with narrow defensive reads, plus one real retail bug corrected on
  the way (the Trinket/Pot placeholder).

### What Worked

- **The blocking gate was the right shape.** Making `VER-01` (retail still loads after the rename) a
  hard gate rather than a deferred cleanup item was what made the no-rollback-TOC decision safe to take.
  The desk-level proof helped more than expected: `git log --stat` showing `1 file changed, 0
  insertions(+), 0 deletions(-)` for the rename meant the retail pass was confirmation rather than
  discovery, and it ran quickly.
- **Planners caught two of my own wrong decisions before they cost anything.** `duration = nil` would
  have thrown at `BuffEngine.lua:283`; omitting `-g` would have made both CI jobs emit the same filename
  and clobber each other. Both were specified confidently and both were wrong, and both were found by
  tracing the actual consumer — the arithmetic site, and the packager's own `release.sh` — rather than
  by reasoning about what "should" work.
- **Capability checks over client-identity checks.** Guarding on `TooltipDataProcessor.AddTooltipPostCall`
  existing, rather than on which client is running, meant one implementation served both flavours and a
  client lacking the API degrades to a silent no-op.
- **Data-driven beats a flavour guard, and not only because a constraint said so.** META-01 hides a tile
  when its catalog does not resolve. A future Forever build that ships lust spells makes the tiles
  reappear with no code change; a `WOW_PROJECT_ID` check would have needed editing.

### What Was Inefficient

- **The test-order inversion should have been asked about up front.** Phase 25 was designed retail-first.
  The user could only test Forever first, which turned Phase 26 from a dependent into a prerequisite —
  `install.bat` could not deploy to any client after the rename until it was fixed — and left
  `25-INGAME-VERIFICATION.md` superseded for execution while still being the formal record. Two
  run-sheets had to be written to paper over a sequencing assumption never checked with the person doing
  the testing.
- **Record hygiene drifted badly from reality.** At close, 23 requirement checkboxes sat unchecked while
  the traceability table in the same file recorded them verified, three `VERIFICATION.md` files still
  read `human_needed` after their gates had passed, and `DIST-01/02/08` read "Pending" after being
  verified. The pre-close audit flagged nine items, six of which were stale records rather than open
  work. Updating a requirement's status at the moment it closes is cheaper than reconstructing it later.
- **I raced my own executor.** After explicitly promising to serialise executors, I ran
  `git add && git commit` while a Phase 30 executor had files staged, bundling its `STATE.md`,
  `ROADMAP.md` and `30-VERIFICATION.md` into an unrelated commit. The commit boundary is the artifact
  here, and it was lost for no gain.
- **Repeated shell-quoting failures.** A regex mangled `REQUIREMENTS.md`, a template literal broke a
  heredoc, and heredoc quoting failed twice more. Each cost a retry. Writing the script to a file and
  running it is more reliable than escaping it through a shell.

### Patterns Established

- **`issecretvalue()` before any comparison or concatenation — including on a value an API just returned
  successfully.** A `pcall` does not cover this: the call succeeds and the comparison after it raises.
  And `type()` reports `"number"` for a secret number, so a type check alone passes and gives false
  confidence. The rule was already written at `BuffEngine.lua:39` and was violated anyway in new code.
- **`/reload` is not a persistence test.** The data survives in memory, so the test cannot fail. Only
  logout→login exercises the load path.
- **A line-ending-only change can produce a literally empty `git diff`** under `core.autocrlf=true` with
  no `.gitattributes`. It happened twice before anyone noticed. Fixed at the root (`stylua.toml`) and the
  blind spot itself closed (`.gitattributes`).
- **An engine-side global present on Midnight is not guaranteed on Forever.**
  `GetScaledCursorPositionForFrame` had shipped since v0.2.0 and threw 53 errors in one Forever drag
  session. Prefer the idiom a file already uses elsewhere over the convenience wrapper.
- **Verify a guard actually fails before trusting it.** `check-toc.ps1` was proven against four
  independent negative cases, and that exercise found two real bugs in the guard itself — a PowerShell
  drive-syntax parse error and a `Where-Object` filter that silently never matched.

### Key Lessons

1. **Trace the consumer, don't reason about the contract.** Both of my wrong decisions this milestone
   were caught by reading the code that would receive the value — the arithmetic at
   `BuffEngine.lua:283`, the discovery logic in the packager's `release.sh`. Neither was caught by
   thinking harder about the API.
2. **Ask who is running the test before designing the test order.** The whole Phase 25/26 resequencing
   followed from assuming a retail-first pass was available.
3. **Close a record when it closes.** Six of the nine items the pre-close audit flagged were bookkeeping
   lag, not work.
4. **A green CI check is not evidence.** The packager omits a game-version tag silently, so
   `DIST-06` explicitly requires reading the log in full. Worth generalising to any CI-verified claim.
5. **State the invalidating detail plainly and early.** The false SavedVariables claim survived in
   `PROJECT.md` for a day because the original record said "verified" without saying "by `/reload`". The
   method was the whole problem, and it was the part left out.

### Cost Observations

- Model mix: predominantly Opus for orchestration and planning, with GSD subagents (`gsd-planner`,
  `gsd-executor`, `gsd-verifier`) doing the bulk of per-phase work.
- Long single-session run with one compaction; the autonomous run covered Phases 25-28 in one stretch.
- Notable: the milestone's two most expensive mistakes cost nothing in the end, because both were caught
  in planning rather than after implementation. The cheap-to-fix window is before the code exists.
- `gsd-sdk` handler gaps recurred all milestone — `state.milestone-switch` does not exist,
  `state.record-session` and `state.record-metric` are silent no-ops against this project's STATE.md
  shape, `audit-open` is not a registered `query` subcommand (only reachable through `gsd-tools.cjs`),
  and `milestone.complete` could not be invoked at all: positional version is rejected and `--version`
  is swallowed by the CLI's own flag. Every one of these was worked around manually.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.2.0 | 6 | — | First GSD milestone; CDM tab + Edit Mode rework |
| v0.2.1 | 5 | — | Secret-value gating introduced as a first-class concern |
| v0.2.3 | 5 | — | Meta-trackers; data tables split from logic |
| v0.2.4 | 8 | 23 | Provider architecture; unified `ActiveProc`; zero type-branching in Display |
| v0.2.5 / v0.2.6 | 0 | 0 | **Shipped outside GSD** — no phase artifacts exist, and were not reconstructed |
| v0.3.0 | 7 | 12 | First multi-flavour release; first inserted decimal phase (27.1); first milestone to close with a deliberate requirement-level deferral |

### Cumulative Quality

No automated test suite exists — this is a WoW addon, and correctness is established by static gates
(`grep`, `stylua --check`, `git ls-files --eol`, `check-toc.ps1`) plus human in-game verification
against a named build.

| Milestone | Static gates | In-game verification | Zero-dep |
|-----------|--------------|----------------------|----------|
| v0.2.4 | stylua + grep-gated dead-code sweep | per-phase human verify | yes |
| v0.3.0 | + `check-toc.ps1`, `.gitattributes`, `stylua.toml` | two ordered run-sheets, build `1.60.1.69913` | yes |

### Top Lessons (Verified Across Milestones)

1. **Read the consumer.** v0.2.4's `df48029` regression (Display reading `slot.spellID` instead of
   `slot.key`) and v0.3's `duration = nil` are the same failure: assuming a value's shape instead of
   checking the site that uses it.
2. **A record without its method is not evidence.** "Verified" with no build number, or with no mention
   that the test was a `/reload`, has repeatedly turned out to mean less than it claimed.
3. **Guards must be proven to fail.** Every guard this project added and then tested negatively had a
   bug in it.
