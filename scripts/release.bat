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

echo === Checking flavor TOC drift ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-toc.ps1"
if errorlevel 1 (
    echo ERROR: check-toc.ps1 reported TOC drift. Aborting before tag.
    exit /b 1
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
