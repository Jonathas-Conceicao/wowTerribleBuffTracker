# Phase 55: ID Preview, Suggested Cooldown & Secrecy - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Mode:** Autonomous smart discuss — every decision below was taken with the user in one up-front batch

<domain>
## Phase Boundary

The add/edit dialog (one dialog, two modes, built from Phase 54's shared field definition) previews
the spell being entered, suggests the game's cooldown, and surfaces aura secrecy — on the dialog, on
TBT's tooltips and on the global TOOL-01 ID tooltip. Applies to simple tracking; Phases 56-57 reuse
the same preview and badge for the detailed-mode aura ID.

Requirements: ADD-04, ADD-05, SECR-01, SECR-02, SECR-03.

</domain>

<decisions>
## Implementation Decisions

### Live preview (ADD-04)
- A preview row under the spell ID box, added as a field in the shared definition: spell icon and
  name, updating on `OnTextChanged`.
- Hovering the row shows the game's own tooltip via `GameTooltip:SetSpellByID` (which also fires
  the TOOL-01 ID line and, after this phase, the secrecy line).
- Unknown ID: `C_Spell.GetSpellInfo(id) == nil` → "Unknown spell" with the 134400 icon. (The icon
  alone cannot distinguish unknown from a real question-mark icon; decide on `GetSpellInfo`.)
- Every read guarded `issecretvalue()`-first per the project rule.

### Suggested cooldown (ADD-05)
- There is **no documented base-cooldown API** (scout, 2026-09-28). Fallback chain:
  1. legacy global `GetSpellBaseCooldown(id)` (milliseconds) — existence-checked, `pcall`,
     `issecretvalue`/`type` guarded; used only when it returns a positive number;
  2. `C_Spell.GetSpellCharges(id).cooldownDuration` for charge spells, when readable
     (`SecretWhenCooldownsRestricted`, so guarded);
  3. otherwise no suggestion.
- The suggestion fills the duration field only while the field is empty **or still holds the
  previous suggestion** — anything the user typed is never overwritten. The typed value is what is
  saved.
- Applies to cooldown trackers (Cooldowns tab). TBT's cooldown display still runs on the typed
  duration (the 2026-09-22 CD-02 decision stands); the suggestion is only a starting value.

### Secrecy display (SECR-01, SECR-02)
- Level from `C_Secrets.GetSpellAuraSecrecy(spellID)` → `Enum.SecrecyLevel`:
  `NeverSecret` 0 "Never secret", `AlwaysSecret` 1 "Always secret", `ContextuallySecret` 2
  "Contextual". Pass plain numbers only (`SecretArguments = "AllowedWhenUntainted"`).
- **Capability-checked**, not flavour-checked: when `C_Secrets.GetSpellAuraSecrecy` or
  `Enum.SecrecyLevel` is absent, the line and badge are silently omitted with no Lua error. (Forever
  has the API — recorded Eureka! = 2 in `TEST-PLAN-CDM-INJECTION-AND-COOLDOWNS.md:511` — but the
  guard stays.)
- SECR-02: add an "Aura secrecy: ..." line to the TOOL-01 post-call (Core.lua:1206-1281), right after
  the spell/aura ID line (:1243), in the same colour family. Because TBT tile tooltips go through
  `SetSpellByID`, they get the line through the same code (SECR-01) — do not print it twice. The
  unresolved-ID branch of `ns:ShowBuffTooltip` (Display.lua:272-276) and the dialog preview need
  their own line since TOOL-01 does not fire there.

### "Secret?" badge (SECR-03) — user decision on scope
- Shown on **both tabs** (buff and cooldown trackers), driven by **aura secrecy** on both. The user's
  reasoning, to keep: secrecy matters for cooldowns too — a never-secret skill, or one not secret in a
  given context, is one TBT might later read cooldown info for from the API, and skills like
  Shadowmeld have cooldowns TBT cannot currently get right. The suggestion is the only place TBT uses
  game cooldown data for now.
- Visible when the level is above `NeverSecret` (1 or 2). Hovering it shows a tooltip explaining the
  level: e.g. Contextual — "this spell's aura can be hidden from addons in combat, M+ and other
  restricted content; aura-driven behaviour may only update out of combat"; Always secret — "addons
  can never read this aura". Wording is Claude's discretion; keep it short and in the user's terms.
- Art: atlas `transmog-icon-warning-small`, with a plain "(secret?)" text fallback if the atlas does
  not resolve (it is referenced on classic branches, which does not prove it ships on Forever —
  check in game).

### Claude's Discretion
- Exact layout of the preview row and badge (keep inside the existing 240 px dialog, height from the
  running `y` cursor), tooltip wording, colours.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- TOOL-01 post-call (Core.lua:1206-1281): filters `Enum.TooltipDataType.Spell` + aura types,
  `issecretvalue(id)` early return (:1240), `RelatedID` helper (:1254-1270) as a guarded-call model.
- `ns:ShowBuffTooltip(frame, proc, opts)` (Display.lua:253-290): resolves via `GetSpellInfo`, calls
  `SetSpellByID`, `opts.showSpellID` / `showDuration` / `extraLines`.
- Name helpers: `SpellName` (Core.lua:1335, pcall + `SafeString`), MergeMode's cached
  `C_Spell.GetSpellName` (MergeMode.lua:582-592). Icon: `ns:GetSpellIcon` (BuffEngine.lua:310-319,
  no secret guard).
- Debug-only `ReadCastCooldown` (Core.lua:1507-1534) — `SafeNumber` guard idiom for cooldown reads.
- `ApplyChargeCount` (Display.lua:1213-1237) — guarded `GetSpellCharges` read to copy.

### Established Patterns
- `issecretvalue()` before any comparison; `type()` alone passes for secret numbers.
- Capability checks, not client-identity checks; the one sanctioned flavour check is the rank
  checkbox (`ns.CLIENT_HAS_SPELL_RANKS`).
- Tooltips: `GameTooltip_SetDefaultAnchor` + `AddLine`.

### Integration Points
- The shared field definition from Phase 54 (preview row, badge, suggestion hook on the ID box's
  `OnTextChanged`).
- CDMTab tile OnEnter (CDMTab.lua:262-338) → `ShowBuffTooltip` with `showSpellID`.

</code_context>

<specifics>
## Specific Ideas

- The user framed the suggestion as "a new feature we're adding" — only a starting value, never a
  live override of the typed duration.

</specifics>

<deferred>
## Deferred Ideas

- Reading real cooldown info from the API for never-secret / not-currently-secret skills (e.g.
  Shadowmeld's buff-end cooldown, backlog 999.10) — the user's stated reason secrecy matters for
  cooldowns; not built in this phase.

</deferred>
