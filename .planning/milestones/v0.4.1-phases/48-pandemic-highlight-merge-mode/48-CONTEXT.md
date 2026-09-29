# Phase 48: Pandemic Highlight in Merge Mode - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous), questions front-loaded and answered by the user before work began

<domain>
## Phase Boundary

A merged CDM entry inside its pandemic refresh window carries Blizzard's own highlight onto TBT's
mirrored icon and bar, read without tainting a CDM frame, and clears when the window ends.

Requirements: PAND-01, PAND-02, PAND-03, PAND-04, PAND-05.

**Merged entries only.** Whether TBT's own *native* (non-merged) trackers should compute a pandemic
window from their own known durations is explicitly out of scope per the backlog item itself — it
is a separate and much simpler question, since TBT owns those durations outright and no secrecy is
involved.

</domain>

<decisions>
## Implementation Decisions

### Signal — USER DECISION, front-loaded 2026-09-24

**Build both signals, with the boolean primary and the numeric pair as a refinement that degrades
silently.** The user chose this over boolean-only and over pausing for an in-game spike first.

- **Primary: `itemFrame.PandemicIcon ~= nil`.** A frame *reference* can never be a secret value —
  only numeric/string data fields on a frame can be secret-tainted. So this read is reliable
  regardless of combat or aura-secrecy state, which is exactly the situation where the highlight
  matters most.
- **Refinement: `itemFrame.pandemicStartTime` / `pandemicEndTime`**, guarded
  `issecretvalue()`-then-`type()`, compared against TBT's own `GetTime()`. These are almost
  certainly secret-tainted in combat — they are arithmetic on `auraData.expirationTime`, which TBT
  already has to guard everywhere else — so when unreadable the code falls back to the boolean.
  PAND-05 requires that degradation anyway, so building it costs almost nothing beyond the guard
  that was mandatory regardless.
- Precedence is fixed and must not be inverted: **numbers win when readable, boolean otherwise.**
  The numbers give exact window bounds; the boolean gives whatever Blizzard is currently rendering.
- **Recomputing the window is CLOSED.** It needs `auraInstanceID`, which Blizzard flags
  `DisallowTaintedAccess`. Read Blizzard's answer; never rebuild it. This is not a new finding — it
  restates what `MergeMode.lua`'s own header already established.

### The no-taint rule — LOCKED, pre-existing, non-negotiable

`MergeMode.lua`'s header (`:5-25`) is the constraint. Five injection experiments proved that
touching a CDM frame the wrong way taints it permanently, surviving combat and clearing only on
`/reload`. TBT must never:

1. call a Blizzard **mixin method** on a CDM frame — so `itemFrame:IsInPandemicTime()`,
   `:ShowPandemicStateFrame()` and `:CheckSetPandemicAlertTriggerTime()` are all forbidden outright;
2. write a field on a CDM frame;
3. parent anything into a CDM frame;
4. call `C_CooldownViewer.SetLayoutData`.

Permitted: plain C widget getters, plain table-field reads, and exactly one generic-container call,
`viewer.itemFramePool:EnumerateActive`. **`itemFrame.PandemicIcon` and the two timestamps are plain
table-field reads and are therefore legal.** `viewer.pandemicIconPool` is NOT — that pool is
CDM-owned, `:Release` in particular is a write against a CDM-owned resource, and it was never
separately audited or admitted.

### Where the read goes — no new CDM surface needed

`CollectShownCooldownIDs` (`MergeMode.lua:478-500`) already walks
`viewer.itemFramePool:EnumerateActive()` and **already caches the frame per cooldown**:
`ns.mergeItemFrames[cooldownID] = itemFrame` (`:497`). So the pandemic state can be read straight
off `ns.mergeItemFrames[entry.cooldownID]` inside the existing per-entry stamping pass in
`ns:RefreshMergeShownSlots` (`:780-800`), alongside the `entry.cdmShown` stamp already made there.

**No new walk, no new API, no new taint argument to write.** One more stamped boolean on the entry.

### Rendering — TBT-owned frames only

- TBT creates and owns **its own** instances of `CooldownPandemicFXTemplate` (icon) and
  `CooldownPandemicBarFXTemplate` (bar), parented to TBT's own mirrored widgets. It never touches,
  reparents or acquires Blizzard's `PandemicIcon` frame.
- Every frame created this way is TBT-owned from `CreateFrame` up, so `Show`, `Hide`, `SetPoint`
  and `SetFrameLevel` on them carry no taint risk. The locked rule is about frames TBT does not own.
- `AnimateWhileShownTemplate` starts and stops its animation on the frame's own `Show`/`Hide`, with
  no dependency on any CDM controller code — so a standalone instantiation behaves identically to
  Blizzard's. Toggle purely with `Show()` / `Hide()`.
- Anchoring, from Blizzard's own source: **icon `-6/+6`** around TBT's icon frame; **bar `-9/+10`**
  around the bar's fill sub-region **plus** an explicit `SetFrameLevel(bar:GetFrameLevel() + 1)`.
  Omitting that frame-level bump misorders the border behind the bar fill — the same way it would
  in Blizzard's own UI if the override were skipped.
- **Wrap template instantiation in `pcall`** and degrade to "no highlight" on failure. No mechanism
  was found to introspect virtual-template existence ahead of time, and this is the established
  defensive idiom in this codebase. Realistic risk is low — both flavours load
  `Blizzard_CooldownViewer` unconditionally — but the guard costs nothing.
- Pool TBT's own instances with `CreateFramePool` in the same idiom TBT already uses. Note
  `CreateFramePool` is globally rebound to `CreateSecureFramePool`, so the objects are
  secure-pool-managed; that is fine, they are not CDM frames.

### The five unknowns — answered in game, not guessed

`PANDEMIC.md` lists five unknowns. The user's decision is to ship the implementation and resolve
them in game, so this phase must **add a `/tbt debug` dump** that answers them rather than leaving
them open:

1. Does `PandemicIcon` clear promptly at window end, or linger past `pandemicEndTime` because
   Blizzard's `OnUpdate` deregisters once `pandemicAlertTriggerTime` is nil'd?
2. Are `pandemicStartTime` / `pandemicEndTime` actually secret for a tainted reader in combat?
   Dump `issecretvalue(...)` and `type(...)` for both, in and out of combat.
3. Does `CanTriggerAlertType(PandemicTime)` gate on spell capability, or on a player-configured
   alert preference? If the latter, this feature needs a check nobody anticipated.
4. Does Forever's build actually produce a positive `carriedOverToNewCast` for anything TBT would
   mirror — i.e. does the mechanic fire in practice, not merely exist in shipped code?
5. Does the read stay reliable for a target-debuff entry (the target-aura path at
   `MergeMode.lua:876-878`), not just a self-buff?

Unknown 1 is the one that decides whether the numeric refinement is load-bearing. If it turns out
to be, PANDEMIC.md says that is a separate phase, not a re-scope of this one.

### Claude's Discretion

- Whether the stamped field is one tri-state or two fields. Prefer one boolean plus the guarded
  numbers only where they are readable.
- Exact debug output format — follow `Core.lua`'s existing `/tbt debug` log style.
- Whether the bar highlight reuses the icon pool or gets its own. Two templates, so likely two.

</decisions>

<code_context>
## Existing Code Insights

### Reusable assets

- **`CollectShownCooldownIDs`** (`MergeMode.lua:478-500`) — the admitted `EnumerateActive` walk.
  Already caches `ns.mergeItemFrames[cooldownID] = itemFrame` at `:497`. **This is why no new CDM
  surface is needed.**
- **`ns:RefreshMergeShownSlots`** (`MergeMode.lua:694-806`) — the per-entry stamping pass. Stamps
  `entry.cdmShown` at `:786`, and `hideAura` / `hasCharges` / `selfAura` / `auraExpiry` are stamped
  at mirror-build time (`:363-376`). The pandemic stamp is their sibling.
- **The `pcall` precedent at `:793-799`** — `pcall(ResolveMergedAuraTiming, entry)`, wrapped as a
  *structural* guarantee rather than against a specific expected raise, because this pass wipes the
  shown-slot arrays before refilling and any raise partway through leaves every merged container
  empty. Its comment cites the real `GetAuraDataByIndex` raise of 2026-09-22. **Anything added to
  this pass inherits that hazard** — a raise here empties the player's containers.
- **`issecretvalue`-then-`type` guarding of CDM structure fields** — worked example at
  `MergeMode.lua:650-656` for `aura.expirationTime` / `aura.duration`.
- **`Display.lua`** — TBT's mirrored icon and bar widgets, where the highlight frames get parented.

### Established patterns

- `issecretvalue()` before `type()`, always, and before any truthiness test.
- One code path for both flavours; no runtime flavour check. Forever ships the identical pandemic
  code — verified line-for-line against `BigWigsMods/WoWUI` branch `forever-beta`, same function and
  field names, ~7-line offset — and `Blizzard_CooldownViewer` loads under
  `## AllowLoadGameType: standard, camelot`, so no flavour gate is needed for instantiation.
- Reusable module-level tables wiped with `wipe()`; no per-frame allocation in hot paths.
- `stylua` bare from repo root; `.gitattributes` pins `*.lua` to `eol=crlf`.

### Carry-over from Phases 46 and 47

Both are **code complete but NOT verified in game** — their gates have not been run. Phase 48 is
independent of both: it touches `MergeMode.lua` and `Display.lua`'s merged-entry render path, not
the item catalogue or item trackers. That independence is real and worth preserving — do not couple
this phase's work to item tracking.

**One lesson from Phase 47 worth applying here:** its blocker was a correctly-wired chain fed by a
table that nothing populated outside a narrow condition. Reading forwards from the entry point
looked perfectly sound. When verifying this phase, trace **backwards** from the rendered highlight
to `ns.mergeItemFrames` and ask what guarantees that table is populated at the moment the stamp is
read — specifically, whether `CollectShownCooldownIDs` has necessarily run.

</code_context>

<specifics>
## Specific Ideas

- `.planning/research/PANDEMIC.md` is **required reading before planning** — 357 lines, with
  `file:line` citations into the local retail snapshot for every claim about how Blizzard computes
  and renders the window.
- **Item-backed merged entries need zero handling.** Blizzard's `CheckSetPandemicAlertTriggerTime`
  short-circuits on `IsItem()` before anything else runs, so trinkets, potions and healthstones
  structurally never carry a pandemic window. TBT's existing `equipSlot` / `spellCategoryID` entries
  simply never see the signal — no filtering needed on TBT's side.
- Blizzard's own hide of `PandemicIcon` can lag the true end of the window. If TBT mirrors the
  boolean literally it inherits that lag — which is arguably correct, since "carry the CDM's
  indicator over" means showing what Blizzard is showing.
- Forever presence is HIGH confidence; Forever *behaving observably the same* is MEDIUM, because
  Forever's in-combat aura secrecy was already measured (999.6) to be more aggressive than retail's
  for direct addon reads.

</specifics>

<deferred>
## Deferred Ideas

- **Pandemic windows for TBT's own native trackers.** Explicitly out of scope per the backlog item.
  Separate and simpler — TBT owns those durations and no secrecy is involved.
- **Recomputing the window from aura data.** Closed by the platform: `expirationTime` and `duration`
  are secret, and both APIs that would redo Blizzard's math key off `auraInstanceID`, flagged
  `DisallowTaintedAccess`.
- **Reading pandemic state via CDM mixin methods.** Locked constraint — measured to taint the frame
  permanently.
- **A second phase for the numeric fallback.** Only if the in-game spike shows unknown 1 or 2 makes
  that path genuinely load-bearing rather than a refinement. PANDEMIC.md is explicit that this would
  be an inserted follow-up phase, not a re-scope of this one.

</deferred>
