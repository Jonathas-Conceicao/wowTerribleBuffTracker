---
phase: 74-buff-duration-on-spell-cooldowns
verified: 2026-10-22T00:00:00Z
status: passed
score: 12/12 must-haves verified (5/5 roadmap success criteria)
overrides_applied: 0
deferred_to_phase_78:
  - "Add on the Cooldowns tab: Advanced shows an unticked 'Track buff duration', a greyed Aura ID showing the Spell ID, and an empty greyed Duration"
  - "Ticking the checkbox enables both boxes and shows 'Advanced: Enter the buff duration' with Add disabled until a duration is typed; Tab skips greyed boxes"
  - "An Edit reopens with the saved checkbox, Aura ID and Duration; a Buffs-tab or Reminders-tab Add shows none of the three fields"
  - "With the buff on, a cast shows the buff countdown on the cooldown's icon and the cooldown continues underneath once it ends"
  - "Clicking the buff off or a dispel ends it after the cast grace, out of combat; it never ends during a secret-aura restriction"
  - "A recast restarts the buff; the CDM settings window and Edit Mode preview the typed buff duration"
  - "/reload or logout keeps the settings and loses only the running timer"
---

# Phase 74: Buff Duration on Spell Cooldowns Verification Report

**Phase Goal:** A player can give any user spell cooldown tracker its buff, and casting the spell runs a buff timer of the typed duration alongside the cooldown.
**Verified:** 2026-10-22
**Status:** passed (code-level). In-game checks are deferred to the Phase 78 retail pass by user decision.
**Re-verification:** No. This is the initial verification.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | The add and edit dialogs of a userCd show on Advanced a "Track buff duration" checkbox (off on new and existing trackers), an Aura ID pre-filled with the spell ID, and an empty Duration | VERIFIED | CDMTab.lua:2376-2481 has three defs, each with `tab = "advanced"` and `visible = CarriesCooldownBuff` (`ctx.kind == ns.KIND.USER_CD`, :1899). `ctx.kind` is set to USER_CD by OpenForAdd on the spells category (:2973) and to `entry.trackerType` by OpenForEdit (:3011). The checkbox's reset is `SetChecked(false)` and its prefill is `entry.buffEnabled == true`, so a missing key reads as off. buffAuraID is built with `BuildFollowSpellIDField`, whose reset sets followsSpell and whose update copies the Spell ID text in. buffDuration's reset is `SetText("")`, and it has no `update`, so it is never auto-filled. |
| SC2 | Ticked: save is refused until the Aura ID and a positive Duration are filled. Unticked: save succeeds and the fields keep their values with no effect | VERIFIED | `BuffFieldEnabled` (:1905) reads the checkbox. RefreshState (:2831-2836) sets `field.enabled` compare-before-write and greys through `ApplyFieldEnabled` (:1743). ValidateAll skips fields where `field.enabled == false` (:2788). The confirm read loop (:2929-2934) still reads every relevant field, so greyed values are saved. When ticked: buffDuration's validate rejects "" ("Enter the buff duration") and unparseable input (DURATION_HINT), and ParseDuration rejects values <= 0. buffAuraID's validate rejects a box the user emptied (`requiredMessage`). The runtime ignores the values while the box is off because `ns:CooldownBuffDuration` requires `buffEnabled == true` (Core.lua:759). |
| SC3 | With the buff on, a cast starts a buff timer of the typed duration at the same moment as the cooldown, and the cooldown runs unchanged | VERIFIED | Providers.lua:340-343: `StartCooldownFromCast` (unchanged, :182-192) runs and is followed by `ns:StartCooldownBuffFromCast(cdKey, tracked[cdKey])`. That function (:213-245) refuses hidden entries, bar containers and buff-off entries. It calls `FillUserBuffProc`, then overrides `duration` and `expiresAt` with `now + buffDuration`, sets `ns.activeTimers[key] = proc`, and stays allocation-free. `cooldownStarts`, `ns:CooldownDuration` and ApplyUserCooldown are untouched. The cross-spell skip key `cdKey` prevents the same cast from ending its own buff. |
| SC4 | The buff ends early on a readable aura-gone read and never on a secret read | VERIFIED | `proc.aliveBuffs = ns:AcquireAliveBuffs(key, ns:CooldownBuffAuraID(entry))` (Providers.lua:236). `castAt` is kept from Fill. `ns:ScanActiveTimersForCancellation` (BuffEngine.lua:1608) is generic over every proc that has aliveBuffs. It aborts on an unreadable `ns:ReadPlayerAura` and respects `CAST_AURA_GRACE`, and OnUnitAura skips it while `C_Secrets.ShouldAurasBeSecret()` is true. `QueueCastAuraRecheck` is queued on cast. The aura-read gate passes with an unchanged allowlist. |
| SC5 | Settings survive logout and login; existing trackers load with the buff off; no schema change, so no dry-run is needed | VERIFIED | ENGINE_OWNED (BuffEngine.lua:1125-1135) does not list any buff* key. `AddTrackedBuff` copies every non-owned field (:1222). `UpdateTrackedBuff` copies the read keys (:1390-1397). `CURRENT_SCHEMA_VERSION = 12` is unchanged, and `scripts/migrate-dryrun.js` is unchanged since 094e619. Missing keys read as off in the dialog (`== true`) and at runtime (`CooldownBuffDuration`). |
| P1-1..6 | 74-01 plan truths: field contract enabled hook, greyed/skip-focus/no-block, follow and empty rules, "Advanced: ..." message, save/prefill of the three keys | VERIFIED | As in SC1 and SC2. Tab ring (:2858) and FocusFirstShown (:2874) both test `field.enabled ~= false`. ValidateAll prefixes "Advanced: " for advanced-tab fields. buffAuraID read stores nil when the value equals the Spell ID. buffDuration prefill uses FormatDuration and its read returns originalValue when the text is unchanged. |
| P2-3 | A recast restarts the buff; a hidden or unloaded tracker starts neither | VERIFIED | The pooled proc is refilled on every cast. The `section ~= "hidden"` guard is present. `cooldownKeyBySpell` only indexes `ns:IsTrackerLoaded(key)` entries (Core.lua:1404). |
| P2-5 | The buff draws only on the cooldown's own icon; "Resets when you cast" ends both; turning the buff off on edit ends the running buff | VERIFIED | The proc is keyed by the cooldown key. The bar-container guard is in the start function. Display.lua's `elseif timer then` branch (:1635) sits above the cooldown-slot branch. ApplyEndOnCast's USER_CD branch nils `activeTimers[k]` (BuffEngine.lua:1510). UpdateTrackedBuff nils `activeTimers[newKey]` when the buff is off (:1400). |
| P2-6 | Preview uses the typed buff duration | VERIFIED | StartAllPreviewTimers (BuffEngine.lua:1563-1581) sets `duration = buffDuration` when `IsCooldownSlotEntry` and `CooldownBuffDuration` are both truthy. `GetDisplayInfo` is unchanged. |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `CDMTab.lua` | enabled hook, ApplyFieldEnabled, buffEnabled/buffAuraID/buffDuration fields | VERIFIED | Exists, substantive, and wired into RefreshState, ValidateAll, the focus ring and the confirm loop |
| `Core.lua` | `ns:CooldownBuffDuration`, `ns:CooldownBuffAuraID` | VERIFIED | :758 and :772. Called from Providers.lua and BuffEngine.lua (preview and edit-off) |
| `Providers.lua` | `ns:StartCooldownBuffFromCast` and its call in OnTrigger | VERIFIED | :213 definition, :342 single call |
| `BuffEngine.lua` | end-on-cast, preview and edit-off | VERIFIED | :1510, :1566, :1400 |
| `Display.lua` | comment-only changes | VERIFIED | `git diff 0c32ed4~1 HEAD -- Display.lua` contains no non-comment lines |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| RefreshState | def.enabled / ApplyFieldEnabled | compare-before-write on field.enabled | WIRED |
| ValidateAll | greyed fields | `field.relevant and field.enabled ~= false` | WIRED |
| confirm handler | AddTrackedBuff / UpdateTrackedBuff | `values[entryKey] = def.read(...)`, buff keys not in ENGINE_OWNED | WIRED |
| OnTrigger | StartCooldownBuffFromCast | `ns:StartCooldownBuffFromCast(cdKey, tracked[cdKey])` | WIRED |
| StartCooldownBuffFromCast | ScanActiveTimersForCancellation | aliveBuffs + castAt + QueueCastAuraRecheck | WIRED |
| activeTimers[cdKey] | RenderIconContainer | GetActiveTimers, then activeByKey[entry.key], then the `elseif timer then` branch | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real Data | Status |
|----------|------|--------|-----------|--------|
| Cooldown icon buff sweep | `timer.startedAt/duration` | proc filled from `entry.buffDuration`, which the dialog saved | Yes | FLOWING |
| Preview sweep | `duration` | `ns:CooldownBuffDuration(entry)` | Yes | FLOWING |
| Cancellation | `proc.aliveBuffs` | `entry.buffAuraID` or `entry.spellID` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| No new aura reader | `node scripts/aura-read-gate.js` | AURA-READ GATE PASS (1 reads in 1 allowlisted readers) | PASS |
| Gate fixtures | `node scripts/aura-read-gate.js --selftest` | 30 cases PASS | PASS |
| Format and Lua parse | `stylua --check .` | exit 0 | PASS |
| Migrations unaffected | `node scripts/migrate-dryrun.js --selftest` | 13 cases PASS | PASS |
| Line endings | `git ls-files --eol` on the 5 Lua files | all `w/crlf` | PASS |
| Stale comments removed | grep for "never enters ns.activeTimers" and similar | no hits | PASS |

### Probe Execution

None is declared or applicable. This phase is not a migration or tooling phase, and the schema is unchanged.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| BUFFCD-01 | 74-01 | SATISFIED | SC1 |
| BUFFCD-02 | 74-01 | SATISFIED | SC1, SC2 |
| BUFFCD-03 | 74-02 | SATISFIED | SC3 |
| BUFFCD-04 | 74-02 | SATISFIED | SC4 |
| BUFFCD-08 | 74-01, 74-02 | SATISFIED | SC5 |

REQUIREMENTS.md maps exactly these five IDs to Phase 74, so no requirement is orphaned.

### Anti-Patterns Found

No TBD, FIXME, XXX, TODO or HACK markers appear in lines added since 0c32ed4~1. Notes on behaviour outside the requirements, none of which blocks:

| File | Line | Note | Severity |
|------|------|------|----------|
| BuffEngine.lua | 1400 | An edit that keeps the buff on but changes the Aura ID or Duration does not update an already-running buff proc (stale aliveBuffs and expiry until the next cast). Only "off" ends it. | Info |
| Providers.lua | 236 | aliveBuffs is the single typed Aura ID, which overrides any rank family for a "cover all ranks" cooldown. On Forever, a rank whose aura ID differs could end the buff after the grace. | Info |
| CDMTab.lua | 2462-2467 | Unparseable Duration text left in the box after unticking reads as nil, so the text is not kept. This is unreachable in practice because a greyed box cannot be typed in. | Info |

### Deferred to Phase 78 (in-game, retail)

1. Cooldowns-tab Add, Advanced tab: an unticked checkbox, a greyed Aura ID showing the Spell ID, and an empty greyed Duration.
2. Ticking the checkbox enables both boxes. "Advanced: Enter the buff duration" shows and Add stays disabled until a duration is typed. Tab skips greyed boxes.
3. Edit reopens with the saved values. The Buffs and Reminders tabs show none of the three fields.
4. A cast shows the buff countdown on the cooldown's icon, and the cooldown shows after the buff ends.
5. A buff clicked off or dispelled ends after the cast grace. It never ends during a secret-aura restriction.
6. A recast restarts the buff. The CDM settings window and Edit Mode preview the typed buff duration.
7. /reload keeps the settings and drops only the running timer.

### Gaps Summary

There are no code gaps. Every roadmap success criterion and every plan must-have traces to wired, substantive code. The static gates, the formatter check and the migration selftest all pass.

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
