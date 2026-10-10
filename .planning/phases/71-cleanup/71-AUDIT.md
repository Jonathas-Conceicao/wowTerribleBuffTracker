# Phase 71 Audit: Findings and Hot-path review

Milestone base: 92f69b0. Re-verified at HEAD 73d7330 on 2026-10-10 before any source change.

## Findings

| Item | Location | Proof | Verdict |
|------|----------|-------|---------|
| `ns:EndTimer` | BuffEngine.lua `function ns:EndTimer(key)` (RACE-03 comment) | `cat *.lua *.xml *.toc scripts/*.js \| grep -c EndTimer` = 1 (the definition). `git grep -n "ns:EndTimer" 92f69b0 -- '*.lua'` shows callers Providers.lua:1435 and :2398 (racial providers, deleted Phase 67) | remove (with the RACE-03 comment) |
| D2 placeholder comment | Display.lua RenderBarContainer, "...would wipe a live timer, which / a live timer the engine still owns." | Read: sentence broken when Phase 67 removed the RacialProviderMixin mention | reword |
| MergeMode.lua header claim | MergeMode.lua lines 6-14: "This file, and this file alone ... TBT never touches a CDM frame" | MergeReanchor.lua (Phases 68-70) moves and styles CDM item frames with C setters; the viewer block in MergeMode.lua already says two places | reword |
| Per-id forget duplicated | MergeReanchor.lua `ns:AttachMergedItem` eviction branch and `ns:FlushMergedPlacement` prune (cellByID, idByCell, kindByID, settingsByID, labelByID, viewerByID) | Read: both clear the same per-id set; the eviction comment says they must go together | unify (`ForgetID`) |
| Item-frame collector duplicated | MergeMode.lua `CollectShownCooldownIDs` (l.537) and `CollectVisibleCooldownIDs` (l.569, Phase 69 STEAL-14) | `grep -n` shows both, called at l.653 and l.623: same walk, IsVisible vs IsShown | unify (`CollectFrameCooldownIDs`) |
| `ns.SPELL_CATEGORY_COMBAT_POTION` | Core.lua:166 | `grep -n SPELL_CATEGORY_COMBAT_POTION *.lua`: reader at Providers.lua:783 (Pot unresolved icon). Locked by 71-CONTEXT.md, Phase 70 review WR-01 | keep |
| `ns.POT_SPELLS` | Providers.lua:488 | `grep -n "ns.POT_SPELLS" *.lua`: only the export. `git log -S"ns.POT_SPELLS = POT_SPELLS"` earliest: 4cd64fc (v0.2.4). Its MergeMode reader went in Phase 70, but the export predates the milestone and is one of four exports with the same documented purpose; PROJECT.md "No refactors during cleanup phases" protects it | keep |
| `ResolveItemIdentity` 3rd/4th returns | MergeMode.lua | Only caller takes two values since before the milestone | keep (pre-existing) |

Fresh sweep: for 241 `function ns:X` / `function ns.X` / `ns.X =` names defined in the seven files, `git grep` counts of `ns[:.]X` at 92f69b0 versus HEAD, listing names with at most one reference now. Result: only EndTimer (5 to 1) and POT_SPELLS (3 to 1) dropped during the milestone. Others with count 1 (POT_ITEM_IDS, TRINKET_ITEM_IDS, TRINKET_SPELLS, SelectTBTTab, SpellProviderBaseMixin, UserSpellProviderMixin) had the same count at 92f69b0, so they are pre-existing and protected. No new item added.

## Hot-path review

- `ns:UpdateDisplay` (Display.lua): no change. One BeginMergedPlacement and one FlushMergedPlacement per tick; the container loop runs under `xpcall(RenderContainers, ReportRenderError, now)` with file-local function and handler, so no closure is allocated.
- RenderBarContainer and RenderIconContainer: no change. `ns:IsMergeReanchorActive()` and `ownViewer` are evaluated once per container per tick (Display.lua l.1245/1248 and l.1511/1513); the merged arms only call AttachMergedItem with existing references, no allocation.
- ApplyBarStyle and ApplyIconStyle on a hidden live merged cell every tick: accepted. Same C calls the pre-milestone code made for a merged row, and the cell's scale, width and height are what PlaceItem sizes Blizzard's frame from (Phase 70 review IN-03 kept this order on purpose). Changing it is a control-flow change only Phase 72 can check.
- `ns:AttachMergedItem`: no change. Table reads and writes only; no game call, no allocation.
- `ns:FlushMergedPlacement`: no change. One comparison (`mappedCount ~= attachedCount`) and one boolean test (`placementPending`) in the steady state.
- PlaceItem: no change. Per-frame dirty stamps keep unchanged frames to a few table reads.
- `ns:RefreshMergeShownSlots`: no change. Event-driven and coalesced by QueueMergeShownSlots; runs PlaceAllMergedItems and ReassertMergedSwipe per pass by design.
- The two `ownViewer` lines: left as they are. One expression each, so a helper would add a call and remove no logic.

## Scripts review

- scripts/install.ps1: OK. File set derived from the TOC (Core, BuffEngine, Providers, MergeMode, MergeReanchor, EditModeFrames, Config, Display, ReminderClick, CDMTab.xml plus CDMTab.lua via the XML); every entry exists on disk, no deleted file is listed. Unchanged this milestone.
- scripts/release.bat: OK. Refuses a non-main branch without TBT_ALLOW_BRANCH=1, then tags and pushes origin main plus the tag. Unchanged.
- .pkgmeta: OK. Ignores scripts, tools, .planning, Media/Source, CLAUDE.md, CHANGELOG.md, README.md, stylua.toml, .gitattributes, .github, *.png; no shipped Lua ignored. Unchanged.
- TerribleBuffTracker.toc: OK. Unchanged this milestone; MergeReanchor.lua is in the load list. Phase 72 needs only /reload for this phase's changes (the milestone note still asks for a full client restart).
- node scripts/aura-read-gate.js: PASS (1 read in 1 allowlisted reader); --selftest PASS (30 cases).
- node scripts/migrate-dryrun.js --selftest: PASS (14 cases).

Phase-wide gates: stylua . then stylua --check . clean; every .lua w/crlf; no Bin in diff stat 92f69b0..HEAD; no Phase 71 commit touches CHANGELOG.md, README.md or the TOC; EndTimer sweep 0; SPELL_CATEGORY_COMBAT_POTION in Providers.lua 1.

Deployed: v0.5.1-109-g3529a83-dev to _retail_, _ptr_, _beta_, _classic_beta_.

Backlog note (pre-existing, unfixed): untracked TerribleBuffTracker.zip and root PNG/BLP icons sit in the repo root; none ship wrongly (zip is untracked).
