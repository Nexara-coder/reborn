# Shared helpers for the Battleborn Reborn self-host kit. Dot-source this file.

$Script:BattlebornAppId = 394230

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Get-SteamPath {
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($name in 'SteamPath', 'InstallPath') {
            if ($item -and $item.$name -and (Test-Path $item.$name)) {
                return (Resolve-Path $item.$name).Path
            }
        }
    }
    return $null
}

function Get-SteamLibraryFolders {
    $steam = Get-SteamPath
    if (-not $steam) { return @() }

    $folders = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($match in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $folders += $match.Groups[1].Value -replace '\\\\', '\'
        }
    }
    return $folders | Select-Object -Unique
}

# Returns the Battleborn\Binaries\Win64 folder, or $null if Battleborn isn't installed.
function Find-BattlebornWin64 {
    param([string]$GameDir)

    $candidates = @()
    if ($GameDir) { $candidates += $GameDir }
    foreach ($lib in Get-SteamLibraryFolders) {
        $candidates += Join-Path $lib 'steamapps\common\Battleborn'
    }

    foreach ($dir in $candidates) {
        foreach ($win64 in @((Join-Path $dir 'Binaries\Win64'), $dir)) {
            if (Test-Path (Join-Path $win64 'Battleborn.exe')) {
                return (Resolve-Path $win64).Path
            }
        }
    }
    return $null
}

function Request-BattlebornInstall {
    Write-Warn "Battleborn isn't installed in any Steam library on this PC."
    Write-Warn "The free trial still installs from Steam and is enough for Reborn."
    $answer = Read-Host "    Open Steam to install Battleborn now? [Y/n]"
    if ($answer -notmatch '^[Nn]') {
        Start-Process "steam://install/$Script:BattlebornAppId"
        Write-Warn "Let the download finish in Steam, then run this installer again."
    }
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Copies the kit's reborn.dll + dxgi.dll into the game, keeping a one-time backup of whatever was there.
function Install-RebornDlls {
    param(
        [Parameter(Mandatory)] [string]$Win64,
        [Parameter(Mandatory)] [string]$ModDir
    )

    foreach ($dll in 'reborn.dll', 'dxgi.dll') {
        $source = Join-Path $ModDir $dll
        if (-not (Test-Path $source)) {
            throw "Missing $source. Use a kit built by the GitHub Action (it puts the DLLs in .\mod)."
        }

        $target = Join-Path $Win64 $dll
        $backup = "$target.official-backup"
        $noneMarker = "$target.official-none"
        # Record the original state only on the first install, so re-running never backs up our own DLL.
        if (-not (Test-Path $backup) -and -not (Test-Path $noneMarker)) {
            if (Test-Path $target) {
                Copy-Item $target $backup
                Write-Ok "Backed up existing $dll -> $(Split-Path $backup -Leaf)"
            }
            else {
                New-Item -ItemType File $noneMarker | Out-Null
            }
        }

        Copy-Item $source $target -Force
        Write-Ok "Installed $dll"
    }
}

function Restore-RebornDlls {
    param([Parameter(Mandatory)] [string]$Win64)

    foreach ($dll in 'reborn.dll', 'dxgi.dll') {
        $target = Join-Path $Win64 $dll
        $backup = "$target.official-backup"
        $noneMarker = "$target.official-none"
        if (Test-Path $backup) {
            Move-Item $backup $target -Force
            Write-Ok "Restored original $dll"
        }
        elseif (Test-Path $noneMarker) {
            Remove-Item $target -Force -ErrorAction SilentlyContinue
            Remove-Item $noneMarker -Force
            Write-Ok "Removed $dll"
        }
    }
}

# host:port, host alone (port 5000 assumed), or empty.
function ConvertTo-CoordinatorAddress([string]$Value) {
    $value = ($Value -replace '^\s*https?://', '').Trim().TrimEnd('/')
    if (-not $value) { return $null }
    if ($value -notmatch ':\d+$') { $value = "${value}:5000" }
    return $value
}

function Read-KitServerAddress([string]$KitRoot) {
    $file = Join-Path $KitRoot 'server.txt'
    if (Test-Path $file) {
        foreach ($line in Get-Content $file) {
            $line = $line.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line -notmatch 'CHANGE-ME') {
                return ConvertTo-CoordinatorAddress $line
            }
        }
    }
    return $null
}

function Set-GameServerAddress {
    param(
        [Parameter(Mandatory)] [string]$Win64,
        [Parameter(Mandatory)] [string]$Address
    )

    $file = Join-Path $Win64 'reborn_server.txt'
    @(
        '# Battleborn Reborn server browser address (host:port).',
        '# Delete this file to go back to the official Reborn servers.',
        $Address
    ) | Set-Content -Path $file -Encoding ascii
    Write-Ok "Server browser now points at $Address"
}

function Test-CoordinatorReachable([string]$Address) {
    try {
        $response = Invoke-WebRequest -Uri "http://$Address/api/games" -UseBasicParsing -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}
