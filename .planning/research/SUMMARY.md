# Project Research Summary

**Project:** TerribleBuffTracker v0.2.0
**Domain:** WoW Midnight addon — CDM tab integration, Edit Mode movable elements, drag-and-drop buff management
**Researched:** 2026-03-28
**Confidence:** HIGH

## Executive Summary

TerribleBuffTracker v0.2.0 is a WoW addon UI milestone that replaces the existing standalone config window with a native-feeling tab inside Blizzard's Cooldown Manager (CDM) settings window, and adds independently movable containers to the Edit Mode system. All research was conducted directly from the Blizzard UI source at `wow-ui-source`, giving HIGH confidence in every integration pattern. The core approach is: inject a tab button into `CooldownViewerSettings.TabButtons` via an XML-defined parentArray frame, manage TBT's own content panel independently (never touching CDM's internal `displayModeToCategories`), and implement drag-and-drop between four buff sections using CDM's established `GLOBAL_MOUSE_UP` + cursor-ghost pattern.

Edit Mode integration is strictly limited to what third-party addons can actually do: CDM's `Enum.EditModeSystem` is Blizzard-internal and cannot be extended, so TBT must listen to `EventRegistry "EditMode.Enter"/"EditMode.Exit"` callbacks and show its own drag handles. The good news is that `Display.lua` already uses this exact EventRegistry pattern for `SnapshotSettings`, so the groundwork exists. The key risk is the existing CDM layout hooks in `Display.lua` — they must be guarded to not re-anchor containers once the user has set Edit Mode positions. Additionally, TBT must register its two movable elements (bars container, buffs container) in the Edit Mode sidebar dialog as toggleable checkboxes, which is the standard third-party pattern for appearing in the Edit Mode UI.

The biggest implementation risk is timing: CDM defers initialization until `COOLDOWN_VIEWER_DATA_LOADED` fires (after `PLAYER_ENTERING_WORLD`), so any CDM interaction that happens earlier will silently fail or crash. Migration must also run before any UI renders, and must use a `schemaVersion` sentinel to avoid overwriting user data.

## Key Findings

### Recommended Stack

All APIs are verified from Blizzard source at Interface 120000. The tab system uses `CooldownViewerSettingsTabTemplate` (inheriting `LargeSideTabButtonTemplate`) with `parentArray="TabButtons"` — this is an XML-only registration mechanism; runtime-created frames must be manually inserted into `CooldownViewerSettings.TabButtons`. CDM's content layout uses `GridLayoutFrame` with `ResizeLayoutFrame` wrappers for auto-sizing sections, and `CreateFramePool` for pooling buff icon frames. Drag-and-drop is entirely custom: a ghost frame at `TOOLTIP` strata parented to `GetAppropriateTopLevelParent()`, positioned each frame via `GetScaledCursorPositionForFrame`, terminated by `GLOBAL_MOUSE_UP`.

**Core technologies:**
- `CooldownViewerSettingsTabTemplate`: CDM tab injection — inherits `LargeSideTabButtonTemplate`, `parentArray="TabButtons"` registration, verified from XML source
- `EventRegistry` callbacks (`EditMode.Enter`, `EditMode.Exit`, `CooldownViewerSettings.OnShow/OnHide`): lifecycle hooks for both Edit Mode and CDM panel integration — already partially used in `Display.lua`
- `GridLayoutFrame` + `ResizeLayoutFrame`: auto-layout for sections in TBT's content panel — handles stride, padding, and height auto-sizing without manual `SetPoint` chaining
- `CreateFramePool`: buff icon pooling for drag-drop grid cells — CDM's own pattern for category items
- `GLOBAL_MOUSE_UP` + cursor ghost frame at `TOOLTIP` strata: drag termination and cursor tracking — mandatory pattern from CDM source; `OnMouseUp` alone is insufficient
- `MenuUtil.CreateContextMenu`: right-click context menus — replaces deprecated `UIDropDownMenu`, confirmed present in Midnight
- `hooksecurefunc(CooldownViewerSettings, "SetDisplayMode", ...)`: detecting tab-away to hide TBT panel — safe hook that avoids replacing Blizzard function

**Critical version notes:**
- All APIs target Interface 120000+
- `UIDropDownMenu` is deprecated/removed; use `MenuUtil.CreateContextMenu` only
- `EditModeSystemMixin` registration requires a valid `Enum.EditModeSystem` value (Blizzard-internal, not extensible)

### Expected Features

**Must have (table stakes, v0.2.0):**
- TBT tab button in CDM settings sidebar — the entire milestone is predicated on this; nothing else has a home without it
- 4 named sections (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) — core organizational structure matching CDM's own sectioning pattern
- Drag buff icons between sections — primary interaction model for reassigning display mode
- Edit Mode movable containers (bars container, buffs container independently draggable) — stated milestone requirement
- Edit Mode sidebar checkbox registration — both TBT elements must appear as toggleable items in the Edit Mode dialog sidebar, which is the table-stakes pattern for third-party addons integrating with Edit Mode; without this users have no standard way to show/hide TBT elements from the Edit Mode UI
- Position persistence for Edit Mode containers — Edit Mode is useless without `/reload` persistence
- Delete drop zone in Not Displayed section — required removal path in the new UI (no separate delete button in the CDM tab model)
- Add button in Suggested section (spell ID + duration prompt landing in Not Displayed) — required to add buffs in the new UI
- Migration: existing tracked buffs preserved with `schemaVersion` sentinel — must not break existing installs
- One-time CDM settings copy for fresh installs — stated milestone requirement

**Should have (v0.2.x, after validation):**
- Context menu (right-click) for section reassignment — ergonomic fast path for power users
- Reorder marker visual during drag — polish that makes drag feel native; functional without it
- Collapsible section headers — useful for long buff lists

**Defer (v0.3+):**
- Real spell suggestions in Suggested section — blocked on reliable Midnight spell ID data
- Import/export buff list — only valuable with large curated lists
- Per-spec buff configurations — scope expansion requiring spec-detection events

### Architecture Approach

The v0.2.0 milestone adds two new files (`CDMTab.lua` for CDM tab injection and section management, `EditModeFrames.lua` for movable container registration and position persistence), deletes `ConfigUI.lua` entirely, and modifies `Core.lua`, `BuffEngine.lua`, and `Display.lua` for data model expansion and new integration points. The fundamental separation is: `CDMTab.lua` owns everything inside the CDM settings window; `EditModeFrames.lua` owns container positioning; `Display.lua` owns rendering and uses the position source that `EditModeFrames.lua` provides. The containers must have stable global names (`"TBTBarContainer"`, `"TBTIconContainer"`) for Edit Mode anchor serialization to work correctly.

**Major components:**
1. `CDMTab.lua` (NEW): CDM tab button injection, 4-section content panel, drag-and-drop between sections, Add button, delete drop zone
2. `EditModeFrames.lua` (NEW): `EditMode.Enter/Exit` hooks, movable drag handles, position save/restore in `TerribleBuffTrackerDB.editModePositions`, Edit Mode sidebar checkbox registration for both containers
3. `BuffEngine.lua` (MODIFIED): adds `section` field, `schemaVersion` migration backfill, `SetBuffSection()` API, defaults new buffs to `section = "hidden"`
4. `Display.lua` (MODIFIED): uses `editModePositions` for container anchoring when set; guards CDM layout hooks to skip re-anchor when containers are in Edit Mode position
5. `ConfigUI.lua` (DELETED): replaced by CDMTab.lua; `/tbt` slash command redirected to open CDM settings to TBT tab

### Critical Pitfalls

1. **CDM initializes after `COOLDOWN_VIEWER_DATA_LOADED`, not at `PLAYER_ENTERING_WORLD`** — use `EventUtil.ContinueAfterAllEvents` mirroring CDM's own pattern; any earlier CDM access crashes or returns nil silently

2. **`SetDisplayMode` asserts on unknown display mode strings** — TBT must never call `CooldownViewerSettings:SetDisplayMode("tbt_buffs")` or any TBT-owned string; manage TBT's tab checked state and content panel visibility entirely independently; hook `SetDisplayMode` only to detect tab-away

3. **`parentArray="TabButtons"` is XML-only** — runtime `CreateFrame` calls do not auto-register into `CooldownViewerSettings.TabButtons`; define the tab in a TBT XML file with `parentArray="TabButtons"` so it is registered at XML load time like the built-in tabs, then call `SetCustomOnMouseUpHandler` after `SetupTabs` has run

4. **Existing CDM layout hooks in `Display.lua` will re-anchor containers after Edit Mode decouples them** — add a guard in every `HookViewerLayout` callback: if `editModePositions` is set for that container, skip the CDM re-anchor entirely

5. **Migration must use `schemaVersion` sentinel** — never wipe or reinitialise `TerribleBuffTrackerDB` during migration; backfill only missing fields; a failed migration has no automated recovery and loses user data permanently

6. **Drag cursor ghost frame must be at `TOOLTIP` strata parented to `GetAppropriateTopLevelParent()`** — any lower strata or parent inside the settings panel causes the cursor icon to clip or become invisible during drag

7. **`GLOBAL_MOUSE_UP` must be registered per drag session, not permanently** — permanent registration fires spurious drop completions on every mouse release anywhere in the UI

## Implications for Roadmap

Based on combined research, the recommended phase structure follows the dependency chain identified in ARCHITECTURE.md's build order. Each phase must be fully stable before the next begins.

### Phase 0: Data Migration and Schema Expansion

**Rationale:** The `section` field on `trackedBuffs` entries is a dependency for every subsequent phase — CDMTab.lua reads sections, EditModeFrames.lua writes positions, Display.lua uses section to drive rendering. Nothing can be tested without this foundation. Migration must happen first to avoid the highest-consequence pitfall (data loss).

**Delivers:** `schemaVersion` sentinel in `TerribleBuffTrackerDB`; `section` field backfilled on all existing entries; `SetBuffSection()` API on BuffEngine; `editModePositions` structure initialized; `AddTrackedBuff` defaulting new entries to `section = "hidden"`.

**Addresses:** Tracked Buffs preservation (migration), new buff section assignment (default behavior)

**Avoids:** PITFALLS.md Pitfall 8 (migration overwrites user data); Pitfall 3 (section field absent when CDM tab reads it)

**Files:** `BuffEngine.lua`, `Core.lua`

---

### Phase 1: Edit Mode Movable Containers

**Rationale:** Edit Mode integration is lower-risk than CDM tab injection (no Blizzard UI hooking), and it resolves the Display.lua anchor conflict (Pitfall 9) before CDM tab development begins. The containers need stable global names and UIParent parenting before any other feature touches them. Getting position persistence working independently validates the EventRegistry pattern that CDM tab also depends on.

**Delivers:** Two named, independently movable containers (`TBTBarContainer`, `TBTIconContainer`); `EditMode.Enter/Exit` hooks showing/hiding drag handles; position save/restore in `TerribleBuffTrackerDB.editModePositions`; Edit Mode sidebar checkbox registration for both containers (table-stakes Edit Mode feature); one-time CDM settings copy for fresh installs; Display.lua guarded against CDM layout hook re-anchor when Edit Mode positions are set.

**Addresses:** Edit Mode movable elements (table stakes), position persistence, Edit Mode sidebar checkboxes, one-time CDM settings copy

**Avoids:** PITFALLS.md Pitfall 4 (Edit Mode registration timing), Pitfall 5 (unnamed frame anchor serialization), Pitfall 9 (CDM layout hooks conflicting with Edit Mode)

**Files:** `EditModeFrames.lua` (new), `Display.lua`, `Core.lua`

---

### Phase 2: CDM Tab Shell and ConfigUI Removal

**Rationale:** Tab injection is the highest-risk integration step — it touches Blizzard's CDM frame directly. Isolating it as its own phase lets the tab button appear, switch correctly, and show/hide a placeholder content panel before any drag-drop complexity is added. ConfigUI.lua removal happens in this phase to prevent two competing config paths from coexisting.

**Delivers:** TBT tab button in CDM sidebar (XML-defined, `parentArray="TabButtons"`); TBT content panel frame (child of `CooldownViewerSettings`, sized to match scroll area); `hooksecurefunc` on `SetDisplayMode` to detect tab-away; CDM scroll frame hidden when TBT tab active, restored on deselect; `/tbt` slash command redirected to open CDM settings to TBT tab; `ConfigUI.lua` removed from project.

**Addresses:** CDM tab button (table stakes), ConfigUI replacement

**Avoids:** PITFALLS.md Pitfall 1 (CDM not ready at load time — gates injection behind `COOLDOWN_VIEWER_DATA_LOADED`), Pitfall 2 (tab not in `TabButtons` parentArray — XML approach), Pitfall 3 (`SetDisplayMode` assertion — TBT never calls it with TBT strings), Pitfall 10 (slash command and UISpecialFrames broken after ConfigUI removal)

**Files:** `CDMTab.lua` (new), `TerribleBuffTracker.xml` (new for tab XML definition), `Core.lua`, `ConfigUI.lua` (deleted), `TerribleBuffTracker.toc`

---

### Phase 3: CDM Tab Sections and Static Layout

**Rationale:** Build the 4-section content layout as static (no drag yet) to validate that data reads correctly from `trackedBuffs`, sections render from DB state, and the Add button creates entries. Drag complexity should only be added once the static layout is confirmed stable.

**Delivers:** 4 sections rendered in TBT content panel (Tracked Buffs, Tracked Bars, Not Displayed, Suggested) using `GridLayoutFrame` + `ResizeLayoutFrame`; buff icons populated from `TerribleBuffTrackerDB`; Add button in Suggested section with spell ID + duration `StaticPopup` dialog; items are displayed but not yet draggable.

**Addresses:** 4 named sections, Add button (table stakes)

**Files:** `CDMTab.lua`

---

### Phase 4: Drag-and-Drop Between Sections

**Rationale:** Most complex feature, depends on all sections being stable. Implementing last avoids debugging drag behavior against a moving layout target. This phase completes the primary interaction model.

**Delivers:** `RegisterForDrag("LeftButton")` on buff icon frames; cursor ghost frame (`TOOLTIP` strata, `GetAppropriateTopLevelParent()` parent, `GetScaledCursorPositionForFrame` in `OnUpdate`); `GLOBAL_MOUSE_UP` registration per drag session; section drop zones with `OnEnter/OnLeave` highlight; `EndBuffDrag` calling `SetBuffSection` then refreshing tab; delete drop zone in Not Displayed (visible only during active drag); cancel on right-click or drag outside.

**Addresses:** Drag between sections, delete drop zone (table stakes)

**Avoids:** PITFALLS.md Pitfall 6 (cursor strata), Pitfall 7 (`GLOBAL_MOUSE_UP` scope)

**Files:** `CDMTab.lua`

---

### Phase 5: Cleanup and Release Prep

**Rationale:** Per the GSD workflow in CLAUDE.md, every milestone ends with a cleanup phase. This is also when v0.2.x enhancements (context menu, reorder marker) can be deferred or added.

**Delivers:** Dead code removal; stylua run on all modified files; hot-path audit (no per-frame CDM reads, OnUpdate nil'd when not dragging); release script verification; changelog entry.

**Addresses:** GSD cleanup requirement

**Files:** All modified files

---

### Phase Ordering Rationale

- Data migration first because `section` field is a hard dependency for all UI phases; data loss from bad migration has no recovery path
- Edit Mode before CDM tab because it resolves the Display.lua anchor conflict (Pitfall 9) before CDM integration begins, and it uses the same EventRegistry pattern without Blizzard UI injection risk
- CDM tab shell before sections because tab injection is the highest-risk step; validating it in isolation reduces debugging surface
- Static sections before drag because drag debugging against a stable layout is dramatically simpler
- Cleanup last per GSD workflow convention

### Research Flags

Phases needing caution during implementation (verified patterns but complex execution):

- **Phase 1 (Edit Mode):** Edit Mode sidebar checkbox registration for third-party addons needs implementation-time verification against `wow-ui-source`; the pattern is known but the specific XML/Lua wiring for the sidebar checkbox entry is not fully documented in research
- **Phase 2 (CDM Tab Shell):** The XML approach for `parentArray="TabButtons"` is confirmed correct but has never been tested in TBT; timing of tab injection relative to CDM's `SetupTabs()` call needs careful verification on first test

Phases with well-documented patterns (can proceed with confidence):

- **Phase 0 (Migration):** Standard Lua table backfill; no Blizzard API involved; straightforward
- **Phase 3 (Static Sections):** `GridLayoutFrame` and `ResizeLayoutFrame` patterns are fully documented in research; static population from DB is low risk
- **Phase 4 (Drag):** CDM drag pattern is completely traced from source; TBT's simpler data model (section string vs. full `CooldownID` system) makes this easier than CDM's own implementation

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified directly from Blizzard UI source at Interface 120000; no inference required |
| Features | HIGH | Feature set derived from CDM source code and existing TBT codebase; milestone scope is well-defined |
| Architecture | HIGH | Build order, component split, and integration points all confirmed from source traces |
| Pitfalls | HIGH | Every pitfall is sourced from specific Blizzard source code behavior, not community inference |

**Overall confidence:** HIGH

### Gaps to Address

- **Edit Mode sidebar checkbox registration specifics:** Research confirms TBT elements should appear as toggleable checkboxes in the Edit Mode sidebar dialog (this is the standard third-party pattern), but the exact XML/Lua wiring for registering into that sidebar list was not fully traced in research. Needs verification against `EditModeManager.lua` and Edit Mode dialog XML before implementing Phase 1.

- **Atlas availability for TBT tab icon:** Research references `tbt_icon_64x64.blp` as the TBT addon icon, but CDM tab templates use specific atlas keys from the CDM atlas. Whether `tbt_icon_64x64.blp` can be used directly as a tab `activeAtlas`/`inactiveAtlas` value, or whether CDM atlas names must be used, needs implementation-time verification. Using an existing CDM atlas as a placeholder for the tab icon is a safe fallback.

- **`AurasTab` as anchor for TBT tab:** Architecture research uses `CooldownViewerSettings.AurasTab` as the reference frame for anchoring TBT's tab below the last existing tab. This should be verified against the current CDM XML to confirm `AurasTab` is the last tab defined, as adding TBT's tab below a non-last tab would misplace it in the sidebar.

## Sources

### Primary (HIGH confidence — Blizzard UI source)

- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.lua` — CDM tab system, `SetDisplayMode`, drag-and-drop implementation, `OnShow/OnHide` events
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_CooldownViewer\CooldownViewerSettings.xml` — Tab templates, item templates, category templates, `parentArray="TabButtons"` pattern
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeSystemTemplates.lua` — `EditModeSystemMixin`, `RegisterSystemFrame`, anchor serialization
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_EditMode\Shared\EditModeManager.lua` — `EnterEditMode`/`ExitEditMode` event triggers, `RegisterSystemFrame` flow
- `C:\Users\jonat\Repositories\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\Mainline\SharedUIPanelTemplates.lua` — `SidePanelTabButtonMixin`, `LargeSideTabButtonTemplate` behavior

### Primary (HIGH confidence — existing TBT codebase)

- `C:\Users\jonat\Repositories\TerribleBuffTracker\Display.lua` — `SnapshotSettings`, `HookViewerLayout`, existing `EventRegistry:RegisterCallback("EditMode.Exit", ...)` pattern
- `C:\Users\jonat\Repositories\TerribleBuffTracker\Core.lua` — Existing initialization order, `ADDON_LOADED`/`PLAYER_ENTERING_WORLD` flow, `TerribleBuffTrackerDB` structure

---
*Research completed: 2026-03-28*
*Ready for roadmap: yes*
