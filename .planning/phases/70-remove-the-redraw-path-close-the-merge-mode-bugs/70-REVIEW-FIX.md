---
phase: 70-remove-the-redraw-path-close-the-merge-mode-bugs
fixed_at: 2026-10-10T00:00:00Z
review_path: .planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 70: Code Review Fix Report

**Fixed at:** 2026-10-10
**Source review:** .planning/phases/70-remove-the-redraw-path-close-the-merge-mode-bugs/70-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (WR-01, WR-02, IN-01..IN-06; IN-02 was comment-only by instruction)
- Fixed: 8
- Skipped: 0

All fixes were committed directly on `milestone/v0.5.2-improved-merge-mode`, as instructed (no worktree).

Gates after the last commit:
- `stylua --check .` passes.
- `aura-read-gate.js` PASS (1 read, 1 reader). `--selftest` PASS (30).
- `migrate-dryrun.js --selftest` PASS (14).
- No `Bin` entries in the diff stat. `.lua` files stay `w/crlf`; the planning `.md` files stay `w/lf`.

Deployed `v0.5.1-101-g5a0c9ed-dev` to `_retail_`, `_ptr_`, `_beta_` and `_classic_beta_`. The TOC is unchanged, so `/reload` is enough.

## Fixed Issues

### WR-01: Whole-path review (and 70-04/70-05 summaries) wrongly says `ns.SPELL_CATEGORY_COMBAT_POTION` has no reader

**Files modified:** `70-MERGE-PATH-REVIEW.md`, `70-04-SUMMARY.md`, `70-05-SUMMARY.md`
**Commit:** ca2c14b
**Applied fix:** Corrected all three notes. They now say `Providers.lua:783` still reads the constant for the Pot meta-tracker's unresolved icon, so it must be kept and is not a cleanup-phase candidate. Each note records the correction. Providers.lua and Core.lua are unchanged. `70-04-PLAN.md:67` still carries the original instruction; it was left alone as a historical plan.

### WR-02: Mirror still builds aura-path-only fields

**Files modified:** `MergeMode.lua`, `Display.lua`
**Commit:** ae4ffe0
**Applied fix:** A grep confirmed that `/tbt merge` was the only reader of `linkedSpellIDs`, `hideAura`, `hasCharges` and `selfAura`. These were removed:
- the four fields
- `CopyLinkedSpellIDs`, which removes one table allocation per entry on every mirror rebuild
- `HIDE_AURA`
- their `/tbt merge` output: `linked=`, `cdmCharges`, `hideAura`, and the yellow `notSelfAura`

`HasCooldownFlag` stays because `HIDE_BY_DEFAULT` still uses it; its comment no longer says "two callers". The comments on `equipSlot` (field and capture block) now say it is kept for diagnostics only. Display.lua's `chargeCapable` comment now says `entry.hasCharges` was removed. `/tbt merge` still prints `id`, `spell`, `shown`, `visible`, `cell`, `equipSlot`, `itemIcon` and `cat`.

### IN-01: Stale comments in Display.lua

**Files modified:** `Display.lua`
**Commit:** d85b3ef
**Applied fix:** Reworded three comments:
- `GridSlotPlacement`: it has one caller now, and the engine aura slots are gone.
- Charge-count font: now refers to Blizzard's re-anchored Essential frame next to a TBT icon.
- `ApplyCooldownGrey`: the aura branch is deleted and `ApplyCooldownHandle` is its only caller.

`GridSlotPlacement` stays an `ns:` method. Making it file-local was optional, and the planning docs refer to it by that name.

### IN-02: `SlotDraws` does not mirror the fail-closed merged arm

**Files modified:** `Display.lua`
**Commit:** b837c31
**Applied fix:** Comment only, as instructed. It explains that the merged arm leaves out the fail-closed arm on purpose, because that arm is unreachable: `mergeShownSlots` is filled only while Merge Mode is on. No logic changed.

### IN-03: Per-tick work on hidden, attached merged bar rows

**Files modified:** `Display.lua`
**Commit:** 16d3f38
**Status:** fixed: requires human verification (control-flow change in the render loop)
**Applied fix:** In `RenderBarContainer`, right after `ApplyBarStyle`, a row with `reanchorHere and slot.isMerged and slot.cdmFrameVisible ~= false` now does only `bar.proc = slot; bar:Hide(); ns:AttachMergedItem(...)`. It skips `ApplyCachedIcon`, `label:SetText`, the status bar, the pip and the time writes. Everything else takes the old path, including the preview placeholder (`cdmFrameVisible == false`), the fail-closed merged arm and TBT's own rows.

Lua 5.1 has no `goto`, so the skip is an `if/else`, and the diff is mostly re-indentation (`git diff -w` shows the real change). The size and position that `AttachMergedItem` reads still come from `SetPoint` and `ApplyBarStyle`, which run first as before. In game, check that merged bars still sit on their rows, and that the Edit Mode placeholder still shows its icon and name.

### IN-04: Whole-path review C5 says `false`; it is `nil`

**Files modified:** `70-MERGE-PATH-REVIEW.md`
**Commit:** 3cd8cd7
**Applied fix:** C5 now says a viewer-less container passes `nil`, names the expression, and says why it still fails closed: an item frame's parent is never nil.

### IN-05: migrate-dryrun omits the `dialogStyle` clear

**Files modified:** `scripts/migrate-dryrun.js`
**Commit:** 58521b2
**Applied fix:** Added `if (g('dialogStyle') != null) { db.delete('dialogStyle'); ... }` just before the `mergeReanchorExperiment` clear. This matches the order in Core.lua:1889-1891. `node -c` and `--selftest` (14) pass.

### IN-06: MergeReanchor `OPEN ITEM` block mixes resolved and open items

**Files modified:** `MergeReanchor.lua`
**Commit:** 5a0c9ed
**Applied fix:** Split the block into two lists:
- "Settled": Hide When Inactive, Visibility and Click to Cast.
- "Known limitations": the bar name revealed on release, and the Show Timer swipe gaps.

The two "see OPEN ITEM" cross-references (in `ApplyMergedStyle` and `ReassertMergedSwipe`'s header) now point to "Known limitations".

---

_Fixed: 2026-10-10_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
