# Phase 40: CDM Steal Mode - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning
**Mode:** Decisions taken with the user up front, before the autonomous run

<domain>
## Phase Boundary

Optionally, TBT becomes the whole display surface: Blizzard's CDM containers hide, and their contents
are mirrored into TBT's four base containers beside the user's own trackers.

In scope: the hide/restore of Blizzard's viewers, reading what the player configured, and rendering
mirrored items as TBT items.
Out of scope: the toggle itself (Phase 35.1), and any change to how the player *configures* the CDM —
that stays in Blizzard's UI.
</domain>

<decisions>
## Implementation Decisions

### The model: the CDM stays the config surface
The user's framing: *"when in steal mode, the user still moves and configs the blizzard cdm directly,
but the new skills configured show in our containers, and we can use the new cdm API to just copy those
skills and show alongside ours."*

So mirrored items are a **read-only mirror**:
- They cannot be reordered, moved between containers, or deleted from within TBT.
- The CDM remains the single source of truth. The player adds and removes spells there.
- `STEAL-05` follows directly: a change in the CDM shows up in TBT without a `/reload`.
- Rejected: reorderable-within-container (needs an ordering override that survives CDM changes) and
  fully-manageable (TBT would have to reconcile its own state against the CDM's on every change).

### All-or-nothing
One toggle, not four. No per-category steal control exists anywhere. Off on a fresh database.

### Hiding Blizzard's containers — `:Hide()`, with the risk acknowledged
- **Plain `:Hide()` on the viewer frames**, by user decision, over driving Blizzard's Edit Mode
  visibility setting.
- Hiding a whole frame is a far lighter touch than the per-item manipulation that tainted in every
  injection variant — but two risks were flagged and accepted:
  1. Blizzard's own layout code may re-show them, so the hide likely needs re-asserting on the events
     that rebuild the viewers.
  2. `:Hide()` on a protected frame is blocked in combat. Gate on `InCombatLockdown()` and defer.
- `STEAL-07` requires restoring **exactly the visibility each viewer had before**, so capture that state
  when steal mode is switched on, not when it is switched off.

### The hard constraint — never touch a CDM frame otherwise
Measured 2026-09-20, and this is what the whole milestone's architecture rests on: five injection
variants — including one using zero Blizzard Lua, C-level `GetChildren()` and deferred writes only —
**all** tainted the CDM with `CooldownViewerItemData.lua:782 hasTotem` errors. Calling any Blizzard CDM
mixin method leaves the frame tainted afterwards, and **the taint is sticky**: it survives leaving
combat and clears only on `/reload`. A combat guard is preventive, never curative.

Therefore TBT must never:
- parent a frame into a Blizzard CDM frame,
- write a field on one,
- call a CDM mixin method,
- call `C_CooldownViewer.SetLayoutData` (it would overwrite the player's live configuration).

`STEAL-08`'s verification is both behavioural and a diff read, for exactly this reason.

### Reading the data
- `C_CooldownViewer.GetCooldownViewerCategorySet` gives the configured slot list per category — this is
  how the injection prototype computed insertion position, and it is readable.
- A CDM item frame's `.auraDataCached` is a readable table whose inner fields are secret but **pipeable**
  — they can be handed to widget setters without being read. All nine widget sinks (`SetText`,
  `SetValue`, `SetTexture`, `SetStatusBarColor`, …) accepted genuinely secret values in combat.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Display.lua`'s bar and icon creation, styling and layout — mirrored items are rendered as TBT items,
  so they go through the same widgets and the same per-container settings.
- `BAR_PADDING_OFFSET = -2` and `ICON_PADDING_OFFSET = -4` already match Blizzard's
  `GetAdditionalPaddingOffset()` exactly; no layout maths needs rediscovering.

### Established Patterns
- Capability checks, not client-identity checks. The CDM APIs may be absent or shaped differently on
  Forever; guard on the symbol existing so a missing one is a silent no-op.
- `issecretvalue()` before any comparison or concatenation.

### Integration Points
- Blizzard's viewers rebuild on their own events; whatever hides them must survive that.
- `.planning/research/TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md` holds the full measured findings,
  including the five injection variants and the exact taint errors.
</code_context>

<specifics>
## Specific Ideas

"we can however 'steal' blizzard buffs and cooldowns and track them in our containers, so we can fully
do what we want with them, and with the new api we can just get whatever the player sets for the
blizzard cdm to show, and show on our containers alongside custom stuff."
</specifics>

<deferred>
## Deferred Ideas

- Per-category steal toggles — explicitly out of scope.
- Letting TBT edit the CDM's configuration — never; `SetLayoutData` is banned.
</deferred>
