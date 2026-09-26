# Phase 42: Cleanup - Context

**Gathered:** 2026-09-22
**Status:** Ready for planning
**Mode:** Interactive discuss (three decisions taken up front, autonomous run)

<domain>
## Phase Boundary

The milestone's own duplication is unified and its hot paths audited.

**Phases 42 and 43 were swapped** by user decision on 2026-09-22: cleanup runs BEFORE the Forever
end-to-end pass, so the full review is run against the cleaned code rather than against code that is
about to be rewritten. That inverts the usual risk calculus for this phase — a regression introduced
here is caught by Phase 43, which has not happened yet, rather than slipping past a pass that has.
It does NOT license carelessness; it means the phase must leave the addon in a state worth testing.

There are **no automated tests**. Every guarantee this codebase has comes from the user's manual
play-testing on Forever. Anything changed here is unverified until Phase 43.

### Not in this phase

- No behaviour changes. Nothing a player can observe may differ, including timing, layout and text.
- No new features, no renames of persisted keys (`category = "spells"` stays; see STATE.md).
- `CHANGELOG.md` is not touched — `CLAUDE.md` forbids it outside an explicit request.
- No retail testing (locked: nothing before Phase 44).

</domain>

<decisions>
## Implementation Decisions

### D1 — Scope: everything this milestone created, including the two render functions

Asked whether to hold the conservative line (`PROJECT.md`'s "No refactors during cleanup phases")
or to include `RenderBarContainer`/`RenderIconContainer`, which share slot-building, the merged
append, `activeByKey` and the pooled-widget resets. The icon path was largely rewritten this
milestone; the bar path is mostly v0.3.0, so unifying them crosses that line.

**User decision:** *"comments, dead code, the two render you mentioned and anything else created in
this milestone, so everything :)"*

So the fence is: **anything this milestone created or rewrote is in scope, and the two render
functions are explicitly in scope despite the bar path predating v0.4.0.** This is an explicit,
recorded override of `PROJECT.md`'s no-refactor decision for these two functions only — it does not
generalise to the rest of the pre-v0.4.0 codebase.

The bar path is the less-tested of the two and the user's manual passes have concentrated on icons
and Merge Mode. Shared extractions must therefore be provably behaviour-preserving: extract what is
character-identical between the two, and leave anything that differs in its own function rather
than parameterising the difference away.

### D2 — Fix the placeholder-proc per-tick allocation

`.planning/todos/2026-09-21-placeholder-proc-table-allocates-per-tick.md`, hinted at this phase.
Both render functions build a fresh table for every *inactive* placeholder slot on every tick
whenever `hide when inactive` is off, in a 20 Hz loop, in combat. Pre-existing v0.3.0 behaviour;
Phase 36 made the container count unbounded, which is what makes it worth fixing now.

**User decision: fix it.** The todo's own solution sketch is approved: a per-widget owned table
(`bar._placeholderProc`) populated in place, rather than reusing `bar.proc` — because `bar.proc` is
*sometimes a borrowed reference to a live timer* and wiping it would wipe that timer. Every read of
`.proc` must be checked before committing (the `OnEnter` tooltip handler, D-19, is the known one).

Move the todo to `.planning/todos/done/` when it lands.

### D3 — Delete both untracked files

`.luarc.json` (a Lua Language Server config, editor-only, carrying the machine-specific absolute
path `C:/Users/jonat/Repositories/vscode-wow-api`) and `foo.md` (a draft addon announcement post,
whose content is already published — it links to the live CurseForge, Wago and GitHub pages).

**User decision: delete both.** Neither is needed by the project: the first affects only one
machine's editor, and the second duplicates copy that already exists publicly. Phase 45's DOC-03
writes store copy from the shipped README rather than from this draft.

### D4 — Comment accuracy is a first-class deliverable, not a tidy-up

This codebase's comments carry the *reasoning* behind non-obvious API constraints, and several are
now actively wrong after the 2026-09-22 play-testing pass. A wrong comment here is worse than no
comment, because the next reader will trust it and re-derive a limit that no longer exists. Known
liars to hunt down (not exhaustive — grep, do not trust this list):

- Claims that **a merged buff icon cannot have a sweep**. It can, and does; the long note above
  `RelayMergedBar` in `Display.lua` still says otherwise at length.
- References to **`ns:SetMergeAuraLayout`**, removed — `Display.lua`'s placed-merged-aura branch
  still names it.
- References to `/tbt aura` and `/tbt sweep`, both removed.
- References to a **slot-per-entry in one container per unit**; it is now one CONTAINER per entry
  per unit, and the reason is load-bearing (see D5).
- `ADD-01`/`ADD-02` control descriptions, and the `CD-02` "follows cooldown reduction live"
  rationale — all three reversed; `REQUIREMENTS.md` records them struck through.

### D5 — Three structures that must NOT be "simplified"

They look like redundancy and are not. Any cleanup that collapses one of these reintroduces a bug
the user already reported and signed off on:

1. **One aura container per merged entry per unit** (`MergeMode.lua`). An aura FRAME carries
   `DenyTaintedAccessWhenAurasAreSecret` and cannot be moved in combat; the CONTAINER carries no
   such restriction. TBT moves containers, never frames. Collapsing back to one container per unit
   breaks Centered growth outright.
2. **`ns:GridSlotPlacement` as the single source of grid arithmetic** (`Display.lua`), used by both
   Display and MergeMode. The two drifted three separate times when they each derived it.
3. **`entry.cdmShown`, stamped from Blizzard's own CDM item frames.** It looks like it duplicates an
   aura lookup. It does not — the aura APIs are secret in combat and the engine's own visible count
   is unreadable; the CDM's `IsShown()` is the one plain boolean available.

### D6 — Hot-path audit produces a written verdict, not just edits

The render path runs at 20 Hz with every container in it. The audit covers `ns:UpdateDisplay` and
everything it reaches, plus the Merge Mode event path, and records an explicit per-finding verdict:
removed, or justified in writing. Specific things known to be worth a look, from this milestone:

- `ns:PlaceMergeAura` — four separate stamp comparisons per merged entry per tick, deliberately not
  a packed string key. Confirm that is still true and say so.
- `ApplyUserCooldown` — runs every tick by necessity (nothing fires when a TBT-owned cooldown ends).
- `ns:GetContainerCategory(def)` called per container per tick from `RenderIconContainer`.
- The centred pre-pass, which walks `#slots` a second time before the layout loop.

</decisions>

<code_context>
## Existing Code Insights

8,873 lines of Lua across seven files. `CDMTab.lua` (2,083) and `MergeMode.lua` (1,678) are the
largest; `Display.lua` (1,671) holds both render functions and the grid arithmetic.

**Milestone-introduced duplication worth looking at** (candidates, to be confirmed during planning):

- The **mutually-exclusive checkbox-pair idiom** appears at least three times in `CDMTab.lua` —
  Icons/Bars, Buffs/Cooldowns, and formerly Buff/Cooldown in the add dialog. Twelve `SetChecked`
  call sites. The second pair was written by copying the first, with its comment saying so.
- **`ns.EnsureContainerSettings` defaults vs the Edit Mode settings popup's control list** —
  two independent statements of what a container setting is and what its range is.
- **Pooled-widget reset blocks** in `RenderIconContainer`, which appear three times with the same
  stamp-clearing body (`icon._cdKey`, `_cdGen`, `_stacks`, `_lastStart`, `_userCdState`,
  `_userCdGrey`, `_mergedExpiry`). This one grew during the play-testing pass and is the clearest
  milestone-introduced duplication in the file.
- `MergeMode.lua`'s filter-building loop, written twice (create path and re-filter path) inside
  `SyncEntryContainers`.

**Load-bearing ordering that must survive any reshuffle** (all recorded in STATE.md):

- `ns:RehydrateUserContainers()` sits between the db guards and the registry settings pass.
- Container deletion unregisters the def from `ns.CONTAINERS` *before* detaching the runtime.
- `ns:QueueMergeShownSlots` and `ns:QueueMergeMirror` defer through `C_Timer.After(0)` because they
  read state Blizzard is mid-computation on; making either inline is a coin flip.
- `ApplyUserCooldown` runs before the cooldown-generation block in `ApplyCooldownSlot`, which is
  what lets it see `icon._lastStart` before that block nils it.

</code_context>

<specifics>
## Specific Ideas

Success criteria, from ROADMAP Phase 42:

1. Duplication introduced by this milestone has one implementation each — container settings,
   tracker rendering and the add-panel surfaces are not copy-pasted per container type or per
   tracker type.
2. A hot-path audit of the render/tick path and the Merge Mode mirror records an explicit verdict,
   with any per-frame allocation or redundant work either removed or justified in writing.
3. Unused variables, dead functions and stale comments added since Phase 31 are gone, shown by a
   grep-gated sweep.
4. `stylua` runs clean from the repo root with no flags, `git diff` shows no line-ending-only churn,
   and `install.bat`, `release.bat` and `release.yml` have each been read end to end.

**Verification available to this phase:** `stylua` parses every file, so a syntax error cannot
survive it. Beyond that, the only check is reading. `./scripts/install.bat` deploys, but nothing
here can be exercised in game until Phase 43 — so every change must be justifiable by reading
alone, and anything that cannot be must not be made.

</specifics>

<deferred>
## Deferred Ideas

- **Renaming the `"spells"` category key to `"cooldowns"`** so code and UI share a vocabulary. It is
  persisted in `ns.db.userContainers`, so it needs a schema migration to buy nothing but a matching
  word. Deferred at the time the labels changed; still deferred.
- **The residual GCD grey** —
  `.planning/todos/2026-09-22-cooldown-icon-can-stay-grey-through-the-gcd.md`. Accepted by the user
  as not a defect, needs a reproduction first, and now reachable only on merged CDM slots.
- **Unifying anything pre-v0.4.0 beyond the two render functions.** `PROJECT.md`'s no-refactor
  decision still stands everywhere else.

</deferred>
