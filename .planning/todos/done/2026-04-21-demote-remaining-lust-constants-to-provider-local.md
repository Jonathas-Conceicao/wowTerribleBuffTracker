---
created: 2026-04-21T21:14:39.884Z
title: Demote remaining lust constants to provider-local
area: providers
files:
  - Providers.lua
  - CDMTab.lua
phase_hint: 23
---

## Problem

After Phase 22, `SHARED_LUST_BUFFS` is demoted to a Providers.lua module-local (no `ns.*` export). But two other lust constants remain exported solely because CDMTab's Suggested section reads them for the class-aware lust icon:

- `ns.CLASS_LUST_SPELL` — class → default lust spellID map
- `ns.GetHunterLustSpell` — MM Hunter (spec 254) → Harrier's Cry override function

These should not be globally exported — they're LustProvider implementation details. The reason they're still on `ns` is backwards compatibility with CDMTab's direct reads.

## Solution

During Phase 23 (CDMTab.lua Unification), migrate CDMTab's Suggested section to use `ns:GetDisplayInfoForKey("lust")` — which returns the class-specific spellID via `LustProvider:GetDisplayInfo`. After that migration has no remaining callers for the raw constants, demote both:

- `ns.CLASS_LUST_SPELL` → module-local `CLASS_LUST_SPELL` in Providers.lua
- `ns.GetHunterLustSpell` → module-local `GetHunterLustSpell` in Providers.lua

This completes the lust-constants internalization started in Phase 22 (SHARED_LUST_BUFFS) and enforces the principle that provider data is provider-internal unless explicitly a public API surface.

Verify by grepping: `grep -n "ns\.CLASS_LUST_SPELL\|ns:GetHunterLustSpell\|ns\.GetHunterLustSpell" *.lua` should return 0 outside Providers.lua after Phase 23.
