@echo off
rem Double-click to set this PC up as a Battleborn Reborn server host.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Host.ps1" %*
pause
