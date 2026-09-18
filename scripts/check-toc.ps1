<#
.SYNOPSIS
    Pre-tag drift guard for TerribleBuffTracker's flavor-suffixed TOC pair.

.DESCRIPTION
    Asserts the two flavor TOCs (TerribleBuffTracker_Mainline.toc and
    TerribleBuffTracker_Camelot.toc) have not silently diverged in a way that
    would either break an existing retail install or cause the BigWigs
    packager to hard-error at tag time (see .planning/research/PITFALLS.md
    pitfall 2).

    Three assertions (25-CONTEXT.md D-14):
      1. Each flavor's ## Interface: value falls inside its expected range.
      2. The two TOC bodies are identical once the two allowlisted directive
         lines (## Interface: and ## Notes:) are excluded, compared in a
         line-ending-insensitive way.
      3. If a .pkgmeta-<flavor> file exists (Phase 29+), it ignores exactly
         the OTHER flavor's TOC and does not ignore its own. Absence of
         these files is not a failure — they are not created until Phase 29.

    This script performs no git calls, no network calls, and no writes to
    disk. It only reads text files under -Root and exits 0 or 1.

.PARAMETER Root
    Directory containing the TOC files. Defaults to the parent of the
    directory this script lives in (the repo root, since this script lives
    in scripts/).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-toc.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-toc.ps1 -Root C:\scratch\toc-test
#>

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Get-TocLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) {
        return @()
    }
    # Line-ending-insensitive split: working tree is CRLF, git stores LF (D-05/D-14.2).
    return [regex]::Split($raw, '\r?\n')
}

function Get-InterfaceValue {
    param([string[]]$Lines, [string]$FileLabel)
    $match = $Lines | Where-Object { $_ -match '^##\s*Interface:\s*(\d+)\s*$' } | Select-Object -First 1
    if (-not $match) {
        $script:failures.Add("${FileLabel}: missing or unparseable '## Interface:' directive")
        return $null
    }
    if ($match -match '^##\s*Interface:\s*(\d+)\s*$') {
        return $Matches[1]
    }
    return $null
}

# --- Resolve TOC paths -------------------------------------------------
$mainlinePath = Join-Path $Root 'TerribleBuffTracker_Mainline.toc'
$camelotPath = Join-Path $Root 'TerribleBuffTracker_Camelot.toc'

$mainlineLines = Get-TocLines -Path $mainlinePath
$camelotLines = Get-TocLines -Path $camelotPath

if ($null -eq $mainlineLines) {
    $failures.Add("Missing required file: $mainlinePath")
}
if ($null -eq $camelotLines) {
    $failures.Add("Missing required file: $camelotPath")
}

# --- Assertion 1: interface ranges (D-14.1) -----------------------------
if ($null -ne $mainlineLines) {
    $mainlineIf = Get-InterfaceValue -Lines $mainlineLines -FileLabel 'TerribleBuffTracker_Mainline.toc'
    if ($null -ne $mainlineIf -and $mainlineIf -notmatch '^12\d{4}$') {
        $failures.Add("TerribleBuffTracker_Mainline.toc: Interface value '$mainlineIf' does not match expected pattern ^12\d{4}$ (retail Midnight range)")
    }
}
if ($null -ne $camelotLines) {
    $camelotIf = Get-InterfaceValue -Lines $camelotLines -FileLabel 'TerribleBuffTracker_Camelot.toc'
    if ($null -ne $camelotIf -and $camelotIf -notmatch '^16\d{3}$') {
        $failures.Add("TerribleBuffTracker_Camelot.toc: Interface value '$camelotIf' does not match expected pattern ^16\d{3}$ (WoW Forever range)")
    }
}

# --- Assertion 2: body parity (D-14.2) ----------------------------------
if ($null -ne $mainlineLines -and $null -ne $camelotLines) {
    $filterDirective = { $_ -notmatch '^##\s*(Interface|Notes):' }
    $mainlineBody = @($mainlineLines | Where-Object $filterDirective | ForEach-Object { $_.TrimEnd() })
    $camelotBody = @($camelotLines | Where-Object $filterDirective | ForEach-Object { $_.TrimEnd() })

    if ($mainlineBody.Count -ne $camelotBody.Count) {
        $failures.Add("Body line count differs: TerribleBuffTracker_Mainline.toc has $($mainlineBody.Count) non-directive lines, TerribleBuffTracker_Camelot.toc has $($camelotBody.Count)")
    }

    $minCount = [Math]::Min($mainlineBody.Count, $camelotBody.Count)
    for ($i = 0; $i -lt $minCount; $i++) {
        if (-not [string]::Equals($mainlineBody[$i], $camelotBody[$i], [System.StringComparison]::Ordinal)) {
            $failures.Add("Body drift at line $($i + 1): Mainline='$($mainlineBody[$i])' Camelot='$($camelotBody[$i])'")
            break
        }
    }
}

# --- Assertion 3: .pkgmeta-<flavor> cross-ignore, forward-looking (D-14.3) --
$pairs = @(
    @{ PkgMeta = '.pkgmeta-mainline'; OwnToc = 'TerribleBuffTracker_Mainline.toc'; OtherToc = 'TerribleBuffTracker_Camelot.toc' },
    @{ PkgMeta = '.pkgmeta-camelot'; OwnToc = 'TerribleBuffTracker_Camelot.toc'; OtherToc = 'TerribleBuffTracker_Mainline.toc' }
)

foreach ($pair in $pairs) {
    $pkgMetaPath = Join-Path $Root $pair.PkgMeta
    if (-not (Test-Path -LiteralPath $pkgMetaPath)) {
        Write-Output "skip: $($pair.PkgMeta) not present (Phase 29)"
        continue
    }

    $pkgLines = Get-TocLines -Path $pkgMetaPath
    if ($null -eq $pkgLines) {
        $pkgLines = @()
    }

    $otherEscaped = [regex]::Escape($pair.OtherToc)
    $ownEscaped = [regex]::Escape($pair.OwnToc)

    $ignoresOther = $pkgLines | Where-Object { $_ -match "^\s*-\s*[""']?$otherEscaped[""']?\s*$" }
    $ignoresOwn = $pkgLines | Where-Object { $_ -match "^\s*-\s*[""']?$ownEscaped[""']?\s*$" }

    if (-not $ignoresOther) {
        $failures.Add("$($pair.PkgMeta): does not ignore $($pair.OtherToc) (expected a YAML ignore entry)")
    }
    if ($ignoresOwn) {
        $failures.Add("$($pair.PkgMeta): incorrectly ignores its own TOC ($($pair.OwnToc))")
    }
}

# --- Report --------------------------------------------------------------
if ($failures.Count -gt 0) {
    foreach ($f in $failures) {
        Write-Output "FAIL: $f"
    }
    exit 1
}

Write-Output "check-toc: OK ($Root)"
exit 0
