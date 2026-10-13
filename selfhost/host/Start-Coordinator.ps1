<#
.SYNOPSIS
    Runs the Battleborn Reborn server browser (game coordinator) with this host's settings,
    restarting it if it stops. Started at logon by the scheduled task Install-Host.ps1 creates.
#>
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$settings = Get-Content (Join-Path $root 'host-settings.json') -Raw | ConvertFrom-Json

$env:RCON_TOKEN      = $settings.RconPassword
$env:GC_PUBLIC_HOST  = $settings.PublicHost
$env:GC_INTERNAL_URL = "localhost:$($settings.CoordinatorPort)"
$env:SERVERBORN_PATH = $settings.ServerbornPath
$env:GAME_PORT_START = "$($settings.FirstGamePort)"
$env:GAME_PORT_COUNT = "$($settings.MaxMatches)"
$env:ASPNETCORE_URLS = "http://0.0.0.0:$($settings.CoordinatorPort)"

$exe = Join-Path $root 'coordinator\gamecontroller.exe'
$log = Join-Path $root 'coordinator.log'

# Never run two copies; a second one would fail to bind the port anyway.
if (Get-Process gamecontroller -ErrorAction SilentlyContinue) {
    Write-Host "Server browser is already running."
    exit 0
}

while ($true) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 20MB) {
        Move-Item $log "$log.old" -Force
    }

    "---- $(Get-Date -Format s) starting server browser on port $($settings.CoordinatorPort) ----" | Out-File $log -Append -Encoding utf8
    # telemetry.db is created in the working directory.
    Push-Location (Join-Path $root 'coordinator')
    try {
        & $exe 2>&1 | ForEach-Object { "$_" } | Out-File $log -Append -Encoding utf8
    }
    finally {
        Pop-Location
    }
    "---- $(Get-Date -Format s) server browser exited ($LASTEXITCODE); restarting in 5s ----" | Out-File $log -Append -Encoding utf8
    Start-Sleep -Seconds 5
}
