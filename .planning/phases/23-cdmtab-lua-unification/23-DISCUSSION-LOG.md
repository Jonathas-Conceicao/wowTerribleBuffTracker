# Phase 23: CDMTab.lua Unification - Discussion Log

> **Audit trail only.** Decisions captured in CONTEXT.md.

**Date:** 2026-04-22
**Phase:** 23-cdmtab-lua-unification
**Areas discussed:** Tooltip reuse, META_DESCRIPTIONS, SUGGESTED_BUFFS closures, Resolution chain collapse

---

## Tooltip reuse
| Option | Selected |
|--------|----------|
| Extend with opts (showSpellID/showDuration/extraLines) | ✓ |
| Compose (call handler + add lines) | |
| Verbatim, drop extras | |

**Choice:** Extend with opts — DISP-03 compliance with CDMTab's richer content preserved.

## META_DESCRIPTIONS
| Option | Selected |
|--------|----------|
| Keep CDMTab-local | ✓ |
| Move to provider method | |
| Delete entirely | |

**Choice:** CDMTab-local file-level table. Passed as opts.extraLines.

## SUGGESTED_BUFFS closures
Initial question was delete closures vs keep aliases vs delete SUGGESTED_BUFFS. User asked to understand what SUGGESTED_BUFFS actually is. After explanation (catalog for CDM Suggested section tiles), user agreed to simple key list approach and asked where tooltip description text would come from.

**Choice:** `ns.SUGGESTED_KEYS = {"lust","trinket","pot"}` — simple key list. Description text stays in CDMTab.lua as META_DESCRIPTIONS. Dynamic info via ns:GetDisplayInfoForKey.

## Resolution chain collapse
| Option | Selected |
|--------|----------|
| Inline one-liners | ✓ |
| Extract helper | |

**Choice:** Inline `ns:GetDisplayInfoForKey(key)` calls at each of 3 sites. Concise enough.

## Folded todo
- Phase 23 hint: Demote CLASS_LUST_SPELL + GetHunterLustSpell to Providers.lua local (unblocked by closure deletion)

## Deferred todos (phase 24)
- Fury of the Aspects cancellation bug
- M+ Lua errors from secret values during lust

## Claude's Discretion
- META_DESCRIPTIONS file-local vs closure-local
- Task ordering inside plan
- Local alias helpers (probably not needed)
