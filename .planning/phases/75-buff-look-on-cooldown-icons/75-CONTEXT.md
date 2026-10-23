# Phase 75: Buff Look on Cooldown Icons - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning
**Mode:** Context front-loaded for the autonomous run (73-77)

<domain>
## Phase Boundary

A cooldown tracker's icon shows its running buff the way Blizzard's CDM shows a cooldown entry's
aura, then the cooldown once the buff is gone. Requirements BUFFDISP-01..05. Applies to every cooldown
slot that can carry a buff (userCd now; bag items reuse it in Phase 76).

</domain>

<decisions>
## Implementation Decisions

### The three states (user's words, kickoff 2026-10-22)
- **Normal:** no cooldown, no buff → full colour, no sweep.
- **Yellow (buff running):** "a yellowish fill of the icon that is cleared by the sweep effect" —
  the swipe starts as a full yellow fill and clears back to normal colours. Icon **not** desaturated,
  **no edge**, and the cooldown is **not** shown during the buff.
- **White-ish → grey (cooldown running):** "sweep starts white and clears to gray, what we already
  have for cd" — keep TBT's existing cooldown look exactly. Icon grey.
- An icon is grey **only** while a cooldown shows and no buff does.
- When the buff ends (expires or is cancelled) and the cooldown still runs, the cooldown look
  appears **at once** — the buff and the cooldown are tracked separately.

### Ground truth: Blizzard's CDM (wow-ui-source, `Blizzard_CooldownViewer/CooldownViewer.lua`)
- `CooldownViewerConstants.ITEM_AURA_COLOR = CreateColor(1, 0.95, 0.57, 0.7)` (line 20);
  `ITEM_COOLDOWN_COLOR = CreateColor(0, 0, 0, 0.7)` (line 21).
- Aura state (`CheckCacheCooldownValuesFromAura`, ~858-905): swipe colour `ITEM_AURA_COLOR`,
  `cooldownShowDrawEdge = false`, `cooldownShowSwipe = true`, `cooldownUseAuraDisplayTime = true`,
  `cooldownDesaturated = false`.
- Applied in `RefreshSpellCooldownInfo` (~1138-1152): `SetSwipeColor`, `SetDrawSwipe`,
  `SetUseAuraDisplayTime`, `CooldownFrame_Set(... start, duration, enabled, showDrawEdge, modRate)`.
- The essential/utility cooldown item's `Cooldown` child in `CooldownViewer.xml` (~48) is **not**
  `reverse`; the buff-icon viewer's Cooldown (~183) is `reverse="true"` and its swipe colour is
  `ITEM_COOLDOWN_COLOR` (`CooldownViewerBuffIconItemMixin:GetCooldownSwipeColor`, ~1406).
- TBT's icons use `SetReverse(true)` and a single black 0.7 swipe today (Display.lua `CreateTimerIcon`
  ~538-566). The planner must decide the reverse/colour combination per state from the CDM source so
  the buff state **starts full yellow and clears**, while the cooldown state keeps today's look.
  Read the CDM source before choosing; do not guess the reverse semantics.

### Scope limits
- **BUFFDISP-05:** Buffs-tab and Reminders-tab icons and the Trinket/Pot meta-trackers keep their
  current look (dark swipe) — matching the CDM, whose buff viewer uses the dark swipe and reserves
  yellow for cooldown entries.
- **BUFFDISP-04:** the charge count (`ApplyChargeCount`) and item count (`ApplyItemCount`) stay
  visible while the buff runs. Note the live-timer branch in `RenderIconContainer` currently does not
  run the cooldown slot's count logic — the planner must make sure the count survives the buff.
- **Preview** (Edit Mode, CDM settings window): a cooldown tracker with its buff on previews in the
  yellow buff look with its typed duration (user decision 2026-10-22).
- Container "Show Timer" (`settings.timerShown` → `SetDrawSwipe`) keeps applying to both states.
- Merge Mode is untouched (merged slots are Blizzard's own frames).

### Hot path
- `RenderIconContainer` runs per tick: swipe colour / reverse / edge / desaturation changes must be
  stamped (dirty-checked) per icon like the existing `_userCdState` / `_userCdGrey` stamps, and the
  stamps must reset when a pooled icon switches tracker (`ClearCooldownStamps`).

### Claude's Discretion
- Function structure; whether the state switch lives in `ApplyCooldownSlot` or a new helper.

</decisions>

<code_context>
## Existing Code Insights

- Display.lua: `CreateTimerIcon` (~538-566), `ApplyIconStyle` (~690-694), `ClearCooldownStamps`
  (~858-865), `ApplyCooldownGrey` (~875-908), `ApplyCooldownHandle` (~944-973), `ApplyChargeCount`
  (~994-1018), `ApplyUserCooldown` (~1062-1112), `ApplyCooldownSlot` (~1114-1191),
  `RenderIconContainer` (~1494; live-timer branch ~1634-1663, cooldown branch ~1664).

</code_context>

<specifics>
## Specific Ideas

- Pixel-match Blizzard's CooldownViewer templates (CLAUDE.md "Patterns").
- In-game checks deferred to Phase 78 (retail only).

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
