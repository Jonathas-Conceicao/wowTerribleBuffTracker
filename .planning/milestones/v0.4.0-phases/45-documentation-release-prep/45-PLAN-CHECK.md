# Phase 45 Plan Check — Documentation & Release Prep

**Verified:** 2026-09-23
**Plans checked:** 45-01-PLAN.md, 45-02-PLAN.md
**Verdict:** NEEDS REVISION (1 blocker, 6 warnings)

---

## Dimension 1/6: Requirement Coverage & Verification Derivation

| Requirement | Plan | Delivered by | Verified by acceptance_criteria? |
|---|---|---|---|
| DOC-02 (one download, both interface numbers) | 45-01 Task 1 | Yes | Yes -- 120100/16001 grep checks |
| DOC-03 (Forever SavedVariables caveat, pasteable) | 45-01 Task 2 (portability) + Task 3 (content) | Yes | Yes -- forever beta / retail is unaffected + no-repo-relative-link check |
| DOC-04 (CHANGELOG appended, never rewritten) | 45-02 Task 1 | Yes | Yes -- title/line-3/numstat checks |
| DOC-05a (Trinket and Pot meta-trackers are kept) | 45-01 Task 1 (action text only) | No | No acceptance criterion checks for Trinket or Damage Potion/Pot anywhere in either plan |
| DOC-05b (no unverified CDM-natively claims) | 45-01 Task 1 + 45-02 Task 1 | Yes | Yes -- banned-phrase greps in both files |

BLOCKER found -- see below.

## Dimension 2: Task Completeness

All 5 tasks (3 in 45-01, 2 in 45-02) have files, action, verify, done. No vague actions -- every task enumerates concrete content requirements. No missing elements.

## Dimension 3: Dependency Correctness

45-02 declares depends_on 45-01, wave 2. 45-01 is wave 1, depends_on []. No cycle, no forward reference, wave numbers consistent with dependency depth. Valid, but see Warning 2 below on whether the dependency is mechanically enforced.

## Dimension 4: Acceptance Criteria Quality

Scanned every acceptance criterion in both plans. None use subjective language ("reads well", "appropriately", "consistent with") -- all are grep/awk/git command assertions with numeric or exact-string expectations. This is a genuine strength of both plans.

Spot-checked that greps/awks match the current file structure:
- TerribleBuffTracker.toc line 1 is exactly "## Interface: 120100, 16001" -- matches plan's literal-number assertions.
- README.md currently has "## AI Usage", "## Showcase", "## Features", "## Usage", "## Lust / Heroism Tracking", "## Known Issues and Limitations", "## License" -- all headings the plans' awk ranges reference exist exactly once, confirmed via grep -c on each heading.
- CHANGELOG.md is confirmed 109 lines, line 1 "# Changelog", line 3 "## v0.3.0 -- WoW Forever Support" -- exactly matching 45-02 Task 1's pre-flight numeric assertions, verified directly against the working tree.
- git ls-files --eol confirmed "i/lf w/crlf" for CHANGELOG.md, README.md, and PROJECT.md -- matching both plans' EOL pre/post-conditions.
- git status --porcelain is currently clean, matching 45-02 Task 1's pre-flight requirement.

One quantitative risk found (Warning 4, D-03 bullet budget) and one line-count risk found (Warning 6, PROJECT.md's fewer-than-15-changed-lines budget against a hand-wrapped paragraph).

## Dimension 5: Scope Sanity

45-01: 3 tasks, 1 file. 45-02: 2 tasks, 2 files. Both well within the 2-3 task / 5-8 file target. No split needed.

## Dimension 7: Context Compliance (CONTEXT.md)

- D-01/D-02 (CHANGELOG override, append-only): fully and rigorously implemented -- see the dedicated CHANGELOG risk assessment below.
- D-06 (Showcase/AI Usage/License untouched): implemented but with a verification gap -- see Warning 3.
- D-08 (no store-copy file, README is the single source): fully honored -- neither plan creates a store-description file; both explicitly forbid it in prose.
- D-09 (.pkgmeta untouched): honored, no plan touches it.
- D-10/D-11 (exactly 3 public known issues, 3 specific items excluded): mostly honored -- see Warning 5 for an incomplete exclusion check.
- D-12 (stale racial claim corrected): honored in both README (Task 1) and PROJECT.md (45-02 Task 2), with the historical Key Decisions cell correctly preserved rather than rewritten.
- Deferred Ideas (fresh screenshots, repo-root hygiene, complete racial catalog): none appear in either plan. Correctly excluded.
- Discretion area (DOC-05 comparative claims -- safe reading: no comparative claims): correctly and consistently applied across both plans with matching banned-phrase lists.

## Dimension 7b: Scope Reduction Detection

Grepped both plans for scope-reduction language (v1, simplified, static for now, hardcoded, placeholder, stub, too complex, etc.) -- no matches. Neither plan silently narrows a CONTEXT.md decision behind soft language.

## Dimension 9: Cross-Plan Data Contracts

CHANGELOG's Known Issues bullets (45-02) are pre-drafted in the plan text to match D-10, and the plan instructs the entry to agree with README's finished wording (45-01) rather than invent parallel wording. No transformation conflict exists (neither plan strips/sanitizes shared data), but there is no automated cross-file check that the two actually agree post-execution -- see Warning 2.

## Dimension 10: CLAUDE.md Compliance

- The CHANGELOG rule (append-only, stop-and-ask, no wholesale rewrite) is followed to the letter -- arguably more rigorously than CLAUDE.md itself requires, given D-01's one-entry exception is scoped tightly and repeatedly cross-referenced.
- Neither plan touches a .lua file; 45-02 explicitly notes stylua is not needed and must not be run, consistent with CLAUDE.md's stylua rule only applying to Lua changes.
- No conflicts found.

## Dimension 11/8/7c/12

Skipped -- no RESEARCH.md or PATTERNS.md exists for Phase 45.

---

## The CHANGELOG Task -- Dedicated Risk Assessment (per review instructions)

Checked against the four specific questions:

1. Numeric, mechanical proof of zero pre-existing-line changes? Yes -- git diff --numstat on CHANGELOG.md must show second field (deletions) 0, doubled by a raw-diff grep also asserting 0. Both are exact commands with a numeric pass/fail, not a subjective read.
2. Handles modified-line-as-delete-plus-add? Yes -- the acceptance criterion explicitly states this reasoning inline: a modified line would appear as a delete plus an add, so a zero here is proof that no pre-existing line changed in any way.
3. Stop-and-ask instruction, not "fix it"? Yes -- Step 1's pre-flight is explicit: if any of the four checks differ, STOP, do not edit, do not "fix", do not reconcile against the plan; report the difference to the user and wait.
4. Wholesale-rewrite forbidden in action text? Yes -- "do not use a script that rewrites the file wholesale, edit in place."

Pre-flight numeric assumptions were independently verified against the actual working tree and are currently accurate (wc -l is 109, line 1/3 content matches, git status is clean, EOL is i/lf w/crlf). This task is well-built and should not by itself destroy CHANGELOG.md content.

---

## Line-Ending Trap Check (per review instructions)

Searched both plans for grep/awk-style CR line-ending assertions. None found. Both plans correctly use git ls-files --eol for every EOL assertion, and 45-02 even calls out why explicitly: checked with git rather than grep, because grep and awk silently strip CR in this repo. No trap present.

---

## Issues

### BLOCKER

**[requirement_coverage] DOC-05's "Trinket and Damage Potion meta-trackers are kept" is unverified**
- Plan: 45-01, Task 1
- DOC-05's first half -- which is also literally ROADMAP Phase 45 success criterion 4's first clause -- has a must_haves truth ("README.md states the Trinket and Damage Potion meta-trackers are kept...") and an explicit action-text instruction (Task 1: "Meta-trackers: Lust / Heroism, Trinket and Damage Potion. DOC-05 requires the README to state these are KEPT") but ZERO acceptance_criteria enforcing it. Task 1's acceptance_criteria checks 8 other required strings (120100, 16001, Essential Cooldowns, Utility Cooldowns, Merge Mode, Options > AddOns, Berserking, Blood Fury) plus 4 banned-phrase absences, but never checks for "Trinket" or "Damage Potion"/"Pot". Under autonomous execution with a long "at minimum" bullet list the user has asked to be "easy to prune," an omission here has no automated gate to catch it.
- Fix: add to Task 1's acceptance_criteria: grep -ci 'Trinket' README.md is at least 1, and grep -ci 'Damage Potion' README.md is at least 1 (or a broader Pot check if wording varies), ideally paired with a nearby "kept"/"remain" check to enforce the framing DOC-05 requires, not just the noun's presence.

### WARNINGS

**1. [cross_plan_data_contracts] 45-02's dependency on 45-01 is advisory, not mechanically enforced**
- Plan: 45-02, Task 1
- 45-02 depends_on 45-01 solely to reuse README's finished wording for the CHANGELOG's Known Issues trio ("must agree with it, not invent parallel wording"). The three CHANGELOG Known Issues bullets are pre-drafted directly in the 45-02 plan text (matching D-10), and no acceptance criterion cross-checks the two files' actual final wording against each other. The dependency is reasonable for sequencing but nothing catches divergence if README's Task 3 rewording ends up differing from the CHANGELOG's pre-drafted text.
- Fix: either accept the dependency as advisory (document the risk), or add a check comparing key phrases between README's Known Issues section and CHANGELOG's Known Issues block.

**2. [task_completeness] D-06 protection relies on indirect proxy checks**
- Plan: 45-01, Task 1
- D-06 (Showcase, AI Usage, License NOT touched) is verified only by absence of the substrings "Assets/", "WTFPL", and "Claude AI" in the diff, rather than a direct line-range comparison proving those three sections are byte-identical. A change elsewhere within those sections that doesn't touch those exact substrings (e.g. rewording a sentence in AI Usage that never says "Claude AI") would pass undetected, silently violating a locked decision.
- Fix: add a direct section-extraction diff (e.g. diff the AI-Usage-through-License range of HEAD's README.md against the working tree's same range) proving byte-identical content, matching the rigor the CHANGELOG task applies via git diff --numstat.

**3. [scope_sanity] D-03 bullet-count language is looser than the acceptance gate**
- Plan: 45-02, Task 1
- Action text says "Roughly 10-15 short bullets in total across the three -- aim for 12-15" while acceptance_criteria enforces a strict "between 12 and 15 inclusive." The looser "10-15" framing risks the executor landing at 10 or 11, failing the gate on first attempt.
- Fix: tighten the action text's stated range to "aim for 12-15" only, removing the "Roughly 10-15" framing.

**4. [context_compliance] D-11 exclusion check is incomplete**
- Plan: 45-01 Task 3, 45-02 Task 1
- D-11 lists three items to keep out of public copy: hostile-target merged debuffs, a potion cooldown not resolving inside a key, and an equipped item's cooldown going unreadable under restriction. Both plans check for absence of the first and third ("hostile target", "equipped item") but neither checks for the second (potion/key language). Risk is low given the strict 3-bullet cap, but the exclusion check set is incomplete relative to D-11's full list.
- Fix: add a grep checking for potion/key phrasing equals 0 in both README Task 3 and CHANGELOG Task 1.

**5. [task_completeness] PROJECT.md's under-15-changed-lines budget is tight against a hand-wrapped paragraph**
- Plan: 45-02, Task 2
- The stale claim spans a hand-wrapped paragraph at source lines 40-46 (7 lines), a second wrapped bullet at lines 73-75 (3 lines), and one long table row at line 214. Manually wordsmithing early lines in a hand-wrapped paragraph commonly cascades reflow into later lines even when their meaning doesn't change, which could push the diff over budget on the first attempt.
- Fix: either instruct the executor explicitly to preserve existing line breaks and edit only the lines containing the stale phrases, or relax the threshold slightly to absorb reasonable reflow.

**6. [verification_derivation] 45-02's DOC-05-CHANGELOG-half claim is unbacked**
- Plan: 45-02
- The frontmatter/success_criteria claims this plan "closes... DOC-05's CHANGELOG half" (naming Trinket/Damage Potion as unchanged "where relevant"), but no task action or acceptance criterion in 45-02 actually adds that content to CHANGELOG.md. Not a functional blocker since DOC-05 is independently satisfiable via README (once the Blocker above is fixed), but the plan's own stated claim is inaccurate/unbacked.
- Fix: either remove the DOC-05-CHANGELOG-half claim from the success criteria, or add a concrete task action/acceptance criterion backing it.

---

## Recommendation

One blocker: 45-01 Task 1 must gain acceptance criteria verifying "Trinket" and "Damage Potion" actually appear in the rewritten README, since this is both a stated must_haves truth and half of ROADMAP Phase 45's fourth success criterion, and currently has no automated gate. This is a small, mechanical fix (two grep lines) -- not a redesign -- but per the goal-backward standard, an unverified required truth is a blocker, not a warning.

The six warnings do not block execution but should be triaged before or during execution: the D-06 proxy-check weakness (Warning 2) and the PROJECT.md line-budget risk (Warning 5) are the two most likely to cause friction (a failed acceptance gate requiring a retry) rather than a silently wrong result.

The CHANGELOG task itself -- the highest-risk operation in the phase -- is well-built: numeric zero-deletion proof, explicit stop-and-ask pre-flight, and an explicit wholesale-rewrite prohibition are all present and were independently verified against the real working tree (109 lines, line 3 is v0.3.0, clean git status, correct EOL). No destruction risk identified there.
