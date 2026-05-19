# Winget.ps1 - software installation via winget.

function Test-MBWinget {
    try {
        $null = & winget --version 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Install-MBWingetSelf {
    Write-MBLog "winget not found, attempting to install App Installer..." -Level WARN
    try {
        $url = 'https://aka.ms/getwinget'
        $tmp = Join-Path $env:TEMP 'AppInstaller.msixbundle'
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        Add-AppxPackage -Path $tmp -ErrorAction Stop
        Write-MBLog "App Installer installed" -Level ACTION
        return $true
    } catch {
        Write-MBLog "Failed to install winget: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Install-MBPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-MBWinget)) {
        if (-not (Install-MBWingetSelf)) { return $false }
    }
    Write-MBLog "winget install $Id ..." -Level ACTION
    $args = @('install','--exact','--id', $Id,
              '--accept-package-agreements','--accept-source-agreements',
              '--silent','--disable-interactivity')
    try {
        $p = Start-Process -FilePath 'winget' -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($p.ExitCode -eq 0) {
            Write-MBLog "winget OK: $Id" -Level ACTION
            return $true
        }
        Write-MBLog "winget $Id exited $($p.ExitCode)" -Level WARN
        return $false
    } catch {
        Write-MBLog "winget $Id failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}
