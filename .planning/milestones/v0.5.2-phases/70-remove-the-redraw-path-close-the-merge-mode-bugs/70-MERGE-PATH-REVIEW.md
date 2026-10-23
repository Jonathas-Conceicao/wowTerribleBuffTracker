# Phase 70: Merge Mode Whole-Path Review

Scope: the shipped Lua at commit `3ebc819` (after plans 70-01..70-04 deleted the redraw path), read
in full for `MergeReanchor.lua` and `MergeMode.lua`, and for every Merge Mode part of `Display.lua`
(`SlotDraws`, `CenteredSlotPlacement`, `RenderBarContainer`, `RenderIconContainer`,
`RenderContainers`, `ns:UpdateDisplay`, the OnUpdate driver in `ns:InitDisplay`). The question is
999.24's requirement (STEAL-22): "review the whole code path, not just the trigger. No code path may
be able to paint one aura over every cell ... the design must make this kind of failure impossible."
Every verdict below stands on a function name; line numbers in parentheses are as of `3ebc819`.
Blizzard source (local `wow-ui-source`, a snapshot) is cited for intent only, never as proof that
something cannot happen in the live game.

## Pixel sources

Everything that can put pixels on, or over, a TBT container while Merge Mode is on:

1. **Blizzard's own CDM item frames**, moved by `PlaceItem` (MergeReanchor.lua:343-424) with one
   `ClearAllPoints` and one `SetPoint(point, cell, point, 0, 0)` (:418-419), a `SetScale` (:414),
   a `SetWidth` for bars (:416), and the plain-setter style in `ApplyMergedStyle` (:199-226). TBT
   writes no content into them except, on the hidden-to-shown edge of a bar's name or duration
   string, the entry's own label or an empty string (`SetBarRegions`, :129-164). Everything else
   inside the frame (icon, sweep, countdown, charges, stacks, glow, pandemic, dispel border) is
   Blizzard's drawing for that frame's own cooldownID.
2. **TBT's preview placeholder** for a merged entry: `ShowMergedPlaceholderIcon` (Display.lua:1465-1480)
   and the bar path's `bar:Show()` (Display.lua:1431-1432). Drawn only when the entry's
   `cdmFrameVisible == false`, which `ns:RefreshMergeShownSlots` stamps false only while
   `ns:IsMergePreviewState()` holds and Blizzard's frame for that id is not visible
   (MergeMode.lua:719-720). Its icon and label come from the entry's own `spellID` / `iconOverride` /
   `label` (resolved at mirror-build time from `C_CooldownViewer.GetCooldownViewerCooldownInfo` for
   that cooldownID, MergeMode.lua:416-436). No aura is read. No frame is attached on that render.
3. **TBT's own non-merged trackers** on their own cells (the timer, cooldown-slot and placeholder
   arms of `RenderIconContainer`, Display.lua:1622-1707, and the bar rows). They are keyed by provider
   key (`activeByKey[entry.key]`), never by a merged entry, and are not part of the merged path. Their
   one aura read is `ns:ReadPlayerAura` (BuffEngine.lua:34-50), a player-only lookup by explicit
   spellID behind `C_Secrets.ShouldSpellAuraBeSecret`; `node scripts/aura-read-gate.js` reports it
   as the only aura read in the shipped tree ("1 reads in 1 allowlisted readers").

Deleted in this phase, each of which used to be a pixel source or fed one: the engine aura containers
(per-unit aura frames placed over merged cells, driven by candidate filters that Blizzard skips for a
harmful aura on an assistable unit -- the 999.24 precedent); the target/player aura lookups that
resolved merged timing by spell name with no caster filter (999.22/999.23); the relays that copied a
Blizzard frame's bar fill and time text into TBT's own widgets; TBT's own pandemic and dispel-border
reads for merged slots; and the merged branches of TBT's charge-count and cooldown drawing (999.21).
The 70-04 sweep for every one of those names prints 0 (see the SUMMARY).

## Event-to-pixel paths

| Trigger | Pass(es) it queues or runs | What it writes | Pixels that can change |
|---|---|---|---|
| REFRESH_MIRROR events: `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`, `TRAIT_CONFIG_UPDATED`, `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`, `PLAYER_LEVEL_CHANGED`, `VARIABLES_LOADED` (MergeMode.lua:1321-1331, OnEvent :1355-1371) | `ns:QueueMergeMirror` (C_Timer 0) -> `ns:RefreshMergeMirror` (:309-511) -> sets `mirrorChangedForPlacement`, queues the shown pass, `ReanchorMergeViewers(true)` (hooks only, places nothing) | `ns.mergeSlots` (TBT tables); no frame | None directly. The queued shown pass renders and places (next row). |
| Shown-pass events: `UNIT_AURA` (player, target), `PLAYER_TARGET_CHANGED`, `PLAYER_TOTEM_UPDATE`, `BAG_UPDATE_COOLDOWN`, `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`, plus every REASSERT-only event (:1303-1308, else-arm :1361) | `ns:QueueMergeShownSlots` (C_Timer 0) -> `ns:RefreshMergeShownSlots` (:641-746): restamps `cdmShown` / `cdmFrameVisible`, refills `ns.mergeShownSlots`; if `mirrorChangedForPlacement`, runs `ns:UpdateDisplay`; then `ns:PlaceAllMergedItems()` and `ns:ReassertMergedSwipe()` | TBT tables; item-frame anchor/scale/style through `PlaceItem`; swipe off on Show-Timer-off cooldown icons | Position, size and style of moved frames; TBT cells via the render |
| REASSERT_VISIBILITY events: the combat edges, `PLAYER_LEVEL_CHANGED`, `VARIABLES_LOADED`, `CVAR_UPDATE`, `EDIT_MODE_LAYOUTS_UPDATED`, `PLAYER_ENTERING_WORLD`, `PLAYER_SPECIALIZATION_CHANGED`, `TRAIT_CONFIG_UPDATED` (:1333-1353) | `ns:QueueMergeVisibility` -> `FlushMergeVisibility` (:1179-1189) -> `ns:ApplyMergeVisibility` (:1131-1175) | Viewer anchor and clamp flag only (`CaptureAndSuppress` / `RestorePlacement`) | The parked viewer's on/off-screen position; never an item frame, never a cell |
| EventRegistry `CooldownViewerSettings.OnDataChanged` (:1378-1380) | `ns:QueueMergeMirror` | as REFRESH_MIRROR | as REFRESH_MIRROR |
| EventRegistry `EditMode.Enter` / `EditMode.Exit` (:1407-1421) | `editModeOpen` flag; visibility and mirror queued | as above | Preview placeholders appear/disappear on the next render |
| EventRegistry `CooldownViewerSettings.OnShow` / `OnHide` (:1441-1453) | visibility, shown pass and mirror queued | as above | as above |
| `dirtyFrame`: `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`, `EDIT_MODE_LAYOUTS_UPDATED` (MergeReanchor.lua:103-109) | `ns:MarkMergedPlacementDirty` (:98-101): `placeGeneration + 1`, `placementPending = true` | Two TBT locals | Every placed frame is re-placed on the next flush, through the same map |
| `RefreshContainerSettings` (Display.lua:208-252) | `ns:MarkMergedPlacementDirty` | as above | as above (new scale/alpha/width/timer style) |
| Each viewer's Layout post-hook (MergeReanchor.lua:594-612) | `PlaceViewer(viewer, true)` for THAT viewer only; while previewing also `ns:QueueMergeMirror` | Anchor/scale/style of that viewer's frames, through the current map | That viewer's frames return to their cells (or to the parked viewer) right after Blizzard's own Layout |
| 20 Hz OnUpdate render (Display.lua:727-735, `UPDATE_INTERVAL = 0.05`) and every other `ns:UpdateDisplay` caller (BuffEngine, Core, EditModeFrames, Providers, the combat frame Display.lua:722-725) | `ns:UpdateDisplay` (:1834-1866): `BeginMergedPlacement` -> `xpcall(RenderContainers)` -> `FlushMergedPlacement` | TBT cells (anchor, style, hidden); `AttachMergedItem` intent; flush prunes and, if pending, `PlaceAllMergedItems(false)` | TBT cells; moved frames follow their cell; ids that lost a cell are released |
| `ns:SetMergeMode` (MergeMode.lua:1208-1231), reached from Config.lua:200 | Off: wipes `ns.mergeShownSlots` inline, `MarkMergedPlacementDirty`; both: mirror and visibility queued | `ns.db.mergeMode`; TBT tables | Off: the next render attaches nothing and its flush releases every placed frame; the mirror's off branch also calls `ReanchorMergeViewers` -> `PlaceAllMergedItems(true)` (:316-323) |

No other code calls `PlaceItem`, `PlaceViewer`, `PlaceAllMergedItems`, `AttachMergedItem` or
`FlushMergedPlacement` (grep across `*.lua`: Display.lua:1435, :1615, :1839, :1865 and the calls
inside MergeMode.lua/MergeReanchor.lua listed above).

## Fan-out candidates

The structural invariant every row leans on, proved from `ns:AttachMergedItem`
(MergeReanchor.lua:467-517), `ns:FlushMergedPlacement` (:553-582) and `ns:PlaceAllMergedItems`
(:436-458): **`cellByID` and `idByCell` are inverse one-to-one maps at every instant.** Every write
`cellByID[id] = cell` (:505) is paired with `idByCell[cell] = id` (:506), after clearing the id's old
cell in `idByCell` (:487-490) and evicting the cell's previous id from every per-id table (:496-504).
The prune (:562-573) removes an id from `idByCell` only when `idByCell[cell] == id`. The off path
wipes both (:438-439). Nothing else writes either table. This holds whatever order renders, flushes
and hooks run in, so it does not depend on `renderGen` bookkeeping.

The placement rule every row leans on: `PlaceItem` puts a frame only on `cellByID[frame.cooldownID]`,
and only when the frame's parent is `viewerByID[id]` (:347-357); every other outcome is
`ReleaseItem` (:359-363, :380-396). A frame has one anchor: `ClearAllPoints` then one `SetPoint`
(:418-419).

| # | Candidate route | Where it would live | Guard that closes it (function + condition) | Verdict |
|---|---|---|---|---|
| C1 | One frame drawn on many cells | `PlaceItem` | One `ClearAllPoints` + one `SetPoint(point, cell, point, 0, 0)` per placement (MergeReanchor.lua:418-419); `cell` is the single value `cellByID[id]` (:348). A WoW region with one anchor point has one rect. | CLOSED |
| C2 | One cooldownID fanned out to many cells | `cellByID`, `AttachMergedItem` | `cellByID` is a map, one cell per id; a second attach of the same id in one render to another cell returns early (`attachGen[id] == renderGen and cellByID[id] ~= cell`, :476-478); a re-attach to a new cell in a later render first clears the old cell (:486-490). | CLOSED |
| C3 | One cell holding many ids (two different frames stacked on one cell -- the 999.22 shape) | `AttachMergedItem`, `idByCell` | Eviction: `previous = idByCell[cell]; if previous and previous ~= id` drops `previous` from `cellByID`, `kindByID`, `settingsByID`, `labelByID`, `viewerByID` (:496-504). With the one-to-one invariant, distinct ids can never resolve to one cell in `PlaceItem`. Cells themselves are unique: `GetIcon` / `GetBar` (Display.lua:613-630) key the pool by container and slot index, a released container's frames are unparented and dropped (`ns.ReleaseContainerRuntime`, :277-293), and every container renders once per `ns:UpdateDisplay`. Cell POSITIONS are unique too: non-centred slots use `ns:GridSlotPlacement(slotIndex, ...)`, bars `-(i - 1) * step`, centred slots a strictly increasing `drawnIndex` (Display.lua:1580-1590), and a non-drawing centred slot gets no anchor at all (`icon:ClearAllPoints()` with no `SetPoint`, :1592-1595). | CLOSED |
| C4 | One id published in two container lists | `ns:RefreshMergeMirror` | `CollectFrameOwners` (MergeMode.lua:226-237) records the owning container per id before any list is filled; `claimable = not claimedIDs[cooldownID] and (frameOwnerByID[cooldownID] or def.key) == def.key` (:373-375), `claimedIDs[cooldownID] = true` on insert (:491). `BuildViewerIDs` skips a repeated id (`viewerOrder[cooldownID] == nil`, :199). The shown pass only filters these lists (:705-725). C2's same-render guard is the safety net behind it. | CLOSED |
| C5 | A frame from another viewer sitting on this container's cell (buff-to-bar move, a stale map) | `PlaceItem` | `if cell and parent ~= viewerByID[id] then cell = nil end` (:354-356) -> `ReleaseItem`. `viewerByID[id]` is the attaching container's own viewer, `ownViewer` (Display.lua:1243, :1501). A container with no resolvable viewer passes `nil` (`reanchorHere and (ns.cdmViewers[def.key] or _G[def.cdmViewerGlobal])` with both lookups unresolved), and an item frame's parent is never nil, so `parent ~= viewerByID[id]` holds and it releases (fail-closed). | CLOSED |
| C6 | Two active frames for one cooldownID in one viewer | Blizzard's pool; `PlaceItem` | Blizzard acquires one frame per layout index and assigns ids by index (`CooldownViewerMixin:RefreshLayout` / `:RefreshData`, CooldownViewer.lua:2021-2031, :2071-2077 -- intent only). If that ever broke, both frames resolve to the same `cellByID[id]`: two copies of the SAME id on that id's own cell, never on another cell. Residual note, not a fan-out. | CLOSED |
| C7 | Blizzard re-assigns cooldownIDs in place without a Layout (same item count: `OnCooldownDataChanged` -> `RefreshData(ids, forceSet)`, CooldownViewer.lua:2007-2019) | Window between Blizzard's handler and TBT's next pass | Each frame stays on the one distinct cell it already held, so the window is a permutation of whole frames, never one frame or aura on many cells. TBT's own callback for the same event (`CooldownViewerSettings.OnDataChanged`, MergeMode.lua:1378-1380) queues the rebuild; the shown pass renders then `PlaceAllMergedItems`, and `PlaceItem`'s `placedID[itemFrame] == id` stamp (:369) re-places every frame whose id changed. Bounded to the two C_Timer(0) hops. | CLOSED |
| C8 | A stale map after a configuration or spec change | `ns:RefreshMergeMirror`, `ns:RefreshMergeShownSlots`, `ns:FlushMergedPlacement` | The Merge-on rebuild places nothing (`pcall(ns.ReanchorMergeViewers, ns, true)`, MergeMode.lua:508; `skipPlace`, MergeReanchor.lua:616). The shown pass it queues runs `ns:UpdateDisplay` first (`mirrorChangedForPlacement`, MergeMode.lua:734-739), whose render rebuilds the map whole: ids not attached this render are pruned (`mappedCount ~= attachedCount`, MergeReanchor.lua:560-575); count equality implies set equality because every attached id holds a cell after the render (no cell is attached twice per render, C3). Only then does `PlaceAllMergedItems` run. Until then the old map is still one-to-one (invariant), so the worst case is an id on its previous cell in its own container. | CLOSED |
| C9 | The Layout post-hook's forced pass placing through the previous render's map | `ns:ReanchorMergeViewers` hook | `PlaceViewer(viewer, true)` walks only the viewer whose Layout ran (MergeReanchor.lua:598); every frame goes through `PlaceItem`'s viewer check (C5) and the one-to-one map (C3). A cell belongs to one container, hence one `ownViewer`, so every frame that can sit on a given cell is in the walk that re-places that cell's frames; the walk is synchronous, so no frame is drawn between its iterations. Off: the hook returns at once (`if not ns:IsMergeReanchorActive() then return end`, :595-597). | CLOSED |
| C10 | The preview placeholder drawing a frame or aura it does not own | `ShowMergedPlaceholderIcon`, bar placeholder arm | Content is the entry's own `spellID` / `iconOverride` / `label` (Display.lua:1475-1476, :1353-1355), set at mirror-build time for that cooldownID; no aura read. The placeholder arm does NOT call `AttachMergedItem` (:1431-1432, :1610-1611), so that id loses its cell in the flush and its Blizzard frame is released to the parked viewer: never drawn twice. Live play never takes the arm: `cdmFrameVisible` is `not previewing or ...` (MergeMode.lua:719-720). | CLOSED |
| C11 | Merge Mode off with frames still placed | `ns:SetMergeMode`, `ns:PlaceAllMergedItems`, `PlaceItem`, the hook | `SetMergeMode(false)` wipes every shown list inline and marks placement dirty (MergeMode.lua:1219-1224); the next render attaches nothing; `FlushMergedPlacement` -> `PlaceAllMergedItems(false)`, whose off branch wipes all maps and runs `ReleaseItem` over every frame in `placedOn` (active or not), one `pcall` per frame (MergeReanchor.lua:437-453). Independently, the mirror's off branch calls `ReanchorMergeViewers` -> `PlaceAllMergedItems(true)` (MergeMode.lua:316-323), `PlaceItem` refuses a cell while `IsMergeReanchorActive()` is false (:347), and the Layout hook returns early (:595). Display's merged arms fail closed when Merge Mode is off: `elseif slot.isMerged then bar:Hide()` / `elseif entry.isMerged then icon:Hide()` (Display.lua:1437-1439, :1617-1621). | CLOSED |
| C12 | An unfiltered or identity-filter-bypassed aura source painting merged cells (the 999.24 precedent: Blizzard's candidate filters skip the spell-ID filter for a harmful aura on an assistable unit) | Formerly the engine aura containers and the target-aura lookups | Deleted (70-03); the 70-04 sweep for every deleted name prints 0. No file in the merged path calls an aura API: `grep` for `C_UnitAuras`, `GetAuraData`, `AuraUtil`, `UnitAura`, `GetPlayerAuraBySpellID` in MergeMode.lua, MergeReanchor.lua and Display.lua finds only a comment (Display.lua:869). `aura-read-gate.js` proves the only aura read in the tree is `ns:ReadPlayerAura` (BuffEngine.lua:34), which serves TBT's own trackers by explicit spellID and is never called from MergeMode.lua, MergeReanchor.lua or Display.lua. Merged cell content is drawn by Blizzard's frame for that cell's own cooldownID. | CLOSED |
| C13 | Mind control / charm: unit reaction or assistability changing with no target change | Formerly the target-slot latch and the player slot with "no guard needed" | Nothing in the merged path reads unit reaction, assistability, faction, charm state or "is from player": `grep` for `UnitIsFriend`, `UnitCanAssist`, `UnitCanAttack`, `UnitReaction`, `UnitIsCharmed`, `UnitIsEnemy`, `isFromPlayerOrPlayerPet`, `sourceUnit` in the three files returns nothing. There is no filter left to bypass and no latch left to go stale. What a merged cell shows is decided by C1-C9 (which frame, by its own id) and by Blizzard (what that frame draws). | CLOSED |
| C14 | A render that raises partway | `ns:UpdateDisplay` | `xpcall(RenderContainers, ReportRenderError, now)` (Display.lua:1861) so `FlushMergedPlacement` always runs (:1865); ids the failed render did not attach are pruned and released (MergeReanchor.lua:557-575). A raise inside `PlaceItem` is per frame (`pcall(PlaceItem, ...)`, :432); the frame is tracked before its first setter with no generation (:409-412), so the next pass retries it; `ReleaseItem` moves the frame off the cell before restyling and clears bookkeeping last (:320-340). A raise before the `xpcall` (`GetActiveTimers`, `RefreshCooldownSlotCounts`) skips the flush: placement stays on the previous, one-to-one map, and the shown pass's own `PlaceAllMergedItems` and Merge-off paths (C11) do not depend on the render. | CLOSED |
| C15 | A frame Blizzard hands back with no id, a secret id, or edit-mode placeholder data | `PlaceItem` | `not issecretvalue(id) and type(id) == "number"` is required before any cell lookup (:347); otherwise `cell = nil` -> `ReleaseItem`. Blizzard's edit-mode padding frames (`ClearCooldownID` + `SetEditModeData`, CooldownViewer.lua:2079-2087) carry no id and are released on TBT's next pass. | CLOSED |
| C16 | A released frame landing on or beside a TBT cell | `ReleaseItem`, `CaptureBlizzardAnchor` | The captured anchor is never a TBT cell (`isCell[rel]`, :297); Blizzard's grid anchors items to the viewer itself (`GridLayoutFrameMixin:Layout` uses `AnchorUtil.CreateAnchor(anchorPoint, self, anchorPoint)`, LayoutFrame.lua:572 -- intent), so a released frame returns to the parked, off-screen viewer; the fallback is the viewer's TOPLEFT (:333-335). | CLOSED |
| C17 | TBT text written into a moved frame for the wrong id | `SetBarRegions`, `ApplyMergedStyle` | `PlaceItem` passes `labelByID[id]` for the frame's own current `cooldownID` (:421); the label is the entry's own string (:516), written only on a hidden-to-shown edge (:146-154). `ReassertMergedSwipe` writes only `SetDrawSwipe(false)` (:531-542). No aura, count or texture is ever written by TBT. | CLOSED |
| C18 | The 20 Hz render re-centring onto overlapping cells while `cdmShown` is stale | `SlotDraws`, `CenteredSlotPlacement` | `drawnIndex` is incremented once per drawing slot (Display.lua:1583-1587), so two drawing slots never share a position; a stale `cdmShown` makes a gap (frame hidden on a placed cell) or a frame on an anchorless cell (not drawn) until the next shown pass, never an overlap. | CLOSED |

## 999.24 -- mind control

Report: while the player was mind-controlled, every merged cell showed the same debuff on the player.

Why no merged slot can now show an aura it does not own: TBT reads no aura in Merge Mode (C12) and
no unit reaction or charm state (C13), so there is no aura source left that a charm could unfilter.
What a cell shows is the one Blizzard item frame placed on it, chosen by that frame's own
cooldownID through a one-to-one map (C1, C2, C3), restricted to the container's own viewer (C5),
rebuilt whole every render (C8) and released on every failure (C11, C14, C15). One aura over every
cell would need one frame on many cells (C1: impossible, one anchor) or one id on many cells (C2,
C4: impossible, one cell per id and one list per id) or TBT writing aura content (C17: it writes
none). STEAL-22 closed by construction.

Residual note: TBT shows exactly Blizzard's CDM frame per cooldownID. If Blizzard's own CDM ever drew
one foreign aura on every item frame during a charm, the same thing would show in the unmerged CDM;
TBT neither reads nor copies that content and cannot add or remove it. The in-game check below
confirms the live behaviour.

## 999.21 -- charges after a spec change

Report: after Arcane to Frost, the merged Frost Orb cell showed 2 charges with none available, until
`/reload`.

Old path: TBT drew the merged charge count itself (`ApplyChargeCount`, from `ApplyCooldownSlot`),
from the sticky `chargeCapable` cache, only on a `_cdGen` change, and left the old text up whenever
`GetSpellCharges` was unreadable.

New path: TBT draws no merged charge count. A merged entry takes the re-anchor arm before the
cooldown-slot arm (`if reanchorHere and entry.isMerged`, Display.lua:1597, ahead of
`elseif ns:IsCooldownSlotEntry(entry)`, :1652), so `ApplyCooldownSlot` (its only call site, :1664)
and `ApplyChargeCount` never run for it; the pooled cell is hidden (`icon:Hide()`, :1614), so its own
charge string cannot show. The count on screen is Blizzard's own frame's. On a spec change,
`PLAYER_SPECIALIZATION_CHANGED` and `TRAIT_CONFIG_UPDATED` are in both `REFRESH_MIRROR` and
`REASSERT_VISIBILITY` (MergeMode.lua:1321-1353): the mirror rebuilds from the viewers' new item
frames, sets `mirrorChangedForPlacement`, and the shown pass renders then places (C8); `PlaceItem`
re-places any frame whose cooldownID changed (`placedID` stamp, MergeReanchor.lua:369), and the
viewer's own Layout post-hook re-places it the moment Blizzard re-lays it out (C9). STEAL-20.

## 999.22 and 999.23 -- another caster's debuff

Reports: 999.22, Freezing drawn over other cells in a centred Essential row (only with another Frost
Mage present); 999.23, the player's Touch of the Magi cell lit when another mage applied it.

Old path: the readable target lookup matched by spell name with `HARMFUL` / `HELPFUL` filters and no
player filter, so another caster's copy matched the player's entry, and the engine aura container it
drove was positioned independently of the cell grid.

New path: TBT reads no aura in Merge Mode (C12), so another caster's debuff cannot match the
player's entry: the cell shows Blizzard's frame for the player's own cooldownID, which is whatever the
unmerged CDM would show for it. Nothing can take another slot's cell: one id per cell and one cell
per id (C2, C3), unique cell positions including in a centred run (C3, C18), and only the
container's own viewer's frames (C5). STEAL-21.

## 999.25 -- Centered

Report: a Centered Tracked Buffs container holding only merged buffs did not re-centre, even after
a custom tracker was added.

Old path suspects: `seen == 0` read as "everything shown"; a parked viewer going stale; no re-render
on a `cdmShown` flip; engine-drawn aura containers keeping their old cell.

New path:
- `SlotDraws` returns `entry.cdmShown == true` for a merged entry (Display.lua:88-91), and the
  centred count and placement both go through it (:1562-1569, :1583-1587).
- `seen` counts ACTIVE frames, not shown ones (`CollectShownCooldownIDs`, MergeMode.lua:583-606).
  The viewer is parked but kept shown (`CaptureAndSuppress` only re-anchors, :1059-1104), so
  Blizzard keeps acquiring one frame per configured id and hiding the inactive ones
  (`RefreshLayout`, CooldownViewer.lua:2021-2031 -- intent), which keeps `seen > 0` outside preview;
  `cdmShown = (seen == 0) or shownCooldownIDs[...]` (MergeMode.lua:710) then reflects Blizzard's
  per-frame shown flag. Preview deliberately takes the `seen == 0` arm (it reads nothing, :694).
- The shown pass runs on `UNIT_AURA` for player and target (:1303) and the render runs every
  `UPDATE_INTERVAL` from the OnUpdate driver (Display.lua:727-735), so a `cdmShown` flip re-centres
  within one interval of the pass.
- Tracked Buffs publishes its whole configured set (`publishWhole`, MergeMode.lua:660, :722), so
  each entry keeps the same pooled cell index and `mergedCount > 0` keeps the container shown under
  Hide When Inactive (Display.lua:1504-1507) when it holds only merged buffs; a custom tracker is
  counted by the same `SlotDraws` chain.
- There is no engine aura container left to keep an old cell; the moved frame follows its cell's
  anchor.
- Accepted latency (Phase 68 IN-01, Display.lua:1602-1606): a merged buff that lands while its
  centred cell has no anchor appears one frame plus up to one interval late.

STEAL-23.

## Observations outside the merged path

- **Custom cooldown trackers still use the sticky `chargeCapable` cache** (Display.lua:197, written
  in `ApplyChargeCount` :1006, read at :1172). A user-added cooldown tracker whose spell stops being
  charge-capable after a respec keeps the charge branch, and an unreadable `GetSpellCharges` leaves
  the old text up (:997-999). Same shape as 999.21, but not a Merge Mode route; not changed here
  (STEAL-20's scope is the merged count). Backlog candidate.
- **A viewer TBT refused to park stays on-screen.** If `CapturePlacement` cannot read a viewer's
  anchors, `ns.mergePriorPlacement[global] = false` and the viewer is never moved
  (MergeMode.lua:1084-1091); frames TBT releases then show in Blizzard's own on-screen CDM. A
  duplicate in Blizzard's own grid slot, never over a TBT cell. Pre-existing, not a fan-out.
- **`ns.SPELL_CATEGORY_COMBAT_POTION`** (Core.lua) is still read by `Providers.lua:783`, the Pot
  meta-tracker's unresolved icon (`MetaItemPotProviderMixin:GetDisplayInfo`). The engine aura
  containers were one reader, not the only one. Keep it; it is NOT a cleanup-phase candidate.
  (Corrected after the 70 code review, WR-01; 70-04 and 70-05 had recorded it as readerless.)

## Routes found and fixed

None: every candidate is CLOSED. No source file was changed by this plan.

## Deferred in-game checks

For the testing phase (Phase 72). The TOC is unchanged in Phase 70, so `/reload` is enough.

- [ ] Arcane to Frost with Frost Orb merged: the cell shows the right charge count without `/reload`, and again after a talent loadout change.
- [ ] Another Frost Mage applying Freezing to the target: it never lights the player's Freezing cell and never overlaps another cell in a centred Essential row.
- [ ] Another mage's Touch of the Magi on the target does not light the player's Touch of the Magi cell.
- [ ] While mind-controlled: no merged cell shows a foreign aura and no two cells show the same debuff; compare with the unmerged CDM if possible.
- [ ] A Centered Tracked Buffs container holding only merged buffs re-centres as each buff comes and goes, and stays shown under Hide When Inactive.
- [ ] The same container with one custom tracker added re-centres when a merged buff ends.
- [ ] A merged buff landing in a centred container appears within a frame or two (the accepted latency), never at a screen corner.
- [ ] `/tbt merge` with Merge Mode on prints CDM Visibility, shown/visible/cell bits, no error; with Merge Mode off prints "Merge Mode is OFF".
- [ ] The old experiment slash word now opens TBT's settings, and after a logout SavedVariables no longer contain the experiment flag.
- [ ] Merge Mode still shows Blizzard's cooldowns, charges, aura timers, glows, pandemic and dispel borders on the moved frames.
- [ ] Reordering two entries inside the CDM settings window (same item count) moves both frames to their new cells within a frame or two (C7).
- [ ] Turning Merge Mode off returns every frame to Blizzard's CDM, nothing stays on a TBT container.
