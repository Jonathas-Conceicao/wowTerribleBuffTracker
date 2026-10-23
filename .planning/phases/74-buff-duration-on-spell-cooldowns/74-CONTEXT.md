# Phase 74: Buff Duration on Spell Cooldowns - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning
**Mode:** Context front-loaded for the autonomous run (73-77); decisions from the v0.5.3 kickoff and
the batched questions answered by the user on 2026-10-22

<domain>
## Phase Boundary

A user spell cooldown tracker (`userCd`) can carry its buff: an Advanced-tab checkbox (off by default),
an Aura ID and a Duration, all typed by the user. With the buff on, casting the spell starts a buff
timer of the typed duration alongside the cooldown. Requirements BUFFCD-01, 02, 03, 04, 08.

The **look** of the buff on the icon (yellow swipe, grey rules) is Phase 75. Bag items are Phase 76.
In this phase the buff timer only needs to exist and be drawn by whatever the current render path
draws for a live timer on that slot.

</domain>

<decisions>
## Implementation Decisions

### Dialog (CDMTab.lua `TRACKER_FIELDS`)
- **Advanced tab**, userCd only in this phase (Phase 76 extends it to bag items): a "Track buff
  duration" checkbox, an "Aura ID" box and a "Duration" box.
- **Checkbox off by default** on new trackers and on every existing one.
- **While the checkbox is off, Aura ID and Duration are shown greyed out** (visible, values kept,
  not editable) — user decision 2026-10-22. They become editable when it is ticked. This needs a
  disabled/greyed state for tracker fields, which the field contract does not have today (fields are
  only shown or hidden). Build it as a reusable capability of the field contract, because Phase 76
  needs the same greyed state for the item's non-buff fields.
- **Aura ID pre-fill:** follows the Spell ID until the user types in it — reuse
  `BuildFollowSpellIDField` (the same behaviour the buff `auraID` and reminder `castID` fields use).
- **Duration** starts empty. No automatic lookup: the 2026-10-22 probe found no API that returns a
  buff's duration (`.planning/research/BUFF-DURATION-PROBE.md`). Do **not** pre-fill it from
  `ns:SuggestedBuffDuration` either — the user chose explicit typed config.
- **Save rule:** with the checkbox on, the dialog refuses to save until the Aura ID and a positive
  Duration are both filled (same validation style as other fields). With it off, save succeeds and
  whatever the two boxes hold is kept but has no effect.
- The existing userCd `auraID` field stays hidden for cooldowns (schema v10 removed it). The buff
  fields are **new**, separate keys.

### Saved data
- New entry keys of their own (naming at planner's discretion, e.g. `buffEnabled`, `buffAuraID`,
  `buffDuration`). Never reuse `auraID` or `duration` — `duration` is the cooldown's typed duration.
- **Missing keys mean off** — every existing tracker loads with the buff off and nothing else
  changed. Prefer **no schema bump**; bump to v13 (with the `scripts/migrate-dryrun.js` mirror and a
  `--selftest` case) only if a real migration is needed.
- New keys must not be in `ENGINE_OWNED` so add/edit persist them automatically
  (BuffEngine.lua:1117-1135); confirm `ns:UpdateTrackedBuff` carries them.

### Timer behaviour
- With the buff on, **the cast that starts the cooldown also starts the buff timer**
  (`ns:StartCooldownFromCast` / the userCd branch in Providers.lua ~182-192, 278-286). Same moment,
  same hidden-section and load rules as the cooldown.
- The cooldown keeps running separately and unchanged (`ns.cooldownStarts`, `ApplyUserCooldown`).
- **A recast restarts the buff timer**, as user buff trackers refresh on cast.
- **Early end:** the buff timer ends when its aura is read as gone, under the same readable-only
  rule as user buff trackers (`aliveBuffs` / `ns:CancelsOnAuraLoss` / `ns:ReadPlayerAura`). Never on
  a secret read. All aura reads go through `ns:ReadPlayerAura` — `scripts/aura-read-gate.js` must
  keep passing (`node scripts/aura-read-gate.js` and `--selftest`).
- The buff is drawn **only on the cooldown's own icon**, never as a separate tile or bar.
  `RenderIconContainer`'s live-timer branch already sits above the cooldown branch
  (Display.lua ~1634-1672), so a timer filed under the cooldown key draws there; the planner decides
  the cleanest keying so the buff never appears elsewhere (Buffs containers, bars).

### Preview (Edit Mode and the CDM settings window)
- **User decision 2026-10-22:** a cooldown tracker with its buff on previews in the **buff look**
  with its typed duration. In this phase it is enough that the preview runs the buff timer; Phase 75
  gives it the yellow look.

### Claude's Discretion
- Exact key names, field ids, label text ("Track buff duration" is the user's wording), plan split.
- How the greyed field state is represented in the field contract.

</decisions>

<code_context>
## Existing Code Insights (code map, 2026-10-22)

- `ns.KIND` Core.lua:496-504; userCd entries created by `ns:AddTrackedBuff` (BuffEngine.lua:1213-1228);
  schema `CURRENT_SCHEMA_VERSION = 12` (BuffEngine.lua:78); migrations mirrored in
  `scripts/migrate-dryrun.js`.
- userCd: start stamped by `ns:StartCooldownFromCast` (Providers.lua:182-192, called :286); duration
  `ns:CooldownDuration` returns `entry.duration` (Core.lua:731-733); drawn by `ApplyCooldownSlot` /
  `ApplyUserCooldown` (Display.lua:1062-1191). A userCd never enters `ns.activeTimers` today
  (Providers.lua:278-279).
- User buff timers: `ns:FillUserBuffProc` (Providers.lua:97-156); cancellation list from
  `ns:DetailedAuraID` (BuffEngine.lua:868-873) gated by `ns:CancelsOnAuraLoss` (:877-882);
  `ns:RefreshAuraStates` (BuffEngine.lua:1783+).
- Timers merge in `ns:GetActiveTimers()` (BuffEngine.lua:935-984; preview timers lose to real ones).
- Dialog: one shared `TRACKER_FIELDS` list (CDMTab.lua:1837-2357), field contract at :1740-1830
  (`id, entryKey, tab, available, build, reset, prefill, update, read, validate, visible`). A field
  hidden by its own `visible()` is neither read nor written (:2733-2746). The only greyed control in
  the file is the New Container dialog's `barsCheck:Disable()` + grey label (:2955-2956).
- `ns:IsEditableTracker` (BuffEngine.lua:1036-1042) — userBuff/userCd/userReminder.

</code_context>

<specifics>
## Specific Ideas

- Follow Blizzard templates for any new control (memory: tabs via TabSystemTemplate, checkboxes and
  boxes as the dialog already builds them) — no custom widgets.
- Hot path rule: nothing new allocated per tick; stamp/dirty-check anything the render reads.
- In-game checks deferred to Phase 78 (retail only).

</specifics>

<deferred>
## Deferred Ideas

- Yellow aura look → Phase 75. Bag items → Phase 76.

</deferred>
