# 23-04 Summary

**One-liner:** Deploy + human-verify; Phase 22 regression discovered and fixed (slot-to-proc lookup used spellID instead of .key — broke meta-buff casts like Time Warp).

**Status:** APPROVED (lgtm) after fix applied

## Deliverables

- scripts/install.bat deploy
- In-game verification across all 4 buff types
- Fix commit `df48029`: Display.lua slot-to-proc lookup corrected to use `.key` uniformly

## Bug discovered during verification

**Symptom:** Cast Time Warp (Mage lust) → bar showed "Spell 80353" with empty bar and no countdown. Touch of the Magi (user-spell) worked correctly.

**Root cause:** Phase 22 made `proc.spellID` always numeric. But `activeBarBySpell` / `activeBySpell` are keyed by `timer.key` (stable slot identity — string for meta-buffs, numeric for user-spells). Read sites used `slot.spellID` which for procs is numeric (80353), not the string key ("lust"). User-spells coincidentally had `key == spellID` (both numeric), so they worked. Meta-buffs failed because their key is a string.

**Fix (Display.lua):**
- Populate `.key` on DB slots in slot-building loops (both bar and icon paths)
- Uniform lookup via `slot.key` / `timer.key` — no `or` fallback
- Applied to both bar layout loop AND icon layout loop (4 sites total)

**Why verification missed it earlier (Phases 17-22):** Phase 22 verification ran all tests with CDM open (which uses the `showPlaceholders=true` path — iterates DB entries where meta entries happen to have `entry.spellID` string-equal to the table key). The `hideWhenInactive=true + CDM closed + real cast` path where `barSlots = barTimers` directly (slot IS the proc, slot.spellID is numeric) was never exercised. User-spells passed verification; meta-buffs never got a real cast test in that state.

## Key Links

- `Display.lua:417`, `413-414` — write sites key by `timer.key`
- `Display.lua:450`, `591` — read sites use `slot.key`
- `Display.lua:424-426`, `565-568` — DB slot-building loops populate `.key`

## Debug leftover

`_G.tbt = ns` in Core.lua — temporary debug export added during bug investigation. Scheduled for removal in Phase 24 cleanup.
