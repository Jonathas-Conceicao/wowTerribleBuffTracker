# Pandemic Highlight — Research (v0.4.1)

**Researched:** 2026-09-24
**Scope:** Backlog 999.7 only — carrying Blizzard's CDM pandemic (refresh-window) highlight into
TBT's Merge Mode mirrored icons/bars. Existing TBT capabilities are out of scope.

## Summary

- Blizzard computes the pandemic window as two plain numeric fields on the CDM item frame itself
  (`itemFrame.pandemicStartTime` / `pandemicEndTime`), and separately keeps a plain frame reference
  (`itemFrame.PandemicIcon`) that is non-nil exactly while the highlight is shown. Both are **plain
  table-field reads**, not mixin-method calls — both are legal under `MergeMode.lua`'s rule 1.
- **Recommended signal: `itemFrame.PandemicIcon ~= nil`.** A frame reference is never a secret
  value, so this read is unconditionally reliable regardless of combat/aura-secrecy state — unlike
  the timestamp fields, which are almost certainly secret-tainted in combat because they are
  arithmetic derived from `auraData.expirationTime`, the same field TBT already has to guard
  everywhere else. Read it inside the already-whitelisted `itemFramePool:EnumerateActive` walk;
  no new CDM surface is needed.
- **Recompute is closed**, for a reason already established in this codebase, not a new finding:
  `expirationTime`/`duration` are secret in combat, and the two APIs that would let TBT redo
  Blizzard's own math (`GetRefreshExtendedDuration`, `GetAuraBaseDuration`) both key off
  `auraInstanceID`, which Blizzard flags `DisallowTaintedAccess` (per `MergeMode.lua`'s own header).
  Read Blizzard's answer; do not rebuild it.
- **Forever ships the identical pandemic system**, verified against `BigWigsMods/WoWUI`
  branch `forever-beta` line-for-line (same functions, same field names, ~7-line offset only).
  `PandemicAlertAnimation.xml` and the rest of `Blizzard_CooldownViewer` load under
  `## AllowLoadGameType: standard, camelot` — Forever included, no flavour gate. HIGH confidence
  this is present in the client; MEDIUM confidence it behaves observably the same, because
  Forever's aura-secrecy in combat is already measured (999.6) to be *more* aggressive than
  retail's for direct addon reads, and this feature's fallback numeric-field route depends on
  exactly that kind of read.
- Item-backed merged entries (trinkets, potions, healthstones — `equipSlot`/`spellCategoryID`
  entries) are structurally excluded from pandemic at the source (`IsItem()` short-circuits
  `CheckSetPandemicAlertTriggerTime` before anything else runs) — no extra filtering needed on
  TBT's side beyond what `MergeMode.lua` already tracks.

## How Blizzard Does It (verified, with file:line)

All line numbers are from the local retail snapshot,
`C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\`, branch
`live` (12.1). Forever line numbers are offset by roughly −7 for everything after the file's
first ~500 lines (confirmed by direct diff of the pandemic block below); function names and field
names are byte-identical.

**Computation (`CooldownViewerItemMixin`, mixed into every CDM item — `CooldownViewer.lua`):**

- `CheckSetPandemicAlertTriggerTime(auraData, timeNow)` — `:529-554`. Bails immediately if
  `self:IsItem()` or `not self:CanUseAuraForDisplay()` (`:530`) — item-backed entries and
  `HideAura`-flagged entries never get a pandemic window. Otherwise reads the item's cached aura
  (`self:GetAuraDataCached()`, `:534`), and if the aura is currently active, asks
  `C_UnitAuras.GetRefreshExtendedDuration` and `GetAuraBaseDuration` (`:539-540`) what the new
  duration would be if the spell were recast *right now*. `carriedOverToNewCast` is the delta
  between those two (`:541`). If that delta is positive **and** `self:CanTriggerAlertType(PandemicTime)`
  is true (`:542`), it calls `SetPandemicAlertTriggerTime` with the window bounds.
- `CanTriggerAlertType(alertType)` — `CooldownViewerItemData.lua:1052-1055`. Checks membership in
  `self.validAlertTypes`, itself `tInvert(C_CooldownViewer.GetValidAlertTypes(cooldownID))`
  (`:1041-1044`), a per-cooldown native capability set. This is the same table the alerts *settings
  dropdown* uses to populate which alert types are offered at all
  (`CooldownViewerSettingsAlerts.lua:15`, `self.validCooldownAlertTypes = cooldownItem:GetValidAlertTypes()`).
  **This reads as "can this spell structurally have a pandemic window" (does it grant a
  refreshable self-aura), not "has the player turned pandemic alerts on for this entry."**
  MEDIUM confidence — inferred from how the same set is consumed elsewhere in source, not from an
  explicit doc comment or in-game confirmation. If wrong, the whole feature is opt-in per spell
  and TBT would be silently correct anyway (it only mirrors what CDM itself lights up).
- `SetPandemicAlertTriggerTime(timeNow, pandemicStartTime, pandemicEndTime)` — `:556-565`. Writes
  three **plain fields** on the item frame: `self.pandemicAlertTriggerTime`,
  `self.pandemicStartTime`, `self.pandemicEndTime`. Then calls `self:CheckPandemicTimeDisplay(timeNow)`
  (`:563`) and `self:RefreshOnUpdateRegistration()` (`:564`).
- `IsInPandemicTime(timeNow)` — `:611-613`. `return self.pandemicStartTime and timeNow >=
  self.pandemicStartTime and timeNow <= self.pandemicEndTime`. Pure arithmetic on the two plain
  fields above — the exact recompute TBT could do itself **if** those fields are readable.
- `CheckPandemicTimeDisplay(timeNow)` — `:585-591`. `ShowPandemicStateFrame()` if
  `IsInPandemicTime`, else `HidePandemicStateFrame()`. Called from three places: inside
  `SetPandemicAlertTriggerTime` (`:563`, i.e. on every aura refresh that recomputes the window —
  `CheckCacheCooldownValuesFromAura`, `:861-907`, calls `CheckSetPandemicAlertTriggerTime` at
  `:904` on every `OnUnitAuraUpdatedEvent`/`RefreshData` pass), from `CooldownViewerBuffItemMixin
  :OnActiveStateChanged` (`:1340-1343`), and from the item's own `OnUpdate` (`:63`, ticking once
  per frame **only while the item is registered for OnUpdate**).
- `ShowPandemicStateFrame()` / `HidePandemicStateFrame()` — `:593-609`. Lazily acquires a frame
  from `self:GetViewerFrame().pandemicIconPool` on first show (`:594-596`,
  `self.PandemicIcon = self:GetViewerFrame():SetupPandemicStateFrameForItem(self)`), keeps reusing
  the same instance across repeated windows, and only releases it back to the pool — nil'ing
  `self.PandemicIcon` — on `HidePandemicStateFrame` (`:601-604`,
  `self:GetViewerFrame():HidePandemicStateFrame(self.PandemicIcon); self.PandemicIcon = nil`).
- **OnUpdate registration is conditional, not permanent.** `NeedsOnUpdateRegistration()` —
  `:472-474` — is true only while `self.pandemicAlertTriggerTime` is set (i.e. before the alert has
  fired) or while other alert types are pending. `TriggerPandemicAlert()` (`:575-583`) nils
  `pandemicAlertTriggerTime` the instant the window opens (`:577`), which can immediately make
  `NeedsOnUpdateRegistration()` false and deregister the item's `OnUpdate` — meaning
  `CheckPandemicTimeDisplay` stops ticking from `OnUpdate` right as the window begins, and the
  eventual *hide* at window end then depends on the aura-refresh path (`OnUnitAuraUpdatedEvent` /
  `OnUnitAuraRemovedEvent` → `RefreshData` → `CheckCacheCooldownValuesFromAura` → the chain above)
  firing again, not on a frame tick. See Unknown #3 below — this is a real staleness risk for
  Blizzard's *own* rendering, and it directly informs which signal TBT should prefer.

**Item frame → viewer frame linkage (needed to reach `pandemicIconPool` and the anchor override):**

- `ShowPandemicStateFrame` calls `self:GetViewerFrame()` (`:106-108`,
  `CooldownViewerItemMixin:GetViewerFrame` returns `self.viewerFrame`, set via `:SetViewerFrame`
  `:102-104`) — so the pool and anchor logic live on the **viewer**, not the item.
- `CooldownViewerMixin:OnLoad` — `:1641-1648` — creates both pools on the viewer:
  `self.itemFramePool = CreateFramePool("FRAME", self:GetItemContainerFrame(), self.itemTemplate, itemResetCallback)`
  and `self.pandemicIconPool = CreateFramePool("FRAME", self, self:GetPandemicStateFrameTemplate())`.
  Per `MergeMode.lua`'s own established finding (its header, and inline at the `itemFramePool
  :EnumerateActive` justification block), `Pools.lua:857` redefines the global `CreateFramePool` to
  `CreateSecureFramePool`, so **both** pools — `itemFramePool` and `pandemicIconPool` — are secure
  pool proxies (`ObjectPoolProxyMixin`), not raw Blizzard pool tables. TBT does not need to touch
  `pandemicIconPool` at all under the recommended approach (see next section), but if it ever did,
  the same taint argument `MergeMode.lua` already makes for `itemFramePool:EnumerateActive` would
  apply unchanged.
- `CooldownViewerMixin:GetPandemicStateFrameTemplate()` — `:2116-2119` — default
  `"CooldownPandemicFXTemplate"` (icon FX).
- `CooldownViewerMixin:SetupPandemicStateFrameForItem(cooldownItem)` — `:2121-2127` — acquires from
  the pool, `frame:SetParent(cooldownItem)`, then `AnchorPandemicStateFrame`.
- `CooldownViewerMixin:AnchorPandemicStateFrame(frame, cooldownItem)` — `:2129-2133` — default
  icon anchor: `TOPLEFT −6/+6, BOTTOMRIGHT +6/−6` relative to the item frame. No explicit frame
  level; relies on `frameStrata="MEDIUM"` from the XML template alone.
- `CooldownViewerMixin:HidePandemicStateFrame(stateFrame)` — `:2135-2137` — `self.pandemicIconPool
  :Release(stateFrame)`.

**Per-viewer-type overrides — which mixin backs which of TBT's four mirrored categories:**

| TBT container | Viewer mixin chain | Pandemic template | Anchor override |
|---|---|---|---|
| Essential Cooldowns | `EssentialCooldownViewerMixin` → `CooldownViewerCooldownMixin` → `CooldownViewerMixin` (`:2141`, `:2203`) | base icon (`CooldownPandemicFXTemplate`) | base `-6/+6`, no override |
| Utility Cooldowns | `UtilityCooldownViewerMixin` → `CooldownViewerCooldownMixin` → `CooldownViewerMixin` (`:2226`) | base icon | base `-6/+6`, no override |
| Tracked Buffs (icons) | `BuffIconCooldownViewerMixin` → `CooldownViewerBuffMixin` → `CooldownViewerMixin` (`:2250`, `:2265`) | base icon | base `-6/+6`, no override |
| Tracked Bars | `BuffBarCooldownViewerMixin` → `CooldownViewerBuffMixin` → `CooldownViewerMixin` (`:2293`) | **overridden**, `CooldownPandemicBarFXTemplate` (`:2348-2351`) | **overridden** — `AnchorPandemicStateFrame` (`:2353-2358`): `TOPLEFT` `cooldownItem.Bar` `-9/+10`, `BOTTOMRIGHT` `+9/-10`, plus `frame:SetFrameLevel(cooldownItem.Bar:GetFrameLevel() + 1)` |

All four mirror categories are therefore covered — three icon-styled (default anchor/template) and
one bar-styled (overridden anchor, template, and an explicit frame-level bump). This matches
exactly what `ROADMAP.md`'s backlog entry already recorded.

**XML templates — `PandemicAlertAnimation.xml` (both flavours, byte-identical, verified below):**

- `CooldownPandemicFXTemplate` (`:3-45`) — `inherits="AnimateWhileShownTemplate"`,
  `frameStrata="MEDIUM"`, `hidden="true"`, `virtual="true"`. A `Border` child textured with atlas
  `UI-CooldownManager-PandemicBorder`, and an `FX` child holding three looping/staggered
  Scale+Alpha animated textures (`UI-CooldownManager-PandemicFX-Icon01/02/03`) masked by
  `UI-CooldownManager-PandemicBorder-Mask`. The `AnimationGroup` is `looping="REPEAT"`, three
  2-second scale+fade cycles staggered 1.5s apart, so the whole loop is continuous once shown.
- `CooldownPandemicBarFXTemplate` (`:47-81`) — same inheritance/strata/hidden/virtual. A `Border`
  child on atlas `UI-CooldownManager-PandemicBorderBar`, and a `Texture` child on atlas
  `UI-CooldownManager-PandemicFX-Bar` masked by `UI-CooldownManager-PandemicBorderBar-Mask`,
  driven by a single continuous 5-second 360° `Rotation` animation.
- Both templates are `virtual="true"` with stable, documented names — instantiable by any addon via
  `CreateFrame("Frame", nil, parent, "CooldownPandemicFXTemplate")` (or the bar variant), same as
  TBT already does elsewhere for Blizzard's other virtual CDM templates.

## Reading The State Without Tainting

**Recommended: `itemFrame.PandemicIcon ~= nil`.**

- Plain field read. `MergeMode.lua`'s header (`:11-15`) permits "Plain C widget getters and plain
  table-field reads"; this is the latter. No mixin method is invoked.
- Reachable from the already-whitelisted `itemFramePool:EnumerateActive()` walk `MergeMode.lua`
  already performs in `BuildViewerIDs` (`:181`) and `CollectShownCooldownIDs` (`:485`) — no new CDM
  surface, no new taint argument needed. The existing per-entry stamping pass in
  `ns:RefreshMergeShownSlots` (`MergeMode.lua:694-806`) is the natural place to add one more
  boolean, alongside the existing `entry.cdmShown` stamp (`:786`) and the `hideAura`/`hasCharges`/
  `selfAura`/`auraExpiry` stamps already made there.
- **Unconditionally readable regardless of combat/secrecy state**, because a frame *reference* is
  never itself a secret value — only the numeric/string *data* fields on a frame can be
  secret-tainted. This is the deciding advantage over the fallback below, and it is exactly the
  situation (combat) where the highlight matters most and where the timestamp fields are least
  likely to be readable.
- Caveat carried over from "How Blizzard Does It": Blizzard's own hide of this frame can lag behind
  the true end of the window because `OnUpdate` deregisters once `pandemicAlertTriggerTime` is
  nil'd (see Unknown #3). TBT inherits that same lag if it mirrors `PandemicIcon` literally — it
  is not perfectly synchronized to `IsInPandemicTime`, it is synchronized to *whatever Blizzard's
  own rendering currently shows*, which is what "carry the CDM's indicator over" actually means
  for this feature, so this is arguably correct behavior, not a bug to fix.

**Fallback / enhancement: `itemFrame.pandemicStartTime` / `itemFrame.pandemicEndTime`, guarded.**

- Also plain field reads, also legal under rule 1. Doing `now >= start and now <= end` with
  `now = GetTime()` (TBT's own clock, never Blizzard's) reproduces `IsInPandemicTime` **without
  calling the mixin method** — literally reading Blizzard's already-computed answer and doing the
  comparison TBT is allowed to do itself, exactly as the backlog entry frames it ("read the CDM's
  own answer" rather than recompute from the aura).
  - Guard exactly like every other numeric field `MergeMode.lua` already reads off a CDM structure:
    `if not issecretvalue(start) and type(start) == "number" and not issecretvalue(finish) and type(finish) == "number" then …`
    (mirrors the pattern at `MergeMode.lua:650-656` for `aura.expirationTime`/`aura.duration`).
- These two fields are almost certainly secret-tainted whenever the underlying aura is, because
  `pandemicStartTime`/`pandemicEndTime` are computed as `auraData.expirationTime − carriedOverToNewCast`
  and `auraData.expirationTime` directly (`CooldownViewer.lua:545`) — arithmetic on a secret value
  propagates the secret flag. Not proven from source (the secret-value propagation rule for
  Blizzard's own internal Lua, as opposed to addon-tainted Lua, is not something the local snapshot
  states explicitly), but it is consistent with the project's own established finding that the CDM's
  Cooldown getters are `SecretReturnsForAspect` and its numeric Cooldown setters are
  `AllowedWhenUntainted` (`MergeMode.lua:906-912`) — the whole point of that machinery is that even
  Blizzard's own UI code cannot handle these numbers as plain Lua values in a restricted context, it
  can only pass them through secret-safe widget channels. LOW-MEDIUM confidence; flagged as
  Unknown #2 below.
- Value if it works: gives TBT the **exact window bounds**, not just a boolean, which is enough to
  drive TBT's own animation timing/`Show()`/`Hide()` calls independent of Blizzard's own
  `OnUpdate`-registration staleness. Treat as a nice-to-have refinement layered on top of the
  `PandemicIcon` boolean, not a replacement for it — when secret, fall back to the boolean.

**What is explicitly NOT viable:** calling `itemFrame:IsInPandemicTime()`,
`itemFrame:ShowPandemicStateFrame()`, `itemFrame:CheckSetPandemicAlertTriggerTime()`, or any other
method on `CooldownViewerItemMixin`/`CooldownViewerItemDataMixin` — every one of those is a
Blizzard mixin method on a CDM frame, forbidden outright by `MergeMode.lua:11-13`. Likewise,
touching `viewer.pandemicIconPool` (`:Acquire`/`:Release`) is out — that pool is CDM-owned and
Release in particular is a write against a CDM-owned resource; only `EnumerateActive`-class reads
on `itemFramePool` are the admitted exception, and `pandemicIconPool` was never separately audited
or admitted.

## Recompute Route

**Closed.** Not new research — this restates what `MergeMode.lua` already established and applies
it to this specific case.

- Recomputing `IsInPandemicTime` from scratch needs `auraData.expirationTime` and `auraData.duration`
  (to know the current window) *and* `C_UnitAuras.GetRefreshExtendedDuration` /
  `GetAuraBaseDuration` (to know what a fresh cast would extend it to) — the exact calculation
  Blizzard performs at `CooldownViewer.lua:539-541`.
- `expirationTime`/`duration` are secret in combat per `CLAUDE.md` ("most values are hidden as
  Secret Values") and per `MergeMode.lua`'s own extensive guarding of exactly these two fields
  throughout `TryResolveFromSpellID` (`:648-656`).
- `GetRefreshExtendedDuration`/`GetAuraBaseDuration` both take `auraInstanceID` as a required
  parameter, and `MergeMode.lua`'s header already states the instance IDs that would unlock these
  calls "live in a table Blizzard flags `DisallowTaintedAccess`" (`:511-513`). TBT has no legal way
  to obtain an `auraInstanceID` for an arbitrary target's aura from tainted code.
- Even where `expirationTime`/`duration` themselves are readable (out of combat, self-buffs), TBT
  would still be missing the "what would a fresh cast look like" half of the computation, since
  that requires the instance ID it cannot have.
- Conclusion unchanged from the roadmap: read Blizzard's own answer (`PandemicIcon` /
  `pandemicStartTime`/`pandemicEndTime`), never rebuild it.

## Forever Support Status

**HIGH confidence the code ships; MEDIUM confidence it behaves observably identically in play.**

- Verified directly against `https://raw.githubusercontent.com/BigWigsMods/WoWUI/forever-beta/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua`
  (fetched via `curl`, not summarized): every pandemic function and field name present —
  `CheckSetPandemicAlertTriggerTime` (`:522`), `SetPandemicAlertTriggerTime` (`:549`),
  `IsInPandemicTime` (`:604`), `ShowPandemicStateFrame`/`HidePandemicStateFrame` (`:586`, `:594`),
  `GetPandemicStateFrameTemplate`/`AnchorPandemicStateFrame` overrides on
  `BuffBarCooldownViewerMixin` (`:2360`, `:2365`), `pandemicIconPool` creation (`:1649`). File is
  2386 lines vs retail's ~2460 — the pandemic block itself is byte-for-byte identical logic, offset
  by roughly 7 lines throughout (one small unrelated diff earlier in the file).
- `Blizzard_CooldownViewer.toc` on `forever-beta` declares `## AllowLoadGameType: standard, camelot`
  (fetched directly) and lists `PandemicAlertAnimation.xml` in its file list, immediately after
  `CooldownViewer.lua` — identical position to retail. Forever's `camelot` game type is explicitly
  admitted, so this file set loads there, not just on `standard`.
- What is **not** verified from source and needs in-game confirmation: whether Forever's spell
  data on build `1.60.1.69913` actually produces `carriedOverToNewCast > 0` for any tracked
  buff/debuff at all (i.e., whether Forever's aura-refresh semantics match retail's "pandemic"
  window math), and whether the secret-value propagation on the two timestamp fields behaves the
  same as retail. The project's own prior probe (`ROADMAP.md` backlog 999.6) found Forever's aura
  restriction in combat to be **more aggressive than retail's for direct addon reads** —
  `C_UnitAuras.GetUnitAuras`/`GetAuraDataByIndex` raise outright rather than degrading — which is a
  reason for caution, not a reason to expect parity, even though the `PandemicIcon` boolean route
  itself does not depend on any addon-side aura read and should be unaffected by that specific
  finding.
- No evidence found, in either source tree, of the pandemic system being gated behind
  `WOW_PROJECT_ID` or any other flavour check — it is unconditional in both.

## Rendering: Templates And Pitfalls

TBT must create and own **its own** instances of the virtual templates, parented to its own
mirrored icon/bar frames — never touch or reparent Blizzard's `PandemicIcon` frame itself, which
belongs to `viewer.pandemicIconPool` and is a CDM-owned resource.

- **Pooling.** Blizzard's `pandemicIconPool` is off-limits (see above). TBT needs its own pool —
  the same `CreateFramePool("FRAME", tbtOwnParent, "CooldownPandemicFXTemplate", resetCallback)`
  idiom, scoped per merged-entry-widget the way TBT already pools its other reusable UI pieces.
  Because `CreateFramePool` is globally rebound to `CreateSecureFramePool` (`Pools.lua:857`, per
  `MergeMode.lua`'s own citation), a pool TBT creates over its **own** frames is still a secure
  proxy — this has no practical downside for TBT (it never needed write access to Blizzard's proxy
  objects, only read access via `EnumerateActive`), but note the object returned by `:Acquire()`
  will itself be a secure-pool-managed frame; that's fine, it is not a CDM frame.
- **Animation lifecycle.** `AnimateWhileShownTemplate` starts/stops its `AnimationGroup` on the
  frame's own `Show`/`Hide` — no dependency on `CooldownViewerItemMixin` or any CDM controller code,
  so a standalone instantiation behaves identically to Blizzard's. TBT toggles the highlight purely
  with `Show()`/`Hide()` on its own frame in response to the observed signal; nothing about the
  template requires being a child of a real CDM item.
- **Frame level / anchoring.** For icon-styled mirrors, replicate `-6/+6` around TBT's own icon
  frame with no extra frame-level work (matches base `AnchorPandemicStateFrame`,
  `CooldownViewer.lua:2129-2133`). For the bar-styled mirror, replicate `-9/+10` around TBT's bar's
  actual bar sub-region (whatever TBT's bar widget's equivalent of Blizzard's `cooldownItem.Bar`
  child key is) **and** the explicit `SetFrameLevel(bar:GetFrameLevel() + 1)` bump
  (`CooldownViewer.lua:2353-2357`) — this is a plain `SetFrameLevel` call on TBT's own frame, not a
  CDM frame, so it carries no taint risk, but omitting it will visually misorder the border behind
  the bar fill exactly as it would in Blizzard's own UI if the override were skipped.
- **Absence-of-template guard.** No mechanism was found to introspect virtual-template existence
  ahead of instantiation; the established defensive idiom elsewhere in this codebase is to wrap the
  `CreateFrame(..., "CooldownPandemicFXTemplate")` call (and its bar counterpart) in a `pcall` and
  degrade to "no highlight" on failure, consistent with the capability-check pattern used throughout
  `MergeMode.lua` (e.g. the `Enum.CooldownViewerCategory` / `Enum.CooldownSetSpellFlags` checks) and
  `CLAUDE.md`'s "guard Secret Value usages behind fail-safe calls" constraint. Given both flavours'
  TOCs load `Blizzard_CooldownViewer` unconditionally and TBT already hard-depends on the CDM, the
  realistic risk here is low, but the guard costs nothing.
- **Taint.** Because every frame TBT creates for this feature is TBT-owned from `CreateFrame` up —
  never acquired from or parented into a Blizzard pool/frame — none of `Show`, `Hide`, `SetPoint`,
  `SetFrameLevel`, or `CreateFrame` itself trips the locked no-mixin-call / no-CDM-frame-write rule.
  The rule is specifically about frames TBT does not own; these are frames TBT does.
- **Forever.** Both templates and their atlases are confirmed present in the same file at the same
  position in the load order; no flavour branch is needed for instantiation itself.

## MEASURED — retail, 2026-09-24

The unknowns below are kept verbatim as written. Four of the five now have measured answers, from
a Restoration Druid on retail using Entangling Roots out of combat (`/tbt debug` + `/tbt merge`).
**The document's central recommendation was correct**; read this block before the list.

First observation of a live window, on the `Entangling Roots` entry (`id=90596`, a TARGET debuff):

```
window ACTIVE   frame=yes icon=yes  trigger=nil        start=86547.021  finish=86556.021  answer=true
window PENDING  frame=yes icon=no   trigger=86577.006  start=86577.006  finish=86586.006  answer=false
```

- **Unknown 2 — FULLY ANSWERED, and this document's LOW-MEDIUM prediction was RIGHT.** The
  timestamps are **plain readable numbers out of combat** and **secret in combat**. Measured on
  Moonfire, in combat:

  ```
  before window   frame=yes icon=no   start(secret=true,type=number,val=nil)   answer=false route=boolean
  in window       frame=yes icon=yes  start(secret=true,type=number,val=nil)   answer=true  route=boolean
  ```

  **`secret=true` alongside `type=number`.** That is the locked `issecretvalue()`-before-`type()`
  rule earning its keep in the most literal way available: a `type(v) == "number"` test *passes*
  on a secret number, so the reverse ordering would have fed a secret into the comparison. This is
  the same class of defect the project already records for `useSpellID` truthiness
  (`Providers.lua:970`), now observed on a second API.

  **The boolean primary is what makes the feature work in combat**, which is when it matters. The
  numeric refinement is a precision upgrade for the out-of-combat case, not the load-bearing path.
  The user's kickoff decision to build both signals is vindicated: numbers-only would be dead in
  combat, boolean-only would work but lose the exact window bounds out of it.
- **Unknown 3 — ANSWERED: capability, not preference.** `C_CooldownViewer.GetValidAlertTypes`
  returns `PandemicTime` for exactly the refreshable auras (Entangling Roots, Moonfire, Wild
  Growth, Tranquility) and not for instant cooldowns, on an unmodified configuration. A Frost mage
  reported `alertCap=no` on every entry including Chilled, which is why an earlier attempt to test
  there produced nothing — that spec has no player-refreshable aura at all.
- **Unknown 5 — ANSWERED: yes.** Entangling Roots is a target debuff (`notSelfAura`) and the read
  worked on it, so the target-unit polarity is fine.
- **Unknown 1 — ANSWERED in practice.** `PandemicIcon` went `yes` during the active window and `no`
  both once the window was merely pending (Entangling Roots) and after the window ended in combat
  (Moonfire: ON at `t=86709.772`, OFF at `t=86714.589`, ~4.8s apart, with no intervening recast).
  It tracks the active state rather than lingering. The `OnUpdate`-deregistration staleness this
  document warned about was not observed.
- **Unknown 4 — STILL OPEN.** Forever untested; the server was down. Retail is confirmed on two
  specs, in and out of combat, on both a target debuff and a DoT.

**`pandemicAlertTriggerTime` is NOT the window start.** It is the time the alert is *scheduled* to
fire, consumed and nil'd when it does — which is what this document's own `OnUpdate`-deregistration
note was describing. It is present exactly when the window is *not* active, so it is the inverse of
what a naive reading suggests. TBT reads and prints it for diagnostics and deliberately does not
route on it: it has no upper bound and would latch a highlight on permanently.

## Unknowns Requiring In-Game Verification

1. **Does `itemFrame.PandemicIcon` reliably clear at the true end of the window, or can it linger
   past `pandemicEndTime` due to the `OnUpdate`-deregistration behavior traced above
   (`CooldownViewer.lua:472-484`, `:577`)?** Testable: track a debuff with a known refresh window
   in a static rotation (no other aura churn), watch whether the CDM's own border visually
   disappears promptly at window end or hangs until the next unrelated aura event.
2. **Are `itemFrame.pandemicStartTime` / `pandemicEndTime` actually secret-tainted for a tainted
   reader (TBT) while the underlying aura is under combat restriction, or are they plain numbers
   even then?** Testable: with debug logging (the existing `TOOL-01`-style guarded print pattern),
   dump `type(itemFrame.pandemicStartTime)` and `issecretvalue(itemFrame.pandemicStartTime)` for a
   pandemic-eligible entry, both in and out of combat, on retail.
3. **Does `CanTriggerAlertType(PandemicTime)` gate on spell capability (this document's working
   assumption) or on a player-configured alert preference?** Testable: on a fresh CDM
   configuration with no alert customization at all, does the pandemic border still appear for a
   spell known to have a refreshable duration (e.g. a DoT)? If it does not, this whole feature
   needs a secondary "did the player enable pandemic alerts for this entry" check that this
   research did not anticipate.
4. **Does Forever's build `1.60.1.69913` actually produce a positive `carriedOverToNewCast` for
   any spell TBT would mirror**, i.e. does the pandemic mechanic fire in practice on that content,
   not just exist in the shipped code? Testable: track any DoT/HoT on a Forever character and
   recast it inside the refresh window; watch whether Blizzard's own CDM border appears at all.
5. **Does the `PandemicIcon` boolean read stay reliable for the target-unit polarity** (a CDM
   "tracked buff" that is really a debuff TBT is displaying via the target-aura path already built
   in `MergeMode.lua`, `:876-878`)? The pandemic system as traced here operates per-item-frame
   regardless of aura polarity, so this should just work, but it has not been observed against a
   target-debuff entry specifically.

## Implications For Scoping

**Likely one phase**, with a strong recommendation to open it with a short in-game verification
spike before locking a plan, because three of the five unknowns above (#1, #2, #3) each change
which signal is primary and whether a fallback path is even needed:

- The read side is cheap to add: one more boolean (or two guarded numbers) stamped onto each
  merged entry inside the pass `ns:RefreshMergeShownSlots` already runs
  (`MergeMode.lua:694-806`), reusing the exact `itemFramePool:EnumerateActive` walk already
  performed there and in `BuildViewerIDs` — no new CDM surface, no new taint argument to write.
- The render side is new: TBT needs its own pooled `CooldownPandemicFXTemplate` /
  `CooldownPandemicBarFXTemplate` instances wired into its existing icon/bar mirror widgets, with a
  pcall guard around creation. This is additive to the render path, not a rework of it.
- Item-backed merged entries (trinkets, potions, healthstones) need zero handling — they are
  excluded at the Blizzard source (`IsItem()` guard, `CooldownViewer.lua:530`), so TBT's
  already-existing `equipSlot`/`spellCategoryID` entries simply never carry the signal.
- Forever needs its own verification pass within the same phase (per this project's standing
  "build and test on Forever as it lands" pattern), specifically Unknown #4, since the codebase
  presence is confirmed but the in-practice trigger is not.
- Split into two phases only if Unknown #1 or #2 surfaces a real defect requiring the numeric-field
  fallback to be built as more than a nice-to-have — in that case the fallback arithmetic path
  (guarded `now >= start and now <= end`) becomes load-bearing rather than a refinement, which is
  enough extra surface (a second signal, a "which one wins" precedence rule, more in-game
  verification) to justify its own phase.
- Explicitly out of scope per the backlog item itself: whether TBT's own *native* (non-merged)
  trackers should compute a pandemic window arithmetically from their own known durations. That is
  a separate, simpler question (TBT owns those durations outright, no secrecy involved) and is not
  part of 999.7.
