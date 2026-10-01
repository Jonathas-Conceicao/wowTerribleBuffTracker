# Phase 62: New Icons - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning
**Mode:** Autonomous run 61-63; every question for the range was asked up front on 2026-09-30. None
fell in this phase — the art, folder layout and converter were settled with the user before kickoff.

<domain>
## Phase Boundary

TBT's tabs draw TBT's own icons, and the textures reach every client and every release
(TAB-08, TAB-09, INST-10, DIST-13):

- CDM tabs: **TBT Cooldowns → `icon_cooldown`**, **TBT Buffs → `icon_buff`**, **TBT Reminders →
  `icon_reminder`**.
- Tracker dialog side tabs: **General → `icon_info`**, **Advanced → `icon_advanced`**.
- `install.ps1` deploys `Media/Textures`, `.pkgmeta` keeps `Media/Source` out of the zip, and the
  already-written `Media/` art plus `scripts/png2blp.js` get committed.

</domain>

<decisions>
## Implementation Decisions

### Art and files (settled before kickoff, 2026-09-30)
- `Media/Source/*.png` — the user's 64x64 source art (palette PNGs), **not shipped**.
- `Media/Textures/*.blp` — **already generated** by `node scripts/png2blp.js`: uncompressed BLP2
  BGRA8888, 8-bit alpha, full mip chain (7 levels), verified pixel-exact against the PNGs. These are
  the shipped files. Regenerate with `node scripts/png2blp.js` only if a PNG changes.
- Both folders and `scripts/png2blp.js` are **untracked** at kickoff — commit them in this phase.
- Texture paths in Lua: `"Interface\\AddOns\\TerribleBuffTracker\\Media\\Textures\\icon_cooldown"`
  (no extension), as the existing `ICON_PATH` does.
- **The TBT logo stays exactly where it is**: `tbt_icon_64x64.blp` in the repo root, on the TOC
  `## IconTexture:` and `Config.lua`'s settings panel. Only CDM tab usage of `ICON_PATH` changes; if
  `ICON_PATH` in `CDMTab.lua` ends up unused, remove it.

### CDM tabs (TAB-08)
- `SetUpTBTTab(tab, label, category)` (`CDMTab.lua` ~3283) gains the icon path as a parameter; the
  three calls in `ns:InitCDMTab` (~3324) pass their own icon. Keep the existing `SetChecked` override
  (it re-sets the texture and toggles `SelectedTexture`); same icon in both states, as Blizzard's own
  CDM tabs use the same atlas for active and inactive. Icon size stays 30x30.

### Dialog side tabs (TAB-09)
- `SIDE_TAB_GENERAL_ICON` (`INV_Misc_Book_09`), `SIDE_TAB_ADVANCED_ATLAS` (`GM-icon-settings`) and
  `SIDE_TAB_ADVANCED_FALLBACK` (`Trade_Engineering`) are removed, along with the
  `C_Texture.GetAtlasInfo` gate and the atlas branch (~2416-2460). Both tabs use a plain
  `SetTexture` of the new file at `DIALOG_SIDE_TAB_ICON_SIZE` (30). A file texture needs no
  per-flavour guard: it ships with the addon.

### Install (INST-10)
- `install.ps1` derives its file set from the TOC load list, XML `file=` references and the
  `## IconTexture:` icon. Add a **fourth source**: every `*.blp` / `*.tga` under `Media/Textures`
  (recursive), added to `$files` as a repo-relative path.
- **Path-separator trap:** the prune loop builds `$rel` with backslashes
  (`Media\Textures\icon_buff.blp`) and checks `$files -notcontains $rel`. The new entries must use
  the same separator, or every texture is copied and then immediately pruned. Normalise one way and
  prove it by a real install run (deploy, re-run: nothing pruned; delete a texture from the repo,
  re-run: it is pruned).
- The copy loop already creates subdirectories.

### Release (DIST-13)
- `.pkgmeta` `ignore:` gains `Media/Source`. `Media/Textures` ships by default (the packager ships
  everything not ignored). The existing `"*.png"` rule is not relied on for this.
- `.github/workflows/release.yml` needs no change unless it enumerates files — check.
- Verify DIST-13 statically (no tag push in this phase): the ignore list excludes `Media/Source` and
  nothing excludes `Media/Textures`.

### Claude's Discretion
- Whether `SetUpTBTTab` takes the path or an icon key.
- One plan or two (code vs scripts).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CDMTab.lua:7` `ICON_PATH`; `SetUpTBTTab` ~3283; `ns:InitCDMTab` ~3319.
- `CDMTab.lua` ~2383 `DIALOG_SIDE_TAB_ICON_SIZE = 30`; ~2416-2460 side-tab icon constants and
  `ns:CreateDialogSideTab`; ~2721 the General/Advanced tabs are created.
- `scripts/install.ps1` ~30-60 file-set derivation, ~90-115 copy + prune.

### Established Patterns
- Replaced `SidePanelTabButtonMixin:SetChecked` so a file texture is never wiped by `SetAtlas`.
- New files on disk need a **full client restart** to be seen by WoW, not `/reload`.

### Integration Points
- `.pkgmeta` ignore list; `.github/workflows/release.yml`.

</code_context>

<specifics>
## Specific Ideas

- The user checked the 32px mips side by side (stopwatch, bolt, bell, book, gear) before kickoff.
- In-game checks are deferred to Phase 66. Deploy with `./scripts/install.bat` at the end.

</specifics>

<deferred>
## Deferred Ideas

- Moving the TBT logo into `Media/` — declined at kickoff; it stays in the repo root.

</deferred>
