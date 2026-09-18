# Phase 18: TrinketProvider + PotProvider + BuffEngine Dispatch - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 18-trinketprovider-potprovider-buffengine-dispatch
**Areas discussed:** Key strategy, Provider factoring, Data location, Dispatch semantics

---

## Key Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| String slot key | key="trinket"/"pot", castSpellID as separate field. Eliminates eviction loop and metaSlot bridge. | ✓ |
| Numeric castSpellID | Preserve current behavior exactly — key=castSpellID with metaSlot="trinket" tag. | |

**User's choice:** String slot key
**Notes:** Research SUMMARY.md flagged this as pivotal decision. Eliminates dual-key/double-index complexity across Display and CDMTab.

---

## Provider Factoring

| Option | Description | Selected |
|--------|-------------|----------|
| Shared MultiSpellProvider | One parameterized mixin, two instances with different configs. Blizzard pattern. | |
| Separate mixins | TrinketProviderMixin + PotProviderMixin as standalone, fully self-contained. | ✓ |

**User's choice:** Separate mixins
**Notes:** User reasoning: "trinket and pots to be independent 'classes'/Mixin structures. That's because in some cases trinkets might endup having more complex setup logics." Keeping them separate leaves room to diverge without refactoring a shared base later.

---

## Data Location

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid move | Static data (spell tables, itemID sets, FALLBACK_ORDER) → Providers.lua. Cache + RefreshMetaIcons stay in BuffEngine. | ✓ |
| Full move | Everything (data, cache, RefreshMetaIcons) into provider mixins. Requires CDMTab call-site update. | |
| Keep in BuffEngine | Providers reference ns.TRINKET_SPELLS etc. Minimal churn. | |

**User's choice:** Hybrid move
**Notes:** CDMTab.lua still calls ns:RefreshMetaIcons — touching that is out of Phase 18 scope. Static data has no external callers, moves cleanly.

---

## Dispatch Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| First-match-wins | Short-circuit on first non-nil proc. Matches current BuffEngine branch-return. | |
| Iterate all | Current Providers.lua behavior. Simpler but wasteful. | ✓ |
| Iterate + warn on collision | Iterate all, log debug warning if multiple providers match same args. | |

**User's choice:** Iterate all
**Notes:** Disjoint IDs (trinket/pot/user-spell never collide) make iteration safe. Dispatcher stays dumb. If future provider needs short-circuit, it can guard in its own OnTrigger.

---

## Claude's Discretion

- Exact location of TRINKET_SPELLS/POT_SPELLS locals in Providers.lua (module-level vs mixin-local)
- Whether to inline OnSpellCastSucceeded into Core.lua event router (cosmetic, low priority)
- Navigation-aid comments at BuffEngine's stripped OnSpellCastSucceeded

## Deferred Ideas

- Provider-level RefreshCache() — PROV-F3 v0.3+
- Shared MultiSpellProvider parameterization — revisit if more meta-slots emerge
- Full data move with CDMTab update — PROV-F3
