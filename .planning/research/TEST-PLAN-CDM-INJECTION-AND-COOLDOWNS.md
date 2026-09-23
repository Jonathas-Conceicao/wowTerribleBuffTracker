# Test Plan — Non-CDM Cooldown Tracking & Native CDM Container Injection

**Written:** 2026-09-20
**Branch:** `dev` — experimentation only
**Status:** plan written, findings not yet gathered
**Companion:** `EXPERIMENTS-BUFF-API-AND-CDM.md` (API survey and evidence behind these two tests)

Two tests. Each must be proven in **three scenarios** before it counts as passing. Findings tables are
laid out below, empty, and are filled in-place as each scenario is run.

**Prioritisation rule (user decision, 2026-09-20):** techniques that already carry a shipping,
functional addon are tested before techniques derived only from the API documentation. Both tests below
are in the first category. Nothing in this plan rests on an untested doc inference except where flagged.

---

## The three scenarios

Different information is available in each, so a technique that works in one proves nothing about the
next. All three are mandatory, in order, and a technique that passes S1 and S2 but fails S3 is a
technique TBT cannot ship — dungeons are the content TBT exists for.

| | Scenario | How to reach it | What is different |
|---|---|---|---|
| **S1** | Out of combat, open world | Stand in a city or quest zone | No restrictions. `C_Secrets.ShouldAurasBeSecret()` and `ShouldCooldownsBeSecret()` both false. Everything reads plainly. This is the control: if a technique fails here it is broken, not restricted. |
| **S2** | In combat, open world | Attack a training dummy | **Combat restrictions only.** Aura and cooldown queries return secrets, but the chat-messaging lockdown and the restricted-map predicates are not in effect. `InCombatLockdown()` true. |
| **S3** | In combat, inside an instance | Pull a trash pack in any dungeon | **Combat + restricted-map restrictions.** `SecretOnRestrictedMaps` and `SecretInChatMessagingLockdown` add on top of S2. Unit identity, comparisons and additional aura paths that survived S2 may not survive here. This is the scenario that matters. |

**Per scenario, record first, before any probe:**

```
C_Secrets.HasSecretRestrictions()
C_Secrets.ShouldAurasBeSecret()
C_Secrets.ShouldCooldownsBeSecret()
C_Secrets.GetSpellCooldownSecrecy(<each probe spell>)
C_Secrets.GetSpellAuraSecrecy(<each probe spell>)
InCombatLockdown()
IsInInstance()
```

A spell that comes back `Enum.SecrecyLevel.NeverSecret` will produce a false pass that looks like a
breakthrough. Record the secrecy level of every probe spell or the results are not interpretable.

**Both clients.** Run all three scenarios on `_retail_` **and** `_classic_beta_` (Forever).
`_beta_` and `_ptr_` are out of scope. If Forever returns `HasSecretRestrictions() == false`, none of
the restriction findings apply there and the two clients get separate conclusions — do not merge them.

**Safety rules that apply to every probe:**

1. `pcall` the call. It does **not** cover a comparison or concatenation done on the result afterwards.
2. Per value, always in this order: `issecretvalue()` → `type()` → `canaccesstable()` → only then read.
3. `type()` reports `"number"` for a secret number. A type check alone is false confidence.
4. Never `tostring()` or concatenate a value that might be secret.
5. Log to a table and print after leaving the restricted context, not during.
6. Visual outcomes cannot be asserted in Lua. Screenshot them.

---

# Test 1 — Cooldown tracking for skills the Blizzard CDM does not support

## Does the non-CDM scope change the API? No.

`C_Spell.GetSpellCooldownDuration(spellIdentifier, ignoreGCD)` is a **`C_Spell`** API. It takes a
spell identifier and returns a `LuaDurationObject`. It has no `cooldownID` parameter, does not touch
`C_CooldownViewer`, and does not consult the CDM's spell table. Nothing about it is CDM-scoped.

It is in fact the *only* tier-1 source available for a non-CDM spell, which makes it more important
here rather than less: the CDM-item-frame data route (Test 2's finding, and the companion document's
"data source" section) works **only** for spells the CDM has an item frame for. A spell the CDM does
not support has no frame, so `GetSpellCooldownDuration` is the whole of its tier-1 story.

Confirmed from the generated documentation:

| API | Tier | Secret-when flag | Returns |
|---|---|---|---|
| `C_Spell.GetSpellCooldownDuration` | **`AllowedWhenTainted`** | **none** | `LuaDurationObject`, `MayReturnNothing` |
| `C_Spell.GetSpellChargeDuration` | **`AllowedWhenTainted`** | none | `LuaDurationObject` |
| `C_Spell.GetSpellCooldown` | `AllowedWhenTainted` | **`SecretWhenCooldownsRestricted`** | struct of numbers |
| `C_Spell.GetSpellCharges` | `AllowedWhenTainted` | **`SecretWhenCooldownsRestricted`** | struct |

The struct-returning `GetSpellCooldown` is the one that goes secret. The duration-object forms are not
flagged as returning secrets at all, because the handle is not a secret — it *holds* secrets.

> **Correction, 2026-09-21 (Phase 38 planning).** The `GetSpellCharges` row above originally read “—”
> in the secrecy column. That was wrong: `SpellDocumentation.lua:250-254` gives it
> `SecretWhenCooldownsRestricted = true`. The error was not caught during the experiments because no
> charge spell was available on the test character, so every `GetSpellCharges` probe returned nothing
> and the flag was never exercised (see T1.5). Both struct-returning forms go secret; only the
> duration-object forms do not. Phase 38 therefore pipes `currentCharges` straight into `SetText`
> without comparison or concatenation, and decides whether to show the text at all from a sticky
> `chargeCapable` cache written only when `issecretvalue(maxCharges)` is false.

### Three caveats that do apply

1. **`MayReturnNothing`.** For a spell the client has no data for, the call returns nothing. Gate on
   `C_SpellBook.IsSpellKnownOrInSpellBook(spellID)` (or `IsSpellKnown`), and call
   `C_Spell.RequestLoadSpellData(spellID)` for spells that may be uncached. A user typing an arbitrary
   spell ID into TBT's add-buff window is exactly this case.
2. **Items have no duration object.** `C_Item.GetItemCooldown(itemInfo)` returns plain numbers
   (`startTimeSeconds`, `durationSeconds`, `enableCooldownTimer`) and **there is no item equivalent of
   `GetSpellCooldownDuration` anywhere in the API**. So TBT's `trinket` and `pot` meta-trackers cannot
   reach tier 1 as items. The route is `C_Item.GetItemSpell(itemInfo)` → `spellID` →
   `GetSpellCooldownDuration`, which is plausible because TBT's providers already resolve trinkets and
   potions to spell IDs (`Providers.lua:203`, `:303`). Probe it as **T1.4**.
3. **`GetSpellCooldown` is not a fallback in restricted content** — it is precisely the call that goes
   secret. The fallback below tier 1 is TBT's existing cast mirror, not a different cooldown API.

## Implementation approaches

| | Approach | Where | Trade-off |
|---|---|---|---|
| **1a** | **New `trackType = "cooldown"` alongside the existing buff tracking.** A tracked entry stores a duration handle instead of `expiresAt`. | `BuffEngine.lua`, `Providers.lua` | Smallest change that delivers the feature. Requires the add-buff window to distinguish "track the buff" from "track the cooldown", which is the UI work already anticipated. |
| **1b** | **Event-driven handle refresh; the engine animates between.** Re-fetch and re-set the handle only on `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`, bar-appears, or fill-direction change. | `BuffEngine.lua`, `Display.lua` | Replaces per-frame work rather than adding it, and the handle tracks cooldown reduction and resets live without TBT knowing. Needs a dirty flag per timer. |
| **1c** | **Build the degradation ladder explicitly**, so every timer declares its tier. | `BuffEngine.lua` | The real architectural deliverable. TBT is tier 3 only today, which is blind to in-combat CDR and to early expiry. Larger change; makes every later feature cheaper. |
| **1d** | **Route items through their on-use spell** so trinkets and potions join the ladder. | `Providers.lua` | Depends on T1.4. If it fails, trinket/pot stay tier 3 permanently and that should be written down rather than retried each milestone. |

Ladder, for reference (tier 1 is what this test unlocks):

| Tier | Source | Properties |
|---|---|---|
| 1 | `GetSpellCooldownDuration` / `GetSpellChargeDuration` → `SetTimerDuration` / `SetCooldownFromDurationObject` | Engine animates; tracks CDR and resets live; nothing read |
| 2 | Clean API numbers, out of combat only | Exact values and pretty text |
| 3 | Cast mirror — `UNIT_SPELLCAST_SUCCEEDED` + known duration | **All TBT has today.** Blind to CDR and early expiry |
| 4 | Fail-open — shown-full bar, no text | Loses precision, never errors |

## Probes

- **T1.1 — handle acquisition.** `C_Spell.GetSpellCooldownDuration(spellID)` on a **spell the CDM does
  not track**, with a long cooldown. Does a handle come back? `d:HasSecretValues()`. Then
  `d:GetRemainingDuration()` guarded by `issecretvalue`.
- **T1.2 — engine-driven render.** `bar:SetMinMaxValues(0, 1)` then
  `bar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)`,
  and separately `cd:SetCooldownFromDurationObject(d)`. **Visual: does the bar drain and the swipe sweep
  with no Lua driving them?** This is the load-bearing test of the whole plan.
- **T1.3 — live CDR.** With the bar running, trigger a cooldown reduction or reset. Does the bar follow
  without TBT re-setting anything? If yes, tier 1 is strictly better than the cast mirror and not just
  equivalent.
- **T1.4 — items.** `C_Item.GetItemSpell(itemInfo)` → `GetSpellCooldownDuration` for a trinket and a
  potion. Also record plain `C_Item.GetItemCooldown` in all three scenarios — it carries no
  `SecretWhen...` flag, so if item cooldowns are never secret that is a simpler answer for meta-trackers.
- **T1.5 — charges.** `GetSpellCharges` and `GetSpellChargeDuration` on a charge spell. `SetValue` is a
  supported secret sink for the count; confirm the recharge timer renders.
- **T1.6 — uncached spell.** An arbitrary spell ID the player does not know. Confirm the
  `MayReturnNothing` path and that `RequestLoadSpellData` + retry recovers it.
- **T1.7 — curve pipe.** `C_CurveUtil.CreateCurve()`, `SetType(Enum.LuaCurveType.Step)`,
  `AddPoint(0, 0)`, `AddPoint(0.001, 1)`, then `d:EvaluateRemainingDuration(curve, 0)` into
  `SetAlpha`/`SetDesaturation`. Record `issecretvalue` on the result **for the record only** — the
  expectation is a secret result and a working pipe. Curves relocate the comparison into the engine;
  they are not a way to read the value.

## Findings — Test 1

### T1.1 handle acquisition

| Scenario | Client | Handle returned | `HasSecretValues()` | `GetRemainingDuration()` readable | Notes |
|---|---|---|---|---|---|
| S1 out of combat | retail | | | | |
| S1 out of combat | Forever | **yes** | `false` | **yes — 7.471** | Frost Nova (122), 25s CD. Total 25, percent 0.29884, start 230437, end 230462, modRate 1. Struct path also fully readable. |
| S2 combat, open world | retail | | | | |
| S2 combat, open world | Forever | | | | |
| S3 combat, instance | retail | | | | |
| S3 combat, instance | Forever | | | | |

### T1.2 engine-driven render (visual)

| Scenario | Client | Bar drains | Swipe sweeps | Timer text | Screenshot | Notes |
|---|---|---|---|---|---|---|
| S1 | retail | | | | | |
| S1 | Forever | | | | | |
| S2 | retail | | | | | |
| S2 | Forever | | | | | |
| S3 | retail | | | | | |
| S3 | Forever | | | | | |

### T1.3 live CDR · T1.4 items · T1.5 charges · T1.6 uncached · T1.7 curve pipe

| Probe | Scenario | Client | Result | Notes |
|---|---|---|---|---|
| T1.3 | S3 | | | |
| T1.4 | S1 | | | |
| T1.4 | S3 | | | |
| T1.5 | S3 | | | |
| T1.6 | S1 | | | |
| T1.7 | S3 | | | |

---

# Test 2 — TBT items inside Blizzard's own CDM container, with the whole container realigned

## The requirement

TBT's tracked icons and bars must appear **as if they were Blizzard's own** — added into the CDM's own
container, not into a TBT container anchored nearby. And the container's layout must be recomputed for
the new total, so items per line and positions are correct rather than TBT's items being tacked onto one
end while Blizzard's wrap at the old count.

This is the injection route. The companion document ranked it as a stretch on taint grounds; the
requirement supersedes that ranking. The taint risk is real and is tested explicitly as **T2.6** —
stated once here, not re-litigated.

## Mechanics, from Blizzard's source

Everything below is verified in `Blizzard_CooldownViewer/CooldownViewer.lua` and
`Blizzard_SharedXML/LayoutFrame.lua`.

**The viewer *is* the container.** `CooldownViewerMixin:GetItemContainerFrame()` returns `self` and is
never overridden (`CooldownViewer.lua:1632`). Injection means parenting TBT frames to
`BuffBarCooldownViewer` / `BuffIconCooldownViewer` / etc. directly.

**Layout child eligibility** (`BaseLayoutMixin:GetLayoutChildren`, `LayoutFrame.lua:37-55`). A child is
laid out when all of:

- `not region.ignoreInLayout`
- `region:IsShown()` **or** `region.includeAsLayoutChildWhenHidden`
- `region.layoutIndex` is set — required, because `GridLayoutFrameMixin:IgnoreLayoutIndex()` returns
  `false`

Children are then **sorted by `layoutIndex`**, and a **duplicate `layoutIndex` raises `GMError`**. So
TBT's indices must be coordinated with Blizzard's, not guessed.

**The wrapping problem, precisely.** For the two buff viewers:

```
BuffBarCooldownViewerMixin:GetStride(cooldownIDs)  -- "Ensure there is only ever one row/column"
    return self:GetItemCount(cooldownIDs)
BuffIconCooldownViewerMixin:GetStride(cooldownIDs) -- same
```

`stride` equals Blizzard's **own** item count. Inject without touching it and the grid wraps after
Blizzard's last item, putting TBT's items on a second row. **This is exactly the misalignment to
avoid**, and the fix is to re-set `stride` to the combined total after Blizzard sets it, then re-run
`Layout()`.

Essential and Utility differ: `CooldownViewerMixin:GetStride()` returns `self.iconLimit`, the user's
Icon Limit setting, so those grids wrap at a fixed width and added items extend into further rows
naturally. Both behaviours need their own expected outcome.

**Two traps in `GetItemCount`:**

- `minimumItemCount = 2` — the viewer always acquires at least two item frames even with one tracked
  cooldown.
- `CooldownViewerBuffBarItemTemplate` carries `includeAsLayoutChildWhenHidden = true`. **Hidden and
  empty Blizzard slots still occupy grid cells.** Any count TBT computes must be derived from
  `GetLayoutChildren()`, not from `#cooldownIDs`.

**What `RefreshLayout` does** (`CooldownViewer.lua:2021-2059`), in order: `itemFramePool:ReleaseAll()` —
which does **not** touch foreign children, so TBT's frames survive — then acquires
`GetItemCount()` frames assigning `layoutIndex = i`, sets `alwaysUpdateLayout = true`, `isHorizontal`,
`layoutFramesGoingRight`, `layoutFramesGoingUp`, `childXPadding`, `childYPadding`, `stride`, then
`RefreshData()` and `Layout()`.

**Re-assert points.** TBT's indices, stride and frame properties must be re-applied after each of:
`RefreshLayout`, `SetBarContent`, `SetBarWidthScale`, `OnAcquireItemFrame`,
`EventRegistry` `CooldownViewerSettings.OnShow` / `OnHide`, and Edit Mode enter/exit.

**Two asymmetries worth planning around:**

- **`BuffBarCooldownViewer` is the only viewer that is *not* `BottomManagedFrameTemplate`.** The other
  three are managed by UIParent's frame manager, which may fight an injected child's effect on frame
  size. **Start with `BuffBarCooldownViewer`.**
- `CooldownViewerMixin:OnLoad` does `self.Selection:SetAllPoints(self:GetItemContainerFrame())`, so the
  Edit Mode selection box will grow to include TBT's items. That is probably the desired behaviour —
  confirm rather than assume.
- All four viewers carry `roleset="cooldownViewers"`, new in 12.x with undocumented implications.

## Implementation approaches

| | Approach | How | Trade-off |
|---|---|---|---|
| **2a** | **Append after Blizzard's items, stride corrected.** TBT frames take `layoutIndex = blizzardCount + i`; after each `RefreshLayout`, set `container.stride = totalCount` (buff viewers) and call `Layout()` again. | `hooksecurefunc(viewer, "RefreshLayout")` | Simplest correct injection. Order is fixed: Blizzard's items always first. Good enough if TBT's items conceptually belong at the end. |
| **2b** | **Interleaved ordering.** Renumber *all* children — Blizzard's and TBT's — from TBT's own sort order after each `RefreshLayout`. | Same hook; rewrite `layoutIndex` on pool frames too | Gives full control over position, which matches TBT's existing per-section `layoutOrder` model. Writes to Blizzard's frames, so higher taint exposure and a `GMError` risk if numbering collides. |
| **2c** | **Frame discovery by pool hook.** `hooksecurefunc(viewer.itemFramePool, "Acquire", ...)` to know when Blizzard adds frames, plus lazily-installed per-frame hooks. | `Display.lua` / new file | Prerequisite for 2a and 2b. **Gotcha:** mixin functions are copied onto each frame at creation, so a hook on `CooldownViewerBuffBarItemMixin` never fires for frames that already existed when the hook was installed. |
| **2d** | **Reuse Blizzard's virtual item templates for TBT's frames.** `CreateFrame("Frame", nil, viewer, "CooldownViewerBuffBarItemTemplate")`. | `Display.lua:133`, `:216` | Pixel-identical by construction, and deletes TBT's reimplemented art. Risk: the template's mixin `OnLoad` expects a `cooldownID`. May need art-only use with the mixin's methods avoided. |
| **2e** | **Mirror per-item properties Blizzard applies on acquire.** `SetBarContent(viewer.barContent)` and `SetBarWidth(viewer:GetBarWidth())`. | wherever TBT frames are created | Without this TBT's bars are the right position and the wrong width. Cheap, easy to forget. |

Recommended sequence: **2c → 2a → 2e → 2d → 2b if ordering demands it.**

## Probes

- **T2.1 — bare injection.** Parent a plain frame to `BuffBarCooldownViewer`, set `layoutIndex` past
  Blizzard's count, call `Layout()`. Does it appear in the grid, in the right cell?
- **T2.2 — survival.** Change a CDM setting to force `RefreshLayout` → `ReleaseAll`. Does the injected
  frame survive, and does it keep its cell? Confirms the pool does not reclaim foreign children.
- **T2.3 — stride correction.** With injection live, set `container.stride` to the combined total and
  re-`Layout()`. **Visual: one unbroken row/column with Blizzard's and TBT's items evenly spaced, no
  second-row break at Blizzard's old count.** This is the acceptance test for the requirement.
- **T2.4 — count derivation.** Verify the total from `#container:GetLayoutChildren()`, not
  `#cooldownIDs`, and confirm hidden/empty Blizzard slots are included as the template's
  `includeAsLayoutChildWhenHidden` implies.
- **T2.5 — template reuse.** `CreateFrame` with `CooldownViewerBuffBarItemTemplate`. Does it load
  without a `cooldownID`? Which mixin methods error? Can the regions be driven as art?
- **T2.6 — taint.** With injection live: enter Edit Mode, select and move the CDM viewer, change its
  settings, exit, `/reload`. Watch for blocked-action errors and for Edit Mode refusing to save. **Go /
  no-go for the whole approach.** Run this early — a negative result saves everything after it.
- **T2.7 — combat entry and exit.** Does injection survive entering and leaving combat, and can stride
  be corrected *during* combat, or must correction be deferred to `PLAYER_REGEN_ENABLED`? Frame
  reparenting and layout in combat is the specific thing S2 and S3 exist to answer here.
- **T2.8 — the other three viewers.** Repeat T2.1 and T2.3 on `BuffIconCooldownViewer`, then
  `EssentialCooldownViewer` / `UtilityCooldownViewer` where stride is `iconLimit` rather than the item
  count. Expect the bottom-managed three to behave differently from `BuffBarCooldownViewer`.
- **T2.9 — Edit Mode selection bounds.** Confirm `Selection` grows to cover TBT's items and decide
  whether that is wanted.

## Findings — Test 2

### T2.1 injection · T2.2 survival · T2.3 stride correction

| Probe | Scenario | Client | Viewer | Result | Screenshot | Notes |
|---|---|---|---|---|---|---|
| T2.1 | S1 | retail | BuffBar | | | |
| T2.1 | S1 | Forever | BuffBar | | | |
| T2.2 | S1 | retail | BuffBar | | | |
| T2.2 | S1 | Forever | BuffBar | | | |
| T2.3 | S1 | retail | BuffBar | | | |
| T2.3 | S1 | Forever | BuffBar | | | |
| T2.1 | S2 | retail | BuffBar | | | |
| T2.3 | S2 | retail | BuffBar | | | |
| T2.1 | S2 | Forever | BuffBar | | | |
| T2.3 | S2 | Forever | BuffBar | | | |
| T2.1 | S3 | retail | BuffBar | | | |
| T2.3 | S3 | retail | BuffBar | | | |
| T2.1 | S3 | Forever | BuffBar | | | |
| T2.3 | S3 | Forever | BuffBar | | | |

### T2.6 taint — go / no-go

| Step | Client | Blocked action? | Edit Mode saved? | Notes |
|---|---|---|---|---|
| Enter Edit Mode | retail | | | |
| Select + move viewer | retail | | | |
| Change CDM settings | retail | | | |
| Exit Edit Mode | retail | | | |
| `/reload`, verify position | retail | | | |
| Same five, Forever | Forever | | | |

### T2.4 · T2.5 · T2.7 · T2.8 · T2.9

| Probe | Scenario | Client | Result | Notes |
|---|---|---|---|---|
| T2.4 | S1 | | | |
| T2.5 | S1 | | | |
| T2.7 | S2 | | | |
| T2.7 | S3 | | | |
| T2.8 BuffIcon | S1 | | | |
| T2.8 Essential | S1 | | | |
| T2.8 Utility | S1 | | | |
| T2.9 | S1 | | | |

---

---

# Findings log

## S1 — Forever, 2026-09-20 (build 1.60.1 / 69913, interface 16001)

Two runs. The first auto-picked `6603 (Attack)`, which has no cooldown, so every Test 1 number was a
legitimate zero; the harness now excludes auto-attack spells and prints an explicit INCONCLUSIVE line.
The second run, with **Frost Nova (122)** genuinely on cooldown, produced the first real data.

### Settled

**Forever has the full secret system.** `C_Secrets.HasSecretRestrictions() == true`, and the whole
predicate and table-security toolkit is present. Critically, **`secretunwrap` is absent** while
`secretwrap`, `settablesecurity`, `canaccesssecrets`, `scrubsecretvalues`, `issecrettable` and
`canaccesstable` are all present. The Blizzard-only unwrap path is closed to addons on the live client,
exactly as the documentation implied. Retail and Forever will not need separate conclusions on this.

**Tier 1 exists and behaves as designed.** `C_Spell.GetSpellCooldownDuration` returns a usable handle,
and — importantly — **it returns one even when nothing is running**, zeroed with `IsActive() == false`
and `HasExpired() == true`. There is no nil-handling branch to write. With a live cooldown every method
answered: total 25, remaining 7.471, percent 0.29884, start/end times, modRate 1.

**The step curve evaluates correctly.** `(0,0)` / `(0.001,1)` returned `1` while the cooldown was
running and `0` when it was not. The branchless conditional works on Forever.

**All nine widget sinks ACCEPTED**, including `SetTimerDuration`, `SetCooldownFromDurationObject`,
`SetAlphaFromBoolean` and `SetDesaturation`, and `GetTimerDuration()` handed a handle back.
**Caveat, and it matters:** in S1 every sample was *readable* (percent 0.29884, `IsActive` true, curve
result 1). This proves the methods exist and accept these types. It does **not** prove they accept
*secret* values. That is precisely what S2 and S3 exist to establish, and no design should lean on the
sink results until then.

**Every Test 2 structural prediction confirmed:**

- `GetItemContainerFrame() == viewer` → `true` on all four viewers. The viewer is the container.
- BuffBar: `stride 2`, `#GetLayoutChildren() 2`, **both children hidden with
  `includeAsLayoutChildWhenHidden = true`**. Both traps are real — the `minimumItemCount = 2` floor and
  hidden slots occupying grid cells. Any total must come from `GetLayoutChildren()`.
- BuffBar is vertical here (`isHorizontal = false`) while the other three are horizontal.
- Essential/Utility: `stride 12` (= `iconLimit`) with `GetItemCount()` of 2 — the asymmetry that means
  those two need separate stride handling from the buff viewers.
- **`GetAdditionalPaddingOffset()` = -2 (bars) / -4 (icons), matching TBT's `BAR_PADDING_OFFSET` and
  `ICON_PADDING_OFFSET` in `Display.lua:9-10` exactly. P2.5 passes** — the hand-derived constants are
  correct and there is no latent layout bug.
- All four item mixins plus `GridLayoutFrameMixin` present as hook targets.

## S2 — Forever, 2026-09-20 — the decisive run

**Forever restricts in plain open-world combat.** `ShouldAurasBeSecret`, `ShouldCooldownsBeSecret` and
`ShouldUnitStatsBeSecret` all returned `true` with `IsInInstance() == false`. S2 on this client is a
genuinely restricted context, which means the test bar the user watched drain in open-world combat
**was being driven by secret data**. T1.2 passes on the secret path, visually and by API.

### VERDICT: Test 1 mechanism — WORKS

Every method on the duration handle went `SECRET(...)`, `HasSecretValues()` returned `true`, and the
struct path went secret field by field. And then:

| Sink | Value fed | Result |
|---|---|---|
| `StatusBar:SetTimerDuration(dur)` | secret-bearing handle | **ACCEPTED** |
| `Cooldown:SetCooldownFromDurationObject(dur)` | secret-bearing handle | **ACCEPTED** |
| `StatusBar:SetValue` | `SECRET(number)` | **ACCEPTED** |
| `Texture:SetDesaturation` | `SECRET(number)` | **ACCEPTED** |
| `Texture:SetDesaturation` | secret curve result | **ACCEPTED** |
| `Frame:SetAlpha` | secret curve result | **ACCEPTED** |
| `Frame:SetAlphaFromBoolean` | `SECRET(boolean)` | **ACCEPTED** |
| `FontString:SetText` | `SECRET(string)` | **ACCEPTED** |
| `StatusBar:GetTimerDuration()` | — | returns the handle back |

**All nine accepted genuinely secret values.** The tier-1 render model is confirmed end to end on the
client TBT targets. This is no longer an inference.

### VERDICT: curve results are SECRET — the corrected model is right

`dur:EvaluateRemainingDuration(step)` and `EvaluateRemainingPercent(step)` both returned
`SECRET(number)` from a curve **the addon built itself**. The literal reading of
`SecretWhenCurveSecret` — that a non-secret curve yields a readable result — **is wrong**, confirmed
empirically. Curves relocate the comparison into the engine so the result can be piped to a setter.
They are not a way to read the value. Design accordingly; the caveat in the companion document stands.

### VERDICT: P2.7 — the CDM data-source route WORKS

`children with live auraDataCached: 1`. On the `BuffIconCooldownViewer` item frame:

| Field | In restricted combat |
|---|---|
| `.auraDataCached` | **`table(readable)`** — indexable by tainted code |
| `.auraDataUnit` | **`"target"`** — plain readable string |
| `.auraSpellID` / `.auraInstanceID` | `SECRET(number)` |
| `cached.applications` | `SECRET(number)` |
| `cached.duration` / `.expirationTime` | `SECRET(number)` |
| `cached.spellId` / `.name` | `SECRET(number)` / `SECRET(string)` |

**The cached table is readable and every field inside it is the pipeable kind.** Combined with the sink
results above, TBT can render real in-combat stacks, durations and names for any spell the CDM holds a
frame for — via frame fields, never via the aura API. This was the highest-value hypothesis in the plan
and it holds.

Incidental: `auraDataUnit` was `"target"`, so the CDM tracks target auras too, not only player ones.

### VERDICT: the direct aura API is CLOSED — P1.1 and P1.3 are dead

```
GetUnitAuraInstanceIDs(): Auras cannot be accessed when secret while tainted by 'TBTProbe'
GetUnitAuras():          Auras cannot be accessed when secret while tainted by 'TBTProbe'
GetAuraSlots():          Auras cannot be accessed when secret while tainted by 'TBTProbe'
```

Hard errors, not silent nils. `GetPlayerAuraBySpellID` returned nothing. The `UNIT_AURA` payload gave
`isFullUpdate = SECRET(boolean)` and `removedAuraInstanceIDs = SECRET(table)`.

**The documentation inference was wrong.** The absence of a `SecretWhenUnitAuraRestricted` flag on
`GetUnitAuraInstanceIDs` did not mean the IDs come back readable — it meant the call is refused
outright for tainted callers. P1.1 was written as Experiment 1's pivot; it is now a **documented
limitation, closed**. Do not re-attempt it in a later milestone. The CDM-frame route above is the only
way TBT gets in-combat aura data, and it works.

### Still readable in restricted combat — worth knowing

`C_Spell.IsSpellUsable`, `cooldownInfo.isEnabled`, `C_Spell.GetBaseSpell`, `C_Spell.GetOverrideSpell`,
all the `C_Secrets` predicates, and every CDM container geometry field (`stride`, paddings,
`GetItemCount`, `GetLayoutChildren`, `layoutIndex`, sizes). **Base/override spell resolution working in
combat matters for the ranked-ID problem below** — the bridge is available exactly where it is needed.

## Stacking auras — closed question, 2026-09-20

**Question:** can TBT detect mid-combat that a stacking buff was fully consumed, and end its display
early? Tested with the gnome racial **Eureka! (`1259817`)** — 3 stacks, 15s or 3 casts.

### VERDICT: NO for any buff the CDM does not track

The watch timeline is unambiguous. Sampling at 0.1s plus every `UNIT_AURA`:

```
[ 6.29] UNIT_AURA  apps=3  exp=232463  iid=229  count="3"  hasExp=true  auraDur=userdata(handle)
[ 8.59] UNIT_AURA  count=ERR  hasExp=ERR  auraDur=ERR  byIID=ERR
[27.54] tick       count=(nothing)  hasExp=(nothing)  auraDur=(nothing)  byIID=nil
```

At 6.29s, out of combat, every route worked — stacks, expiration, a duration handle, the lot. At
8.59s combat began and **all four ID-based calls hard-errored** with "Auras cannot be accessed when
secret while tainted".

**A cached instance ID does not help.** `RequiresUnitAuraAccess` (FailureMode `Error`) is a blanket
gate on the entire `C_UnitAuras` namespace for tainted callers under restriction — not a per-value
secrecy rule. Holding a valid ID from before combat changes nothing.

Complete route table for in-combat aura data:

| Route | Result |
|---|---|
| `GetUnitAuraInstanceIDs` / `GetUnitAuras` / `GetAuraSlots` | hard error |
| `GetAuraApplicationDisplayCount` / `DoesAuraHaveExpirationTime` / `GetAuraDuration` / `GetAuraDataByAuraInstanceID` with a **cached** ID | hard error |
| `GetPlayerAuraBySpellID` | returns nothing |
| `UNIT_AURA` payload | `removedAuraInstanceIDs` is a secret table; a secret cannot be compared to a cached ID |
| **CDM item frame `auraDataCached`** | **works — readable table, secret pipeable fields** |

**The CDM item frame is the only in-combat aura source that exists.** Eureka! has no CDM frame and no
`NeverSecret` exemption (`GetSpellAuraSecrecy` = 2), so there is no route at all.

### What remains possible

- **CDM-tracked buffs:** stacks are *renderable* via `auraDataCached.applications` →
  `FontString:SetText`, and presence via the frame's readable `IsActive()`. TBT never learns the value;
  it just draws the truth. Early consumption therefore shows correctly.
- **Untracked buffs:** TBT keeps doing what it does today — run the nominal duration from the cast and
  accept that early consumption is invisible. This is a **documented engine limitation, not a TBT
  shortcoming**, and should be stated that way in user-facing copy rather than treated as a bug.

Do not re-attempt this in a later milestone. Every route has been tested against the live client.

## Cast-driven stack tracking — WORKS, and it is the workaround

Prototyped 2026-09-20 after the aura routes closed. **The cast stream is not restricted even though the
aura stream is**, so a consumable-stack buff can be modelled entirely from casts.

`UNIT_SPELLCAST_SUCCEEDED` fires for the player with a non-secret `spellID` (already relied on by TBT),
and **`C_Spell.IsSpellHarmful` is `AllowedWhenTainted` with no secrecy flag at all** — so the
"damaging ability" filter works in restricted combat with no per-class spell index.

Model: the granting cast starts the buff at N stacks; each qualifying cast spends one; reaching zero
**ends it early**. That is exactly the behaviour the aura API refused to provide.

Measured on Forever with Eureka! (`1259817`, 3 stacks / 15s):

```
[ 0.00] APPLY — 3 stacks, 15s
[ 4.56] CAST 143 (Fireball)     harmful=true  helpful=false -> SPEND, predicted 2
[ 5.10] CAST 7300 (Frost Armor) harmful=false helpful=true  -> ignored, predicted 2
[ 6.59] CAST 122 (Frost Nova)   harmful=true  helpful=false -> SPEND, predicted 1
[10.18] CAST 143 (Fireball)     harmful=true  helpful=false -> SPEND, predicted 0
[     ] END (all stacks consumed)
```

The helpful spell was correctly ignored and the buff ended on the third spend rather than running the
full 15s.

### Known inaccuracy, accepted by user decision

`IsSpellHarmful` documents as *"can be cast on hostile targets"* — **targeting, not damage.** Frost Nova
is harmful by that definition but deals no damage in vanilla, so the prototype spent a stack the game
did not. Polymorph is the same class of error.

**User decision, 2026-09-20: accept the approximation and keep the `IsSpellHarmful` filter.** The
alternative — a per-spell damage index across every class and expansion — costs far more than the
occasional early drop is worth. Prefer over-consuming to under-consuming: a stack dropped early shows a
buff ending slightly sooner, while a missed decrement leaves a stale buff on screen indefinitely.

### Structural limitation, worth stating plainly

**The cast-driven model can never be self-verified in combat.** `GetPlayerAuraBySpellID` returns nothing
under restriction, so TBT cannot compare its prediction against reality in exactly the content where
the prediction matters. Consequences for design:

- The nominal duration timer must **always** run as a backstop, so a mis-modelled buff still expires.
- Any drift correction can only happen when restrictions lift.
- The harness prints `RESTRICTED (unverifiable)` rather than a bare `nil` so this is never mistaken for
  "the buff is absent".

## Test 2 injection — WORKS. T2.1, T2.2, T2.3 pass

Prototyped and measured on Forever, 2026-09-20, injecting a TBT-owned item frame into
`BuffIconCooldownViewer` (Tracked Buffs) driven by the cast-driven Eureka! tracker.

**T2.1 injection** — a frame parented to the viewer with a `layoutIndex` is laid out by
`GridLayoutFrame` exactly like a Blizzard item. Sized and scaled from a live sibling so user scale
settings are inherited for free.

**T2.2 survival** — the frame survives `RefreshLayout` and its `itemFramePool:ReleaseAll()`, confirmed
repeatedly in the event log. `ReleaseAll` only touches pool frames, as predicted from the source.

**T2.3 stride correction — numerically verified:**

```
child 1 layoutIndex=1  left=904  w=40  shown=false
child 2 layoutIndex=2  left=940  w=40  shown=false
child 3 layoutIndex=3  left=976  w=40  shown=true   <== TBT
```

Deltas of exactly **36 px** = 40 width + (−4) `GetAdditionalPaddingOffset()`. The injected item is
spaced identically to Blizzard's own, and the row re-flows for the new total rather than wrapping at
Blizzard's old count. Confirmed working live in combat with the stack tracker driving it.

### Two bugs found and fixed in the prototype

**1. Insertion index must come from the CONFIGURED set, not the visible one.**
The first build took `layoutIndex = max(live layoutIndex) + 1`. With no buffs procced the pool is
empty, so our frame took index 1 and rendered **first**. It only corrected itself in Edit Mode, where
Blizzard populates a preview of every configured buff. Fixed by deriving the count from
`C_CooldownViewer.GetCooldownViewerCategorySet(viewer.cooldownViewerCategory, allowUnlearned)` —
queried both ways and maxed — then maxed again against `viewer:GetItemCount()` (which applies the
`minimumItemCount = 2` floor) and against any live index. The configured set is stable whether or not
anything is currently active.

**2. Never re-assert from `itemFramePool.Acquire`.**
`Acquire` fires once per item from *inside* `RefreshLayout`, after `ReleaseAll()` has emptied the
container. Re-asserting there ran against a half-built container and briefly drove `stride` to **1**,
costing three layout passes per rebuild:

```
pool Acquire  → stride 2 -> 1      (container transiently empty)
pool Acquire  → stride 1 -> 2
RefreshLayout → stride 2 -> 3      (settles correct)
```

`RefreshLayout`'s own hook fires after every acquire and is the only correct re-assert point. The
`Acquire` hook is retained for logging only. **This is a general rule for the milestone, not a one-off:
pool hooks observe, layout hooks act.**

### Notes carried forward

- `viewer:GetStride()` still returns Blizzard's own value (2) while `viewer.stride` holds ours (3).
  The field is what `GridLayoutFrameMixin:Layout()` reads, so overriding the field is correct and the
  method is not worth fighting.
- Blizzard's `minimumItemCount = 2` means two empty slots occupy grid cells even with nothing tracked.
  That is pre-existing Blizzard behaviour, visible with or without injection.
- The injected frame reports `MISSING (no method …)` for `GetCooldownID` / `IsActive` / etc., which is
  correct — it is hand-built, not an instance of Blizzard's template. Anything walking the container
  must tolerate children that are not CDM items.

### FINAL VERDICT — T2.6 FAILS. Injection into the CDM container cannot ship.

Five variants were tested on Forever, 2026-09-20, each from a clean `/reload`, each exercised through
an Edit Mode cycle followed by combat. **Every one taints**, producing on every subsequent cast:

```
CooldownViewerItemData.lua:782: attempt to perform boolean test on local 'hasTotem'
(a secret boolean value, while execution tainted by 'TBTProbe')
  ← RefreshTotemData ← CheckCacheCooldownValuesFromAura ← CacheCooldownValues
  ← RefreshSpellCooldownInfo ← RefreshData ← OnSpellUpdateCooldownEvent
```

| Variant | Writes `viewer.stride` | Writes our `layoutIndex` | Calls Blizzard mixins | Result |
|---|---|---|---|---|
| `full` | yes | yes | yes | taints |
| `nostride` | no | yes | yes | taints |
| `manual` | no | no (excluded from layout) | yes | taints |
| `deferred` | yes, via `After(0)` | yes | yes | taints |
| `pure` | **no** | yes | **none at all** | **taints** |

`pure` is the decisive one: no `GetItemCount`, no `GetLayoutChildren`, no `Layout`, no `stride`,
children walked via the C-level `GetChildren()`, counts from the `C_CooldownViewer` namespace API, and
every write pushed onto a fresh execution frame with `C_Timer.After(0)`. It still taints.

**Mechanism, as far as it can be established:** our frame is a child of the viewer, so Blizzard's own
`BaseLayoutMixin:GetLayoutChildren()` iterates it and reads `layoutIndex`, `ignoreInLayout` and
`IsShown()` **off an addon-owned frame**. Reading a tainted frame inside their untainted code taints
that execution, which later reaches a secret comparison in the totem/aura cache path. If that is right,
**no variation helps — being a child at all is the problem.**

**One variable remains unisolated:** `hooksecurefunc` on `RefreshLayout` and on
`itemFramePool.Acquire`, present in all five variants. It is unlikely to be the cause — that is what
`hooksecurefunc` exists for — but it was never removed. Recorded for honesty, not as a live hope.

### Process note — four of the five arms were invalid

`full`, `nostride`, `manual` and `deferred` all called `viewer:GetItemCount()` and
`viewer:GetLayoutChildren()` through a shared `BlizzardSlotCount` helper, and all but `manual` called
`viewer:Layout()`. Those mixin calls were **already known** to taint, from the earlier `safeMode`
experiment. The bisect therefore varied `stride` and `layoutIndex` while holding the most likely cause
constant in every arm, and four user test cycles were spent on arms that could not have answered the
question. **When a taint vector is already established, remove it from every arm before bisecting
anything else.**

### DIRECTION SET BY USER, 2026-09-20 — mirror, do not join

TBT keeps its own containers, its own styling and its own Edit Mode presence, which is already proven
to work consistently. Rather than joining Blizzard's row, TBT **reads the user's CDM configuration and
renders it in TBT's containers alongside custom entries.** The CDM becomes a data source and a
settings UI; TBT owns all display.

This is supported end to end by what was measured, and none of it touches a Blizzard frame:

| Need | Source | Proven |
|---|---|---|
| Which spells the user chose to track | `C_CooldownViewer.GetCooldownViewerCategorySet(category, allowUnlearned)` | yes — namespace API, no frames |
| Spell/override/linked IDs, `hasAura`, `charges`, `isKnown`, flags, category | `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)` | yes |
| Cooldown rendering, in combat | `C_Spell.GetSpellCooldownDuration` → `SetTimerDuration` / `SetCooldownFromDurationObject` | yes — tier 1, engine-driven |
| Charges | `GetSpellCharges` / `GetSpellChargeDuration` | partially — no charge spell available on the test character |
| Stacks and early expiry for untracked buffs | cast stream + `IsSpellHarmful` | yes |
| In-combat aura state for CDM-tracked buffs | CDM item frame `auraDataCached` / `auraDataUnit`, **read as plain fields** | yes |

**Why this is strictly better than injection:** TBT gains full control of layout, ordering, styling and
grouping; CDM content and custom content sit together; and nothing writes to, parents into, or executes
Blizzard's frame code. The taint class that killed injection cannot arise.

### Two open questions this direction raises

**1. Aura mirroring depends on Blizzard's viewers still running.** Cooldown mirroring is fully
frame-free — `GetCooldownViewerCategorySet` plus `GetSpellCooldownDuration` needs no CDM frame at all.
But the *only* in-combat aura source is the CDM item frame's `auraDataCached`, and
`CooldownViewerMixin:RefreshLayout` only calls `RefreshData()` when the viewer `IsShown()`. So if the
user hides or disables the CDM to avoid seeing everything twice, **the aura data stops**.

Do not solve this by hiding or alpha-ing Blizzard's frames — that is a write to a frame we do not own,
the same class of action that produced every taint failure above. Options to evaluate, in order of
safety: leave the CDM visible and let the user decide; mirror cooldowns only when the CDM is hidden and
degrade auras to the cast mirror; or investigate whether a CDM viewer positioned by the *user* off-screen
in Edit Mode keeps refreshing.

**2. Duplication is a product question, not a technical one.** If TBT renders the user's CDM selections
and the CDM also renders them, everything appears twice by default. That is a UX decision for the
milestone: opt-in mirroring, a "hide originals" instruction, or mirroring only what the user explicitly
adds to TBT.

### Consequence: fall back to Option B

TBT keeps its own container and never becomes part of Blizzard's. Make TBT's container a real
`GridLayoutFrame`, copy `stride` / `childXPadding` / `childYPadding` / `isHorizontal` / `iconScale`
from the CDM viewer by **reading plain fields only**, and anchor it to the viewer. Zero writes, zero
children inside their frame, zero Blizzard Lua executed.

What this delivers: visual parity, correct scale and padding, automatic follow on Edit Mode changes,
and deletion of the hand-derived layout arithmetic in `Display.lua` (419–452, 590–678).

**What it does not deliver, and the user should decide with this in mind:** TBT's items cannot sit
*inside* Blizzard's row. They will form an adjacent row or column that tracks the CDM's geometry. The
explicit requirement — "as if they were Blizzard's own … update the whole container so items per line
are not offset" — **is not achievable.** The CDM is closed to addon participation at the frame level.

### Earlier partial result, now superseded

Tested deliberately 2026-09-20. Entering Edit Mode, moving the viewer, changing its settings, saving
and exiting produced **no Lua errors and no blocked actions**, and the injected frame followed padding,
visibility and position changes correctly. **Injection is viable to ship.**

### The taint source was the probe, not the injection

An earlier Edit Mode run threw
`CooldownViewer.lua:939 "attempted to index a table that cannot be accessed while tainted"` with
`dataCache = <forbidden table>`. The decisive clue was in the locals: `viewerFrame =
EssentialCooldownViewer` — **a viewer never injected into**.

The cause was the harness's own diagnostics calling CDM mixin methods (`IsActive`, `ShouldBeShown`,
`IsExpired`, `GetCooldownID`, `GetStride`, `GetItemCount`) across all four viewers. Those run Blizzard
code on a tainted stack and write tainted values into the frames' cooldown caches, leaving the frames
permanently tainted. Gating them behind a `safeMode` flag (default on) removed the error entirely.

**This upgrades the earlier "mixin methods can throw" rule: they do not merely fail, they leave the
frame tainted afterwards.** Everything TBT needs is available as a plain field, so the rule costs
nothing.

### Combat + Edit Mode — a real taint window, and the guard for it

With Edit Mode open and combat entered, every cast threw:

```
CooldownViewerItemData.lua:782: attempt to perform boolean test on local 'hasTotem'
(a secret boolean value, while execution tainted by 'TBTProbe')
  ← RefreshTotemData ← CheckCacheCooldownValuesFromAura ← CacheCooldownValues
  ← RefreshSpellCooldownInfo ← RefreshData ← OnSpellUpdateCooldownEvent
```

Mechanism: writing `viewer.stride` / `layoutIndex` taints the viewer. That is **harmless until
Blizzard's own code boolean-tests or compares a SECRET**, which only happens in combat. Untainted
Blizzard code handles secrets fine; tainted execution of the same code does not. Edit Mode's
`isEditing` path reaches `RefreshTotemData`, which is where it surfaced.

**Guard implemented: never write to a Blizzard frame while `InCombatLockdown()`.** Re-asserts are
deferred and flushed on `PLAYER_REGEN_ENABLED`. Costs nothing — the layout cannot meaningfully change
mid-combat anyway — and matches the convention `EditModeFrames.lua` already follows.

**The guard is preventive, not curative — taint is sticky.** Once a frame is tainted it stays tainted
until `/reload`; user-observed 2026-09-20, errors continued into the following combat. So the guard can
only be evaluated from a clean session, and any test of it MUST start with `/reload`.

**Open question this leaves.** It is not yet established whether writing `viewer.stride` taints the
viewer *permanently and consequentially*, or whether the errors were confined to the Edit-Mode
`isEditing` code path that reaches `RefreshTotemData`. Evidence so far points to the latter: an earlier
combat test with injection active and Edit Mode never opened produced no errors at all. The decisive
test is a clean reload, then combat without Edit Mode, then Edit Mode out of combat, then combat again.

**Fallback if writing stride turns out to be fatal:** mark the injected frame `ignoreInLayout = true`
and position it manually against the last Blizzard child, writing nothing to the viewer. That keeps our
frame untainted but gives up the whole-row re-flow the user asked for, since Blizzard's grid would no
longer account for the extra item. Only adopt it if the clean-session test fails.

**Generalised rule for the milestone:** an addon may taint a Blizzard frame without consequence right
up until that frame's own code touches a secret. Combat is when that happens. So all writes to CDM
frames are out-of-combat-only, full stop — not merely "usually".

### Icon scale must be re-applied by hand

`itemFrame:SetScale(self.iconScale)` happens in `CooldownViewerMixin:OnAcquireItemFrame`
(`CooldownViewer.lua:1996`), which only ever runs for **pool** frames. An injected frame never receives
it and ignores the user's Icon Size slider. Fixed by reading `viewer.iconScale` (plain field, no method
call) and re-syncing size from a live sibling on every re-assert.

### Still to run
- **T2.5 — Blizzard's virtual item template** via `/tbtp inject template`, which would replace the
  reimplemented art in `Display.lua`.
- **T2.8** — the same on `BuffBarCooldownViewer` and the two bottom-managed viewers.

## Calling Blizzard's CDM mixin methods from addon code is UNSAFE

Found incidentally in the same run, and it is a **hard constraint on the whole of Test 2**:

```
c:IsExpired()  ERROR: Blizzard_CooldownViewer/CooldownViewer.lua:1130: attempt to compare field
               'cooldownStartTime' (a secret number value, while execution tainted by 'TBTProbe')
```

Blizzard's own mixin code compares secrets freely, which is legal *for them*. The moment that code
runs on a call stack tainted by an addon, the same comparison throws. `IsActive()` and
`ShouldBeShown()` happened to be safe; `IsExpired()` was not, and which is which is not documented.

**Rules this imposes on the injection work:**

1. Read **plain fields** off CDM item frames (`auraDataCached`, `layoutIndex`, `stride`, sizes). Never
   assume a mixin *method* is callable.
2. Any Blizzard method call that is genuinely needed must be `pcall`-wrapped with a fallback, and must
   be treated as able to fail at any patch.
3. Prefer `hooksecurefunc` — it runs *after* Blizzard's own untainted call, so the comparison happens
   on a clean stack.

This also retro-justifies `CDMTab.lua:4`'s existing warning about touching CDM internals.

## Retail probing SKIPPED — user decision, 2026-09-20

Forever and retail run the same 12.1 engine and every mechanism tested behaved exactly as the generated
API documentation predicted, including all four negative results. On that basis the user chose **not**
to spend further cycles probing retail M+ or raid bosses, and instead to make **retail validation the
final phase of the milestone** — testing and fixing against M+ and raids once the features exist.

What this defers rather than answers, to be verified in that final phase:

- **T1.4 trinkets / potions** — `C_Item.GetItemSpell` → `GetSpellCooldownDuration`. Untestable on
  Forever: both trinket slots were empty. If it fails, `trinket`/`pot` stay on the cast mirror.
- **T1.5 charges** — `GetSpellCharges` / `GetSpellChargeDuration` returned nothing for every probe
  spell because the vanilla character had no charge ability.
- **A populated CDM** — Forever offered only 8 tracked spells and frequently zero live
  `auraDataCached`. Retail exercises the mirroring layer far harder.
- **Stricter predicates** — M+ stacks encounter, challenge-mode and restricted-map restrictions on top
  of combat. Forever's open-world combat already set all three `C_Secrets` predicates true, so the
  expectation is no change, but it is an expectation rather than a measurement.
- **Ranked spell IDs** are a Forever/vanilla artefact and should simply be absent on retail.

**Risk accepted knowingly:** if a retail-only difference exists, it surfaces late, during the
validation phase, rather than during design. Given five consecutive confirmations of the documented
behaviour that is a reasonable trade.

### Still open after S2

- **S3 on Forever** (dungeon) — S2 already has full restrictions here, so S3 mainly adds the
  restricted-map predicates. One run, low expected delta.
- **Retail M+** — the governing S3, plus trinkets (T1.4), charges (T1.5) and a populated CDM.
- **The injection probes (T2.1, T2.2, T2.3, T2.6) are not covered by this harness at all.** They need
  real frame-injection code, which is the prototype step.

### Client asymmetry — the two S3s are not equivalent

Forever is vanilla: its instances are ordinary dungeons, and challenge mode / Mythic+ does not exist
there. Retail M+ stacks encounter, challenge-mode and restricted-map predicates on top of combat and is
therefore the strictest environment TBT will ever run in.

**Retail M+ is the governing S3.** A technique that passes Forever's S3 but fails retail M+ has not
passed. Plan (user, 2026-09-20): finish the Forever passes, then run retail inside an M+ instance —
which also covers `T1.4` (trinkets) and `T1.5` (charges), both untestable on the current Forever
character, and gives `P2.7` a populated CDM to read from.

### New finding not in the plan — ranked spell IDs on Forever

Forever is vanilla, so the spellbook carries **rank variants with distinct spell IDs**, and the CDM
tracks only one of them:

| Spellbook | CDM |
|---|---|
| `116` Frostbolt | `205` Frostbolt |
| `133`, `143` Fireball | `145` Fireball |
| `168` Frost Armor | `7300` Frost Armor |

TBT keys everything by spellID. If a user adds the rank they cast and the CDM holds a different ID,
the two systems silently disagree — and every CDM-frame-derived route in Test 2 depends on matching
them. `C_Spell.GetBaseSpell` / `GetOverrideSpell` are the likely bridge and TBT already calls both in
`Core.lua`. Probes added to the harness to confirm. **This affects the add-buff window design
regardless of which test wins**, so it belongs in the milestone scope.

### Still inconclusive

- **Test 1 on a genuinely non-CDM spell.** Frost Nova is CDM-tracked; the harness flagged the premise
  violation. `20589 (Escape Artist)` is the clean pick from the candidate list.
- **P2.7, the data-source probe.** Every CDM child had `auraDataCached = nil` and all tracked-buff
  children were hidden — the CDM has no tracked buff configured that the character currently has. The
  harness now counts cache hits and says so explicitly.
- **T1.4 items.** Both trinket slots empty.
- **Charges.** `GetSpellCharges` returned nothing for every probe spell; no charge spell available.
- **`cooldownInfo.isOnGCD`** read `false` on a live cooldown but `nil` on an idle one — field presence
  is conditional, so never assume it exists.

### Harness bugs found and fixed

1. `%.4g` number formatting destroyed IDs (`199344` printed as `1.993e+05`).
2. Auto-pick chose auto-attack; now excludes `IsAutoAttackSpell` / `IsAutoRepeatSpell`, added
   `/tbtp list`, and prints INCONCLUSIVE when a handle comes back zeroed.

---

## Definition of done

This plan is complete when, for **both** tests:

1. All three scenarios are recorded, on both clients, with the `C_Secrets` context captured per run.
2. Every visual outcome has a screenshot.
3. Each test has a written verdict: **works / works with constraints / not possible**, with the
   constraint or the blocking reason named.
4. Anything that came back "not possible" is written up as a documented limitation, not left open to be
   re-attempted next milestone.
5. The approach tables above have a chosen approach marked, with the reason.

## Out of scope for this plan

- No `C_CooldownViewer.SetLayoutData` call — it would overwrite the user's live CDM configuration.
- No deploy to `_beta_` or `_ptr_`.
- No probe file committed to either TOC's load list; `check-toc.ps1` requires the two TOCs to differ
  only on `## Interface:` and `## Notes:`.
- No change to `CHANGELOG.md`.
- Aura-side probes (`GetUnitAuraInstanceIDs`, the `UNIT_AURA` payload IDs) stay in the companion
  document. They rest on documentation inference rather than a working precedent and are deprioritised
  accordingly.
