# Phase 48: Pandemic Highlight in Merge Mode - Pattern Map

**Mapped:** 2026-09-24
**Touch points analyzed:** 7 (per orchestrator's mapping request)
**Analogs found:** 6 strong / 1 "no analog, genuinely new" (rendering — no prior TBT use of a
Blizzard virtual FX template by name)

## File Classification

| New/Modified surface | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| Pandemic stamp in `ns:RefreshMergeShownSlots` | event-driven stamping (read) | request-response (poll CDM frame, stamp entry) | `entry.cdmShown` stamp, `MergeMode.lua:786` | exact |
| Secret-guarded numeric read of `pandemicStartTime`/`pandemicEndTime` | utility / guard | transform | `aura.expirationTime`/`duration` guard, `MergeMode.lua:648-656` | exact |
| Pandemic highlight frame pool (icon) | utility / frame pool | CRUD (acquire/reset/release) | `section.itemPool` in `CDMTab.lua:753-768` | role-match (pool-with-reset idiom) |
| Pandemic highlight frame pool (bar) | utility / frame pool | CRUD | same as above; also `Display.lua` `GetBar`/`GetIcon` lazy 1:1 idiom (`Display.lua:531-549`) | role-match, two competing idioms — see §5 |
| Highlight render/toggle on mirrored icon | component (render) | request-response (Show/Hide per tick or per stamp change) | `RelayMergedBar`, `Display.lua:1476-1507` | role-match |
| `CreateFrame(..., "CooldownPandemicFXTemplate")` capability guard | utility / capability check | transform | `Enum.CooldownViewerCategory` / `Enum.CooldownSetSpellFlags` guards, `MergeMode.lua:43-54` | role-match |
| `/tbt debug` dump of the five unknowns | utility / logging | event-driven (print) | `LogItemUse`/`LogPlayerCast`, `Core.lua:1259-1302` | exact (protected, reference only) |

---

## Pattern Assignments

### 1. The pandemic read site — `ns:RefreshMergeShownSlots` (`MergeMode.lua:694-806`)

**Role:** event-driven stamping pass. **Data flow:** request-response — reads a cached CDM item
frame, stamps a plain field onto TBT's own `entry` table.

**Analog:** the function itself; specifically the `entry.cdmShown` stamp and its neighboring pcall.

**No-taint boundary:** the loop body only ever does `itemFrame.<field>` reads on a frame obtained
from `ns.mergeItemFrames` (populated by `CollectShownCooldownIDs`'s admitted `EnumerateActive`
walk) and writes fields on TBT's own `entry` table, never on the CDM frame. This is squarely on the
**permitted** side — plain table-field reads off a cached CDM frame, writes only to TBT-owned data.

**Core pattern — the stamp site** (`MergeMode.lua:780-803`):
```lua
for _, entry in ipairs(slots) do
	-- Stamped on EVERY entry, published or not: Display reads it to decide whether a
	-- merged aura takes a cell in a centred run. "seen == 0" is the no-answer case --
	-- no viewer, or a viewer with no item frames -- and there everything counts as
	-- shown, exactly as the publish filter below treats it.
	entry.cdmShown = (seen == 0) or (shownCooldownIDs[entry.cooldownID] == true)

	if engineOwns or seen == 0 or shownCooldownIDs[entry.cooldownID] then
		-- entry.hideAura is Blizzard's CanUseAuraForDisplay, stamped at mirror-build
		-- time: an entry flagged HideAura keeps its cooldown and never swaps to its
		-- aura, and skipping it here means two fewer aura lookups per event as well.
		if isAuraCategory and not entry.hideAura then
			-- pcall'd as a structural guarantee, not because a specific raise is
			-- expected: everything inside is already guarded. This pass wipes the
			-- shown-slot arrays before refilling them, so ANY raise partway through
			-- leaves every merged container empty until the next aura event -- which
			-- is exactly what the GetAuraDataByIndex raise did on 2026-09-22. The
			-- sweep is a nicety; the containers rendering is not.
			pcall(ResolveMergedAuraTiming, entry)
		end
		shown[#shown + 1] = entry
	end
end
```

**What to copy:** stamp the pandemic boolean (and, if built, the guarded numeric pair) as a
sibling of `entry.cdmShown` — same loop, same `entry` table, right where `ns.mergeItemFrames` is
already in scope via `entry.cooldownID`. Do **not** put the pandemic read inside the
`pcall(ResolveMergedAuraTiming, entry)` call — that pcall is scoped to aura-timing resolution only
and the comment's hazard applies to *this whole pass*, not specifically to that one call. Any new
work added directly in this loop **inherits the same hazard**: a raise here, unguarded, empties
`shown` for every category until the next aura event. Whatever reads `ns.mergeItemFrames[...]`
and stamps `entry.pandemic*` must be wrapped in its own `pcall`, exactly as `ResolveMergedAuraTiming`
is, for the same structural reason — not because a specific raise is anticipated from a frame
reference read, but because this pass cannot afford a raise from *anything* added to it.

**What NOT to copy:** the `isAuraCategory`/`hideAura`/`engineOwns` gating logic is specific to aura
timing resolution and buff-vs-cooldown ownership; the pandemic stamp should run unconditionally for
every entry that has a `cooldownID` (item-backed entries structurally never carry the signal per
PANDEMIC.md, so no extra category filter is needed — see PANDEMIC.md's "no filtering needed" note).

**`CollectShownCooldownIDs`** (`MergeMode.lua:478-500`), the source of `ns.mergeItemFrames`:
```lua
local function CollectShownCooldownIDs(viewer)
	local pool = viewer.itemFramePool
	if not pool or not pool.EnumerateActive then
		return 0
	end

	local seen = 0
	for itemFrame in pool:EnumerateActive() do
		seen = seen + 1

		-- Guarded before use, per the addon-wide rule, even though neither value is expected
		-- to be secret: a cooldownID that is unreadable simply does not join, and an
		-- unreadable shown flag is treated as not shown.
		local cooldownID = itemFrame.cooldownID
		if not issecretvalue(cooldownID) and type(cooldownID) == "number" then
			local isShown = itemFrame:IsShown()
			if not issecretvalue(isShown) and isShown == true then
				shownCooldownIDs[cooldownID] = true
				ns.mergeItemFrames[cooldownID] = itemFrame
			end
		end
	end

	return seen
end
```
**What to copy:** nothing needs to change here — this is exactly why "no new CDM surface is
needed." `ns.mergeItemFrames[cooldownID] = itemFrame` at `:497` is the cache the pandemic stamp
reads from.

**Backwards-trace caution (per CONTEXT.md's Phase 47 lesson):** `ns.mergeItemFrames` is wiped
unconditionally at the top of `ns:RefreshMergeShownSlots` (`:701`, `wipe(ns.mergeItemFrames)`) and
only repopulated when `ns.db.mergeMode == true` (the early return at `:703-705` skips repopulation
entirely when Merge Mode is off). Any pandemic-stamp code added inside the per-entry loop is safe
by construction because it only runs after that gate — but if pandemic-stamping is ever hoisted
into its own function called from elsewhere, it must not assume `ns.mergeItemFrames` is populated;
guard with the same `seen == 0` idiom (`:786`) the existing stamp already uses for "no answer."

---

### 2. Mirror-build-time stamps (`MergeMode.lua:363-376`)

**Role:** one-time-per-rebuild stamping (not per-refresh). **Data flow:** transform (raw CDM info
struct → plain fields on `entry`).

```lua
-- Phase 43.1: Blizzard's CanUseAuraForDisplay, resolved here rather
-- than at render time -- the flag cannot change without a mirror
-- rebuild, and reading it per frame would mean a bit.band per
-- merged slot per tick.
hideAura = HasCooldownFlag(info, HIDE_AURA),
-- Whether the CDM considers this a charge spell. A plain bool on
-- the info struct, read here at mirror-build time rather than from
-- C_Spell.GetSpellCharges at render time -- that call is
-- SecretWhenCooldownsRestricted, this field is not. Display uses it
-- to pick the recharge handle over the cooldown handle.
hasCharges = info.charges == true,
-- Blizzard's own flag, present in CooldownViewerCooldown but read
-- NOWHERE in their UI, so its meaning is inferred from its name
-- and has to be confirmed against real data before anything is
-- built on it. If it means "this entry's aura lands on the
-- caster", it is the discriminator that says which entries could
-- ever need a target container at all.
selfAura = info.selfAura == true,
```

**Why this is the wrong stamping point for pandemic:** these three fields come off the mirror's
static `info` struct (`C_CooldownViewer.GetCooldownViewerCooldownInfo`-class data), which is
rebuilt only when the mirror itself changes (spec/talent/config changes) — not once per refresh
event. The pandemic window is dynamic per-cast (it opens and closes continuously while the entry
is live), so it cannot be resolved here; it must be resolved at **shown-slot-refresh time** (touch
point 1), which runs on every relevant event. This is presented per the orchestrator's request so
the planner can see both stamping points and confirm the choice, not because it is a candidate
site — it is explicitly the wrong one for a time-varying signal.

---

### 3. Secret-guarded CDM field reads (`MergeMode.lua:648-656`)

**Role:** utility / guard. **Data flow:** transform (raw frame field → validated plain number or
`false`/early-return).

```lua
if not ns:CanReadTable(aura) then
	return false
end

-- Guarded individually even though ns:CanReadTable passed: a readable table can still carry
-- secret fields, and these two are about to be used in arithmetic.
local expiry = aura.expirationTime
local duration = aura.duration
if issecretvalue(expiry) or type(expiry) ~= "number" then
	return false
end
if issecretvalue(duration) or type(duration) ~= "number" or duration <= 0 then
	return false
end

entry.auraExpiry = expiry
entry.auraDuration = duration
```

**What to copy verbatim:** the two-line guard shape — `issecretvalue()` checked **before**
`type()`, on each field individually, even after a table-level `CanReadTable`/similar check has
already passed. Apply identically to both `pandemicStartTime` and `pandemicEndTime`:

```lua
local startTime = itemFrame.pandemicStartTime
local endTime = itemFrame.pandemicEndTime
if issecretvalue(startTime) or type(startTime) ~= "number" then
	-- fall back to boolean signal
elseif issecretvalue(endTime) or type(endTime) ~= "number" then
	-- fall back to boolean signal
else
	-- both readable: numbers win per CONTEXT.md's fixed precedence
end
```

**No-taint boundary:** plain table-field reads off a cached CDM frame (`itemFrame`, not `aura` —
same class of object, an item frame vs. an aura struct, same rule applies). Permitted.

**What NOT to copy:** the `duration <= 0` sanity check is specific to aura-duration semantics; the
pandemic window equivalent is `endTime > startTime` if a sanity check is wanted at all — not a
required copy, since `GetTime()` comparison against two independently-secret-checked numbers is
already safe.

---

### 4. `Display.lua` mirrored icon/bar widgets — attachment points and existing frame-level handling

**Role:** component (render). **Data flow:** request-response (per-frame `Show`/`Hide`/`SetPoint`
driven by stamped entry state).

**Icon frame creation** (`Display.lua:418-521`, `CreateTimerIcon`) — key sub-frames:
- `frame` — the icon's own top-level Frame, `BUFF_ICON_SIZE` × `BUFF_ICON_SIZE` (`:419-420`).
- `frame.icon` — the icon texture (`:423-424`).
- `frame.iconOverlay` — `CreateTexture`, `UI-HUD-CoolDownManager-IconOverlay` atlas, anchored
  `TOPLEFT -8,7` / `BOTTOMRIGHT 8,-7` around `frame` (`:432-435`) — this is TBT's existing analog
  for "an overlay anchored with negative/positive offsets around the icon," the same anchoring
  shape the pandemic icon FX needs (`-6/+6` per PANDEMIC.md).
- `frame.chargeCount` — `CreateFrame("Frame", nil, frame)`, created *after* `frame.cooldown` so it
  draws above the swipe, hidden by default (`:484-489`) — the established idiom for "a child frame
  that must sit above the cooldown swipe and starts hidden until it has an answer."
- `frame.mergedTime` — a merge-mode-specific overlay FontString, explicitly **not** parented to
  `chargeCount` because a hidden parent hides its children, given its own `OVERLAY` sublevel 7 to
  clear `iconOverlay` (`:491-506`). **This is the single most relevant precedent**: it is the exact
  prior instance of "a new merge-mode-only visual element added to the shared icon widget, parented
  directly to `frame`, with an explicit draw-layer/sublevel choice documented against exactly this
  hidden-parent hazard." The pandemic icon FX frame should follow the same shape: parent directly
  to the icon frame (or its own wrapper), not to a frame that might be hidden independently.

**Bar frame creation** (`Display.lua:316-407`, `CreateTimerBar`) — key sub-frames:
- `bar` — top-level Frame (`:317-318`).
- `bar.iconFrame` — left-side icon, `SetFrameLevel(bar:GetFrameLevel() + 2)` (`:321-324`) — an
  existing example of an explicit frame-level bump relative to the parent, the same idiom the
  pandemic bar highlight needs (`SetFrameLevel(bar:GetFrameLevel() + 1)` per PANDEMIC.md, though
  relative to the *bar's fill sub-region* specifically, not the top-level `bar` — see below).
- **`bar.statusBar`** — `CreateFrame("StatusBar", nil, bar)`, `SetFrameLevel(bar:GetFrameLevel() +
  1)` (`:354-358`). **This is the fill sub-region key the orchestrator asked to be reported.**
  Blizzard anchors its bar pandemic highlight to `cooldownItem.Bar` (the StatusBar child);
  `bar.statusBar` is TBT's exact structural equivalent — same role (the StatusBar that actually
  fills), same relative frame-level relationship to its parent (`+1` over the container). The
  pandemic bar FX frame's `SetFrameLevel(bar.statusBar:GetFrameLevel() + 1)` therefore lands one
  level above `bar.statusBar`, mirroring Blizzard's `cooldownItem.Bar:GetFrameLevel() + 1` exactly.
- `bar.fillTexture` — the actual StatusBar texture, `UI-HUD-CoolDownManager-Bar` atlas
  (`:363-365`) — confirms `bar.statusBar` is the analog of `cooldownItem.Bar`, not `bar.fillTexture`
  itself: Blizzard's own anchor override targets the StatusBar frame region (`cooldownItem.Bar`),
  not its inner fill texture.
- `bar.pip` — `CreateTexture(nil, "OVERLAY")` anchored relative to `bar.fillTexture` (`:374-376`)
  — another existing overlay-anchoring precedent, though this one tracks a moving point rather than
  a static border.

**Confirmation from the read side** — `RelayMergedBar` (`Display.lua:1476-1507`) reads
`itemFrame.Bar` directly (`:1479`, `local source = itemFrame and itemFrame.Bar`) as a plain
table-field read off the cached CDM item frame — independent confirmation that Blizzard's own bar
sub-region field is literally named `Bar` on the item frame, matching PANDEMIC.md's
`cooldownItem.Bar` citation. **No-taint boundary:** this read (`itemFrame.Bar`, then
`source:GetMinMaxValues()`/`source:GetValue()`) is a plain C widget getter call on a CDM-owned
StatusBar region — permitted under the same rule as `itemFrame:IsShown()` in touch point 1. It is
**not** a mixin method; `GetMinMaxValues`/`GetValue` are plain StatusBar C getters, not
`CooldownViewerItemMixin` methods.

**What to copy:** the anchoring/frame-level relationship (`bar.statusBar` as the fill sub-region,
`+1` frame level above it), and the "parent directly to the specific widget it decorates, pick an
explicit draw-layer/sublevel, document why" idiom from `frame.mergedTime`.

**What NOT to copy:** `frame.mergedTime`/`RelayMergedBar` are themselves data-relay code (text and
StatusBar value passthrough) — the pandemic FX frame carries no data, only `Show()`/`Hide()`
toggling per PANDEMIC.md's "toggle purely with Show()/Hide()" note, so none of the relay logic
itself is relevant, only the parenting/layering shape.

---

### 5. Existing frame pooling in TBT — two competing idioms, report both

**(a) `CreateObjectPool` with reset callback — `CDMTab.lua:753-768`:**
```lua
section.itemPool = CreateObjectPool(function(pool)
	return CreateIconFrame(section.container)
end, function(pool, frame)
	frame:Hide()
	frame.spellID = nil
	frame.sectionName = nil
	frame.layoutIndex = nil
	-- Phase 46 (S10): a pooled frame keeps its previous tile's charge count. Clearing it
	-- here, once, covers both acquisition paths -- a freshly created frame is already
	-- hidden by CreateIconFrame's own f.chargeCount:Hide(), and a recycled frame is
	-- cleared by ReleaseAll() running this reset function at the top of every
	-- ns:RefreshTBTSections pass. The discipline lives here, not in the itemPool:Acquire()
	-- call sites -- each tile loop only needs to Show()/SetText() when a count applies.
	frame.chargeCount.Current:SetText("")
	frame.chargeCount:Hide()
end)
```
Acquire/release usage sites: `section.itemPool:Acquire()` (`CDMTab.lua:869`, `:902`, `:948`,
`:980`), full-sweep `section.itemPool:ReleaseAll()` (`:815`, `:1599`), and iteration via
`section.itemPool:EnumerateActive()` (`:492`, `:585`). This is a true acquire/release pool: frames
come and go across refresh passes, count varies.

**(b) Hand-rolled 1:1 lazy index pool — `Display.lua:531-549`:**
```lua
local function GetBar(key, index)
	local pool = pools[key]
	if not pool[index] then
		local bar = CreateTimerBar(ns.containers[key])
		bar.containerKey = key
		pool[index] = bar
	end
	return pool[index]
end

local function GetIcon(key, index)
	local pool = pools[key]
	if not pool[index] then
		local frame = CreateTimerIcon(ns.containers[key])
		frame.containerKey = key
		pool[index] = frame
	end
	return pool[index]
end
```
No `Acquire`/`Release`/`ReleaseAll` at all — created once per `(containerKey, index)` slot, kept
forever, reused in place, visibility controlled entirely by `Show()`/`Hide()` elsewhere in the
render pass. This is the idiom every existing bar/icon widget in Display.lua already uses.

**Recommendation for the planner (mapping, not deciding):** since the pandemic highlight frame is
always a 1:1 child of an already-pooled bar/icon widget (one highlight frame per bar or icon slot,
never more, never independent of the slot's lifetime), the closer structural analog is **(b)** —
lazily create-once and cache directly on the bar/icon widget itself (e.g.
`bar.pandemicFrame`/`frame.pandemicFrame`, created on first need, toggled with `Show()`/`Hide()`
thereafter) — rather than standing up a separate `CreateObjectPool` with acquire/release semantics
that would need its own count-tracking independent of the bar/icon pool it shadows. CONTEXT.md's
Claude's Discretion note ("Pool TBT's own instances with CreateFramePool in the same idiom TBT
already uses") is satisfied by either reading of "the idiom TBT already uses" — this codebase has
both; (a) is the literal `CreateFramePool`-family idiom, (b) is the dominant idiom for anything
1:1 with a mirrored bar/icon slot specifically. Two templates (icon FX, bar FX) argues for two
lazy fields, one per widget type, following (b) — not two `CreateObjectPool` instances, since (a)'s
value (tracking an *unbounded, varying-count* set of active frames across sweeps) does not apply
here: the count is always exactly 1 per existing bar/icon slot.

**No-taint boundary:** both (a) and (b) create and parent frames that are TBT-owned from
`CreateFrame` up — squarely permitted. Neither touches a CDM frame's pool.

---

### 6. `pcall`-guarded capability check — `MergeMode.lua:43-54`

**Role:** utility / capability check. **Data flow:** transform (probe availability, degrade to nil
rather than error).

```lua
-- than a load-time error on a client without Enum.CooldownViewerCategory.
	return Enum.CooldownViewerCategory and def.cdmCategoryName and Enum.CooldownViewerCategory[def.cdmCategoryName]
...
local HIDE_BY_DEFAULT = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault
...
local HIDE_AURA = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideAura
```

**What to copy — the shape, not the mechanism:** this specific example is a short-circuit `and`
chain against `Enum` tables (guards against a missing *enum*, evaluated once at file load). The
pandemic case guards against a missing **virtual XML template**, which cannot be probed ahead of
time (no `Enum`-style existence check exists for template names) — so per PANDEMIC.md's own
"Absence-of-template guard" section, the correct mechanism is `pcall` around the `CreateFrame` call
itself, not an `and`-chain:
```lua
local ok, fxFrame = pcall(CreateFrame, "Frame", nil, parent, "CooldownPandemicFXTemplate")
if not ok or not fxFrame then
	-- degrade to "no highlight"
end
```
The shared idiom being copied across both is: **structural capability check, evaluated once (or
once per attempt), degrading silently to "feature off" rather than erroring** — same spirit as
`Enum.CooldownViewerCategory and ...`, applied via `pcall` because the failure mode here (an
unrecognized template name) raises rather than returning nil/false.

**Second precedent, same file, already `pcall`-based and closer in mechanism** —
`MergeMode.lua:746` (inside `ns:RefreshMergeShownSlots`, already excerpted in touch point 1):
```lua
local ok, count = pcall(CollectShownCooldownIDs, viewer)
if ok and not issecretvalue(count) and type(count) == "number" then
	seen = count
end
```
This is the more directly applicable analog for the template-instantiation guard: `pcall` wrapping
a call that might raise, checked with `ok and <value sanity check>`, falling through to an
already-established "no answer" default on failure. Use this shape for
`CreateFrame(..., "CooldownPandemicFXTemplate")`.

---

### 7. `/tbt debug` logging — `Core.lua` (PROTECTED — reference only, do not modify)

**Role:** utility / logging. **Data flow:** event-driven (print on trigger).

**Gate** (`Core.lua:1056-1057`, `:1260`, `:1283`, and five more sites):
```lua
ns.debugLogging = not ns.debugLogging
local state = ns.debugLogging and "|cff00ff00ON|r" or "|cffff6600OFF|r"
...
local function LogItemUse(itemID)
	if not ns.debugLogging then
		return
	end
```
The gate is a single module-level boolean, `ns.debugLogging`, toggled by the `/tbt debug` slash
command and checked with a guard-clause early-return at the top of every logging function — never
an `if ns.debugLogging then ... end` wrapping a whole body.

**One representative print** (`Core.lua:1273-1277`):
```lua
local line = "|cff00ccffTBT Debug|r: |cffffd100ITEM|r " .. (ItemName(itemID) or "?") .. " — itemID " .. itemID
if spellID then
	line = line .. ", casts spellID " .. spellID
end
print(line)
```
Color-coded prefix `|cff00ccffTBT Debug|r:`, a category tag in a second color
(`|cffffd100ITEM|r` / `|cff40ff40SPELL|r`), then plain concatenated fields — no string.format,
plain `..` concatenation throughout.

**Guard helpers used before any value reaches a print** (`Core.lua:1210-1222`):
```lua
local function SafeNumber(value)
	if issecretvalue(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

local function SafeString(value)
	if issecretvalue(value) or type(value) ~= "string" then
		return nil
	end
	return value
end
```
Every value bound for a debug print is screened through one of these first — the same
`issecretvalue()`-before-`type()` order as elsewhere, applied specifically so a debug dump itself
never raises.

**What the new debug dump for PANDEMIC.md's five unknowns should copy:** the gate
(`if not ns.debugLogging then return end`), the color-coded print format, and — critically — the
`SafeNumber`/`SafeString`-style screening before printing `issecretvalue(...)` and `type(...)`
results for `pandemicStartTime`/`pandemicEndTime` (Unknown #2 explicitly asks to dump
`issecretvalue()` and `type()` themselves, which is safe to print directly since those two calls
never themselves raise or return a secret — they are exactly the introspection functions used to
detect one).

**PROTECTED:** this block (`Core.lua:1172-1303` and the four hook sites at `:1325-1365`) must not
be modified by this phase's plan. A new print for the pandemic unknowns is a new call site
elsewhere (most naturally inside the `ns:RefreshMergeShownSlots` stamping pass or its own debug
helper in `MergeMode.lua`/`Display.lua`), gated by the same `ns.debugLogging` global, not an edit
to this file's existing functions.

---

## Shared Patterns

### Secret-value guard order
**Source:** `MergeMode.lua:650-656`, `Core.lua:1210-1222`
**Apply to:** every read of `itemFrame.PandemicIcon`... — actually `PandemicIcon` is a **frame
reference**, not a data field, and per CONTEXT.md's own signal decision does *not* need this guard
(`issecretvalue` applies to numeric/string data, not frame references) — apply the guard only to
`pandemicStartTime`/`pandemicEndTime`, and to any value destined for the new debug dump.
```lua
if issecretvalue(value) or type(value) ~= "number" then
	-- degrade / return nil
end
```
Always `issecretvalue()` before `type()`, never the reverse — stated identically in three places
across the codebase (`MergeMode.lua`, `Core.lua`, `CLAUDE.md`'s "guard Secret Value usages" rule).

### `pcall` as a structural guarantee inside a wipe-then-refill pass
**Source:** `MergeMode.lua:793-799` (comment) and `:746`
**Apply to:** whatever code in `ns:RefreshMergeShownSlots` reads `ns.mergeItemFrames[...]` for the
pandemic stamp, and the `CreateFrame(..., "CooldownPandemicFXTemplate")` instantiation.
Both are pcall'd not because a specific raise is expected, but because the surrounding pass (or,
for the template case, the total absence of an existence-probe API) makes silent degradation
strictly better than letting an exception propagate.

### Pool-then-reuse widget idiom
**Source:** `Display.lua:531-549` (dominant), `CDMTab.lua:753-768` (alternate, unbounded-count case)
**Apply to:** the pandemic FX frames — see touch point 5 for the recommendation between the two.

### `Enum`/table-existence short-circuit for optional Blizzard surface
**Source:** `MergeMode.lua:43-54`
**Apply to:** anywhere a Blizzard enum or table might not exist on a given client; not directly
applicable to the FX-template guard (use the `pcall` idiom instead), but the same
degrade-don't-error philosophy underlies both.

## No Analog Found

| Surface | Role | Data Flow | Reason |
|---|---|---|---|
| `CreateFrame(..., "CooldownPandemicFXTemplate")` / `"CooldownPandemicBarFXTemplate"` instantiation | component (render) | request-response | TBT has never instantiated a Blizzard **virtual FX/animation template by name** before — every existing `CreateFrame` call in `Display.lua` builds a plain `Frame`/`StatusBar`/`Cooldown` from scratch or uses `CooldownFrameTemplate` (a functional cooldown widget, not a decorative FX template). This is genuinely new surface; the closest available precedent is the `pcall`-wrapped-capability-check *shape* (touch point 6), not a prior instance of the same operation. |
| `AnimateWhileShownTemplate`-driven Show/Hide-triggered animation | component | event-driven | No existing TBT frame relies on an inherited template's own `OnShow`/`OnHide` animation lifecycle — TBT's existing animations (if any) are not present in the files read for this phase. Treat PANDEMIC.md's own description (Show/Hide toggling is sufficient, no controller code needed) as authoritative since no local counter-example exists. |

## Metadata

**Analog search scope:** `MergeMode.lua`, `Display.lua`, `Core.lua`, `CDMTab.lua`,
`EditModeFrames.lua` — full-file line-range Reads and targeted Greps, no directory walk needed
(flat repo-root source layout, ~9550 total Lua lines across 6 files).
**Files scanned:** 6 Lua source files (all existing TBT source), 2 planning docs
(`48-CONTEXT.md`, `.planning/research/PANDEMIC.md`), `CLAUDE.md`.
**Pattern extraction date:** 2026-09-24
