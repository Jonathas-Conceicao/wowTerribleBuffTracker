---
phase: 47-item-tracking-cooldown-sharing
plan: 03
subsystem: addon-runtime
tags: [wow-addon, lua, cooldown-manager, item-tracking, display-render]

# Dependency graph
requires:
  - phase: 47-item-tracking-cooldown-sharing (Plan 01)
    provides: "ns:TrackedItemCount(key), ns.cooldownStarts[key] stamped by Plan 01's provider/reconcile"
  - phase: 47-item-tracking-cooldown-sharing (Plan 02)
    provides: "a real ns.db.trackedBuffs[\"item:<itemID>\"] entry, ns:GetTrackerCategory widened, event wiring"
provides:
  - "Four widened trackerType gates in Display.lua: SlotDraws, RefreshCooldownSlotCounts, the bar-slot exclusion, the icon dispatch gate"
  - "ApplyItemCount(icon, entry) -- the item-count render parallel to ApplyChargeCount"
  - "A 23-row trackerType audit table covering every hit in the codebase, each with a WIDEN / ALREADY WIDENED / NO CHANGE determination"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Explanatory Phase-N comments placed BEFORE a statement, never spliced between operands of a multi-line boolean expression -- a comment sitting between `return X` and its first `or` continuation triggers a reproducible stylua blank-line-insertion bug local to that exact syntactic position (see Deviations)"
    - "A second render function (ApplyItemCount) kept structurally parallel to, not merged into, the function it resembles (ApplyChargeCount) because the two are driven by disjoint data sources with disjoint failure modes"

key-files:
  created: []
  modified:
    - Display.lua

key-decisions:
  - "SlotDraws' widening comment moved from between `return timer ~= nil` and its first `or` clause to immediately before the `return` statement, after discovering stylua repeatedly (and cumulatively, once per invocation) duplicated the CRLF terminator on any standalone `--` comment line placed between a `return` and its first `or` continuation. Functionally identical widening (`entry.trackerType == \"item\"` still ORed into the same boolean), placement changed for reasons documented in Deviations."
  - "The four Display.lua gates widened exactly as scoped -- SlotDraws, RefreshCooldownSlotCounts, the bar-slot exclusion, the icon dispatch gate -- and nothing else in Display.lua touched. ApplyUserCooldown, ApplyCachedIcon and ApplyCooldownSlot's body are unmodified, confirmed by the S-gate that asserts no added/removed line mentions either of the first two names."

patterns-established:
  - "Pattern: when adding a structural comment near an existing multi-line boolean `or`/`and` chain, place it before the statement that owns the chain, not between the chain's first term and its continuation -- stylua's Windows line-ending emitter has a reproducible bug at that specific position (confirmed empirically across five stylua invocations, CR count climbing 1->2->3 before the comment was relocated)."

requirements-completed: []

# Metrics
duration: 70min
completed: 2026-09-24
---

# Phase 47 Plan 03: Item Tracker Rendering Summary

**Audited all 23 `trackerType` sites in the codebase (not the three named in prior research), widened the four `Display.lua` gates an item tracker must pass to reach the screen, and added `ApplyItemCount` as a structural parallel to `ApplyChargeCount`. Task 3 (the in-game G1-G5 gate) was not attempted, per this plan's explicit checkpoint boundary -- the phase remains `human_needed`.**

## Performance

- **Duration:** ~70 min (two task commits; most of the time spent diagnosing and fixing a reproducible stylua line-ending bug -- see Deviations)
- **Tasks:** 2/2 automatable tasks completed; Task 3 (blocking human-verify checkpoint) correctly not attempted
- **Files modified:** 1 (`Display.lua`)

## Accomplishments

- Full audit of every `trackerType` hit in the codebase: `grep -rn 'trackerType' *.lua` returns **23** hits today (not the "twenty" recorded at planning time -- Waves 1 and 2 added three more since the plan was written: `Core.lua:100`'s Phase 47 comment, and `Providers.lua:1115`/`:1146` inside Plan 01's own item-specific functions). Every hit carries a recorded determination in the table below.
- `SlotDraws` (`Display.lua:86-102`) widened: an item tracker now draws on the same terms as a cooldown tracker, with a comment noting the widening is currently unreachable/defensive (the centred layout it gates only applies to buffs containers).
- `RefreshCooldownSlotCounts` (`Display.lua:696-711`, load-bearing) widened: a container holding only tracked items now counts toward `hasActiveIcons`, so it does not hide under `hideWhenInactive`.
- The bar-slot exclusion (`Display.lua:1656`, negated form) widened: an `item:` entry is now excluded from bar containers on the same terms as a `cd:` entry, extending the Phase 38 "cooldowns are icons, never bars" comment to cover tracked items.
- The icon dispatch gate (`Display.lua:2036`) widened: an item entry now reaches `ApplyCooldownSlot` instead of falling through to the placeholder branch.
- `ApplyItemCount(icon, entry)` added (`Display.lua:962-969`) immediately after `ApplyChargeCount`, reading `ns:TrackedItemCount(entry.key)` only, showing a count of zero (not hiding it -- the ITEM-09 case), and making zero `C_Item.`/`C_Spell.` calls.
- The call site inside `ApplyCooldownSlot`'s generation-gated block now branches on `entry.trackerType == "item"` between `ApplyItemCount` and the unmodified `ApplyChargeCount` call, in the same position in the block.
- `ApplyUserCooldown`, `ApplyCachedIcon` and `ApplyCooldownSlot`'s body confirmed unmodified by source assertion (no added/removed line mentions either of the first two names).
- `ns:ItemCatalogueCount` confirmed absent from the whole of `Display.lua` (S8) -- the tracked tile's count can never silently break on a rescan the way the Suggested tile's would.

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit every trackerType site and widen the four gates in Display.lua** - `9afe479` (feat)
2. **Task 2: Add ApplyItemCount and branch the count render at ApplyChargeCount's call site** - `b26c900` (feat)

**Plan metadata:** this summary + STATE.md, per `commit_docs` (STATE.md/ROADMAP.md are NOT touched by this executor per `<do_not_touch>` -- the orchestrator owns those).

## The trackerType Audit Table

One row per hit of `grep -rn 'trackerType' *.lua`, run fresh against the post-Task-2 source. **23 hits**, not the 20 recorded at planning time -- see note above.

| # | File:Line | Code / comment | Determination | Structural reason |
|---|-----------|-----------------|----------------|--------------------|
| 1 | `BuffEngine.lua:97` | comment: "adds no migration block at all. entry.trackerType reads as nil..." | NO CHANGE | Explanatory prose only, no code test. |
| 2 | `BuffEngine.lua:199` | `if type(key) == "number" and entry.trackerType == "cooldown" then` | NO CHANGE | The one-time numeric-key rekey migration. Gated on `type(key) == "number"` and runs once; an item entry's key is always the string `"item:<itemID>"`, never numeric, so it can never reach this branch. |
| 3 | `BuffEngine.lua:416` | comment: `opts.trackerType "buff" / "cooldown" -- anything else...` | NO CHANGE | Doc comment for `ns:AddTrackedBuff`'s options, the numeric-spell creation path. |
| 4 | `BuffEngine.lua:450` | `local trackerType = (opts and opts.trackerType == "cooldown") and "cooldown" or "buff"` | NO CHANGE | Inside `ns:AddTrackedBuff` -- the numeric-spell creation path. An item tracker is created by `AddSuggestedTracker` (`CDMTab.lua`), not this function; this function is never called with an item shape. |
| 5 | `BuffEngine.lua:458` | `local dbKey = ns:TrackerKey(spellID, trackerType)` | NO CHANGE | Same function as #4; only ever produces `"cd:"` or a numeric buff key, never an `"item:"` key. |
| 6 | `BuffEngine.lua:464` | `trackerType = trackerType,` | NO CHANGE | Same function; writes the entry field for a numeric-spell tracker only. |
| 7 | `BuffEngine.lua:480` | `.. trackerType` | NO CHANGE | Same function; string concatenation for a debug/label string, numeric-spell path only. |
| 8 | `CDMTab.lua:183` | `trackerType = cooldownSpellID and "cooldown" or (itemID and "item") or nil,` | ALREADY WIDENED (Plan 02) | `AddSuggestedTracker`'s entry constructor -- this is the exact line that gives an item drop its `trackerType = "item"`. Confirmed unchanged by this plan (read-only, per the plan's own scope). |
| 9 | `CDMTab.lua:1201` | `trackerType = ns.tbtActiveCategory == "spells" and "cooldown" or "buff",` | NO CHANGE | The manual "Add by Spell ID" dialog's `ns:AddTrackedBuff` call. Reads a user-typed numeric spell ID (`spellIdBox:GetNumber()`) -- there is no item-drop path through this dialog, so it can only ever produce `"cooldown"` or `"buff"`. |
| 10 | `Core.lua:21` | comment: "trackerType, so no migration and no second source of truth..." | NO CHANGE | Explanatory prose in a header comment, no code test. |
| 11 | `Core.lua:96` | comment: "tracker trackerType == \"cooldown\"; everything else..." | NO CHANGE | Explanatory prose above `ns:GetTrackerCategory`, no code test. |
| 12 | `Core.lua:100` | comment: "Phase 47: trackerType == \"item\" answers \"spells\" too..." | NO CHANGE (documents #13) | Plan 02's own explanatory comment for the widened line immediately below it; not itself a code test. |
| 13 | `Core.lua:106` | `if entry and (entry.trackerType == "cooldown" or entry.trackerType == "item") then` | ALREADY WIDENED (Plan 02) | `ns:GetTrackerCategory`, the line this plan's S7-equivalent Core.lua gate asserts is in place before trusting this plan's render work. Confirmed unchanged and passing the whole-file completeness check (both "cooldown"/"item" on the same line). |
| 14 | `Core.lua:479` | `function ns:TrackerKey(spellID, trackerType)` | NO CHANGE | Function signature for the numeric-spell creation path (mirrors `BuffEngine.lua ns:AddTrackedBuff`). An item tracker's key is built directly as `"item:" .. itemID` in `CDMTab.lua`, never through this function. |
| 15 | `Core.lua:480` | `if trackerType == "cooldown" then` | NO CHANGE | Inside `ns:TrackerKey`; only ever called with `"cooldown"` or `"buff"` from the numeric-spell path (see #14). |
| 16 | `Display.lua:86` (`SlotDraws`) → net at 96 after edit | `or (entry.trackerType == "cooldown" or entry.trackerType == "item")` | **WIDEN** (done, Task 1) | A cooldown tracker produces no `ns.activeTimers` entry, so `SlotDraws` special-cases it to draw regardless; an item tracker has the identical property for the identical reason. |
| 17 | `Display.lua:698` (`RefreshCooldownSlotCounts`) → net at 704 | `if (entry.trackerType == "cooldown" or entry.trackerType == "item") and entry.section then` | **WIDEN** (done, Task 1) | Load-bearing. Without this, a container holding only tracked items has `cooldownSlotCounts[def.key] == 0`, `#timers == 0`, `mergedCount == 0` → `hasActiveIcons` false → the container hides under `hideWhenInactive` while a sweep runs inside it. This is ITEM-09's container-hiding failure mode. |
| 18 | `Display.lua:1635` (bar-slot exclusion) → net at 1656 | `if entry.section == def.key and entry.trackerType ~= "cooldown" and entry.trackerType ~= "item" then` | **WIDEN** (done, Task 1) | Negated form. The Phase 38 "cooldowns are icons, never bars" locked decision covers tracked items too, per the locked v0.4.0 decision that item trackers render icon-only with a count. Unwidened, an item tracker misfiled into a bar container would draw as a permanently-empty bar. |
| 19 | `Display.lua:1999` (icon dispatch gate) → net at 2036 | `elseif entry.trackerType == "cooldown" or entry.trackerType == "item" then` | **WIDEN** (done, Task 1) | Without this, an item entry falls through to the placeholder branch and never reaches `ApplyCooldownSlot`, i.e. never renders at all. The branch body is unmodified -- `entry.isMerged` is always false for an item entry, so the merge-aura call below needs no additional guard. |
| 20 | `MergeMode.lua:356` | `trackerType = (def.kind == "icon" and def.cdmCategoryName ~= "TrackedBuff") and "cooldown" or "buff",` | NO CHANGE | The CDM def mirror -- mirrors Blizzard's own CooldownViewer defs (icon vs TrackedBuff category), which have no concept of a TBT-tracked item. Confirmed by reading the surrounding `list.insert` block: it is built entirely from `C_CooldownViewer` API defs, never from `ns.db.trackedBuffs`. |
| 21 | `Providers.lua:142` | `if entry.trackerType == "cooldown" then` | NO CHANGE | The buff-side provider's defence-in-depth reject, inside `local entry = tracked[spellID]` (a **numeric**-key lookup). An `"item:<itemID>"` key is a string and can never be returned by a numeric-keyed table lookup, so this line is structurally unreachable for an item entry regardless of its own value. |
| 22 | `Providers.lua:1115` | `if entry.trackerType == "item" and type(entry.itemID) == "number" then` | ALREADY WIDENED (Plan 01) | Inside `ns:RefreshTrackedItemCooldowns`, one of Plan 01's own item-specific functions -- built item-aware from inception, not a gate that needed widening by this plan. |
| 23 | `Providers.lua:1146` | `if entry.trackerType == "item" and type(entry.itemID) == "number" then` | ALREADY WIDENED (Plan 01) | Inside `ns:ReconcileTrackedItemCounts`, same reasoning as #22. |

**Disagreements with the plan's own expected-determinations list:** none. Every row matches the plan's own check-against list in the four cases it named explicitly (`Core.lua` `ns:GetTrackerCategory`, the merge-mode branch, the buff-side reject, the rekey migration, `ns:AddTrackedBuff`/`ns:TrackerKey`, `AddSuggestedTracker`, the add-panel constructor, `MergeMode.lua`'s def mirror). The three rows not named in the plan's own list (`Core.lua:100`, `Providers.lua:1115`, `Providers.lua:1146`) are new since Wave 1/2 landed and are marked ALREADY WIDENED / NO CHANGE above with reasons, not left unexamined.

## ApplyItemCount

Signature (`Display.lua:962`):

```lua
local function ApplyItemCount(icon, entry)
	local count = ns:TrackedItemCount(entry.key)
	if type(count) ~= "number" then
		icon.chargeCount:Hide()
		return
	end

	icon.chargeCount.Current:SetText(count)
	icon.chargeCount:Show()
end
```

Call site, inside `ApplyCooldownSlot`'s generation-gated block (replacing the bare `ApplyChargeCount(icon, spellID)` call, same position in the block):

```lua
if entry.trackerType == "item" then
	ApplyItemCount(icon, entry)
else
	ApplyChargeCount(icon, spellID)
end
```

## Deviations from Plan

### 1. [Rule 1 - Bug, self-caught during drafting] A reproducible stylua line-ending duplication bug, triggered by a specific comment placement

- **Found during:** Task 1, first attempt at `SlotDraws`.
- **What happened:** The first draft placed the widening comment *between* `return timer ~= nil` and its first `or` continuation (i.e. a standalone `--` comment sitting inside a multi-line boolean expression, between two of its operands). Every subsequent `stylua .` invocation against that file state added exactly one extra `\r` to each of the six comment lines in that block, confirmed byte-for-byte via a raw (`:raw`-mode) Perl read: the CR count climbed 1 → 2 → 3 across three separate `stylua .` runs, while every other line in the file (including the other three Task-1 comment insertions, structured identically but placed *before* their statement rather than *inside* an expression) stayed perfectly clean at every check.
- **Diagnosis:** Several tool-chain layers in this environment silently normalize CRLF to LF when piping through `sed`/`awk`/`cat -A` on this Windows/MSYS setup — even without `-i`, a bare `sed -n 'Np' file | cat -A` does not reliably show `\r` bytes that are actually present on disk. This is a **new addition to the CRLF-blindness family** CLAUDE.md already documents for `sed -i` and `text=auto` files: here it affects `sed -n`/`awk` used read-only, with no `-i`, on an `eol=crlf`-attributed file, purely from piping through those tools' line-oriented text-mode processing. Confirmed authoritative only via Perl's raw-mode file read (`open(..., "<:raw", ...)`), which never applies any newline translation. Every intermediate diagnosis in this task that used `sed`/`awk`/`cat -A` produced a false "bare LF" reading contradicted by the true byte content.
- **Fix:** Moved the six-line comment to sit entirely before the `return` statement it explains, rather than between the statement and its first `or` continuation. This is functionally identical (the widened boolean logic is unchanged) and matches the placement pattern used successfully in the other three Task-1 edits. After the move, `stylua --check .` reported clean (exit 0) on the first subsequent run and stayed clean on repeat runs.
- **Verified:** `stylua .` / `stylua --check .` clean and idempotent across three consecutive re-runs after the fix; raw Perl byte scan of the whole file reports zero doubled-CR sequences and zero bare-LF-only lines; `git ls-files --eol Display.lua` reports `w/crlf` (previously `w/-text`, git's own mixed-encoding flag, while the bug was present).
- **Files modified:** `Display.lua` (comment placement only, inside the already-in-progress Task 1 edit -- no separate commit; the corrected version is what `9afe479` contains).
- **Not a runtime bug and not a Rule 4 architectural question:** this never reached a commit in its broken form, and the fix touches only comment placement, not the widened logic itself. Flagged here because it consumed most of this plan's wall-clock time and because CLAUDE.md's CRLF-blindness warning needs this specific trigger (a comment between a `return` and its own `or` continuation, formatted through `sed -n`/`cat -A` for diagnosis) added to the pattern it already tracks.

### 2. [Rule 1 - Bug, self-caught during drafting] `ApplyItemCount`'s own header comment tripped its own gate, twice

- **Found during:** Task 2, first draft of `ApplyItemCount`'s header comment and the branch comment at the `ApplyChargeCount` call site.
- **What happened:** Both comments initially named the literal API call `C_Spell.GetSpellCharges` in prose (read-only reference, explaining why `ApplyChargeCount` cannot be reused), which tripped Task 2's own gate (`git diff -U0 -- Display.lua | grep -E '^[+-][^+-].*GetSpellCharges'` must be empty) because that gate cannot distinguish a comment mention from a real call. This is the exact same drafting-time pattern the 47-01 and 47-02 executors both hit and documented in their own summaries (naming a protected/gated identifier in prose inside a `<read_first>`-sourced comment).
- **Action:** Reworded both comments to describe "the game's own charge API keyed on spellID" / "the charge API" without naming the literal identifier. No functional change.
- **Not a runtime bug:** caught and fixed before the Task 2 commit, not after.

Neither deviation reached a commit in its broken form and neither is a Rule 1-4 runtime/architectural deviation in the traditional sense -- both were drafting-time gate failures caught and fixed before any commit.

## Issues Encountered

None beyond the two self-caught drafting issues above. All eleven `<automated>` verify clauses for Task 1 and all eleven for Task 2 passed on the corrected source, run individually rather than as a single compound `&&` chain (so each clause's pass/fail could be attributed precisely rather than only seeing the first failure in a chain).

## Known Stubs

None. `ApplyItemCount` is fully wired to `ns:TrackedItemCount`, the real Plan 01 store; nothing in this plan's diff hardcodes an empty value, a placeholder string, or leaves a component with no real data source.

## Threat Flags

None. This plan's diff makes no `C_Item`/`C_Spell` call, opens no new network/file/auth surface, and reads one cached number through an existing accessor (`ns:TrackedItemCount`) exactly as `47-VALIDATION.md`'s threat register (T-47-09, T-47-10, T-47-11) anticipated and this plan's own gates enforce.

## G1-G5: NOT STARTED -- AWAITING HUMAN VERIFICATION

Task 3 (the in-game phase gate) was **not attempted**, simulated, or inferred, per this plan's explicit `<checkpoint_rule>` boundary: it requires a human playing WoW Forever beta (build 1.60.1) on a character carrying real potions from the shared 999.6 cooldown group, and no part of it can be performed or approximated by this executor.

Run the checks below **in this order** (G2 and G5 cannot be shortened):

1. **G1 (ITEM-02, ITEM-04)** -- Open the Cooldown Manager, TBT tab, **Cooldowns** category. Drag a Suggested consumable tile into a container.
   Proves: `iconOverride` was written at creation (real item icon, not a question mark); `ns:GetTrackerCategory` files it under Cooldowns, not Buffs; the item leaves the Suggested list.

2. **G2 (ITEM-05)** -- Track **two** potions that share a cooldown group (any two of Minor Healing / Mana / Rejuvenation Potion). Drink **one**.
   Proves: the shared-cooldown re-read in `ns:RefreshTrackedItemCooldowns` (Plan 01) actually reaches the **other**, untouched tile -- the single behaviour no static read can infer. Watch both tiles.

3. **G3 (ITEM-06)** -- With a tracked item on cooldown from G2, try to use it again (refused press). Confirm its count does **not** change. Then use a different, off-cooldown tracked item and confirm its count drops by exactly 1.
   Proves: the decrement in Plan 01's `ItemProviderMixin:OnTrigger` fires only on a landed use, and `ApplyItemCount` (this plan) renders it correctly.

4. **G4 (ITEM-07)** -- Enter combat, drink a tracked potion (count drops by 1 locally), loot more of the same item while still in combat, leave combat.
   Proves: `ns:ReconcileTrackedItemCounts`'s combat gate (Plan 01) and its `PLAYER_REGEN_ENABLED` wiring (Plan 02) correct the displayed count to the true bag count after combat ends.

5. **G5 (ITEM-09)** -- Drink a tracked item down to its last one, then drink the last one so the stack leaves the bags entirely. Confirm in the Blizzard bag UI it is genuinely gone.
   Proves: the tile **remains visible** (this plan's `RefreshCooldownSlotCounts` widening), its sweep keeps running to expiry, and it shows `0` (this plan's `ApplyItemCount` showing a zero count rather than hiding it). A tile that disappears, freezes, or errors is a FAIL. If the **container** vanishes rather than just the tile, the defect is `RefreshCooldownSlotCounts` specifically.

G6 (retail parity) is out of scope for this plan and this phase -- it is Phase 52 by design (`47-VALIDATION.md`).

**Attribution if a check fails:** a FAIL on G1 or G5 points at this plan (icon override, category, dispatch gate, slot count). A FAIL on G2 or G3 points at Plan 01 (the map, the re-read, the decrement). A FAIL on G4 points at Plan 02's event wiring or Plan 01's reconcile.

## Phase Status: `human_needed`

All static gates (S1-S11, S7's completeness form) pass on the current source. **That proves the code is shaped correctly and nothing more.** None of ITEM-02, ITEM-04, ITEM-05, ITEM-06, ITEM-07 or ITEM-09 is closed until G1 through G5 come back from a real play session. Do not tick those requirements in `REQUIREMENTS.md` on the strength of this summary alone -- `requirements-completed` in this summary's frontmatter is deliberately empty for that reason.

## User Setup Required

Deploy with `./scripts/install.bat` before running G1-G5 -- this plan changes no TOC, so `/reload` is sufficient after the initial deploy; no full client restart is needed.

## Next Phase Readiness

- This is the last plan of Phase 47. There is no Plan 04.
- The phase closes only when a human runs G1-G5 and reports results, either in a fresh session against this summary or by resuming Task 3 directly.
- Phase 46's carry-over in-game verification risk (its own outstanding G1-G7) is unrelated to and not resolved by this plan.

---
*Phase: 47-item-tracking-cooldown-sharing*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `Display.lua`
- FOUND: `.planning/phases/47-item-tracking-cooldown-sharing/47-03-SUMMARY.md`
- FOUND: `9afe479` (Task 1 commit)
- FOUND: `b26c900` (Task 2 commit)
