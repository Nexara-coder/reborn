<#
.SYNOPSIS
    Runs always-on Serverborn instances listed in fixed-servers.csv, restarting each one when its match ends.
    Players join these with Direct Connect (host:port) instead of the server browser.

    Use this for a permanent "Incursion on 7777, Capture on 7778" style setup. Keep these ports
    outside the range the server browser uses (FirstGamePort .. FirstGamePort+MaxMatches-1).
#>
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'fixed-servers.csv')
)

$ErrorActionPreference = 'Stop'
$settings = Get-Content (Join-Path $PSScriptRoot 'host-settings.json') -Raw | ConvertFrom-Json
$serverExe = $settings.ServerbornPath
$serverDir = Split-Path $serverExe

$servers = Import-Csv $ConfigFile | Where-Object { $_.Port -and -not $_.Port.StartsWith('#') }
if (-not $servers) { throw "No servers in $ConfigFile" }

$browserPorts = $settings.FirstGamePort..($settings.FirstGamePort + $settings.MaxMatches - 1)
foreach ($server in $servers) {
    if ([int]$server.Port -in $browserPorts) {
        throw "Port $($server.Port) is reserved for server-browser matches; pick another in fixed-servers.csv."
    }
}

$running = @{}
Write-Host "Running $(@($servers).Count) fixed server(s). Press Ctrl+C to stop watching (servers keep running)."

while ($true) {
    foreach ($server in $servers) {
        $proc = $running[$server.Port]
        if (-not $proc -or $proc.HasExited) {
            $arguments = "-SEEKFREEPACKAGEMAP -SEEKFREELOADINGPCCONSOLE -RebornPort=$($server.Port) -RebornMap=$($server.Map) -RebornPlayers=$($server.PlayersToStart)"
            $running[$server.Port] = Start-Process -FilePath $serverExe -ArgumentList $arguments -WorkingDirectory $serverDir -PassThru
            Write-Host "$(Get-Date -Format T)  $($server.Name): $($server.Map) on port $($server.Port) (starts at $($server.PlayersToStart) players)"
        }
    }
    Start-Sleep -Seconds 10
}
