# Cleanup.ps1 - safe junk/cache cleanup with size preview.

$script:MBCleanupTargets = @(
    @{ Id='temp-user';   Name=@{ru='Временные файлы пользователя'; en='User temp files'}; Path=$env:TEMP },
    @{ Id='temp-windows';Name=@{ru='Временные файлы Windows';     en='Windows temp files'}; Path="$env:SystemRoot\Temp" },
    @{ Id='prefetch';    Name=@{ru='Prefetch';                    en='Prefetch'};           Path="$env:SystemRoot\Prefetch" },
    @{ Id='delivery';    Name=@{ru='Кэш Delivery Optimization';   en='Delivery Optimization cache'}; Path="$env:SystemRoot\SoftwareDistribution\Download" },
    @{ Id='recyclebin';  Name=@{ru='Корзина';                     en='Recycle Bin'};        Path=$null; Special='Recycle' },
    @{ Id='cbslogs';     Name=@{ru='Журналы CBS';                 en='CBS logs'};           Path="$env:SystemRoot\Logs\CBS" },
    @{ Id='evtlogs';     Name=@{ru='Журналы событий Windows';     en='Windows event logs'}; Path=$null; Special='EventLog' },
    @{ Id='thumbnails';  Name=@{ru='Кэш миниатюр';                en='Thumbnail cache'};    Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
)

function Get-MBCleanupTargets { $script:MBCleanupTargets }

function Get-MBFolderSize {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { return 0 }
        return [int64]$sum
    } catch { return 0 }
}

function Invoke-MBCleanupTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Target)
    $bytesBefore = 0
    if ($Target.Special -eq 'Recycle') {
        try {
            $shell = New-Object -ComObject Shell.Application
            $bin = $shell.Namespace(10)
            $items = @($bin.Items())
            foreach ($i in $items) { $bytesBefore += [int64]$i.Size }
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-MBLog "cleanup: recycle bin emptied" -Level ACTION
            return $bytesBefore
        } catch { return 0 }
    }
    if ($Target.Special -eq 'EventLog') {
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue
        $cleared = 0
        foreach ($l in $logs) {
            if ($l.RecordCount -gt 0) {
                try { wevtutil.exe cl $l.LogName 2>$null; $cleared++ } catch {}
            }
        }
        Write-MBLog "cleanup: cleared $cleared event logs" -Level ACTION
        return 0
    }
    $path = $Target.Path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return 0 }
    $bytesBefore = Get-MBFolderSize -Path $path
    try {
        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-MBLog ("cleanup: {0} ({1:N1} MB)" -f $path, ($bytesBefore/1MB)) -Level ACTION
    } catch {
        Write-MBLog "cleanup failed $path : $($_.Exception.Message)" -Level WARN
    }
    return $bytesBefore
}
