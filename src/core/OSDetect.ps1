# OSDetect.ps1 - Windows version, build, architecture detection.

function Get-MBOSInfo {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cur = Get-ItemProperty -Path $cv -ErrorAction SilentlyContinue
    $build = [int]($cur.CurrentBuildNumber)
    $ubr   = [int]($cur.UBR)
    $major = if ($build -ge 22000) { '11' } else { '10' }
    $os    = Get-CimInstance Win32_OperatingSystem
    $cs    = Get-CimInstance Win32_ComputerSystem
    [pscustomobject]@{
        Major          = $major                 # '10' / '11'
        Build          = $build
        UBR            = $ubr
        DisplayVersion = $cur.DisplayVersion    # 22H2, 23H2, 24H2...
        Edition        = $cur.EditionID
        ProductName    = $cur.ProductName
        Arch           = $env:PROCESSOR_ARCHITECTURE
        IsArm64        = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
        TotalRAMGb     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        FreeRAMGb      = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        LastBoot       = $os.LastBootUpTime
    }
}

function Test-MBOSCompatible {
    param([string[]]$Win)
    if (-not $Win -or $Win.Count -eq 0) { return $true }
    $os = Get-MBOSInfo
    return ($Win -contains $os.Major)
}

$global:MB.OS = Get-MBOSInfo
Write-MBLog ("Detected: Windows {0} build {1}.{2} ({3}) {4}" -f `
    $global:MB.OS.Major, $global:MB.OS.Build, $global:MB.OS.UBR, $global:MB.OS.DisplayVersion, $global:MB.OS.Arch) -Level INFO
