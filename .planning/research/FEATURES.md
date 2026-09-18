# Feature Research — WoW Forever Cross-Flavor Parity

**Domain:** WoW addon (Cooldown-Manager-integrated buff/cooldown timer tracker), porting an existing shipped feature set to a new game flavor (WoW Forever, game type `camelot`, Interface 16001, beta build 1.60.1.69893 as of 2026-09-17)
**Researched:** 2026-09-18
**Confidence:** Mixed — HIGH for anything verifiable by diffing Blizzard UI source between the `forever`/`forever-beta` and `live`/12.1 branches; LOW-MEDIUM for anything that depends on live game data (spell IDs, per-spell secrecy allowlists, class/content availability) that isn't visible in UI Lua source and can only be confirmed in-game.

This is not a "what should we build" feature study — TBT already ships every capability below on Midnight retail. The question is which of those capabilities survive unmodified on Forever, which degrade gracefully, which would break, and which are simply unknowable from source. That categorization is what drives the v0.3 "parity only" milestone's in-game verification pass.

## Method

- Diffed the exact files TBT depends on between `Gethe/wow-ui-source` branches `forever` and `live` (both mirror `BigWigsMods/WoWUI`'s `forever-beta`/`live`; `forever`/`forever-beta` were fetched directly from GitHub via `raw.githubusercontent.com` and the Trees API — no local clone was modified, per the constraint not to touch the user's `wow-ui-source` working tree).
- Cross-checked the generated API doc files (`Blizzard_APIDocumentationGenerated`) that formally declare secrecy flags and function signatures.
- Corroborated with two third-party, dated, beta-build-specific sources for anything not resolvable from UI source alone (server-side event/data behavior): [`Thunderz96/forever-addon-kit`](https://github.com/Thunderz96/forever-addon-kit) (a live-captured API/behavior baseline from the Forever beta, build 1.60.1.69893, 2026-09-17) and [`Caeth/CleanCombatLog`](https://github.com/Caeth/CleanCombatLog) (an addon actively probing CLEU on Forever). These are community research repos, not official Blizzard documentation — treated as MEDIUM confidence at best, explicitly flagged wherever relied upon.

---

## Capability Compatibility Matrix

### 1. Cooldown Manager (CDM) — hard dependency, no standalone fallback

| Sub-capability | Category | Confidence | Evidence |
|---|---|---|---|
| `Blizzard_CooldownViewer` addon loads on Forever | **Works as-is** | HIGH | `Interface/AddOns/Blizzard_CooldownViewer/Blizzard_CooldownViewer.toc` diff: live has `## AllowLoadGameType: standard`; forever has `## AllowLoadGameType: standard, camelot`. This is an explicit Blizzard allow-list addition, not a leftover/dormant flag — Forever is deliberately included. |
| `BuffBarCooldownViewer` / `BuffIconCooldownViewer` global frames, `itemFramePool` | **Works as-is** | HIGH (source) + MEDIUM (empirical) | `CooldownViewer.xml` line 320/331 names identical in both branches; `itemFramePool` construction (`CreateFramePool("FRAME", self:GetItemContainerFrame(), self.itemTemplate, itemResetCallback)`) and its `EnumerateActive()` usage are unchanged. Independently, `forever-addon-kit`'s live-captured Forever session data (`data/forever_api.json`) lists `BuffBarCooldownViewer`, `BuffIconCooldownViewer`, `CooldownViewerSettings`, and `GroupBuffFilter` as real, enumerated globals from an actual play session — not just declared-but-dormant XML. |
| `CooldownViewer.lua` internals (`CooldownViewerMixin`) | **Works as-is** | HIGH | 64-line diff, entirely internal Blizzard refinements: `GetCooldownID()` nil-guards, `GetInventoryItemCooldown` now also reads `isOnGCD`, a new `EditMode.RefreshCooldownViewer` callback, debug-log comment reformatting. None touch `itemFramePool`, `GetItemContainerFrame`, or any field TBT reads. |
| `CooldownViewerSettings` tab structure (`SpellsTab`/`AurasTab`/`GroupBuffsTab`) | **Works as-is** | HIGH | `CooldownViewerSettings.xml` line 169/181/193: identical `parentKey` names and template inheritance in both branches. TBT's XML anchor (`CDMTab.xml`, anchors to `$parent.AurasTab`) and its runtime tab discovery (`CDMTab.lua` `CollectCDMTabs`, which walks `CooldownViewerSettings:GetChildren()` filtering on a `displayMode` string field, with `KNOWN_CDM_TABS = {"GroupBuffsTab","AurasTab","SpellsTab"}` as fallback) both hold unchanged. |
| `CooldownViewerSettingsTabTemplate` mixin change | **Works as-is (no effect on TBT)** | HIGH | Forever adds `mixin="CooldownViewerSettingsTabMixin"` to Blizzard's own tab template (`CooldownViewerSettingsSetTooltipTextSetupFunction` support for the disabled Group Buffs tooltip). TBT's tab (`CDMTab.xml`) inherits `LargeSideTabButtonTemplate` directly — explicitly *not* `CooldownViewerSettingsTabTemplate`, by design (comment: "does NOT use parentArray to avoid tainting CDM's secure TabButtons iteration") — so this change doesn't apply to TBT's tab at all. |
| `GetExtraPanelWidth()` (side panel width calc) | **Works as-is** | HIGH | Changed from hardcoded `return 50` to `self.SpellsTab:GetWidth() + 7`. Blizzard's own `SpellsTab` width is unchanged, so the computed result is identical; not something TBT reads. |
| Reorder marker frame relocation | **Works as-is (no effect on TBT)** | HIGH | Forever nests Blizzard's `ReorderMarker` frame one level deeper in the XML tree (`self.CooldownScroll.Content.ReorderMarker` vs. a sibling `Frame`) — purely Blizzard's own list-reorder visual. TBT builds and owns its own separate reorder marker (`CDMTab.lua` `GetOrCreateReorderMarker`) — unaffected. |
| `COOLDOWN_VIEWER_DATA_LOADED` event, used as one of three gating events for both Blizzard's settings init and TBT's `ns:InitCDMTab` | **Works as-is** | HIGH | `CooldownViewerSettings.lua` line 854 (live) / 856 (forever): `EventUtil.ContinueAfterAllEvents(LoadCooldownSettings, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED")` — byte-identical. TBT's own `CDMTab.lua` bottom-of-file init gate copies this exact pattern. |
| `GroupBuffFilter.lua` (used by `ShowTBTPanel`/`HideTBTPanel` to hide/restore the Group Buffs content pane) | **Works as-is** | HIGH | 2-line diff, a `GetCurrentVisualAlerts()` lookup unrelated to TBT's usage (`CooldownViewerSettings.GroupBuffFilter:Hide()/SetShown()`). |
| CDM's own built-in spell/cooldown suggestions for Forever specs | **Works but degraded/empty (Blizzard's own data, not TBT's)** | MEDIUM (third-party) | `forever-addon-kit` README: "Every `C_CooldownViewer` category is empty for Forever specs, even with unlearned spells shown." This means Blizzard's *own* CDM content (what shows in the Spells/Auras tabs by default) may be sparse in this beta — a content-population gap on Blizzard's side, not a TBT dependency. TBT never reads `C_CooldownViewer` category data; it only anchors to the container frames. Included here so the milestone doesn't mistake "CDM's own list looks empty" for "TBT is broken." |

**Overall for CDM: Works as-is**, HIGH confidence for every structural/API element TBT actually touches. The one open item is whether the settings window visually opens and lays out normally given Blizzard's own beta content gaps — see verification checklist below.

### 2. Edit Mode

| Sub-capability | Category | Confidence | Evidence |
|---|---|---|---|
| `EventRegistry:TriggerEvent("EditMode.Enter"/"EditMode.Exit")` | **Works as-is** | HIGH | `Shared/EditModeManager.lua`: `EnterEditMode()` and `ExitEditMode()` are **byte-identical** between branches (same line-for-line body, only line numbers shift because unrelated code was added earlier in the file). TBT's entire Edit Mode integration is two `EventRegistry:RegisterCallback("EditMode.Enter"/"EditMode.Exit", ...)` calls in `EditModeFrames.lua` — the exact events, unchanged. |
| TBT is not a registered `EditModeSystem` | **Works as-is (not applicable)** | HIGH | TBT's containers (`TBTBarContainer`, `TBTBuffContainer`) are plain `CreateFrame("Frame", ..., UIParent)` instances using `SetMovable`/`StartMoving`/`StopMovingOrSizing` — they never subclass `EditModeSystemMixin` and are never in `EditModeManagerFrame.registeredSystemFrames`. All the new/changed system mixins in `EditModeSystemTemplates.lua` (see below) are therefore irrelevant to TBT by construction. |
| `EditModeSettingDropdownTemplate` / `EditModeSettingSliderTemplate` / `EditModeSettingCheckboxTemplate` (used by `ns:ShowSettingsPopup`) | **Works as-is** | HIGH | `Shared/EditModeTemplates.xml` is byte-identical between branches (0-line diff after fetch); all three templates present in both. |
| `EditModeSystemTemplates.lua` — new content | **Works as-is (additions only)** | HIGH | Diff (3630→3787 lines) adds: `EditModeMicroMenuSystemMixin:ApplySystemAnchor` (QueueStatusButton anchor logic), new `EditModeSwingTimerSystemMixin`, `EditModeMainActionBarEndCapSystemMixin`, `EditModeGroupFinderSystemMixin`, and a `dynamicEndCaps`→`manageEndCaps` field rename on one internal check. All are pure additions or internal renames on mixins TBT never touches (confirmed: `grep` for `dynamicEndCaps`/`manageEndCaps` across TBT's own files returns nothing). No removals found anywhere in the diff. |
| `Enum.EditModeCooldownViewerSetting` (used by "Copy Blizzard CDM Config": `Orientation`, `IconDirection`, `IconSize`, `IconPadding`, `Opacity`, `VisibleSetting`, `BarContent`, `HideWhenInactive`, `ShowTimer`, `ShowTooltips`, `BarWidthScale`) | **Works as-is** | HIGH | `EditModeManagerConstantsDocumentation.lua` diff (953→1045 lines) is entirely scoped to `EditModeAccountSetting` (new `ShowGroupFinder`/`ShowSwingTimer` account toggles) and three brand-new enums (`EditModeGroupFinderSetting`, `EditModeMainActionBarEndCapSetting`, `EditModeSwingTimerSetting`) plus one `EditModeMicroMenuSetting` field rename (`EyeSize`→`DeprecatedEyeSize`, unrelated to CDM). `EditModeCooldownViewerSetting`'s own field block is untouched. |
| Forever's `Camelot/` EditMode override folder | **Works as-is (no effect on TBT)** | HIGH | New `Interface/AddOns/Blizzard_EditMode/Camelot/{EditModeManagerOverrides.lua, EditModeUtil.lua, EditModePresetLayoutConstants.lua}` customize Blizzard's *own* default-UI managed frames for the Camelot flavor (hides ArenaFrames/ArchaeologyBar/TalkingHeadFrame Edit Mode checkboxes since those systems don't exist; adds a Totem Action Bar and Swing Timer). None of it touches the generic `EnterEditMode`/`ExitEditMode`/Enter/Exit events or the setting-widget templates TBT depends on. |

**Overall for Edit Mode: Works as-is**, HIGH confidence — every line TBT's Edit Mode integration actually executes was diffed and found unchanged or unaffected by nearby additions.

### 3. Event + timing core

| Sub-capability | Category | Confidence | Evidence |
|---|---|---|---|
| `UNIT_SPELLCAST_SUCCEEDED` fires with a usable numeric `spellID` | **Unknown — needs in-game verification** | — | This is a server/client core event, not scripted in Lua UI source — it cannot be confirmed or refuted by diffing `wow-ui-source`. PROJECT.md's own Context section states Forever "follows a Midnight-style API," which is the working assumption TBT's whole architecture depends on, but no direct evidence was found either way. |
| `COMBAT_LOG_EVENT_UNFILTERED` disabled or available on Forever | **Unknown (observation only — no action this milestone)** | LOW (third-party, actively being tested) | `Caeth/CleanCombatLog`'s README frames this as an open question as of the same beta build (1.60.1.69893, 2026-09-17): it ships a `/ccl cleu` test specifically because the answer wasn't known yet. `Thunderz96/forever-addon-kit`'s Tier-1 watchlist item #3 lists the same question as unresolved. One indirect signal: `forever-addon-kit` states "creature health and damage numbers are secret" on Forever, consistent with Midnight's restriction pattern carrying over — but that doesn't confirm CLEU specifically. Per the milestone scope, this is recorded for awareness only; TBT is not changing its cast-detection strategy regardless of the answer. |

**Overall: Unknown for the one item that matters (`UNIT_SPELLCAST_SUCCEEDED` payload), observation-only for CLEU.** This is the single highest-priority item for in-game verification since every timer TBT starts depends on it.

### 4. Secret values (`C_Secrets`, `UNIT_AURA` payload)

| Sub-capability | Category | Confidence | Evidence |
|---|---|---|---|
| `C_Secrets.ShouldAurasBeSecret()` / `ShouldSpellAuraBeSecret(spellID)` — function existence, signature, return shape | **Works as-is** | HIGH | `SecretPredicateAPIDocumentation.lua` diff between branches is a single blank-line addition — the `ShouldAurasBeSecret` (line 119) and `ShouldSpellAuraBeSecret` (line 139) entries, including `SecretArguments = "AllowedWhenUntainted"` and return types, are byte-identical. |
| `C_UnitAuras.GetPlayerAuraBySpellID` — signature and secrecy flags (used by `ns:ReadPlayerAura`) | **Works as-is** | HIGH | `UnitAuraDocumentation.lua` diff: the only functional change is a *new* function (`GetAuraCasterGUID`) being added; `GetPlayerAuraBySpellID`'s own entry (`SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true`, `SecretArguments = "AllowedWhenTainted"`, `Returns: aura: AuraData, Nilable = true`) is unchanged. |
| The blanket combat restriction itself (`ShouldAurasBeSecret() == true` in combat, throwing on any restricted aura read) | **Works as-is (confirmed empirically)** | MEDIUM (third-party, but concrete/dated) | `forever-addon-kit` Bug Report #4 (filed against the same build, 2026-09-17): "Every aura read throws 'Auras cannot be accessed when secret while tainted'" for the player's own auras in combat, and "the `UNIT_AURA` event's added/removed lists also arrive as secret tables." This is exactly the behavior TBT's `ns:ReadPlayerAura`, `ns:CanReadTable`, `ScanActiveTimersForCancellation`'s `allReadable` guard, and `LustProviderMixin`'s `ScanSatedBySpellID` fallback were built to survive on Midnight — the underlying restriction pattern is present unchanged on Forever. |
| Per-spell "never secret" allowlist data (specifically: is spellID `57724` "Sated" — and the other four `SATED_DEBUFF_TO_LUST` keys — still flagged never-secret on Forever the way it is on Midnight 12.1?) | **Unknown — needs in-game verification** | — | This is live game *data* (a per-spell flag on the secrecy system), not something declared in the generated API doc files, which only describe function signatures/predicates in the abstract. Nothing in `wow-ui-source` exposes this table. The third-party bug report's combat-aura test did not target a known-allowlisted spell, so it neither confirms nor denies the allowlist survives. |

**Overall: Works as-is for the API surface** (HIGH confidence, directly diffed) — **Unknown for the specific allowlist data** that TBT's Lust provider and aura-cancellation scan lean on for in-combat behavior. See verification checklist.

### 5. Spell/aura APIs TBT calls directly

| API | Category | Confidence | Evidence |
|---|---|---|---|
| `C_Spell.GetSpellInfo` | **Works as-is** | HIGH | `SpellDocumentation.lua` diff: the `GetSpellInfo` entry itself (`MayReturnNothing = true`, `SecretArguments = "AllowedWhenTainted"`, returns `SpellInfo`) is byte-identical; the diff's only changes are new additions elsewhere in the file (`CancelAutoRepeatSpell`, `GetTargetSpellID`, `IsActiveSpell`, `PlaceTargetingSpellAtCursor`, `CancelItemTempEnchantment`). |
| Spell icon lookup (`ns:GetSpellIcon` → `C_Spell.GetSpellInfo(spellID).iconID`) | **Works as-is** | HIGH | TBT never calls the legacy `GetSpellTexture` global — confirmed by reading `BuffEngine.lua`'s `GetSpellIcon` implementation, which only calls `C_Spell.GetSpellInfo`. Covered by the row above. |
| `C_UnitAuras.GetPlayerAuraBySpellID` | **Works as-is** | HIGH | Covered under Secret Values above. |
| `GetTime()` | **Works as-is** | HIGH (by inference) | A trivial, non-secret, flavor-agnostic timestamp function present in every WoW client build since Classic Era; no plausible mechanism for removal or signature change. Not independently diffed (not present in any doc-generated file — it's a raw global, like most base Lua-API-extension functions). |
| `CreateFromMixins`, `hooksecurefunc`, `UISpecialFrames` | **Works as-is** | MEDIUM-HIGH (by inference, not directly diffed) | These are foundational, engine-level Lua API globals — not defined in any `wow-ui-source` Lua file (targeted search across `Blizzard_UIParent`, `Blizzard_UIPanelTemplates`, `Blizzard_FrameXMLBase` found no declaration for `UISpecialFrames` or `CreateFromMixins`, confirming they're baked into the client binary, not addon-visible Lua source). They have been stable, unchanged API surface across every WoW flavor (Classic Era through current retail) for over a decade. `forever-addon-kit`'s captured baseline (6,045 global functions, 11,417 named frames) is consistent with a full modern/Mainline global surface, not a stripped one. No direct evidence either way, but also zero indication of removal — this is the weakest-evidence "Works as-is" call in this document and worth a cheap in-game sanity check. |

**Overall: Works as-is** for every API in this section — HIGH confidence for the four directly diffed, MEDIUM-HIGH for the three foundational globals that can only be checked in-game or by successful addon load with zero errors.

### 6. Content-dependent data — Trinket, Pot, and Lust providers

**No fix is proposed here — this section documents behavior only, per the milestone's explicit "parity only, no content work" scope.**

**TrinketProvider / PotProvider** (`Providers.lua`, `TRINKET_SPELLS`/`POT_SPELLS` tables and their mixins):

- Both tables are keyed by hardcoded, current-TWW-season retail spellIDs (e.g. `1259633` Light Company Guidon, `1236616` Light's Potential) mapped to matching itemIDs.
- **Cast detection (`OnTrigger`)**: does a direct table lookup — `TRINKET_SPELLS[spellID]` / `POT_SPELLS[spellID]` — against whatever `spellID` `UNIT_SPELLCAST_SUCCEEDED` delivers. Forever is a Classic-inspired, level-30-cap beta with none of this season's trinkets or potions in its item pool, so no cast a Forever player performs will ever match one of these keys. **Behavioral consequence: this is a silent, permanent no-op** — not an error, not a crash, just dead code that never fires on this flavor.
- **At-rest resolution (`RefreshAtRest`)**: scans `INVSLOT_TRINKET1/2` (`GetInventoryItemID`) and bag counts (`C_Item.GetItemCount`) against the same hardcoded itemID sets. None of those itemIDs can be equipped/held on Forever, so the scan always falls through to `TRINKET_FALLBACK_ORDER[1]` / `POT_FALLBACK_ORDER[1]` — a hardcoded itemID that is looked up in the static table regardless of whether it resolves to anything real in Forever's item/spell database.
- **Display (`GetDisplayInfo`)**: calls `C_Spell.GetSpellInfo(spellID)` on that fallback spellID. Per `GetSpellInfo`'s documented (and confirmed-unchanged) `MayReturnNothing = true` contract, a nonexistent spellID returns `nil` — so the label falls back to the hardcoded default string (`"Trinket"` / `"Damage Pot"`) and `ns:GetSpellIcon` falls back to the question-mark placeholder icon (`134400`).
- **Category: Works but degraded/empty.** No Lua errors expected. The Suggested-section tiles for Trinket and Pot will most likely render as a generic question-mark icon with a generic label, and will never produce a real timer from any in-game action on Forever. **This is expected, not a bug** — testers should not report "trinket tracker shows a question mark and never fires" as a regression; it's the correct, documented consequence of retail-season-specific data on a Classic-styled flavor with no equivalent content.

**LustProvider** (`Providers.lua`, `SATED_DEBUFF_TO_LUST`, `CLASS_LUST_SPELL`, `GetHunterLustSpell`):

- Maps five Sated-family debuff spellIDs (`57724`, `57723`, `80354`, `390435`, `264689`) to five lust-buff spellIDs (`2825` Bloodlust, `32182` Heroism, `80353` Time Warp, `390386` Fury of the Aspects, `264667`/`466904` Hunter pet lust).
- Two of these spellIDs (`2825` Bloodlust, `32182` Heroism) are extremely long-lived — present since Vanilla/Wrath — and are *plausible* candidates to share the same numeric ID on Forever if the flavor shares the modern engine's persistent spell ID space for continuity abilities. This is speculation, not confirmed: spell data is server-side and invisible to a UI-source diff.
- The other three (`80353` Time Warp/Mage, `390386` Fury of the Aspects/Evoker, `466904` Harrier's Cry/MM Hunter) are tied to specs that may not exist, or may not be reachable, at Forever's current beta level cap of 30 (per `forever-addon-kit`'s watchlist). Evoker in particular is a modern-only class family whose presence in Forever's roster is unknown from source.
- **Category: Unknown — needs in-game verification**, distinct from Trinket/Pot's confirmed "always empty" verdict because Bloodlust/Heroism's long-lived spellIDs make a working outcome plausible rather than structurally impossible. If no lust-equivalent effect exists at all in Forever's current beta content, the behavioral consequence is identical to Trinket/Pot: `OnTrigger` never fires, a silent structural no-op, no error.
- The Suggested-section tile's label/icon (`LustProviderMixin:GetDisplayInfo`, via `CLASS_LUST_SPELL`) always resolves to *some* value even for a class with no real lust ability — it falls back to `2825` (Bloodlust) for any class not in `CLASS_LUST_SPELL`. If `2825` doesn't correspond to a real spell on Forever, the same graceful nil→placeholder degradation described for Trinket/Pot applies (generic label, question-mark icon) rather than an error.

---

## Feature Dependencies

```
CDM frame existence (BuffBarCooldownViewer/BuffIconCooldownViewer)
    └──required by──> Display.lua rendering (ns:InitDisplay bails with a chat print if neither exists)

CooldownViewerSettings tab structure
    └──required by──> CDMTab.lua tab injection, anchor discovery, taint-safe tab uncheck

EditMode.Enter / EditMode.Exit events
    └──required by──> EditModeFrames.lua container drag/select/settings-popup lifecycle

UNIT_SPELLCAST_SUCCEEDED delivering a usable spellID
    └──required by──> ALL timer starts (UserSpellProvider, TrinketProvider, PotProvider) — this is
                       the single load-bearing unknown; everything else in this matrix is secondary
                       to it actually firing correctly

C_Secrets API + per-spell allowlist for Sated debuffs
    └──required by──> LustProvider's in-combat detection path (ScanSatedBySpellID fallback)
    └──enhances────>  ScanActiveTimersForCancellation's ability to auto-cancel mid-combat

Trinket/Pot/Lust spellID catalogs (content data)
    └──independent of── every structural/API item above; these can be 100% broken while every
                          other capability in this matrix is 100% intact, because they gate on
                          data (hardcoded spellIDs), not on API/UI availability
```

### Dependency Notes

- The CDM/EditMode/Secret-Values/Spell-API items are all **independently verified structural facts** (diffable source) — a failure in any one of them would produce a Lua error or visible breakage during the addon-load / tab-injection / Edit-Mode-entry verification steps below, and none showed evidence of breakage.
- The event-core item (`UNIT_SPELLCAST_SUCCEEDED`) is the **one true unknown that everything else depends on**. If it doesn't fire with a usable spellID on Forever, nothing else in this addon can work regardless of how clean the rest of the API surface is — it should be the very first thing verified in-game.
- The content-data item (Trinket/Pot/Lust) is **structurally decoupled** from all of the above — it can (and, per this analysis, almost certainly will) be broken/empty on Forever while every other capability works perfectly. This is why it's explicitly out of scope for a fix this milestone and must not be conflated with a real parity bug during verification.

---

## Parity Definition (what "done" means for v0.3)

### Must hold on Forever (structural/API — this milestone's actual acceptance bar)

- [ ] Addon loads with zero Lua errors under the `_Camelot` TOC
- [ ] `BuffBarCooldownViewer`/`BuffIconCooldownViewer` are found and `ns:InitDisplay` does not print "Cooldown Manager not found"
- [ ] TBT tab is injected into CDM settings, anchored below Blizzard's bottom-most tab, and opens/closes its content panel correctly
- [ ] `UNIT_SPELLCAST_SUCCEEDED` triggers a UserSpellProvider timer for at least one manually-tracked test spell
- [ ] Edit Mode entry/exit shows/hides the TBT floating checkbox panel and NineSlice overlays, and position changes persist across a UI reload
- [ ] No Lua errors during a full loop: open CDM settings → open TBT tab → preview → drag between sections → close → re-open

### Expected to be empty/meaningless on Forever (content data — do not treat as bugs)

- [ ] Trinket Suggested tile: generic icon/label, never triggers from any Forever cast — **expected**
- [ ] Pot Suggested tile: generic icon/label, never triggers from any Forever cast — **expected**
- [ ] Lust Suggested tile: may or may not trigger depending on whether Bloodlust/Heroism-equivalent content exists at Forever's current level cap — **treat as unknown, not a confirmed bug, until tested**

### Out of scope this milestone (per PROJECT.md)

- Any new Forever-specific trinket/pot/lust spellID catalog — deferred, content work, not parity work
- Switching detection strategy even if `COMBAT_LOG_EVENT_UNFILTERED` turns out to be available on Forever

---

## In-Game Verification Checklist (Forever Beta)

Ordered from highest-risk/highest-payoff to lowest. Each step names the exact expected result so a pass/fail is unambiguous. Steps 1–6 are the acceptance bar; 7–10 answer the open research questions; 11 covers a beta-platform caveat that could otherwise cause false failure reports.

1. **Addon loads.**
   Install via the `_Camelot` TOC to the Forever client's AddOns folder, log in, and check for TBT's load-chat line (`TerribleBuffTracker loaded. Type /tbt...`).
   *Expected:* the load message prints; no red Lua error appears at login or during `PLAYER_ENTERING_WORLD`.

2. **CDM attaches.**
   Watch the login-time chat output for `TerribleBuffTracker: Attached to Cooldown Manager.` (from `ns:InitDisplay`).
   *Expected:* this message prints, NOT `Cooldown Manager not found. Addon disabled.` If the latter prints, `BuffBarCooldownViewer`/`BuffIconCooldownViewer` failed to resolve — stop and investigate before continuing (this would contradict the source-level "Works as-is" finding above and needs its own root-cause pass).

3. **CDM settings window opens and TBT tab is injected.**
   Run `/tbt`. This should open `CooldownViewerSettings` (if not already open) and select the TBT tab.
   *Expected:* the settings window opens without error; a TBT tab icon appears below Blizzard's existing tabs (Spells/Auras/Group Buffs, or however many exist in this beta build); clicking it shows the four TBT sections (Tracked Bars, Tracked Buffs, Not Displayed, Suggested) with no Lua error.

4. **Cast detection fires.**
   In the TBT tab's Suggested section, click "+" and add any known-castable spell on your current Forever character by spell ID (use the spellbook tooltip or `/dump C_Spell.GetSpellInfo(<name>)` to find one), with a short duration (e.g. 5s). Drag it into Tracked Bars. Cast that spell.
   *Expected:* a timer bar appears in the TBT bar container within roughly 0.05–1s of the cast completing, counts down from the configured duration, and disappears at zero. **This is the single most important check in this list** — it directly resolves the open `UNIT_SPELLCAST_SUCCEEDED` question from Section 3 above.

5. **Bar/icon rendering matches CDM visuals.**
   With the timer from step 4 active, visually compare the bar's icon mask, fill texture, and pip against Blizzard's own CDM bars (if any are visible) or against a known-good Midnight retail screenshot.
   *Expected:* icon is masked/rounded correctly, status bar fill uses the CDM atlas texture (not a fallback solid color), countdown text is legible. A visibly broken atlas texture would indicate an atlas-name change on Forever not caught by the source diff (none was found, but atlases are string names, not something the generated docs list exhaustively).

6. **Edit Mode works end-to-end.**
   Open Blizzard's Edit Mode (default keybind or Game Menu → Edit Mode). Confirm the "TerribleBuffTracker" checkbox panel appears anchored below the Edit Mode manager frame. Click a TBT container (bar or buff icon container) — it should show a yellow NineSlice "selected" overlay and open the TBT settings popup. Drag the container to a new position. Exit Edit Mode (click Done or press Escape). Reload UI (`/reload`).
   *Expected:* the container's new position persists after reload; no Lua error during Enter, drag, Exit, or the settings-popup slider/dropdown interactions.

7. **Combat secret-value gating behaves as expected.**
   Enter combat (e.g. attack a low-level mob). While in combat, attempt to view a tracked buff's tooltip or watch the debug log (`/tbt debug` then re-trigger an aura event).
   *Expected:* no Lua error is thrown from any aura read; if `ns.debugLogging` is on, you may see the "aura scan blocked — ShouldAurasBeSecret() returned true" message, matching Midnight's known behavior. A thrown error here (not caught by TBT's `ns:CanReadTable`/`ns:ReadPlayerAura` guards) would indicate a Forever-specific secret-value edge case not present on Midnight.

8. **Sated-family allowlist (Lust provider), if content permits.**
   If your Forever character is a Shaman (or any class with access to a Bloodlust/Heroism-equivalent effect) and such an effect exists in this beta's content, cast/receive it in combat. Separately, open the TBT tab's Suggested section as any class to confirm the Lust tile renders without error even if the class has no real lust spell.
   *Expected (primary):* if a lust effect exists and is cast, the Sated-family debuff triggers a 40s TBT timer even while in combat (mirrors Midnight's LUST-01 allowlist behavior). *Expected (fallback):* if no such effect exists in this beta's content at all, no timer starts, but opening the Suggested section still shows a placeholder tile with no Lua error (Bloodlust fallback in `GetDisplayInfo`).

9. **Trinket/Pot providers show placeholder, not error.**
   Open the TBT tab's Suggested section and hover the Trinket and Pot tiles.
   *Expected:* tooltip shows a generic label ("Trinket"/"Damage Pot") and a question-mark icon (or similar generic icon), consistent with the "Works but degraded/empty" analysis above. **A generic/empty tile here is correct and should NOT be filed as a bug.** Only a Lua error while hovering or dragging these tiles would indicate a real problem.

10. **Foundational-global sanity check.**
    Confirm no Lua error occurs anywhere that would indicate `CreateFromMixins`, `hooksecurefunc`, or `UISpecialFrames` are missing or behave differently — specifically, opening the Add Buff dialog (`UISpecialFrames` registration, so Escape closes it) and confirming Escape actually closes `TBTAddBuffDialog`.
    *Expected:* pressing Escape while the Add Buff dialog is open closes it, same as on Midnight.

11. **Session-hygiene caveat while testing.**
    Per a third-party bug report against this same beta build, the Forever client stops delivering Lua errors to any handler (including the default UI error frame and BugSack-style addons) after 100 errors in a single session, until `/reload`. If any other addon is installed alongside TBT and is error-flooding, TBT's own errors could go silently unreported.
    *Recommendation:* test with a minimal addon list (TBT + a Lua error display addon only), and `/reload` between test sessions rather than accumulating one long play session, to avoid a false "no errors" result.

**Known beta-platform risks unrelated to TBT's own code** (found via third-party bug reports against the same build, 1.60.1.69893, 2026-09-17 — flagged here so a failure isn't misattributed to TBT):
- **SavedVariables may not load at all.** A filed bug report claims addon SavedVariables files are written correctly on logout but never read back in at any point from `ADDON_LOADED` through `PLAYER_LOGOUT` — every addon starts from hardcoded defaults every session. If TBT's tracked-buff configuration or Edit Mode positions don't persist across a `/reload` on Forever, check whether *other* addons' SavedVariables also fail to persist before concluding it's a TBT-specific bug.
- **Secure handler snippets fail to compile** (`loadstring_untainted` missing) — does not affect TBT, which uses no `SecureHandlerWrapScript`/`_onstate-*` attributes, but is worth knowing if diagnosing unrelated addon interactions during testing.

---

## Sources

- `Interface/AddOns/Blizzard_CooldownViewer/{CooldownViewer.lua,.xml,Settings.lua,Settings.xml,GroupBuffFilter.lua,Blizzard_CooldownViewer.toc}` — diffed directly, `Gethe/wow-ui-source` branches `forever` vs `live`, fetched 2026-09-18
- `Interface/AddOns/Blizzard_EditMode/Shared/{EditModeManager.lua,EditModeSystemTemplates.lua,EditModeTemplates.xml}` and new `Camelot/*.lua` overrides — diffed directly, same branches/date
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/{SecretPredicateAPIDocumentation.lua,SecretPredicatesDocumentation.lua,UnitAuraDocumentation.lua,SpellDocumentation.lua,CooldownViewerConstantsDocumentation.lua,EditModeManagerConstantsDocumentation.lua}` — diffed directly, same branches/date
- [`Thunderz96/forever-addon-kit`](https://github.com/Thunderz96/forever-addon-kit) — `docs/BUG_REPORTS.md`, `docs/BETA_WATCHLIST.md`, `docs/retail_addon_portability.csv`, `data/forever_api.json` — third-party, live-captured from Forever beta build 1.60.1.69893, dated 2026-09-15/17. MEDIUM confidence (concrete, dated, build-specific; not official Blizzard documentation).
- [`Caeth/CleanCombatLog`](https://github.com/Caeth/CleanCombatLog) — README, same build. LOW-MEDIUM confidence (explicitly frames CLEU availability as an open, actively-tested question, not a confirmed answer).
- `C:\Users\jonat\.claude\projects\C--Users-jonat-Repositories-TerribleBuffTracker\memory\reference_121_secret_aura_api.md` — prior verified-in-game finding for Midnight 12.1 (Sated allowlist behavior), used as the baseline this research checks for parity against on Forever.
- TBT source read directly for this research: `Core.lua`, `BuffEngine.lua`, `Providers.lua`, `Display.lua`, `CDMTab.lua`, `EditModeFrames.lua`, `README.md`, `.planning/PROJECT.md`, `CLAUDE.md`.

---
*Feature research for: WoW Forever cross-flavor parity (v0.3 milestone)*
*Researched: 2026-09-18*
