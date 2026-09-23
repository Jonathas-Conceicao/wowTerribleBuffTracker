@echo off
setlocal enabledelayedexpansion

rem Deploys the throwaway TBTProbe harness. Deliberately NOT part of
rem scripts/install.bat: the probe is never shipped, and only the two clients
rem in scope get it (_beta_ and _ptr_ are explicitly out of scope, 2026-09-20).

set "SOURCE=%~dp0"
set "WOW_ROOT=%ProgramFiles(x86)%\World of Warcraft"
if defined TBT_WOW_ROOT set "WOW_ROOT=%TBT_WOW_ROOT%"

set "FILES=TBTProbe.toc Probe.lua"
set "FLAVORS=_retail_ _classic_beta_"

for %%F in (%FILES%) do (
    if not exist "%SOURCE%%%F" (
        echo ERROR: missing source file %%F in %SOURCE%
        exit /b 1
    )
)

set "INSTALLED=0"

for %%L in (%FLAVORS%) do (
    if exist "%WOW_ROOT%\%%L\" (
        set "DEST=%WOW_ROOT%\%%L\Interface\AddOns\TBTProbe"
        if not exist "!DEST!" mkdir "!DEST!"
        for %%F in (%FILES%) do (
            copy /Y "%SOURCE%%%F" "!DEST!\" >nul
            if errorlevel 1 (
                echo ERROR: failed to copy %%F to !DEST!
                exit /b 1
            )
        )
        set /a INSTALLED+=1
        echo Installed probe to !DEST!
    )
)

if "!INSTALLED!"=="0" (
    echo ERROR: neither _retail_ nor _classic_beta_ found under "%WOW_ROOT%"
    echo If WoW is installed elsewhere, set TBT_WOW_ROOT and try again.
    exit /b 1
)

echo Done^^! Enable "TBT Probe" in the AddOns list, then /tbtp help
