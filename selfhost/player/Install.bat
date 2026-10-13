@echo off
rem Double-click to set up Battleborn Reborn for this server.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Player.ps1" %*
pause
