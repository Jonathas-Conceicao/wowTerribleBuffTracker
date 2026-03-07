@echo off
set "SOURCE=%~dp0"
set "DEST=%PROGRAMFILES(x86)%\World of Warcraft\_retail_\Interface\AddOns\TerribleBuffTracker"

if not exist "%DEST%" mkdir "%DEST%"

echo Copying TerribleBuffTracker to WoW retail addons folder...
copy /Y "%SOURCE%TerribleBuffTracker.toc" "%DEST%\"
copy /Y "%SOURCE%Core.lua" "%DEST%\"
copy /Y "%SOURCE%BuffEngine.lua" "%DEST%\"
copy /Y "%SOURCE%Display.lua" "%DEST%\"
copy /Y "%SOURCE%ConfigUI.lua" "%DEST%\"

echo Done! /reload in WoW to load the addon.
pause
