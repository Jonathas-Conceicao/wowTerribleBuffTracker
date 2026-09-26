---
phase: 36-user-containers
verified: 2026-09-21T16:39:31Z
status: passed
closed_at_milestone: v0.4.0 (2026-09-23)
closure_evidence:
  - ".planning/testing/43-FOREVER-E2E-PASS.md"
  - ".planning/testing/44-RETAIL-PASS.md"
closure_note: >-
  Closed in bulk at milestone close, not item by item. The human_verification list below was
  written when this phase's code landed and records what still needed a live client at that
  moment. Those observations were carried out in Phase 43 (Forever beta, build 1.60.1.69913,
  continuous play-testing 2026-09-21 to 22) and Phase 44 (retail, Mythic+ and a raid encounter,
  2026-09-23). The user signed both off as a whole -- "everything on Forever is tested and
  acceptable" and "no lua errors so far" -- rather than ticking each row, so read the list below
  as covered by those two passes collectively, not as individually attested. It is kept intact
  because it is the best record of what this phase could not prove statically.
score: 4/4 roadmap success criteria verified at code level; 4/4 requirements (CONT-04..07) satisfied at code level; 9 items require in-game confirmation
overrides_applied: 0
human_verification:
  - test: "Create a container from the config panel"
    expected: "It appears as a section in the CDM tab (between Utility Cooldowns and Not Displayed) and as a movable frame in Edit Mode."
    why_human: "Rendered section/frame appearance and CDM-tab layout can only be observed in a running client."
  - test: "Drag a tracker into a newly created container"
    expected: "The tracker renders inside that container's frame."
    why_human: "Drag-and-drop result and render output require a live client."
  - test: "Change a container's scale/padding/orientation/items-per-row/bar-width"
    expected: "Every OTHER container is visually unchanged."
    why_human: "Visual isolation between sibling frames can only be confirmed by looking at the rendered UI."
  - test: "Delete a non-empty user container"
    expected: "The confirm popup names the tracker count before commit; afterwards those trackers are in Not Displayed, not gone."
    why_human: "Popup rendering and post-delete tracker location require a live client."
  - test: "Check the config panel and Edit Mode for a Delete control on any of the four base containers"
    expected: "None exists anywhere."
    why_human: "Absence of a rendered control is a visual check."
  - test: "Create a container while Edit Mode is already open"
    expected: "It is immediately movable/selectable/showing its handle, not a ghost."
    why_human: "Requires live Edit Mode interaction."
  - test: "Delete a container mid-drag"
    expected: "The mouse is not left captured and no error fires."
    why_human: "Requires a live drag-in-flight interaction, cannot be simulated statically."
  - test: "/reload and confirm user containers rehydrate from ns.db with their settings and positions"
    expected: "Containers, their settings, and positions survive a /reload (rehydration, not SavedVariables persistence — that belongs to Phase 44's retail logout→login pass)."
    why_human: "Rehydration only manifests when the addon actually reloads in-client."
  - test: "Watch for Lua errors on load, create, delete, Edit Mode entry/exit, and in combat"
    expected: "No uncaught Lua error at any point."
    why_human: "Runtime error absence cannot be proven by static analysis alone."
---

# Phase 36: User Containers & Per-Container Settings Verification Report

**Phase Goal:** A player can shape TBT's display to their own layout — as many containers as they want, each configured on its own.
**Verified:** 2026-09-21T16:39:31Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can create a container, and it appears in Edit Mode and in the CDM tab alongside the four base ones | VERIFIED (code) | `Core.lua:212-236` `ns:CreateUserContainer` calls `ns:GenerateContainerKey`, `ns:RegisterContainerDef`, `ns.EnsureContainerSettings`, then `ns:AttachContainerRuntime(def)` (`Core.lua:168-181`), which in turn no-op-guards into `ns.AllocateContainerRuntime` (`Display.lua:101`), `ns.CreateContainerFrames` (`EditModeFrames.lua:788`), `ns.RebuildContainerSectionDefs` + `ns.AddContainerSection` (`CDMTab.lua:55, 1335`). Same attach path is used by `ns:RehydrateUserContainers` (`Core.lua:156-161`). All four surfaces confirmed wired. |
| 2 | A user-created container can be deleted and a base one cannot; deleting one moves its trackers to a destination the user is told about before confirming, and nothing silently disappears | VERIFIED (code) | `Core.lua:243-292` `ns:DeleteUserContainer` rejects any def without `.isUser` (`245`), which is set nowhere except `ns:RegisterContainerDef` (`Core.lua:135`). Trackers are moved to `"hidden"` via `ns:SetBuffSection` BEFORE `ns:UnregisterContainerDef`/`ns:DetachContainerRuntime` run (`252-263`). `CDMTab.lua:1180-1198` computes `count = ns:CountContainerTrackers(key)` and builds the message string BEFORE calling `StaticPopup_Show("TBT_DELETE_CONTAINER", message, ...)` — the count is embedded in the popup text, not reported after the fact. `StaticPopupDialogs["TBT_DELETE_CONTAINER"].text = "%s"` (`CDMTab.lua:1031`) keeps a user title out of a format string. Delete rows are generated only from `ns.db.userContainers` (`CDMTab.lua:1171` loop, `grep -c` = 3 inside the function), so no base container can ever get a Delete button — a second, independent guard alongside the `isUser` check in `Core.lua`. |
| 3 | Changing scale, padding, orientation, items-per-row or bar width on one container leaves every other container visually unchanged | VERIFIED (code) | `Display.lua:49-87` `RefreshContainerSettings` builds a fresh `dst = {}` per container key on first refresh and reuses it forever (`61-65`) — no two containers ever share a table. `EditModeFrames.lua` sliders write `ns.db.containerSettings[activeContainerKey][settingKey]` (verified at the "Items Per Row" slider, `461`), keyed by the specific container, then call `ns.RefreshContainerSettings()`/`ns:UpdateDisplay()`. `itemsPerRow` is scoped to the non-bar branch only (`EditModeFrames.lua:420-465`: bar branch has no "Items Per Row" line; icon branch does). `RenderIconContainer` (`Display.lua`) reads `settings.itemsPerRow` per-container off the cached snapshot, never `ns.db` directly. |
| 4 | A tracker can be moved from any container to any other, and stays there across `/reload` | VERIFIED (code, `/reload` portion needs live confirmation) | `CDMTab.lua:183-193` both the Suggested "Add to …" menu and the right-click "Move to …" menu loop `ipairs(ns.CONTAINERS)`, which includes user containers once rehydrated/created — no filtering by kind or base/user. `VALID_DROP_SECTIONS` is rebuilt from the same registry (`CDMTab.lua:55-65`) and consumed by `SectionHitTest`/`OnDragUpdate` (`295`, `339`). Persistence across `/reload`: `ns:SetBuffSection` writes `entry.section` into `ns.db.trackedBuffs` (pre-existing, `BuffEngine.lua:271`), which is SavedVariables-backed; rehydration order (`Core.lua:357-364`) guarantees the container the tracker points at exists again before anything renders. Actual `/reload` behavior is a human check (see below). |

**Score:** 4/4 roadmap success criteria verified at the code level.

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| CONT-04 | User can create additional containers beyond the four base ones | SATISFIED | `Core.lua:212-236` `ns:CreateUserContainer`; UI in `CDMTab.lua:910-1000` (`CreateContainerDialog`). |
| CONT-05 | User can delete a container they created — never a base one — and its contents move somewhere predictable rather than disappearing | SATISFIED | `Core.lua:243-292` `ns:DeleteUserContainer`; two independent base-container guards (see truth 2 above); count-first confirm dialog (`CDMTab.lua:1180-1198`, `1030-1042`). |
| CONT-06 | Each container carries its own settings (scale, padding, orientation, items per row, bar width) independent of every other container | SATISFIED | Fresh-table-per-key pattern in `Display.lua:49-87`; `itemsPerRow` added end-to-end (`Core.lua:60-104`, `Display.lua:49-87, 728-766`, `EditModeFrames.lua:420-465, 285-294`). |
| CONT-07 | User can move a tracker from one container to another | SATISFIED | Registry-derived drag targets and right-click menus (`CDMTab.lua:183-193, 295, 339`); machinery pre-existed from Phase 35, extended automatically by the dynamic registry. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Core.lua` | `ns.db.userContainers`/`ns.db.nextContainerId` persistence, key generation, rehydration, create/delete API | VERIFIED | All present and substantive: `ns:GenerateContainerKey` (`112-121`), `ns:RegisterContainerDef`/`ns:UnregisterContainerDef` (`126-151`), `ns:RehydrateUserContainers` (`156-161`), `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime` (`168-196`), `ns:CreateUserContainer`/`ns:DeleteUserContainer`/`ns:CountContainerTrackers` (`200-292`). |
| `Display.lua` | `ns.AllocateContainerRuntime`/`ns.ReleaseContainerRuntime`, allocation-free render path | VERIFIED | `101-124`; zero table constructors below `RenderBarContainer` except the two pre-existing `proc = {...}` placeholder lines (confirmed present verbatim in commit `b6c0978`, i.e. pre-dating this phase — filed as a Phase 43 cleanup item, not a new stub). |
| `EditModeFrames.lua` | `ns.CreateContainerFrames`/`ns.DestroyContainerFrames`, Items Per Row slider, CopyButton hide | VERIFIED | `788-848` (create/destroy), `461` (slider, icon-kind branch only), `354` (`popup.CopyButton:SetShown(...)`). |
| `CDMTab.lua` | Rebuildable `SECTION_DEFS`/`VALID_DROP_SECTIONS`, section add/remove, config-panel create/delete UI | VERIFIED | `ns.RebuildContainerSectionDefs` (`55-65`, wipe+refill, never reassigned), `ns.AddContainerSection`/`ns.RemoveContainerSection` (`1335-1361`, key-lookup only, never walk `ns.CONTAINERS`), `ns:RefreshContainerConfigSection` (`1166-1203`), `StaticPopupDialogs["TBT_DELETE_CONTAINER"]` (`1030-1042`). |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Core.lua ADDON_LOADED` | `ns.CONTAINERS` | `ns:RehydrateUserContainers()` called after the `containerSettings` guard and before the `ipairs(ns.CONTAINERS)` settings pass | WIRED | `Core.lua:334-364` — line order confirmed by direct read, not just grep count. |
| `ns:CreateUserContainer`/`ns:DeleteUserContainer` | `Display.lua`/`EditModeFrames.lua`/`CDMTab.lua` | `ns:AttachContainerRuntime`/`ns:DetachContainerRuntime` nil-guarded dispatch | WIRED | `Core.lua:168-196`; every hook call guarded on function existence, and each hook additionally guards on its own subsystem state (`ns.containers`, `ns.tbtSections`). |
| `VALID_DROP_SECTIONS` | `SectionHitTest`/`OnDragUpdate` | same module-level table, wiped and refilled | WIRED | `CDMTab.lua:56-57` (`wipe`), `59-64` (refill), `295`/`339` (consumers) — declared once (`grep -c 'VALID_DROP_SECTIONS = {}'` = 1), never reassigned. |
| `EditModeFrames.lua` Items Per Row slider | `Display.lua RenderIconContainer` | `ns.db.containerSettings[key].itemsPerRow → RefreshContainerSettings → cachedSettings[key].itemsPerRow` | WIRED | `EditModeFrames.lua:461` write path is the shared slider plumbing; `Display.lua:83` (`dst.itemsPerRow = math.max(1, src.itemsPerRow or 12)`); `Display.lua:735` (`local perRow = settings.itemsPerRow`) reads the cached snapshot, not `ns.db` directly. |

### Data-Flow / Lifecycle Trace

| Concern | Trace | Status |
|---|---|---|
| Rehydration ordering | `Core.lua:334` (`containerSettings` guard) → `343-348` (userContainers/nextContainerId defaults) → `357` (`ns:RehydrateUserContainers()`) → `362-364` (settings pass). Confirmed every `ipairs(ns.CONTAINERS)`/`ns.CONTAINER_BY_KEY` use across `Display.lua`, `EditModeFrames.lua`, `CDMTab.lua`, `BuffEngine.lua` is either inside a function called at `PLAYER_ENTERING_WORLD`/event time (re-callable, runs after rehydration) or inside `ns.RebuildContainerSectionDefs`'s file-scope initial call (harmlessly rebuilds with only the 4 base containers, then correctly re-rebuilt per-user-container by `ns:AttachContainerRuntime`). No file-scope loop was found that runs once at load and is never re-run. | VERIFIED |
| Deletion ordering | `Core.lua:262-263`: `ns:UnregisterContainerDef(key)` runs strictly before `ns:DetachContainerRuntime(key)`. `Display.lua:112-124` `ns.ReleaseContainerRuntime` and `EditModeFrames.lua:826-848` `ns.DestroyContainerFrames` both look up state by key alone and never walk `ns.CONTAINERS`. `Display.lua:786-799` `ns:UpdateDisplay`'s fallback branch guards a possibly-nil `pool`/`container`. No window found where `ns:UpdateDisplay` could index a nil pool. | VERIFIED |
| Key reuse | `Core.lua:112-121` `ns:GenerateContainerKey`: id is drawn from `ns.db.nextContainerId`, only ever written forward (`119`, and `Core.lua:346-347` seeds it once); the live re-check loop excludes `ns.CONTAINER_BY_KEY[key]`, `"hidden"`, `"suggested"`. A deleted container's key is removed from `CONTAINER_BY_KEY` (`Core.lua:146`) but `nextContainerId` is never decremented, so the same string can never be reissued — a stale `entry.section = "userN"` on some tracker can never be adopted by a later container. | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| stylua formatting compliant | `stylua --check .` | exit 0 | PASS |
| CHANGELOG.md untouched by phase commits | `git diff --stat b6c0978..5dfe764 -- CHANGELOG.md` | empty | PASS |
| Only the four expected files touched | `git diff --stat b6c0978..5dfe764` | `CDMTab.lua`, `Core.lua`, `Display.lua`, `EditModeFrames.lua` only | PASS |
| No flavour checks introduced | `grep -rn 'GetBuildInfo\|WOW_PROJECT\|tocversion\|IsTestBuild' *.lua` | no matches | PASS |
| `TBTSettingsTab`/`AnchorTabBelowCDMTabs` untouched by phase 36 | `git diff b6c0978..5dfe764 -- CDMTab.lua \| grep 'AnchorTabBelowCDMTabs\|TBTSettingsTab'` | no matches | PASS |
| No rename control anywhere | `grep -rin 'rename' *.lua` | only 2 unrelated pre-existing comments (`BuffEngine.lua` migration comment, `Providers.lua` pitfall note) | PASS |
| `ns.db.stealMode` still has zero behavioural readers | `grep -rn 'ns.db.stealMode' *.lua` | only the Phase 35.1 checkbox write/re-sync and the Core.lua default seed | PASS |
| No container cap introduced | `grep -n 'MAX_CONTAINER\|containerLimit' Core.lua CDMTab.lua` | no matches | PASS |
| No new hot-path table constructors | `sed -n '/^local function RenderBarContainer/,$p' Display.lua \| grep -c '{}'` | 2 (pre-existing `proc = {}` lines, confirmed present in `b6c0978` before this phase) | PASS (known, filed for Phase 43) |
| `ns:UpdateDisplay` allocation-free | `sed -n '/^function ns:UpdateDisplay/,/^end$/p' Display.lua \| grep -c '{}'` | 0 | PASS |

### Anti-Patterns Found

None. `grep -n 'TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER' Core.lua Display.lua EditModeFrames.lua CDMTab.lua` returns nothing.

### Human Verification Required

See YAML frontmatter `human_verification` block. These 9 items are outstanding on the WoW Forever beta client, matching Plan 04 Task 4's own documented checklist (not re-derived), and are folded into Phase 42's end-to-end verification pass. None of the code-level checks above are contingent on these — the frontmatter/table evidence stands independent of them.

### Gaps Summary

No code-level gaps found. Every observable truth, artifact, key link, and lifecycle-ordering concern in the goal-backward checklist traces to real, substantive, wired code — not stubs. The only outstanding items are the nine in-game observations that genuinely require a running client (rendering, drag-and-drop, `/reload`, and Lua-error absence in combat), none of which can be verified by static reading. Per the verification-reality guidance for this phase, that makes the status `human_needed`, not `gaps_found`.

---

*Verified: 2026-09-21T16:39:31Z*
*Verifier: Claude (gsd-verifier)*
