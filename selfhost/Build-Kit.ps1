<#
.SYNOPSIS
    Builds the player and host kits locally (same steps as the GitHub Action).
    Needs Visual Studio 2022 (or Build Tools) with "Desktop development with C++", and the .NET 9 SDK.
    Run from a "Developer PowerShell for VS 2022" so msbuild is on PATH.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$out = Join-Path $repo 'out'
Push-Location $repo
try {
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Get-Command msbuild -ErrorAction SilentlyContinue)) {
        throw "msbuild not found. Open 'Developer PowerShell for VS 2022' and run this again."
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "dotnet not found. Install the .NET 9 SDK: winget install Microsoft.DotNet.SDK.9"
    }

    $mod = Join-Path $out 'mod\'
    foreach ($project in 'reborn\reborn.vcxproj', 'dxgi\dxgi.vcxproj') {
        msbuild $project /m /p:Configuration=Release /p:Platform=x64 "/p:OutDir=$mod"
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
    }

    dotnet publish gamecontroller\gamecontroller.csproj -c Release -r win-x64 --self-contained true -o (Join-Path $out 'coordinator')
    if ($LASTEXITCODE -ne 0) { throw "Coordinator publish failed" }

    foreach ($kit in 'player', 'host') {
        $dir = Join-Path $out "BattlebornReborn-$kit"
        New-Item -ItemType Directory -Force (Join-Path $dir 'mod') | Out-Null
        Copy-Item (Join-Path $mod 'reborn.dll'), (Join-Path $mod 'dxgi.dll') (Join-Path $dir 'mod')
        Copy-Item "selfhost\$kit\*" $dir -Recurse
        Copy-Item 'selfhost\common\*' $dir
        Copy-Item 'selfhost\README.md', 'LICENSE.txt' $dir
    }
    Copy-Item (Join-Path $out 'coordinator') (Join-Path $out 'BattlebornReborn-host\coordinator') -Recurse
    Compress-Archive (Join-Path $out 'BattlebornReborn-player\*') (Join-Path $out 'BattlebornReborn-player.zip') -Force
    Copy-Item (Join-Path $out 'BattlebornReborn-player.zip') (Join-Path $out 'BattlebornReborn-host')
    Compress-Archive (Join-Path $out 'BattlebornReborn-host\*') (Join-Path $out 'BattlebornReborn-host.zip') -Force

    Write-Host "Built:" -ForegroundColor Green
    Get-ChildItem (Join-Path $out '*.zip') | ForEach-Object { Write-Host "  $($_.FullName)" }
}
finally {
    Pop-Location
}
