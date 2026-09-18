# Pitfalls Research: Adding WoW Forever Support to a Shipping Addon

**Domain:** WoW addon cross-flavor packaging (adding a second game-type TOC to an existing single-flavor retail addon shipping on CurseForge/Wago/GitHub)
**Researched:** 2026-09-18
**Confidence:** HIGH for packager/TOC mechanics (verified against `BigWigsMods/packager` source directly); MEDIUM for CurseForge/Wago live data state (endpoints not queryable without API tokens, which are currently disabled); LOW/anecdotal where explicitly marked

All packager behavior below was verified by downloading and reading
`https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh`
directly (not summarized secondhand) on 2026-09-18, at commit `e50a250f`
(tag `v2.6.1`, which is what `TerribleBuffTracker`'s `.github/workflows/release.yml`
resolves via the floating `BigWigsMods/packager@v2` tag). Forever/Camelot support
landed in that repo via PR #202, **merged 2026-09-17 — the day before this research**,
and the WoW Forever beta itself began 2026-09-17. Treat every packager-side finding
below as freshly-landed and re-verify against `release.sh` if this milestone slips
more than a few weeks, since a reviewer on PR #202 originally asked for Forever
detection to be *removed* pending "solid confirmation" from Blizzard on the TOC
convention — it was re-added once confirmed, but the convention was genuinely in
flux within the last 24 hours of writing.

## Critical Pitfalls

Ranked by consequence. Pitfalls 1–2 can break the **existing retail install** and are
release blockers. Pitfalls 3+ are scoped to the **new Forever target** or to
**process/tooling** and do not regress retail if handled correctly.

---

### Pitfall 1: The rename trap — deleting the working retail TOC identity

**What goes wrong:**
`git mv TerribleBuffTracker.toc TerribleBuffTracker_Mainline.toc` looks like a pure
rename, but it changes what every existing retail client resolves as "the addon's
TOC." If anything about the new suffixed file is wrong — filename casing, a stray
extra suffix, an interface number outside the retail range, or the file simply
missing from the packaged zip — existing users get one of three regressions on
their next update, with **no error dialog for any of them**:
- Addon vanishes from the AddOns list entirely (client never resolves a TOC for the
  folder) — indistinguishable at a glance from "user disabled it."
- Addon shows in the list but flagged "out of date" and unloaded (suffix resolved,
  but the `## Interface:` value inside `_Mainline.toc` didn't pass validation).
- Addon loads, but `TerribleBuffTrackerDB` looks "reset" to users — not actually a
  data loss (SavedVariables are keyed by folder name, not TOC filename, so the file
  itself is untouched), but if the addon silently fails to load at all, users
  reasonably report "lost my settings" when what actually happened is "the addon
  never re-registered its DB reference this session."

**Why it happens:**
The retail flavor-suffix convention (`_Mainline.toc` / `-Mainline.toc`) has been
supported by the client since Patch 9.1.0 (Shadowlands, 2021 — verified via
warcraft.wiki.gg TOC_format), so for any *current* Midnight client this rename is
routine and low-risk **when done correctly**. The trap is procedural, not
technical: a rename done as part of a larger multi-file commit, without a
same-session in-game reload check on the actual retail client, ships a typo or an
interface mismatch straight to users who have zero visibility into why the addon
disappeared.

**How to avoid:**
1. Do the rename as its own isolated commit, before any other v0.3 change lands.
2. Immediately after, run `install.bat` and `/reload` on a real retail Midnight
   client (not just a code review) and confirm:
   - `TerribleBuffTracker` still appears in the AddOns list, enabled.
   - The Core.lua `ADDON_LOADED` chat print ("TerribleBuffTracker loaded...")
     still fires — this print is a free, already-existing smoke test.
   - `/tbt` still opens the CDM tab.
3. **Keep an unsuffixed `TerribleBuffTracker.toc` alongside the two suffixed TOCs**,
   at least through the first Forever-compatible release. Verified from
   `release.sh`: the TOC-discovery loop globs for
   `$package{,-Mainline,_Mainline,...,-Camelot,_Camelot}.toc` and adds **every
   file that exists** to `toc_paths` — there is no conflict, no "ambiguous" error,
   and no preference logic between an unsuffixed and a suffixed TOC when
   `package-as` is explicitly set in `.pkgmeta` (TBT's already is:
   `package-as: TerribleBuffTracker`). The "Ambiguous addon name" hard error in
   `release.sh` only fires when `package` is auto-detected from the shortest
   `*.toc` glob match *and* that shortest name itself carries a flavor suffix —
   irrelevant here because `package-as` bypasses that auto-detection entirely.
   Net effect: shipping all three TOCs costs nothing at packaging time and gives
   every already-installed retail client a fallback path if the `_Mainline`
   suffix resolution ever misbehaves on an edge-case client. Remove the
   unsuffixed TOC in the milestone's cleanup phase once both flavors have been
   verified in-game for at least one release cycle.
4. Never let the rename and the Forever-specific TOC creation land in the same
   commit as unrelated shared-source edits — isolate it so `git bisect` or a
   revert is a single clean action if users report the addon missing.

**Warning signs:**
- Any CI packaging run where the zip's file listing doesn't show exactly the
  expected TOC files (diff the archive contents against a known-good list).
- A retail in-game test where the AddOns list count doesn't match expectations
  after `install.bat`.
- User bug reports of the form "addon disappeared after update" — treat these as
  TOC-resolution issues first, not data-loss issues, given SavedVariables survive
  independently of TOC changes.

**Phase to address:** First phase of the milestone (the TOC-split phase itself,
i.e. the phase implementing the target feature "Split flavor TOCs"). This must be
verified on real retail hardware before any other v0.3 phase proceeds — it is a
gate, not a parallel task.

---

### Pitfall 2: Interface-version drift silently diverging the two flavors, then hard-failing the packager at the worst time

**What goes wrong:**
With two TOCs, every future patch-version bump (routine Midnight point releases,
Forever beta build bumps) must touch both files. Miss one and:
- If the mismatch is just "forgot to bump," the stale flavor's interface number is
  wrong and that flavor starts showing "out of date" for its users — silent until
  a user reports it.
- If the mismatch is worse — e.g. someone pastes the wrong interface number into
  the wrong file, giving `TerribleBuffTracker_Camelot.toc` a `12xxxx` retail-range
  interface, or `_Mainline.toc` a `16xxx` value — the **packager hard-errors the
  entire release**, blocking a routine retail bugfix tag that has nothing to do
  with Forever. Verified exact failure mode from `release.sh`
  (`set_info_toc_interface`): for a suffixed TOC, if the suffix's expected game
  type doesn't match the type implied by the TOC's own `## Interface:` value, it
  prints
  `"$toc_name has an interface version (<value>) that is not compatible with the game version \"<type>\"."`
  to stderr and `exit 1`s the whole job — no partial success, no per-flavor
  isolation.

**Why it happens:**
Two TOCs means two independent sources of truth for a value that used to be
edited in exactly one place. Muscle memory from single-TOC releases (bump the one
`## Interface:` line, tag, done) doesn't carry over, and nothing in the existing
`scripts/release.bat` enforces the two files stay in sync — it only tags and
pushes.

**How to avoid:**
Add a pre-tag guard, either as a `release.bat` precondition or (preferably) a CI
step that runs *before* `BigWigsMods/packager@v2` in `release.yml`, so a bad drift
fails fast with a readable message instead of the packager's generic stderr line.
Sketch (bash, runs on the `ubuntu-latest` runner already used by the workflow):

```bash
# .github/workflows/release.yml — add before the packager step
- name: Validate flavor TOC interfaces
  run: |
    mainline_if=$(grep -oP '^## Interface:\s*\K[0-9]+' TerribleBuffTracker_Mainline.toc)
    camelot_if=$(grep -oP '^## Interface:\s*\K[0-9]+' TerribleBuffTracker_Camelot.toc)
    [[ "$mainline_if" =~ ^12[0-9]{4}$ ]] || { echo "Mainline interface '$mainline_if' is not a 12xxxx (retail) value"; exit 1; }
    [[ "$camelot_if" =~ ^16[0-9]{3}$ ]]  || { echo "Camelot interface '$camelot_if' is not a 16xxx (forever) value"; exit 1; }
    # Same file list, ignoring the directive block, so the two TOCs can't drift on shared sources
    diff <(grep -vE '^##|^\s*$' TerribleBuffTracker_Mainline.toc) \
         <(grep -vE '^##|^\s*$' TerribleBuffTracker_Camelot.toc) \
      || { echo "Mainline and Camelot TOC file lists differ — shared-source decision requires identical lists"; exit 1; }
```

This also directly enforces the user-locked "one shared Lua/XML source set, no
flavor-forked source files" decision as a CI check, not just a convention.

**Warning signs:**
- A tag push that fails in GitHub Actions with a packager stderr line mentioning
  "is not compatible with the game version" — this means drift already happened
  and reached CI instead of being caught locally.
- `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc` showing
  different file lists in a `git diff` review — a body-line diff should be exactly
  zero once directive headers are excluded.

**Phase to address:** Same phase as the TOC split (guard added alongside the
files it protects), verified by a real CI dry-run (a tag on a throwaway branch or
a manual `workflow_dispatch` trigger) before the milestone's actual release tag.

---

### Pitfall 3: Wrong-suffix silent failure on Forever

**What goes wrong:**
If `_Camelot` turns out not to be (or stops being) the exact suffix the Forever
client reads — a capitalization mismatch, a future Blizzard rename, or a
copy-paste of the wrong suffix string — the addon simply does not appear on
Forever. There is no error, no log line, nothing: the client never associates any
TOC file with the `TerribleBuffTracker` folder for that flavor, so there is
nothing to error *about*.

**Why it happens:** Same mechanism as Pitfall 1, but scoped to the new flavor
only, so it doesn't regress retail — it just means the whole Forever-support
milestone silently produces nothing to test. A specific, verified-from-source
trap: the packager's suffix regex is **case-sensitive**
(`(Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)` requires
capital `C`), and the TOC-discovery glob (`"$topdir/$package"{...,-Camelot,_Camelot}.toc`)
is a literal bash glob against the checked-out filesystem. Windows' NTFS is
case-insensitive, so a locally-created `TerribleBuffTracker_camelot.toc`
(lowercase `c`) will look completely normal in Explorer, in most editors, and
even to a casual `dir` — but the `ubuntu-latest` GitHub Actions runner checks out
git's exact recorded byte-for-byte filename, which is case-sensitive, and neither
the packager's glob nor its regex will match it. The mistake is invisible on the
developer's Windows machine and only surfaces in CI (or in-game, since Forever's
client-side TOC matching is presumably also case-sensitive on file systems where
that matters).

**Concrete diagnostics — how to tell these three failure modes apart:**

| Symptom | Root cause | How to confirm |
|---|---|---|
| Addon absent from AddOns list entirely, no entry at all | Wrong/unrecognized TOC suffix, or case mismatch | `/run print(C_AddOns.GetAddOnInfo("TerribleBuffTracker"))` returns `nil` — the client has zero knowledge of the addon |
| Addon present in AddOns list but grayed out / shows "out of date" | Suffix resolved correctly, but `## Interface:` value rejected | `C_AddOns.GetAddOnInfo("TerribleBuffTracker")` returns a table whose `reason` field is `"INTERFACE_VERSION"`; also check the account setting "Load out of date AddOns" |
| Addon loads (chat print from `Core.lua`'s `ADDON_LOADED` handler appears), but CDM tab / bars never appear | Loaded fine; `Blizzard_CooldownViewer` absent, disabled, or exposes a different API surface on this build | Run `/console scriptErrors 1` **before** reload, then `/reload` — a real Lua error surfaces as an on-screen dialog naming file/line; separately, `/run print(C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer"))` |
| Uncertain which flavor/build you're even testing | Wrong install targeted, or beta build rolled forward | Read the `.flavor.info` file in the install root (e.g. `_classic_beta_\.flavor.info`) and the build number shown bottom-left on the character-select screen; cross-check against the interface number in `_Camelot.toc` |
| Uncertain what suffix/interface *this exact beta build* expects | Convention assumptions (wiki, packager docs) can lag the live build | Open Blizzard's own shipped TOCs for that install, e.g. `_classic_beta_\Interface\AddOns\Blizzard_CooldownViewer\Blizzard_CooldownViewer*.toc` — whatever suffix and interface number Blizzard's own bundled addon uses for that exact build is ground truth, more current than any external doc |

**How to avoid:**
- Generate `_Camelot.toc` by literal copy of the working `_Mainline.toc` plus a
  targeted `## Interface:` edit, never by retyping the suffix from memory.
- Add the suffix regex check to the same CI guard sketched in Pitfall 2
  (`[[ -f TerribleBuffTracker_Camelot.toc ]]` with the exact case), so a
  case-mismatched file fails CI instead of failing silently in-client.
- Do the first Forever in-game load test immediately after creating the TOC,
  before writing any other Forever-facing code, so a wrong suffix is caught in
  minutes, not at the end of the milestone.

**Warning signs:** Nothing appears for TBT on Forever after `install.bat`, with
no error anywhere. Treat literal silence as the expected symptom of this pitfall,
not as "nothing is wrong yet."

**Phase to address:** TOC-split phase (creation of `_Camelot.toc`), verified
immediately by the milestone's own in-game-on-Forever verification step rather
than deferred to the end.

---

### Pitfall 4: Distribution mistakes — CurseForge/Wago metadata gaps surfacing for the first time on this milestone

**What goes wrong:** Several distinct failure modes bundled under "uploading
wrong":

1. **CurseForge/Wago may not yet expose a queryable Forever game version.**
   Verified from `release.sh`: CurseForge upload already hardcodes
   `forever) game_id=88568` as of the version pinned by this repo's `@v2` tag
   (v2.6.1, released the day after Forever's beta launch), and Wago's upload
   function queries `https://addons.wago.io/api/data/game` for a `.patches.forever`
   array. **Both are live-queried at upload time, not hardcoded lists** — so
   whether an actual "16001"-class version string exists under CurseForge's
   `gameVersionTypeID 88568` or Wago's `forever` patch array is a live
   backend-data question this repo cannot currently answer, because `CF_API_KEY`
   and `WAGO_API_TOKEN` are commented out in `release.yml`, meaning **nobody has
   made this call yet**. UNVERIFIED beyond the packager's own code shape: a
   WebSearch summary (low-confidence, unofficial fan sites) suggested CurseForge
   and Wago "have no Forever flavor yet" as of the beta's first days — treat this
   as a real possibility to check, not a confirmed fact.
2. **Silent partial-tagging, not silent zip-dropping.** Because `game_type_version`
   is one shared associative array covering all TOCs found, and
   `upload_curseforge` / `upload_wago` are each invoked exactly once per release
   (not once per flavor), a single zip containing both `_Mainline.toc` and
   `_Camelot.toc` is uploaded as **one file with combined version tags** — this is
   the established, already-working pattern for existing dual-flavor addons and
   is *not* itself a bug. The actual risk is narrower: if the live version lookup
   for `forever` returns zero matches, each uploader independently falls back to
   "grab the next highest version for that type" and, failing that, prints
   `WARNING: No CurseForge/Wago game version match for "...", ignoring` and simply
   **omits that type's tag from the payload** — the upload still succeeds, but
   the released file silently isn't tagged/discoverable as Forever-compatible on
   that store, even though the zip inside genuinely contains a working
   `_Camelot.toc`. This fails quietly (a successful CI run, an easy-to-miss
   yellow warning line in the Actions log) rather than loudly.
3. **`.pkgmeta` `ignore` rules accidentally excluding a needed TOC.** The current
   ignore list (`.gitignore`, `.pkgmeta`, `CHANGELOG.md`, `CLAUDE.md`,
   `README.md`, `LICENSE`, `scripts`, `*.png`, `RELEASE_NOTES.md`) has no TOC-
   related entries today, but a future edit adding a broad pattern intended for
   an unrelated purpose (e.g. a hypothetical `*camelot*` entry meant to exclude a
   dev/test scratch folder) would silently strip `TerribleBuffTracker_Camelot.toc`
   from the package with no warning — `.pkgmeta` ignore matching is silent by
   design.
4. **Since the API keys are currently disabled, the first real cross-flavor
   upload is also the first real end-to-end test of all of the above** — there
   is no dry-run environment that exercises the actual CurseForge/Wago version
   lookup today.

**Why it happens:** The addon's release pipeline has never needed to reason about
multiple game-version tags on one file before, and the tokens being disabled
means this exact code path (in both uploaders) has literally never executed for
this project.

**How to avoid:**
- Before re-enabling `CF_API_KEY`/`WAGO_API_TOKEN`, manually probe both live
  endpoints once (no upload needed, both are unauthenticated `GET`s):
  `curl -s https://addons.wago.io/api/data/game | jq '.patches.forever'` and,
  once a CurseForge API token exists for any purpose,
  `curl -s -H "x-api-token: $TOKEN" https://wow.curseforge.com/api/game/wow/versions | jq 'map(select(.gameVersionTypeID==88568))'`.
  An empty result on either confirms distribution mistake #1 is real for that
  store today, and the mitigation is simply "expect the Forever tag to be
  silently absent from that store's version list until the store back-fills it —
  the file itself is still fine and the GitHub release is unaffected."
- Re-enable the tokens on a throwaway pre-release tag first (`file_type: alpha`),
  read the Actions log in full for both `WARNING: No ... game version match`
  lines before trusting a real version tag.
- Add an explicit CI assertion that the built zip contains both
  `TerribleBuffTracker_Mainline.toc` and `TerribleBuffTracker_Camelot.toc` by
  unzipping the packager's output artifact and checking file presence — this
  catches the `.pkgmeta` ignore-exclusion mistake regardless of its cause.
- Never add a broad/wildcard `.pkgmeta` ignore pattern without grepping it
  against both TOC filenames first.

**Warning signs:** Any `WARNING: No CurseForge game version match` or
`WARNING: No Wago game version match` line in the Actions log — these are easy to
scroll past since the job still reports success.

**Phase to address:** Distribution/packaging verification phase (after both TOCs
exist and pass the CI TOC guard, before the milestone's actual public release
tag) — this is a **release-blocking** *tag* concern for the Forever entry, but
not for retail: a bad Forever version tag does not affect the retail listing on
either store.

---

### Pitfall 5: Shared-source pitfalls — one file set, two flavors, differing API surfaces

**What goes wrong:** With `Core.lua`, `BuffEngine.lua`, `Providers.lua`,
`EditModeFrames.lua`, `Display.lua`, `CDMTab.lua`/`.xml` all loading unmodified on
both flavors (per the locked "no flavor-forked source files" decision), any of
the following breaks one or both flavors:
- **Calling an API that exists on only one flavor at file scope** (i.e., directly
  in the file body, not inside a function) is a **load-time** error — it throws
  during `ADDON_LOADED` processing of that file, before any event handler runs,
  and can abort the rest of that file's execution, which is a much harsher
  failure than a runtime error inside a guarded function call later.
- **Assuming retail-only globals/namespaces exist** (e.g. anything under a
  retail-specific `C_` namespace that Forever's Classic-inspired API surface
  doesn't expose, or vice versa).
- **Assuming CDM is present** — TBT's hard dependency is Blizzard's Cooldown
  Manager; PROJECT.md's own research states Forever ships
  `Blizzard_CooldownViewer` including `GroupBuffFilter.lua`, `Blizzard_EditMode`,
  and the secret-value API docs, so the dependency itself should be present on
  Forever — but the *shape* of that API (field names, function signatures) is
  not guaranteed identical to Midnight's until verified in-game, since Forever's
  API mirrors a Midnight-style surface rather than being byte-identical to it.
- **Hardcoded retail spell IDs resolving to `nil` or to a wrong spell on
  Forever** — Forever is Classic-inspired with its own spell database; the
  numeric spellIDs TBT stores in `Providers.lua` for trinkets/pots and in the
  lust/heroism tables are retail-specific and have no guaranteed relationship to
  Forever's ID space. A retail spellID could resolve to nothing (safe-ish, shows
  a blank/missing icon) or, worse, to a *real but unrelated* Forever spell
  (silently tracks or displays the wrong thing, with no error).

**Why it happens:** Single-file-set sharing is the right architectural call here
(per the locked decision), but it means every "this API exists" or "this ID
means X" assumption baked into the shared code during single-flavor development
is now being evaluated against two different runtimes with only one code path.

**Defensive pattern:**
```lua
-- File scope: never call an API directly; only reference functions inside
-- event handlers or init functions, so a missing API surfaces as a caught
-- runtime error inside a pcall-able path, not an uncatchable load-time abort.

-- Prefer existence checks before calling anything whose presence isn't
-- guaranteed on every flavor:
if C_CooldownViewer and C_CooldownViewer.SomeFunction then
    C_CooldownViewer.SomeFunction(...)
end

-- Prefer "fails to nil, don't crash" for spell resolution, and treat nil
-- results as "don't display" rather than propagating into display code:
local info = spellID and C_Spell.GetSpellInfo(spellID)
if info then
    -- use info.iconID, info.name, etc.
end
```

**In-scope (parity) vs. out-of-scope (feature) — given this milestone forbids
new capability:**

| In scope (fix to reach parity) | Out of scope (defer) |
|---|---|
| Guarding a file-scope or unconditional API call so it degrades to a no-op instead of throwing on whichever flavor lacks it | Adding new Forever-specific tracked buffs, trinkets, or pots (new content = a feature) |
| Making a hardcoded retail spellID resolve to "nothing displayed" instead of erroring or showing garbage on Forever | Building a Forever-specific spell catalog to replace or supplement the retail one |
| Confirming CDM's actual field/function shape on Forever and adjusting *how* TBT reads it (still reading the same conceptual settings) | Adding a standalone timer UI fallback for when CDM is absent — explicitly barred by both the "no standalone fallback" architectural constraint and the parity-only scope |
| Fixing a Lua error that only reproduces on Forever due to a secret-value or event-payload shape difference | Any new Edit Mode option, display mode, or config surface introduced "while we're in there" |

**Warning signs:** A Lua error on Forever load that retail never showed (check
file + line via `/console scriptErrors 1`); a tracked buff icon/name blank or
wrong specifically on Forever; any `nil`-index error inside `Providers.lua`'s
trinket/pot resolution when tested on Forever.

**Phase to address:** The milestone's dedicated Forever-fix phase (after both
TOCs exist and Forever load is confirmed), scoped explicitly to parity fixes per
the milestone's own constraint — this is the phase most likely to warrant deeper
phase-specific research (confirming exact CDM API shape on the Forever beta
build) rather than being resolvable from the roadmap-research pass alone.

---

### Pitfall 6: SavedVariables across flavors — separate by default, but only if nobody intervenes

**What goes wrong / what does NOT go wrong:**
Retail (`_retail_`) and Forever beta (`_classic_beta_`, per PROJECT.md) are
**separate WoW products with separate WTF trees**
(`_retail_\WTF\Account\<ACCOUNT>\SavedVariables\TerribleBuffTracker.lua` vs.
`_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\TerribleBuffTracker.lua`).
Using the same `TerribleBuffTrackerDB` global name in both flavors' shared
`Core.lua` does **not** cause the two flavors to read or write the same file —
there is no cross-product file sharing in WoW's SavedVariables model, so "schema
migration runs twice" and "settings not shared between flavors" are not bugs to
fix; they are simply the expected, safe default (a first-time Forever user gets
a fresh, empty `TerribleBuffTrackerDB`, and `Core.lua`'s existing
`if not TerribleBuffTrackerDB then ... end` / backfill-on-load logic is already
idempotent and handles "first load ever" correctly on either flavor without
change).

**The real surprise (anecdotal, community-practice-based, not officially
supported by Blizzard):** players sometimes manually copy a
`SavedVariables\*.lua` file between WTF trees to carry settings across a fresh
install or a new flavor. If a user does this with `TerribleBuffTrackerDB` from
retail into the Forever WTF tree, `Core.lua`'s schema-3 backfill logic will
run — harmlessly, since it's already written idempotently (`if not
ns.db.containerSettings then ... end` style guards) — but the *contents* of that
migrated data (spellIDs in `trackedBuffs`) are retail spellIDs with no defined
meaning on Forever. This reproduces exactly the Pitfall 5 spellID-resolution
problem, except self-inflicted by the user rather than by TBT's own code, and
with zero code path in TBT today that distinguishes "this DB was populated on a
different flavor."

**How to avoid / does schema-3 need a guard:**
No guard is required for the normal case (each flavor's WTF tree is naturally
isolated). A cheap, defensive addition for the copied-DB edge case: on
`ADDON_LOADED`, if `ns.db.trackedBuffs` contains entries whose spellID resolves
to `nil` via `C_Spell.GetSpellInfo`, treat that identically to how any
unresolvable spellID is already handled elsewhere (this is the same defensive
pattern as Pitfall 5's spell-resolution fix, not a new mechanism) — do not add
flavor-tagging to the schema; that would be new persisted-data-shape work,
arguably a feature, and is not needed since the underlying nil-safe resolution
fix already covers this case for free.

**Warning signs:** A Forever user reporting tracked buffs that show blank icons
or wrong names immediately on first login (before they've configured anything)
— strongly suggests they copied a retail SavedVariables file rather than
starting fresh; distinguishes cleanly from a genuine bug because a fresh-install
Forever user would have an empty `trackedBuffs` table instead.

**Phase to address:** Covered as a side-effect of Pitfall 5's defensive
spellID-resolution fix; no dedicated phase needed, but worth one line in the
Forever-fix phase's verification checklist ("confirm a completely fresh Forever
WTF tree loads TBT with zero tracked buffs and no errors").

---

### Pitfall 7: Beta-specific risk — building against a target that moves under the milestone's feet

**What goes wrong:** Forever's beta began 2026-09-17 (the day before this
research) and is explicitly time-boxed (publicly stated to run through
2026-10-21 per low-confidence, unofficial fan-site sources — **UNVERIFIED**,
treat only as an approximate signal that the beta window is short and active).
Within that window:
- The client's exact build number and `## Interface:` value can and will move.
  This is **less dangerous than it sounds** for the packager layer specifically:
  verified from `release.sh`, both `toc_to_type()` and `toc_to_file_type()`
  match on the pattern `16???` (any five-digit interface starting `16`), so a
  beta bump from `16001` to, say, `16010` or `16100` still resolves to game type
  `forever` without any packager-side breakage. The risk is narrower than "the
  whole pipeline breaks every beta build" — it's specifically that
  `TerribleBuffTracker_Camelot.toc`'s own literal `## Interface:` value must
  still be manually kept at-or-below whatever the live beta build actually
  reports, or the **client** (not the packager) will show TBT as "out of date"
  on that specific build, independent of anything CI validates.
- API surfaces on the beta client can change between builds in ways that only
  break Forever, not retail, since Midnight's API is frozen relative to this
  milestone but Forever's is explicitly still moving.
- The BigWigs packager's own Forever support is, as of this research, less than
  24 hours old upstream and was floated/pulled/re-added once already during its
  own PR review — this repo's `@v2` floating tag means CI will silently pick up
  *future* packager changes to Forever handling with no action from this repo,
  for better or worse.

**What should NOT be released to users while Forever is still beta:**
- Do not point CurseForge/Wago's *stable/release* channel at a build that has
  only been tested against a specific beta interface number — use the
  packager's `alpha`/`beta` file-type channel (already supported via the
  existing `file_type` mechanism in `release.sh`) for any Forever-inclusive tag
  made before Forever ships to live realms, so users on the stable channel
  aren't pulled into beta-only churn.
- Do not remove the retail-only single-flavor fallback behavior (Pitfall 1's
  unsuffixed TOC) until Forever has shipped at least one stable interface number
  that isn't expected to move again.
- Do not bake the specific beta interface number (`16001`) into anything beyond
  the TOC file itself and this milestone's documentation — avoid hardcoding it
  in comments, guard conditions, or version-comparison logic in the shared Lua,
  since any such reference becomes stale the moment the beta build increments.

**How to avoid baking in something that breaks next build:**
Treat the `_Camelot.toc` interface number as the *only* place the specific
number lives, bump it opportunistically whenever testing on a newer beta build,
and keep the CI guard from Pitfall 2 pattern-matching on the `16[0-9]{3}` prefix
rather than the exact value, so routine beta bumps pass CI without edits to the
guard itself.

**Warning signs:** TBT shows "out of date" on Forever after a beta client patch,
even though it worked the previous session — check the build number banner at
character select against `_Camelot.toc`'s `## Interface:` value first, before
assuming a code regression.

**Phase to address:** Ongoing across the milestone, but concretely owned by
whichever phase does the final in-game Forever verification — that phase's
acceptance criterion should explicitly record which beta build number/interface
was tested against, since "verified on Forever" without a build number is not
reproducible information.

---

### Pitfall 8: Verification gaps — what looks done but isn't tested until it's tested on Forever specifically

**What goes wrong:** Several things are easy to believe are correct from
reading code, packager behavior, or the retail-side test, but are not actually
confirmed until a human is logged into the Forever beta client:
- "The packager accepted both TOCs without error" confirms *packaging*
  correctness, not *client-side load* correctness — the client's own TOC
  resolution logic is independent code Blizzard controls, not something the
  packager can validate.
- "CDM ships on Forever" (per PROJECT.md's own research) confirms the
  *dependency exists*, not that its Lua API surface matches Midnight's closely
  enough for TBT's existing `SnapshotSettings()` cached-read pattern
  (`CDM settings ... are cached via SnapshotSettings() on load, layout hooks,
  and EditMode.Exit`) to read the same fields without error.
- "No Lua errors on Mainline" tells you nothing about Forever — the two flavors
  can diverge in ways that only manifest as a Forever-only error, per Pitfall 5.
- "The zip contains both TOCs" (confirmed by unzipping the CI artifact) does not
  confirm CurseForge/Wago actually *tag* the file as Forever-compatible on their
  end (Pitfall 4) — those are two independent claims.
- "Edit Mode works" on retail says nothing about whether Forever's
  `Blizzard_EditMode` exposes the same container/anchor API TBT's
  `EditModeFrames.lua` depends on.

**Phase to address:** A dedicated in-game Forever verification pass, explicit in
the milestone's target features list, must independently exercise: addon load,
CDM tab injection, cast detection via `UNIT_SPELLCAST_SUCCEEDED`, bar/icon
rendering, Edit Mode drag/position persistence, and zero Lua errors — each
checked *on Forever*, not inferred from the retail result.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|-----------------|
| Keeping an unsuffixed `TerribleBuffTracker.toc` indefinitely alongside the two flavor TOCs | Extra rollback safety during the transition | Three TOCs to keep in sync forever; masks whether the suffix mechanism alone actually works | Only through the first verified release cycle; remove in the milestone's cleanup phase |
| Hardcoding the literal beta interface number in code comments for "future reference" | Documents intent inline | Goes stale the moment the beta build bumps, and can mislead future readers into thinking it's still current | Never — put build/interface context in `CHANGELOG.md`/`PROJECT.md` instead, which are expected to be updated per release |
| Skipping the CI interface/suffix guard because "the packager already errors on bad interfaces" | Saves writing a script | Packager's error message is generic and only fires at tag time, after the tag and push already happened, versus a pre-tag guard that fails before anything public occurs | Never for this milestone, given the explicit ranking of the retail-regression risk |
| Leaving `CF_API_KEY`/`WAGO_API_TOKEN` disabled through the whole milestone | Avoids surfacing distribution issues mid-milestone | Defers all of Pitfall 4's discovery to the very last step, right before the actual public release | Acceptable only if a manual, unauthenticated probe of both stores' version endpoints (sketched in Pitfall 4) is done first as a substitute |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| BigWigs Packager (`BigWigsMods/packager@v2`) | Assuming a floating major-version tag (`@v2`) is pinned/stable | Know that `@v2` already resolved to `v2.6.1` (post-Forever-support) as of this research; re-check `release.sh` behavior if the milestone spans weeks, since `@v2` will silently pick up future packager changes |
| CurseForge upload API | Assuming `gameVersionTypeID` existing in the packager's code means CurseForge's live version list has matching entries | Probe `GET /api/game/wow/versions` (with any valid token) and filter for `gameVersionTypeID == 88568` before trusting an automated Forever tag |
| Wago upload API | Same assumption for `.patches.forever` | Probe `GET https://addons.wago.io/api/data/game` (unauthenticated) and check `.patches.forever` is non-empty before trusting an automated Forever tag |
| `.pkgmeta` `ignore` list | Adding a broad pattern for an unrelated purpose that accidentally matches a TOC filename | Grep any new ignore pattern against both TOC filenames before committing it |
| GitHub Actions checkout (`ubuntu-latest`) | Trusting a filename's on-disk case as seen in Windows Explorer/editors | Remember the CI runner is case-sensitive even though the dev machine (NTFS) is not; verify exact filenames via `git ls-files` rather than a Windows file browser |

## Performance Traps

Not applicable in the traditional sense — this milestone is metadata/tooling
only, touches no runtime hot paths, and CLAUDE.md's existing hot-path review
discipline (per-frame allocations, `wipe()` reuse, etc.) is unaffected by TOC or
packaging changes. The one adjacent risk is Pitfall 5's defensive API-existence
checks: keep them at file-scope/init-time or inside already-infrequent paths
(`ADDON_LOADED`, settings snapshot), not inside `OnUpdate`-style per-frame
callbacks, so parity fixes don't introduce new per-frame branching.

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Uncommenting `CF_API_KEY: ${{ secrets.CF_API_KEY }}` / `WAGO_API_TOKEN` in `release.yml` and accidentally committing a literal token value while testing locally | Leaked publishing credentials, usable to push malicious releases under this addon's identity | Only ever reference tokens via `${{ secrets.* }}`; never paste a real token into a local test of the workflow file; rotate immediately if one is ever committed |
| Testing the CI guard scripts with `echo`/debug output that includes secret values | Same as above, surfaced in public Actions logs | Keep any debug output limited to non-secret values (interface numbers, filenames), never the token env vars |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|--------------|-------------------|
| Addon silently absent on Forever with no explanation (Pitfall 3) | Users assume TBT simply "doesn't support Forever" and stop trying, generating support burden via confused bug reports rather than clear ones | Ship a `CHANGELOG.md`/release-notes line explicitly stating Forever support and the tested build/interface number, so users know what to expect and can report deviations precisely |
| "Out of date" flag on one flavor after a missed interface bump (Pitfall 2) | Users on the affected flavor lose functionality until the next release, while the other flavor's users see nothing wrong — support reports will look contradictory ("works for me") until someone asks which flavor | The CI guard doubles as documentation: a failed guard message names which flavor's interface is wrong, shortening time-to-fix |

## "Looks Done But Isn't" Checklist

- [ ] **TOC split lands:** Often missing — an in-game retail reload confirming
      the addon still loads, still prints its load message, and `/tbt` still
      opens the CDM tab. Code review alone does not verify this.
- [ ] **Forever TOC created:** Often missing — confirmation that the *exact*
      suffix and interface number match what Blizzard's own bundled
      `Blizzard_CooldownViewer` TOC declares for that specific beta build, not
      just what documentation/packager source says the convention "should" be.
- [ ] **CI packager run succeeds:** Often missing — actually unzipping the
      produced artifact and confirming both TOCs are present inside it, rather
      than trusting a green checkmark alone.
- [ ] **Shared-source parity fixes:** Often missing — a Forever-specific in-game
      pass with `/console scriptErrors 1` enabled, since a clean retail session
      proves nothing about Forever-only Lua errors.
- [ ] **CurseForge/Wago tagging:** Often missing — actually reading the full CI
      log for `WARNING: No ... game version match` lines, not just checking the
      job's overall success/failure status.
- [ ] **install.bat "every client present" behavior:** Often missing —
      verification on a machine that has *only* retail installed (no Forever
      beta present), confirming the script skips the absent target gracefully
      rather than erroring.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|-----------------|
| Rename trap breaks retail load (Pitfall 1) | LOW | Revert the isolated TOC-rename commit; since it's isolated per the prevention strategy, this is a single clean revert with no entanglement with unrelated changes |
| Interface drift blocks a release tag (Pitfall 2) | LOW | Fix the offending TOC's interface value locally, re-tag (packager never partially released — it hard-errors before uploading anything) |
| Wrong suffix ships silently to Forever users (Pitfall 3) | LOW–MEDIUM | Push a follow-up release with the corrected suffix; no user data is at risk since Forever's SavedVariables tree was never populated if the addon never loaded |
| CurseForge/Wago silently missing the Forever tag (Pitfall 4) | LOW | Re-run the upload once the store's version list includes the entry, or re-tag once tokens/version data are confirmed available — the underlying zip was already correct |
| Shared-source Forever-only Lua error (Pitfall 5) | MEDIUM | Requires a targeted fix-and-retest cycle on the beta client specifically; cost scales with how deep in the shared file the offending call is |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| 1. Rename trap | TOC-split phase (first phase of v0.3) | Retail in-game reload test + ADDON_LOADED chat print observed |
| 2. Interface drift | TOC-split phase (guard added alongside the TOCs) | CI guard step fails a deliberately-broken test tag before it reaches the packager |
| 3. Wrong-suffix silent failure | TOC-split phase | First Forever in-game load test, done immediately after TOC creation, not deferred |
| 4. Distribution mistakes | Packaging/distribution verification phase (after TOC-split, before public release tag) | Manual unauthenticated probe of CF/Wago version endpoints; CI artifact unzip check; log scan for WARNING lines |
| 5. Shared-source parity pitfalls | Dedicated Forever-fix phase (parity-only scope) | Forever in-game pass with `/console scriptErrors 1`; explicit pass/fail per shared file touched |
| 6. SavedVariables surprises | Covered inside the Forever-fix phase (same spellID-resolution fix as #5) | Fresh Forever WTF tree login test, zero tracked buffs, zero errors |
| 7. Beta volatility | Ongoing; owned by the final in-game verification phase | Verification record includes the exact beta build/interface tested, and uses `16[0-9]{3}` range guard rather than an exact-value guard |
| 8. Verification gaps | Dedicated in-game Forever verification phase (explicit milestone target feature) | Checklist run on Forever specifically: load, CDM tab, cast detection, bars/icons, Edit Mode, zero errors — each independently confirmed, none inferred from retail |
| Cleanup (unsuffixed TOC removal, release-script audit) | Milestone-end cleanup phase (per CLAUDE.md's standing GSD workflow requirement) | Remove `TerribleBuffTracker.toc` fallback only after at least one verified release cycle on both flavors; re-review `release.bat`/`install.bat` per CLAUDE.md's mandated cleanup pass |

## Sources

- `https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh` — downloaded and read directly (commit `e50a250f`, tag `v2.6.1`, 2026-09-18). HIGH confidence — primary source, exact code quoted above for suffix regex, interface validation, error message text, CurseForge/Wago upload logic, and the `16???`→`forever` type mapping.
- `https://github.com/BigWigsMods/packager/pull/202` ("Add WoW Forever support") — merged 2026-09-17. MEDIUM confidence (PR description/review summarized via fetch, not the full diff); establishes that Forever detection was contested and re-added within the packager's own review process, i.e. genuinely new and recently unstable upstream.
- GitHub API queries against `BigWigsMods/packager` (commits, tags, tag refs) — HIGH confidence, directly queried, confirms `@v2` currently resolves to `v2.6.1` which post-dates Forever support.
- `https://warcraft.wiki.gg/wiki/TOC_format` — MEDIUM confidence (fetched/summarized, not the full page verbatim); used for TOC suffix priority order and the Patch 9.1.0 origin of flavor-suffix support, and the `AllowLoadGameType` field.
- WebSearch results on CurseForge/Wago Forever game-version support and the Forever beta timeline — LOW confidence, unofficial fan-site aggregation; flagged explicitly wherever used (Pitfall 4's "may not yet expose a Forever version" claim, Pitfall 7's beta end-date). Treat as directional only; the authoritative check is the live, unauthenticated endpoint probes described in Pitfall 4.
- `.planning/PROJECT.md`, `CLAUDE.md`, `TerribleBuffTracker.toc`, `.pkgmeta`, `.github/workflows/release.yml`, `scripts/install.bat`, `scripts/release.bat`, `CHANGELOG.md`, `Core.lua` — read directly from the repository, HIGH confidence, primary source for current-state facts (existing constraints, decisions, DB schema, ignore list, workflow shape).

---
*Pitfalls research for: WoW Forever cross-flavor addon support (TerribleBuffTracker v0.3)*
*Researched: 2026-09-18*
