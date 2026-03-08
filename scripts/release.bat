@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: release.bat ^<version^> [next-dev-version]
    echo Example: release.bat 0.1.0 0.2.0-dev
    exit /b 1
)

set "VERSION=%~1"
set "TAG=v%VERSION%"
set "SOURCE=%~dp0..\\"
set "TOC=%SOURCE%TerribleBuffTracker.toc"

if "%~2"=="" (
    set "NEXT_VERSION=%VERSION%-dev"
) else (
    set "NEXT_VERSION=%~2"
)

echo === Releasing TerribleBuffTracker %VERSION% ===

:: Update .toc version to release version
powershell -NoProfile -Command "(Get-Content '%TOC%') -replace '## Version: .*', '## Version: %VERSION%' | Set-Content '%TOC%'"

:: Commit version change if needed, then tag
git -C "%SOURCE%" add TerribleBuffTracker.toc
git -C "%SOURCE%" diff --cached --quiet || git -C "%SOURCE%" commit -m "release: v%VERSION%"

git -C "%SOURCE%" tag -a "%TAG%" -m "Release %VERSION%"
if errorlevel 1 (
    echo ERROR: Tag creation failed.
    exit /b 1
)

git -C "%SOURCE%" push origin main "%TAG%"
if errorlevel 1 (
    echo ERROR: Push failed.
    exit /b 1
)

:: Build release zip
call "%~dp0pack.bat"

echo === Released %TAG% ===

:: Bump to next development version
powershell -NoProfile -Command "(Get-Content '%TOC%') -replace '## Version: .*', '## Version: %NEXT_VERSION%' | Set-Content '%TOC%'"

git -C "%SOURCE%" add TerribleBuffTracker.toc
git -C "%SOURCE%" commit -m "general: Bump version to %NEXT_VERSION%"
git -C "%SOURCE%" push origin main

echo === Now on development version %NEXT_VERSION% ===
