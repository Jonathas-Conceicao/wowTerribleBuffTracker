---
phase: 83-reminder-review-doc
verified: 2026-11-09T12:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 83: Reminder Review Doc Verification Report

**Phase Goal:** A human can review every built-in reminder, Forever and retail, in one document kept in step with the code
**Verified:** 2026-11-09
**Status:** passed
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `docs/REMINDERS.md` lists every built-in reminder, Forever and retail, existing and new, with class, spell, ID, duration, group and alternatives, client and verified status, each with a Wowhead link (`/forever/` for Forever, the retail path for retail) | VERIFIED | `## Forever` (8 class tables, 28 rows plus the `both` row 1459) and `## Retail` (7 class tables, 10 rows plus 1459). All 39 `MetaReminderRow` calls in Providers.lua have a table line. Link prefixes in the whole doc: 144 `wowhead.com/forever/spell=`, 3 `wowhead.com/forever/item=` (the three scrolls), 15 `wowhead.com/spell=`. All the plain links are in the Retail section, and the Forever section has no plain link. No `classic`, `/tbc/`, `/wotlk/` or `/cata/` path anywhere. Durations match the `minutes` argument for every row (0 shows as `permanent`: Blood Pact, Shadowform, both Devotion rows, Aspect). Verified column: `yes` exactly for 1459, 7301, 11767, 20217, 25291, 25290 and every retail row, the rows whose trailing comment has no "unverified". Every v0.5.6 row reads `unverified`. |
| 2 | The doc lists every candidate left out, each with a reason | VERIFIED | `## Not included` has 23 rows, each with a non-empty Reason cell. It covers every **Exclude** verdict in research §6: Molten Armor, Fel Armor, the wards, Shadow Ward, Barkskin and Nature's Grasp, Elune's Grace and Feedback, the group buffs as their own rows, Soul Link, the detection and tracking skills (the MREM-17 drop), Unending Breath, imbues and poisons (backlog 999.29), totems, Earth Shield, Fear Ward, Touch of Weakness, Omen of Clarity, forms, stances and seals. It adds Sanctity Aura, Blessing of Sanctuary and Viper/Falcon. Salvation, Blessing of Light, Revoker, 1038, 19979, 25895 and 25890 appear nowhere in the doc (MREM-06). They are only in the internal note at Providers.lua:1104-1106. |
| 3 | Every ID in the doc matches a row or alternative in `Providers.lua` and the reverse, zero mismatches; the reminder table's comment points at the doc | VERIFIED | **Independent diff (not via the script):** I stripped the comments from Providers.lua lines 1067-1339 and collected the Forever set: non-retail row IDs, `auraID`, `useItems` item IDs and the IDs inside the `if ns.CLIENT_IS_FOREVER` block, 132 IDs. The retail set is the retail and both row IDs, `auraID` and `MetaReminderGroup(465, 317920, 32223)`, 15 IDs. I diffed each against the links in the matching doc section (Not included excluded): both match exactly (`F-MATCH`, `R-MATCH`). The script agrees (`REMINDERS-DOC CHECK PASS (132 Forever IDs, 15 retail IDs, 39 rows)`). The pointer comment is at Providers.lua:1122-1125 and names both `docs/REMINDERS.md` and `node scripts/reminders-doc-check.js`. |
| 4 | The packaged zip contains no `docs/` (`.pkgmeta` ignores it) | VERIFIED | `.pkgmeta` `ignore:` has `- docs`. `docs/` is not in the TOC load list, so `install.ps1` (which takes its file set from the TOC) does not deploy it either. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `docs/REMINDERS.md` | Review list, DOC-06 | VERIFIED | 194 lines. Tables have a consistent column count (every 5-column table line has NF=7, every Not included line NF=5), and no stray pipe inside a cell. |
| `scripts/reminders-doc-check.js` | Doc-to-code check with `--selftest`, DOC-07 | VERIFIED | 886 lines. The check exits 0. `--selftest` passes 27 cases, including one-sided mismatches, a wrong duration, a wrong verified cell, the wrong class and the wrong client. |
| `Providers.lua` | Pointer comment only | VERIFIED | In `git diff c86be51 HEAD -- Providers.lua` the only added lines are comments. No code line changed, so the scope rule holds. |
| `.pkgmeta` | `docs` ignored | VERIFIED | Present |
| `CLAUDE.md` | Two Architecture lines | VERIFIED | Commit 87a1bd5 adds exactly 2 lines and removes none. |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| reminders-doc-check.js | Providers.lua row and group calls | comment-stripped lexing, Forever block | WIRED: the counts (39 rows, 19 groups) match a manual count |
| reminders-doc-check.js | docs/REMINDERS.md | link collection per section | WIRED: the 132/15 counts equal the independent extraction |
| Providers.lua header | docs/REMINDERS.md and the check | column-0 comment | WIRED |

### Spot-check against research (FOREVER-REMINDERS.md), independent of the script

I spot-checked 28 IDs. Each appears in the research with the same role as in the doc: 10220, 22783 (armor group §3), 1302303, 1302285, 1296202 (familiar tiers), 277493, 277483 and 275069 (scroll items §11.1, in the same Cat, Frog, Rat order as `useItems`), 11735, 696, 10432, 408510, 10952, 15473, 19312, 10293, 25296, 13163, 20190, 18788 with aura 18789, 10958, 27683, 10170, 10173, 25780, 19746 and 19900. For the spot rows, durations match research §5: Inner Fire 10, Demon Armor/Skin 30, the shields 10, Demonic Sacrifice 120, Shadowform 0.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Doc and code agree | `node scripts/reminders-doc-check.js` | `REMINDERS-DOC CHECK PASS`, exit 0 | PASS |
| The check catches mismatches | `node scripts/reminders-doc-check.js --selftest` | `REMINDERS-DOC SELFTEST PASS (27 cases)`, exit 0 | PASS |
| Independent ID set diff | grep/awk extraction plus `diff` | Forever 132 = 132, retail 15 = 15, no diff | PASS |

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| DOC-06 | 83-01 | SATISFIED | Truths 1, 2 and 4 |
| DOC-07 | 83-01 | SATISFIED | Truth 3. Phase 84 SC4 re-runs the check. |

No requirements were orphaned: REQUIREMENTS.md maps only DOC-06 and DOC-07 to Phase 83.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| docs/REMINDERS.md, scripts/reminders-doc-check.js | — | Working tree is LF (`w/lf`); most of the repo's `.md`/`.js` files are `w/crlf` under `text=auto` | Info | Index is `i/lf` either way, so nothing is committed differently. A cosmetic working-tree difference that Phase 84 can normalise if wanted. |

There are no TBD, FIXME, XXX or TODO markers in the phase files.

### Human Verification Required

None for this phase. Checking the rows in game and changing a row's `unverified` to `yes` is Phase 85's testing pass (VER-15). This phase verified that the review document exists and agrees with the code.

### Gaps Summary

None. The doc covers all 39 rows and every group member and alternative on both clients, and every link uses the right Wowhead path. The excluded candidates have reasons, the retired Forever blessings are absent, the pointer comment is in place and `docs/` is not packaged.

---

_Verified: 2026-11-09_
_Verifier: Claude (gsd-verifier)_
