# Milestones

## v0.2.4 SpellProvider Refactor (Shipped: 2026-04-22)

**Scope:** Pure internal architecture refactor. Zero user-facing feature additions.
**Phases:** 8 phases, 23 plans
**Timeline:** ~9 days (2026-04-13 → 2026-04-22)
**Interface bump:** 120005

### Key accomplishments

- **SpellProvider architecture** — Four providers (UserSpell, Trinket, Pot, Lust) implementing a common interface (`GetEventInterests`, `OnTrigger`, `GetDisplayInfo`, `RefreshAtRest`) registered on `ns.providers`. `ns:DispatchEventToProviders` routes events by declared interest; `BuffEngine.OnSpellCastSucceeded` and `OnUnitAura` are single-line dispatchers with zero `if/elseif` chains (PROV-01, PROV-02).
- **Unified ActiveProc shape** — 9-field normalized plain table (`{key, spellID, duration, label, expiresAt, aliveBuffs, ...}`) consumed by one Display codepath with zero type-specific branching (PROV-03, DISP-01).
- **Single icon-resolution dispatch** — `ns:GetDisplayInfoForKey(key)` replaces all duplicated resolution chains; providers own `RefreshAtRest` (PROV-04, PROV-F3 pulled forward from v0.3+).
- **Additive preview architecture** — Separate `ns.previewTimers` table eliminates the mid-CDM real-cast-loss bug (v0.2.3 regression) as an architectural side-effect (LIFE-03).
- **Shared tooltip handler** — `ns:ShowBuffTooltip` used uniformly by timer bars, buff icons, and CDM settings tiles (DISP-03).
- **CDMTab unification** — All icon/tooltip resolution flows through `ns:GetDisplayInfoForKey`; `ns.SUGGESTED_KEYS` ordered list replaces the old closure table; `CLASS_LUST_SPELL` / `GetHunterLustSpell` demoted to Providers.lua module-local (DISP-02).
- **Orphan removal** — Three backwards-compat shims (`GetAtRestMetaIcon`, `GetAtRestMetaInfo`, `ResolveSuggestedSpellID`), two `ns.*FALLBACK_ORDER` exports, CSV source files, and `_G.tbt` debug export all deleted. `RefreshMetaIcons` renamed to `RefreshProvidersAtRest` (DISP-04).
- **Hot-path audit** — Phase 24 verified zero per-frame/per-event allocation regressions on Display render, `OnUnitAura` dispatch, and `ScanActiveTimersForCancellation`.

### Bugs fixed as architectural side-effects

- Trinket/pot preview bars showing 0-second durations (PITFALL-4) — fixed by Phase 20's provider-owned `RefreshAtRest` + `GetDisplayInfoForKey`.
- Mid-CDM real-cast loss — fixed by Phase 21's additive-preview design (separate tables, no snapshot/restore).
- Phase 22 regression (`df48029`) surfaced the exact bug class the refactor was designed to eliminate: Display read-sites using `slot.spellID` instead of `slot.key` for lookup. Unmasked by Mage Time Warp where `.key = "lust"` ≠ `.spellID = 80353`. Fixed by standardizing all reads on `.key`.

### Process notes

- No COMBAT_LOG_EVENT_UNFILTERED introduced (platform constraint held).
- Schema unchanged (`CURRENT_SCHEMA_VERSION = 3`); no SavedVariables migration.
- stylua clean across all 6 Lua files at exit.
- Phase 24 audit surfaced and resolved `_G.tbt` debug export tech debt before squash-merge.

---

_See `.planning/milestones/v0.2.4-ROADMAP.md` for full phase details._
_See `.planning/milestones/v0.2.4-REQUIREMENTS.md` for requirement-level traceability._
_See `.planning/milestones/v0.2.4-MILESTONE-AUDIT.md` for the final audit report._
