# App.ps1 - CLI orchestration: JSON loader, tweak engine, applied-log, console menu.

# ------------------------------------------------------------------
# Data loaders
# ------------------------------------------------------------------
function Read-MBJson {
    param([Parameter(Mandatory)][string]$Relative)
    try {
        $raw = Get-MBSource -RelativePath $Relative
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-MBLog "Failed to load $Relative : $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Initialize-MBData {
    $global:MB.Data = [pscustomobject]@{
        Tweaks   = (Read-MBJson 'src/data/tweaks.json')
        Apps     = (Read-MBJson 'src/data/apps.json')
        Services = (Read-MBJson 'src/data/services.json')
        Debloat  = (Read-MBJson 'src/data/debloat.json')
        Tasks    = (Read-MBJson 'src/data/tasks.json')
        Presets  = (Read-MBJson 'src/data/presets.json')
    }
    Write-MBLog ("Loaded data: {0} tweaks, {1} apps, {2} services, {3} appx, {4} tasks" -f `
        @($global:MB.Data.Tweaks).Count, @($global:MB.Data.Apps).Count, `
        @($global:MB.Data.Services).Count, @($global:MB.Data.Debloat).Count, `
        @($global:MB.Data.Tasks).Count) -Level INFO
}

# ------------------------------------------------------------------
# applied.json - persistent record of every action for undo
# ------------------------------------------------------------------
function Read-MBApplied {
    if (-not (Test-Path $global:MB.AppliedFile)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $global:MB.AppliedFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch { return @() }
}

function Write-MBApplied {
    param([Parameter(Mandatory)]$Entries)
    ($Entries | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $global:MB.AppliedFile -Encoding UTF8
}

function Add-MBAppliedEntry {
    param([Parameter(Mandatory)][hashtable]$Entry)
    $list = @(Read-MBApplied)
    $list += [pscustomobject]$Entry
    Write-MBApplied -Entries $list
}

# ------------------------------------------------------------------
# Action dispatcher - the heart of the tweak engine
# ------------------------------------------------------------------
function Convert-MBAction {
    param($Action)
    $hash = @{}
    foreach ($p in $Action.PSObject.Properties) { $hash[$p.Name] = $p.Value }
    return $hash
}

function Get-MBRegistryKeysFromActions {
    param($Actions)
    $keys = @()
    foreach ($a in $Actions) {
        if ($a.type -eq 'registry' -and $a.path) { $keys += [string]$a.path }
    }
    return ($keys | Select-Object -Unique)
}

function Invoke-MBActionList {
    param(
        [Parameter(Mandatory)] $Actions,
        [string]$TweakId = 'adhoc'
    )
    $regKeys = Get-MBRegistryKeysFromActions -Actions $Actions
    if ($regKeys.Count -gt 0) { [void](New-MBRegBackup -Keys $regKeys -TweakId $TweakId) }
    foreach ($a in $Actions) {
        $action = Convert-MBAction -Action $a
        try {
            switch ($action.type) {
                'registry' { Invoke-MBRegistryAction -Action $action }
                'service'  { Invoke-MBServiceAction  -Action $action }
                'appx'     { Invoke-MBAppxAction     -Action $action }
                'task'     { Invoke-MBTaskAction     -Action $action }
                default    { Write-MBLog "Unknown action type: $($action.type)" -Level WARN }
            }
        } catch {
            Write-MBLog "action failed [$($action.type)] : $($_.Exception.Message)" -Level ERROR
        }
    }
}

function Invoke-MBTweak {
    param([Parameter(Mandatory)] $Tweak)
    if (-not (Test-MBOSCompatible -Win $Tweak.win)) {
        Write-MBLog "skip $($Tweak.id) - incompatible OS" -Level DEBUG
        return
    }
    Write-MBLog "APPLY tweak: $($Tweak.id)" -Level ACTION
    Invoke-MBActionList -Actions $Tweak.apply -TweakId $Tweak.id
    Add-MBAppliedEntry -Entry @{
        id        = $Tweak.id
        category  = $Tweak.category
        appliedAt = (Get-Date).ToString('s')
        undo      = $Tweak.undo
    }
}

function Undo-MBTweak {
    param([Parameter(Mandatory)][string]$Id)
    $applied = @(Read-MBApplied)
    $entry = $applied | Where-Object { $_.id -eq $Id } | Select-Object -Last 1
    if (-not $entry) { Write-MBLog "Undo: no applied entry for $Id" -Level WARN; return }
    Write-MBLog "UNDO tweak: $Id" -Level ACTION
    Invoke-MBActionList -Actions $entry.undo -TweakId "undo-$Id"
    $remaining = $applied | Where-Object { $_.id -ne $Id -or $_.appliedAt -ne $entry.appliedAt }
    Write-MBApplied -Entries @($remaining)
}

# ------------------------------------------------------------------
# Console helpers
# ------------------------------------------------------------------
function Write-MBLine { Write-Host ('-' * 70) -ForegroundColor DarkGray }
function Write-MBDouble { Write-Host ('=' * 70) -ForegroundColor Cyan }

function Write-MBHeader {
    param([string]$Title)
    Clear-Host
    Write-MBDouble
    Write-Host ("   " + $Title) -ForegroundColor Cyan
    Write-MBDouble
    Write-Host ""
}

function Read-MBChoice {
    param([string]$Prompt = 'Choice')
    Write-Host ""
    Write-Host -NoNewline ("   " + $Prompt + ": ") -ForegroundColor Yellow
    return (Read-Host)
}

function Pause-MB {
    Write-Host ""
    Write-Host -NoNewline '   Press Enter to continue...' -ForegroundColor DarkGray
    $null = Read-Host
}

function ConvertFrom-MBIndexInput {
    # "1 3 5-8 11" => @(1,3,5,6,7,8,11)
    param([string]$Selection, [int]$Max)
    $result = New-Object System.Collections.Generic.HashSet[int]
    foreach ($tok in ($Selection -split '[\s,]+' | Where-Object { $_ })) {
        if ($tok -match '^(\d+)-(\d+)$') {
            $a = [int]$matches[1]; $b = [int]$matches[2]
            if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
            for ($i = $a; $i -le $b; $i++) {
                if ($i -ge 1 -and $i -le $Max) { [void]$result.Add($i) }
            }
        } elseif ($tok -match '^\d+$') {
            $i = [int]$tok
            if ($i -ge 1 -and $i -le $Max) { [void]$result.Add($i) }
        } elseif ($tok -eq 'all' -or $tok -eq '*') {
            for ($i = 1; $i -le $Max; $i++) { [void]$result.Add($i) }
        }
    }
    return ($result | Sort-Object)
}

function Confirm-MB {
    param([string]$Message)
    Write-Host ""
    Write-Host -NoNewline ("   " + $Message + " [y/N]: ") -ForegroundColor Yellow
    $ans = Read-Host
    return ($ans -match '^(y|yes|д|да)$')
}

function Invoke-MBRebootPrompt {
    Write-Host ""
    Write-Host "   ============================================================" -ForegroundColor Yellow
    Write-Host "      Reboot recommended - some tweaks need a restart to apply" -ForegroundColor Yellow
    Write-Host "      Перезагрузка рекомендуется - часть твиков сработает после рестарта" -ForegroundColor Yellow
    Write-Host "   ============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '   [1] Restart now     / Перезагрузить сейчас'
    Write-Host '   [2] Restart later   / Позже (вручную)'
    Write-Host ''
    $c = Read-MBChoice 'Choose'
    if ($c.Trim() -eq '1') {
        Write-Host ''
        Write-Host '   Restarting in 10 seconds... (Ctrl+C to abort)' -ForegroundColor Red
        Write-MBLog 'User chose reboot now' -Level ACTION
        try {
            & shutdown.exe /r /t 10 /c "MightyBoost: applying tweaks - rebooting in 10 seconds" | Out-Null
        } catch {
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    } else {
        Write-Host '   OK - reboot when ready / Хорошо, перезагрузишь позже' -ForegroundColor DarkYellow
        Write-MBLog 'User chose reboot later' -Level INFO
    }
}

# ------------------------------------------------------------------
# Menu rendering
# ------------------------------------------------------------------
function Show-MBMainMenu {
    Write-MBHeader 'MightyBoost - main menu'
    $os = $global:MB.OS
    Write-Host ("   System  : Windows {0} {1} (build {2}.{3})" -f $os.Major, $os.DisplayVersion, $os.Build, $os.UBR)
    Write-Host ("   Hardware: {0} | {1} GB RAM | user {2}" -f $os.Arch, $os.TotalRAMGb, $os.UserName)
    Write-Host ("   App     : MightyBoost v{0} | locale '{1}' | log {2}" -f $global:MB.Version, $global:MB.Locale, (Split-Path -Leaf $global:MB.LogFile))
    Write-Host ""
    Write-MBLine

    $tweaks   = @($global:MB.Data.Tweaks)
    $privacy  = ($tweaks | Where-Object { $_.category -eq 'Privacy' }).Count
    $perform  = ($tweaks | Where-Object { $_.category -eq 'Performance' }).Count
    $gaming   = ($tweaks | Where-Object { $_.category -eq 'Gaming' }).Count
    $network  = ($tweaks | Where-Object { $_.category -eq 'Network' }).Count
    $uiCount  = ($tweaks | Where-Object { $_.category -eq 'UI' }).Count
    $applied  = @(Read-MBApplied).Count

    Write-Host ""
    Write-Host '   [1] Apply preset           (Safe / Balanced / Aggressive)'
    Write-Host ("   [2] Privacy tweaks         ({0})" -f $privacy)
    Write-Host ("   [3] Performance tweaks     ({0})" -f $perform)
    Write-Host ("   [4] Gaming tweaks          ({0})" -f $gaming)
    Write-Host ("   [5] Network tweaks         ({0})" -f $network)
    Write-Host ("   [6] UI tweaks              ({0})" -f $uiCount)
    Write-Host ("   [7] Debloat apps           ({0})" -f @($global:MB.Data.Debloat).Count)
    Write-Host ("   [8] Configure services     ({0})" -f @($global:MB.Data.Services).Count)
    Write-Host ("   [9] Install software       ({0})" -f @($global:MB.Data.Apps).Count)
    Write-Host '   [C] Cleanup junk files'
    Write-Host ("   [R] Restore (undo applied) (applied: {0})" -f $applied)
    Write-Host '   [P] Create restore point now'
    Write-Host '   [L] Show log file path'
    Write-Host '   [Q] Quit'
}

# ------------------------------------------------------------------
# Tweak selector for one category
# ------------------------------------------------------------------
function Invoke-MBCategoryMenu {
    param([string]$Category)
    $items = @($global:MB.Data.Tweaks | Where-Object { $_.category -eq $Category })
    if ($items.Count -eq 0) {
        Write-Host "   No tweaks in '$Category'." -ForegroundColor DarkGray
        Pause-MB; return
    }
    Write-MBHeader "$Category tweaks"
    Write-Host '   Enter numbers separated by spaces (e.g. "1 3 5"), ranges ("1-5"), or "all".'
    Write-Host ''
    for ($i = 0; $i -lt $items.Count; $i++) {
        $t = $items[$i]
        $name = Get-MBLocalized $t.name
        $compat = if (Test-MBOSCompatible -Win $t.win) { '  ' } else { '!!' }
        $presets = if ($t.presets) { ($t.presets -join ',') } else { '-' }
        Write-Host ("   [{0,3}] {1} {2,-58}  [{3}]" -f ($i + 1), $compat, $name, $presets)
    }
    $sel = Read-MBChoice 'Pick tweaks (empty = back)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $items.Count
    if (-not $idx -or $idx.Count -eq 0) {
        Write-Host '   Nothing selected.' -ForegroundColor DarkYellow
        Pause-MB; return
    }
    Write-Host ''
    Write-Host ("   Selected {0} tweak(s):" -f $idx.Count) -ForegroundColor Cyan
    foreach ($i in $idx) { Write-Host ("     - " + (Get-MBLocalized $items[$i - 1].name)) }
    if (-not (Confirm-MB 'Apply?')) { return }

    [void](New-MBRestorePoint)
    foreach ($i in $idx) { Invoke-MBTweak -Tweak $items[$i - 1] }
    Write-Host ''
    Write-Host ("   Applied {0} tweak(s)." -f $idx.Count) -ForegroundColor Green
    Invoke-MBRebootPrompt
    Pause-MB
}

# ------------------------------------------------------------------
# Preset
# ------------------------------------------------------------------
function Invoke-MBPresetMenu {
    Write-MBHeader 'Apply preset'
    Write-Host '   [1] Safe        - only reversible privacy/UI tweaks'
    Write-Host '   [2] Balanced    - good balance for daily driver'
    Write-Host '   [3] Aggressive  - max optimisation, disables more features'
    $c = Read-MBChoice 'Pick preset (empty = back)'
    $preset = switch ($c) {
        '1' { 'safe' }
        '2' { 'balanced' }
        '3' { 'aggressive' }
        default { return }
    }
    $tweaks = @($global:MB.Data.Tweaks | Where-Object { $_.presets -contains $preset -and (Test-MBOSCompatible -Win $_.win) })
    Write-Host ''
    Write-Host ("   '{0}' preset = {1} tweak(s):" -f $preset, $tweaks.Count) -ForegroundColor Cyan
    foreach ($t in $tweaks) { Write-Host ("     - " + (Get-MBLocalized $t.name)) -ForegroundColor DarkGray }
    if ($preset -eq 'aggressive') {
        Write-Host ''
        Write-Host '   WARNING: aggressive disables search indexer, SuperFetch, IPv6 etc.' -ForegroundColor Red
    }
    if (-not (Confirm-MB 'Apply preset?')) { return }
    [void](New-MBRestorePoint)
    foreach ($t in $tweaks) { Invoke-MBTweak -Tweak $t }
    Write-Host ''
    Write-Host ("   Applied {0} tweak(s)." -f $tweaks.Count) -ForegroundColor Green
    Invoke-MBRebootPrompt
    Pause-MB
}

# ------------------------------------------------------------------
# Debloat
# ------------------------------------------------------------------
function Invoke-MBDebloatMenu {
    $items = @($global:MB.Data.Debloat)
    Write-MBHeader ("Debloat - remove built-in apps ({0})" -f $items.Count)
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("   [{0,3}]  {1,-32}  ({2})" -f ($i + 1), (Get-MBLocalized $items[$i].name), $items[$i].appx)
    }
    $sel = Read-MBChoice 'Pick apps to remove (empty = back)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $items.Count
    if ($idx.Count -eq 0) { return }
    if (-not (Confirm-MB ("Remove {0} app(s)?" -f $idx.Count))) { return }
    foreach ($i in $idx) {
        [void](Remove-MBAppx -Name $items[$i - 1].appx)
    }
    Write-Host ''
    Write-Host '   Done.' -ForegroundColor Green
    Invoke-MBRebootPrompt
    Pause-MB
}

# ------------------------------------------------------------------
# Services
# ------------------------------------------------------------------
function Invoke-MBServicesMenu {
    $items = @($global:MB.Data.Services)
    Write-MBHeader ("Services - apply hardening ({0})" -f $items.Count)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $s = $items[$i]
        Write-Host ("   [{0,3}]  {1,-30}  preset={2,-10}  -> {3}" -f ($i + 1), $s.name, $s.preset, $s.startup)
    }
    $sel = Read-MBChoice 'Pick services to configure (empty = back)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $items.Count
    if ($idx.Count -eq 0) { return }
    if (-not (Confirm-MB ("Configure {0} service(s)?" -f $idx.Count))) { return }
    foreach ($i in $idx) {
        $s = $items[$i - 1]
        Invoke-MBServiceAction -Action @{
            name    = $s.service
            startup = $s.startup
            stop    = $true
        }
    }
    Write-Host ''
    Write-Host '   Done.' -ForegroundColor Green
    Invoke-MBRebootPrompt
    Pause-MB
}

# ------------------------------------------------------------------
# Install software via winget
# ------------------------------------------------------------------
function Invoke-MBInstallMenu {
    $items = @($global:MB.Data.Apps)
    Write-MBHeader ("Install software via winget ({0})" -f $items.Count)
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("   [{0,3}]  {1,-32}  ({2})" -f ($i + 1), $items[$i].name, $items[$i].id)
    }
    $sel = Read-MBChoice 'Pick apps to install (empty = back)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $items.Count
    if ($idx.Count -eq 0) { return }
    if (-not (Confirm-MB ("Install {0} package(s)?" -f $idx.Count))) { return }
    $ok = 0
    foreach ($i in $idx) { if (Install-MBPackage -Id $items[$i - 1].id) { $ok++ } }
    Write-Host ''
    Write-Host ("   Installed {0}/{1}." -f $ok, $idx.Count) -ForegroundColor Green
    Pause-MB
}

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
function Invoke-MBCleanupMenu {
    $targets = @(Get-MBCleanupTargets)
    Write-MBHeader 'Cleanup - junk and caches'
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $name = Get-MBLocalized ([pscustomobject]$targets[$i].Name)
        Write-Host ("   [{0,3}]  {1}" -f ($i + 1), $name)
    }
    $sel = Read-MBChoice 'Pick targets (default = all)'
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = 'all' }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $targets.Count
    if ($idx.Count -eq 0) { return }
    if (-not (Confirm-MB ("Clean {0} target(s)?" -f $idx.Count))) { return }
    $total = 0
    foreach ($i in $idx) { $total += (Invoke-MBCleanupTarget -Target $targets[$i - 1]) }
    Write-Host ''
    Write-Host ("   Freed approximately {0:N1} MB." -f ($total / 1MB)) -ForegroundColor Green
    Pause-MB
}

# ------------------------------------------------------------------
# Restore (undo)
# ------------------------------------------------------------------
function Invoke-MBRestoreMenu {
    $items = @(Read-MBApplied)
    Write-MBHeader ("Restore - undo applied tweaks ({0})" -f $items.Count)
    if ($items.Count -eq 0) {
        Write-Host '   No applied tweaks yet.' -ForegroundColor DarkGray
        Pause-MB; return
    }
    for ($i = 0; $i -lt $items.Count; $i++) {
        $e = $items[$i]
        Write-Host ("   [{0,3}]  {1}  {2,-12}  {3}" -f ($i + 1), $e.appliedAt, $e.category, $e.id)
    }
    Write-Host ''
    Write-Host '   Type numbers to undo, or "all" to roll back everything.'
    $sel = Read-MBChoice 'Pick (empty = back)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return }
    $idx = ConvertFrom-MBIndexInput -Selection $sel -Max $items.Count
    if ($idx.Count -eq 0) { return }
    if (-not (Confirm-MB ("Undo {0} tweak(s)?" -f $idx.Count))) { return }
    # Undo in reverse order (newest first).
    $sorted = $idx | Sort-Object -Descending
    foreach ($i in $sorted) { Undo-MBTweak -Id $items[$i - 1].id }
    Write-Host ''
    Write-Host '   Done.' -ForegroundColor Green
    Invoke-MBRebootPrompt
    Pause-MB
}

# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------
function Start-MBApp {
    Initialize-MBData
    while ($true) {
        Show-MBMainMenu
        $c = (Read-MBChoice 'Choice').Trim().ToUpper()
        switch ($c) {
            '1' { Invoke-MBPresetMenu }
            '2' { Invoke-MBCategoryMenu -Category 'Privacy' }
            '3' { Invoke-MBCategoryMenu -Category 'Performance' }
            '4' { Invoke-MBCategoryMenu -Category 'Gaming' }
            '5' { Invoke-MBCategoryMenu -Category 'Network' }
            '6' { Invoke-MBCategoryMenu -Category 'UI' }
            '7' { Invoke-MBDebloatMenu }
            '8' { Invoke-MBServicesMenu }
            '9' { Invoke-MBInstallMenu }
            'C' { Invoke-MBCleanupMenu }
            'R' { Invoke-MBRestoreMenu }
            'P' {
                $ok = New-MBRestorePoint -Force
                Write-Host ''
                if ($ok) { Write-Host '   Restore point created.' -ForegroundColor Green }
                else     { Write-Host '   Failed. Check System Protection settings.' -ForegroundColor Red }
                Pause-MB
            }
            'L' {
                Write-Host ''
                Write-Host ('   Log file : ' + $global:MB.LogFile)
                Write-Host ('   Backups  : ' + $global:MB.BackupDir)
                Write-Host ('   Applied  : ' + $global:MB.AppliedFile)
                Pause-MB
            }
            'Q' { Write-MBLog 'User exit'; return }
            ''  { }
            default {
                Write-Host '   Unknown choice.' -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds 600
            }
        }
    }
}
