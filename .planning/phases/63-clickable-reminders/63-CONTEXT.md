# Phase 63: Clickable Reminders - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning
**Mode:** Autonomous run 61-63; every question for the range was asked up front on 2026-09-30 and
answered by the user (three decisions below marked **user decision**). The rest is the settled
backlog 999.18 design plus the user's kickoff additions.

<domain>
## Phase Boundary

Out of combat, clicking a shown reminder icon casts that reminder's cast spell on the player
(CLICK-01..06). Covers: the secure click overlays, their placement/visibility lifecycle, the
per-container on/off option, the per-reminder cast-spell setting, and the built-in reminders' cast
spells. Not in scope: retail class-buff suggestions (Phase 64), any in-combat clicking, right/
modifier clicks.

</domain>

<decisions>
## Implementation Decisions

### Where the option lives — **user decision 2026-09-30: per container**
- A **"Click to Cast"** checkbox in the Edit Mode settings popup of **every reminders container**
  (the base Buff Reminders container and every user-added reminders container), next to
  "Show Tooltips" (`EditModeFrames.lua` `AddCheckbox`, ~500-525). Not shown on buff/bar/cooldown
  containers.
- **On by default**: stored as a container setting; a nil value means on (same style as
  `showTooltips ~= false`), so no migration and no schema step.
- Its tooltip states plainly that clicks work **out of combat only** (secure buttons cannot change
  in combat). Short wording, no content-type names (the user trims tooltip text; keep it one line or
  two).

### Who a click casts on — **user decision 2026-09-30: always the player**
- Attributes: `type1 = "spell"`, `unit1 = "player"` (or `unit = "player"`), `spell = <cast spell>`.
  A reminder tracks the player's own missing buff, so a friendly target never receives it.
- REQUIREMENTS.md's Out of Scope line was updated to match.

### Which rank — **user decision 2026-09-30: highest known**
- The `spell` attribute is the cast spell's **name** (resolved from the cast spell ID with
  `C_Spell.GetSpellInfo`, out of combat), so the game casts the highest rank the player knows. On
  retail this is equally correct (one rank; base/override resolves by name).
- If the name cannot be resolved (unknown ID, nil info), the reminder has **no click action**.

### Cast spell setting (CLICK-06)
- A new **Advanced** field on reminders, "Cast spell" (spell ID), in `TRACKER_FIELDS` (`CDMTab.lua`)
  so add and edit get it from the one definition (EDIT-03). Shown for reminder kinds only.
- **Stored nil at its default** (the General/Advanced rule from v0.5.0: advanced values are nil at
  their defaults; "not read means not written"). Default = the reminder's own spell ID.
- Reminders are buffs: the field follows the same field rules as every other reminder field; the
  live ID preview used by other ID fields may be reused if cheap, not required.
- **Built-ins (metaReminder):** not user-editable (MREM-01). Their cast spell comes from
  `META_REMINDER_DEFS` (`Providers.lua` ~1540): every row casts its own `spellID`, **except Blood
  Pact (11767), which has no cast spell and therefore no click action** (user decision at
  requirements, 2026-09-30). Add a field to the row/def (e.g. `castID`, `false` for Blood Pact)
  rather than special-casing the ID in code.

### Secure overlay — the settled 999.18 design (binding)
- **One overlay per shown reminder icon**, `CreateFrame("Button", nil, UIParent,
  "SecureActionButtonTemplate")`, pooled and reused. Parented to `UIParent`, **never anchored** to
  the icon, its container or any TBT frame — an anchor from a protected frame would make TBT's
  display tree protected, and every later `SetPoint`/`Show` on it would error in combat.
- **Screen-coordinate placement:** read the plain icon's `GetRect()` (scaled to UIParent's effective
  scale), then `SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)` and `SetSize`; copy
  strata, frame level + 1. **Dirty-checked on the rect** — no work when nothing moved.
- **When to place:** initial login (deferred one frame so rects are calculated), when Edit Mode
  closes, and whenever the set of shown reminder icons or their layout changes **out of combat**
  (container relayout, a reminder appearing/being satisfied, container settings change). Never
  per frame; hook the existing layout/refresh points.
- **Clicks only where an icon is shown (CLICK-04, user addition):** an overlay exists (is shown)
  only for a reminder icon that is currently drawn. Empty container, all reminders unloaded, or all
  satisfied → no shown overlay, nothing clickable. Hidden container (visibility setting) → none.
- **Combat:** `RegisterStateDriver(overlay, "visibility", "[combat] hide; show")` so the game's
  secure code hides overlays in combat without TBT touching them. Every function that changes
  attributes, position, size, `EnableMouse` or visibility returns early on `InCombatLockdown()` and
  marks itself dirty; `PLAYER_REGEN_ENABLED` applies whatever was deferred.
  - Note the interaction: the state driver owns shown/hidden; to take an overlay out of service out
    of combat (icon no longer drawn, option off, Edit Mode), unregister/re-register the driver or
    park it (e.g. `UnregisterStateDriver` + `Hide`) — the plan must choose one consistent way and
    keep it combat-safe.
- **Edit Mode:** overlays are taken out of service when `EditMode.Enter` fires (mouse off or
  hidden) so they never swallow a container drag, and re-placed on `EditMode.Exit`. Uses
  `EventRegistry` callbacks as `EditModeFrames.lua` ~946 does. **Must not touch
  `EditModeManagerFrame`** (Phase 61 removed TBT's only such call).
- **Tooltip (CLICK-05):** the overlay sits on top of the icon and receives the mouse, so its own
  `OnEnter`/`OnLeave` show the reminder's tooltip through the shared `ns:ShowBuffTooltip`
  (`Display.lua` ~280), respecting the container's Show Tooltips setting. Setting scripts on a TBT-
  created secure button out of combat is fine; do it once at creation.
- **Hover affordance:** give the overlay the standard square button highlight
  (`Interface\Buttons\ButtonHilight-Square`, ADD blend) as its own highlight texture, so a
  clickable reminder visibly reacts to hover. Owned by the overlay; nothing drawn on TBT frames.
- **No taint:** no TBT display frame becomes protected; no Blizzard mixin method is called; no
  `ADDON_ACTION_BLOCKED`. Aura reads are unchanged (DTRK-06: `node scripts/aura-read-gate.js`
  must still pass).

### Claude's Discretion
- File placement: a new small module (e.g. `ReminderClick.lua`, added to the TOC load list) vs
  inside `Display.lua`. A new file must be added to `TerribleBuffTracker.toc` — and a TOC change
  needs a **full client restart** to test.
- Pool size / keying (by icon frame vs tracker key).
- How the known-spell check for the cast spell is done (reuse the load rule's "When known" helper
  if it fits).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:ShowBuffTooltip(frame, proc, opts)` — `Display.lua` ~280.
- `ns.editModeActive` (`EditModeFrames.lua:3`); `EventRegistry` `EditMode.Enter`/`EditMode.Exit`
  callbacks at `EditModeFrames.lua` ~946 and `MergeMode.lua` ~2394.
- Reminder display gate: `Display.lua` ~86 (REM-03), ~2302-2330 (reminder keeps container shown),
  ~2539 (reminder placeholder drawing). `ns:IsReminderEntry` / `ns.REMINDER_KINDS`.
- `TRACKER_FIELDS` in `CDMTab.lua` (~1635 onward) — the one field definition for add + edit;
  `auraID` / `keepOnAuraLoss` / `endOnCast` / `alternatives` are the Advanced fields.
- `META_REMINDER_DEFS`, `MetaReminderRow`, `ns:ApplyMetaReminderDef` — `Providers.lua` ~1540-1600.
- Container settings popup `AddCheckbox(labelText, settingKey)` — `EditModeFrames.lua` ~432.

### Established Patterns
- Per-frame paths use pooled tables and dirty checks; no per-frame allocation.
- `InCombatLockdown()` gates + `PLAYER_REGEN_ENABLED` flush already exist for other deferred work
  (grep `PLAYER_REGEN_ENABLED` in `Core.lua`).
- File-local upvalue order trap: a local called from a function declared above it is nil at
  runtime — put cross-file helpers on `ns`.

### Integration Points
- Reminder icon layout/refresh in `Display.lua`; Edit Mode enter/exit; `PLAYER_REGEN_ENABLED`;
  login (`PLAYER_ENTERING_WORLD` deferred one frame).

</code_context>

<specifics>
## Specific Ideas

- Example the user gave (retail Mage, used in Phase 64): the "Arcane Familiar" reminder is gated on
  talent 205022, checks aura 210126, and **casts 1459 (Arcane Intellect)** — the cast-spell field
  exists for exactly this. Phase 64 adds that row; this phase only needs the field to support it.
- In-game checks are deferred to Phase 66 (Forever first, then retail). Deploy with
  `./scripts/install.bat`.

</specifics>

<deferred>
## Deferred Ideas

- Retail class-buff reminder rows — Phase 64.
- In-combat clicking, right/modifier clicks, targeted casts — out of scope by design.

</deferred>
