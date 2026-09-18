---
phase: 30-cleanup
plan: 03
subsystem: performance-audit
tags: [hot-path, memoisation, tooltip, ghost-frame, todos]

requires:
  - phase: 30-01
    provides: stylua.toml and CRLF-normalised EditModeFrames.lua (precondition for closing the LF todo)
provides:
  - Hot-path audit of all five v0.3-touched sites, verdict NONE
  - LF/stylua todo closed with resolution note
  - install.bat prune todo confirmed left open
affects: [30-04]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified: [.planning/todos/done/2026-09-18-editmodeframes-lua-is-lf-and-stylua-dirty.md]

key-decisions:
  - "Hot-path audit verdict: NONE — no per-frame or per-event allocation regression introduced by v0.3, matching v0.2.4 Phase 24's vocabulary"
  - "install.bat prune todo deliberately left open — pruning is new behaviour outside INST-01..04"

patterns-established: []

requirements-completed: []

duration: 20min
completed: 2026-09-18
---

# Phase 30 Plan 03: Hot-path audit + todo ledger cleanup Summary

Audited all five v0.3-touched code sites for per-frame/per-event allocation regressions (verdict: NONE), and closed the resolved LF/stylua todo while deliberately leaving the install.bat prune todo open.

## Performance

- **Duration:** ~20 min
- **Tasks:** 2/2 completed
- **Files modified:** 1 (todo rename + resolution note; Task 1 changed nothing)

## Accomplishments

- All five v0.3-touched hot-path sites audited with per-invocation allocation and call-frequency evidence, verdict `NONE` (no regression), matching v0.2.4 Phase 24's vocabulary
- Ghost-frame `OnUpdate` proven to allocate nothing per frame and to hold `topLevel` as a session-lifetime upvalue, not a per-frame resolver call
- `ns:IsSuggestedKeyResolvable` proven to genuinely memoise (`~= nil` test, not truthiness) and `HasResolvableCatalog` proven absent from `CDMTab.lua`'s render path
- LF/stylua todo closed with a resolution note; install.bat prune todo confirmed untouched

## Task Commits

1. **Task 1: Hot-path audit of the five v0.3-touched sites (D-15, D-16, D-17, D-18)** — no commit (read-only, changed nothing)
2. **Task 2: Close the LF/stylua todo, leave the install.bat prune todo open (D-21)** - `b56728e` (docs)

## Five-Site Audit Record

### Site 1 — Ghost frame `OnUpdate` (`CDMTab.lua:232-245`, `GetOrCreateGhostFrame`). The only genuine per-frame path, and only during an active drag.

- **What v0.3 changed:** Replaced `GetScaledCursorPositionForFrame(topLevel)` (absent on Forever, 53 errors/session) with `topLevel:GetScale()` + `GetCursorPosition()` (`9e32f92`).
- **Allocates:** Nothing. No table constructor, no string concatenation/format, no inner closure (the handler itself is the only `function` in its body). `GetCursorPosition()` returns two Lua number values; `topLevel:GetScale()` is a cheap C accessor.
- **Frequency:** Per frame, only while a drag is active.
- **Confirmed:** `topLevel` is captured once inside `GetOrCreateGhostFrame` (`local topLevel = GetAppropriateTopLevelParent()`, line 224) — a session-lifetime upvalue, not a per-frame resolver call. `GetAppropriateTopLevelParent()` does not appear inside the `OnUpdate` closure body (grep count 0).
- **Second per-frame handler in the same drag:** `OnDragUpdate` on `ns.tbtPanel` (`CDMTab.lua:304`), set in `BeginDrag` and cleared with `ns.tbtPanel:SetScript("OnUpdate", nil)` in `EndDrag` (no idle cost). Confirmed **not modified by v0.3**: `git log --oneline v0.2.6..HEAD -- CDMTab.lua` shows only `9e32f92` (ghost `OnUpdate` fix) and `ae378d6` (META-01, unrelated); `git blame`/`git log -L` on `OnDragUpdate`'s body traces it to `d086429`, v0.2.0. It still calls `GetAppropriateTopLevelParent():GetScale()` per frame, same as it always has — that is v0.2.4 Phase 24 territory, not this plan's, per D-15's explicit scope.
- **Correctness caveat (observed, not fixed here):** capturing `topLevel` once means a ghost frame created in one UI-parent context keeps that parent for the session. This is a correctness observation about the Phase 27.1 fix, not a performance one, and per hard constraint is not to be changed in this audit.
- **Command output:**
  ```
  $ git log --oneline v0.2.6..HEAD -- CDMTab.lua
  9e32f92 fix(27.1): drag no longer calls a nil engine global on Forever (PAR-02)
  ae378d6 feat(27.1): skip Suggested meta tiles whose catalog resolves nothing (META-01)
  ```

### Site 2 — `ns:ShowBuffTooltip`'s resolve probe (`Display.lua:73-110`)

- **What v0.3 changed:** Added a `C_Spell.GetSpellInfo(spellID)` resolve probe before choosing `SetSpellByID` vs `SetText` (`9fde1eb`).
- **Allocates:** One API call per invocation; result stored in `spellResolves` (a boolean) and reused — not re-probed.
- **Frequency:** Per hover. Call sites: bar `OnEnter` (`Display.lua:201-206`), icon `OnEnter` (`Display.lua:250-255`), CDM settings grid (`CDMTab.lua:89`, `:112`) — all hover-driven, confirmed via `grep -B4 'ns:ShowBuffTooltip(self, self.proc)' Display.lua` showing `OnEnter` immediately above both call sites, and zero `OnUpdate` references anywhere near `ShowBuffTooltip`.
- **Judgement (D-17):** A single API call on a hover path is not a regression.

### Site 3 — Core.lua's tooltip post-call and `RelatedID` pcalls (`Core.lua:155-209`)

- **What v0.3 changed:** New `TooltipDataProcessor.AllTypes` post-call (TOOL-01) adding a Spell ID / Aura spell ID line, with `RelatedID` computing Base/Override spell IDs via `pcall`.
- **Allocates:** For non-spell/non-aura tooltips (item, unit, currency): three table lookups (`tooltipData.type`, `SPELL_TYPE` comparison, `AURA_TYPES[dataType]`) and nothing else — the early-out at `Core.lua:172` returns **before** `local function RelatedID` at `Core.lua:190` (confirmed by line number: 172 < 190). For a spell/aura tooltip: one closure allocation (`RelatedID`) plus up to two `pcall`s plus up to two `AddLine` calls.
- **Frequency:** Per tooltip hover, never per frame.
- **Judgement (D-17), stated explicitly:** Acceptable on a hover path. The `pcall`s are not defensive clutter — `C_Spell.GetBaseSpell`/`GetOverrideSpell` can reject an ID the client only partly knows, and the code's own comment at `Core.lua:188-189` already states "Tooltips fire on hover, not per frame."
- **Command output:**
  ```
  $ grep -n 'if not (isSpell or isAura) then' Core.lua | head -1
  172:		if not (isSpell or isAura) then
  $ grep -n 'local function RelatedID' Core.lua | head -1
  190:		local function RelatedID(fn)
  ```

### Site 4 — `UnresolvedDisplayInfo` (`Providers.lua:218-225`)

- **What v0.3 changed:** Nothing — pre-existing since Phase 27, in scope only because D-15 names it.
- **Allocates:** One fresh 4-field table literal per call.
- **Frequency:** Only from the two `GetDisplayInfo` unpopulated-cache branches (`TrinketProviderMixin`, `PotProviderMixin`), bounded by `ns:RefreshTBTSections` — i.e. per Suggested tile per section redraw, not per frame. Unreachable on Forever, since META-01 hides those tiles before `GetDisplayInfo` is called.
- **Accepted, not changed:** A shared module-level table would remove the allocation but hand callers a mutable alias — a behaviour change, out of scope for this audit.

### Site 5 — `ns:IsSuggestedKeyResolvable`'s memoisation (`Providers.lua:684-696`). The one D-18 singles out.

- **What v0.3 changed:** New function (META-01), backing the data-driven Suggested-tile hide.
- **Confirmed it genuinely memoises:** `local cached = catalogResolvable[key]; if cached ~= nil then return cached end` — the `~= nil` test, not a truthiness test, so a cached `false` sticks and does not re-walk the catalog. The walk (`p:HasResolvableCatalog()`) runs at most once per key per session.
- **Load-bearing render-path check:** `grep -c 'HasResolvableCatalog' CDMTab.lua` → `0`. No render path can reach a catalog walk, however often `ns:RefreshTBTSections` redraws (confirmed 3 `ipairs(ns.SUGGESTED_KEYS)` sites in `CDMTab.lua`: context-menu add, drag-drop add, and the render loop at line 728/738 — only the render loop is gated by `ns:IsSuggestedKeyResolvable`, the other two do bounded work over a 3-element list).
- **Asymmetry recorded:** when `keyToProvider[key]` is nil, the function returns `true` **without** writing the cache — harmless (no walk happens on that branch) but a real difference from the cached branch.
- **Frequency:** Catalog walk once per key per session; the memoised read runs on every CDM open and after every drag/add/move/delete.

### Sites explicitly excluded (D-15 scope)

`Display.lua`'s render loop, `BuffEngine.OnUnitAura`'s dispatch, and `ScanActiveTimersForCancellation` were audited under v0.2.4 Phase 24 and v0.3 did not touch them: `git log --oneline v0.2.6..HEAD -- BuffEngine.lua` returns zero commits; `Display.lua`'s only v0.3 commit (`9fde1eb`) touched `ShowBuffTooltip` alone, not the render loop.

### Criterion-3 Verdict

**NONE** — v0.3 introduced no per-frame or per-event allocation regression, in v0.2.4 Phase 24's vocabulary.

## Planner Findings — Confirmed

1. **Confirmed in full**, including the `OnDragUpdate`/`topLevel` upvalue distinction and the correctness caveat, marked observed-not-fixed.
2. **Confirmed in full**, including the nil-provider branch asymmetry.
3. **Confirmed in full**, including the line-number ordering proof (172 < 190).
4. **Confirmed in full.**
5. **Confirmed in full.**

No finding was refuted.

## Todo Ledger (D-21)

- **Closed:** `.planning/todos/done/2026-09-18-editmodeframes-lua-is-lf-and-stylua-dirty.md` — precondition verified first (all six Lua files `w/crlf`, `stylua.toml` present with `line_endings = "Windows"`) before the move. Resolution section records the deliberate step-1/step-3 inversion, the final six-row `--eol` table, the `CLAUDE.md` amendment, and carries the declined `.gitattributes` forward as still-open future work.
- **Left open, byte-identical:** `.planning/todos/pending/2026-09-18-install-bat-does-not-prune-stale-files.md`. This is a deliberate decision, not an omission: pruning `install.bat`'s deploy target is new behaviour outside `INST-01…04`, and the real stale-TOC risk it documents does not license a cleanup phase to add a capability (`30-CONTEXT.md` Deferred Question 1). `.planning/todos/pending/` holds exactly this one file after the close.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- FOUND: `.planning/todos/done/2026-09-18-editmodeframes-lua-is-lf-and-stylua-dirty.md`
- FOUND: `.planning/todos/pending/2026-09-18-install-bat-does-not-prune-stale-files.md` (byte-identical, untouched)
- FOUND commit b56728e (`git log --oneline --all | grep b56728e`)
- Working tree confirmed clean for all `.lua`, `.toc`, `.xml`, `scripts` paths after Task 1

<deferred_questions>
None.
</deferred_questions>
