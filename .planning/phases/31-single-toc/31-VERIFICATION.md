---
status: passed
closed_at_milestone: v0.4.0 (2026-09-23)
closure_evidence:
  - ".planning/testing/43-FOREVER-E2E-PASS.md"
  - ".planning/testing/44-RETAIL-PASS.md"
closure_note: >-
  Closed in bulk at milestone close, not item by item. The human_verification list below was
  written when this phase's code landed and records what still needed a live client at that
  moment. Those observations were carried out in Phase 43 (Forever beta, build 1.60.1.69913,
  continuous play-testing 2026-09-21 to 22) and Phase 44 (retail, Mythic+ and a raid encounter,
  2026-09-23). The user signed both off as a whole -- "everything on Forever is tested and
  acceptable" and "no lua errors so far" -- rather than ticking each row, so read the list below
  as covered by those two passes collectively, not as individually attested. It is kept intact
  because it is the best record of what this phase could not prove statically.
phase: 31
verified: 2026-09-20
must_haves_verified: 3
must_haves_total: 4
---

# Phase 31 Verification — Single TOC

## Automated checks

| # | Criterion | Result |
|---|---|---|
| 1 | `git ls-files` shows one TOC declaring `## Interface: 120100, 16001`, no `AllowLoadGameType`; `_Camelot.toc` and `check-toc.ps1` gone | ✅ PASS |
| 3 | No forked Lua or XML source file anywhere in the tree | ✅ PASS — no Lua/XML file was touched this phase |
| 4 | Nothing outside git history and `CHANGELOG.md` references `_Camelot`, `check-toc` or `pkgmeta-` | ✅ PASS — the one remaining `camelot` hit is `CLAUDE.md`'s reference to Blizzard's own `Blizzard_CooldownViewer.toc`, which is accurate and unrelated |

Evidence for #1:

```
$ git ls-files | grep -i 'toc$\|pkgmeta\|check-toc'
.pkgmeta
TerribleBuffTracker_Mainline.toc
tools/TBTProbe/TBTProbe.toc
```

## Human verification required

| # | Criterion | How to check |
|---|---|---|
| 2 | The Forever AddOns folder holds exactly one TOC, and TBT loads and works there | Launch the **Forever beta** client (`_classic_beta_`). Confirm TerribleBuffTracker is listed and enabled at character select, then on a live character run `/tbt` — the CDM opens on the TBT tab. Check a tracked buff renders a bar or icon, and that Edit Mode still moves the containers. |

The deployed folder was already verified from disk — `_classic_beta_` holds exactly one TOC, reading
`## Interface: 120100, 16001` — so only the in-game load remains.

**If it does not load:** `git revert` this phase's commit and re-run `scripts/install.bat`. That
restores shipped v0.3.0 behaviour exactly; nothing else in the milestone depends on the migration yet.

## Notes

No in-game metadata read is required. `_classic_beta_` held only `TerribleBuffTracker_Camelot.toc`
before this phase, which settles from disk which TOC v0.3's Forever pass ran against — the question
backlog item 999.3 raised. The answer is the Camelot TOC, so that pass stands.
