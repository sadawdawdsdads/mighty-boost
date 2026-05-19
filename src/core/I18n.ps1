# I18n.ps1 - localization loader. Picks ru/en by Get-Culture, fallback to en.

$script:MBLocale = @{}
$script:MBDefault = @{}

function Initialize-MBI18n {
    param([string]$Culture = $global:MB.Culture)
    $script:MBDefault = Read-MBLocale -Code 'en'
    if ($Culture -eq 'ru') {
        $script:MBLocale = Read-MBLocale -Code 'ru'
    } else {
        $script:MBLocale = $script:MBDefault
    }
    $global:MB.Locale = $Culture
    Write-MBLog "Locale loaded: $($global:MB.Locale)" -Level DEBUG
}

function ConvertTo-MBHashtable {
    param($Object)
    if ($null -eq $Object) { return @{} }
    $hash = @{}
    foreach ($prop in $Object.PSObject.Properties) {
        $hash[$prop.Name] = $prop.Value
    }
    return $hash
}

function Read-MBLocale {
    param([string]$Code)
    $rel = "src/data/locales/$Code.json"
    try {
        $raw = Get-MBSource -RelativePath $rel
        $obj = $raw | ConvertFrom-Json
        return (ConvertTo-MBHashtable $obj)
    } catch {
        Write-MBLog "Failed to load locale $Code : $($_.Exception.Message)" -Level WARN
        return @{}
    }
}

function Get-T {
    param([Parameter(Mandatory)][string]$Key, [object[]]$Tokens)
    $val = $null
    if ($script:MBLocale.ContainsKey($Key)) { $val = $script:MBLocale[$Key] }
    elseif ($script:MBDefault.ContainsKey($Key)) { $val = $script:MBDefault[$Key] }
    else { $val = $Key }
    if ($Tokens) { return ($val -f $Tokens) }
    return $val
}

function Get-MBLocalized {
    # Returns localized name/description from JSON objects with { ru: ..., en: ... }
    param([Parameter(Mandatory)][object]$Field)
    if ($null -eq $Field) { return '' }
    if ($Field -is [string]) { return $Field }
    $lang = $global:MB.Locale
    if ($Field.PSObject.Properties.Name -contains $lang) { return $Field.$lang }
    if ($Field.PSObject.Properties.Name -contains 'en')  { return $Field.en }
    return ''
}

Initialize-MBI18n
