# Phase 23: CDMTab.lua Unification - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate CDMTab.lua to consume `ns:GetDisplayInfoForKey` for all icon/tooltip resolution. Remove META_DESCRIPTIONS branch and 3 parallel resolution chains. Extend `ns:ShowBuffTooltip` with an opts param so CDMTab's extra tooltip content (Spell ID line, Duration line, description text) can flow through the shared handler. Replace SUGGESTED_BUFFS with a simple key list. Fold in the lust constants demotion (phase_hint: 23 todo).

**In scope:**
- CDMTab.lua: replace 3 `type(x) == "string"` resolution chains with inline `ns:GetDisplayInfoForKey(key)` calls
- CDMTab.lua: tile tooltip uses extended `ns:ShowBuffTooltip(frame, proc, opts)` with opts from CDMTab
- CDMTab.lua: META_DESCRIPTIONS promoted from tooltip-local to file-local, remains CDMTab-local
- Display.lua: extend `ns:ShowBuffTooltip` signature to `(frame, proc, opts)` with opts.showSpellID / opts.showDuration / opts.extraLines
- BuffEngine.lua: replace `ns.SUGGESTED_BUFFS` with `ns.SUGGESTED_KEYS = {"lust","trinket","pot"}`; delete getCDMSpellID + getCDMIcon closures + metaBuff flag
- Providers.lua: demote `ns.CLASS_LUST_SPELL` + `ns.GetHunterLustSpell` to module-local (folded todo)

**Out of scope (phase boundary):**
- Shim removal: `ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo` stay until Phase 24 (may have remaining non-CDMTab callers to audit)
- Phase 24 cleanup todos: Fury of the Aspects cancellation bug, M+ Lua errors from secret values — both carry phase_hint: 24
- `ns:RefreshMetaIcons` rename — Phase 24
- SUGGESTED_BUFFS references in other files (grep first — some may just be unused after closure deletion)

</domain>

<decisions>
## Implementation Decisions

### Tooltip Handler Extension (Area 1)

- **D-01:** Extend `ns:ShowBuffTooltip(frame, proc, opts)` — opts is optional table. Display passes nil; CDMTab passes opts.
- **D-02:** opts shape:
  ```lua
  {
      showSpellID = <bool>,   -- add "Spell ID: N" line (CDMTab only)
      showDuration = <bool>,  -- add "TBT Duration: Xs" line (CDMTab only)
      extraLines = { <str>... },  -- additional gray lines at the bottom
  }
  ```
- **D-03:** Display bar/icon OnEnter calls remain `ns:ShowBuffTooltip(self, self.proc)` (opts = nil, unchanged behavior).
- **D-04:** CDMTab tile OnEnter calls `ns:ShowBuffTooltip(self, info, opts)` with opts populated from CDMTab locals.
- **D-05:** `ns:ShowBuffTooltip` handles opts nil case as "just show spell tooltip" (current behavior).

### META_DESCRIPTIONS Location (Area 2)

- **D-06:** META_DESCRIPTIONS stays in CDMTab.lua — promoted from inside OnEnter closure to file-level local. Same values: trinket/pot/lust description strings.
- **D-07:** CDMTab reads `META_DESCRIPTIONS[key]` and passes as `opts.extraLines = { descriptionText }` to `ns:ShowBuffTooltip`. Users without a meta-description (future non-meta keys if any) get no extra line.
- **D-08:** Not moved to provider — it's genuinely CDM-settings UX text, not provider concern.

### SUGGESTED_BUFFS Replacement (Area 3)

- **D-09:** Delete `ns.SUGGESTED_BUFFS` table entirely from BuffEngine.lua.
- **D-10:** Replace with `ns.SUGGESTED_KEYS = { "lust", "trinket", "pot" }` — ordered list of meta-buff keys.
- **D-11:** All per-entry data (label, duration, getCDMSpellID, getCDMIcon, metaBuff flag) is redundant — provider already returns these via `ns:GetDisplayInfoForKey`.
- **D-12:** CDMTab.lua changes:
  - Line 105 (tooltip fallback suggested lookup): iterate SUGGESTED_KEYS instead of SUGGESTED_BUFFS to check membership; use `ns:GetDisplayInfoForKey` for label/duration.
  - Line 160: same pattern.
  - Line 549: same pattern.
  - Line 749 (section render): iterate SUGGESTED_KEYS; call `ns:GetDisplayInfoForKey(key)` for icon/label.
- **D-13:** `item.suggestedIndex` field on pooled items can stay (used for drag state tracking); just holds the index into SUGGESTED_KEYS instead of SUGGESTED_BUFFS. Equivalent.
- **D-14:** After the closure deletion, `ns.CLASS_LUST_SPELL` and `ns.GetHunterLustSpell` have NO remaining external readers (grep-verified before deletion). Both are demoted to Providers.lua module-local.

### Resolution Chain Collapse (Area 4)

- **D-15:** Three CDMTab sites that currently have `type(x) == "string"` + meta chain + fallback, all collapsed to inline `ns:GetDisplayInfoForKey(key)` call:
  - **Site 1 (tile tooltip, line 73-142):** Replace the entire isMetaString/metaInfo/ResolveSuggestedSpellID chain with single `local info = ns:GetDisplayInfoForKey(self.spellID)` call. Pass to extended ShowBuffTooltip with opts.
  - **Site 2 (drag ghost icon, line 431-442):** Replace with `local info = ns:GetDisplayInfoForKey(iconFrame.spellID); ghost.Icon:SetTexture(info and info.icon or 134400)`.
  - **Site 3 (section rebuild icon, line 787-797):** Replace with same pattern.
- **D-16:** No helper extracted — one-liner is concise enough. Inline at each site.
- **D-17:** `iconFrame.spellID` / `self.spellID` field naming stays for now (used by drag state tracking and existing frame conventions). CDMTab doesn't switch to `.key` in this phase — that's a broader rename outside Phase 23 scope.

### Folded Todo: Lust Constants Demotion

- **D-18:** `ns.CLASS_LUST_SPELL` → `CLASS_LUST_SPELL` (module-local in Providers.lua).
- **D-19:** `ns.GetHunterLustSpell` → `GetHunterLustSpell` (module-local in Providers.lua). Update LustProvider:GetDisplayInfo and related callers inside Providers.lua to read the local names.
- **D-20:** Verify pre-deletion: repo-wide `grep "ns\.CLASS_LUST_SPELL\|ns\.GetHunterLustSpell\|ns:GetHunterLustSpell"` returns 0 matches outside Providers.lua AFTER the SUGGESTED_BUFFS closure deletion.
- **D-21:** Move the pending todo file to done: `.planning/todos/pending/2026-04-21-demote-remaining-lust-constants-to-provider-local.md` → `.planning/todos/done/` after successful verification.

### Preservation

- **D-22:** Display.lua's bar/icon OnEnter calls unchanged (pass nil opts — Phase 22 behavior preserved).
- **D-23:** `ns:GetDisplayInfoForKey` API unchanged.
- **D-24:** All providers unchanged (no proc shape change, no method additions).
- **D-25:** `SATED_DEBUFF_TO_LUST` stays as-is (already provider-local).
- **D-26:** `SHARED_LUST_BUFFS_LOCAL` stays as-is (provider-local from Phase 22).
- **D-27:** CURRENT_SCHEMA_VERSION = 3.
- **D-28:** Core.lua UNTOUCHED.
- **D-29:** Drag/drop, section reorder, right-click menus, Add dialog — all unchanged structurally. Only the icon/tooltip resolution inside changes.

### Claude's Discretion

- Whether META_DESCRIPTIONS is a file-level local or stays inside the OnEnter closure (cosmetic)
- Whether to introduce a local alias in CDMTab like `local function getInfo(key) return ns:GetDisplayInfoForKey(key) end` to shorten call sites (probably not worth it)
- Ordering of tasks inside the plan — can do CDMTab + tooltip together or split
- Whether to update comment references to "SUGGESTED_BUFFS" in migration code / old comments (grep and update where accurate)

</decisions>

<canonical_refs>
## Canonical References

### Prior phase contexts
- `.planning/phases/22-display-lua-unification/22-CONTEXT.md` — ns:ShowBuffTooltip contract (D-18) being extended in Phase 23
- `.planning/phases/20-getpreviewinfo-dispatch-helper/20-CONTEXT.md` — ns:GetDisplayInfoForKey API
- `.planning/phases/19-lustprovider-unit-aura-dispatch/19-CONTEXT.md` — CLASS_LUST_SPELL + GetHunterLustSpell origin

### Pending todo to fold in
- `.planning/todos/pending/2026-04-21-demote-remaining-lust-constants-to-provider-local.md` — CLASS_LUST_SPELL + GetHunterLustSpell demotion (phase_hint: 23)

### Project docs
- `CLAUDE.md` — stylua after Lua edits
- `.planning/REQUIREMENTS.md` — DISP-02 (CDMTab uses GetDisplayInfoForKey; META_DESCRIPTIONS branch and parallel resolution chains removed)

### Code files
- `CDMTab.lua` — primary target (read FULLY)
- `BuffEngine.lua` — SUGGESTED_BUFFS definition (lines 57-101); delete closures; replace with SUGGESTED_KEYS
- `Providers.lua` — LustProvider internals that read CLASS_LUST_SPELL/GetHunterLustSpell need local references after demotion
- `Display.lua` — extend ns:ShowBuffTooltip signature only; don't rewrite bar/icon OnEnter

</canonical_refs>

<code_context>
## Existing Code Insights

### 3 CDMTab resolution chain sites
- Line 73-142 (tile OnEnter tooltip): META_DESCRIPTIONS local + GetAtRestMetaInfo + ResolveSuggestedSpellID + entry/suggested lookup + description
- Line 431-442 (drag ghost icon): GetAtRestMetaIcon + ResolveSuggestedSpellID + GetSpellIcon
- Line 787-797 (section rebuild): GetAtRestMetaIcon + ResolveSuggestedSpellID + GetSpellIcon

### 4 CDMTab SUGGESTED_BUFFS readers
- Line 105 — tooltip fallback lookup (if entry absent, look in catalog)
- Line 160 — another tooltip lookup
- Line 549 — drag-related lookup
- Line 749 — main section rendering loop (builds 3 tiles)

### 3 BuffEngine SUGGESTED_BUFFS entries (lines 57-101)
- lust entry — has `getCDMSpellID` closure that reads ns.CLASS_LUST_SPELL and ns.GetHunterLustSpell
- trinket entry — has `getCDMIcon` closure calling ns:GetAtRestMetaIcon
- pot entry — same pattern as trinket

### Expected behavior (no user-visible change)
- Suggested section still shows 3 tiles (lust + trinket + pot) in same order
- Icons resolve the same — equipped trinket icon, first-bag pot icon, class-aware lust icon
- Tooltips show the same content — spell name + ID + duration + description
- Drag behavior unchanged — ghost icon matches tile icon
- Tile right-click menu unchanged

### Scope files after Phase 23
- **CDMTab.lua** — 3 resolution chains collapsed; META_DESCRIPTIONS promoted to file-level; SUGGESTED_BUFFS reads → SUGGESTED_KEYS + GetDisplayInfoForKey
- **BuffEngine.lua** — SUGGESTED_BUFFS → SUGGESTED_KEYS; closure deletions (~40 lines removed)
- **Providers.lua** — CLASS_LUST_SPELL / GetHunterLustSpell demoted; LustProvider internal reads updated
- **Display.lua** — ShowBuffTooltip signature extended; bar/icon call sites pass nil opts (unchanged behavior)

</code_context>

<specifics>
## Specific Ideas

- User wants SUGGESTED_BUFFS reduced to **simple key list** — description text stays CDMTab-local (META_DESCRIPTIONS), dynamic info (icon/label/duration/spellID) comes from `ns:GetDisplayInfoForKey`. User quote: "if we keep a simple list, which also looks good to me, where the info like extra description/tooltip text comes from?" — confirmed the file-local META_DESCRIPTIONS flow.
- Tooltip extension via opts param is explicit user choice — they want ONE handler (DISP-03 compliance) while preserving CDMTab's richer content.
- Folded todo (lust constants demotion, phase_hint: 23) — unblocked by SUGGESTED_BUFFS closure deletion. Grep-verify zero external readers before demotion.
- Three Phase 24 todos remain unfolded: Fury of the Aspects bug, M+ secret-value errors — out of Phase 23 scope.

</specifics>

<deferred>
## Deferred Ideas

- **Shim removal** (`ns:ResolveSuggestedSpellID`, `ns:GetAtRestMetaIcon`, `ns:GetAtRestMetaInfo`) — Phase 24 (DISP-04). May have remaining callers after Phase 23 (the shim internals are fine; the ns.* exports may still be called from legacy code paths — audit in Phase 24).
- **Fury of the Aspects cancellation bug** — Phase 24 todo file present. User still investigating.
- **M+ Lua errors from secret values during lust** — Phase 24 todo file present. User investigating.
- **`ns:RefreshMetaIcons` rename** — Phase 24 cosmetic.
- **`iconFrame.spellID` → `iconFrame.key` rename** — broader CDMTab naming concern, defer.
- **SUGGESTED_KEYS → provider self-registration** — bigger architectural change, defer indefinitely.

</deferred>

---

*Phase: 23-cdmtab-lua-unification*
*Context gathered: 2026-04-22*
