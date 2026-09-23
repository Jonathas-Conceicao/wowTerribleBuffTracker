# Deploys TerribleBuffTracker to every WoW client folder present on the machine.
#
# Three things this does that a plain copy cannot:
#   1. Derives the file set from the TOC instead of duplicating it (INST-09).
#   2. Substitutes a dev version into the DEPLOYED TOC only, so the client
#      reports something real instead of the literal "@project-version@"
#      (INST-05/INST-06). The repo TOC is never modified — the packager keyword
#      has to survive for real releases.
#   3. Prunes files the repo no longer has, so a deployed folder is an honest
#      picture of the current source (INST-07/INST-08).
#
# Entry point is scripts\install.bat, which just forwards here.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = (Resolve-Path (Join-Path $scriptDir '..')).Path
$tocName = 'TerribleBuffTracker.toc'
$tocPath = Join-Path $source $tocName

if (-not (Test-Path -LiteralPath $tocPath)) {
    Write-Host "ERROR: missing $tocName in $source"
    exit 1
}

$wowRoot = if ($env:TBT_WOW_ROOT) { $env:TBT_WOW_ROOT } else { Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft' }
$flavors = @('_retail_', '_ptr_', '_beta_', '_classic_beta_', '_classic_', '_classic_era_', '_classic_ptr_')

# ---------------------------------------------------------------- file set --

$tocLines = Get-Content -LiteralPath $tocPath

# The load list: every non-directive, non-blank line in the TOC.
$files = New-Object System.Collections.Generic.List[string]
$files.Add($tocName)
foreach ($line in $tocLines) {
    $trimmed = $line.Trim()
    if ($trimmed -and -not $trimmed.StartsWith('#')) { $files.Add($trimmed) }
}

# Anything an XML in the load list pulls in (CDMTab.xml -> CDMTab.lua).
foreach ($entry in @($files)) {
    if ([System.IO.Path]::GetExtension($entry) -ne '.xml') { continue }
    $xmlPath = Join-Path $source $entry
    if (-not (Test-Path -LiteralPath $xmlPath)) { continue }
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $xmlPath -Raw), '(?i)\bfile\s*=\s*"([^"]+)"')) {
        $ref = $m.Groups[1].Value
        if ($files -notcontains $ref) { $files.Add($ref) }
    }
}

# The icon named by ## IconTexture:, which carries no extension in the TOC.
$iconLine = $tocLines | Where-Object { $_ -match '^\s*##\s*IconTexture\s*:' } | Select-Object -First 1
if ($iconLine) {
    $iconBase = Split-Path -Leaf ($iconLine -replace '^\s*##\s*IconTexture\s*:\s*', '').Trim()
    $icon = Get-ChildItem -LiteralPath $source -Filter "$iconBase.*" -File |
        Where-Object { $_.Extension -in '.blp', '.tga' } | Select-Object -First 1
    if ($icon -and ($files -notcontains $icon.Name)) { $files.Add($icon.Name) }
}

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $f))) {
        Write-Host "ERROR: $tocName references $f, which does not exist in $source"
        exit 1
    }
}

Write-Host "Deploying $($files.Count) files derived from ${tocName}: $($files -join ', ')"

# ----------------------------------------------------------- dev version ----

# Unmistakably a dev build. A bare "0.4.0" sitting in a dev folder would be
# worse than the raw keyword, which is at least honest about being unsubstituted.
$describe = & git -C $source describe --tags --always --dirty 2>$null
if ($LASTEXITCODE -ne 0 -or -not $describe) { $describe = 'unknown' }
$devVersion = "$describe-dev"
Write-Host "Deployed version: $devVersion"

$tocText = (Get-Content -LiteralPath $tocPath -Raw) -replace '@project-version@', $devVersion
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# -------------------------------------------------------------- deploy ------

$installed = 0
foreach ($flavor in $flavors) {
    $clientDir = Join-Path $wowRoot $flavor
    if (-not (Test-Path -LiteralPath $clientDir)) { continue }

    $dest = Join-Path $clientDir 'Interface\AddOns\TerribleBuffTracker'
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

    foreach ($f in $files) {
        $target = Join-Path $dest $f
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        if ($f -eq $tocName) {
            [System.IO.File]::WriteAllText($target, $tocText, $utf8NoBom)
        } else {
            Copy-Item -LiteralPath (Join-Path $source $f) -Destination $target -Force
        }
    }

    # Prune anything the repo no longer ships. SavedVariables live under WTF\,
    # never here, so nothing a player owns is at risk.
    $pruned = 0
    foreach ($existing in Get-ChildItem -LiteralPath $dest -File -Recurse) {
        $rel = $existing.FullName.Substring($dest.Length).TrimStart('\')
        if ($files -notcontains $rel) {
            Remove-Item -LiteralPath $existing.FullName -Force
            Write-Host "  pruned stale file: $rel"
            $pruned++
        }
    }

    $installed++
    $suffix = if ($pruned -gt 0) { " ($pruned stale file(s) pruned)" } else { '' }
    Write-Host "Installed to $dest$suffix"
}

if ($installed -eq 0) {
    Write-Host "ERROR: no WoW client folders found under `"$wowRoot`""
    Write-Host "Checked flavors: $($flavors -join ' ')"
    Write-Host 'If WoW is installed elsewhere, set TBT_WOW_ROOT to the correct root and try again.'
    exit 1
}

Write-Host 'Done! /reload in WoW to load the addon.'
