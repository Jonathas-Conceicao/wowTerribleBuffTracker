# Phase 56: Detailed Tracking — Mode & Aura Rules - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Mode:** Autonomous smart discuss — decisions taken with the user in one up-front batch covering Phases 56 and 57

<domain>
## Phase Boundary

User-defined trackers gain a **detailed tracking** mode in the add/edit dialog. This phase delivers
the mode switch, the separate aura ID, the aura-loss cancellation opt-out, the "unreadable aura is
never absent" guarantee, and the ADD-06 portrait preview redesign. Visibility modes and cross-spell
rules are Phase 57, which builds on this phase's fields and helpers.

Requirements: DTRK-01, DTRK-02, DTRK-04, DTRK-06, ADD-06.

</domain>

<decisions>
## Implementation Decisions

### Mode switch (DTRK-01)
- A **"Detailed tracking"** checkbox field in TRACKER_FIELDS, on BOTH tabs (by user decision,
  cooldown trackers get detailed mode too — see scope below). Unchecked (simple) is the default, and
  simple behaves exactly as v0.4.1 / Phase 55.
- Checking it shows the detailed child fields through the existing `visible` hook plus Layout();
  unchecking hides them. Per the Phase 54 WR-02 rule ("not read means not written"), hidden children
  keep their saved values. **The runtime must gate on `entry.detailed`, never on whether child keys
  exist**, so a tracker switched back to simple behaves exactly as simple even with stale child keys
  saved.
- Child fields capture `dialog.GetFieldState("detailed")` in `build`, since `visible` only receives
  `(state, ctx)`. The master checkbox must come before its children in TRACKER_FIELDS.
- Copy coverAllRanks' inline CheckButton. `AddExclusiveCheck` is declared below CreateAddDialog and
  is nil inside field definitions.

### Scope per tracker kind (user decision)
- **Buffs tab (userBuff), detailed:** aura ID, "End when the aura is lost" (this phase); visibility
  mode and "Ends when you cast" (Phase 57).
- **Cooldowns tab (userCd), detailed:** "Reset when you cast" and an **aura ID used only for
  visibility** (show-when-present/absent) — both land in Phase 57. For this phase the Cooldowns tab
  gets the Detailed checkbox. If no cooldown child field exists yet, the checkbox may be buff-only
  until Phase 57 adds cooldown children; Claude's discretion, but whatever ships must not show an
  empty detailed section.
- Aura-loss cancellation and DTRK-06 do not apply to cooldowns (a cooldown has no aura behind it and
  never enters ns.activeTimers).

### Aura ID (DTRK-02)
- A second ID box, "Aura ID" with the hint "blank = same as spell". It has its own small icon + name
  preview and a "secret?" badge driven by the AURA ID's secrecy, reusing the Phase 55 helpers
  (`ns:SpellPreview`, `ns:SpellAuraSecrecy`, `ns:SecrecyWarns`, `ns:SecrecyExplanation`). Saved as
  `entry.auraID` (nil when blank or equal to the spell ID).
- Runtime (buff): at Providers.lua `UserSpellProviderMixin:OnTrigger` (~line 176) the aura ID must
  take priority over the rank family, because `ns.rankFamilies` holds CAST IDs, not the aura:
  `entry.detailed and entry.auraID` → `ns:AcquireAliveBuffs(ownerKey, entry.auraID)`, else the
  current rank-family / spellID logic. Same pattern as StartRacialProc's `def.auraID or def.spellID`
  (Providers.lua ~1863).
- This fixes the suspected v0.4.1 bug where a user buff whose aura ID differs from its cast ID is
  cancelled at the first out-of-combat aura event.

### Cancellation opt-out (DTRK-04)
- A checkbox, "End when the aura is lost", **default ON** (the lesson from the removed racial
  `cancelOnAuraLoss` opt-in). Saved only when OFF, e.g. `entry.keepOnAuraLoss = true`; field name is
  Claude's discretion, but a missing key must mean "cancellation on".
- Runtime: when opted out, leave `proc.aliveBuffs` nil. The scan already skips such procs
  (BuffEngine.lua ~1225), and AcquireProc clears stale fields. If Phase 57's visibility needs the
  aura ID while cancellation is off, it reads `entry.auraID` separately, not `aliveBuffs`.

### Unreadable aura is never absent (DTRK-06)
- Already the engine rule. `ns:ReadPlayerAura` returns present / absent / unreadable (gated on
  `C_Secrets.ShouldSpellAuraBeSecret`), and `ScanActiveTimersForCancellation` abandons a proc's check
  on any unreadable read. The PLAYER_REGEN_ENABLED rescan catches drops that happened in combat.
- **Keep the predicate gate.** MergeMode.lua's "over-conservative" comment (~526-537) is superseded
  in the same file (~614-625): live testing showed the gate is right. Do not switch
  ReadPlayerAura to a direct read.
- This phase must verify that the aura-ID path goes through the same reader and inherits the rule,
  and add a static proof (grep/awk gate) that no new aura read bypasses ReadPlayerAura.

### Portrait preview (ADD-06), design settled with the user
- A centered 50px icon at the top of the dialog, under the title and above the Spell ID box. It
  uses the CDM icon styling TBT's trackers use (mask + border). The spell name is centered beneath
  it; "Unknown spell" plus the question-mark icon when the spell doesn't resolve. The "secret?" badge
  sits on the icon's top-right corner, and hover shows the game tooltip plus the secrecy line. It
  replaces Phase 55's 18px preview row. 50px on both tabs (CDM essential size at 100% scale; TBT
  matches the CDM: essential 50, buff 40, utility 30, bar icon 30). The mockup is in ROADMAP.md,
  Phase 56 section.
- **Implementation:** keep the portrait a TRACKER_FIELDS entry, moved to the FRONT of the list,
  resolving the Spell ID box through `GetFieldState` at UPDATE time (not build time), so
  `CreateAddDialog` stays byte-identical. Update the "Order is load-bearing" contract comment. The
  Phase 55 badge moves onto the portrait. Reuse Display.lua's icon styling (whatever TBT's buff icon
  frame applies: mask texture / border atlas), not a new art path.

### Claude's Discretion
- Field names on the entry (`detailed`, `auraID`, the opt-out key), exact labels and hints,
  small-preview layout for the aura ID row, and whether the Cooldowns tab shows the Detailed
  checkbox before Phase 57 gives it children.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- TRACKER_FIELDS contract (CDMTab.lua ~1229-1287): build/reset/prefill/update/read/validate/
  available/visible; `GetFieldState` returns only fields built earlier; Layout() stacks shown rows
  and resizes; RefreshState runs updates, then visibility, then relayout only if something changed;
  hidden fields are skipped by validate, Tab and read.
- Phase 55 helpers in Core.lua (above TOOL-01): ns:SpellAuraSecrecy, ns:SecrecyLine,
  ns:SecrecyExplanation, ns:SecrecyWarns, ns:SecrecyScopeNote, ns:SuggestedCooldown, ns:SpellPreview.
- `ns:AcquireAliveBuffs(key, id)` pooled one-element list (BuffEngine.lua ~604-614).
- AddTrackedBuff copies every field key not in ENGINE_OWNED, and UpdateTrackedBuff writes only the
  read fieldKeys, so new entry keys persist with no engine change.

### Established Patterns
- The racial `auraID` precedent (StartRacialProc). Cancellation is default-on.
- Aura reads are gated, and one unreadable read aborts a proc's check.
- Line endings, stylua CRCRLF trap, and upvalue-order trap: see CLAUDE.md and memory.

### Integration Points
- Providers.lua UserSpellProviderMixin:OnTrigger (the aliveBuffs assignment).
- CDMTab.lua TRACKER_FIELDS (new fields and the portrait move).
- Display.lua icon styling, to reuse for the portrait.

</code_context>

<specifics>
## Specific Ideas

- The portrait mockup is in ROADMAP.md, Phase 56 section. The user reviewed the Phase 55 dialog in
  game ("it was looking nice") and asked for the icon on top and bigger.

</specifics>

<deferred>
## Deferred Ideas

- Visibility modes, cross-spell end/reset rules, and the cooldown aura-ID-for-visibility: Phase 57.
- Using the CDM's own aura state for spells also in the CDM (in-combat reads): backlog 999.16.

</deferred>
