---
phase: 62-new-icons
reviewed: 2026-09-30T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - CDMTab.lua
  - scripts/install.ps1
  - .pkgmeta
  - scripts/png2blp.js
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: fixed
fixed_at: 2026-09-30
fixes:
  WR-01: fixed (99e483c)
  WR-02: fixed (b441cfb)
  WR-03: fixed, per orchestrator decision (c4f0d67)
  IN-01: fixed (cbddcd7)
  IN-02: skipped (out of fix scope)
  IN-03: skipped (out of fix scope)
---

# Phase 62: Code Review Report

**Reviewed:** 2026-09-30
**Depth:** standard
**Files Reviewed:** 4
**Status:** fixed (WR-01, WR-02, WR-03, IN-01 fixed; IN-02, IN-03 skipped as out of scope)

## Summary

Reviewed `git diff 15ae927` for `CDMTab.lua`, `scripts/install.ps1` and `.pkgmeta`, plus the whole of the new `scripts/png2blp.js`.

**What was checked and holds up:**
- **CDMTab.lua.** No old code is left behind. `ICON_PATH`, `SIDE_TAB_GENERAL_ICON`, `SIDE_TAB_ADVANCED_ATLAS`, `SIDE_TAB_ADVANCED_FALLBACK`, `ns:SetAdvancedSideTabIcon` and the `C_Texture.GetAtlasInfo` gate are all gone, with zero references left in any `.lua`, `.xml` or `.toc`.
  - `ns:CreateDialogSideTab` gained `iconPath` as its 3rd parameter. Both of its callers (lines 2710 and 2712) were updated, and there are no other callers.
  - The five texture constants are file-scope locals at lines 9-13, declared above every use, so the upvalue-order trap does not apply.
  - No per-frame work was added. `stylua --check` passes.
- **Textures.** All five `Media/Textures/*.blp` files are tracked with `-text` (because `*.blp binary`). Each is 23016 bytes, which matches the expected size: a 1172-byte header plus a 64x64 BGRA mip chain of 7 levels. I re-ran `png2blp.js` into a scratch copy, and its output is byte-identical to the committed BLPs.
- **BLP2 header.** The layout is correct: offsets at 20..83, sizes at 84..147, a 1024-byte palette, and compression 3 / alphaDepth 8 / alphaType 8.
- **install.ps1 prune loop.** The texture entries are built exactly the way the prune loop builds `$rel`: `FullName.Substring(root.Length).TrimStart('\')` with backslashes. `-notcontains` is case-insensitive. So a deployed texture cannot be pruned as stale.
- **.pkgmeta.** `Media/Source` is ignored, nothing ignores `Media/Textures`, and `release.yml` does not list files.

No blockers. The findings below are about robustness: the converter can quietly write a broken texture, and dev installs can differ from what a release ships.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: png2blp.js ignores `tRNS` transparency for RGB (colour type 2) PNGs

**File:** `scripts/png2blp.js:81`
**Issue:** An RGB PNG (type 2) can mark one colour as transparent through a `tRNS` chunk, which holds three 16-bit samples. The decoder reads `tRNS` (line 41) but only uses it for types 0 and 3. For type 2 it always sets `al = 255`. If an icon is saved as truecolour-with-colour-key, a common output of pixel editors and optimisers, it converts without an error. The result is an opaque square: the transparent background turns into a solid colour inside a 30px tab icon. The current five sources are palette PNGs, so the shipped textures are fine. The script's header comment says it handles "any colour type", though, so the next icon could hit this.
**Fix:**
```js
else if (type === 2) {
	const key = trns && trns.length >= 6
		&& trns.readUInt16BE(0) === s[0] && trns.readUInt16BE(2) === s[1] && trns.readUInt16BE(4) === s[2];
	[r, g, bl, al] = [s[0], s[1], s[2], key ? 0 : 255];
}
```

**Resolution:** Fixed in `99e483c`. Type 2 now compares each pixel against the three 16-bit tRNS samples and sets alpha 0 on a match. Tested with a 2x2 RGB PNG whose key colour is magenta: key pixels come out with alpha 0 and the others with 255. The five shipped BLPs regenerate byte-identical.

### WR-02: png2blp.js turns a malformed PNG into a corrupt BLP instead of failing

**File:** `scripts/png2blp.js:51-73`
**Issue:** There are two ways bad input slips through without an error:
- **Unknown filter byte.** If a scanline's filter byte is greater than 4, the chain at lines 62-71 does nothing, and the row is decoded as filter 0.
- **Short decompressed data.** If `raw` is shorter than `h * (stride + 1)`, which happens with a truncated file or a wrong IHDR size, `line[x]` is `undefined`. `undefined + a` is `NaN`, and `NaN & 255` is `0`. The missing rows silently become transparent black.

In both cases the script prints its normal `-> ... (64x64, 7 mips)` line and writes a broken texture. Nobody would notice until an in-game check, and this project defers those to a later phase (Phase 66).
**Fix:** Check the data before decoding:
```js
if (raw.length < h * (stride + 1)) fail(file + ": image data truncated");
// inside the row loop:
if (filter > 4) fail(file + ": invalid filter type " + filter + " on row " + y);
```

**Resolution:** Fixed in `b441cfb`, as suggested. Both checks exit 1 and name the file. Tested with a PNG that uses filter byte 7 and with one whose IDAT is 4 bytes short. `node scripts/png2blp.js` still leaves `git status --short Media/` empty.

### WR-03: install.ps1 deploys every texture on disk, so a dev install can show icons that a release will not ship

**File:** `scripts/install.ps1:65-71` (also `scripts/png2blp.js:172-177`)
**Issue:** The new fourth source adds every `.blp`/`.tga` found under `Media\Textures`, whether or not it is committed and whether or not any Lua references it. The BigWigs packager ships only what git tracks. This can go wrong in three ways:
- **Uncommitted texture.** A newly converted BLP that was never committed shows up correctly in every local client, but a real release draws a green/missing square.
- **Orphaned BLP.** `png2blp.js` never deletes a BLP whose PNG was removed or renamed. The orphan keeps being deployed, and if it is tracked, keeps being released.
- **Path typo in Lua.** Nothing checks that the five paths in `CDMTab.lua` match a real file. A typo only shows up in-game.

Before this phase, every other part of the file set was derived from the TOC, which is the same source of truth the packager uses. This source breaks that.
**Fix:** Build the texture list from what git tracks, so the dev install and the release are the same set:
```powershell
$tracked = & git -C $source ls-files -- 'Media/Textures/*.blp' 'Media/Textures/*.tga'
if ($LASTEXITCODE -eq 0 -and $tracked) {
    foreach ($t in $tracked) { $texRel = $t -replace '/', '\'; if ($files -notcontains $texRel) { $files.Add($texRel) } }
} else { <# fall back to the current Get-ChildItem walk #> }
```
Optionally, also warn about any `Media\Textures` file that is on disk but not tracked. It would also help if `png2blp.js`, when run with no arguments, reported any `.blp` in `Media/Textures` that has no matching PNG.

**Resolution:** Fixed in `c4f0d67`, using the orchestrator's decision instead of the git-only list. Untracked textures still deploy, because TOC-listed Lua files deploy untracked too and the user tests new art before committing it.
- `install.ps1` prints `WARNING: <file> is not tracked by git - it will not be in a release` for each `Media\Textures` file that `git ls-files` does not list. If git is unavailable, it skips the warning silently.
- `png2blp.js` warns about any `Media/Textures/*.blp` that has no matching PNG in `Media/Source`. It never deletes anything.

Both were tested with a temporary untracked `tbtfix_orphan.blp`. After that file was removed, the next install pruned it from every client. The path-typo part is not addressed; the in-game check in Phase 66 covers it.

## Info

### IN-01: The missing-file error blames the TOC for texture entries

**File:** `scripts/install.ps1:73-76`
**Issue:** The existence check now also covers texture entries, but its message still reads "`$tocName references $f`". Texture entries come from a directory walk, not the TOC. In practice this cannot fire for them, since they were just listed from disk. If WR-03's git-based list is adopted, though, a tracked file that was deleted locally would trigger it with a misleading message.
**Fix:** Change the wording to "`the file set includes $f`", or track which source added each entry.

**Resolution:** Fixed in `cbddcd7`. The message now reads "the file set includes $f, which does not exist in $source".

### IN-02: The prune loop removes files but never empty directories

**File:** `scripts/install.ps1:117-125`
**Issue:** This phase adds the first subdirectory to the deployed file set. If `Media\Textures` is ever renamed or emptied, the loop prunes the files but leaves empty `Media\Textures` (and `Media`) directories in every client's AddOns folder. The deployed folder then no longer exactly matches the source.
**Fix:** After the file loop, remove empty directories, deepest first:
```powershell
Get-ChildItem -LiteralPath $dest -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item -Force
```

**Resolution:** Skipped. It is out of the fix scope (warnings, plus IN-01 as a trivial fix).

**Phase 65:** Fixed in `a860d0e`. install.ps1 prunes empty directories deepest first after the file prune, proven with a real install and a probe folder in every client.

### IN-03: png2blp.js edge cases in how it handles input

**File:** `scripts/png2blp.js:166-174`
**Issue:**
- If `Media/Source` is missing, `fs.readdirSync(srcDir)` throws a raw ENOENT stack trace instead of going through `fail()`.
- Explicit arguments are written to `Media/Textures/<basename>.blp`, so two inputs with the same basename from different folders silently overwrite each other.
- The signature check only looks at bytes 1-3.
**Fix:**
- Check `fs.existsSync(srcDir)` and call `fail()` if it is missing.
- Reject duplicate output basenames.
- Compare all 8 signature bytes (`89 50 4E 47 0D 0A 1A 0A`).

**Resolution:** Skipped. It is out of the fix scope (warnings, plus IN-01 as a trivial fix).

**Phase 65:** Fixed in `956feb8`. A missing Media/Source goes through `fail()`, duplicate output names are rejected before any write, and the full 8-byte signature is checked. The shipped BLPs regenerate byte-identical.

---

_Reviewed: 2026-09-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
