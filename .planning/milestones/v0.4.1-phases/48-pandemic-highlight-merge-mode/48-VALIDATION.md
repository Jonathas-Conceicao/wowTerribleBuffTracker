---
phase: 48
slug: pandemic-highlight-merge-mode
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-24
---

# Phase 48 — Validation Strategy

> `.planning/research/PANDEMIC.md` is required reading. This file is the contract.

---

## Test Infrastructure

**No test runner exists, and none is planned.** The only runtime is the game client. Verification is
static assertion plus in-game human checks.

| Property | Value |
|----------|-------|
| **Framework** | none |
| **Config file** | none |
| **Quick run command** | `stylua .` (formatting gate, not a test) |
| **Full suite command** | none — the phase gate is the in-game list below |
| **Estimated runtime** | static: seconds. In-game: user-driven |

Do not invent a test command. **Scope every gate to the diff, not to the file** — three gates broke
earlier in this milestone because a whole-file grep matched pre-existing code it was never meant to
see (Phase 46's ordering gate, Phase 47's flavour-token gate, and the protected debug block, which
legitimately contains the very `hooksecurefunc` token a naive "no hooks" gate would reject).

---

## Static Assertions

| ID | Check | Method | Proves |
|----|-------|--------|--------|
| S1 | stylua clean and idempotent | `stylua .` twice, `git diff --stat` empty after each | No formatting drift. Run twice: a Phase 47 comment placement made stylua **non-idempotent**, duplicating the CRLF terminator on each run |
| S2 | Line endings held | `git ls-files --eol <touched files>` reports `w/crlf` | `git diff` cannot see a reflow |
| S3 | No flavour check **introduced** | `test "$(git diff <base>..HEAD -- <files> \| grep '^+' \| grep -cE 'buildInterfaceVersion\|GetBuildInfo\|wow_classic')" = "0"` | One code path. **Diff-scoped:** `Core.lua:565-576` is Phase 37's sanctioned one-off and a whole-file grep can never return zero |
| S4 | **No CDM mixin method called** | Source read of every new line touching an `itemFrame`: only plain field reads (`.PandemicIcon`, `.pandemicStartTime`, `.pandemicEndTime`) and permitted C widget getters. No `itemFrame:IsInPandemicTime()`, `:ShowPandemicStateFrame()`, `:CheckSetPandemicAlertTriggerTime()` | **PAND-04.** The locked constraint — measured to taint the frame permanently, surviving combat, clearing only on `/reload` |
| S5 | **No write to a CDM frame, no reparent into one** | Source read: nothing assigns a field on an `itemFrame`, nothing passes one as a `CreateFrame` parent | The locked constraint, clauses 2 and 3 |
| S6 | **`viewer.pandemicIconPool` never touched** | `test "$(git diff <base>..HEAD \| grep '^+' \| grep -c 'pandemicIconPool')" = "0"` | That pool is CDM-owned and was never audited or admitted. `:Release` in particular is a write against a CDM-owned resource |
| S7 | Secret guard ordering | The two timestamps are read `issecretvalue(v)` before `type(v)`, matching `MergeMode.lua:650-656` | The locked rule. `type()` reports `"number"` for a secret number |
| S8 | Precedence not inverted | Source read: readable numbers win; the boolean is the fallback | Inverting it discards the exact window bounds whenever they are available |
| S9 | Stamp is `pcall`-wrapped | Source read of the addition to `ns:RefreshMergeShownSlots` | **This pass wipes the shown-slot arrays before refilling.** Any raise partway through leaves every merged container empty until the next aura event — which is exactly what a `GetAuraDataByIndex` raise did on 2026-09-22 |
| S10 | Template creation `pcall`-guarded | Source read of both `CreateFrame(..., "CooldownPandemicFXTemplate")` / `...BarFXTemplate` calls | **PAND-05.** No way exists to introspect a virtual template ahead of use; degrade to no highlight |
| S11 | Highlight frames are TBT-owned | Source read: every highlight frame is created by TBT and parented to a TBT widget, never acquired from a Blizzard pool | What makes `Show`/`Hide`/`SetPoint`/`SetFrameLevel` on them taint-free |
| S12 | Debug log untouched | `git diff Core.lua` shows no edit inside the `pendingItemCasts` / `LogPlayerCast` / `LogItemUse` block | Protected feature. A new dump reuses the `ns.debugLogging` gate from a new call site |
| S13 | Bar frame level bumped | Source read: `SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)` | Omitting it misorders the border behind the bar fill, exactly as it would in Blizzard's own UI |
| S14 | No per-render allocation | Source read of the stamp site and the render path | `ns:RefreshMergeShownSlots` runs on merge refresh; the render path runs on a ticker |

S4, S5, S6 and S11 together are PAND-04. They are the highest-value gates in this phase: a taint
violation is invisible until it breaks the player's Cooldown Manager for the rest of the session.

---

## In-Game Human Checks (phase gate)

Forever first, then retail. **G0 must run first** — it answers the unknowns that decide whether the
rest is even observable.

| ID | Requirement | Check | Pass condition |
|----|-------------|-------|----------------|
| G0 | — | Enable `/tbt debug`. Track a refreshable DoT/HoT on a merged CDM entry and recast it inside the refresh window. Read the dump | Answers PANDEMIC.md's five unknowns: whether `PandemicIcon` clears promptly, whether the two timestamps are secret in combat, whether `CanTriggerAlertType` gates on capability or player preference, whether Forever fires the mechanic at all, and whether it works for a target-debuff entry |
| G1 | PAND-01 | With a merged entry inside its pandemic window, look at TBT's mirrored **icon** | The highlight shows |
| G2 | PAND-02 | Same entry, TBT's mirrored **bar** | The highlight shows, and its border sits **in front of** the bar fill, not behind it (S13) |
| G3 | PAND-03 | Let the window end without triggering any other aura event | The highlight clears. If it lingers, that is unknown 1 — record how long, it decides whether the numeric path is load-bearing |
| G4 | PAND-04 | After G1–G3, use Blizzard's Cooldown Manager normally — open it, change a setting, drag an entry | It behaves normally. **Any Lua error, or a CDM that stops responding until `/reload`, means a frame was tainted — stop and report immediately** |
| G5 | PAND-05 | Find an entry where the state cannot be observed (an item-backed entry — trinket, potion, healthstone — which Blizzard excludes from pandemic at source via its `IsItem()` guard) | Renders exactly as today: no highlight, no error, no stuck highlight |
| G6 | — | Repeat G1–G5 on Midnight retail | Same behaviour. Forever presence is HIGH confidence; Forever *behaving* the same is only MEDIUM |

G4 is the one that cannot be skipped. Taint does not announce itself — it shows up as the player's
own Cooldown Manager quietly breaking later in the session.

---

## Per-Task Verification Map

Filled by the planner.

| Task ID | Plan | Wave | Requirement | Static gate | In-game gate | Status |
|---------|------|------|-------------|-------------|--------------|--------|
| 48-01 T1 stamp + resolver | 48-01 | 1 | PAND-03, PAND-04, PAND-05 | S1-S9, S12, S14 | G0, G3, G4, G5 | planned |
| 48-01 T2 debug dumps | 48-01 | 1 | PAND-04 (instrument for G0) | S1-S4, S6, S12 | G0 | planned |
| 48-02 T1 FX frames + toggles | 48-02 | 2 | PAND-01, PAND-02, PAND-05 | S1-S3, S10-S14 | G1, G2, G5 | planned |
| 48-02 T2 render wiring | 48-02 | 2 | PAND-01, PAND-02, PAND-03 | S1-S4, S10-S12, S14 | G1, G2, G3, G5 | planned |
| 48-03 T1 consolidated sweep + deploy | 48-03 | 3 | none (closes nothing) | S1-S14 | - | planned |
| 48-03 T2 in-game gate (blocking) | 48-03 | 3 | PAND-01..05 | - | G0-G6 | planned |

S4, S5, S8, S11 and S14 are recorded in that table as command gates where a grep can carry them
and as **source reads** where it cannot: a grep proves the five named mixin methods are absent,
only a read proves a sixth was not invented. 48-03 Task 1 performs and records both halves.

---

## Verification Guidance

**Trace backwards, not forwards.** Phase 47's blocker was a correctly-wired chain fed by a table
nothing populated outside a narrow condition; read forwards from the entry point it looked sound,
and both the plan check and the verification passed over it.

Apply that here: start from the rendered highlight and trace back to `ns.mergeItemFrames`, then ask
what guarantees that table is populated at the moment the stamp is read — specifically whether
`CollectShownCooldownIDs` has necessarily run, and what the stamp reads when it has not. The
`seen == 0` no-answer case already handled at `MergeMode.lua:786` is the precedent for how this
codebase treats "no viewer, or a viewer with no item frames".

---

## Environment Availability

| Dependency | Required by | Available |
|------------|-------------|-----------|
| stylua | S1 | yes — bare, from repo root |
| git `ls-files --eol` | S2 | yes |
| WoW Forever beta | G0–G5 | yes — build 1.60.1 |
| Midnight retail | G6 | yes |
| `wow-ui-source` snapshot | citation only | yes — read-only; a snapshot cannot prove absence |

---

## Security Domain

Unchanged. Single-player client addon, no network surface, no auth, no server-side trust boundary.

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Secret-value type confusion on the two timestamps | Tampering (of TBT's own logic) | S7 |
| **CDM frame taint** — the real risk in this phase | Tampering (taint propagation) | S4, S5, S6, S11, verified in game by G4. Permanent for the session, clearing only on `/reload` |
