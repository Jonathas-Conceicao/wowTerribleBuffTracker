---
status: passed
gate_progress: "retail 2026-09-24 — PAND-01, 02, 03, 05 confirmed in game; PAND-04 closed by user decision, not tested; Forever untested (server down), carried to Phase 51"
phase: 48-pandemic-highlight-merge-mode
verified: 2026-09-24T00:00:00Z
score: 4/4 static-provable truths verified; 0/4 success criteria closeable without in-game evidence
overrides_applied: 0
human_verification:
  - test: "G0 — /tbt debug, cast a refreshable DoT/HoT on a merged CDM entry, recast it inside the refresh window, read the PANDEMIC chat lines and the /tbt merge pandemic rows"
    expected: "Answers PANDEMIC.md's five unknowns — verbatim OFF-line GetTime() vs last finish value (unknown 1), secret=/type= columns in and out of combat (unknown 2), the PandemicTime alertCap column (unknowns 3/4), and one run on a target-debuff entry (unknown 5)"
    why_human: "Requires a live game session; no test runner exists. Must run first — it decides whether the numeric route (S8's precedence) is load-bearing or cosmetic, and unlocks meaningful interpretation of G1-G3"
  - test: "G1 — with a merged entry inside its pandemic window, look at TBT's mirrored icon"
    expected: "PAND-01: Blizzard's animated pandemic border shows on TBT's icon, same as on the CDM's own icon"
    why_human: "Visual rendering in a real Cooldown Manager; cannot be proven by source inspection"
  - test: "G2 — same entry, TBT's mirrored bar"
    expected: "PAND-02: highlight shows and its border sits in front of the bar fill, not behind it"
    why_human: "Visual z-order in a real render; the frame-level bump (S13) is statically present but its visual effect is unproven"
  - test: "G3 — let the window end on its own, no other aura event"
    expected: "PAND-03: highlight clears at or near the true window end. A lingering highlight is a timed measurement (surfaces unknown 1 visually), not automatically a FAIL; never clearing at all is a FAIL"
    why_human: "Timing behavior over a live game session"
  - test: "G4 — after G1-G3, use Blizzard's Cooldown Manager normally (open it, change a setting, drag an entry, keep playing a few minutes) — UNSKIPPABLE"
    expected: "PAND-04: CDM behaves normally throughout. Any Lua error, or a CDM that stops responding until /reload, means a frame was tainted"
    why_human: "Taint does not announce itself in source or static grep — it is a runtime property of the player's live Cooldown Manager, sticky for the session, clearing only on /reload. This is the highest-consequence, least-skippable check in the phase"
  - test: "G5 — find an entry whose pandemic state cannot be observed (item-backed merged entry: trinket, potion, healthstone), including after a container has shrunk"
    expected: "PAND-05: renders exactly as before — no highlight, no error, no highlight stuck from a previously pooled slot"
    why_human: "Requires observing pooled-widget reuse and absence-of-effect in a live render; cannot be proven by grep alone"
  - test: "G6 — repeat G1 through G5 on Midnight retail"
    expected: "Same behavior as Forever, especially G0's secret=/type= columns. Forever code presence is HIGH confidence; Forever behaving the same as retail is only MEDIUM — retail's secret-value behavior on the two timestamps has never been measured"
    why_human: "Cross-client behavioral parity cannot be inferred from a single-client source tree"
---

# Phase 48: Pandemic Highlight in Merge Mode Verification Report

**Phase Goal:** A merged CDM entry inside its pandemic refresh window carries Blizzard's own
highlight onto TBT's mirrored icon and bar, read without tainting a CDM frame.

**Verified:** 2026-09-24
**Status:** human_needed
**Re-verification:** No — initial verification

## Framing

This project has no test runner and none is planned; the only runtime is the game client. Static
source inspection can prove the code is *shaped* correctly — no forbidden mixin call, correct guard
ordering, correct anchors — but it cannot prove a highlight renders, that it clears on time, or the
one thing that matters most: that no CDM frame was tainted. Taint is a runtime property of the
player's live Cooldown Manager; it does not appear in a diff. 48-03's Task 2 (G0-G6) is a blocking
human checkpoint that was **deliberately not attempted** per its own SUMMARY, and it is the *only*
evidence path for all five PAND requirements per `48-03-PLAN.md`'s own acceptance criteria ("This
checkpoint is the only evidence path for all five PAND requirements... a static sweep cannot see a
rendered frame or a tainted one").

I independently re-ran the load-bearing static checks against the shipped code rather than trusting
48-03-SUMMARY.md's reported output. All of them hold.

## Goal Achievement

### Observable Truths (static, independently re-verified)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Pandemic state is read only through plain table-field reads on a cached CDM item frame | VERIFIED | `MergeMode.lua:756-806` (`ReadPandemicState`) reads `ns.mergeItemFrames[entry.cooldownID]` (`:757`), then only `itemFrame.PandemicIcon` (`:776`), `.pandemicStartTime` (`:784`), `.pandemicEndTime` (`:785`) — zero `itemFrame:` method-call syntax in the function; the sole `itemFrame:IsShown()` call in the file (`:493`) is pre-existing, in `CollectShownCooldownIDs`, a plain C widget getter permitted by the file's own rule |
| 2 | No Blizzard mixin method is called on a CDM frame; `viewer.pandemicIconPool` never touched | VERIFIED | `grep -nE 'IsInPandemicTime\|ShowPandemicStateFrame\|HidePandemicStateFrame\|CheckSetPandemicAlertTriggerTime\|SetPandemicAlertTriggerTime'` returns zero matches in `MergeMode.lua`/`Display.lua`. `pandemicIconPool` returns zero matches in both files. The two `SetLayoutData` occurrences (`MergeMode.lua:18`, `:1651`) are comment lines documenting the rule; confirmed pre-existing via `git log -S"SetLayoutData is never called"` — present since `6ea1ab9`/`f0c8e35`, both pre-dating this milestone, not added by Phase 48 |
| 3 | A raise anywhere in the pandemic read cannot empty the merged containers | VERIFIED | `pcall(ReadPandemicState, entry)` at `MergeMode.lua:935`, unconditional per entry, inside `ns:RefreshMergeShownSlots`'s wipe-then-refill pass, sibling to and separate from `pcall(ResolveMergedAuraTiming, entry)` — comment at `:926-934` states the structural reason (2026-09-22 precedent) |
| 4 | Both timestamps guarded `issecretvalue()` before `type()`; unreadable pair degrades to the boolean | VERIFIED | `MergeMode.lua:786-797` — `issecretvalue(startTime)` and `issecretvalue(endTime)` both checked before `type(...) == "number"`, all-or-nothing stamp (`entry.pandemicStart`/`Finish` both set or both nil) |
| 5 | Readable numbers decide the answer; boolean is the fallback, never inverted | VERIFIED | `MergeMode.lua:816-826` (`ns:IsMergedEntryInPandemic`) — numeric branch checked and returned first (`:821-822`), `entry.pandemicActive` reached only as fallback (`:825`) |
| 6 | A render-time resolver answers "in window right now" from plain numbers and TBT's own `GetTime()` | VERIFIED | Same function; takes `now` as a parameter, never calls `GetTime()` itself; `Display.lua` passes the existing per-tick `now` at both call sites (`:1891`, `:2134`), confirmed zero `GetTime(` occurrences inside `RenderIconContainer`/`RenderBarContainer` bodies |
| 7 | `/tbt debug` dumps carry enough to answer PANDEMIC.md's five unknowns | VERIFIED (instrument exists; unknowns themselves NOT answered) | `LogPandemicStateChange` (`MergeMode.lua:702-743`) prints on state change with `t=`, `start(secret=,type=,val=)`, `finish(...)`; `/tbt merge` pandemic block (`:2374-2444`) adds `frame=`, `icon=`, `answer=`, `route=`, `alertCap=` including the guarded `C_CooldownViewer.GetValidAlertTypes` capability check (`:2408`). The instrument is real and correctly gated on `ns.debugLogging`, but **no one has run it** — the five unknowns remain unanswered data, not just unconfirmed |
| 8 | Both `CreateFrame(..., "CooldownPandemic*")` calls are `pcall`-guarded, degrading to no highlight | VERIFIED | `Display.lua:582` and `:619`, both `pcall(CreateFrame, ...)`, both stamp `_pandemicFailed` on failure and return `nil` rather than retry every tick |
| 9 | Bar frame level bumped one above `bar.statusBar`, so the border renders in front of the fill | VERIFIED (statically only — visual result NOT observed) | `Display.lua:635` — `fx:SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)`, anchored to `bar.statusBar` (the fill sub-region) with Blizzard's `-9/+10` offsets (`:630-631`) |
| 10 | Icon FX parented to the container (not the icon), with a trailing clear so no highlight persists after an entry stops rendering | VERIFIED | `Display.lua:577` (`icon:GetParent()`), commented reasoning about the Tracked-Buffs hidden-icon hazard (`:561-568`); trailing hide loop at `Display.lua:2347-2354` calls `ApplyPandemicIcon(pool[i], false, settings)` alongside `pool[i]:Hide()`. Bar FX is a true child of `bar` (`:619`), so its trailing loop needs no equivalent clear — confirmed correct, not an oversight |
| 11 | `Core.lua` byte-unchanged | VERIFIED | `wc -l Core.lua` = `1367`; `git status --porcelain -- Core.lua` empty |
| 12 | No stray debt markers in touched files | VERIFIED | Zero `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` matches in `MergeMode.lua`/`Display.lua` |
| **G0-G6 (the actual goal)** | **A merged entry's highlight renders, clears correctly, and no CDM frame is tainted, on both Forever and retail** | **NOT VERIFIED — NOT RUN** | 48-03-SUMMARY.md Task 2 section, verbatim: "This checkpoint requires a human to play on two WoW clients and observe rendered behavior. It was not attempted, not simulated, and no outcome is asserted anywhere in this document." No PAND requirement is closed; `REQUIREMENTS.md:139-143` still lists all five as "Not started" |

**Score:** 12/12 statically-provable truths verified against the shipped code (independently re-checked, not taken from the SUMMARY). 0/4 roadmap success criteria are closeable — every one of them is an in-game rendering or taint observation, and G0-G6 were not run.

### Backwards Trace (independently re-checked, not trusted from SUMMARY)

Traced from the render call sites back to the frame cache, per `48-VALIDATION.md`'s explicit
instruction (the Phase 47 lesson — a correctly-wired chain fed by an unpopulated table read as sound
forwards):

1. `Display.lua:1891` / `:2134` — `ApplyPandemicBar(bar, slot.isMerged and ns:IsMergedEntryInPandemic(slot, now))` / `ApplyPandemicIcon(icon, entry.isMerged and ns:IsMergedEntryInPandemic(entry, now), settings)`.
2. `ns:IsMergedEntryInPandemic` (`MergeMode.lua:816-826`) reads only the three stamped fields — no frame touch.
3. The three fields are written exclusively inside `ReadPandemicState` (`MergeMode.lua:756-806`).
4. `ReadPandemicState` reads `ns.mergeItemFrames[entry.cooldownID]` (`:757`) — a plain table lookup.
5. **What guarantees population:** `ns:RefreshMergeShownSlots` wipes `ns.mergeItemFrames` once at the top of the whole pass (`:839`). Inside the same pass, per `def`/viewer, `pcall(CollectShownCooldownIDs, viewer)` (`:884`) populates `ns.mergeItemFrames[cooldownID] = itemFrame` for every currently-shown item frame (`:493-497`), and this runs in program order **immediately before** the per-entry loop (`:919` onward) that calls `pcall(ReadPandemicState, entry)` (`:935`) for that same `def`'s entries. Confirmed directly by reading `MergeMode.lua:845-935` — this is not taken from the SUMMARY's narrative.
6. **What the stamp reads when `CollectShownCooldownIDs` has not run for a `def`** (i.e., `viewer` is falsy at `:879`): `ns.mergeItemFrames[entry.cooldownID]` is `nil` (never repopulated after the pass-wide wipe), so `ReadPandemicState`'s early-return branch (`:758-767`) fires and explicitly clears all three stamps (`pandemicActive = false`, `pandemicStart`/`Finish = nil`) rather than leaving a stale `true`. This is the fail-safe direction PAND-05 requires.

Trace holds. This is a genuinely different chain shape from Phase 47's blocker (that table was populated only under a narrow, easily-missed condition; here population is unconditional per pass for any `def` with a live viewer, and the no-answer case degrades safely) — but the reasoning had to be checked, not assumed, and I checked it against the actual code rather than accepting the SUMMARY's copy of the same argument.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MergeMode.lua: ReadPandemicState` | pcall'd per-entry stamp | VERIFIED | `:756-806`, exactly one definition |
| `MergeMode.lua: ns:IsMergedEntryInPandemic` | render-time resolver | VERIFIED | `:816-826`, exactly one definition |
| `MergeMode.lua: LogPandemicStateChange` + `/tbt merge` block | debug instrument for the 5 unknowns | VERIFIED (exists, correct) but UNEXERCISED | `:702-743`, `:2374-2444` |
| `Display.lua: EnsurePandemicIconFX/BarFX` | pcall-guarded lazy creators | VERIFIED | `:569-640` |
| `Display.lua: ApplyPandemicIcon/Bar`, `SetPandemicShown` | dirty-checked toggles | VERIFIED | `:646-709` |
| `Display.lua` render wiring | one call/slot in each render function | VERIFIED | `:1891`, `:2134`, plus trailing clear `:2353` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `ns:RefreshMergeShownSlots` | `ReadPandemicState` | `pcall(ReadPandemicState, entry)` | WIRED | `:935`, unconditional per entry |
| `ReadPandemicState` | `ns.mergeItemFrames` | cached frame lookup | WIRED | `:757`, populated by `CollectShownCooldownIDs` earlier in the same pass (`:884`, `:497`) |
| `RenderIconContainer`/`RenderBarContainer` | `ns:IsMergedEntryInPandemic` | one call per slot per tick | WIRED | `:2134`, `:1891` |
| `EnsurePandemicBarFX` | `bar.statusBar` | anchor + frame-level bump | WIRED | `:630-631`, `:635` |
| **The actual highlight** | **the player's screen** | **rendering in the live game client** | **UNVERIFIED** | No test runner; only G1/G2 can observe this |
| **`ReadPandemicState`'s frame access** | **CDM frame taint** | **runtime property of the live Cooldown Manager** | **UNVERIFIED — the highest-consequence link in the phase** | Static gates (S4/S5/S6/S11) prove the code is *shaped* to avoid taint; only G4 can observe whether it actually did |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| PAND-01 | Highlight on the mirrored icon | NEEDS HUMAN (G1) | Code shaped correctly (`Display.lua:2134`, `:569-604`); not rendered/observed |
| PAND-02 | Highlight on the mirrored bar, border in front of fill | NEEDS HUMAN (G2) | Code shaped correctly (`:1891`, `:611-640`); visual z-order not observed |
| PAND-03 | Clears at window end without an unrelated aura event | NEEDS HUMAN (G3) | Numeric-precedence render tick resolves this in theory (`MergeMode.lua:816-826`); actual timing/lag not observed |
| PAND-04 | Never taints a CDM frame | NEEDS HUMAN (G4) — **unskippable** | S4/S5/S6/S11 pass statically; taint is a runtime-only property that static analysis structurally cannot observe |
| PAND-05 | Unobservable state renders exactly as today | NEEDS HUMAN (G5) | `pcall` guards and dirty-checked clears exist and are shaped correctly; absence-of-effect on a live pooled widget not observed |

No requirement is ORPHANED — all five map to plan-declared `requirements:` frontmatter across 48-01/02/03 and to `REQUIREMENTS.md:74-80,139-143`, which still lists all five as "Not started."

### Anti-Patterns Found

None. Zero debt markers, zero placeholder/TODO/HACK strings, zero empty-return stubs in the touched
files. `stylua`/CRLF gates confirmed independently (`git ls-files --eol` reports `w/crlf` for all
three files).

### Behavioral Spot-Checks

Skipped. This addon has no runnable entry point outside the WoW client — there is nothing a
sandboxed shell can execute that would exercise `CreateFrame`, `C_CooldownViewer`, or Blizzard's
CDM. This is exactly why the phase's own validation strategy routes all behavioral proof through
G0-G6.

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention exists in this repository (`tools/TBTProbe/Probe.lua` is
an in-game diagnostic tool, not a shell-runnable probe). No probe declared in PLAN/SUMMARY/VALIDATION
for this phase. N/A.

### Human Verification Required

See YAML frontmatter `human_verification` — G0 through G6, in run order, Forever first then retail,
copied faithfully from `48-VALIDATION.md`'s authoritative table and `48-03-PLAN.md`'s Task 2. **G0
must run first** (it decides whether the numeric-precedence path is load-bearing or a nicety and
unlocks interpreting G1-G3). **G4 is flagged unskippable** — it is the only check that exercises the
real Cooldown Manager, and a taint violation does not announce itself anywhere a static tool can see;
it manifests later, silently, and only clears on `/reload`.

### Gaps Summary

There are no code-shape gaps: every static, source-provable claim in 48-01/02/03's SUMMARYs was
independently re-verified against the shipped code in this session (not taken on the SUMMARYs' word)
and holds. `MergeMode.lua` and `Display.lua` are correctly wired, the no-taint rule's four clauses
are respected by inspection, the debug instrument for PANDEMIC.md's five unknowns exists and is
correctly gated, and the backwards trace from the rendered highlight to `ns.mergeItemFrames` resolves
cleanly with a fail-safe default.

What is missing is not code — it is the entire evidence path the phase's own validation strategy
requires: the in-game G0-G6 checkpoint. None of the four roadmap success criteria are actually
"true" in an observable sense yet; they are only "shaped to become true," which is a different claim.
Per this phase's own documents, that is the honest state: `48-03-PLAN.md` states outright that "No
PAND requirement closes until Task 2's report comes back," and `48-03-SUMMARY.md` self-reports zero
attempt at Task 2. This verification agrees with that self-report after independently confirming the
static half is genuinely complete, not merely claimed.

---

_Verified: 2026-09-24_
_Verifier: Claude (gsd-verifier)_

---

## In-Game Gate Results — retail, 2026-09-24

Run on a Restoration Druid, after a Frost mage attempt produced nothing: that spec has no
player-refreshable aura, so `alertCap=no` on every entry. See `PANDEMIC.md`'s measured block.

| Gate | Req | Result | Evidence |
|------|-----|--------|----------|
| G1 | PAND-01 | **PASS** | Highlight renders on TBT's own mirrored icon. Confirmed by the user on Moonfire (DoT, in combat) and Entangling Roots (target debuff, out of combat) |
| G2 | PAND-02 | **PASS** | Lifebloom renders as a **bar**, and its highlight works — so the bar mirror path, including the `SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)` bump that keeps the border in front of the fill, is exercised and correct |
| G3 | PAND-03 | **PASS** | Moonfire ON at `t=86709.772`, OFF at `t=86714.589` — ~4.8s, no intervening recast, no unrelated aura event. The `OnUpdate`-staleness risk did not materialise |
| G4 | PAND-04 | **NOT TESTED — accepted by user decision, 2026-09-24** | "PAND-04 is not a real use case, I won't be testing this, any behaviour is fine by me." The risk was stated plainly beforehand (taint is silent until the player's own Cooldown Manager breaks for the session) and the user accepted it. No taint was observed across a long session of reloads and CDM interaction, but that is absence of evidence, not evidence |
| G5 | PAND-05 | **PASS** | Two independent degrade paths. Item-backed entries (`Combat Potion`, `Emerald Coach's Whistle`) render normally with `answer=false` and no error — Blizzard excludes them at source via `IsItem()`. And in combat, with both timestamps secret, entries fell back to `route=boolean` rather than erroring or sticking |
| G6 | — | **NOT RUN** | Forever was down |

**The load-bearing finding.** In combat the numeric pair is **secret** and the feature runs
`route=boolean`; out of combat it runs `route=numbers` with real values. Both halves of the kickoff
decision do the job they were chosen for, and a numbers-only implementation would have been dead in
exactly the situation the highlight exists for.

Measured in combat on Moonfire: `start(secret=true,type=number,val=nil)`. `secret=true` alongside
`type=number` is the locked `issecretvalue()`-before-`type()` ordering earning its keep — the
reverse would have passed a secret into the comparison.

### Third aura polarity, and concurrency

A later run added **Lifebloom** — a HoT on a *friendly* target, with no harmful component. It
highlighted correctly, and it captured both routes on one spell:

```
18:22:00  Lifebloom ON   start(secret=false, val=86998.98)  finish(val=87003.48)   out of combat, route=numbers
18:22:30  Lifebloom ON   start(secret=true,  val=nil)                              in combat,     route=boolean
```

So all three aura polarities are confirmed: **friendly HoT** (Lifebloom), **target debuff**
(Entangling Roots), **DoT** (Moonfire) — and all three tracked independently and concurrently in
the same fight, which `PANDEMIC.md`'s unknown 5 only asked about for a single target-debuff case.

### Known cosmetic artifact: duplicate ON after a mirror rebuild

```
18:22:34  Moonfire ON   t=87033.075
18:22:38  Moonfire ON   t=87036.94     <- duplicate, no OFF between
18:22:39  Moonfire OFF  t=87037.755
```

`Tiger Dash` was cast at 18:22:38. A shapeshift fires `SPELLS_CHANGED`, which rebuilds the mirror,
and a rebuild **replaces the entry tables** (`MergeMode.lua:394`, "Every rebuild here replaces the
entry tables the shown-slot arrays hold references to"). The fresh entry carries no pandemic stamp,
so `wasActive` reads false and the next pass logs `ON` again.

**Not fixed, deliberately.** The rebuild ends by queueing the shown-slot pass through
`C_Timer.After(0)`, so the stamp is restored within a frame and the visible effect is at most a
one-frame flicker of the highlight. Carrying the stamp across a rebuild would couple the pandemic
state to the mirror's table lifecycle to buy something imperceptible. Recorded so a future reader
does not mistake the duplicate log line for a state-machine bug.

### Final status — `passed`, 2026-09-24

PAND-01, PAND-02, PAND-03 and PAND-05 are confirmed in game on retail. PAND-04 is closed by user
decision rather than by evidence, and its row says so — it is not a gate that was quietly waived.

Lifebloom turned out to be a **bar**, which closed PAND-02 without a further test: the icon and bar
mirrors were both exercised by the three auras already in use.

**Forever remains untested** — the server was down for the whole session. That is not a gap in this
phase's implementation (both flavours ship the identical pandemic code, verified line-for-line
against `BigWigsMods/WoWUI` branch `forever-beta`) but it is unobserved behaviour, and it belongs to
Phase 51's Forever review pass.
