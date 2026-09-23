@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: release.bat ^<version^>
    echo Example: release.bat 0.1.0
    exit /b 1
)

set "VERSION=%~1"
set "TAG=v%VERSION%"
set "SOURCE=%~dp0..\\"

echo === Releasing TerribleBuffTracker %VERSION% ===

rem REL-01: this script tags HEAD and then pushes origin main. Run it from any
rem other branch and it tags the wrong commit while still pushing main. The
rem workflow is: squash-merge the milestone branch into main FIRST, then
rem release from main. Set TBT_ALLOW_BRANCH=1 to override deliberately.
set "BRANCH="
for /f "usebackq tokens=* delims=" %%B in (`git -C "%SOURCE%" rev-parse --abbrev-ref HEAD`) do set "BRANCH=%%B"
if not "!BRANCH!"=="main" (
    if not "%TBT_ALLOW_BRANCH%"=="1" (
        echo ERROR: on branch "!BRANCH!", but release.bat tags HEAD and pushes origin main.
        echo Squash-merge into main first, then release from main.
        echo Set TBT_ALLOW_BRANCH=1 to override.
        exit /b 1
    )
    echo WARNING: releasing from "!BRANCH!" because TBT_ALLOW_BRANCH=1.
)

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

echo === Released %TAG% — GitHub Actions will handle packaging ===
