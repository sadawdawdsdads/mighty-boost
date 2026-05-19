# ScheduledTasks.ps1 - disable/enable scheduled tasks (telemetry collectors etc).

function Invoke-MBTaskAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Action)
    $path = $Action.path
    $name = $Action.name
    try {
        $t = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop
        if ($Action.state -eq 'Disabled') {
            $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            Write-MBLog "task disabled: $path$name" -Level ACTION
        } elseif ($Action.state -eq 'Ready' -or $Action.state -eq 'Enabled') {
            $t | Enable-ScheduledTask -ErrorAction Stop | Out-Null
            Write-MBLog "task enabled: $path$name" -Level ACTION
        }
    } catch {
        Write-MBLog "task $name ($path) not found or failed: $($_.Exception.Message)" -Level WARN
    }
}
