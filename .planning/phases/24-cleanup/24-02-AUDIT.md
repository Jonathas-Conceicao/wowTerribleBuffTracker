# Phase 24 Hot-Path Audit

**Scope:** Read-only audit of three v0.2.4-touched hot paths, per CONTEXT.md D-04.
**Audit type:** Static code inspection. No runtime profiling (out of scope for v0.2.4 cleanup).
**Output consumer:** Plan 24-03 reads the `## CHANGELOG Input` section at the bottom of this file and copies it verbatim into the CHANGELOG.md v0.2.4 entry.

---

## Path 1: Display per-widget icon cache

**Sites found (Display.lua):**
- Line 478: `if bar.cachedSpellID ~= resolvedSpellID then` — compare (bar placeholder/active path)
- Line 479: `bar.cachedSpellID = resolvedSpellID` — write (bar miss branch)
- Line 480: `bar.cachedIcon = resolvedSpellID and ns:GetSpellIcon(resolvedSpellID) or 134400` — write (bar miss branch)
- Line 482: `bar.icon:SetTexture(bar.cachedIcon)` — read (every frame, unconditional)
- Line 617: `if icon.cachedSpellID ~= timer.spellID then` — compare (icon active path)
- Line 618: `icon.cachedSpellID = timer.spellID` — write (icon active miss branch)
- Line 619: `icon.cachedIcon = ns:GetSpellIcon(timer.spellID)` — write (icon active miss branch)
- Line 621: `icon.icon:SetTexture(icon.cachedIcon)` — read (every frame when timer active, unconditional)
- Line 640: `if icon.cachedSpellID ~= resolvedSpellID then` — compare (icon placeholder path)
- Line 641: `icon.cachedSpellID = resolvedSpellID` — write (icon placeholder miss branch)
- Line 642: `icon.cachedIcon = resolvedSpellID and ns:GetSpellIcon(resolvedSpellID) or 134400` — write (icon placeholder miss branch)
- Line 644: `icon.icon:SetTexture(icon.cachedIcon)` — read (every frame, placeholder path)

**Change-detection pattern verified:** yes
- All three sites follow the canonical pattern: read the current resolved spellID into a local (`resolvedSpellID` or `timer.spellID`), compare to the widget-local cache (`bar.cachedSpellID` / `icon.cachedSpellID`), and ONLY on mismatch call `ns:GetSpellIcon(...)` to refresh both the cached spellID and the cached icon ID.
- On the cache-hit path (the common case — spellID has not changed since last frame) there is zero work beyond the integer compare and the `SetTexture(cached)` call. No `C_Spell.GetSpellInfo` call, no table allocation, no closure creation.
- `ns:GetSpellIcon` (BuffEngine.lua:116) DOES call `C_Spell.GetSpellInfo` internally, but only on the miss branch — which fires at most once per widget per spellID change (e.g., at proc start, at lust/trinket/pot swap, or once at CDM-open when populating the placeholder icon).

**wipe() accumulator pattern preserved:** yes
- Accumulators confirmed wiped each UpdateDisplay cycle: `wipe(barTimers)` (Display.lua:380), `wipe(iconTimers)` (381), `wipe(activeBarBySpell)` (411), `wipe(barSlots)` (420 and 431), `wipe(buffSlots)` (562), `wipe(activeBySpell)` (573).
- All six accumulator tables are declared at module scope (lines 23-28) — not re-created per frame.
- Any `local foo = {}` found inside hot loop body: none. The only `{}` literals in the whole file are at module scope (lines 14-28) for pools and accumulators.

**New per-frame allocations found:**
- Line 467: `bar.proc = { spellID = info.spellID, label = info.label, key = slot.key }` — three-field table constructor inside the bar-placeholder else branch.
- Line 635: `icon.proc = { spellID = info.spellID, label = info.label, key = entry.key }` — three-field table constructor inside the icon-placeholder branch.
- **Context:** Both allocations are on the PLACEHOLDER path, which only runs when a slot has NO active timer AND `(not settings.hideWhenInactive OR ns.configOpen OR ns.editModeActive)`. Typical gameplay path (real timer active) short-circuits to the `timer then bar.proc = timer` branch at line 461 / `icon.proc = timer` at line 614 and does NOT allocate. The placeholder tables allocate every 50ms (UPDATE_INTERVAL) ONLY while the CDM settings window is open or Edit Mode is active — both transient, out-of-combat UI states. Not a gameplay-hot-path regression; acceptable per CONTEXT.md "targeted check, not broader audit" scope.
- **Pre-existing note:** These allocations predate Phase 22 in spirit — the placeholder proc-shim pattern used to build a similar ad-hoc table for tooltip anchoring. Phase 22 normalized them to the `{ spellID, label, key }` shape so `ns:ShowBuffTooltip` sees a uniform proc. No new pattern introduced.

**Finding (Path 1):** No regression vs. pre-Phase-22 baseline — per-widget change-detection is correctly allocation-free on the common cache-hit gameplay path; the two placeholder-proc table allocations (lines 467, 635) are gated behind CDM-open/Edit-Mode conditions (not the gameplay hot path) and predate Phase 22 architecturally.

---

## Path 2: UNIT_AURA dispatch flow

**eventToProviders built once (not per-event):** yes
- Declaration site: Providers.lua:9 (`local eventToProviders = {}`)
- Build-loop site (runs at module load, after ns.providers is populated): Providers.lua:569-578
- Read sites (inside `ns:DispatchEventToProviders`): Providers.lua:591 (`local interested = eventToProviders[event]`)
- Any write sites inside DispatchEventToProviders: none. The only writes to `eventToProviders` are at lines 571-574 (inner `eventToProviders[event] = {}` lazy-create and `table.insert(eventToProviders[event], provider)`) which run exactly once at file load, wrapped by the `for _, provider in ipairs(ns.providers) do` outer loop.

**DispatchEventToProviders per-call allocations:** none
- Providers.lua:590-607 — walked line-by-line:
  - L591 `local interested = eventToProviders[event]` — table lookup, no alloc.
  - L592-594 — nil-check + early return (scalar 0), no alloc.
  - L595 `local handled = 0` — scalar local, no alloc.
  - L596 `for _, provider in ipairs(interested) do` — `ipairs` on an existing table, no alloc for the iterator in Lua 5.1/LuaJIT / Blizzard's patched Lua (iterator state is the table ref + integer).
  - L597 `local proc = provider:OnTrigger(event, ...)` — method call; any allocation is the provider's responsibility (audited per-provider below).
  - L598-600 `if proc then ns.activeTimers[proc.key] = proc; handled = handled + 1` — table assignment + scalar add, no alloc.
  - L601-603 `if ns.UpdateDisplay then ns:UpdateDisplay() end` — conditional nested call; UpdateDisplay itself respects wipe() accumulator pattern (verified Path 1).
  - L606 `return handled` — scalar return, no alloc.
- Zero table constructors, zero `function()` closures, zero `string.format` / concat-heavy strings inside the loop body.

**LustProvider:OnTrigger hot-path allocations (no-match path):** none
- Providers.lua:455-509 — walked line-by-line for the NO-MATCH PATH (the ~99% case where `updateInfo.addedAuras` contains no Sated-family debuff):
  - L456-464 — four early-return guards (event != UNIT_AURA, unit != player, missing updateInfo/addedAuras). Scalar compares, no alloc.
  - L467 `local entry = ns.db and ns.db.trackedBuffs and ns.db.trackedBuffs["lust"]` — chained table lookup, no alloc.
  - L468-470 — entry guard (nil / section=="hidden"), early return. No alloc.
  - L473 `local existing = ns.activeTimers and ns.activeTimers["lust"]` — table lookup, no alloc.
  - L474-476 — no-restart guard (active lust proc still running), early return. `GetTime()` returns a number, no alloc.
  - L479 `for _, aura in ipairs(updateInfo.addedAuras) do` — iterates a Blizzard-provided table, no alloc for the iterator.
  - L481 `if not issecretvalue(aura.spellId) then` — builtin call returning boolean, no alloc.
  - L482 `local lustSpellID = ns.SATED_DEBUFF_TO_LUST[aura.spellId]` — table lookup, no alloc.
  - L483 `if lustSpellID then ... end` — on the NO-MATCH path this branch never executes; the proc-table constructor at L493-503 is skipped.
  - L508 `return nil` — no alloc.
- Hot path entered ~every UNIT_AURA event; proc-table allocation only on match (acceptable — once per lust cast, not per frame).

**OnUnitAura per-event allocations:** none
- BuffEngine.lua:329-365 — walked line-by-line:
  - L335 `ns:DispatchEventToProviders("UNIT_AURA", "player", updateInfo)` — passes the `updateInfo` reference through varargs; Lua's `...` does NOT copy the table contents. The vararg forwarding at Providers.lua:597 `provider:OnTrigger(event, ...)` likewise does not copy. (Vararg packing in Lua 5.1 / Blizzard Lua is internally implemented via the C stack — no Lua-heap table allocated per call.)
  - L341 `if C_Secrets.ShouldAurasBeSecret()` — API returning boolean, no alloc.
  - L342-348 — `if not ns.secretGateLogged then ns.secretGateLogged = true; <debug print only if ns.debugLogging>` — scalar assignment + optional print (debug off by default). No per-call alloc in normal flow.
  - L352 `if updateInfo and updateInfo.isFullUpdate` — field read on provided table, no alloc.
  - L353-355 — `if ns.debugLogging then print(...)` — debug off by default; print string is a constant literal (not concatenated). No alloc.
  - L364 `ns:ScanActiveTimersForCancellation()` — delegated to Path 3.
- Zero closures, zero table constructors, zero per-call string builds.

**Finding (Path 2):** No regression vs. pre-Phase-19 baseline — the dispatcher-first pattern (BuffEngine.lua:335) adds one vararg-forwarding call per UNIT_AURA event but no heap allocation; `eventToProviders` is built exactly once at module load; the LustProvider no-match fast-path is guard-based and allocation-free; the only allocation (proc table at Providers.lua:493) fires once per lust cast, not per event.

---

## Path 3: ScanActiveTimersForCancellation

**Post-Phase-22 flow:** iterates `ns.activeTimers`; per-entry reads `timer.aliveBuffs` (a short list of spellIDs) and calls `C_UnitAuras.GetPlayerAuraBySpellID(buffID)` for each; removes the timer entry if NONE of the aliveBuffs are present. Called from `ns:OnUnitAura` after the `ShouldAurasBeSecret` gate and `isFullUpdate` suppression.

**Per-call allocations in hot path:** none (in the normal/release flow)
- BuffEngine.lua:284-327 — walked line-by-line:
  - L285 `local cancelledCount = 0` — scalar, no alloc.
  - L286 `local cancelledLabels` — nil local (lazy-allocated only inside `if ns.debugLogging` branch at L306), no alloc in the default release flow.
  - L288 `for key, timer in pairs(ns.activeTimers) do` — `pairs` on an existing table. In Lua 5.1 / Blizzard Lua, `pairs` iteration does not allocate a heap table — the iterator state is internal to the C-level `next` call. NOT a Phase-22 regression (pre-Phase-22 code used the same `pairs` pattern on `ns.activeTimers`).
  - L293 `if timer.aliveBuffs and #timer.aliveBuffs > 0` — field read + `#` length operator on an existing array-like table, O(1) in practice for the small lists we produce (1-2 elements). No alloc.
  - L294 `local anyPresent = false` — scalar, no alloc.
  - L295 `for _, buffID in ipairs(timer.aliveBuffs) do` — `ipairs` on existing table, no alloc.
  - L296 `C_UnitAuras.GetPlayerAuraBySpellID(buffID)` — Blizzard API. Returns a NEW AuraData table if the aura is present, or nil if absent. The return value is used only as a boolean in the `if ... then` test and immediately discarded (never bound to a local, never stored). Blizzard's GC handles the transient table. This allocation is API-induced, NOT introduced by Phase 22.
  - L297-299 — scalar assignment + `break`, no alloc.
  - L301-302 — `if not anyPresent then ns.activeTimers[key] = nil` — table-assignment-to-nil removes the entry, no alloc.
  - L303 `cancelledCount = cancelledCount + 1` — scalar add, no alloc.
  - L304-309 `if ns.debugLogging then ... end` — debug branch; `cancelledLabels = {}` at L306 is LAZY (first cancellation only) and conditional on `ns.debugLogging` (false by default). `table.insert` at L308 on existing table, no alloc beyond the one-shot lazy `{}`.
  - L314-326 — post-loop: debug-only string concat (L316-321 uses `..` chain and `table.concat`; all gated by `ns.debugLogging`), then `ns:UpdateDisplay()`. Release flow: zero string builds.
- Note: `C_UnitAuras.GetPlayerAuraBySpellID` returns a Blizzard-allocated table on hit; we discard it immediately (no storage). Pre-Phase-22 code had identical behavior on the same set of spellIDs (via branches on `timer.source == "lust"` / `"trinket"` / etc.); this is not a regression.
- Note: The `if ns.debugLogging` branch lazy-allocates `cancelledLabels`; debug logging is off by default, so this fires zero times in release builds.

**aliveBuffs iteration vs. pre-Phase-22 source branching:** Same number of `GetPlayerAuraBySpellID` calls per scan (one per tracked-buff spellID across all active timers), just dispatched through a uniform `ipairs(timer.aliveBuffs)` loop instead of a hand-written `if timer.source == "lust" then ... elseif timer.source == "trinket" then ...` branch tree. No new allocations introduced by the aliveBuffs pattern — it is strictly a code-organization win (DISP-01 / DISP-03 uniformity) with identical runtime characteristics.

**Finding (Path 3):** No regression vs. pre-Phase-22 baseline — the aliveBuffs iteration is allocation-free in the release flow; the only heap churn (`C_UnitAuras.GetPlayerAuraBySpellID` return tables) is Blizzard-API-induced and identical to pre-Phase-22 behavior; the lazy `cancelledLabels` list is debug-only and off by default.

---

## CHANGELOG Input

**Instruction to Plan 24-03:** Copy the `note_text` string below verbatim into the v0.2.4 CHANGELOG entry (after the one-liner from D-07), OR omit the note entirely if `note_text` is `"NONE"`.

```
note_text: "NONE"
```

**Rationale (for the planner, not for CHANGELOG):** All three audited hot paths (Display per-widget icon cache, UNIT_AURA dispatch flow, ScanActiveTimersForCancellation) show zero per-frame / per-event allocation regressions vs. the pre-refactor baseline. The Phase 22 per-widget cache correctly short-circuits on the common case. The Phase 19 dispatcher forwards UNIT_AURA via varargs without heap copies, and the LustProvider no-match fast-path is guard-based. The Phase 22 aliveBuffs iteration performs the same number of Blizzard API calls as the pre-Phase-22 source-branching code and adds no new allocations. No measurable improvement either — the refactor was a code-organization / dispatch-unification win (DISP-01 / DISP-03) with runtime-equivalent behavior. Per D-08 ("performance note appended only if a measurable improvement or regression"), the correct action is to OMIT the performance note: the v0.2.4 CHANGELOG entry stays a one-liner per D-07 ("Internal file reworking — no user-visible changes.").
