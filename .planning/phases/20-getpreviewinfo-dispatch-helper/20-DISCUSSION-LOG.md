# Phase 20: GetDisplayInfo + Dispatch Helper - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 20-getpreviewinfo-dispatch-helper
**Areas discussed:** Return shape, Dispatch strategy, At-rest cache access, Preview vs AtRest

---

## Return shape

| Option | Description | Selected |
|--------|-------------|----------|
| Single spellID | { icon, label, duration, spellID } — spellID always numeric (for string keys, provider resolves to concrete spell). | ✓ |
| Separate tooltipSpellID | { icon, label, duration, spellID, tooltipSpellID } — explicit separation | |
| Minimal no spellID | { icon, label, duration } — tooltips resolved separately | |

**User's choice:** Single spellID
**Notes:** Providers resolve string keys to their at-rest concrete spell, so callers use previewInfo.spellID uniformly with GameTooltip:SetSpellByID.

---

## Dispatch strategy

| Option | Description | Selected |
|--------|-------------|----------|
| OwnsKey method | Iterate providers, each declares OwnsKey(key). Consistent with GetEventInterests pattern. | |
| Key-provider map | Build map at load time. Hybrid static + dynamic. | |
| Type dispatch | Hardcoded switch (via local lookup table) in helper. Fastest, simplest. | ✓ |

**User's choice:** Type dispatch
**Notes:** Implementation uses local keyToProvider table in Providers.lua for cleanliness. Fast O(1), acceptable coupling to provider inventory (rare additions).

---

## At-rest cache access

| Option | Description | Selected |
|--------|-------------|----------|
| Read ns.metaAtRest | Providers read shared cache via namespace. Cache stays in BuffEngine. Minimal churn. | |
| Move cache to provider | Full PROV-F3 scope pulled in. Cache + RefreshAtRest live in provider. | ✓ |
| Helper indirection | ns:GetAtRestDuration(key) helpers. Extra indirection. | |

**User's choice:** Move cache to provider (full PROV-F3)
**Notes:** Providers should own their data end-to-end. ns:RefreshMetaIcons becomes thin wrapper iterating ns.providers.

---

## Preview vs AtRest

| Option | Description | Selected |
|--------|-------------|----------|
| Collapse to one | Single GetDisplayInfo(key) returning { icon, label, duration, spellID }. Callers ignore duration if not needed. | ✓ |
| Base-derived AtRest | Keep both; base auto-derives AtRest from Preview. Override only Preview. | |
| Keep separate | Both methods, each provider implements both. | |

**User's choice:** Collapse to one
**Notes:** Cleaner contract. duration is only field unique to Preview. Base mixin has 4 methods total: GetEventInterests, OnTrigger, GetDisplayInfo, RefreshAtRest.

---

## Cache shape (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| spellID + duration | Minimal cache. Icon AND label derived from spellID in GetDisplayInfo. Single source of truth. | ✓ |
| icon + spellID + duration | Current pattern. Icon cached, label derived. Slightly less CPU. | |
| icon + label + spellID + duration | Cache everything display-related. | |

**User's choice:** spellID + duration
**Notes:** User probed the semantics — "Why save icon field?" — and chose minimal cache once it was clear icon can be derived from spellID. spellID becomes the primary key; display fields are derivations in GetDisplayInfo.

---

## Claude's Discretion

- Exact Lua style for provider instance-state init
- Whether to call RefreshAtRest once at addon load
- FindSpellByItemID scope (top-level local vs upvalue)
- Shim implementation style (direct provider.atRest read vs calling GetDisplayInfo)

## Deferred Ideas

- Display.lua migration — Phase 22
- CDMTab.lua migration — Phase 23
- StartAllPreviewTimers additive-preview rewrite — Phase 21 (LIFE-03)
- Removal of ResolveSuggestedSpellID / GetAtRestMetaIcon / GetAtRestMetaInfo — Phase 24
- Rename ns:RefreshMetaIcons — Phase 24
