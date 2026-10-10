---
phase: 65-cleanup
verified: 2026-10-01T00:00:00Z
status: human_needed
score: 4/4 roadmap criteria verified in code
overrides_applied: 0
gaps: []
human_verification:
  - test: "Edit a buff and a reminder; open the Advanced tab (Aura ID field) and, on a reminder, the Cast spell ID field"
    expected: "Both fields prefill with and follow the Spell ID until typed in; preview icon, name and spell tooltip as before; the Aura ID field keeps its secrecy badge and scope note; emptying Cast spell ID previews 'No click action' and saves false; an ID past 32 bits shows 'Aura ID is too large' / 'Cast spell ID is too large'; equal-to-Spell-ID saves nil"
    why_human: "No Lua interpreter here. The D-01 factory (BuildFollowSpellIDField, CDMTab.lua:1589) is read-verified, but behaviour preservation is only provable in game (Phase 66)"
  - test: "Hover a reminder click overlay, then move to another frame that owns GameTooltip, and leave the overlay"
    expected: "The overlay hides GameTooltip only when it owns it; another frame's tooltip is not hidden"
    why_human: "D-05 is the one deliberate behaviour change; tooltip ownership is runtime state (Phase 66)"
  - test: "Reminder click overlays after login, Edit Mode exit and a /reload; shrink and grow a reminder container"
    expected: "Overlays still follow their icons and click-cast; icons removed from a container lose their overlay (shared ClearClickStamp / ClearContainerClickStamps paths)"
    why_human: "Runtime secure-frame placement and stamp clearing need the game client (Phase 66)"
---

# Phase 65: Cleanup Verification Report

**Phase Goal:** v0.5.1 ships without duplication, dead code or hot-path waste of its own making
**Verified:** 2026-10-01
**Status:** human_needed
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Milestone-introduced duplication is unified; pre-milestone code untouched | VERIFIED | `BuildFollowSpellIDField(opts)` at CDMTab.lua:1589, declared above `TRACKER_FIELDS` (1902); both `auraID` (2256) and `castID` (2359) are built from it, the castID difference is the `emptyIsNone` option ("No click action", false when emptied) and the 'too large' message is `opts.tooLarge`. `ClearClickStamp(icon)` (Display.lua:150) is the only place the five stamp fields are nilled, used at 165, 2779, 2792, and `ClearContainerClickStamps` is shared by the two stamped-container blocks (Display.lua:174, 281). D-03 closed with reason in 63-REVIEW.md IN-01. No pre-milestone resolver was changed. |
| 2 | Hot-path audit finds no milestone-added per-frame work; overlay placement only on dirty edges | VERIFIED | Every `MarkReminderClicksDirty` caller is a state change, event or release path (Core.lua:1483, Display.lua:175/284/2781/2793/2849, ReminderClick.lua:223/231/250); the function only sets a flag and coalesces one `C_Timer.After(0, ...)`. The per-tick stamp test is comparisons only. Audit recorded in 65-01-SUMMARY.md under "D-09 hot-path audit". |
| 3 | Dead code gone incl. replaced tab icon refs; `stylua .` clean; every touched source file has expected line endings | VERIFIED | Dead `if ns.MarkReminderClicksDirty then` guard gone (Core.lua:1483 calls it directly). grep finds no `INV_Misc_Book_09` or `GM-icon-settings` in Lua/XML/TOC. Media/Textures (10 BLP) and Media/Source (10 PNG) match one-to-one. `stylua --check .` exit 0. `git ls-files --eol`: CDMTab, Core, Display, ReminderClick, install.ps1 all `w/crlf` with `eol=crlf`; no CRCR; png2blp.js `w/lf`. |
| 4 | install.bat/ps1, release.bat, .pkgmeta, release.yml reviewed end to end against Media/Textures | VERIFIED | install.ps1 now prunes empty directories deepest first, strictly inside `$dest`, with a non-recursive delete (lines 154-163), and canonicalises `$dest` first (WR-01, be337ab). png2blp.js: `fail()` on a missing `Media/Source` (180), duplicate output names rejected (190), full 8-byte signature checked (29). `.pkgmeta`, `release.yml` and `release.bat` unchanged since 631c7b3, consistent with the Phase 58 decision (release.bat changed only if broken). Review recorded in 65-02-SUMMARY.md. |

**Score:** 4/4 truths verified in code

### Decisions Honored

| Decision | Status | Evidence |
|----------|--------|----------|
| D-01 factory | Honored (code read; behaviour is human item 1) | One factory, differences are parameters (`secrecy`, `emptyIsNone`, `tooLarge`, `label`, `visible`) |
| D-02 / D-04 stamp clear | Honored | See truth 1 |
| D-03 resolvers: no change | Honored | 63-REVIEW.md line 172 records the reason |
| D-05 owned tooltip | Honored (human item 2) | ReminderClick.lua:58-63 `if GameTooltip:IsOwned(self)` |
| D-06 install.ps1 empty dirs | Honored | install.ps1:154-163; real-install probe recorded in 65-02-SUMMARY.md, not rerun here (writes files) |
| D-07 png2blp checks | Honored | png2blp.js:29, 180, 190; byte-identical regeneration recorded in SUMMARY, not rerun (writes files) |
| D-08 dead code | Honored | See truth 3 |
| D-09 hot-path audit | Honored | See truth 2 |
| D-10 release chain | Honored | No diff to release.bat, .pkgmeta, release.yml; gate scripts not wired in |
| D-11 CLAUDE.md list | Honored | CLAUDE.md lines 24, 28, 29, 35 add ReminderClick.lua, Media/Textures, Media/Source, png2blp.js |
| D-12 Phase 64 bookkeeping | Honored | 64-VERIFICATION.md line 86 and 64-REVIEW.md line 162 append the 1126 change (`f2d4209`) and Lightning Shield (`a793fe9`) without rewriting history |
| D-13 CHANGELOG untouched | Honored | CHANGELOG.md absent from the diff since 631c7b3 |
| D-14 closing checks | Honored | Commands below |

### Behavioral Spot-Checks

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Formatting | `stylua --check .` | exit 0 | PASS |
| Aura read gate | `node scripts/aura-read-gate.js` | `AURA-READ GATE PASS (10 reads in 3 allowlisted readers)` | PASS |
| Migration selftest | `node scripts/migrate-dryrun.js --selftest` | `SELFTEST PASS (12 cases)` | PASS |
| Line endings | `git ls-files --eol` on touched source | CRLF working copies for Lua/ps1 with `eol=crlf`; `grep -c $'\r\r'` 0 for all five | PASS |

### Anti-Patterns Found

None in the files touched by this phase. The ROADMAP.md Phase 65 plan checkboxes are still unticked; that is orchestrator bookkeeping, not a code gap.

### Human Verification Required

Listed in the frontmatter. All three need the game client and are deferred to Phase 66, the milestone's single testing pass.

### Gaps Summary

No gaps. All four roadmap criteria are verified in the codebase. The status is `human_needed` only because behaviour preservation of the shared field builder, the owned-tooltip hide and the overlay stamp clearing cannot be proven without the game.

---

_Verified: 2026-10-01_
_Verifier: Claude (gsd-verifier)_
