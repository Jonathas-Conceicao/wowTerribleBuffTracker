---
phase: 42-cleanup
plan: 02
subsystem: documentation
tags: [wow-addon, lua, comments, secret-values, merge-mode, grep-gated-sweep]

# Dependency graph
requires:
  - phase: 40-cdm-merge-mode
    provides: the engine-driven aura path whose header comment described the design it replaced
  - phase: 41-racial-meta-tracker
    provides: the 2026-09-22 play-testing pass that made three of these comments false
provides:
  - Aura-path header in MergeMode.lua that matches the shipped AddAuraSlot / container-per-entry shape
  - Relay comments in Display.lua that scope the no-sweep impossibility to relaying, not to sweeps
  - A recorded FIXED/CLEAN table over the whole D4 liar list, re-runnable by grep
affects: [42-03, 42-04, 42-05, 42-06, 43-forever-end-to-end]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One authoritative statement per load-bearing fact: the aura-path header now POINTS at the
       block above auraContainers instead of restating the container shape. A second statement of
       the same fact is what drifted in the first place."
    - "Comment liars are found by grep, not by reading: every ns.Foo / ns:Foo named in a comment is
       checked for a non-comment definition, and a count of zero is a liar by construction."

key-files:
  created: []
  modified:
    - MergeMode.lua (Phase 40 aura-path banner above AURA_UNITS)
    - Display.lua (RelayMergedBar header, RelayMergedIconTime header)
    - Providers.lua (ns.previewActive bullet, meta-provider forward reference, dispatcher DESIGN NOTE, branch-3 provenance)
    - Core.lua (ns:AttachContainerRuntime nil-guard rationale)
    - BuffEngine.lua (two nil-guard rationales in the add-tracker path)
    - CDMTab.lua (delete-zone "visual only" note)

key-decisions:
  - "The secret-value API argument in both Display.lua relay blocks was kept VERBATIM. Only the
     conclusion drawn from it changed: it rules out relaying a sweep off the CDM's Cooldown, not
     sweeps as such. Weakening the API reasoning would have destroyed exactly what D4 exists to
     protect."
  - "Every liar was corrected, never deleted. All six carried a real reason; only the state of the
     world they were attached to had moved on."
  - "Providers.lua:101's 'branch 3' provenance was reworded rather than left, because a reader
     following it would find a BuffEngine cast handler with zero branches. It is now explicitly
     framed as history Phase 17 removed."

patterns-established:
  - "Comment-only plans are verified by diffing with `git diff -U0 | grep -E '^[+-]' | grep -vE
     '^(\\+\\+\\+|---)' | grep -vE '^[+-][[:space:]]*--'` — an empty result proves zero executable
     lines changed, which reading a diff by eye cannot."

requirements-completed: []

# Metrics
duration: 18min
completed: 2026-09-22
---

# Phase 42 Plan 02: Comment Accuracy Sweep Summary

**Six comments that told the next reader a limit exists which the code has already removed — two of them about merged buff sweeps, one about the whole aura-path design — corrected in place, with a grep-gated sweep recording FIXED or CLEAN for every entry on the D4 liar list. Zero executable lines changed.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-09-22T08:13:00-03:00 (approx)
- **Completed:** 2026-09-22T08:31:00-03:00
- **Tasks:** 3
- **Files modified:** 6 (`MergeMode.lua`, `Display.lua`, `Providers.lua`, `Core.lua`, `BuffEngine.lua`, `CDMTab.lua`)

## Accomplishments

- **Task 1** — the Phase 40 banner above `AURA_UNITS` in `MergeMode.lua` described the *first* design of the engine-driven sweep, not the shipped one. It claimed `AddAuraGroup` was used "precisely because a GROUP lays its own frames out", and that adding a group was what banned untrusted layout scripts on the container. The code calls `AddAuraSlot`, adds no group at all, and keeps `DisableUntrustedLayoutScriptsTemplate` *because* no group is added — the exact inverse. Its closing "one container per unit" sentence was false in the same way; the header now points at the authoritative block above `auraContainers` rather than restating the shape a second time.
- **Task 2** — both relay headers in `Display.lua` stated at length that a merged buff icon cannot have a cooldown sweep, and recorded that as settled so nobody would retry it. The secret-value API argument behind the claim is correct and was kept verbatim; the conclusion was wrong. It rules out *relaying* a sweep off the CDM's Cooldown, not sweeps as such. A merged buff icon already gets a real one two ways, and `RelayMergedIconTime` is the fallback for when neither is available, not the ceiling.
- **Task 3** — three D4 entries confirmed CLEAN with zero-count greps and deliberately left alone; the sweep then widened past D4's list and found six more liars across four files, each corrected rather than deleted.

## Task Commits

1. **Task 1: aura-path header in `MergeMode.lua`** — `f51e1ec` (docs) — *the aura path adds a slot per container, not a group*
2. **Task 2: both relay headers in `Display.lua`** — `9e64db3` (docs) — *a merged buff icon does get a sweep, two ways*
3. **Task 3: grep-gated sweep across `Providers.lua`, `Core.lua`, `BuffEngine.lua`, `CDMTab.lua`** — `aa963e9` (docs) — *grep-gated sweep for comments naming things that are gone*

**Plan metadata:** not committed — this SUMMARY.md is intentionally left uncommitted, following Phase 41's precedent (summaries are committed together at phase close-out).

## The D4 sweep: FIXED / CLEAN table

This table is the phase's evidence for ROADMAP success criterion 3. Every CLEAN row carries the grep that proves it, so the next reader can re-run the sweep rather than trust this pass.

### D4's named entries

| # | D4 entry | Verdict | Evidence / fix |
|---|----------|---------|----------------|
| 1 | "a merged buff icon cannot have a sweep" (`RelayMergedBar`, `RelayMergedIconTime`) | **FIXED** | `Display.lua:956-969` and `Display.lua:1013-1025`. `grep -ci 'still has no sweep\|never a sweep\|sweep is not possible' Display.lua` → **0**. API argument preserved: `grep -c 'SecretArguments' Display.lua` → **6** (was 6). |
| 2 | `ns:SetMergeAuraLayout` referenced in `Display.lua`'s placed-merged-aura branch | **CLEAN** | `grep -rn 'SetMergeAuraLayout' *.lua *.xml` → no output, exit 1. Already removed before this plan; no edit made. |
| 3 | `/tbt aura` and `/tbt sweep` | **CLEAN** | `grep -rn 'tbt aura\|tbt sweep' *.lua` → no output, exit 1. Separately, `grep -rnoE '/tbt [a-z]+' *.lua *.xml` returns only two hits, both the phrase "/tbt command" (`CDMTab.lua:1989`, `CDMTab.lua:2061`), and both are accurate — `Core.lua:834`'s handler falls through to `ns:SelectTBTTab`. No edit made. |
| 4 | "slot-per-entry in one container per unit" | **FIXED** | `MergeMode.lua:667-671`. `grep -v '^\s*--' MergeMode.lua \| grep -c 'container per unit'` → **0**. `grep -c 'CONTAINER PER MERGED ENTRY PER UNIT' MergeMode.lua` → **1** (the authoritative block, untouched). |
| 5 | `AddAuraGroup` bullets in the aura-path header | **FIXED** | `MergeMode.lua:660-670`. `grep -c 'AddAuraGroup' MergeMode.lua` → **0** (file-wide, code and comment). `grep -c 'AddAuraSlot' MergeMode.lua` → **3** (header mention + `:891` capability check + `:900` call). |
| 6 | `ADD-01` / `ADD-02` control descriptions | **CLEAN** | `CDMTab.lua:948` already reads "Type (ADD-01) and Container (ADD-02) are both GONE as controls, by user decision 2026-09-22". Describes the reversal correctly. No edit made. |
| 7 | `CD-02` "follows cooldown reduction live" rationale | **CLEAN** | `Display.lua:828` ("This reverses CD-02, by user decision on 2026-09-22…") and `Core.lua:409` ("user decision, 2026-09-22, reversing CD-02") both record the reversal explicitly. No edit made. |

### The widened sweep (D4 says not to trust its own list)

**Identifier sweep.** Every `ns.Foo` / `ns:Foo` named inside a comment across all seven `.lua` files was extracted (81 distinct identifiers) and checked for at least one occurrence on a **non-comment** line in `*.lua *.xml`. A count of zero means the identifier does not exist and the comment naming it is a liar by construction.

| Identifier | Before | After | Verdict |
|------------|--------|-------|---------|
| `ns.previewActive` | 2 total, **0 in code** | gone from comments | **FIXED** — `Providers.lua:522` |
| other 80 identifiers | ≥1 in code each | unchanged | **CLEAN** |

Re-run with:

```sh
grep -rhoE '^[[:space:]]*--.*' *.lua | grep -oE '\bns[:.][A-Za-z_][A-Za-z0-9_]*' | sort -u |
while read -r id; do name="${id:3}";
  def=$(cat *.lua *.xml | grep -vE '^[[:space:]]*--' | grep -cE "ns[.:]${name}\b");
  [ "$def" -eq 0 ] && echo "LIAR $id"; done
```

Post-plan result: **no output** — zero liars.

**Stale phase-lifecycle prose.** Grepped for future-tense and "does not exist yet" comment prose across all files, then checked each hit against the code.

| # | Location | Claim | Verdict | What was done |
|---|----------|-------|---------|---------------|
| 8 | `Providers.lua:522` | "NO `ns.previewActive` check … Intentional prep for Phase 21 / LIFE-03" | **FIXED** | The flag has not existed since Phase 21 made preview additive. Rewritten to say there is no preview gate at all, and why one is not needed: `ns:StartAllPreviewTimers` writes to its own `ns.previewTimers` and skips any key a real proc owns. |
| 9 | `Providers.lua:62` | meta keys "will be handled by meta providers in Phase 18-19" | **FIXED** | Those providers are defined further down the same file. Rewritten to present tense. |
| 10 | `Providers.lua:983-988` | DESIGN NOTE: UserSpellProvider "will be" the only writer "once Plan 17-02 removes BuffEngine's branch 3" | **FIXED** | `ns:OnSpellCastSucceeded` (`BuffEngine.lua:182-187`) has had **zero branches** since Phase 17 — it does nothing but call the dispatcher. Rewritten to record the migration as finished and the single-writer invariant as current fact. |
| 11 | `Providers.lua:101` | "Preserve section=\"hidden\" guard from BuffEngine OnSpellCastSucceeded branch 3" | **FIXED** | Accurate as history but a reader following it finds no branch 3. Reworded to frame it explicitly as provenance Phase 17 removed. |
| 12 | `CDMTab.lua:727` | delete zone "(visual only in Phase 4)" | **FIXED** | It is live: `SectionHitTest` (`CDMTab.lua:311`) gives it top priority and `EndDrag` (`CDMTab.lua:537-543`) calls `ns:RemoveTrackedBuff` on a drop. Rewritten to say so. |
| 13 | `Core.lua:249-252` | hooks "do not exist until Plans 02-04 land … this plan lands and works standalone in Wave 1" | **FIXED** | Those plans landed; the nil-guards are still correct but for a different reason. Rewritten as load-order insurance (Core loads first), which is the reason that survives. |
| 14 | `BuffEngine.lua:290-291` and `296-297` | "Plan 01 is a wave-1 sibling, so this plan lands and works standalone" | **FIXED** | Same shape as #13; both rewritten as load-order insurance, the second now deferring to the first instead of restating it. |
| 15 | `BuffEngine.lua:146` | "a container whose settings do not exist yet" | **CLEAN** | Not lifecycle prose — a statement about runtime state during a schema migration, and true. No edit. |
| 16 | `CDMTab.lua:554`, `Providers.lua:697`, `Providers.lua:724` | "Not yet tracked" / "not yet supported" / "not yet resolved" | **CLEAN** | All three describe runtime state, not an unlanded phase. No edit. |
| 17 | ~20 further `Plan NN` / `Phase NN` cross-references | **CLEAN** | All are backward-looking attributions of where something lives (e.g. "Plan 01's `ns:CreateUserContainer`"), not claims that something is absent. Left alone deliberately. |

**Phase 37 seams named in `STATE.md`.** Both confirmed CLEAN with no edit needed: `UserSpellProviderMixin:OnTrigger` (`Providers.lua:70`) carries no lifecycle comment, and no comment anywhere describes `ns:StartAllPreviewTimers` as skipping `trackerType == "cooldown"` — `grep -rn 'trackerType' *.lua` returns four comment hits (`BuffEngine.lua:79`, `:226`, `Core.lua:21`, `:96`), none of which mentions preview.

**Total: 8 FIXED, 9 CLEAN.**

## Files Created/Modified

- `MergeMode.lua` — Phase 40 aura-path banner above `AURA_UNITS`: two false bullets replaced (the real reason TBT may not touch an aura frame plus the container/`AddAuraSlot` anchoring rule; the real role of `DisableUntrustedLayoutScriptsTemplate`), and the "one container per unit" sentence replaced with a pointer to the authoritative block above `auraContainers` plus the two-units-per-entry fact, which is stated nowhere else.
- `Display.lua` — `RelayMergedBar` header: API argument kept verbatim, conclusion rescoped to relaying, both working sweep routes named. `RelayMergedIconTime` header: reframed as the fallback rather than the ceiling, pointing at the `SetCooldown` branch in `RenderIconContainer`.
- `Providers.lua` — four corrections (#8, #9, #10, #11 above).
- `Core.lua` — `ns:AttachContainerRuntime` nil-guard rationale (#13).
- `BuffEngine.lua` — two nil-guard rationales in the add-tracker path (#14).
- `CDMTab.lua` — delete-zone note (#12).

## Decisions Made

- Kept the secret-value API reasoning in both `Display.lua` blocks **word for word**, and changed only the conclusion. D4 exists to protect exactly that kind of hard-won constraint, and shortening it while "fixing" the surrounding paragraph was the obvious way to lose it.
- Corrected rather than deleted in all eight cases. Each liar carried a real reason — a load-order invariant, a single-writer invariant, a design constraint — attached to a world state that had moved on.
- Left ~20 `Plan NN` cross-references alone. They attribute where code lives rather than claiming it is absent, so they are provenance, not liars. Sweeping them would have been scope creep against a clean grep.
- Did **not** add a blank line between the `RelayMergedIconTime` header block and the `MatchMergedTimeFont` header it runs straight into (`Display.lua:1026-1027`). The two blocks abut with no separator, which reads oddly, but a blank line is not a comment line and would have broken this plan's zero-executable-lines guarantee. Noted for Phase 42's remaining plans.

## Deviations from Plan

**1. [Plan-vs-code mismatch, no code changed] Task 2's `icon.cooldown:SetCooldown` count assertion is wrong in the plan**

- **Found during:** Task 2 verification.
- **Issue:** The plan's automated check is `test "$(grep -c 'icon.cooldown:SetCooldown' Display.lua)" -eq 1`. The actual count is **4** — the unescaped `.` matches `SetCooldownFromDurationObject` at `Display.lua:747`, and there are genuinely three `icon.cooldown:SetCooldown(` call sites (`:871` user-cooldown, `:1460` timer branch, `:1540` merged-aura branch). The plan's stated intent is "proves the `SetCooldown` branch the new comments point at still exists and was not edited", which a count of 1 could never have expressed.
- **Fix:** None to the code. The assertion was evaluated as intended: the count was **4 before and 4 after**, and the non-comment diff for `Display.lua` is empty, which proves the branch was not edited. The plan's literal `-eq 1` is a planning error, not a code defect.
- **Files modified:** none.
- **Verification:** `grep -c 'icon.cooldown:SetCooldown' Display.lua` → 4 at both HEAD~2 and HEAD.

**2. [Scope, within Task 3's brief] The widened sweep found six liars outside D4's list**

- **Found during:** Task 3.
- **Issue:** D4 warns its list is not exhaustive and Task 3 explicitly instructs the sweep to widen past it. It found one dead identifier (`ns.previewActive`) and five pieces of stale phase-lifecycle prose across `Providers.lua`, `Core.lua`, `BuffEngine.lua` and `CDMTab.lua` — files the plan's `files_modified` frontmatter does not list, though the task's own `<files>` element does.
- **Fix:** All six corrected, comment-only, in Task 3's single commit. This is the task working as specified, recorded here because the plan frontmatter understates the file set.
- **Files modified:** `Providers.lua`, `Core.lua`, `BuffEngine.lua`, `CDMTab.lua`.
- **Committed in:** `aa963e9`.

---

**Total deviations:** 2 (one plan assertion that cannot be satisfied as literally written; one expected widening that touched more files than the frontmatter listed)
**Impact on plan:** None on behaviour. Zero executable lines changed across all three commits.

## Verification

| Check | Result |
|-------|--------|
| `stylua .` then `stylua --check .` from repo root, no flags | exits 0 |
| Zero executable lines changed (`git diff -U0` filtered to non-comment `+`/`-` lines) | **empty** for every commit and for the plan as a whole |
| Line endings | `git ls-files --eol *.lua *.xml` → all eight files `i/lf w/crlf attr/text eol=crlf`, unchanged. (`grep -c $'\r'` was **not** used — Git Bash text mode makes it lie; see the 42-01 trap.) |
| `CHANGELOG.md` untouched | `git diff --name-only` across all three commits lists only the six `.lua` files |
| D5 #1 — one container per merged entry per unit | `grep -c 'CONTAINER PER MERGED ENTRY PER UNIT' MergeMode.lua` → **1** |
| D5 #2 — `ns:GridSlotPlacement` single source | `grep -c 'function ns:GridSlotPlacement' Display.lua` → **1** |
| D5 #3 — `entry.cdmShown` | `grep -rc 'cdmShown' *.lua` → `Display.lua:2`, `MergeMode.lua:1`, all others 0 — **unchanged** |
| Branch | still `milestone/v0.4.0-cooldown-tracking-cdm-view`; no branch created, renamed or switched |

## Issues Encountered

None. No `git clean`, `git stash`, `git reset` or any other destructive git operation was run.

## Next Phase Readiness

- Nothing in this plan is exercisable in game — it changed no executable line, so Phase 43's Forever end-to-end pass has exactly the same binary to test as before it ran.
- The remaining 42-* plans inherit a corrected map: the aura-path header now describes `AddAuraSlot` and container-level anchoring, so a reader working on `MergeMode.lua` will not re-derive the group-based design.
- `Display.lua`'s relay comments now point at the `SetCooldown` branch in `RenderIconContainer` rather than restating its detail, which matters for whichever plan unifies `RenderBarContainer` / `RenderIconContainer` (D1) — that branch is now the single documented place the merged-sweep rule lives.
- One cosmetic seam deliberately left: `Display.lua:1026-1027`, where two comment blocks abut with no blank line. Fixing it costs one non-comment line and belongs to a plan that is allowed to change them.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*
