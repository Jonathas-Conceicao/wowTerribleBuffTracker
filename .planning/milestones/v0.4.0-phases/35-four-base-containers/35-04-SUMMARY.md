---
phase: 35-four-base-containers
plan: 04
subsystem: display
tags: [containers, rendering, hot-path, edit-mode]
requires:
  - "ns.CONTAINERS / ns.CONTAINER_BY_KEY (Plan 01, Core.lua)"
  - "ns.containers[key] (Plan 02, EditModeFrames.lua)"
  - "ns.db.containerSettings[key] seeding (Plan 01, Core.lua)"
provides:
  - "cachedSettings[key] — one settings snapshot per registered container"
  - "pools[key] / timersByContainer[key] — per-container frame pools and timer lists"
  - "ns.containerTooltipsShown[key] — per-container tooltip toggle"
  - "ns.cdmViewers[key] — CDM viewer resolved from def.cdmViewerGlobal"
  - "RenderBarContainer / RenderIconContainer — one render per registry kind"
affects:
  - "Display.lua"
  - "EditModeFrames.lua"
tech-stack:
  added: []
  patterns:
    - "registry-driven dispatch on def.kind instead of two hardcoded blocks"
    - "key-indexed per-container tables built once at load, inner lists wiped per cycle"
key-files:
  created: []
  modified:
    - "Display.lua"
    - "EditModeFrames.lua"
decisions:
  - "cachedSettings[key] is created lazily on first refresh, so a container with no DB settings keeps a nil cache and is skipped by UpdateDisplay rather than rendering half-configured."
  - "Timer grouping falls back to the bars list when timer.section names no registered container, reproducing the pre-Phase-35 two-way split for stale data."
  - "No example-icon placeholder for empty icon containers — deferred by 35-CONTEXT.md. The SetSize(40, 40) empty case is what keeps them clickable in Edit Mode."
metrics:
  duration: ~35m
  completed: 2026-09-21
  tasks: 4
  commits: 3
---

# Phase 35 Plan 04: Per-Container Rendering Summary

`UpdateDisplay` now groups timers per registered container and dispatches one render
function per container on `def.kind`, with every previously-paired table (settings cache,
frame pool, timer list, tooltip flag, CDM viewer) key-indexed off `ns.CONTAINERS`.

## What Was Built

**Task 1 — per-container state (commit `0537ee9`)**
- `cachedBarSettings` / `cachedIconSettings` → one `cachedSettings` table. `RefreshContainerSettings`
  loops `ns.CONTAINERS`, reads `ns.db.containerSettings[def.key]`, and writes into
  `cachedSettings[def.key]`, creating that inner table on first refresh and reusing it forever
  after. Every coercion is verbatim, including `(vis == 2) and 1 or (vis == 3) and 2 or 0` and
  `math.max(0.1, …)`. Kind-specific fields branch on `def.kind`: `barWidth`/`barContent` for
  bars, `orientationSetting`/`iconDirection` for icons.
- `barPool` / `iconPool` → `pools[key]`; `barTimers` / `iconTimers` → `timersByContainer[key]`.
  Both are built once at load in a single `ipairs(ns.CONTAINERS)` pass and never rebuilt.
- `GetBar(key, index)` / `GetIcon(key, index)` parent new frames to `ns.containers[key]` and
  stamp `containerKey` on them.
- `ns.barTooltipsShown` / `ns.iconTooltipsShown` → `ns.containerTooltipsShown[key]`, read by
  both `OnEnter` handlers as `ns.containerTooltipsShown[self.containerKey]`.
- `ns.cdmBarViewer` / `ns.cdmIconViewer` → `ns.cdmViewers[key]`, filled from
  `_G[def.cdmViewerGlobal]` when that global exists and has `.itemFramePool`. The
  disable-and-print path now fires on `not next(ns.cdmViewers)`.

**Task 2 — render split (commit `5b8e184`)**
- `RenderBarContainer(def, container, settings, timers, now)` and
  `RenderIconContainer(def, container, settings, timers, now)`, both module-level locals above
  `ns:UpdateDisplay`. Slot filters read `entry.section == def.key`; container anchors and sizing
  use the `container` argument.
- `ns:UpdateDisplay` wipes each `timersByContainer[key]` list, refills by
  `timersByContainer[timer.section] or timersByContainer.bars`, then loops `ns.CONTAINERS`,
  resolves container + settings, skips (hiding that container's pooled frames) when either is
  nil, and dispatches on `def.kind`.
- Scratch tables consolidated: `barSlots`/`buffSlots` → `slots`, `activeBarBySpell`/`activeBySpell`
  → `activeByKey`. Renders run sequentially, so one pair serves all four containers.

**Task 3 — bridge removal (commit `13f3702`)**
- `ns.barContainer` / `ns.iconContainer` and their comment deleted from `InitEditModeFrames`.
  Only change this plan made to `EditModeFrames.lua`.

**Task 4 — format, syntax check, deploy**
- `stylua` (no flags, repo root) produced no further changes after the per-task runs, so Task 4
  has no commit of its own.

## Preserved Behaviour

Verified line-by-line against the pre-split block: the `showPlaceholders` branch, the
`layoutOrder` sort, `EXAMPLE_BAR_SLOT` on `barEditing and #slots == 0` (bar kind only), the
`GetDisplayInfoForKey` fallback, both `cachedIcon == nil` guards with their comments (the
commit `3c1acf2` fix), `ShouldShow(..., ns.editModeActive)`, the orientation/direction anchor
matrix, the unused-frame hide loops, the bar height/width sizing, and the
`SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)` empty-icon-container case.

**Every `return` in the extracted icon block was read.** The original block had exactly three:
`not ns.iconContainer` (→ now the dispatch loop's nil-container skip), `not iconSettings`
(→ the same skip, which also hides the container), and `not iconVisible` (→ the one surviving
`return` inside `RenderIconContainer`, which correctly ends only that container's render). The
extracted functions now contain exactly one `return` each plus the sort comparator's return, and
`ns:UpdateDisplay` contains none.

## Hot-Path Discipline

No table constructor exists in `ns:UpdateDisplay`, `RenderBarContainer` or `RenderIconContainer`.
The ten `= {}` sites in `Display.lua` are all at module scope, in `RefreshContainerSettings`
(snapshot path, first call only), or in `ns:InitDisplay`.

Two pre-existing allocations remain in the placeholder path of both render functions:
`bar.proc = { spellID = …, label = …, key = … }` and its icon twin. They are byte-identical to the
pre-plan code and the plan mandated keeping the `GetDisplayInfoForKey` fallback verbatim, so they
were not touched. Worth revisiting in the milestone cleanup phase — with four containers they can
fire once per placeholder slot per tick. Same note applies to the two inline `layoutOrder` sort
comparators, which predate this plan and are now in two functions instead of two inline blocks.

## Deviations from Plan

**1. [Rule 3 — blocking] Task 1 had to touch `UpdateDisplay` references.**
Task 1's acceptance criterion (zero non-comment hits for `barPool`, `cachedBarSettings`, …)
cannot be met without rewriting the references inside `UpdateDisplay`, which Task 2 then
restructures. Task 1 therefore rewrote them to the literal-key intermediate form
(`pools.bars`, `cachedSettings.buffs`, `GetBar("bars", i)`, …) so that commit `0537ee9` is a
working addon on its own; Task 2 replaced those literals with `def.key`. No behaviour change in
either step.

**2. `now` is unused in `RenderIconContainer`.** Kept because the plan specifies the signature and
a uniform dispatch signature is what lets `UpdateDisplay` call either function the same way.

**3. `cmd.exe /c scripts\install.bat` produced no output under this shell**, so the deploy was run
as `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1` — the exact command
`install.bat` wraps. Exit 0, all four client folders written.

## Verification

Commands run from the repo root, real output:

| Check | Result |
|---|---|
| `grep -v '^\s*--' Display.lua \| grep -c 'cachedBarSettings\|cachedIconSettings\|barPool\|iconPool\|ns\.barTooltipsShown\|ns\.iconTooltipsShown\|ns\.cdmBarViewer\|ns\.cdmIconViewer'` | `0` |
| `grep -n 'ns.containerTooltipsShown\[self.containerKey\]' Display.lua` | lines 223, 272 (two matches) |
| `grep -n 'frame.containerKey = \|bar.containerKey = ' Display.lua` | lines 296, 306 |
| `grep -n '_G\[def.cdmViewerGlobal\]' Display.lua` | line 381 |
| `grep -n 'Cooldown Manager not found' Display.lua` | line 388 |
| `grep -n 'local function RenderBarContainer\|local function RenderIconContainer' Display.lua` | lines 428, 576 |
| `grep -v '^\s*--' Display.lua \| grep -c 'timer.section == "buffs"'` | `0` |
| `grep -n 'EXAMPLE_BAR_SLOT' Display.lua` | line 40 (declaration), line 478 (inside `RenderBarContainer`) |
| `grep -c 'ipairs(ns.CONTAINERS)' Display.lua` | `5` (≥ 2) |
| table constructors in the three functions | none (`awk` scan of lines 428-746: only the two pre-existing `proc = { … }`) |
| `grep -v '^\s*--' *.lua \| grep -c 'ns\.barContainer\|ns\.iconContainer'` | `0` |
| whole-plan paired-field sweep (V1, 10 alternatives) | `0` |
| `grep -rn 'editModePositions.icons' *.lua` | 3 hits, all inside the `ver < 4` migration in `BuffEngine.lua` |
| `grep -c 'ipairs(ns.CONTAINERS)' Core.lua BuffEngine.lua EditModeFrames.lua Display.lua CDMTab.lua` | Core 2, BuffEngine 0, EditModeFrames 9, Display 5, CDMTab 4 |
| `grep -rn '"essential"\|"utility"' *.lua` | only `Core.lua:29` and `Core.lua:38` (the `key =` fields) |
| `stylua --check .` | exit 0 |
| `git diff --stat` for Tasks 1-3 | only `Display.lua` and `EditModeFrames.lua` |
| deploy | exit 0, four client folders |

`luac` is **not** on this machine's PATH (nor `lua`, nor `luacheck`), so the plan's
`luac -p` step was skipped as the plan allows. `stylua --check .` passing is a full parse of both
files by stylua's Lua parser and stands in for it.

There is no test runner, CI suite or headless harness for this addon; no tests were run or claimed.

## Outstanding — In-Game Pass (human, Forever beta)

Not attempted and not claimed. The whole-phase list from the plan, `/reload` first:

1. `/tbt` shows six sections in order: Tracked Buffs, Tracked Bars, Essential Cooldowns, Utility
   Cooldowns, Not Displayed, Suggested; every tracked buff in the section it was left in.
2. Edit Mode shows four labelled TBT overlays; pre-existing bar/buff containers unmoved, the two
   new ones stacked below.
3. Each of the four drags alone; settings popup title matches; only the bar container offers
   *Bar Width* and *Display Mode*.
4. Exit and re-enter Edit Mode: all four positions held.
5. A tracker dragged from Not Displayed into Essential Cooldowns renders as an icon in that
   container, and its right-click menu lists the other three containers plus Hide/Remove.
6. No Lua error on load, first Edit Mode entry, Edit Mode exit, or in combat.

Persistence (logout→login) is retail-only and deferred to Phase 44 — `/reload` is not a
persistence test and no persistence claim is recorded from this pass.

## Known Stubs

None. The two cooldown containers render nothing only because nothing is assigned to them yet;
they render correctly as soon as a tracker's `section` names them (in-game step 5), and Phase 38
supplies their real content.

## Self-Check: PASSED

- `Display.lua` — FOUND
- `EditModeFrames.lua` — FOUND
- `.planning/phases/35-four-base-containers/35-04-SUMMARY.md` — FOUND
- commit `0537ee9` — FOUND
- commit `5b8e184` — FOUND
- commit `13f3702` — FOUND
