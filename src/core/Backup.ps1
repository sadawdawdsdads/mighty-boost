# Backup.ps1 - System Restore Point + per-action .reg snapshots.

$script:MBCheckpointThrottleKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'

function New-MBRestorePoint {
    [CmdletBinding()]
    param(
        [string]$Description = "MightyBoost session $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        [switch]$Force
    )
    try {
        # Enable System Restore on system drive if disabled.
        $sysDrive = $env:SystemDrive
        try { Enable-ComputerRestore -Drive $sysDrive -ErrorAction Stop } catch {
            Write-MBLog "Enable-ComputerRestore: $($_.Exception.Message)" -Level WARN
        }
        # Bypass the 24h throttle if -Force.
        if ($Force) {
            try {
                Set-ItemProperty -Path $script:MBCheckpointThrottleKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -Force
            } catch {}
        }
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-MBLog "Restore point created: $Description" -Level ACTION
        return $true
    } catch {
        Write-MBLog "Restore point failed: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-MBRestorePoints {
    try { Get-ComputerRestorePoint | Sort-Object CreationTime -Descending } catch { @() }
}

function New-MBRegBackup {
    <#
    .SYNOPSIS Export one or more registry keys to .reg files in the backup folder.
    .PARAMETER Keys Array of registry paths (HKLM:\..., HKCU:\...).
    .PARAMETER TweakId  Used to namespace the backup folder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$Keys,
        [Parameter(Mandatory)] [string]$TweakId
    )
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir   = Join-Path $global:MB.BackupDir "$stamp-$TweakId"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $exported = @()
    foreach ($key in $Keys) {
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $regPath = $key -replace '^HKLM:\\', 'HKLM\' `
                       -replace '^HKCU:\\', 'HKCU\' `
                       -replace '^HKCR:\\', 'HKCR\' `
                       -replace '^HKU:\\', 'HKU\'
        $safe   = ($key -replace '[\\:]+','_') -replace '[^\w\-]+','_'
        $file   = Join-Path $dir "$safe.reg"
        try {
            $proc = Start-Process -FilePath 'reg.exe' -ArgumentList @('export', "`"$regPath`"", "`"$file`"", '/y') `
                -WindowStyle Hidden -PassThru -Wait
            if ($proc.ExitCode -eq 0 -and (Test-Path $file)) {
                $exported += $file
            }
        } catch {
            Write-MBLog "reg export failed for $key : $($_.Exception.Message)" -Level WARN
        }
    }
    if ($exported.Count -gt 0) {
        Write-MBLog "Backed up $($exported.Count) registry key(s) to $dir" -Level INFO
    }
    return [pscustomobject]@{ Folder = $dir; Files = $exported }
}

function Restore-MBRegBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegFile)
    if (-not (Test-Path $RegFile)) { throw "Backup file not found: $RegFile" }
    $proc = Start-Process -FilePath 'reg.exe' -ArgumentList @('import', "`"$RegFile`"") `
        -WindowStyle Hidden -PassThru -Wait
    if ($proc.ExitCode -ne 0) { throw "reg import returned $($proc.ExitCode) for $RegFile" }
    Write-MBLog "Restored registry from $RegFile" -Level ACTION
}
