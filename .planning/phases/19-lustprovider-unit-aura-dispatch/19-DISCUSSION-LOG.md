# Phase 19: LustProvider + UNIT_AURA Dispatch - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 19-lustprovider-unit-aura-dispatch
**Areas discussed:** Pre-gate routing, Event arg shape, No-restart guard, OnUnitAura shape, Preview semantics, Flag rename, Data location

---

## Pre-gate routing (LUST-01 preservation)

| Option | Description | Selected |
|--------|-------------|----------|
| Dispatch-first-by-position | OnUnitAura calls dispatcher BEFORE secret gate; LustProvider runs Sated check in OnTrigger. | (superseded) |
| Two-phase dispatch | Add pre-gate vs post-gate dispatcher concepts. | |
| BypassesSecretGate provider flag | Provider declares opt-in bypass; dispatcher checks for UNIT_AURA. | (proposed by Claude, rejected by user) |
| Fully provider-governed | Dispatcher has NO gate logic. Each provider handles its own secret-value safety (per-entry issecretvalue for lust). | ✓ |

**User's choice:** Fully provider-governed (final)
**Notes:** User rejected dispatcher-level gate logic: "avoid any 'exceptions' on events and have a shared behavior". Lust is safe because Sated IDs are Blizzard-allowlisted; per-entry issecretvalue covers defense. No dispatcher gate check.

---

## Event arg shape

| Option | Description | Selected |
|--------|-------------|----------|
| Provider iterates | Dispatcher passes updateInfo as-is; provider iterates addedAuras internally. | ✓ |
| Dispatcher iterates | Dispatcher special-cases UNIT_AURA per aura entry. | |

**User's choice:** Provider iterates internally
**Notes:** User confirmed raw event pass-through. Provider receives (event, unit, updateInfo), walks addedAuras, returns single proc or nil.

---

## No-restart guard location

| Option | Description | Selected |
|--------|-------------|----------|
| Provider-internal | LustProvider:OnTrigger checks ns.activeTimers["lust"] and returns nil if active. | ✓ |
| Dispatcher AllowsRefresh flag | Provider declares AllowsRefresh=false; dispatcher skips overwrite. | |
| Always overwrite | Remove guard; timer resets on every Sated re-fire. | |

**User's choice:** Provider-internal
**Notes:** Rule co-located with the provider. Dispatcher stays simple.

---

## OnUnitAura post-dispatch shape

| Option | Description | Selected |
|--------|-------------|----------|
| Keep gates + scan inline | OnUnitAura keeps secret gate, isFullUpdate, previewActive, scan call. | ✓ |
| Extract helper | Pull gates + scan into ns:HandleAuraPostDispatch; OnUnitAura becomes 2 lines. | |

**User's choice:** Keep gates + scan inline
**Notes:** No behavioral benefit from extraction; cosmetic only. Gates apply to scan only after Phase 19.

---

## Preview semantics for lust detection

| Option | Description | Selected |
|--------|-------------|----------|
| Provider checks previewActive (current v0.2.3 behavior) | Lust detection suppressed during preview. | |
| Provider runs normally during preview | Real lust procs fire mid-preview and naturally overwrite preview placeholders. Full preview-rewrite deferred to Phase 21. | ✓ |

**User's choice:** Provider runs normally during preview
**Notes:** User stated: "Providers should run normally during preview. It's the actual displaying that should change... preview should not OVERWRITE present trackers." Phase 19 removes the previewActive guard from lust detection; Phase 21 implements the full additive-preview pattern (LIFE-03).

---

## Flag rename (auraCheckBlocked)

| Option | Description | Selected |
|--------|-------------|----------|
| Rename to secretGateLogged | Update ClearAuraBlock to ClearSecretGateLog. Same behavior, clearer name. | ✓ |
| Delete entirely | Remove flag + clear function. Log always or never. | |
| Other name | Propose alternate | |

**User's choice:** Rename to secretGateLogged
**Notes:** Flag is purely a one-shot debug log suppression. Rename makes clear it's about secret-gate logging, not a gate itself.

---

## Data location

| Option | Description | Selected |
|--------|-------------|----------|
| Lust data colocated with LustProvider in Providers.lua; ns.* exports preserved for external readers (cancellation scan, CDMTab) | Matches Phase 18 hybrid pattern. | ✓ |
| Keep in BuffEngine, providers reference via ns.* | Minimal churn | |

**User's choice:** Colocate with LustProvider (hybrid move)
**Notes:** User stated: "lust variables like CLASS_LUST_SPELL and so on should be alongside lust dispatcher if it's on a new file they should also be moved there." Follows Phase 18 D-08 precedent.

---

## Claude's Discretion

- Exact placement within Providers.lua (after PotProvider, matching ns.providers order)
- Debug log wording for renamed ClearSecretGateLog
- Whether GetHunterLustSpell is inline or separate local

## Deferred Ideas

- StartAllPreviewTimers full rewrite to additive-preserve pattern — Phase 21 (LIFE-03)
- Shared gate-aware aura reader helper — no consumer today, build when needed
- Delete secretGateLogged flag entirely — user opted to rename instead
