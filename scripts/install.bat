@echo off
setlocal enabledelayedexpansion

set "SOURCE=%~dp0..\"
set "WOW_ROOT=%ProgramFiles(x86)%\World of Warcraft"
if defined TBT_WOW_ROOT set "WOW_ROOT=%TBT_WOW_ROOT%"

set "FILES=Core.lua BuffEngine.lua Providers.lua EditModeFrames.lua Display.lua CDMTab.xml CDMTab.lua tbt_icon_64x64.blp TerribleBuffTracker_Mainline.toc TerribleBuffTracker_Camelot.toc"
set "FLAVORS=_retail_ _ptr_ _beta_ _classic_beta_ _classic_ _classic_era_ _classic_ptr_"

for %%F in (%FILES%) do (
    if not exist "%SOURCE%%%F" (
        echo ERROR: missing source file %%F in %SOURCE%
        exit /b 1
    )
)

set "INSTALLED=0"

for %%L in (%FLAVORS%) do (
    if exist "%WOW_ROOT%\%%L\" (
        set "DEST=%WOW_ROOT%\%%L\Interface\AddOns\TerribleBuffTracker"
        if not exist "!DEST!" mkdir "!DEST!"
        for %%F in (%FILES%) do (
            copy /Y "%SOURCE%%%F" "!DEST!\" >nul
            if errorlevel 1 (
                echo ERROR: failed to copy %%F to !DEST!
                exit /b 1
            )
        )
        set /a INSTALLED+=1
        echo Installed to !DEST!
    )
)

if "!INSTALLED!"=="0" (
    echo ERROR: no WoW client folders found under "%WOW_ROOT%"
    echo Checked flavors: %FLAVORS%
    echo If WoW is installed elsewhere, set TBT_WOW_ROOT to the correct root and try again.
    exit /b 1
)

echo Done^^! /reload in WoW to load the addon.
