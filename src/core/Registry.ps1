# Registry.ps1 - safe registry operations with backup-before-write.

function Test-MBHive {
    param([string]$Path)
    $prefix = ($Path -split ':')[0] + ':'
    switch ($prefix) {
        'HKLM:' { return $true }
        'HKCU:' { return $true }
        'HKCR:' { return $true }
        'HKU:'  { return $true }
        default { return $false }
    }
}

function Set-MBRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('String','ExpandString','Binary','DWord','MultiString','QWord')]
        [string]$Kind = 'DWord'
    )
    if (-not (Test-MBHive $Path)) { throw "Unsupported registry hive: $Path" }
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    Write-MBLog "reg set $Path :: $Name = $Value ($Kind)" -Level ACTION
}

function Remove-MBRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )
    if (-not (Test-Path $Path)) { return }
    try {
        Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
        Write-MBLog "reg del $Path :: $Name" -Level ACTION
    } catch {
        Write-MBLog "reg del failed $Path :: $Name : $($_.Exception.Message)" -Level WARN
    }
}

function Get-MBRegistryValueSafe {
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path $Path)) { return $null }
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch { return $null }
}

function Invoke-MBRegistryAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Action)
    if ($Action.delete) {
        Remove-MBRegistryValue -Path $Action.path -Name $Action.name
        return
    }
    $kind = if ($Action.kind) { [string]$Action.kind } else { 'DWord' }
    Set-MBRegistryValue -Path $Action.path -Name $Action.name -Value $Action.value -Kind $kind
}
