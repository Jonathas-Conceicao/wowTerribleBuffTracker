# Phase 58: Cleanup - Discussion Log

**Date:** 2026-09-29

## Areas offered
- Reminder internal names: **selected**
- Reminders container "In Combat": not selected (left to Claude's discretion)
- Release safety checks: **selected**
- Docs touch-ups: **selected**

## Reminder internal names
- Q: Rename the Phase 57 "visibility" runtime to reminder names?
- Options: Rename to reminder* (recommended) / Keep the names
- **User:** Rename to reminder*

## Release safety checks
- Q: What should release.bat do with aura-read-gate.js and migrate-dryrun.js?
- Options: Run both and refuse to tag on failure (recommended) / Run and warn only / Leave
  release.bat alone
- **User:** Leave release.bat alone

## Docs touch-ups
- Q: Which docs may Phase 58 edit? (multi-select; CHANGELOG.md is never touched)
- Options: CLAUDE.md stylua line / REQUIREMENTS wording / Architecture list in CLAUDE.md
- **User:** all three

## Claude's discretion
- Reminders container "In Combat" option: first proposed as "hide it", then corrected by the
  user: "reminders do partially work in combat ... if we have previous info of buff duration and
  it expires by time mid combat, we do show the icon". Keep the option and fix the stale notes.
- The new names and which duplication to unify.

## Deferred
- Release-script integration of the checks.
