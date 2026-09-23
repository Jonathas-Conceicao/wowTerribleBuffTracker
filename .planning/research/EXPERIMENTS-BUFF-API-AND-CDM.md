# Experiment Plan — Richer Buff Data, CDM Integration, Cooldown Tracking

**Written:** 2026-09-20
**Branch:** `dev` (experimentation only — nothing here is committed addon behaviour)
**Status:** research complete, no code written, no deploy performed

**Ground truth used:**
- `C:\Users\jonat\Repositories\wow-ui-source` @ `eb941aad0` — 12.1.0 build 69273, branch `live`
- `Blizzard_APIDocumentationGenerated/*` — the client's own machine-generated API contract. This is the
  authoritative statement of which calls may touch secret values and under what taint conditions.
- `Blizzard_CooldownViewer/*` — Blizzard's own reference implementation of "render an aura I am not
  allowed to read".
- **Not yet consulted:** `BigWigsMods/WoWUI` branch `forever-beta`. Every finding below is retail
  12.1.0. Forever may differ and each probe must be run on both clients.

**Correction log:** an earlier revision of this document concluded that
`Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration` were closed to addons, and
that no fire-and-forget render path existed. That was wrong — it read `SecretArguments` as governing
the call rather than governing *secret arguments*, and a duration object is not a secret value. Fixed
throughout; see "Duration objects and curves".

A second revision corrected the curve claim in the other direction: curve evaluation results must be
treated as **secret**, not readable. Curves move the comparison into the engine; they do not extract
data. See "Duration objects and curves".

**Client scope (user decision, 2026-09-20):** `_classic_beta_` (Forever) is the primary target;
`_retail_` must show no regression. `_beta_` and `_ptr_` are out of scope and are not to be deployed to.

---

## 0. The mechanism that governs all three experiments

Everything below turns on one thing. Every documented API carries a `SecretArguments` tier, and there
are exactly three values across the whole generated documentation:

| Tier | Count | Reading |
|---|---|---|
| `NotAllowed` | 92 | A secret must never be passed. |
| `AllowedWhenUntainted` | 3565 | The overwhelming default. |
| `AllowedWhenTainted` | 123 | Explicitly opened to tainted callers — i.e. to addons. |

The 123-entry `AllowedWhenTainted` set is not a random spread. It is, almost entirely, **the display
setters plus the string/colour formatting helpers**, and it conspicuously *excludes* every
time-animating API. That shape is the finding:

**Open to addons (may be handed a secret):**

- `FontString:SetText` / `SetFormattedText` / `SetTextColor` / `SetTextToFit`
- `StatusBar:SetValue` / `SetMinMaxValues` / `SetStatusBarColor` / `SetStatusBarDesaturated` / `SetStatusBarDesaturation`
- `Texture:SetTexture` / `SetAtlas` / `SetDesaturated` / `SetVertexColor` / `SetTexCoord` / `SetRotation` / `SetRadialProgressBarPercent` / `SetSpriteSheetCell`
- `Frame/Region:SetAlpha` and **`SetAlphaFromBoolean`**
- `Cooldown:SetDrawSwipe` / `SetDrawEdge` / `SetDrawBling` / `SetEdgeColor` / `SetSwipeColor` (style only)
- `GameTooltip:SetText`
- `CurveUtil.EvaluateColorFromBoolean`, `ColorUtil.WrapTextInColor`, `StringUtil.TruncateWhenZero`,
  `Localization.AbbreviateNumbers`
- `C_Spell.GetSpellCooldown`, `GetSpellCooldownDuration`, `GetSpellChargeDuration`, `GetSpellCharges`,
  `GetSpellCastCount`, `GetSpellMaxCumulativeAuraApplications`, `GetSpellInfo`, `IsSpellUsable`
- `C_UnitAuras.GetPlayerAuraBySpellID`, `GetUnitAuraBySpellID`, `GetAuraBaseDuration`,
  `GetRefreshExtendedDuration`, `GetCooldownAuraBySpellID`, `AuraIsBigDefensive`, `AuraIsPrivate`

**Closed to addons (`AllowedWhenUntainted`, Blizzard code only):**

- `Cooldown:SetCooldown`, `SetCooldownDuration`, `SetCooldownFromExpirationTime`, `SetCooldownUNIX` —
  these take **secret scalars** and are marked `SecretArgumentsAddAspect = { Cooldown }`, so a secret
  cannot be pushed through them from addon code.
- `C_UnitAuras.GetAuraDuration`, `GetAuraApplicationDisplayCount`, `DoesAuraHaveExpirationTime` —
  the *arguments* are closed, i.e. a secret `auraInstanceID` may not be passed. See Experiment 1.
- `secretunwrap`, `settablesecurity`

**Not in this list, despite carrying `AllowedWhenUntainted`:** `Cooldown:SetCooldownFromDurationObject`
and `StatusBar:SetTimerDuration`. See below — their argument is a duration *object*, not a secret, so
the tier never applies. This corrects an earlier reading of these two as closed.

Read together: **Blizzard opened per-frame visual state to addons and closed the setters that take a
secret scalar.** The `...FromBoolean` variants, `TruncateWhenZero` and the pre-formatted-string getters
exist precisely because a tainted caller cannot write `if x > 0 then`. They are a branchless rendering
toolkit.

But the per-frame push is the *fallback*, not the only path — see the next section.

### Duration objects and curves — the actual sanctioned mechanism

A `LuaDurationObject` is a **userdata handle, not a secret value.** It may hold secrets internally, and
it says so via `HasSecretValues()` (marked `ReturnsNeverSecret`), but the handle itself is an ordinary
value. That single fact changes the design, because `SecretArguments` only governs *secret* arguments:

- `Cooldown:SetCooldownFromDurationObject(duration)` takes a `LuaDurationObject` and — unlike
  `SetCooldown`, `SetCooldownDuration`, `SetCooldownFromExpirationTime` and `SetCooldownUNIX` — carries
  **no `SecretArgumentsAddAspect`**. Nothing secret is being passed.
- `StatusBar:SetTimerDuration(duration, interpolation, direction)` has the same shape, and
  `StatusBar:GetTimerDuration()` returns one back.

So the engine animates a swipe or drains a bar **from real, unreadable data, with no per-frame work and
no reads at all.** Duration objects are the laundering vehicle: obtain one from an
`AllowedWhenTainted` getter, hand it to a widget, and the widget renders the truth. That is the
fire-and-forget path, and it is why `C_Spell.GetSpellCooldownDuration` being `AllowedWhenTainted`
matters so much (Experiment 3).

**Curves are the second half.** `C_CurveUtil.CreateCurve()` returns a `LuaCurveObject` with
`SetType(Enum.LuaCurveType.Step | Linear | Cosine | Cubic)` and `AddPoint(x, y)`;
`C_CurveUtil.CreateColorCurve()` is the colour equivalent, with `Evaluate` / `EvaluateUnpacked`.
`LuaDurationObject` then exposes `EvaluateRemainingDuration(curve, modifier)`,
`EvaluateRemainingPercent`, `EvaluateElapsedDuration`, `EvaluateElapsedPercent`,
`EvaluateTotalDuration` — each flagged **`SecretWhenCurveSecret = true`**.

A `Step` curve with points `(0, 0)` and `(0.001, 1)` is `remaining > 0 ? 1 : 0` **computed inside the
engine** — the comparison TBT is not allowed to write, made for us. More points give more buckets:
GCD-length thresholds, pandemic windows, colour ramps via `CreateColorCurve`.

**What curves do NOT do: they do not hand back readable data.** `SecretWhenCurveSecret` reads as though
a self-built curve yields a readable result, and an earlier revision of this document said so. **Treat
that as wrong.** The correct model, and the one to design against:

> A curve **relocates the comparison into the engine** so the *result* can be piped into an
> `AllowedWhenTainted` setter. The result must be assumed secret and never compared, concatenated or
> stored as a decision. You stop needing to read the value; you do not get to read it.

That is still the single most useful technique available, because it replaces every `if remaining > x`
with a curve plus a setter. But a design that assumes a readable number here would be built on sand.
Two consequences worth keeping:

1. Every curve result goes straight into `SetDesaturation`, `SetAlpha`, `SetSwipeColor`,
   `SetVertexColor`, `SetValue` or `SetText` on the same line it was produced. Never into a variable
   that something later branches on.
2. Inputs to the curve's *construction* can themselves be secret and must be guarded. Haste is the
   worked example: `UnitSpellHaste("player")` is secret in instanced combat, so a GCD-length curve
   built from it needs `issecretvalue` first with a fallback to the unhasted 1.5s — which errs toward
   suppressing a tail slightly early on hasted players rather than erroring.

### Honest uncertainty

The generated docs state the tiers but not their runtime semantics, and one data point cuts against the
literal reading: `issecretvalue` is marked `AllowedWhenUntainted`, yet TBT calls it on secrets from
tainted code in shipped builds and it works. So `AllowedWhenUntainted` is probably the emitted default
rather than a hard gate, and the real behaviour on a violation (error vs. silent no-op vs. secret
return) is unknown per-call.

**This is exactly why we probe rather than design.** The doc gives a strong hypothesis; only the live
client settles it. Every probe below records three things per call: did it throw, did it return a
secret, did the frame visibly change.

---

## Experiment 1 — Can we get richer buff data in combat?

### Where TBT stands

`BuffEngine.lua` derives everything from `UNIT_SPELLCAST_SUCCEEDED` plus a hardcoded duration, and uses
aura reads only for **presence** (`ns:ReadPlayerAura` -> `GetPlayerAuraBySpellID`), gated behind
`C_Secrets.ShouldSpellAuraBeSecret`. In a restricted context `ScanActiveTimersForCancellation` is
switched off entirely (`BuffEngine.lua:388`). So today: no real duration, no stacks, no early-expiry
detection, in exactly the content where it matters.

### What exists that we are not using

| API | Gives | Tier | Secret in combat? |
|---|---|---|---|
| `GetAuraApplicationDisplayCount(unit, id, min, max)` | **pre-formatted stack string** — the `>1` test is done for you | untainted-only | yes (string) |
| `DoesAuraHaveExpirationTime(unit, id)` | bool | untainted-only | yes |
| `GetAuraDuration(unit, id)` | **LuaDurationObject** | untainted-only | object; contents may be secret |
| `GetAuraBaseDuration(unit, id, spellID)` | number | **tainted OK** | yes |
| `GetRefreshExtendedDuration(unit, id, spellID)` | pandemic-predicted new duration | **tainted OK** | yes |
| `GetUnitAuraInstanceIDs(unit, filter, ...)` | table of instance IDs | untainted-only args | **unflagged — unknown** |
| `GetUnitAuras(unit, filter, ...)` | table of AuraData | untainted-only args | `ConditionalSecretContents` |

`LuaDurationObject` is the interesting type. It exposes `HasSecretValues()` marked
`ReturnsNeverSecret = true` — a **readable** predicate telling you whether the object is carrying
secrets — plus `GetRemainingPercent`, `FormatRemainingDuration`, `HasExpired`, `IsActive`. That is the
shape of a legitimate pass-through. Given a duration object, TBT has three options in descending order
of preference: hand it straight to `StatusBar:SetTimerDuration` or
`Cooldown:SetCooldownFromDurationObject` and let the engine animate it; evaluate it through a
self-built curve for a readable threshold (P1.7); or, failing both, pipe `GetRemainingPercent()` into
`StatusBar:SetValue` and `FormatRemainingDuration()` into `FontString:SetText` per frame — both
`AllowedWhenTainted`. The blocker below is getting the object at all, not using it.

### The blocker, stated precisely

**Every richer aura API is keyed by `auraInstanceID`, and in a restricted context that ID is itself a
secret.** Blizzard's own code proves the difficulty: `CooldownViewerSecure.lua` exists solely to use
instance IDs as table keys, and it needs `secretunwrap` plus `settablesecurity` to do it —

> "Aura instance IDs are secret, but cooldown viewer needs to use them as map keys. Store entries
> through a proxy that unwraps keys before touching the secured backing table [...] If this goes wrong,
> expect a few thousand errors in the SetScript calls around UpdateOnUpdateScript."

Both of those functions are closed to addons. And `CooldownViewerItemData.lua:348` compares
`self.auraInstanceID ~= auraInstanceID` directly — legal for untainted code, an error for us.

So Experiment 1 reduces to a single question:

> **Can addon code obtain a *readable* `auraInstanceID` for a tracked spell while aura restrictions
> are active?**

If yes, most of the table above opens up. If no, the ceiling is `GetAuraBaseDuration` /
`GetRefreshExtendedDuration` — which accept secret IDs from tainted callers but need an ID we cannot
hold.

### Probes

Run each in three states: open world out of combat, open world in combat, and inside a dungeon
(`ShouldAurasBeSecret() == true`). Log `issecretvalue`, `type`, and a `pcall`'d read for every value.

- **P1.1 — the pivot.** `C_UnitAuras.GetUnitAuraInstanceIDs("player", "HELPFUL")`. Is the returned
  table readable (`canaccesstable`)? Are the entries readable numbers (`issecretvalue` each)? This one
  call decides the experiment. It carries no `SecretWhenUnitAuraRestricted` and no
  `ConditionalSecretContents` flag, which is why it is worth asking.
- **P1.2** — same for `C_UnitAuras.GetAuraSlots("player", "HELPFUL")` (identical flag profile) and
  `C_UnitAuras.GetUnitAuras`, which *is* flagged `ConditionalSecretContents` and should therefore fail
  where P1.1 succeeds. P1.2 is the control: if both behave identically, the flags carry no runtime
  meaning and the whole doc-driven model is wrong.
- **P1.3 — payload IDs.** In `OnUnitAura`, inspect `updateInfo.updatedAuraInstanceIDs` and
  `removedAuraInstanceIDs` (both `table`/`number`). If `removedAuraInstanceIDs` is readable, TBT gets
  **in-combat expiry detection** even with no duration — the single most valuable outcome short of
  full durations, and it directly replaces the disabled cancellation scan.
- **P1.4 — pass-through, with a readable ID.** If P1.1 or P1.3 yields a usable ID: call
  `GetAuraDuration`, then `HasSecretValues()`, then push `GetRemainingPercent()` into a throwaway
  `StatusBar:SetValue` and `FormatRemainingDuration()` into a `FontString:SetText`. **Success is
  visual, not logged** — the point is whether the bar moves, since we will never be able to read back
  what we set.
- **P1.5 — pass-through, without one.** Independent of the ID question: does
  `GetAuraApplicationDisplayCount` work at all for a tainted caller, and does its secret string survive
  `SetText`? Stacks-without-durations is a shippable feature on its own.
- **P1.7 — the curve pipe.** Build `C_CurveUtil.CreateCurve()`, `SetType(Enum.LuaCurveType.Step)`,
  `AddPoint(0, 0)`, `AddPoint(0.001, 1)`. Evaluate against a secret duration via
  `EvaluateRemainingDuration(curve, 0)`, run `issecretvalue` on the result **for the record**, and
  regardless of the answer pipe it into `SetDesaturation` / `SetAlpha` and confirm the visual flips at
  expiry. The expectation is a secret result and a working pipe; the `issecretvalue` line exists to
  settle the documentation question, not to gate the design. Use a spell cooldown as the duration
  source so this does not depend on P1.1.
- **P1.6 — the branchless toolkit.** Confirm `SetAlphaFromBoolean` accepts a secret boolean and
  `StringUtil.TruncateWhenZero` accepts a secret number. These are the substitutes for the `if`
  statements TBT cannot write, and their absence would cap any design at "show it or don't".

### Decision tree

| P1.1/P1.3 outcome | What TBT can build |
|---|---|
| Readable IDs | Real durations, real stacks, real expiry. Largest feature in the addon's history. |
| Removed-IDs readable only | In-combat expiry detection; re-enable cancellation in restricted content. Still no durations. |
| Nothing readable | Ceiling is P1.5 (stack display) and a documented "this is not possible" note. Close the question instead of re-litigating it each milestone. |

---

## The finding that merges Experiments 1 and 2

Everything in Experiment 1 is blocked on obtaining an `auraInstanceID`. There is a way around it that
does not involve the aura API at all, and it is verifiable in Blizzard's own source.

**`CooldownViewerItemDataMixin` caches aura data as plain fields on each CDM item frame**
(`CooldownViewerItemData.lua:714-736`):

```
self.auraDataCached   -- an AuraData table, refreshed by RefreshAuraInstance
self.auraDataUnit     -- "player" or "target", whichever the aura was found on
self.auraInstanceID    -- set by SetAuraInstanceInfo
self.auraSpellID
```

with public getters `GetAuraDataCached()`, `GetAuraDataUnit()`, `GetAuraSpellInstanceID()`, plus
`cooldownInfo.linkedSpellID` recording **which member of a linked spell family is currently active** —
something an addon cannot compute for itself.

Reading a field off a frame is not a guarded API call. So for any spell the CDM already has an item
frame for, TBT can obtain aura state it could never obtain directly. The fields' *values* are secret in
restricted content, but they are the pipeable kind: `auraDataCached.applications` is a plain number on
live and a secret one under the 12.1 restriction, and **both go straight into `StatusBar:SetValue` and
`FontString:SetText`**.

This reframes the whole plan. TBT already *requires* the CDM (CLAUDE.md: "Requires Blizzard's Cooldown
Manager (CDM) — no standalone fallback"), so treating the CDM as the **data** source rather than only
the visual reference is consistent with what TBT already is, not a new dependency.

**The boundary, stated honestly:** this only covers spells the CDM has an item frame for. TBT's
user-added arbitrary spells and its `trinket`/`pot`/`lust` meta-trackers have no CDM frame and get
nothing from this. So it is not a replacement for the cast-mirror engine — it is a higher tier above it
(see the ladder below). Whether TBT should nudge users toward CDM-tracked spells to get the better tier
is a product question, not a technical one.

Two matching cautions:

- `C_UnitAuras.GetAuraDataByAuraInstanceID(unit, iid)` **hard-errors on restricted units** — it is not
  a silent nil. Any use needs both a `pcall` *and* an `issecretvalue(iid)` guard before the call, and
  it is only a fallback for an unpopulated cache. Prefer `auraDataCached`.
- Frame fields are private implementation, not API. They can be renamed in any patch. Anything built on
  them needs a presence check per field and a clean fallback to the tier below, never an assumption.

### The degradation ladder

The right architecture is a strict preference order where each tier loses precision and none errors.
Written out, because TBT currently only implements tier 3:

| Tier | Source | Properties |
|---|---|---|
| 1 | Engine duration handle — `GetSpellCooldownDuration` / `GetSpellChargeDuration` fed to `SetTimerDuration` / `SetCooldownFromDurationObject` | Engine animates the drain and **tracks CDR and resets live**. Secret-proof by construction. Timer text from the handle's remaining, secret in combat, accepted by `SetFormattedText`. |
| 2 | Clean API numbers, out of combat only | Exact values, pretty text, keeps a cast mirror synced. |
| 3 | Cast mirror — `UNIT_SPELLCAST_SUCCEEDED` + known duration | Local dead reckoning. **Blind to in-combat CDR and to early expiry.** This is all TBT has today. |
| 4 | Fail-open — shown-full bar, no text | Secrecy costs precision, never correctness. |

Tier 1 is the prize and it is reachable today for cooldowns (Experiment 3). Tier 1 for *auras* needs a
duration object TBT cannot obtain, which is why the CDM-frame route above matters: it supplies aura
state without one.

### Side note for backlog Phase 999.3 (single TOC)

Not part of these experiments, but it settles an open question cheaply and was visible in passing: a
**single TOC with a multi-value `## Interface:` line** covering both retail and Forever is a working
configuration in the wild, and runtime flavour detection needs no TOC split at all —
`select(4, GetBuildInfo())` returns the interface number, with Forever in the `16000-19999` range,
retail at `12xxxx` and Classic Era at `115xx`. The ranges never overlap. That does not by itself
resolve the locked two-flavour-zip decision, but it removes "we need two TOCs to know which client we
are on" as an argument.

---

## Experiment 2 — Integrating with the CDM properly

### What TBT does today

`Display.lua` **hand-reimplements** `CooldownViewerBuffBarItemTemplate` and
`CooldownViewerBuffIconItemTemplate` in Lua (lines 133 and 216), anchors its own containers to
`BuffBarCooldownViewer` / `BuffIconCooldownViewer` (347-348), and **re-derives GridLayoutFrame's
arithmetic by hand** (419-452, 590-678, with `BAR_PADDING_OFFSET` / `ICON_PADDING_OFFSET` fudge
constants). Settings are snapshotted from CDM. It looks right, and it has to be re-verified pixel by
pixel every time Blizzard touches the CDM.

### What the CDM actually offers

- Four global frames, all `parent="UIParent"`: `EssentialCooldownViewer`, `UtilityCooldownViewer`,
  `BuffIconCooldownViewer`, `BuffBarCooldownViewer`. Each inherits
  `EditModeCooldownViewerSystemTemplate, GridLayoutFrame` with `mixin="CooldownViewerMixin"` and
  `roleset="cooldownViewers"`.
- `CooldownViewerMixin:RefreshLayout()` calls `itemFramePool:ReleaseAll()`, acquires exactly
  `GetItemCount(cooldownIDs)` frames assigning `layoutIndex = i`, sets `stride`, `childXPadding`,
  `childYPadding`, `isHorizontal`, `layoutFramesGoingRight/Up` on the item container, then
  `:Layout()`. **`ReleaseAll` only touches pool frames** — a foreign child with a `layoutIndex` would
  survive it and be laid out by `GridLayoutFrame`.
- `CooldownViewerBuffBarItemTemplate` and `...BuffIconItemTemplate` are **virtual templates** — an addon
  can `CreateFrame(..., "CooldownViewerBuffBarItemTemplate")` and get Blizzard's exact art:
  `UI-HUD-CoolDownManager-Mask`, `-IconOverlay`, `-Bar`, `-Bar-BG`, `-Bar-Pip`, the `Applications`
  font string, `DebuffBorder`.
- `C_CooldownViewer.GetLayoutData()` / `SetLayoutData(data)` expose the **entire CDM layout as a
  string** (serialiser: `CooldownViewerSettingsDataStoreSerialization.lua`, 487 lines).

### Three options

**A — Inject TBT frames into Blizzard's item container.** Add children to
`BuffBarCooldownViewer:GetItemContainerFrame()` with `layoutIndex` past Blizzard's count; let
`GridLayoutFrame:Layout()` position them. *Upside:* one layout engine, drift impossible, TBT bars sit
inside the CDM's own Edit Mode selection bounds. *Risks:* `stride` is recomputed from Blizzard's item
count on every `RefreshLayout`, so wrapping is wrong the moment TBT's count matters; parenting tainted
frames into an `EditModeCooldownViewerSystemTemplate` is the most taint-sensitive thing in this
project, and `roleset="cooldownViewers"` is new in 12.x with unknown restrictions. CDMTab.lua:4 already
carries a hard warning about touching CDM internals, earned the hard way.

**B — Keep TBT's container, adopt Blizzard's layout engine.** Make TBT's container an actual
`GridLayoutFrame`, copy `stride`/padding/direction off the CDM viewer, anchor below it. Deletes the
hand-derived arithmetic without ever touching a Blizzard frame's children. *Upside:* near-zero taint
risk, fixes the actual maintenance problem. *Downside:* still two systems, still two Edit Mode
entries, and `GetLayoutData()`'s string may need parsing for settings the frames don't expose.

**C — Instantiate Blizzard's item templates inside TBT's own container.** Orthogonal to A/B and
combinable with either. Kills the reimplemented art in `Display.lua`. *Risk:* the template's `mixin`
runs `CooldownViewerBuffBarItemMixin:OnLoad`, which chains into `CooldownViewerItemMixin:OnLoad` and
expects a `cooldownID`; TBT's spells are not in the cooldown table. Probe is whether the frame can be
created and driven as art-only without its mixin erroring.

**D — Hook, do not inject; and invert the anchoring.** The option missing from the original three, and
on the evidence the one that actually works at scale. Nothing is parented into a Blizzard frame. Instead:

- `hooksecurefunc` the **mixin tables** — `CooldownViewerBuffBarItemMixin`,
  `CooldownViewerBuffIconItemMixin`, `CooldownViewerEssentialItemMixin`,
  `CooldownViewerUtilityItemMixin` — on `OnCooldownIDSet` to learn when Blizzard binds a cooldown to
  an item frame. **Gotcha that will cost a day otherwise:** mixin functions are *copied onto each frame
  instance at creation*, so a mixin-table hook never fires for frames that already existed when the
  hook was installed. Per-frame instance hooks must be installed lazily for those.
- `hooksecurefunc(viewer.itemFramePool, "Acquire", ...)` to catch every newly acquired item frame.
  This is the reliable discovery mechanism — far better than walking `GetChildren()` and guessing.
- `hooksecurefunc(viewer, "Layout")`, `(viewer, "SetPoint")` and `(viewer, "RefreshLayout")` to
  re-sync. Use `RefreshLayout` specifically for *immediate* reanchoring; a timer-based resync shows a
  visible flash.
- `EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow" / "OnHide", ...)` — a public
  callback, no hooking needed, for when the settings panel re-lays-out the viewers.
- Track hooked frames in a weak-keyed table (`setmetatable({}, { __mode = "k" })`) so nothing is
  retained and nothing is tainted.
- **Invert the anchoring.** Rather than TBT anchoring to `BuffBarCooldownViewer`, anchor the *viewer*
  to TBT's container, and have the `SetPoint` hook re-assert it when something else moves it. One
  container owns the geometry and the two systems stop fighting. This is the opposite of what
  `Display.lua:347-348` does today.

All of it is `hooksecurefunc` (runs after, cannot taint) plus reads of documented mixin getters. It is
also the mechanism that unlocks the data-source finding above, because the item frame you hook is the
frame whose `auraDataCached` you want.

**Recommendation to discuss: D is the spine; C on top of it for the art; B if TBT keeps its own
container; A remains a stretch and is probably unnecessary.** D and C together address the actual
maintenance cost — hand-reimplemented art and hand-derived layout math — without parenting anything
into an Edit Mode system frame.

### Probes

- **P2.1** `CreateFrame("Frame", nil, someTestParent, "CooldownViewerBuffBarItemTemplate")` — does it
  load without a `cooldownID`? Which mixin methods error? Can the regions be driven directly?
- **P2.2** Add a bare frame with `layoutIndex = 99` to `BuffBarCooldownViewer:GetItemContainerFrame()`,
  call `:Layout()`, and check it survives a CDM settings change -> `RefreshLayout` -> `ReleaseAll`.
- **P2.3** `print(C_CooldownViewer.GetLayoutData())` — dump the string, decide whether it is parseable
  and whether it contains anything the frames don't already expose. **Never call `SetLayoutData`
  during experimentation**; it would overwrite the user's real CDM configuration.
- **P2.4** Taint check for A: enter Edit Mode with an injected frame present, move a CDM viewer, exit,
  reload. Watch for blocked actions. This is the go/no-go for option A and is worth doing early
  precisely because a negative result saves the rest of the work.
- **P2.6** Install a `hooksecurefunc` on `CooldownViewerBuffBarItemMixin.OnCooldownIDSet` and on
  `BuffBarCooldownViewer.itemFramePool.Acquire`. Log which fires, when, and whether pre-existing
  frames are missed (they should be). Confirms option D's discovery mechanism and its documented gap.
- **P2.7 — the data-source probe, and now the most valuable single test in this plan.** From a
  `BuffBarCooldownViewer` item frame, read `GetAuraDataCached()`, `GetAuraDataUnit()` and
  `GetAuraSpellInstanceID()` in a dungeon. For the cached table: `canaccesstable` first, then
  `issecretvalue` per field. Then pipe `.applications` into `FontString:SetText` and confirm the
  stack count renders. **If this works, TBT gets real in-combat aura state without solving P1.1 at
  all.** Do not call `GetAuraDataByAuraInstanceID` here without a `pcall` — it hard-errors on
  restricted units.
- **P2.5** Compare TBT's hand-derived `BAR_PADDING_OFFSET` / `ICON_PADDING_OFFSET` against
  `CooldownViewerMixin:GetAdditionalPaddingOffset()`. If they disagree, TBT's current layout is subtly
  wrong today and that is a bug independent of this experiment.

---

## Experiment 3 — Spell cooldown tracking (-> next milestone)

The user has already decided this ships. Research says it is the **easiest** of the three, not the
hardest, and it is worth saying why before the window redesign gets scoped around the wrong
assumption.

Exactly three duration-object APIs in the entire client are marked `AllowedWhenTainted`, and all three
are `C_Spell`:

```
C_Spell.GetSpellCooldownDuration(spellIdentifier, ignoreGCD)  -- LuaDurationObject
C_Spell.GetSpellChargeDuration(spellIdentifier)               -- LuaDurationObject
C_Spell.GetSpellLossOfControlCooldownDuration(spellIdentifier)
```

Every other duration-object source — `GetActionCooldownDuration`, `GetSpellBookItemCooldownDuration`,
`GetTotemDuration`, `C_UnitAuras.GetAuraDuration`, the `UnitCasting/Channel` family — is
untainted-only. **Blizzard deliberately opened spell cooldowns to addons and left auras closed.** Note
also that `GetSpellCooldownDuration` carries *no* `SecretWhenCooldownsRestricted` flag, while
`GetSpellCooldown` (the struct-returning variant TBT would otherwise reach for) does.

So the display path is:

1. `C_Spell.GetSpellCooldownDuration(spellID)` -> duration object, keyed by **spellID** — which is what
   TBT already stores. No `auraInstanceID`, no secret key, no Experiment 1 blocker.
2. Hand the object straight to `Cooldown:SetCooldownFromDurationObject(d)` for a swipe, or
   `StatusBar:SetTimerDuration(d, interpolation, direction)` for a draining bar. **No reads, no
   `OnUpdate`, no secret ever touched.** This is the whole feature.
3. `d:HasSecretValues()` — readable — for anything that needs an actual number out of combat.
4. For thresholds (about to come off cooldown, charge nearly back), evaluate through a self-built curve
   (P1.7) rather than comparing. Per-frame `SetValue`/`SetText` pushing is the fallback if curve
   results turn out secret.

Also available and tainted-safe: `GetSpellCharges`, `GetSpellCastCount`, `IsSpellUsable`,
`GetSpellMaxCumulativeAuraApplications`. `C_UnitAuras.GetCooldownAuraBySpellID(spellID)` maps a spell
to its cooldown-aura spell, which is how the CDM links a cooldown to the buff it grants — relevant if
the add-buff window is to offer "track the cooldown" and "track the buff" as two facets of one entry
rather than two unrelated rows.

- **P3.1** `GetSpellCooldownDuration` on a known long cooldown, in and out of combat: readable out,
  `HasSecretValues()` in? Does a bar driven from `GetRemainingPercent()` actually move in a dungeon?
- **P3.2** `GetSpellCharges` on a charge spell — do charges read, and does `GetSpellChargeDuration`
  behave like the cooldown one?
- **P3.4** `Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration` fed from
  `GetSpellCooldownDuration` inside a dungeon. Visual check: does the swipe sweep and the bar drain
  with no Lua driving them? This is the single most load-bearing assumption in the whole plan and it is
  cheap to settle.
- **P3.3** `GetCooldownAuraBySpellID` for TBT's existing tracked spells — does it return the buff TBT
  already tracks? If so the data model unifies and the window redesign gets simpler.

**No probe is needed to justify the feature.** P3.1-P3.4 exist to settle the *data model* and the
render path before the add-buff window is redesigned around them. P3.4 is worth running first of all
four.

---

## Harness design

One throwaway file, not wired into the shipped load path, driven by a slash command. Rules:

1. **One file, never added to either TOC's load list.** The TOCs must stay identical apart from
   `## Interface:` and `## Notes:` (CLAUDE.md), and `check-toc.ps1` enforces it. Load the probe file
   by hand or behind a temporary local-only TOC edit that is reverted before any commit.
2. **`install.bat` deploys to every client folder present and never prunes.** For experimentation,
   set `%TBT_WOW_ROOT%` or copy the single file by hand into `_classic_beta_` and `_retail_` only.
   `_beta_` and `_ptr_` are out of scope.
3. **Every probe is wrapped, and the wrapper is not enough.** `pcall` covers the *call*. It does not
   cover a comparison or concatenation performed on the result afterwards — that is the mistake this
   project has already made once. Order per value, always: `issecretvalue()` -> `type()` ->
   `canaccesstable()` -> only then read. Never `tostring()` a value that might be secret.
4. **`type()` lies helpfully.** A secret number reports `"number"`. A type check alone is false
   confidence; it must follow `issecretvalue`.
5. **Three contexts, both clients.** Out of combat open world -> in combat open world -> inside a
   dungeon (`ShouldAurasBeSecret() == true`). Run on `_retail_` and `_classic_beta_`. Record
   `C_Secrets.HasSecretRestrictions()` first: if Forever returns false, *none* of the restriction
   findings apply there and the two clients need separate conclusions.
6. **Log to a table, print at the end.** Printing inside a restricted context risks the chat-messaging
   lockdown predicate (`SecretInChatMessagingLockdown`) and, for the visual probes, scrolls away the
   thing we are trying to watch.
7. **Visual probes cannot be asserted in Lua.** P1.4, P1.5 and P3.1 succeed or fail on screen. Plan
   for a screenshot per probe, not a log line.
8. **Record `C_Secrets.GetSpellAuraSecrecy` / `GetSpellCooldownSecrecy` per probe spell.** A spell
   flagged `NeverSecret` will produce a false positive that looks like a breakthrough. TBT already
   relies on this for the Sated debuffs.

> ### ⚠ Superseded in part by live testing — 2026-09-20
>
> `TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md` now carries measured results from the WoW Forever client
> and they settle three things in this document:
>
> 1. **P1.1 and P1.3 are dead.** `GetUnitAuraInstanceIDs`, `GetUnitAuras` and `GetAuraSlots` **hard
>    error** for tainted callers in restricted combat ("Auras cannot be accessed when secret while
>    tainted"), and the `UNIT_AURA` payload's `removedAuraInstanceIDs` is a secret table. The missing
>    `SecretWhenUnitAuraRestricted` flag meant *refused*, not *readable*. Closed, not deferred.
> 2. **Curve results are secret**, even from a self-built curve. The corrected model in "Duration
>    objects and curves" is confirmed; the earlier literal reading was wrong.
> 3. **The tier-1 render path works with genuinely secret values** — all nine widget sinks accepted
>    them — and **the CDM item frame's `auraDataCached` is readable with pipeable secret fields**, so
>    the CDM-as-data-source route replaces the aura API entirely.
>
> Read the test plan's Findings log before acting on anything below.

### Prioritisation rule (user decision, 2026-09-20)

**A technique already carrying a shipping, functional addon gets tested before one derived only from
the API documentation.** A working implementation in the wild is evidence the mechanism exists; a
documentation flag is a hypothesis about it. This plan has both kinds and they should not be run in the
same breath.

| Kind | Probes | Priority |
|---|---|---|
| Corroborated by a shipping addon | P3.4, P2.7, P2.6, P1.7 | First. Expect these to work; the probe confirms shape and cost, not existence. |
| Documentation inference only | P1.1, P1.2, P1.3, P1.5 | After. Genuinely unknown, and nothing structural should wait on them. |
| Cheap confirmations of existing behaviour | P2.1, P2.3, P2.5, P3.1-P3.3 | Any time. |

### Suggested order

P3.4 -> P2.7 -> P2.6 -> P1.7 -> P3.1 -> P1.3 -> P1.1 -> P1.5 -> P2.1 -> P2.3 -> P2.2 -> P2.4 -> the rest.

**P3.4** settles whether engine-driven rendering works at all; every tier-1 design depends on it.
**P2.7** is the highest-value single test, because a positive result routes around Experiment 1's
blocker entirely. **P2.6** is P2.7's delivery mechanism — without frame discovery there is nothing to
read. **P1.7** settles the curve pipe, the only conditional logic available in restricted content.

**P1.1 is demoted to near-last.** It was written as the pivot for Experiment 1. It rests purely on the
absence of a `SecretWhenUnitAuraRestricted` flag, no shipping addon appears to rely on it, and if P2.7
succeeds it stops deciding anything structural. Worth knowing, not worth blocking on.

---

## What this plan deliberately does not do

- No `SetLayoutData` call — it would overwrite the user's live CDM layout.
- No change to `CHANGELOG.md`.
- No `install.bat` run, no TOC edit committed, no deploy to `_beta_` or `_ptr_`.
- No attempt to defeat the secret-value system. Every path above is either a documented
  `AllowedWhenTainted` API or a read that the client itself declares readable. If a probe comes back
  "not possible", the answer is a documented limitation, not a workaround.
