# Phase 30: Cleanup - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning
**Mode:** Auto-generated; the refactor-scope decision below came from the user directly.

<domain>
## Phase Boundary

The standing end-of-milestone cleanup CLAUDE.md mandates: dead code removed, duplication introduced by v0.3 unified, hot paths unaffected, release scripts reviewed, docs corrected to match what v0.3 actually became.

Requirements owned: none — this is a standing workflow phase, not tied to a v0.3 REQ-ID.

**Not this phase:** any new behaviour, any feature, re-enabling upload tokens, refactoring code v0.3 did not introduce.

</domain>

<the_rule_conflict_resolved>
## The CLAUDE.md vs PROJECT.md contradiction — settled

Two of the project's own rules collided here:

- `CLAUDE.md` GSD Workflow: *"Always run a cleanup phase at the end of new milestones: clean up unused variables, definitions, **unify repeated behavior into shared functions**, review hot paths…"*
- `PROJECT.md` Key Decisions: *"**No refactors during cleanup phases** — Keeps release-prep phases narrow and predictable; prevents last-mile scope creep."*

It never bit before because earlier cleanups had little duplication to unify. Phase 30 touches `install.bat` and two near-identical `.pkgmeta-*` files, which is real duplication.

**User decision, 2026-09-18 — "Unify only v0.3's own new duplication":**

- **D-01:** CLAUDE.md's unify mandate applies to **code this milestone introduced**. PROJECT.md's no-refactor rule protects **pre-existing code**. Read that way the two rules are complementary, not contradictory.
- **D-02:** In scope to unify: the two `.pkgmeta-*` files, `install.bat`'s per-client/per-flavor structure, and anything else v0.3 created. Out of scope: every line that predates v0.3.
- **D-03:** **Amend both documents** so this stops recurring. `CLAUDE.md`'s rule gains the scoping clause; `PROJECT.md`'s Key Decision gains the same. The user explicitly asked for this as part of the decision — it is not optional tidying.

</the_rule_conflict_resolved>

<decisions>
## Implementation Decisions

### Dead code and orphans — all already identified, none speculative

- **D-04:** `TRINKET_FALLBACK_ORDER` (`Providers.lua`) is **declared but unreferenced** after Phase 27. Phase 27's D-10 locked it in place at the time and handed it here explicitly. Remove it. Note the asymmetry: `POT_FALLBACK_ORDER` **is** still used by the pot bag-scan `ipairs` loop and must stay.
- **D-05:** The in-code comment Phase 27 left marking `TRINKET_FALLBACK_ORDER` as dead weight goes with it.
- **D-06:** Grep-gate every deletion — the established pattern from v0.2.4's Phase 24: confirm each removed symbol reaches zero references across all Lua files before committing.

### Line endings — the root cause, not just the symptom

- **D-07:** `EditModeFrames.lua` is `w/lf` on disk while every other Lua file is `w/crlf`. Fix with `~/.cargo/bin/stylua.exe --line-endings Windows EditModeFrames.lua`. Verified 2026-09-18: its `stylua --check` diff marks every line from line 1, the signature of a pure line-ending difference — the file's formatting is fine, so this carries no formatting risk.
- **D-08:** **Add a `stylua.toml` with `line_endings = "Windows"`.** This is the actual root-cause fix. Today a bare `stylua <file>` silently reflows a file to LF and — because `core.autocrlf=true` with no `.gitattributes` means the index is `i/lf` — produces a **literally empty `git diff`**. Two files already got hit this way. Every plan has had to remember the flag, and a forgotten flag leaves no trace. A config file makes the bare invocation correct.
- **D-09:** With `stylua.toml` in place, **amend CLAUDE.md's "Always run `stylua`" rule** to note the config now handles line endings, so the bare form is safe. The rule as written is what caused the drift.
- **D-10:** Do **not** add a `.gitattributes`. It would rewrite index state for every Lua file and deserves its own deliberate, isolated commit — not a cleanup phase.
- **D-11:** Assert `git ls-files --eol *.lua` reports `w/crlf` for all six files at exit. That is the only reliable on-disk check; a git diff cannot see this class of change.

### Docs corrected to match reality

- **D-12:** `PROJECT.md`'s **"Parity only: v0.3 adds no user-facing features"** constraint is now **false**. TOOL-01 (spell/aura ID tooltip) and META-01 (meta-tile hiding) are both new user-facing behaviour, added mid-milestone with explicit user approval. Amend it to state what v0.3 actually delivered rather than leaving a constraint the code violates.
- **D-13:** Move v0.3's delivered work into `PROJECT.md`'s Validated list, following the established per-milestone format.
- **D-14:** Record the milestone's substantive findings in `PROJECT.md` Context / Key Decisions, specifically: Forever does not ship retail spell data; `GetScaledCursorPositionForFrame` is absent from Forever's engine; SavedVariables do persist on build `1.60.1.69913` contrary to the earlier third-party report.

### Hot-path review

- **D-15:** Audit what v0.3 actually touched, not the whole addon: `ns:ShowBuffTooltip`'s new `C_Spell.GetSpellInfo` probe and `RelatedID` pcalls; `UnresolvedDisplayInfo`; `ns:IsSuggestedKeyResolvable`'s memoisation; the ghost frame's `OnUpdate` after the cursor change.
- **D-16:** The `OnUpdate` is the only genuine per-frame path among those, and only during an active drag. Confirm the replacement allocates nothing per frame — `GetCursorPosition()` returns two numbers, and `topLevel:GetScale()` is a cheap accessor.
- **D-17:** Tooltip handlers fire on hover, not per frame. The `pcall`s in `RelatedID` are acceptable there; say so explicitly rather than leaving a reader to wonder.
- **D-18:** Confirm `ns:IsSuggestedKeyResolvable` genuinely memoises — the Suggested section redraws on every CDM open and after every drag, add, move and delete, so a non-cached catalog walk would be a real regression.

### Release script review

- **D-19:** Read `scripts/release.bat` and `.github/workflows/release.yml` end to end against the new two-flavor flow. **Do not execute either.** Confirm the `check-toc.ps1` invocation is correctly ordered before tagging and that its failure aborts.
- **D-20:** Confirm `check-toc.ps1`'s third assertion now actually fires, rather than skipping, once Phase 29 has created the `.pkgmeta-<flavor>` files.

### Todos

- **D-21:** Two pending todos are in scope. `2026-09-18-editmodeframes-lua-is-lf-and-stylua-dirty.md` is tagged `resolves_phase: 30` and is closed by D-07/D-08. `2026-09-18-install-bat-does-not-prune-stale-files.md` is a **judgment call** — see Deferred Questions.

</decisions>

<canonical_refs>
## Canonical References

### Phase scope
- `.planning/ROADMAP.md` — Phase 30's five success criteria
- `CLAUDE.md` — the GSD Workflow cleanup mandate and the `stylua` rule, both amended by this phase
- `.planning/PROJECT.md` — Key Decisions (the no-refactor rule), Constraints (the now-false parity-only claim)

### Work to clean up
- `Providers.lua` — `TRINKET_FALLBACK_ORDER` (D-04) and Phase 27's marker comment
- `EditModeFrames.lua` — line endings only, no formatting change (D-07)
- `.pkgmeta-mainline` / `.pkgmeta-camelot`, `scripts/install.bat` — v0.3's own duplication (D-02)
- `.planning/todos/pending/` — both open todos

### Evidence for the findings being recorded
- `.planning/testing/FOREVER-TEST-PASS.md` — the completed Forever pass, build `1.60.1.69913`, and the SavedVariables observation
- `.planning/phases/27.1-forever-testing-enablers/` — the two mid-session defect fixes
- Commits `9e32f92` (engine-global removal), `9fde1eb` (lust tooltip), `c4dce25` (base/override lines)

</canonical_refs>

<code_context>
## Existing Code Insights

### Established Patterns
- **Grep-gated deletion** — v0.2.4's Phase 24 set the precedent: every removed symbol verified at zero references across all Lua files, before/after counts reproduced in the SUMMARY as evidence.
- **Comment scrub policy** — remove migration-history comments (`Phase N will remove this`), preserve current-state invariants (PITFALL-N markers, `D-NN` decision IDs, `Combat-gated`).
- **stylua as the only parse gate** — no `lua`, `luac` or `luacheck` on this machine, so `stylua` doubles as the syntax check.

### Integration Points
- Six Lua files total: `Core.lua`, `BuffEngine.lua`, `Providers.lua`, `EditModeFrames.lua`, `Display.lua`, `CDMTab.lua`.
- `scripts/check-toc.ps1` is invoked by `release.bat`; its assertion 3 becomes live once Phase 29 lands.

</code_context>

<specifics>
## Specific Ideas

- The user asked for the rule conflict to be **resolved in the documents**, not just worked around in this phase. D-03 is therefore a deliverable, not housekeeping.
- The `stylua.toml` (D-08) is the highest-leverage item here: it converts a rule that has silently caused drift twice into one that is correct by default.

</specifics>

<deferred>
## Deferred Ideas

- **`.gitattributes` for `*.lua text eol=crlf`** — the honest git-layer fix, but it rewrites index state for every Lua file. Deserves its own commit, not a cleanup phase (D-10).
- **Re-enabling CurseForge / Wago tokens** — `FTOOL-01`.
- **A dedicated `_forever_` install path** — `FTOOL-02`, if Forever gets its own product folder at GA.

</deferred>

<deferred_questions>
## Deferred Questions for Human Review

1. **Should `install.bat` prune stale files?** The pending todo documents that it copies but never deletes, which is why the retail folder still holds a pre-rename `TerribleBuffTracker.toc`, a `ConfigUI.lua` removed back in v0.2.0, and a stray PNG. The stale TOC case is not cosmetic — it nearly invalidated v0.3's own retail verification. But pruning is **new behaviour**, and `INST-01…04` say nothing about it, so adding it here would be exactly the scope creep PROJECT.md's no-refactor rule guards against. Recommend leaving the todo open for a v0.3.1 tooling pass. Flagging rather than deciding.
2. **Two retail verification items remain provisional** and are unaffected by this phase: the stale TOC was still present during the general retail test, and META-01's retail behaviour was not explicitly confirmed. Neither blocks cleanup, but neither should be recorded as verified at milestone close.

</deferred_questions>

---

*Phase: 30-Cleanup*
*Context gathered: 2026-09-18*
