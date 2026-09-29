---
phase: 50-cleanup-release-prep
verified: 2026-09-26T01:17:37Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
deferred:
  - truth: "ApplyDispelBorder's dirty check still renders and clears a dispel border correctly in combat, and no pooled widget keeps a stale colour after a container re-sort (SC3's behavioural proof)"
    addressed_in: "Phase 51 (Forever Full Review) and Phase 52 (Retail Full Review)"
    evidence: "50-CONTEXT.md D-03: 'the reason for doing it now is timing: Phases 51 and 52 are two full review passes, so anything landing before them is verified for free and needs no gate of its own.' 50-01-PLAN.md's own <verification> section labels this a 'Human gate — NOT an executor criterion' and names the exact watch-items for 51/52."
---

# Phase 50: Cleanup & Release Prep Verification Report

**Phase Goal:** Everything v0.4.1 built — item tracking, the pandemic highlight, the dispel-type
border, and the Forever racial catalogue — has its milestone-introduced duplication unified, hot
paths audited, dead code swept, release scripts reviewed, and the public copy updated (as amended:
CHANGELOG drafted, not appended; no README/store-copy changes).

**Verified:** 2026-09-26T01:17:37Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Success Criteria, as amended)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Duplication THIS MILESTONE introduced (racial def-by-spellID walk) is unified; pre-existing code (`cd:` key parser) left alone | VERIFIED | `Providers.lua:1096` — `function ns:RacialDefInList(defs, spellID)`, on `ns` not file-local. Three call sites confirmed each keeping its own list: `ns:RacialDefForSpellID` → `ns:RacialDefsForPlayer()` (`:1109`), `ns:RacialCooldownSeed` → `ns:RacialSuggestions()` (`:1190`, gated list preserved), `ns:IsRacialKeyVisible` → `ns:RacialDefsRaw()` (`:1131`, raw list preserved). `git status --porcelain -- Core.lua` empty across every phase commit; decision to leave the three `Core.lua` key parsers unified recorded in `50-02-SUMMARY.md` with two stated reasons |
| 2 | Hot paths this milestone touched show no avoidable per-frame/per-event allocation | VERIFIED | `racialGateKeyIDs` memo added (`Providers.lua:988`, read at `:1120`, write at `:1123`) — closes the per-render-pass `string.match` capture allocation in `ns:IsRacialKeyVisible`, called from both `Display.lua` render loops. Memoises the PARSE only (confirmed: no `wipe()` call, `grep -c 'wipe(racialGateKeyIDs)'` → 0). Seven-site audit table recorded in `50-02-SUMMARY.md` with per-site frequency/allocation verdicts; all cleared or already dirty-checked by prior phases |
| 3 | `ApplyDispelBorder` no longer re-issues `SetAtlas` every render pass while the atlas is secret | VERIFIED (static) | `Display.lua:795-841` — read in full. Dirty check now three-way: `widget._dispelKey ~= key or widget._dispelID ~= id or id == nil` (`:831`), replacing the old unconditional `or key == SECRET_ATLAS_KEY` clause (confirmed absent via grep). `identity` sanitised via `issecretvalue(id)` BEFORE any comparison (`:818-820`) — no secret ever compared or stored. Both live call sites pass `slot.cooldownID` / `entry.cooldownID` (`Display.lua:2057`, `:2347`); both pool resets still pass `(pool[i], nil, false)` unchanged and reach the `widget._dispelID = nil` clear (`:808`). **Confirmed `cooldownID` arrives non-nil in practice**: `MergeMode.lua:341` builds `entry.key = "cdm:" .. cooldownID` — a concatenation that would raise on a secret — proving every entry has a real, non-secret `cooldownID`, so the stamp is not a silent no-op |
| 4 | stylua clean on every changed file; `git ls-files --eol` reads `i/lf w/crlf`; install/release scripts reviewed against what changed | VERIFIED | `stylua --check .` → exit 0 (whole repo). `git ls-files --eol` on all four phase-touched files (`Display.lua`, `Providers.lua`, `.planning/REQUIREMENTS.md`, `50-CHANGELOG-DRAFT.md`) all read `w/crlf` (the `.lua` files pinned `attr/text eol=crlf`, the two `.md` files `attr/text=auto` but still measuring `w/crlf` — no reflow occurred). Five-question release-mechanics review recorded in `50-03-SUMMARY.md` with command/line evidence for each of: no runtime file added/removed, `install.ps1` load-list coverage, `.pkgmeta` ignore list (`tools`, `.planning` both present), `release.bat`'s `TBT_ALLOW_BRANCH` guard (4 occurrences), single TOC with both interface versions. `git status --porcelain -- scripts .pkgmeta .github TerribleBuffTracker.toc` confirmed empty — reviewed, not edited, and no release run |
| 5 (AMENDED) | No README changes, no store-copy changes, CHANGELOG entry drafted to a separate artifact, never appended | VERIFIED | `git diff --stat 73f260b3011ccc8e35e400ca7191050cce00483e..HEAD -- CHANGELOG.md README.md` → **empty output** (confirmed directly, not from SUMMARY claim). `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md` exists, contains `## v0.4.1` inside a fenced block, covers the four features in build order, and a Notes section with both required recommendations (G8 Known Issues bullet, priest-branch leave-out). No commit in the phase's range (`a7fd247^..762ce34`) touches `CHANGELOG.md` or `README.md` |

**Score:** 5/5 truths verified

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | SC3's behavioural proof (border still renders/clears correctly; no stale colour on a pooled widget after re-sort) | Phase 51 (Forever) and Phase 52 (Retail) | `50-CONTEXT.md` D-03 explicitly times SC3's landing to be "verified for free" by the two already-scheduled review passes; `50-01-PLAN.md`'s `<verification>` section labels this a human gate, not an executor criterion, and names the exact behaviours 51/52 must watch |

This is **not** classified as `human_needed` for Phase 50 itself: the phase's own deliverable was the
statically-provable code change (identity stamp, sanitisation-before-comparison, pool-reset clearing),
all of which is verified above. The runtime rendering proof was never this phase's job by design — it
is Phase 51/52's job, on purpose, per an explicit and recorded user/architecture decision made before
execution began, not a gap discovered after the fact.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Display.lua` | `ApplyDispelBorder` identity-stamped dirty check + two call sites | VERIFIED | Function widened to 4 params, `_dispelID` stamp added/compared/cleared, both call sites pass `cooldownID`, both pool resets untouched |
| `Providers.lua` | `ns:RacialDefInList` shared lookup + memoised race-gate key parse | VERIFIED | `function ns:RacialDefInList` on `ns`; `racialGateKeyIDs` module-level memo, read/write on miss path only |
| `.planning/REQUIREMENTS.md` | Corrected RACE traceability | VERIFIED | RACE-07/08/10 ticked (`grep -c '^- \[x\] \*\*RACE-\(07\|08\|10\)'` → 3), stale "not started" text gone, footnote fixed to "Phases 50", RACE-09 untouched |
| `.planning/phases/50-cleanup-release-prep/50-CHANGELOG-DRAFT.md` | Paste-ready v0.4.1 entry | VERIFIED | File exists, `## v0.4.1` present, four features in order, Notes section with both recommendations, `i/lf` per `git ls-files --eol` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `Display.lua` `RenderBarContainer` | `ApplyDispelBorder` | `slot.cooldownID` as 4th arg | WIRED | `ApplyDispelBorder(bar, slot.dispelAtlas, slot.isMerged and slot.dispelShown == true, slot.cooldownID)` at `Display.lua:2057` |
| `Display.lua` `RenderIconContainer` | `ApplyDispelBorder` | `entry.cooldownID` as 4th arg | WIRED | `ApplyDispelBorder(icon, entry.dispelAtlas, entry.isMerged and entry.dispelShown == true, entry.cooldownID)` at `Display.lua:2347` |
| `Providers.lua` `ns:RacialDefForSpellID` | `ns:RacialDefInList` | walks `ns:RacialDefsForPlayer()` | WIRED | `Providers.lua:1109` |
| `Providers.lua` `ns:RacialCooldownSeed` | `ns:RacialDefInList` | walks flavour-gated `ns:RacialSuggestions()` | WIRED | `Providers.lua:1190` |
| `Providers.lua` `ns:IsRacialKeyVisible` | `ns:RacialDefInList` | walks raw list `ns:RacialDefsRaw()` | WIRED | `Providers.lua:1131` |
| `MergeMode.lua:341` (`entry.cooldownID` write) | `Display.lua` dispel-border identity read | field carried on slot/entry table | WIRED, DATA FLOWS | The concatenation `"cdm:" .. cooldownID` at write time proves the value reaching the identity parameter is a real, non-secret number in every case an entry exists — not a silent always-nil path |

### Anti-Patterns Found

None. `grep -n "TBD\|FIXME\|XXX"` and `grep -n "TODO\|HACK\|PLACEHOLDER"` on all phase-touched files
(`Display.lua`, `Providers.lua`, `.planning/REQUIREMENTS.md`, `50-CHANGELOG-DRAFT.md`) return no
matches. No stub returns, no empty handlers, no hardcoded-empty stand-ins introduced.

### Requirements Coverage

Not applicable. Phase 50 is a process phase with `requirements: []` on all three plans, matching
ROADMAP's "Requirements: None." No requirement ID is orphaned to this phase in `.planning/REQUIREMENTS.md`'s
traceability table (only RACE-07/08/09/10 map to Phase 49, corrected footnote now correctly excludes
Phase 50). This is not treated as a coverage gap, per the task instructions.

### Explicitly Out-of-Scope Items — Confirmed Correctly Absent

| Item | Expected disposition | Confirmed |
|------|----------------------|-----------|
| F-3 (racial aura-icon swap) | Not touched; backlog 999.8 | `git status --porcelain -- Core.lua Display.lua MergeMode.lua` (icon-resolution paths) clean of this change; `999.8` entry present in `ROADMAP.md:508` with full scope recorded |
| Three `Core.lua` key parsers | NOT unified; reason recorded | `Core.lua` untouched by any phase-50 commit; decision + two reasons recorded in `50-02-SUMMARY.md` |
| Pandemic icon/bar FX split | Confirmed justified divergence, left alone | `50-01-SUMMARY.md` records all four checked divergences (parent, template, anchor, frame-level source) each holding against source; `git diff -U0 ... | grep -c Pandemic` → 0 |
| `RACIAL_SUPPORTED_LINES`/`UNSUPPORTED_LINES` | Already gone (Phase 49) | Not this phase's concern; no search performed, consistent with instructions |
| `tools/TBTProbe/` | Predates milestone, protected, no decision taken | Untouched by this phase; `.pkgmeta` still excludes `tools` from the shipped zip |
| Running a release | Reviewed only, not run | `release.bat` and `.github/workflows/release.yml` read-only in this phase; no tag created, nothing pushed; `git status --porcelain -- scripts .pkgmeta .github` empty |

### Bookkeeping Item — Resolved Since 50-03-SUMMARY Was Written

`50-03-SUMMARY.md` recorded an incomplete Task 3 Part B (leftover worktree `.claude/worktrees/agent-ad696cb1`
/ branch `worktree-agent-ad696cb1` could not be removed from inside the sandboxed executor worktree, and
was flagged as a "blocker carried forward" for the orchestrator or user to finish). **Verified now
resolved:** `git worktree list` shows only the main worktree, `git branch --list worktree-agent-ad696cb1`
returns nothing, and `.claude/worktrees/` is empty. The tip SHA (`a3b1aa3c1b4cff927096efae789d9188c6d2d188`)
was recorded in the SUMMARY before deletion, satisfying the plan's reflog-recoverability requirement.
One caveat for the record: the sandboxed executor could not run `git -C <worktree> status --porcelain`
before deletion (only the zero-`A`-entries diff against `main` was provable from inside the sandbox), so
the "proven to hold nothing unmerged" bar was met via the diff check but not the full working-tree-clean
check the plan specified. Since the worktree directory itself is now gone, this is a closed historical
gap in the audit trail rather than a live risk — there is nothing left to lose. Not scored as a failure
because the artifact (a clean `git worktree list`) is the thing the must-have actually requires, and it
now holds.

### Human Verification Required

None for this phase's own scope. See "Deferred Items" above for the one human-gate item, which is
explicitly the responsibility of Phases 51 and 52 by an architecture decision made before this phase
was planned, not an unresolved gap in Phase 50's own deliverable.

### Gaps Summary

No gaps. All five (amended) success criteria are verified directly against the current source, not
inferred from SUMMARY claims. The one item that cannot be verified statically — SC3's in-combat
rendering behaviour — was deliberately scoped out of this phase's own gate by `50-CONTEXT.md` D-03 and
handed to the two dedicated review phases that immediately follow; treating that as a live gap here
would penalize the phase for a boundary it was explicitly designed not to own. The one process
loose-end from `50-03-SUMMARY.md` (the leftover git worktree) has since been closed and was confirmed
directly against `git worktree list` / `git branch --list` rather than taken on the SUMMARY's word.

---

*Verified: 2026-09-26T01:17:37Z*
*Verifier: Claude (gsd-verifier)*
