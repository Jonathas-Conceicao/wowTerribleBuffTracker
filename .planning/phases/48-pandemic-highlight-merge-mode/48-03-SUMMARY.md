---
phase: 48-pandemic-highlight-merge-mode
plan: 03
subsystem: ui
tags: [wow-addon, lua, cooldown-manager, secret-values, merge-mode, verification]

# Dependency graph
requires:
  - phase: 48-pandemic-highlight-merge-mode/48-01
    provides: "ReadPandemicState, ns:IsMergedEntryInPandemic, entry.pandemicActive/pandemicStart/pandemicFinish"
  - phase: 48-pandemic-highlight-merge-mode/48-02
    provides: "EnsurePandemicIconFX/EnsurePandemicBarFX, SetPandemicShown, ApplyPandemicIcon/ApplyPandemicBar, render wiring"
provides:
  - "Consolidated S1-S14 static sweep run once across MergeMode.lua and Display.lua, every result recorded"
  - "Source-read confirmation of S4, S5, S8, S11, S14 (no grep can carry these)"
  - "Written backwards trace from the rendered highlight to ns.mergeItemFrames"
  - "Deploy to all four detected WoW client folders (retail, PTR, beta, classic beta)"
  - "Task 2 (G0-G6) explicitly NOT run — recorded as awaiting human verification"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified: []

key-decisions:
  - "No code written or modified in this plan — Task 1 is verification and deploy only, per its own <files> declaration"
  - "Task 2 (the in-game G0-G6 checkpoint) was not attempted, not simulated, and no outcome asserted — recorded verbatim as human_needed per gate"

patterns-established: []

requirements-completed: []

# Metrics
duration: ~15min
completed: 2026-09-24
---

# Phase 48 Plan 03: Consolidated Static Sweep and Deploy Summary

**Every S1-S14 static gate across MergeMode.lua and Display.lua re-run as one consolidated chain and passed with zero grep-only fudging, three source-only checks (S4/S5/S11) confirmed by eye, the backwards trace from rendered highlight to `ns.mergeItemFrames` written down, and the phase deployed to all four detected WoW clients — the in-game G0-G6 checkpoint was not attempted and remains the only path to closing PAND-01..05.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-09-24T13:28:10Z
- **Tasks:** 1/2 completed (Task 2 is a blocking human-verify checkpoint, correctly not attempted)
- **Files modified:** 0 (verification and deploy only)

## Accomplishments

- Ran the full command chain from `48-03-PLAN.md`'s `<verify><automated>` block, split across multiple `Bash` calls (not because any clause failed, but because `grep -c` returning `0` exits `1` and breaks a `&&` chain — the plan's own documented gotcha) — every clause passed.
- Confirmed stylua clean and idempotent: ran `stylua .` then `stylua --check .` twice each; `git status --short` was empty after every run (no drift, no reflow).
- Confirmed `git ls-files --eol` reports `w/crlf` for `MergeMode.lua`, `Display.lua`, and `Core.lua` — no CRLF→LF reflow occurred anywhere in this plan's work.
- Deployed via `./scripts/install.bat` to all four detected clients (retail, PTR, beta, classic beta) — argument-free, no TOC changed this phase, so `/reload` is sufficient in game.
- Performed the three source-only reads (S4, S5, S11) by eye, not grep, and the two source-only precedence/allocation reads (S8, S14) — all recorded below with line numbers.
- Wrote the backwards trace `48-VALIDATION.md` § Verification Guidance demands, from `ApplyPandemicIcon`/`ApplyPandemicBar` back through `ns:IsMergedEntryInPandemic` to `ReadPandemicState` to `ns.mergeItemFrames`, and stated what the stamp reads when `CollectShownCooldownIDs` has not run for a given def/viewer this pass.
- Performed a scoped cleanup/performance review of what this milestone's Waves 1-2 introduced (not pre-existing code) — no issues found; findings recorded below.
- Did **not** attempt, simulate, or assert any outcome for Task 2 (G0-G6). Recorded as `awaiting human verification` below.

## Task Commits

Task 1 modified no source file (verification and deploy only, per its own `<files>` declaration), so there is no task commit for it beyond this plan's own metadata commit. No prior-wave commits were touched.

**Plan metadata:** committed alongside this SUMMARY.md via the standard final `docs(48-03): ...` commit.

## Files Created/Modified

None. This plan is read-only against the source tree — `git status --short` was empty at the start, throughout, and at the end of the sweep.

## S1-S14 Sweep Results (verbatim)

All command output below is exactly what the terminal printed; nothing paraphrased.

### Command-gated clauses (S1-S3, S4b/S6, S7, S9, S10, S12, S13, plus wiring counts)

```
S_check1 OK          (ReadPandemicState defined exactly once)
S_check2 OK          (ns:IsMergedEntryInPandemic defined exactly once)
S_check3 OK          (S9 — pcall(ReadPandemicState, entry) present exactly once in ns:RefreshMergeShownSlots)
S7 OK                (issecretvalue appears >= 2 times inside ReadPandemicState)
S4a OK                (zero itemFrame: mixin-call syntax inside ReadPandemicState)
S5 OK                (zero itemFrame.field = assignments inside ReadPandemicState)
S4b/S6 OK             (zero non-comment occurrences of the seven forbidden CDM tokens across both files, incl. pandemicIconPool, SetLayoutData)
S10a OK               (exactly two CreateFrame(...CooldownPandemic...) calls in Display.lua)
S10b OK               (zero of those two lack pcall)
S13 OK                (bar.statusBar:GetFrameLevel() + 1 present exactly once in EnsurePandemicBarFX)
icon-wiring OK         (ApplyPandemicIcon( appears exactly twice in RenderIconContainer — main call + trailing-hide clear)
bar-wiring OK          (ApplyPandemicBar( appears exactly once in RenderBarContainer)
S3a OK                (zero flavour/build tokens in MergeMode.lua)
S3b OK                (zero flavour/build tokens in Display.lua)
S12a OK                (zero LogItemUse/LogPlayerCast/pendingItemCasts tokens in MergeMode.lua)
S12b OK                (zero LogItemUse/LogPlayerCast/pendingItemCasts tokens in Display.lua)
S12c-core-linecount OK (wc -l Core.lua = 1367)
```

### S1 — stylua clean and idempotent (run twice, as the plan's `<read_first>` requires)

```
stylua-run-1 done
stylua-check-1 OK (no drift after run 1)
stylua-run-2 done
stylua-check-2 OK (idempotent)
```
`git status --short` printed nothing after either run — zero files touched by stylua in either pass.

### S2 — line endings held

```
i/lf  w/crlf  attr/text eol=crlf   MergeMode.lua
i/lf  w/crlf  attr/text eol=crlf   Display.lua
i/lf  w/crlf  attr/text eol=crlf   Core.lua
```

### Deploy

```
Deploying 11 files derived from TerribleBuffTracker.toc: TerribleBuffTracker.toc, Core.lua, BuffEngine.lua,
Providers.lua, MergeMode.lua, EditModeFrames.lua, Config.lua, Display.lua, CDMTab.xml, CDMTab.lua, tbt_icon_64x64.blp
Deployed version: v0.4.0-63-gb273cdf-dev
Installed to C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_beta_\Interface\AddOns\TerribleBuffTracker
Installed to C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\TerribleBuffTracker
Done! /reload in WoW to load the addon.
```
No TOC changed this phase, so `/reload` is sufficient in game — no full client restart needed. This covers all four clients the machine has installed, including the WoW Forever beta (`_classic_beta_`) Task 2 requires to run first.

Every command-based clause the plan's `<verify><automated>` chain specifies exited successfully; the chain's final `echo SWEEP_OK` sentinel is satisfied by construction (every prior clause in the chain passed when run, split only to work around the documented `grep -c` zero-exit-code gotcha, never to skip a clause).

## Source Reads (S4, S5, S8, S11, S14) — line by line

Per the plan's own instruction, S4/S5/S11 are stated as source reads because a grep can prove the five named mixin methods absent but cannot prove a sixth was never invented — only a read can.

### S4 / S5 — every line touching `itemFrame` (`MergeMode.lua:756-806`, `ReadPandemicState`)

- `MergeMode.lua:757` — `local itemFrame = ns.mergeItemFrames[entry.cooldownID]` — plain table lookup, not a frame method.
- `MergeMode.lua:776` — `entry.pandemicActive = itemFrame.PandemicIcon ~= nil` — plain field read (`itemFrame.PandemicIcon`), write lands on `entry`, never on `itemFrame`.
- `MergeMode.lua:784` — `local startTime = itemFrame.pandemicStartTime` — plain field read.
- `MergeMode.lua:785` — `local endTime = itemFrame.pandemicEndTime` — plain field read.
- No other line in the function touches `itemFrame`. No `itemFrame:MethodName(...)` call syntax anywhere (confirmed by both the `itemFrame:` grep above and this manual read). No `itemFrame.field = ...` assignment anywhere (confirmed by both the assignment-pattern grep above and this manual read) — every write in the function lands on `entry`'s own fields (`entry.pandemicActive`, `entry.pandemicStart`, `entry.pandemicFinish`). No sixth mixin method name appears anywhere in this block beyond the five the grep already covers, because there is no method-call syntax on `itemFrame` at all — only three plain field reads.

### S11 — highlight frames are TBT-owned, never acquired from a Blizzard pool (`Display.lua:569-640`)

- `EnsurePandemicIconFX` (`Display.lua:569-604`): `local parent = icon:GetParent()` (`:577`, a TBT container frame) then `pcall(CreateFrame, "Frame", nil, parent, "CooldownPandemicFXTemplate")` (`:582`) — the frame is created by TBT via `CreateFrame`, parented to a TBT-owned container, never `pool:Acquire()`'d from `viewer.pandemicIconPool` or any other Blizzard pool. Stored on `icon.pandemicFX` (`:602`), a TBT-owned table field.
- `EnsurePandemicBarFX` (`Display.lua:611-640`): `pcall(CreateFrame, "Frame", nil, bar, "CooldownPandemicBarFXTemplate")` (`:619`) — parented directly to `bar`, a TBT-owned widget, again via `CreateFrame`, never a pool acquisition. Stored on `bar.pandemicFX` (`:638`).
- Both creators are lazy (checked via `icon.pandemicFX`/`bar.pandemicFX` before creating) and `pcall`-guarded around the one call that could raise (`CreateFrame` against a possibly-absent virtual template), degrading to `nil` on failure rather than retrying every tick (`icon._pandemicFailed`/`bar._pandemicFailed`, S10/PAND-05).
- Because every highlight frame is TBT's own from `CreateFrame` up, `Show`/`Hide`/`SetPoint`/`SetFrameLevel` on them (`SetPandemicShown`, `Display.lua:646-656`, and the anchor/level calls inside both creators) never touch a CDM-owned object — consistent with the file's own no-taint framing that the locked rule is "about frames TBT does not own."

### S8 — precedence not inverted (`MergeMode.lua:816-826`, `ns:IsMergedEntryInPandemic`)

```lua
if entry.pandemicStart and entry.pandemicFinish then
    return now >= entry.pandemicStart and now <= entry.pandemicFinish
end
return entry.pandemicActive == true
```
Readable numbers are checked and returned first (`:821-822`); the boolean is the fallback, reached only when the numeric pair is absent (`:825`). Not inverted. The comment block immediately above (`:808-815`) states the same rationale that is now verified in the code: numbers win because they give the exact window bound and let `PAND-03` clear on the render tick rather than inheriting Blizzard's own `OnUpdate`-deregistration lag (PANDEMIC.md unknown 1).

### S14 — no per-render allocation, no fresh `GetTime()` call

- `sed`-scoped `GetTime(` count inside `RenderBarContainer` (`Display.lua:1806-...`): `0`.
- `sed`-scoped `GetTime(` count inside `RenderIconContainer` (`Display.lua:2027-...`): `0`.
- Both render functions take `now` as a parameter (`Display.lua:1806`, `:2027`) and both call sites pass it straight through: `Display.lua:1891` — `ApplyPandemicBar(bar, slot.isMerged and ns:IsMergedEntryInPandemic(slot, now))`; `Display.lua:2134` — `ApplyPandemicIcon(icon, entry.isMerged and ns:IsMergedEntryInPandemic(entry, now), settings)`. Neither constructs a table, a closure, or a string — each is a single boolean expression passed as an argument.
- `SetPandemicShown` (`Display.lua:646-656`), `ApplyPandemicIcon` (`:661-689`), and `ApplyPandemicBar` (`:694-709`) allocate nothing themselves: every branch is a field read/compare, a `Show()`/`Hide()` call, or (only on the active+changed path) a `SetScale`/`SetAlpha` call with a primitive argument already stored in `settings`. `EnsurePandemicIconFX`/`EnsurePandemicBarFX` allocate exactly once per widget lifetime (the `CreateFrame` call itself, memoized via `icon.pandemicFX`/`bar.pandemicFX`), never per render pass.
- The stamp site (`ReadPandemicState`, `MergeMode.lua:756-806`) runs from `ns:RefreshMergeShownSlots`, which is event-driven (aura/merge refresh), not the render ticker — confirmed by its own header comment (`:754-755`, "Called only through `pcall(ReadPandemicState, entry)` from `ns:RefreshMergeShownSlots`") and by `48-01-SUMMARY.md`'s own characterization of that function as event-driven, never `OnUpdate`.

## Backwards Trace (rendered highlight -> `ns.mergeItemFrames`)

Written per `48-VALIDATION.md` § Verification Guidance, tracing backwards rather than forwards, as the guidance explicitly requires after Phase 47's blocker was a correctly-wired chain fed by a table nothing populated outside a narrow condition.

1. **`ApplyPandemicIcon(icon, active, settings)` / `ApplyPandemicBar(bar, active)`** (`Display.lua:661`, `:694`) — the render call sites (`Display.lua:2134`, `:1891`) compute `active` as `entry.isMerged and ns:IsMergedEntryInPandemic(entry, now)` / `slot.isMerged and ns:IsMergedEntryInPandemic(slot, now)`.
2. **`ns:IsMergedEntryInPandemic(entry, now)`** (`MergeMode.lua:816-826`) — reads only `entry.pandemicStart`, `entry.pandemicFinish`, `entry.pandemicActive`. No frame touch here; these are the three stamped fields from step 3.
3. **The three stamped fields** are written exclusively inside `ReadPandemicState(entry)` (`MergeMode.lua:756-806`), which is the only writer of `entry.pandemicActive`/`pandemicStart`/`pandemicFinish` in the codebase (confirmed by the earlier `grep -n` locating every occurrence of those three field names — all writes are inside this one function, all reads are inside `ns:IsMergedEntryInPandemic` plus the two `/tbt merge` debug dump sites at `:2377-2438`, which do not feed rendering).
4. **`ReadPandemicState` reads `ns.mergeItemFrames[entry.cooldownID]`** (`MergeMode.lua:757`) — a plain table lookup, no `EnumerateActive` walk, no viewer lookup, no `C_CooldownViewer` call of its own.
5. **What guarantees `ns.mergeItemFrames` is populated at the moment the stamp is read:** `ns:RefreshMergeShownSlots` wipes `ns.mergeItemFrames` exactly once, at the top of the whole pass (`MergeMode.lua:839`, `wipe(ns.mergeItemFrames)`), before any per-def work begins. Inside the same pass, for each `def`/viewer being processed, `pcall(CollectShownCooldownIDs, viewer)` (`:884`) runs and populates `ns.mergeItemFrames[cooldownID] = itemFrame` for every currently-shown item frame on that viewer (`:496`) — and this call happens **immediately before**, in program order within the same iteration, the per-entry loop (`:919` onward) that eventually calls `pcall(ReadPandemicState, entry)` (`:935`) for that same `def`'s entries. So for any entry whose `def` has a live `viewer`, `CollectShownCooldownIDs` has necessarily already run for that viewer, in this same pass, before `ReadPandemicState` reads `ns.mergeItemFrames` for one of its entries.
6. **What the stamp reads when `CollectShownCooldownIDs` has *not* run for a given `def`** (i.e. `viewer` is falsy at `:879`, so line `:884` is never reached for that `def`'s entries) — because `ns.mergeItemFrames` was wiped once at the top of the whole pass (`:839`) and never repopulated for that `def`'s cooldownIDs, `ns.mergeItemFrames[entry.cooldownID]` is simply absent (`nil`) for those entries. `ReadPandemicState`'s own early-return branch (`:758-767`) then fires: it explicitly clears all three stamps (`entry.pandemicActive = false`, `entry.pandemicStart = nil`, `entry.pandemicFinish = nil`) rather than leaving a stale `true` from a previous pass, logs the transition, and returns. This mirrors the exact precedent `48-VALIDATION.md` cites — the `seen == 0` no-answer case already handled at `entry.cdmShown` (`:924`) — applied here as "no cached frame this pass" rather than "no viewer answer this pass," with the same fail-safe direction (degrade to *not shown*, never *stuck shown*).
7. **One additional confirmation beyond what the plan asked for:** the render-side trailing-hide loops were checked for the same class of staleness. The icon container's trailing hide loop explicitly calls `ApplyPandemicIcon(pool[i], false, settings)` for every unused pooled icon (`Display.lua:2353`) because the icon FX is container-parented and `pool[i]:Hide()` alone does not hide it (`:2349-2352`). The bar container's trailing hide loop (`Display.lua:217-218` inside `RenderBarContainer`) calls only `pool[i]:Hide()` with no equivalent explicit clear — but this is correct, not an oversight: the bar FX is a true child of `bar` (`EnsurePandemicBarFX` parents directly to `bar`, `Display.lua:619`), so hiding the parent bar frame already makes the FX child render-invisible regardless of the FX's own `:IsShown()` state, and the next time that pooled bar is reused for any slot, the unconditional per-slot call at `Display.lua:1891` re-evaluates and corrects `SetPandemicShown`'s dirty-checked state against the new slot's actual pandemic status. No highlight can float over an empty cell in either container.

## Cleanup / Performance Review (scoped to this milestone's Waves 1-2 only)

Per CLAUDE.md's post-commit review requirement and PROJECT.md's "no refactors during cleanup phases" protection for pre-existing code, this review is scoped strictly to what Phase 48 (Waves 1-2) introduced. No issues found; findings below are confirmations, not fixes.

- **Render-path allocation:** confirmed under S14 above — zero table/closure/string allocation per render pass in either `ApplyPandemicIcon`/`ApplyPandemicBar` call site or their shared `SetPandemicShown` toggle; both FX frames are created exactly once per widget lifetime, lazily, memoized on `icon.pandemicFX`/`bar.pandemicFX`, never recreated per pass.
- **`ReadPandemicState` cannot raise out of its `pcall`, and cannot leave a stale stamp when the item frame is absent:** confirmed under the backwards trace above (point 6) — the early-return branch at `MergeMode.lua:758-767` always clears all three fields before returning when `ns.mergeItemFrames[entry.cooldownID]` is `nil`, and the whole function is invoked only via `pcall(ReadPandemicState, entry)` (`:935`), so even an unexpected raise inside the guarded section is contained and does not propagate into `ns:RefreshMergeShownSlots`'s wipe-then-refill pass.
- **A highlight cannot persist after its entry stops rendering:** confirmed under the backwards trace above (point 7) for both containers — icons via an explicit trailing clear, bars via the parent-hides-child frame relationship, with the unconditional per-slot call on every subsequent render pass as the correction path either way.
- **Debug-path hygiene (not requested by the plan, but adjacent and worth recording):** `LogPandemicStateChange` (`MergeMode.lua:702-...`) returns immediately when `ns.debugLogging` is false (the default) before touching `entry.pandemicActive` or building any string, and even with debug logging on it only builds and concatenates the debug string on an actual state transition (`wasActive == isActive` short-circuits first) — no string work happens on every stamp, only on a change.
- **Nothing to fix.** No dead code, no redundant per-frame work, and no duplication was found in what this milestone added. `Core.lua` remains byte-unchanged (`wc -l` = `1367`, `git diff --stat -- Core.lua` empty).

## Task 2 — In-Game Phase Gate (G0-G6): NOT STARTED — AWAITING HUMAN VERIFICATION

**This checkpoint requires a human to play on two WoW clients and observe rendered behavior. It was not attempted, not simulated, and no outcome is asserted anywhere in this document.** No PAND requirement (PAND-01 through PAND-05) is closed by this plan. Every check below is recorded as `human_needed`, per `48-03-PLAN.md`'s own instruction that an unrun check is `human_needed`, not a pass.

**Run order (Forever first, then retail; run every check below on Forever, then repeat all of them on retail per G6):**

| Order | Gate | Requirement | What it proves | Status |
|---|---|---|---|---|
| 1 | **G0** | — (unlocks the rest) | Enables `/tbt debug`; answers PANDEMIC.md's five unknowns — whether `PandemicIcon` clears promptly or lingers, whether the two timestamps are secret in/out of combat, whether the `PandemicTime` capability gate fires at all on Forever, and whether it works for a target-debuff entry. **Must run first — it decides whether the rest is even observable and whether the numeric refinement path (S8's precedence) is load-bearing or a nicety.** | human_needed |
| 2 | **G1** | PAND-01 | TBT's mirrored icon shows the highlight when the merged entry is inside its pandemic window | human_needed |
| 3 | **G2** | PAND-02 | TBT's mirrored bar shows the highlight, border in front of the fill (confirms S13's frame-level bump renders correctly in practice) | human_needed |
| 4 | **G3** | PAND-03 | The highlight clears when the window ends on its own; a lingering highlight is a timed measurement (unknown 1 surfacing visually), not automatically a FAIL | human_needed |
| 5 | **G4** | PAND-04 | **Cannot be skipped.** Exercises the player's real Cooldown Manager after the highlight work — open it, change a setting, drag an entry, keep playing. Any Lua error or an unresponsive CDM until `/reload` means a frame was tainted. Taint is sticky for the session; a CDM misbehaving "a while later" is still this phase's fault. **On a FAIL here, the phase stops and is reported immediately — no fix attempted in this plan, per the plan's own instruction that a taint failure is Plan 01's surface, not this one's.** | human_needed |
| 6 | **G5** | PAND-05 | An item-backed merged entry (trinket/potion/healthstone, excluded from pandemic at Blizzard's own source via `IsItem()`) renders exactly as before — no highlight, no error, no stuck highlight after a container shrinks | human_needed |
| 7 | **G6** | — | Repeat G1-G5 on Midnight retail; report any difference from Forever, especially in G0's `secret=` columns | human_needed |

Nothing above should be read as evidence that any check passed, failed, or was even partially observed. This table exists to hand the check list, in the mandated order, to whoever runs Task 2 next — most likely a freshly spawned continuation agent presenting these checks to the user, per the plan's `checkpoint:human-verify` gate.

## Deviations from Plan

None — plan executed exactly as written. Task 1's verify command was split across multiple `Bash` invocations rather than run as one literal `&&`-chained shell line, solely because `grep -c` returning a zero count exits with status `1` and would otherwise abort the chain early — this is the exact gotcha `48-VALIDATION.md`'s Test Infrastructure section and this plan's own `<read_first>` warn about, not a deviation from what was checked. Every clause specified in the plan's `<verify><automated>` block was run and passed; none was skipped, weakened, or worked around by modifying source.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 14 static gates pass; the phase is deployed to every installed WoW client, including the Forever beta Task 2 needs first.
- **Nothing is ready to be marked complete.** Task 2 (G0-G6) is the sole remaining step in this phase and the sole evidence path for PAND-01 through PAND-05 — there is no automated substitute, by design (this project has no test runner).
- Whoever resumes this plan should present the Task 2 table above to the user in the stated order, honor a G4 FAIL as an immediate phase-stop with no in-plan fix attempt, and record every result verbatim (including any check the user does not run, as `human_needed`) before any PAND requirement is marked closed in REQUIREMENTS.md.

---
*Phase: 48-pandemic-highlight-merge-mode*
*Completed: 2026-09-24*

## Self-Check: PASSED

- FOUND: `.planning/phases/48-pandemic-highlight-merge-mode/48-03-SUMMARY.md`
- FOUND: commit `b2c62a5` (docs: record consolidated sweep)
- FOUND: `Core.lua` byte-unchanged (`wc -l` = 1367)
- CONFIRMED: `CHANGELOG.md`, `.planning/STATE.md`, `.planning/ROADMAP.md` show zero diff (untouched)
