@echo off
rem Undo the self-host setup and go back to the official Reborn servers.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Player.ps1" -Uninstall
pause
