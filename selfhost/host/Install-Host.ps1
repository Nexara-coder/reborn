<#
.SYNOPSIS
    Turns a Windows PC or VM with Battleborn into a Battleborn Reborn server host:
    server browser (game coordinator) + on-demand Serverborn match servers.

.PARAMETER PublicHost
    Address players connect to: a DuckDNS/DNS name or your public IP. Use the LAN IP for LAN-only play.

.PARAMETER MaxMatches
    How many matches may run at once. Roughly one per 2-3 GB of free RAM.

.PARAMETER FirstGamePort
    First game port. Matches use FirstGamePort .. FirstGamePort+MaxMatches-1.

.PARAMETER InstallDir
    Where the coordinator and scripts go.

.PARAMETER GameDir
    Battleborn folder, if it isn't in a Steam library.
#>
[CmdletBinding()]
param(
    [string]$PublicHost,
    [int]$MaxMatches = 3,
    [int]$FirstGamePort = 7777,
    [string]$InstallDir = "$env:SystemDrive\BattlebornHost",
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$KitRoot = $PSScriptRoot
. (Join-Path $KitRoot 'BattlebornCommon.ps1')

$CoordinatorPort = 5000

Write-Host "Battleborn Reborn - host setup" -ForegroundColor White

if (-not (Test-IsAdmin)) {
    Write-Warn "Needs administrator rights (firewall rules and startup task). Re-launching elevated..."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($entry in $PSBoundParameters.GetEnumerator()) { $argList += "-$($entry.Key)", "`"$($entry.Value)`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit 0
}

# --- Game -------------------------------------------------------------------------------------
Write-Step "Finding Battleborn"
$win64 = Find-BattlebornWin64 -GameDir $GameDir
if (-not $win64) {
    Request-BattlebornInstall
    exit 1
}
Write-Ok $win64

Write-Step "Installing the self-host build of Reborn"
if (-not (Test-Path (Join-Path $win64 'reborn.dll'))) {
    Write-Warn "Official Reborn isn't installed here. Install it once from https://bereborn.dev first if the game fails to start."
}
Install-RebornDlls -Win64 $win64 -ModDir (Join-Path $KitRoot 'mod')

Write-Step "Creating Serverborn.exe (the dedicated server is a renamed copy of the game)"
$gameExe = Join-Path $win64 'Battleborn.exe'
$serverExe = Join-Path $win64 'Serverborn.exe'
$needsCopy = -not (Test-Path $serverExe) -or
    ((Get-FileHash $gameExe).Hash -ne (Get-FileHash $serverExe).Hash)
if ($needsCopy) {
    Copy-Item $gameExe $serverExe -Force
    Write-Ok "Serverborn.exe created"
}
else {
    Write-Ok "Serverborn.exe already up to date"
}

# --- Settings ---------------------------------------------------------------------------------
Write-Step "Server settings"
$settingsFile = Join-Path $InstallDir 'host-settings.json'
$existing = $null
if (Test-Path $settingsFile) {
    $existing = Get-Content $settingsFile -Raw | ConvertFrom-Json
}

if (-not $PublicHost -and $existing) { $PublicHost = $existing.PublicHost }
while (-not $PublicHost) {
    $PublicHost = (Read-Host "    Address players will use (DuckDNS name, public IP, or LAN IP)").Trim()
}

$rconToken = if ($existing -and $existing.RconPassword) { $existing.RconPassword } else {
    $bytes = New-Object byte[] 18
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($bytes)
    $rng.Dispose()
    [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'B')
}

$settings = [ordered]@{
    PublicHost      = $PublicHost
    CoordinatorPort = $CoordinatorPort
    FirstGamePort   = $FirstGamePort
    MaxMatches      = $MaxMatches
    ServerbornPath  = $serverExe
    RconPassword    = $rconToken
}

New-Item -ItemType Directory -Force $InstallDir | Out-Null
$settings | ConvertTo-Json | Set-Content $settingsFile -Encoding utf8
# Only admins and SYSTEM may read the file holding the RCON password.
icacls $settingsFile /inheritance:r /grant:r "*S-1-5-32-544:F" "*S-1-5-18:F" "${env:USERNAME}:F" | Out-Null
Write-Ok "Saved $settingsFile"

# --- Coordinator ------------------------------------------------------------------------------
Write-Step "Installing the server browser (game coordinator)"
$coordinatorSource = Join-Path $KitRoot 'coordinator'
$coordinatorDir = Join-Path $InstallDir 'coordinator'
if (-not (Test-Path (Join-Path $coordinatorSource 'gamecontroller.exe'))) {
    throw "Missing coordinator\gamecontroller.exe in the kit. Use a kit built by the GitHub Action."
}
Get-Process gamecontroller -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force $coordinatorDir | Out-Null
# Keep telemetry.db across upgrades.
Copy-Item (Join-Path $coordinatorSource '*') $coordinatorDir -Recurse -Force -Exclude 'telemetry.db'
Copy-Item (Join-Path $KitRoot 'Start-Coordinator.ps1'), (Join-Path $KitRoot 'Start-FixedServers.ps1'), (Join-Path $KitRoot 'BattlebornCommon.ps1') $InstallDir -Force
if (Test-Path (Join-Path $KitRoot 'fixed-servers.csv')) {
    $csvTarget = Join-Path $InstallDir 'fixed-servers.csv'
    if (-not (Test-Path $csvTarget)) { Copy-Item (Join-Path $KitRoot 'fixed-servers.csv') $csvTarget }
}
Write-Ok $coordinatorDir

# --- Firewall ---------------------------------------------------------------------------------
Write-Step "Opening Windows Firewall"
$lastGamePort = $FirstGamePort + $MaxMatches - 1
Get-NetFirewallRule -DisplayName 'Battleborn Reborn*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Battleborn Reborn - server browser' -Direction Inbound -Protocol TCP `
    -LocalPort $CoordinatorPort -Action Allow -Profile Any | Out-Null
foreach ($proto in 'UDP', 'TCP') {
    New-NetFirewallRule -DisplayName "Battleborn Reborn - game servers ($proto)" -Direction Inbound -Protocol $proto `
        -LocalPort "$FirstGamePort-$lastGamePort" -Action Allow -Profile Any | Out-Null
}
New-NetFirewallRule -DisplayName 'Battleborn Reborn - Serverborn.exe' -Direction Inbound -Program $serverExe `
    -Action Allow -Profile Any | Out-Null
Write-Ok "TCP $CoordinatorPort, UDP/TCP $FirstGamePort-$lastGamePort"

$fixedCsv = Join-Path $InstallDir 'fixed-servers.csv'
if (Test-Path $fixedCsv) {
    $fixedPorts = @(Import-Csv $fixedCsv | Where-Object { $_.Port -match '^\d+$' } | ForEach-Object { $_.Port })
    if ($fixedPorts) {
        foreach ($proto in 'UDP', 'TCP') {
            New-NetFirewallRule -DisplayName "Battleborn Reborn - fixed servers ($proto)" -Direction Inbound -Protocol $proto `
                -LocalPort $fixedPorts -Action Allow -Profile Any | Out-Null
        }
        Write-Ok "Fixed servers (fixed-servers.csv): $($fixedPorts -join ', ')"
    }
}

# --- Startup task -----------------------------------------------------------------------------
Write-Step "Starting the server browser when you sign in"
# Serverborn is the full game and needs a desktop session, so this runs at logon rather than as a service.
$taskName = 'Battleborn Reborn Server Browser'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$InstallDir\Start-Coordinator.ps1`"" `
    -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $taskSettings `
    -Principal $principal -Force | Out-Null
Write-Ok "Scheduled task '$taskName'"

# --- Player kit -------------------------------------------------------------------------------
Write-Step "Making the player kit for your friends"
$playerZip = Join-Path $KitRoot 'BattlebornReborn-player.zip'
$address = "${PublicHost}:$CoordinatorPort"
if (Test-Path $playerZip) {
    $staging = Join-Path $env:TEMP "bbr-player-$(Get-Random)"
    Expand-Archive $playerZip $staging -Force
    @(
        '# Server browser address for this kit (host:port).',
        $address
    ) | Set-Content (Join-Path $staging 'server.txt') -Encoding ascii
    $outZip = Join-Path ([Environment]::GetFolderPath('Desktop')) "BattlebornReborn-player-$($PublicHost -replace '[^\w.-]', '_').zip"
    Compress-Archive (Join-Path $staging '*') $outZip -Force
    Remove-Item $staging -Recurse -Force
    Write-Ok "Send players: $outZip"
}
else {
    Write-Warn "BattlebornReborn-player.zip isn't in this kit; send players the player kit and have them enter $address."
}

# This PC's own game client uses the local server browser.
Set-GameServerAddress -Win64 $win64 -Address "localhost:$CoordinatorPort"

# --- Start and check --------------------------------------------------------------------------
Write-Step "Starting the server browser"
Start-ScheduledTask -TaskName $taskName
$up = $false
foreach ($i in 1..15) {
    Start-Sleep -Seconds 1
    if (Test-CoordinatorReachable "localhost:$CoordinatorPort") { $up = $true; break }
}
if ($up) { Write-Ok "Running at http://localhost:$CoordinatorPort/api/games" }
else { Write-Warn "Didn't answer yet. Check the minimized PowerShell window or $InstallDir\coordinator.log" }

Write-Host ""
Write-Host "Host ready." -ForegroundColor Green
Write-Host "  RCON password (needed to create matches in-game): $rconToken" -ForegroundColor White
Write-Host "  Router: forward TCP $CoordinatorPort and UDP $FirstGamePort-$lastGamePort to this machine" -ForegroundColor White
Write-Host "          (plus the ports in fixed-servers.csv if you use Start-FixedServers.ps1)." -ForegroundColor White
Write-Host "  To create a match: launch Battleborn here (or anywhere), pick a Public mode," -ForegroundColor White
Write-Host "  press 'RCON Admin', choose the map, set players, enter the RCON password." -ForegroundColor White
