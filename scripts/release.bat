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
