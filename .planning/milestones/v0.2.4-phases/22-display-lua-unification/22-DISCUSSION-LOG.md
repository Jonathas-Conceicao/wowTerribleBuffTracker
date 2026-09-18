# Phase 22: Display.lua Unification + Proc Shape Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-04-21
**Phase:** 22-display-lua-unification
**Areas discussed:** Tooltip handler, Tooltip spellID (expanded into proc shape cleanup), Layout icon source, metaIconsDirty flag

---

## Tooltip handler consolidation

| Option | Description | Selected |
|--------|-------------|----------|
| ns:ShowBuffTooltip | Namespace export; CDMTab can reuse Phase 23 | ✓ |
| Display-local | Local function | |
| Defer | Phase 23 only | |

**User's choice:** ns:ShowBuffTooltip
**Notes:** Satisfies DISP-03 in Phase 22. CDMTab migrates its tooltip call sites in Phase 23 to use the same helper.

---

## Tooltip spellID source → expanded into proc shape cleanup

Initial question was "which field drives the tooltip" (castSpellID? spellID? iconSpellID?). User flipped it: "the tooltip spellid should always be the same spellid we use for the icon. When lust is detected we have a spellid for the actuall buff to show on icon, the spell id should match that."

Then further: "Provider should return a spellID itslef. Then both icon and tooltip can be loaded from that."

Then even further: "why do we need spellid AND castspellid AND lustbuffid?? They are all just spellid, a single field all providers HAVE to provide so we can have icon and unit resolved for that. Also providers dont need to return an icon, just the spellid, icon will be resolved from it."

Then on source: "let's make it more generic. We should have a second field with a small list of possible spellids/buffs and any if NONE of these buffs are present we clear... for lust, where we can detect a proc and not be sure which of two or more buffs it cooresponds too, we return a list of 2 or 3 lust buffs which might actually be the lust we detected."

**Outcome:** Proc shape collapsed from ~15 fields with mixed-type spellID to 9 fields:
- `key` (identity)
- `spellID` (numeric, drives icon + tooltip + cancellation strategy)
- `duration`, `expiresAt`, `startedAt`
- `section`, `layoutOrder`, `label`
- `aliveBuffs` (list, replaces source/castSpellID/lustBuffID branch selection)

Dropped: `icon`, `source`, `castSpellID`, `lustBuffID`, string-coexistence `spellID`.

---

## Layout icon source

| Option | Description | Selected |
|--------|-------------|----------|
| Direct + Display cache | ns:GetDisplayInfoForKey + cache on frame by spellID | ✓ |
| Keep thin wrapper | GetSuggestedAtRestIcon as named alias | |

**User's choice:** Direct call + Display-side caching
**Notes:** Delete GetSuggestedAtRestIcon local helper. Icon resolved once per spellID change on each frame.

---

## metaIconsDirty flag

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entirely | Redundant with numeric-spellID cache detection | ✓ |
| Keep | Forced-invalidate for edge cases | |

**User's choice:** Delete entirely
**Notes:** With numeric proc.spellID, cache-invalidation-by-spellID-change fires naturally. Removes 1 CDMTab writer, 2 Display readers, 1 Display clearer.

---

## Icon caching principle (user-articulated)

User quote: "icon SHOULD be cached, but not from a providers prespective. Display should cache the icon for the proc it received. Providers shouldn't have to lookup UI elements."

**Outcome:** providers return numeric spellID only; Display caches `cachedIcon`/`cachedSpellID` per frame and refreshes only when spellID changes.

---

## Source field (user-driven elimination)

User quote: "how is source field used right now? Why is it necessary?"

Investigation showed source is only used to pick cancellation strategy (direct-check vs group-check). Generalized to `aliveBuffs` list; strategy eliminated.

---

## Claude's Discretion

- Name of Providers.lua-local SHARED_LUST_BUFFS constant
- ns:HideBuffTooltip helper vs inline GameTooltip:Hide()
- Whether OnEnter handlers store proc reference or reconstruct via GetDisplayInfoForKey
- Task ordering inside the plan

## Deferred Ideas

- CDMTab.lua full migration — Phase 23
- Shim removal — Phase 24
- CLASS_LUST_SPELL demotion — Phase 23
- RefreshMetaIcons rename — Phase 24
