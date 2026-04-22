---
gsd_state_version: 1.0
milestone: v0.2.4
milestone_name: SpellProvider Refactor
status: completed
last_updated: "2026-04-22T06:24:12.261Z"
last_activity: 2026-04-22
progress:
  total_phases: 9
  completed_phases: 8
  total_plans: 23
  completed_plans: 23
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** Players can see countdown timers for buffs/cooldowns that the game no longer surfaces automatically.
**Current focus:** Phase 24 — cleanup

## Current Position

Phase: 999.1
Plan: Not started
Status: Ready for /gsd:complete-milestone (squash-merge to main; no tag/release.bat performed per D-13 boundary)
Last activity: 2026-04-22

Progress: [████████] 8/9 phases (89%)

## Accumulated Context

### Decisions

- [SpellProvider]: Providers are stateless — BuffEngine manages all lifecycle (option A)
- [ActiveProc]: Plain table shape {key, icon, duration, label, expiresAt, source} + optional castSpellID/lustBuffID — no metatable
- [Event routing]: Providers declare event interest via GetEventInterests(); BuffEngine routes matching events only — no hardcoded if/elseif chains
- [Provider keys]: spellID (numeric) for user-created buffs; string labels ("trinket1", "trinket2", "pot", "lust") for meta-buffs
- [Provider order]: { TrinketProvider, PotProvider, LustProvider, UserSpellProvider } — priority encodes shared-slot overwrite semantics
- [DB constraint]: Schema must NOT change — CURRENT_SCHEMA_VERSION stays unchanged; providers constructed from existing SavedVariables at runtime
- [Preview]: GetPreviewInfo() is for CDM tab at-rest display; StartAllPreviewTimers iterates providers directly (not provider dispatch)
- [Display]: Single codepath for all buff types — zero type-specific branching; wipe() accumulator preserved
- [OOP pattern]: CreateFromMixins / CreateAndInitFromMixin — matches CDM source; no per-instance metatable GC overhead
- [LUST-01]: Pre-gate ordering (Sated check before ShouldAurasBeSecret) is load-bearing — must be explicit and verified
- [Phase 17-01]: UserSpellProvider returns extended ActiveProc shape (startedAt, section, layoutOrder, spellID) for coexistence with Display.lua until Phase 22 unification
- [Phase 17-01]: eventToProviders dispatch map is module-local in Providers.lua — built once at file load, never rebuilt per-event
- [Phase 17-01]: ns:DispatchEventToProviders calls ns:UpdateDisplay inline after each proc write, matching existing BuffEngine pattern
- [Phase 17-provider-skeleton-userspellprovider]: Only branch 3 (user-spell path) replaced in Phase 17; trinket/pot branches preserved until Phase 18
- [Phase 17-provider-skeleton-userspellprovider]: Trinket/pot preview 0-second duration deferred to Phase 20/21 (PITFALL-4/LIFE-03) — confirmed pre-existing, not Phase 17 regression
- [Phase 18]: TrinketProviderMixin and PotProviderMixin are separate independent concrete mixins (D-05/D-06) — string slot key in proc.key, castSpellID as separate numeric field (D-01/D-02)
- [Phase 18]: castSpellID added to UserSpellProviderMixin proc (D-17) for single-path ScanActiveTimersForCancellation in Plan 18-02
- [Phase 18]: Phase 18-02: OnSpellCastSucceeded reduced to single-line dispatcher — zero branches for all cast types (PROV-02, D-18/D-19)
- [Phase 18]: Phase 18-02: ScanActiveTimersForCancellation reads castSpellID with type-guard; Display accumulators use timer.key or timer.spellID (D-04, D-15, D-16)
- [Phase 18]: Phase 18-03: In-game verification approved — trinket/pot dispatch, reproc overwrite, cancellation, lust regression guard, and preview all confirmed correct
- [Phase 18]: Trinket/pot preview 0-second duration confirmed pre-existing (PITFALL-4); fix deferred to Phase 20/21
- [Phase 18]: Edit Mode click-release timing bug captured as backlog 999.1 (a71cca2); out-of-scope for Phase 18
- [Phase 19-lustprovider-unit-aura-dispatch]: LustProvider additive-only in Plan 19-01: registered in ns.providers/eventToProviders but BuffEngine.OnUnitAura not yet routing UNIT_AURA through dispatcher — behavioral change deferred to 19-02
- [Phase 19-lustprovider-unit-aura-dispatch]: ns.SHARED_LUST_BUFFS is new namespace export (was local in BuffEngine.lua) enabling ScanActiveTimersForCancellation access after 19-02
- [Phase 19-lustprovider-unit-aura-dispatch]: ns.GetHunterLustSpell uses dot-syntax (no self) so SUGGESTED_BUFFS closures in BuffEngine resolve it after 19-02 removes the local
- [Phase 19-lustprovider-unit-aura-dispatch]: Phase 19-02: OnUnitAura rewritten to dispatcher-first shape (D-14) — unconditional dispatch before ShouldAurasBeSecret gate, LUST-01 ordering preserved by architecture
- [Phase 19-lustprovider-unit-aura-dispatch]: Phase 19-02: ns.auraCheckBlocked renamed to ns.secretGateLogged (D-15); ns:ClearAuraBlock renamed to ns:ClearSecretGateLog (D-16); Core.lua two call sites updated
- [Phase 19]: In-game verification approved — LustProvider dispatch, no-restart guard, M+ secret gate (SKIP/code-verified), and cancellation all confirmed correct. PROV-01 and LIFE-02 complete.
- [Phase 20]: D-01: Collapsed GetPreviewInfo+GetAtRestInfo into single GetDisplayInfo returning {icon,label,duration,spellID} — one method, one contract, duration always included
- [Phase 20]: D-13: Minimal provider atRest cache {spellID,duration} — icon/label derived on-demand in GetDisplayInfo via ns:GetSpellIcon+C_Spell.GetSpellInfo
- [Phase 20]: D-09/D-11: keyToProvider is module-local in Providers.lua (not on ns); no OwnsKey method; ns:GetDisplayInfoForKey uses O(1) table lookup for string keys
- [Phase 20]: D-24: All three backwards-compat shims (GetAtRestMetaIcon, GetAtRestMetaInfo, ResolveSuggestedSpellID) delegate through ns:GetDisplayInfoForKey — internal provider cache never accessed directly
- [Phase 20-getpreviewinfo-dispatch-helper]: Mid-CDM cast loss is PRE-EXISTING (savedPreviewTimers not refreshed mid-preview after StartAllPreviewTimers); not a Phase 20 regression; fix deferred to Phase 21 / LIFE-03 additive-preview rewrite
- [Phase 21-preview-mode-migration]: Phase 21 D-01/D-02/D-03: ns.previewTimers is separate from ns.activeTimers; table identity replaces previewActive flag and source=preview marker
- [Phase 21-preview-mode-migration]: Phase 21 D-11/D-12: ClearAllTimers wipes ns.previewTimers only — ns.activeTimers untouched; eliminates mid-CDM cast-loss bug from v0.2.3
- [Phase 21-preview-mode-migration]: Phase 21 D-14/D-16: ns.previewActive flag fully deleted; CDMTab 3 disjuncts collapsed to ns.configOpen (set/cleared in StartPreview/StopPreview)
- [Phase 21-preview-mode-migration]: LIFE-03 runtime-confirmed — trinket/pot preview bars show real non-zero durations via ns:GetDisplayInfoForKey; PITFALL-4 retired
- [Phase 21-preview-mode-migration]: Phase 20 mid-CDM cast-loss bug fixed as architectural side-effect of separate-tables design (ClearAllTimers only wipes ns.previewTimers)
- [Phase 22-display-lua-unification]: proc.spellID always numeric after Phase 22 (D-03) — string coexistence removed from all 4 providers
- [Phase 22-display-lua-unification]: aliveBuffs field drives data-driven cancellation scan — no source/castSpellID/lustBuffID branching (D-09/D-10)
- [Phase 22-display-lua-unification]: SHARED_LUST_BUFFS demoted to Providers.lua module-local SHARED_LUST_BUFFS_LOCAL (D-12)
- [Phase 22-display-lua-unification]: ns:ShowBuffTooltip exported from Display.lua as single unified handler used by bar + icon OnEnter; CDMTab-ready for Phase 23
- [Phase 22-display-lua-unification]: Per-widget icon cache (cachedSpellID/cachedIcon) on bar + icon frames replaces metaIconsDirty flag — invalidation via spellID change detection
- [Phase 22-display-lua-unification]: Display.lua has zero type-discriminating branches post-Phase-22 — DISP-01 satisfied; all four buff types use single codepath
- [Phase 22-display-lua-unification]: metaIconsDirty flag fully removed from entire addon (D-25); per-widget cachedSpellID/cachedIcon change detection makes dirty flag redundant
- [Phase 22-display-lua-unification]: PROV-F3 fully satisfied by Phase 20 (provider-owned RefreshAtRest + ns:GetDisplayInfoForKey) combined with Phase 22 (unified Display codepath)
- [Phase 22-display-lua-unification]: CDMTab Phase 23 shims preserved — ns:GetAtRestMetaInfo, ns:ResolveSuggestedSpellID, ns:GetAtRestMetaIcon, ns.CLASS_LUST_SPELL, ns.GetHunterLustSpell; Phase 23 migrates all
- [Phase 22-display-lua-unification]: Phase 22 APPROVED in-game — 12/12 steps PASSED; zero visual regression vs Phase 21; DISP-01 + DISP-03 runtime-confirmed
- [Phase 23-cdmtab-lua-unification]: Extended ns:ShowBuffTooltip to (frame, proc, opts); nil opts preserves Phase 22 behavior (D-01/D-05)
- [Phase 23-cdmtab-lua-unification]: Replaced ns.SUGGESTED_BUFFS closure table with ns.SUGGESTED_KEYS ordered list (D-09/D-10/D-11)
- [Phase 23-cdmtab-lua-unification]: CDMTab.lua uses ns:GetDisplayInfoForKey for all icon resolution (zero shim calls, zero type-string branches); META_DESCRIPTIONS promoted to file-level local; SUGGESTED_BUFFS fully replaced by SUGGESTED_KEYS at all 4 reader sites
- [Phase 23-cdmtab-lua-unification]: D-18/D-19: CLASS_LUST_SPELL and GetHunterLustSpell demoted to Providers.lua module-local after D-20 grep gate confirmed zero external readers
- [Phase 24-cleanup]: Phase 24-02 hot-path audit: note_text NONE — no performance note in v0.2.4 CHANGELOG per D-08 (zero per-frame/per-event allocation regressions across all three audited paths)
- [Phase 24]: [Phase 24 Plan 01]: DISP-04 closed — grep-gated deletion of 3 shims, 2 FALLBACK_ORDER exports, 2 obsolete CSV files; ns:RefreshMetaIcons renamed to ns:RefreshProvidersAtRest; 8 stale Phase-N migration-history comments scrubbed per D-03
- [Phase 24-cleanup]: Phase 24 Plan 03: stylua-clean, CHANGELOG v0.2.4 D-07 one-liner (no perf note per D-08 audit NONE), both pending todos closed (D-05/D-06), schema unchanged at 3 (D-12), DISP-04 closure gates all green — working tree ready for /gsd:complete-milestone (D-13 boundary respected)

### Pending Todos

(none)

### Blockers/Concerns

(none)
