@echo off
rem Thin wrapper. The deploy logic lives in install.ps1 — batch cannot derive
rem the file set from the TOC or substitute a version without becoming
rem unreadable. ./scripts/install.bat stays the documented entry point.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %errorlevel%
