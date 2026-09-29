---
phase: 50-cleanup-release-prep
reviewed: 2026-09-26T01:18:28Z
depth: deep
files_reviewed: 2
files_reviewed_list:
  - Display.lua
  - Providers.lua
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 50: Code Review Report

**Reviewed:** 2026-09-26T01:18:28Z
**Depth:** deep
**Files Reviewed:** 2
**Status:** clean

## Summary

Reviewed the exact Phase 50 diff (`git diff 73f260b3011ccc8e35e400ca7191050cce00483e..HEAD -- '*.lua'`), which touches only `Display.lua` (`ApplyDispelBorder`'s new `identity` parameter and dirty check) and `Providers.lua` (`ns:RacialDefInList` unification plus the `racialGateKeyIDs` parse memo). All other source in the repo was left untouched and is out of scope per this phase's "no refactors of pre-existing code" constraint; no findings were filed against it.

This diff is adversarially reviewed against the six domain hazards this project has actually hit before (secret-value comparisons, pooled-widget stale state, the Lua upvalue-order trap, memo staleness, hot-path allocation, and CDM taint). Each is traced below to a concrete pass/fail with call-site evidence, not just a read of the changed lines in isolation.

**1. Secret values (`ApplyDispelBorder`).** `identity` is run through `issecretvalue(id)` at Display.lua:818 before the first comparison at Display.lua:831, collapsing to `nil` on failure — the standing "issecretvalue before type/comparison" rule is followed. `id`/`widget._dispelID` are compared only to each other, never `tostring`'d, never concatenated. The raw `atlas` parameter still reaches only `border.Texture:SetAtlas(atlas, false)` at Display.lua:834 and is never compared, stored, or tested for nilness anywhere — `key` (the dirty-check cache value) is always the non-secret sentinel-or-plain-string, never `atlas` itself. Confirmed by reading the full function body (Display.lua:795-841).

**2. Pooled widget reuse — the hazard this phase exists to fix.** Traced all four call sites: the bar path (Display.lua:2057), the bar pool reset (Display.lua:2223), the icon path (Display.lua:2347), and the icon pool reset (Display.lua:2582). `widget._dispelID` is cleared alongside `_dispelKey` in the `not shown` branch (Display.lua:805-810), gated on `widget._dispelShown` being true — so every transition into "not shown", whether from the render loop itself (an entry's `dispelShown` flipping false) or from a pool-tail reset (`ApplyDispelBorder(pool[i], nil, false)`), clears the stamp. Traced the reuse scenario directly: a pooled widget carrying `_dispelID=5` from a prior entry, now assigned a different entry with `cooldownID=7` and `dispelShown=true` in the same pass (no intervening hide), hits `widget._dispelID ~= id` (`5 ~= 7`) and forces `SetAtlas` even when the plain atlas string happens to be identical between the two entries — the exact case the old atlas-only key could not distinguish. Confirmed `entry.cooldownID`/`slot.cooldownID` is always present whenever `isMerged`/`dispelShown` can be true: entries only exist in `ns.mergeSlots`/`ns.mergeShownSlots` because `MergeMode.lua:341` already built `key = "cdm:" .. cooldownID` (a concatenation, which raises on a secret value and would have prevented `table.insert` from ever running) — so an entry reaching `ApplyDispelBorder` with `isMerged == true` is guaranteed to carry a real, non-secret `cooldownID`, closing the "identity always nil for merged entries → falls back to always-set for every frame" regression risk. `MergedSlotsFor` (Display.lua:1921-1924) returns direct references into `ns.mergeShownSlots`, not copies, so identity is not lost between the mirror and the render loop.

**3. Lua upvalue-order trap.** `ns:RacialDefInList` (Providers.lua:1096) is declared with `function ns:` syntax, resolved through the `ns` table at call time rather than as a file-local — so declaration order relative to its three callers (`ns:RacialDefForSpellID` at Providers.lua:1108-1110, `ns:IsRacialKeyVisible` at Providers.lua:1116-1130, `ns:RacialCooldownSeed` further below) cannot trigger the nil-upvalue bug regardless of file position. It is also physically declared before all three callers in this file, so even a file-local declaration would have been safe here — belt and suspenders. The one true file-local this diff adds, `local racialGateKeyIDs = {}` (Providers.lua:988), is declared before its only reader/writer, `ns:IsRacialKeyVisible` (Providers.lua:1116), so no upvalue hazard there either.

**4. Memo safety.** `racialGateKeyIDs` stores the PARSE result only (`ns:RacialKeySpellID(key) or ns:CooldownKeySpellID(key) or false`, Providers.lua:1122), never a visibility answer — it has no dependency on `UnitRace("player")` at all, so an unreadable race read cannot poison it. The `false` sentinel ("not a racial-shaped key") is correctly distinguished from `nil` ("not yet parsed") via `spellID == nil` as the miss test (Providers.lua:1121) rather than `not spellID` — confirmed this round-trips correctly for both outcomes by tracing both branches. `ns:IsRacialKeyVisible` still walks `ns:RacialDefsRaw()` (the raw, ungated list) for the actual membership check (Providers.lua:1130), unchanged from before this refactor, so visibility itself is still computed fresh every call as the comment requires.

**5. Hot paths.** No new table constructors, string concatenations, closures, or `string.match` calls were added to any per-pass path. `ApplyDispelBorder`'s new lines (`local id = identity`, `issecretvalue(id)`) are a local copy and a C-function call, not allocations. `ns:RacialDefInList` is a plain `ipairs` walk with one equality test, same shape as the three walks it replaced. The memo genuinely removes the allocation it claims to: `racialGateKeyIDs[key]` is a table lookup on the hit path, with the `string.match`-backed parse (`ns:RacialKeySpellID`/`ns:CooldownKeySpellID`) running only once per distinct key for the life of the session.

**6. Taint.** No new call into any Blizzard Cooldown Manager mixin method was introduced. `border.Texture:SetAtlas` is the same plain widget setter call as before (now conditioned differently, not newly added). `ns:RacialDefInList` and the memo touch only plain Lua tables.

No BLOCKER, WARNING, or INFO findings resulted from this review. The diff is small, defensively commented, and each domain hazard it was written against has a corresponding, verifiable guard in the code rather than only in prose.

---

_Reviewed: 2026-09-26T01:18:28Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
