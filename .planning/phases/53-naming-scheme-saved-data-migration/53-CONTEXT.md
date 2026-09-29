# Phase 53: Naming Scheme & Saved-Data Migration - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Mode:** Autonomous smart discuss — every decision below was taken with the user in one up-front batch

<domain>
## Phase Boundary

One canonical naming scheme for tracker kinds, applied in code AND in saved data: every
`ns.db.trackedBuffs` entry carries its canonical kind, and every saved key is re-keyed to a uniform
`<kind>:<id>` shape. A v0.4.1 database migrates on first load with every tracker's container, order
and settings intact. No user-visible behaviour changes except the chat prints that show keys.

Requirements: NAME-01, NAME-02.

</domain>

<decisions>
## Implementation Decisions

### Kind names (user decision)
- Six canonical kinds, camelCase, stored in one field on **every** entry (today meta buff entries
  have no `trackerType` at all):

  | Kind | What it covers today |
  |---|---|
  | `userBuff` | user-made buff (today: numeric spellID key, `trackerType` `"buff"` or nil) |
  | `userCd` | user-made cooldown (today: `cd:<spellID>`, `trackerType` `"cooldown"`) |
  | `metaSkill` | built-in skill, buff side: Lust (`lust`) and racial buffs (`racial:<spellID>`) |
  | `metaSkillCd` | built-in skill cooldown tiles: racial cooldowns (today plain `cd:<racialSpellID>`, indistinguishable from a user cooldown) |
  | `metaItem` | built-in items: `trinket`, `pot`, bag consumables (`item:<itemID>`) |
  | `userItem` | reserved — no producer yet |

- `userCd` (not `userCooldown`) was chosen by the user to match `metaSkillCd` in style.
- The field name is Claude's discretion (keep `trackerType`, or rename to `kind`); pick whichever
  keeps the diff and the read sites simplest, and use it consistently.

### Keys (user decision)
- **Uniform keys: `<kind>:<id>`**, so every key is standardised:
  `userBuff:<spellID>`, `userCd:<spellID>`, `metaSkill:lust`, `metaSkill:<racialSpellID>`,
  `metaSkillCd:<racialSpellID>`, `metaItem:trinket`, `metaItem:pot`, `metaItem:<itemID>`.
  Exact spelling of the meta ids is Claude's discretion as long as it is `<kind>:<id>`.
- **User's explicit condition: tooltip and icon resolution must not break.** Every place that treats
  a key as a spell ID must go through a parser instead — known sites: the CDMTab tile fallback
  `ns:GetSpellIcon(key)` (CDMTab.lua:1070-1071), `UserSpellProviderMixin:GetDisplayInfo`'s
  `type(key)=="number"` branch (Providers.lua:183-193), `GetDisplayInfoForKey`'s dispatch order
  (Providers.lua:2154-2190), the CDMTab tooltip path, and the rank index `directKey` checks.
- **Hot path must not regress.** The cast path today does `tracked[spellID]` directly. Do not add a
  per-cast string concat: resolve casts through a spellID → key index rebuilt at the same moments as
  `ns:RebuildRankIndex` (add/remove/migration), so the cast path stays one table lookup. The existing
  `ns.COOLDOWN_KEY_PREFIX .. spellID` concat at Providers.lua:106 should move to the same index.

### Migration shape (default, accepted)
- New schema **v8**, a new block after `ns:MigrateRacialKeys` (v7).
- **Pin v7 first.** `MigrateRacialKeys` gates on and stamps `CURRENT_SCHEMA_VERSION`; bumping the
  constant to 8 would make a v7 DB re-run it and stamp 8 without the re-key. Change it to use a
  literal 7, per the chain's own "older blocks keep a literal" rule (BuffEngine.lua:204-208).
- v7 can be deferred when `UnitRace` is unreadable at ADDON_LOADED and re-run on
  PLAYER_ENTERING_WORLD (Core.lua:1020). The v8 re-key must run **after** v7 has completed, on the
  same trigger(s), or it re-keys `racial`/`racial2` legacy entries it cannot classify.
- **Move the record, never rebuild it** (the v6 precedent): collect keys first, then move each entry
  table to its new key, so `section`, `layoutOrder`, `coverAllRanks`, `iconOverride`, `duration`,
  `label` all survive. Rewrite the persisted `entry.key` copy too.
- Old migration blocks call live code (`ns:TrackerKey` in v6, `ns.RACIAL_KEY_PREFIX` in v7). Changing
  those helpers changes what old steps produce — freeze the legacy prefixes as file-local literals
  inside the old blocks, or make v8 accept both the old and new shapes.
- Classification of a `cd:<id>` entry as `metaSkillCd` vs `userCd`: it is `metaSkillCd` when `<id>`
  is a racial spellID in `RACIAL_SPELLS` (any race — do not gate on the current character's race).
- `scripts/migrate-dryrun.js` is updated to mirror v8.
- Verify with a real logout/login, never `/reload` (NAME-02). A second login must be a no-op.

### Parsers and constants (default, accepted)
- One kind table / constant set drives identifiers, key minting and parsing. The three hard-coded
  `^cd:(%d+)$`-style patterns are rebuilt from the constants, so a prefix can never drift from its
  parser.
- Provider mixin names follow the scheme where a mixin maps to a kind (Claude's discretion on exact
  names — e.g. `UserSpellProviderMixin` covers two kinds and may keep a descriptive name).

### Claude's Discretion
- Field name (`trackerType` vs `kind`), the exact meta-id spelling, provider mixin renames, and
  whether the runtime-only `cdm:` (MergeMode) and `__tbt_example__` keys are renamed (they are never
  saved; leave them unless it simplifies).
- The chat prints that show raw keys (BuffEngine.lua:576, 601, 612) should show something readable
  (label + spell ID) rather than the new long key.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ns:TrackerKey` (Core.lua:479-484), `ns:CooldownKeySpellID` (489-495), `ns:ItemKeyItemID`
  (515-521), `ns:RacialKeySpellID` (542-548) — the minting/parsing helpers to rebuild on the scheme.
- `ns:RebuildRankIndex` (Core.lua:813-880) — the rebuild moment and pattern for a new spellID→key
  index (`ns.rankIndex` / `ns.rankIndexCooldown` already map cast IDs to owner keys).
- v6 re-key block (BuffEngine.lua:185-210) — the collect-then-move pattern to copy.

### Established Patterns
- Schema chain: `if ver < N then ... ns.db.schemaVersion = N end` blocks in `ns:InitBuffEngine`
  (BuffEngine.lua:95-210); `CURRENT_SCHEMA_VERSION = 7` at BuffEngine.lua:81.
- Nothing outside `ns.db.trackedBuffs` is saved under a tracker key (containers, positions and
  settings are keyed by container), so the migration only touches that table.
- Keys doubling as IDs: numeric user-buff key = spellID (cast path `tracked[spellID]`,
  `proc.spellID = ownerKey`, Providers.lua:125-160); meta string keys hard-coded in
  `ns.SUGGESTED_KEYS` (BuffEngine.lua:68), `keyToProvider` (Providers.lua:2140-2144),
  `META_DESCRIPTIONS` (CDMTab.lua:11-15), provider reads (Providers.lua:400, 517, 690, 696), and
  `AddSuggestedTracker` (CDMTab.lua:150-200).
- `trackerType` read sites: Core.lua:106 (`GetTrackerCategory`), BuffEngine.lua:193, Providers.lua:146,
  1458, 1513, 1544; Display.lua:97, 999, 1647, 1994-1995, 2445. Only `"cooldown"` and `"item"` are
  ever tested; nothing branches on `"buff"`.
- `racialGateKeyIDs` (Providers.lua:988) memoises parsed keys; `IsRacialKeyVisible` also parses
  `cd:` keys to hide other races' racial cooldowns — must follow the new `metaSkillCd:` shape.
- Rank-index ties are broken by `tostring(key)` order; renaming can change which owner wins — keep
  the tie-break deterministic.

### Integration Points
- ADDON_LOADED → `ns:InitBuffEngine` (Core.lua:1003); PLAYER_ENTERING_WORLD →
  `ns:MigrateRacialKeys` (Core.lua:1020).
- `ns:GetDisplayInfoForKey` dispatch (Providers.lua:2154-2190) and `ns:IsSuggestedKeyResolvable`
  (2199) — the router every key passes through for icon/label.

</code_context>

<specifics>
## Specific Ideas

- The user asked for uniform keys "so it's standardised, since we already have these for some" —
  the `cd:` / `item:` / `racial:` prefixes are the precedent being generalised.
- "Be sure that we don't break tooltip and icon resolution with this" — treat every icon, label and
  tooltip path as a verification item, on both a user buff and a user cooldown and on every meta
  kind.

</specifics>

<deferred>
## Deferred Ideas

- `userItem` producer (custom item trackers) — reserved name only; backlog.

</deferred>
