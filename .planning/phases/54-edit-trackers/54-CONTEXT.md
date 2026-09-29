# Phase 54: Edit Trackers - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Mode:** Autonomous smart discuss — every decision below was taken with the user in one up-front batch

<domain>
## Phase Boundary

Any input of a user-defined tracker (`userBuff`, `userCd` — the kinds settled in Phase 53) can be
changed after creation, through an edit dialog that shares one field definition with the Add dialog.
Built on Phase 53's uniform `<kind>:<id>` keys.

Requirements: EDIT-01, EDIT-02, EDIT-03, EDIT-04.

</domain>

<decisions>
## Implementation Decisions

### Entry point
- A right-click **"Edit"** entry in the tracked tile's context menu (`MenuUtil.CreateContextMenu`,
  CDMTab.lua:368-386), placed just before the divider that precedes "Remove".
- Shown only for `userBuff` and `userCd` tiles. **Built-in kinds get no Edit entry — including
  racial cooldown tiles (`metaSkillCd`), by user decision:** their durations come from the racial
  table. Kind is read from the Phase 53 kind field, not inferred from key shape.

### One dialog, two modes
- The Add dialog (`CreateAddDialog`, CDMTab.lua:1154-1360, singleton `TBTAddBuffDialog`) is
  refactored so its field block is built from **one shared field definition** (EDIT-03). Add and Edit
  are the same frame in two modes: edit mode titles itself "Edit Buff Tracker" / "Edit Cooldown
  Tracker" and its confirm button reads **Save**. A field added to the definition appears in both
  modes with no second change — Phase 55 (preview, suggested cooldown, badge) and Phases 56-57
  (detailed tracking) will add fields through it, which is the proof.
- Edit mode opens **prefilled** from the entry: spell ID, duration, and "cover all ranks" on Forever
  (`ns.CLIENT_HAS_SPELL_RANKS`).
- Add the dialog in edit mode to `ns:DismissTBTDialogs` (CDMTab.lua:1989-1996) like the Add dialog.
- Styling copies the existing idiom (`CreateContainerDialog`, CDMTab.lua:1408-1553).

### Commit semantics (EDIT-04)
- Unchanged ID: update the entry's fields in place.
- Changed ID: **move the record** to the new `<kind>:<newID>` key, keeping `section` and
  `layoutOrder`; re-derive `label` from the new spell (no label field exists — out of scope);
  update `spellID`/`key`; clear all runtime state held for the old key — `ns.activeTimers`,
  `ns.previewTimers`, the proc/aliveBuffs/displayInfo pools (`ns:ReleaseProc`), and
  **`ns.cooldownStarts` / `ns.cooldownOverrides`** (which `ns:RemoveTrackedBuff` misses today);
  then `PreallocateProc(newKey)`, `RebuildRankIndex`, `MarkTrackersDirty`, `RefreshTBTSections`,
  `StartAllPreviewTimers`.
- One chat line ("Updated <label> ...") instead of a stop + start pair.
- **Duplicate rejection:** a new ID already tracked as the same kind is rejected with a message in
  the dialog's error label, and the tracker is left unchanged.
- **Found bug, fixed in this phase:** `ns:AddTrackedBuff` has no duplicate check and silently
  overwrites an existing tracker (resetting its section and order). Add gets the same rejection.
- `ns:RemoveTrackedBuff` also gains the missing `cooldownStarts` / `cooldownOverrides` clear, so a
  removed-then-re-added cooldown does not inherit a running cooldown.

### Combat
- No `InCombatLockdown` guard, matching the Add dialog today (none exists in CDMTab.lua).

### Claude's Discretion
- Whether the move is implemented as a dedicated `ns:UpdateTrackedBuff(oldKey, fields)` in
  BuffEngine.lua or composed from Add/Remove with the prints suppressed — prefer a dedicated
  function so the side-effect list lives in one place.
- Exact wording of the chat line and error messages.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ParseDuration`, `DURATION_UNITS`, `DURATION_HINT` (CDMTab.lua:1113-1152) — file-locals, reusable
  by the shared field builder.
- `RefreshAddState` validation (CDMTab.lua:1271-1283) and the Tab/Enter keyboard wiring
  (1325-1334).
- `AddExclusiveCheck` (CDMTab.lua:1363) — shared checkbox builder.
- `ns:AddTrackedBuff` (BuffEngine.lua:518-596) and `ns:RemoveTrackedBuff` (598-628) — the full
  side-effect lists to reuse or mirror.

### Established Patterns
- Dialog: `BackdropTemplate` frame, DIALOG strata, level 200, movable, in `UISpecialFrames`,
  `GameFontNormalLarge` title, `InputBoxTemplate` 180×22 boxes, `GameFontRed` error label, 80×22
  `UIPanelButtonTemplate` buttons at BOTTOMLEFT (16,12) / BOTTOMRIGHT (-16,12). Height from a
  running `y` cursor.
- Title and tracker type come from the active tab (`ns.tbtActiveCategory`); switching buff ↔ cooldown
  is out of scope.
- Tile key is `item.spellID` (CDMTab.lua:1067) — holds the tracker key, not necessarily a spell ID.
- Widget icon caches compare `spellID` and self-invalidate on an ID change (Display.lua:1043-1048,
  2399-2403); MergeMode holds no per-tracker-key tables.

### Integration Points
- Context menu builder in `CreateIconFrame` `OnMouseUp` (CDMTab.lua:340-390).
- `ns:BuildAllSections` builds the dialog singleton (CDMTab.lua:1645); the "+" square opens it
  (1666-1673).

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the above — match the existing Add dialog.

</specifics>

<deferred>
## Deferred Ideas

- Editing built-in trackers (Lust, trinket, pot, racials incl. racial cooldowns, bag items) — out of
  scope by requirement and by user decision.

</deferred>
