# AppxDebloat.ps1 - Appx (UWP) and provisioned-package management.

function Get-MBAppxList {
    $installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Select-Object Name, PackageFullName, Publisher
    return $installed
}

function Remove-MBAppx {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $removed = 0
    # Remove for all users.
    try {
        $pkgs = Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-MBLog "appx removed: $($p.PackageFullName)" -Level ACTION
                $removed++
            } catch {
                Write-MBLog "appx remove failed $($p.PackageFullName): $($_.Exception.Message)" -Level WARN
            }
        }
    } catch {
        Write-MBLog "Get-AppxPackage failed for $Name : $($_.Exception.Message)" -Level WARN
    }
    # Remove provisioned (so new users don't get it back).
    try {
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $Name }
        foreach ($pp in $prov) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Write-MBLog "appx provisioned removed: $($pp.PackageName)" -Level ACTION
                $removed++
            } catch {
                Write-MBLog "appx provisioned remove failed $($pp.PackageName): $($_.Exception.Message)" -Level WARN
            }
        }
    } catch {}
    return $removed
}

function Invoke-MBAppxAction {
    param([Parameter(Mandatory)][hashtable]$Action)
    if ($Action.remove) { [void](Remove-MBAppx -Name $Action.remove) }
}
