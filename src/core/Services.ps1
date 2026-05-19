# Services.ps1 - service start/stop with state capture for undo.

$script:MBStartupMap = @{
    'Automatic'         = 'Automatic'
    'AutomaticDelayed'  = 'AutomaticDelayedStart'
    'Manual'            = 'Manual'
    'Disabled'          = 'Disabled'
    'Boot'              = 'Boot'
    'System'            = 'System'
}

function Get-MBServiceState {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name    = $svc.Name
        Status  = $svc.Status.ToString()
        Startup = if ($wmi) { $wmi.StartMode } else { 'Unknown' }
        Exists  = $true
    }
}

function Invoke-MBServiceAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Action)
    $name = $Action.name
    $svc  = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-MBLog "Service '$name' not found - skipped" -Level WARN
        return
    }
    if ($Action.startup) {
        $key = [string]$Action.startup
        $mapped = if ($script:MBStartupMap.ContainsKey($key)) { $script:MBStartupMap[$key] } else { $key }
        try {
            Set-Service -Name $name -StartupType $mapped -ErrorAction Stop
            Write-MBLog "svc startup $name -> $mapped" -Level ACTION
        } catch {
            Write-MBLog "svc startup $name failed: $($_.Exception.Message)" -Level WARN
        }
    }
    if ($Action.stop -eq $true) {
        try {
            if ($svc.Status -ne 'Stopped') { Stop-Service -Name $name -Force -ErrorAction Stop }
            Write-MBLog "svc stop $name" -Level ACTION
        } catch {
            Write-MBLog "svc stop $name failed: $($_.Exception.Message)" -Level WARN
        }
    }
    if ($Action.start -eq $true) {
        try {
            Start-Service -Name $name -ErrorAction Stop
            Write-MBLog "svc start $name" -Level ACTION
        } catch {
            Write-MBLog "svc start $name failed: $($_.Exception.Message)" -Level WARN
        }
    }
}
