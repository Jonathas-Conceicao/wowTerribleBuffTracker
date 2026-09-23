---
phase: 42-cleanup
plan: 06
subsystem: documentation
tags: [wow-addon, hot-path-audit, duplication-verdicts, grep-gated-sweep, roadmap, closeout]

# Dependency graph
requires:
  - phase: 42-cleanup
    plan: 01
    provides: the .pkgmeta fix and the RacialProviderMixin deletion this audit records, plus the nine pre-v0.4.0 exports it inherits as an out-of-scope finding
  - phase: 42-cleanup
    plan: 02
    provides: the corrected comments the audit reads the code through
  - phase: 42-cleanup
    plan: 03
    provides: AddExclusiveCheck / WireExclusivePair — the add-panel duplication verdict
  - phase: 42-cleanup
    plan: 04
    provides: ClearCooldownStamps and _placeholderProc — the removed per-tick allocation
  - phase: 42-cleanup
    plan: 05
    provides: MergedSlotsFor / BuildActiveByKey / AppendMergedSlots / ApplyCachedIcon — the render-path helpers the audit measures
provides:
  - 42-HOT-PATH-AUDIT.md — 14 hot-path verdicts, 4 duplication verdicts, 7 out-of-scope findings, 3 evidenced sweeps
  - ROADMAP Phase 42 success criterion 1 annotated PARTIAL with the container-settings exception
  - Two todo files carrying the two findings the scope fence stopped
affects: [43-forever-end-to-end, 44-retail-validation, 45-docs-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Unused-local sweep without a linter: extract every `local` declaration (including each name
       in a multi-assignment), then count non-comment occurrences of that name in the same file.
       A count of 1 means declared and never read. Reported per file, never as a bare 'clean'."
    - "Dead-function sweep in two shapes, because a namespaced function and a file-local function
       need different greps and different corpora — the namespaced sweep must include *.xml and the
       TOC, or an XML-referenced handler reads as dead."
    - "A count-gated acceptance check for call sites must account for the definition line, which
       contains the same substring. Assert n+1 or anchor the pattern."

key-files:
  created:
    - .planning/phases/42-cleanup/42-HOT-PATH-AUDIT.md
    - .planning/todos/2026-09-22-getactivetimers-allocates-two-tables-and-a-closure-per-tick.md
    - .planning/todos/2026-09-22-current-schema-version-is-declared-and-never-read.md
  modified:
    - .planning/ROADMAP.md (one appended line — Phase 42 criterion 1 PARTIAL annotation)

key-decisions:
  - "ns:GetActiveTimers allocates two tables and a closure per tick and was NOT fixed. It dates from
     the initial commit (the result/sorted/closure shape from v0.2.4, 4cd64fc), so PROJECT.md's
     no-refactor decision covers it and D1's override reaches only the two render functions.
     Recorded as finding H14 and carried to a todo."
  - "CURRENT_SCHEMA_VERSION (BuffEngine.lua:82) is declared and never read — the single flag from an
     845-declaration sweep — and was NOT deleted. It predates Phase 31 (d086429, v0.2.0), and
     deleting it would make Core.lua:98's comment name an identifier that does not exist, which is
     the exact D4 defect class 42-02 removed. Carried to a todo with a wire-it-up fix sketch."
  - "The container-settings duplication is wider than 42-CONTEXT.md estimated: all five settings
     disagree across the three statements, not just padding, because AddSlider's fallback is
     structurally `or minVal`. This strengthens rather than weakens the leave-it verdict."
  - "ROADMAP Block C's checklist still lists Phase 42 as the Forever pass and Phase 43 as Cleanup,
     pre-swap. Recorded as an out-of-scope finding and surfaced for the user rather than edited —
     Task 2 is scoped to one appended annotation and forbidden from rewording."

patterns-established:
  - "Every failed plan-verification assertion in this phase was a wrong grep pattern, never a code
     defect — four plans, four instances, two variants (unescaped `.`, and a call-site count that
     forgot the definition line matches). Recorded as audit §2b with the two rules that prevent it."

requirements-completed: []

# Metrics
duration: 34min
completed: 2026-09-22
---

# Phase 42 Plan 06: Hot-Path Audit, Duplication Verdicts and Closeout Summary

**Fourteen hot-path findings and four duplication candidates now carry an explicit written verdict — one removed, the rest justified by name — alongside three evidenced sweeps (87 namespaced functions, 110 local functions, 845 local declarations) that turn ROADMAP criterion 3 from an assertion into a re-runnable check, and a PARTIAL annotation on criterion 1 for the one duplication the phase deliberately left standing.**

## Performance

- **Duration:** ~34 min
- **Completed:** 2026-09-22
- **Tasks:** 3, one atomic commit each
- **Source files modified:** **zero** (`git status --porcelain -- '*.lua' '*.xml' '*.toc' .pkgmeta` printed nothing after Task 1, and still does)

## Task Commits

1. **Task 1: the audit** — `8530586` (docs) — *hot-path audit and duplication verdicts*
2. **Task 2: ROADMAP** — `523e843` (docs) — *mark criterion 1 partial — container settings stay triplicated*
3. **Task 3: closeout** — `9bfb790` (chore) — *close the cleanup phase — stylua, diff check, deploy* (empty by design; see Deviations)

**Plan metadata:** this SUMMARY.md is intentionally left uncommitted — all six phase-42 summaries are committed together at phase close-out.

## The audit's headline verdicts

`.planning/phases/42-cleanup/42-HOT-PATH-AUDIT.md`, 410 lines, five sections.

| Category | Count | Breakdown |
|----------|------:|-----------|
| Hot-path findings | 14 | 1 **removed**, 13 **justified** (1 of those justified by the scope fence and carried) |
| Duplication candidates | 4 | 2 **unified**, 1 **does not exist**, 1 **real, deliberately not unified** |
| Out-of-scope findings | 7 | all recorded, none fixed; 2 carried to todos, 1 surfaced for a user decision |
| Evidenced sweeps | 3 | 87 namespaced functions → 0 dead; 110 local functions → 0 dead; 845 local declarations → 1 flag, which predates the fence |
| Criteria closed without code | 2 | D3 (both files verified gone); criterion 4's "read end to end" (four files, one line each) |

### The one removal

**H10 — the placeholder tooltip payload**, removed in `c2b89b2` (42-04). It was a fresh table per
*inactive* placeholder slot, per container, per tick, at 20 Hz, in combat, whenever "hide when
inactive" is off. Now one nil test plus three unconditional overwrites into a per-widget owned
table. `grep -v '^\s*--' Display.lua | grep -c 'proc = { spellID'` → **0**.

### The four D6 items, each confirmed against the shipped code

1. **`ns:PlaceMergeAura`** — the four stamp tables are still four separate tables
   (`MergeMode.lua:770`, compared at `:1005-1008`; the plan's spot-check grep returns **7** lines:
   one declaration, one forced-reset, four comparisons, one write). **Justified:** a packed key
   would allocate one string per merged entry per tick to discover nothing moved.
2. **`ApplyUserCooldown`** — **justified**, runs every tick by necessity because nothing fires an
   event when a TBT-owned cooldown ends. No API call and no allocation on the steady path. *One
   correction:* the body has **three** stamp tests, not the two its comment claims —
   `icon._lastStart ~= nil` joined the pair when the preview-sweep bug was fixed and the comment
   above the call was not updated with it. The claim the sentence is actually making is true either
   way.
3. **`ns:GetContainerCategory(def)`** — body confirmed still `(def and def.category) or "buffs"`
   (`Core.lua:109-111`). **Justified:** re-derived, never cached, so a `growthDirection` left behind
   by a container that changed category cannot produce a layout its dropdown never offered.
4. **The centred pre-pass** — confirmed gated on `if centered then` (`Display.lua:1463`), so a
   non-centred container pays nothing, and `SlotDraws` allocates nothing. *One correction:* D6 says
   it walks `#slots` "a second time"; it does so **only** when centred — the unconditional line above
   it is a single `#`, not a walk.

### The seven extras

`ns:UpdateDisplay`'s per-tick `wipe()` loop (justified — the lists are constructed once in
`ns.AllocateContainerRuntime` and only ever wiped); `RefreshCooldownSlotCounts` (justified — still
one integer compare and a return on the unchanged path, with a deliberate non-stamp when the DB is
not ready); 42-05's four helpers (three are once-per-container-per-tick with two call sites each;
`MergedSlotsFor` returns two values, not a table — see the correction below for the fourth);
`_placeholderProc` (allocates nothing from tick 2 onward, walked through in 42-04); the two mirror
tables (built event-driven only, indexed from the render path and never rebuilt in it); the two
`C_Timer.After(0)` deferrals (**justified and load-bearing — a structure to protect**, with the
`CallbackRegistryMixin` registration-order argument written out in full); and
`{ includeSpellIDs = includeSet }` in `SyncEntryContainers` (**justified — event-driven, not
per-tick**, stated explicitly so it is not mistaken for the allocation D2 removed; the `includeSet`
payload itself is already pooled and wiped in place).

### The duplication verdicts

| Candidate | Verdict |
|-----------|---------|
| Checkbox-pair idiom (`CDMTab.lua`) | **Unified** — 42-03. Appears **twice**, not D4's "at least three times"; the third instance died with `ADD-01`/`ADD-02` on 2026-09-22. |
| Pooled-widget reset blocks | **Unified** — 42-04 as `ClearCooldownStamps`. **Two** copies, not three; the placeholder copy's extra `_mergedExpiry` clear stayed out on purpose. |
| `MergeMode.lua`'s filter loop "written twice" | **Does not exist.** The `includeSet` fill appears once (`:856-866`), above the `AURA_UNITS` loop; both the create path (`:905-911`) and the re-filter path (`:877-880`) hand the engine the *same* table. `grep -c 'includeSet\[' MergeMode.lua` → **2**, both inside that one block. Recorded as a candidate that did not survive contact with the code, **not** as work skipped. |
| Container settings vs the Edit Mode popup | **Real, deliberately not unified** → ROADMAP criterion 1 marked PARTIAL. |

## The unused-local sweep, per file

ROADMAP criterion 3 names three categories; a dead-function sweep answers only one of them. There is
no Lua linter in this repo, so the variable sweep was built explicitly: extract every `local`
declaration (including each name in a multi-assignment `local a, b, c = …`), then count non-comment
occurrences of that name in the same file. **A count of 1 means declared and never read.** `_` is
excluded as the conventional throwaway.

| File | `local` declarations swept | Flagged |
|------|---------------------------:|--------:|
| `BuffEngine.lua` | 31 | **1** |
| `CDMTab.lua` | 241 | 0 |
| `Core.lua` | 64 | 0 |
| `Display.lua` | 168 | 0 |
| `EditModeFrames.lua` | 92 | 0 |
| `MergeMode.lua` | 137 | 0 |
| `Providers.lua` | 112 | 0 |
| **Total** | **845** | **1** |

**The one flag: `CURRENT_SCHEMA_VERSION` (`BuffEngine.lua:82`).** Declared `= 5` and never read —
every migration block writes its own literal instead.

**Not fixed, for two independent reasons.** It predates the fence (`d086429`, *v0.2.0 Config & Edit
Mode Rework*; Phase 36 only changed its value from 4 to 5), and deleting it would leave
`Core.lua:98`'s comment — *"…which is why `CURRENT_SCHEMA_VERSION` does not move for this change"* —
naming an identifier that does not exist, which is precisely the D4 comment-liar class plan 42-02
spent a whole plan removing. The correct fix is to wire it up
(`ns.db.schemaVersion = CURRENT_SCHEMA_VERSION` in the final block), which is a behaviour-adjacent
edit to the database migration path and untestable before a logout→login, i.e. Phase 44. Carried to
`.planning/todos/2026-09-22-current-schema-version-is-declared-and-never-read.md`.

**Because the only flag in an 845-declaration superset predates Phase 31, the set of unused locals
added *since* Phase 31 is empty.** Criterion 3's variable clause closes on evidence, not on the
absence of a check.

The dead-function sweep, run in two shapes, returned **zero** both times: 87 namespaced
`function ns.X` / `function ns:X` definitions checked against `*.lua`, `*.xml` and the TOC (so an
XML-referenced handler cannot read as dead), and 110 `local function` definitions covered by the
local sweep above.

## Deviations from Plan

No source file was touched, so none of Rules 1-4 fired on code. Four plan-vs-reality mismatches, all
recorded rather than worked around.

**1. [Finding outside the plan's list] `ns:GetActiveTimers` allocates two tables and a closure per tick**

- **Found during:** Task 1, extending past D6's list as the plan instructs.
- **Issue:** `BuffEngine.lua:194-222` is called once per tick from `ns:UpdateDisplay:1704` and
  allocates `result`, `sorted` and a fresh `table.sort` comparator closure, unconditionally, at
  20 Hz. It is the largest remaining per-tick allocation in the path and the plan did not list it.
  The contrast is sharp: `Display.lua:114-119` hoists `ByLayoutOrder` to module level *"so neither
  render function allocates a closure per tick"*, and the function feeding it does exactly that.
- **Not fixed, and the reason is the fence rather than the cost.** `git log -S` dates the function
  to the initial commit and its `result`/`sorted`/closure shape to `4cd64fc` (v0.2.4) — far earlier
  than Phase 31, so `PROJECT.md` protects it, and D1's override reaches only the two render
  functions. Fixing it blind before Phase 43, in the function feeding every timer TBT draws, is
  exactly what this plan's NO SOURCE CHANGES constraint exists to prevent.
- **Action taken:** recorded as audit finding **H14** with its own subsection (§1c), and carried to
  `.planning/todos/2026-09-22-getactivetimers-allocates-two-tables-and-a-closure-per-tick.md` with a
  solution sketch and the one thing to check first (the returned array would become shared).

**2. [Plan-vs-code, no code changed] The plan's Section 3 predicted the local sweep would "come back clean"; it came back 844/845**

- **Found during:** Task 1.
- **Issue:** The plan says "Expect it to come back clean". One declaration flagged —
  `CURRENT_SCHEMA_VERSION` — detailed above.
- **Resolution:** Recorded as FIXED/CLEAN-style evidence with the per-file counts the plan asks for,
  plus a verdict and a todo. The plan's underlying point survives intact: criterion 3's variable
  clause is closed by evidence, and the one flag is out of scope by date.

**3. [Plan defect — internal inconsistency] The plan specifies three task commits and then asserts two**

- **Issue:** `<success_criteria>` reads "Two atomic commits, one per task", while `<commits>` names
  **three** subjects (Tasks 1, 2 and 3) and then says "Both commits end with…". Three tasks, three
  subjects.
- **Resolution:** Three commits, one per task, using the subjects `<commits>` specifies — the
  orchestrator's instruction is "one atomic commit per task, using the subjects the plan specifies".
  Task 3 modifies nothing, so its commit is `--allow-empty` and its body carries the closeout record
  (stylua result, changed-file list, the silent-empty-diff trap, the deploy). A verification-only
  task with a mandated subject has no other way to be one atomic commit.

**4. [Out-of-scope finding, surfaced not fixed] ROADMAP Block C still lists the phases in pre-swap order**

- **Issue:** `.planning/ROADMAP.md:36-37` still reads *"Phase 42: Forever End-to-End Verification
  Pass"* and *"Phase 43: Cleanup"*, while the detailed sections at `:296` and `:313` carry the
  swapped order agreed 2026-09-22. Both bullets are unticked, so there is **no checkbox-crosstalk
  hazard today**, but a reader skimming Block C gets the wrong phase numbers.
- **Not fixed.** Task 2 is scoped to appending one PARTIAL annotation and explicitly forbidden from
  rewording; correcting the Block C narrative is a planning-document edit the user owns.
- **Action taken:** recorded as audit §3.6 and surfaced here for a decision.

---

**Total deviations:** 4 — one finding beyond the plan's list, one prediction the sweep disproved,
one plan self-contradiction, one out-of-scope documentation defect. **Zero behavioural.**

## Other things recorded that the plan asked for by name

- **The plan-verification defect pattern (audit §2b).** All four failed assertions in this phase were
  the assertion's fault, never the code's: 42-02's unescaped `.` matching
  `SetCooldownFromDurationObject`; 42-03's `UICheckButtonTemplate` threshold set as if the file held
  only four occurrences (it holds eight, and four-becomes-one moved it 8→5); 42-04's and 42-05's
  call-site counts forgetting that the definition line matches the same substring — with 42-05
  *internally inconsistent*, because its Task 2 assertion does count the definition. In every case
  the executor verified intent and changed nothing; no helper was renamed and no parameter reshaped
  to make a literal count pass. Two prevention rules are written into the audit.
- **`ApplyCachedIcon` vs T-42-12 (audit §1a).** 42-05's own `<constraints>` and threat entry assert
  "Helpers are called once per container per tick, never per widget", and its Task 2 then mandates a
  per-widget helper by name. The helper is correct — it replaces an inline block at the same point —
  but the constraint's wording no longer describes the file. Recorded so a future reader auditing
  against T-42-12 does not read it as a violation and inline the block back into three places.
- **The three unused locals 42-03 created and `d3ec95b` removed** (`buffsLabel`, `spellsLabel`,
  `iconsLabel`; only `barsLabel` is still read, by `ApplyCategory`). A cleanup phase created the
  exact defect its own criterion 3 forbids, and the sweep caught it — which is the argument for
  running the sweep at all rather than assuming a cleanup phase leaves nothing behind.
- **The `.proc` hazard was real, with proof (audit §3.7).** `Providers.lua:848-858` does
  `proc.stacks = proc.stacks - 1` on the live racial timer that `Display.lua:1221` hands straight to
  `bar.proc`. Reusing `bar.proc` as the scratch buffer — the obvious way to fix D2 without a new
  field — would have wiped a table `RacialProviderMixin` is still mutating, destroying a running
  Eureka! stack count. This is the concrete justification for the separate `_placeholderProc` field,
  recorded because the temptation to "save a field" will recur.
- **The abutting comment blocks are FIXED**, in `a28610e`, outside every plan's diff budget after
  42-02, 42-04 and 42-05 each correctly declined. Audit §3.7 records it as closed; it is **not**
  outstanding and should not be re-reported.

## Verification Performed

| Check | Result |
|-------|--------|
| `test -f 42-HOT-PATH-AUDIT.md` | exists, 410 lines |
| `grep -c 'Verdict\|verdict'` ≥ 3 | **11** |
| `grep -c 'PlaceMergeAura'` / `ApplyUserCooldown` / `GetContainerCategory` / `QueueMergeMirror` ≥ 1 | 2 / 2 / 1 / 3 |
| `git status --porcelain -- '*.lua' '*.xml' '*.toc' .pkgmeta` after Task 1 | **empty** — no source file touched |
| `grep -c 'placedAnchor\|placedX\|placedY\|placedScale' MergeMode.lua` | **7** (declaration, forced reset, four comparisons, one write) — four stamps still separate |
| `grep -c 'includeSet\[' MergeMode.lua` | **2**, both inside the single fill block at `:856-866` |
| `grep -c 'or minVal' EditModeFrames.lua` | **1** (`:406`) |
| `grep -c 'PARTIAL' .planning/ROADMAP.md` | **4** (Phase 40's two, plus the two halves of the new note) |
| ROADMAP criterion 1 wording unchanged | `git diff --stat` → **1 insertion, 0 deletions**; the criterion line is byte-identical at `:301` |
| `stylua .` then `stylua --check .`, repo root, no flags | both exit **0** — reformatted nothing |
| `CHANGELOG.md` across the whole phase | `git diff --name-only cb53015..HEAD \| grep -c CHANGELOG` → **0** |
| Line endings | `git ls-files --eol` → every `.lua`/`.xml`/`.toc` still `i/lf w/crlf attr/text eol=crlf`; `.pkgmeta` still `i/lf w/lf`. `grep -c $'\r'` **not** used — Git Bash text mode makes it lie (42-01's trap). |
| Silent-empty-diff check | Every file the phase edited shows a non-zero line count in `git diff --stat cb53015..HEAD`: `.pkgmeta` +3, `BuffEngine.lua` 7, `CDMTab.lua` 102, `Core.lua` 9, `Display.lua` 282, `MergeMode.lua` 24, `Providers.lua` 27. `EditModeFrames.lua` is correctly **absent** — no plan edited it. The one zero-line entry is the `git mv` of the D2 todo into `done/`, a pure rename. |
| `./scripts/install.bat` | exit **0** — 10 TOC-derived files as `v0.3.0-161-g523e843-dev` to **four** clients: `_retail_`, `_ptr_`, `_beta_`, `_classic_beta_`. Nothing pruned. |
| In-game exercise | **Not attempted, by design.** Phase 43's job. |
| Branch | still `milestone/v0.4.0-cooldown-tracking-cdm-view`; none created, renamed or switched |
| Destructive git | none. No `git clean`, `git stash`, `git reset --hard`, `git rm` or force-push at any point. |

## Issues Encountered

- **The unused-local sweep needed three attempts to be trustworthy.** The first script reported
  *every* declaration as having zero references — the `'\\b' + name + '\\b'` regex lost its
  backslashes passing through the heredoc, so it matched nothing and would have "proved" the whole
  codebase dead. Rewritten with lookaround character classes and no backslashes at all
  (`(?<![A-Za-z0-9_])name(?![A-Za-z0-9_])`), then sanity-checked against a known-live identifier
  before its output was believed. Recorded because a sweep that returns a uniformly alarming result
  is easier to disbelieve than one that returns a uniformly clean one, and the clean direction is
  the dangerous one.
- **`python` is absent** (Microsoft Store stub only), as 42-03 found. All scripting was done with
  `node`.
- **One pre-existing line-ending drift, out of scope and not fixed:** `tools/TBTProbe/TBTProbe.toc`
  is `w/lf` while `.gitattributes` pins `*.toc` to `eol=crlf`. It is untouched by this phase, is not
  in the phase diff, and `tools` is in `.pkgmeta`'s ignore list so it never ships. Noted only so it
  is not read as churn this phase introduced.

## Known Stubs

None.

## User Setup Required

None. The addon is deployed to all four client folders present.

## Next Phase Readiness

- **Phase 43 inherits a written record rather than a set of diffs.** `42-HOT-PATH-AUDIT.md` is the
  phase's only durable output and is written for two readers: whoever runs Phase 43, and whoever next
  opens the render path.
- **What Phase 43 should actually look at**, gathered from the five sibling summaries, since almost
  nothing in this phase is observable when working correctly:
  1. A **bar** container with mirrored CDM bars — the bar path is the less-tested of the two and took
     three of 42-05's nine call-site edits. Confirm it still shows, still orders under a custom
     `layoutOrder` with a mirror present, and never shows "Example Buff Name".
  2. **"Hide when inactive" off**, on one bar and one icon container: hover an inactive placeholder,
     then reorder or delete a tracker so a pooled widget moves slots, and hover again. A stale
     `spellID`/`label`/`key` is the one way 42-04's table reuse could show itself.
  3. A **racial (Eureka!) or lust timer** running: hover its bar/icon. That is the borrowed-reference
     path `_placeholderProc` exists to protect.
  4. A widget moved **from a cooldown slot to a buff slot**, then **into a merged slot** —
     `ClearCooldownStamps` and the asymmetric `_mergedExpiry` clear.
  5. The **New Container dialog's five states** (42-03's walkthrough): Cooldowns greys and disables
     Bars, Buffs brings it back, a checked box stays checked, and reopening after creating a
     Cooldowns container restores Buffs + Icons with Bars enabled.
  6. A **merged buff icon still gets its sweep**, and a **cooldowns-only container still shows**.
- **Two todos carried forward**, neither blocking: `ns:GetActiveTimers`'s per-tick allocations and
  `CURRENT_SCHEMA_VERSION`. Both are out of scope by the fence and both have solution sketches.
- **One decision waiting on the user:** ROADMAP Block C's pre-swap phase labels (Deviation 4).
- **Phase 44 should watch the first tag push** to confirm the release zip no longer carries
  `.planning` — 42-01's fix is not observable locally, only in CI.

---
*Phase: 42-cleanup*
*Completed: 2026-09-22*

## Self-Check: PASSED

- `.planning/phases/42-cleanup/42-HOT-PATH-AUDIT.md` — FOUND
- `.planning/todos/2026-09-22-getactivetimers-allocates-two-tables-and-a-closure-per-tick.md` — FOUND
- `.planning/todos/2026-09-22-current-schema-version-is-declared-and-never-read.md` — FOUND
- `.planning/ROADMAP.md` — FOUND, PARTIAL annotation present, criterion text unchanged
- Commit `8530586` — FOUND
- Commit `523e843` — FOUND
- Commit `9bfb790` — FOUND
- `stylua --check .` — exits 0
- Working tree clean apart from the six uncommitted phase-42 summaries, by design
