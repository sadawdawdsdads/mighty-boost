# App.ps1 - central orchestration: JSON loader, tweak engine, applied-log, UI bootstrap.

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Actions,
        [string]$TweakId = 'adhoc'
    )
    # 1) Backup all touched registry keys first.
    $regKeys = Get-MBRegistryKeysFromActions -Actions $Actions
    if ($regKeys.Count -gt 0) { [void](New-MBRegBackup -Keys $regKeys -TweakId $TweakId) }

    # 2) Execute every action.
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
    [CmdletBinding()]
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
    [CmdletBinding()]
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
# UI bootstrap
# ------------------------------------------------------------------
function Start-MBApp {
    Initialize-MBData

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    $xaml = Get-MBSource -RelativePath 'src/ui/MainWindow.xaml'
    $xaml = $xaml -replace 'x:Class="[^"]+"\s*', ''
    [xml]$xml = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $xml
    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-MBLog "XAML load failed: $($_.Exception.Message)" -Level ERROR
        throw
    }

    # Cache named elements.
    $named = @{}
    $xml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
        $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($n) { $named[$n] = $window.FindName($n) }
    }
    $global:MB.UI = $named
    $global:MB.Window = $window

    Invoke-MBUIBindings
    [void]$window.ShowDialog()
}

# ------------------------------------------------------------------
# UI bindings - populate lists, wire up events
# ------------------------------------------------------------------
function Invoke-MBUIBindings {
    $ui = $global:MB.UI

    # ----- Home tab -----
    if ($ui.HomeStatusText) {
        $os = $global:MB.OS
        $ui.HomeStatusText.Text = (
            "Windows {0}  {1}  (build {2}.{3})`r`n" +
            "{4}   |   {5} GB RAM   |   User: {6}`r`n" +
            "MightyBoost v{7}   |   Locale: {8}"
        ) -f $os.Major, $os.DisplayVersion, $os.Build, $os.UBR, `
             $os.Arch, $os.TotalRAMGb, $os.UserName, $global:MB.Version, $global:MB.Locale
    }
    if ($ui.BtnRestorePoint) {
        $ui.BtnRestorePoint.Add_Click({
            $ok = New-MBRestorePoint -Force
            [System.Windows.MessageBox]::Show(
                $(if ($ok) { 'Точка восстановления создана / Restore point created.' }
                  else     { 'Не удалось создать. Проверь System Protection.' }),
                'MightyBoost') | Out-Null
        })
    }

    # ----- Tweaks tabs (Privacy/Performance/Gaming/Network/UI) -----
    foreach ($cat in 'Privacy','Performance','Gaming','Network','UI') {
        $panelName = "Panel$cat"
        $panel = $ui[$panelName]
        if (-not $panel) { continue }
        $panel.Children.Clear()
        $items = $global:MB.Data.Tweaks | Where-Object { $_.category -eq $cat }
        foreach ($t in $items) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Margin  = '0,4,0,4'
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Content = Get-MBLocalized $t.name
            $cb.ToolTip = Get-MBLocalized $t.description
            $cb.Tag     = $t.id
            [void]$panel.Children.Add($cb)
        }
    }

    # ----- Debloat tab -----
    if ($ui.PanelDebloat) {
        $ui.PanelDebloat.Children.Clear()
        foreach ($d in $global:MB.Data.Debloat) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Margin     = '0,4,0,4'
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Content    = Get-MBLocalized $d.name
            $cb.ToolTip    = $d.appx
            $cb.Tag        = $d.id
            [void]$ui.PanelDebloat.Children.Add($cb)
        }
    }

    # ----- Services tab -----
    if ($ui.PanelServices) {
        $ui.PanelServices.Children.Clear()
        foreach ($s in $global:MB.Data.Services) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Margin     = '0,4,0,4'
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Content    = "$($s.name)  [$($s.preset)]"
            $cb.ToolTip    = Get-MBLocalized $s.description
            $cb.Tag        = $s.id
            [void]$ui.PanelServices.Children.Add($cb)
        }
    }

    # ----- Install (winget) tab -----
    if ($ui.PanelInstall) {
        $ui.PanelInstall.Children.Clear()
        foreach ($a in $global:MB.Data.Apps) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Margin     = '0,4,0,4'
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Content    = "$($a.name)   ($($a.id))"
            $cb.ToolTip    = $a.description
            $cb.Tag        = $a.id
            [void]$ui.PanelInstall.Children.Add($cb)
        }
    }

    # ----- Cleanup tab -----
    if ($ui.PanelCleanup) {
        $ui.PanelCleanup.Children.Clear()
        foreach ($t in (Get-MBCleanupTargets)) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Margin     = '0,4,0,4'
            $cb.IsChecked  = $true
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.Content    = (Get-MBLocalized ([pscustomobject]$t.Name))
            $cb.Tag        = $t.Id
            [void]$ui.PanelCleanup.Children.Add($cb)
        }
    }

    # ----- Buttons -----
    if ($ui.BtnApplyTweaks) {
        $ui.BtnApplyTweaks.Add_Click({ Invoke-MBApplySelectedTweaks })
    }
    if ($ui.BtnApplyDebloat) {
        $ui.BtnApplyDebloat.Add_Click({ Invoke-MBApplySelectedDebloat })
    }
    if ($ui.BtnApplyServices) {
        $ui.BtnApplyServices.Add_Click({ Invoke-MBApplySelectedServices })
    }
    if ($ui.BtnInstallApps) {
        $ui.BtnInstallApps.Add_Click({ Invoke-MBInstallSelectedApps })
    }
    if ($ui.BtnRunCleanup) {
        $ui.BtnRunCleanup.Add_Click({ Invoke-MBRunCleanup })
    }
    if ($ui.BtnApplyPresetSafe) {
        $ui.BtnApplyPresetSafe.Add_Click({ Invoke-MBApplyPreset 'safe' })
    }
    if ($ui.BtnApplyPresetBalanced) {
        $ui.BtnApplyPresetBalanced.Add_Click({ Invoke-MBApplyPreset 'balanced' })
    }
    if ($ui.BtnApplyPresetAggressive) {
        $ui.BtnApplyPresetAggressive.Add_Click({
            $r = [System.Windows.MessageBox]::Show(
                'Aggressive preset disables many features. Are you sure?',
                'MightyBoost', 'YesNo', 'Warning')
            if ($r -eq 'Yes') { Invoke-MBApplyPreset 'aggressive' }
        })
    }
    if ($ui.BtnRefreshUndo) {
        $ui.BtnRefreshUndo.Add_Click({ Update-MBUndoList })
    }
    if ($ui.BtnUndoSelected) {
        $ui.BtnUndoSelected.Add_Click({ Invoke-MBUndoSelected })
    }
    Update-MBUndoList
}

# ------------------------------------------------------------------
# UI handlers
# ------------------------------------------------------------------
function Get-MBCheckedFromPanel {
    param($Panel)
    if (-not $Panel) { return @() }
    $list = @()
    foreach ($child in $Panel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
            $list += [string]$child.Tag
        }
    }
    return $list
}

function Invoke-MBApplySelectedTweaks {
    $ids = @()
    foreach ($cat in 'Privacy','Performance','Gaming','Network','UI') {
        $ids += Get-MBCheckedFromPanel $global:MB.UI["Panel$cat"]
    }
    if ($ids.Count -eq 0) { return }
    [void](New-MBRestorePoint)
    foreach ($id in $ids) {
        $t = $global:MB.Data.Tweaks | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($t) { Invoke-MBTweak -Tweak $t }
    }
    [System.Windows.MessageBox]::Show("Applied $($ids.Count) tweaks.", 'MightyBoost') | Out-Null
    Update-MBUndoList
}

function Invoke-MBApplySelectedDebloat {
    $ids = Get-MBCheckedFromPanel $global:MB.UI.PanelDebloat
    if ($ids.Count -eq 0) { return }
    foreach ($id in $ids) {
        $d = $global:MB.Data.Debloat | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($d) { [void](Remove-MBAppx -Name $d.appx) }
    }
    [System.Windows.MessageBox]::Show("Debloated $($ids.Count) apps.", 'MightyBoost') | Out-Null
}

function Invoke-MBApplySelectedServices {
    $ids = Get-MBCheckedFromPanel $global:MB.UI.PanelServices
    if ($ids.Count -eq 0) { return }
    foreach ($id in $ids) {
        $s = $global:MB.Data.Services | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($s) {
            Invoke-MBServiceAction -Action @{
                name    = $s.service
                startup = $s.startup
                stop    = $true
            }
        }
    }
    [System.Windows.MessageBox]::Show("Configured $($ids.Count) services.", 'MightyBoost') | Out-Null
}

function Invoke-MBInstallSelectedApps {
    $ids = Get-MBCheckedFromPanel $global:MB.UI.PanelInstall
    if ($ids.Count -eq 0) { return }
    $okCount = 0
    foreach ($id in $ids) { if (Install-MBPackage -Id $id) { $okCount++ } }
    [System.Windows.MessageBox]::Show("Installed $okCount of $($ids.Count) packages.", 'MightyBoost') | Out-Null
}

function Invoke-MBRunCleanup {
    $ids = Get-MBCheckedFromPanel $global:MB.UI.PanelCleanup
    if ($ids.Count -eq 0) { return }
    $totalBytes = 0
    foreach ($id in $ids) {
        $t = (Get-MBCleanupTargets) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($t) { $totalBytes += (Invoke-MBCleanupTarget -Target $t) }
    }
    [System.Windows.MessageBox]::Show(("Freed approximately {0:N1} MB." -f ($totalBytes/1MB)), 'MightyBoost') | Out-Null
}

function Invoke-MBApplyPreset {
    param([string]$Preset)
    [void](New-MBRestorePoint)
    $tweaks = $global:MB.Data.Tweaks | Where-Object { $_.presets -contains $Preset }
    foreach ($t in $tweaks) { Invoke-MBTweak -Tweak $t }
    [System.Windows.MessageBox]::Show("Applied preset '$Preset' - $($tweaks.Count) tweaks.", 'MightyBoost') | Out-Null
    Update-MBUndoList
}

function Update-MBUndoList {
    $lb = $global:MB.UI.UndoList
    if (-not $lb) { return }
    $lb.Items.Clear()
    foreach ($e in @(Read-MBApplied)) {
        [void]$lb.Items.Add("$($e.appliedAt) | $($e.category) | $($e.id)")
    }
}

function Invoke-MBUndoSelected {
    $lb = $global:MB.UI.UndoList
    if (-not $lb -or -not $lb.SelectedItem) { return }
    $line = [string]$lb.SelectedItem
    $id   = ($line -split '\|')[-1].Trim()
    Undo-MBTweak -Id $id
    Update-MBUndoList
}
