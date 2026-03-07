@echo off
set "SOURCE=%~dp0"
set "STAGING=%SOURCE%TerribleBuffTracker"
set "ZIPFILE=%SOURCE%TerribleBuffTracker.zip"

if exist "%ZIPFILE%" del "%ZIPFILE%"
if exist "%STAGING%" rmdir /S /Q "%STAGING%"

mkdir "%STAGING%"

echo Packing TerribleBuffTracker...
copy /Y "%SOURCE%TerribleBuffTracker.toc" "%STAGING%\"
copy /Y "%SOURCE%Core.lua" "%STAGING%\"
copy /Y "%SOURCE%BuffEngine.lua" "%STAGING%\"
copy /Y "%SOURCE%Display.lua" "%STAGING%\"
copy /Y "%SOURCE%ConfigUI.lua" "%STAGING%\"

powershell -NoProfile -Command "Compress-Archive -Path '%STAGING%' -DestinationPath '%ZIPFILE%'"

rmdir /S /Q "%STAGING%"

echo Created %ZIPFILE%
