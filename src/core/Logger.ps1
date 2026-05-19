# Logger.ps1 - centralized timestamped logging.

$script:MBLogFile = Join-Path $global:MB.LogDir ("session-{0:yyyyMMdd-HHmmss}.log" -f $global:MB.StartedAt)
$global:MB.LogFile = $script:MBLogFile

function Write-MBLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG','ACTION')] [string]$Level = 'INFO',
        [switch]$NoConsole
    )
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1,-6}] {2}" -f $ts, $Level, $Message
    try { Add-Content -LiteralPath $script:MBLogFile -Value $line -Encoding UTF8 } catch {}
    if ($NoConsole) { return }
    switch ($Level) {
        'WARN'   { Write-Host $line -ForegroundColor Yellow }
        'ERROR'  { Write-Host $line -ForegroundColor Red }
        'DEBUG'  { Write-Host $line -ForegroundColor DarkGray }
        'ACTION' { Write-Host $line -ForegroundColor Cyan }
        default  { Write-Host $line -ForegroundColor Gray }
    }
}

function Get-MBLogPath { $script:MBLogFile }

Write-MBLog "MightyBoost v$($global:MB.Version) session started" -Level INFO
Write-MBLog "PowerShell: $($PSVersionTable.PSVersion) | Culture: $($global:MB.Culture)" -Level DEBUG
