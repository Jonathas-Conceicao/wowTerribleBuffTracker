# Phase 32: Single-Zip Packaging - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning

<domain>
## Phase Boundary

One `.pkgmeta`, one CI job, one zip carrying every game version the TOC declares.

In scope: `.pkgmeta`, `.github/workflows/release.yml`, the `check-toc.ps1` call in `release.bat`, and
**observing** a real packager run rather than designing against one.

Out of scope: the TOC itself (Phase 31), `install.bat` (Phase 33), and any retail check (Phase 44).
</domain>

<decisions>
## Implementation Decisions

### Packaging Shape
- One zip for everything — user decision 2026-09-20, reversing the locked two-flavour-zip decision. A
  single TOC naturally implies a single package.
- `-g` is **not** passed. With no `-g` and no split, the packager reads the root `## Interface:` value,
  derives one game type per interface version, and — because more than one results — leaves `game_type`
  empty and reports `multi-version`. That is exactly the desired outcome: one artifact carrying both
  game versions.
- `-n "{package-name}-{project-version}"` drops the `{game-type}` segment. Keeping it would have
  produced a trailing dash, since `game_type` is deliberately empty in the multi-version case.
- `package-as: TerribleBuffTracker` stays in `.pkgmeta`.

### Verification Approach
- `DIST-12` is **observed**, not deferred. v0.3 left `DIST-03`…`DIST-07` open precisely because the
  observable half was pushed to "the first real release", which then never happened before the milestone
  closed. A local packager run costs minutes.
- The local run uses `release.sh -d` (no upload). `zip` is absent from this machine's Git Bash, so the
  run stops at the archive step — **after** every value under test has been printed.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.pkgmeta-mainline` became `.pkgmeta` via `git mv` in Phase 31, so the shared config and its history
  carried over; only the two cross-ignore lines needed removing.

### Established Patterns
- The ignore list is the load-bearing part: `scripts`, `tools`, `*.png`, `CHANGELOG.md`, `CLAUDE.md`,
  `README.md`, `LICENSE`, `stylua.toml`, `RELEASE_NOTES.md`. `tools` must stay — it holds the throwaway
  probe harness, which must never ship.
- `release.yml` generates `RELEASE_NOTES.md` from `CHANGELOG.md`'s first `## ` section before the
  packager runs; that step is unchanged by going single-job.

### Integration Points
- BigWigs packager `release.sh` decides game type from the TOC **filename suffix** before it ever looks
  at the `## Interface:` line. That interaction is what this phase found — see Findings in the summary.
</code_context>

<specifics>
## Specific Ideas

None beyond "one zip for everything".
</specifics>

<deferred>
## Deferred Ideas

- Enabling CurseForge/Wago upload credentials (`FTOOL-01`) remains deliberately off; v0.3.0 published to
  GitHub releases only and v0.4.0 will too unless the user turns them on.
</deferred>
