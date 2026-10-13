<#
.SYNOPSIS
    Sets up Battleborn + Reborn on a player's PC and points the in-game server browser at a self-hosted server.

.PARAMETER Server
    Server browser address (host or host:port). Defaults to the address in server.txt next to this script.

.PARAMETER GameDir
    Battleborn folder, if it isn't in a Steam library.

.PARAMETER Uninstall
    Put back the original Reborn DLLs and go back to the official server browser.
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$GameDir,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$KitRoot = $PSScriptRoot
. (Join-Path $KitRoot 'BattlebornCommon.ps1')

Write-Host "Battleborn Reborn - player setup" -ForegroundColor White

Write-Step "Finding Battleborn"
$win64 = Find-BattlebornWin64 -GameDir $GameDir
if (-not $win64) {
    Request-BattlebornInstall
    exit 1
}
Write-Ok $win64

if ($Uninstall) {
    Write-Step "Removing self-host changes"
    Restore-RebornDlls -Win64 $win64
    Remove-Item (Join-Path $win64 'reborn_server.txt') -ErrorAction SilentlyContinue
    Write-Ok "Done. Battleborn is back to the official Reborn setup."
    exit 0
}

Write-Step "Checking for the official Reborn install"
if (-not (Test-Path (Join-Path $win64 'reborn.dll'))) {
    Write-Warn "Official Reborn doesn't appear to be installed yet."
    Write-Warn "Install it once from https://bereborn.dev (ReBornInstaller.exe, pick your Battleborn folder),"
    Write-Warn "then run this again. This kit replaces its DLLs with the self-host build."
    $answer = Read-Host "    Open bereborn.dev now? [Y/n]"
    if ($answer -notmatch '^[Nn]') { Start-Process 'https://bereborn.dev/' }
    $answer = Read-Host "    Continue anyway without the official install? [y/N]"
    if ($answer -notmatch '^[Yy]') { exit 1 }
}

Write-Step "Installing the self-host build of Reborn"
Install-RebornDlls -Win64 $win64 -ModDir (Join-Path $KitRoot 'mod')

Write-Step "Setting the server browser address"
$address = if ($Server) { ConvertTo-CoordinatorAddress $Server } else { Read-KitServerAddress $KitRoot }
while (-not $address) {
    $address = ConvertTo-CoordinatorAddress (Read-Host "    Server address from your host (for example bb.example.com:5000)")
}
Set-GameServerAddress -Win64 $win64 -Address $address

if (Test-CoordinatorReachable $address) {
    Write-Ok "Server browser is online."
}
else {
    Write-Warn "Couldn't reach http://$address right now. If the host's server is up, check the address and their port forward."
}

Write-Step "Creating a desktop shortcut"
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Battleborn Reborn.lnk'))
    $shortcut.TargetPath = "steam://rungameid/$Script:BattlebornAppId"
    $exe = Join-Path $win64 'Battleborn.exe'
    if (Test-Path $exe) { $shortcut.IconLocation = "$exe,0" }
    $shortcut.Save()
    Write-Ok "Battleborn Reborn.lnk"
}
catch {
    Write-Warn "Couldn't create the shortcut; launch Battleborn from Steam instead."
}

Write-Host ""
Write-Host "All set. Launch Battleborn and pick any *Public* mode (Versus, Story or Operations)." -ForegroundColor Green
Write-Host "That opens the server browser; pick a match and press Join." -ForegroundColor Green
