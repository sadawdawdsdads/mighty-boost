#Requires -Version 5.1
<#
.SYNOPSIS
    MightyBoost - Windows 10/11 optimizer with one-liner launch.
.DESCRIPTION
    Entry point. Bootstraps the GUI, downloads/loads modules and data,
    handles UAC elevation, and starts the WPF application.
.NOTES
    Project:  MightyBoost
    License:  MIT
    Repo:     https://github.com/sadawdawdsdads/mighty-boost
    Launch:   irm https://raw.githubusercontent.com/sadawdawdsdads/mighty-boost/main/boost.ps1 | iex
#>

# Optional parameters (work both with `.\boost.ps1` invocation and with `irm | iex`):
#   $Branch    : branch to fetch modules from (default: 'main')
#   $Local     : force local mode - read modules from $PWD instead of GitHub
#   $NoElevate : skip the auto-elevation prompt
# To pass them via irm | iex, set the variable before piping:
#   $Branch = 'dev'; irm '...' | iex
if (-not (Test-Path Variable:Branch))    { $Branch    = 'main' }
if (-not (Test-Path Variable:Local))     { $Local     = $false }
if (-not (Test-Path Variable:NoElevate)) { $NoElevate = $false }

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------- Globals ----------
$global:MB = [ordered]@{
    Name        = 'MightyBoost'
    Version     = '0.1.0'
    RepoOwner   = 'sadawdawdsdads'
    RepoName    = 'mighty-boost'
    Branch      = $Branch
    AppDataDir  = Join-Path $env:APPDATA 'MightyBoost'
    LogDir      = Join-Path $env:APPDATA 'MightyBoost\Logs'
    BackupDir   = Join-Path $env:APPDATA 'MightyBoost\Backups'
    DataDir     = Join-Path $env:APPDATA 'MightyBoost\Data'
    AppliedFile = Join-Path $env:APPDATA 'MightyBoost\applied.json'
    StartedAt   = Get-Date
    IsLocal     = [bool]$Local
    RootDir     = $null
    Culture     = (Get-Culture).TwoLetterISOLanguageName
}

foreach ($dir in @($global:MB.AppDataDir, $global:MB.LogDir, $global:MB.BackupDir, $global:MB.DataDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ---------- Detect run mode (local script vs irm | iex) ----------
if ($Local -or $PSCommandPath) {
    $global:MB.IsLocal = $true
    $global:MB.RootDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
} else {
    $global:MB.IsLocal = $false
    $global:MB.RootDir = $global:MB.DataDir
}

# ---------- Banner ----------
function Write-Banner {
    $b = @"

  __  __ _       _     _         ____                  _
 |  \/  (_) __ _| |__ | |_ _   _| __ )  ___   ___  ___| |_
 | |\/| | |/ _` | '_ \| __| | | |  _ \ / _ \ / _ \/ __| __|
 | |  | | | (_| | | | | |_| |_| | |_) | (_) | (_) \__ \ |_
 |_|  |_|_|\__, |_| |_|\__|\__, |____/ \___/ \___/|___/\__|
           |___/           |___/                  v$($global:MB.Version)

  Windows 10/11 optimizer  -  MIT licensed  -  github.com/$($global:MB.RepoOwner)/$($global:MB.RepoName)

"@
    Write-Host $b -ForegroundColor Cyan
}
Write-Banner

# ---------- Admin check ----------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    if ($NoElevate) {
        Write-Warning 'Running without admin rights. Many tweaks will fail.'
        return
    }
    Write-Host '[+] Re-launching with administrator privileges...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($global:MB.IsLocal -and $PSCommandPath) {
        $argList += @('-File', "`"$PSCommandPath`"")
    } else {
        $url = "https://raw.githubusercontent.com/$($global:MB.RepoOwner)/$($global:MB.RepoName)/$Branch/boost.ps1"
        $argList += @('-Command', "irm '$url' | iex")
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Error "Elevation failed: $($_.Exception.Message)"
        return
    }
    exit 0
}

if (-not (Test-Admin)) { Request-Elevation }

# ---------- Module loader ----------
$ModuleNames = @(
    'Logger', 'OSDetect', 'I18n', 'Backup',
    'Registry', 'Services', 'AppxDebloat', 'ScheduledTasks',
    'Cleanup', 'Winget', 'App'
)

function Get-MBSource {
    param(
        [Parameter(Mandatory)] [string]$RelativePath
    )
    if ($global:MB.IsLocal) {
        $local = Join-Path $global:MB.RootDir $RelativePath
        if (Test-Path $local) { return Get-Content -LiteralPath $local -Raw -Encoding UTF8 }
    }
    $url = "https://raw.githubusercontent.com/$($global:MB.RepoOwner)/$($global:MB.RepoName)/$($global:MB.Branch)/$RelativePath"
    return (Invoke-RestMethod -Uri $url -ErrorAction Stop)
}

Write-Host "[+] Loading modules..." -ForegroundColor Green
foreach ($m in $ModuleNames) {
    try {
        $code = Get-MBSource -RelativePath "src/core/$m.ps1"
        $sb   = [scriptblock]::Create($code)
        . $sb
    } catch {
        Write-Error "Failed to load module $m : $($_.Exception.Message)"
        return
    }
}

# ---------- Start application ----------
try {
    Start-MBApp
} catch {
    Write-Host ""
    Write-Host "[!] Unrecoverable error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    See log file: $($global:MB.LogDir)" -ForegroundColor DarkYellow
    if (-not $global:MB.IsLocal) { Read-Host 'Press Enter to exit' }
    exit 1
}
