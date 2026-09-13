<#
.SYNOPSIS
    Lecture/écriture de config.json et des catalogues JSON, partagées par le lanceur et les scripts d'installation.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\launch-config.lib.ps1')

    config.json :
        riotClientPath, productSettingsPath, companionApps = [ { id, name, path, arguments }, … ]

    Un config.json antérieur (bloc unique companionApp { enabled, name, path, arguments }) est migré à la lecture :
    l'entrée activée devient la seule ligne de companionApps, avec un id dérivé de son nom.
#>

function Read-JsonFile([string]$Path) {
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# ForEach-Object déplie le tableau que ConvertFrom-Json (PS 5.1) renvoie comme un seul objet
function Read-JsonCatalog([string]$Path) {
    return @(Read-JsonFile $Path | ForEach-Object { $_ })
}

function Write-JsonFile($Object, [string]$Path) {
    $json = $Object | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($Path, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

# "OP.GG" → "opgg", "Porofessor" → "porofessor" : mêmes identifiants que companion-apps.json
function ConvertTo-CompanionId([string]$Name) {
    return ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

# Nom de process déduit de l'exécutable (Blitz.exe → Blitz) pour une entrée qui n'en déclare pas
function Get-LaunchCompanionProcessNames($Entry) {
    $declared = @($Entry.processNames | Where-Object { $_ })
    if ($declared.Count -gt 0) { return $declared }
    if ([string]::IsNullOrWhiteSpace($Entry.path)) { return @() }
    return @([IO.Path]::GetFileNameWithoutExtension($Entry.path))
}

function ConvertFrom-LegacyCompanionApp($Legacy) {
    if ($null -eq $Legacy -or -not [bool]$Legacy.enabled -or [string]::IsNullOrWhiteSpace($Legacy.path)) { return @() }
    $entry = [pscustomobject]@{ id = ConvertTo-CompanionId $Legacy.name; name = $Legacy.name; path = $Legacy.path; arguments = [string]$Legacy.arguments; processNames = @() }
    $entry.processNames = Get-LaunchCompanionProcessNames $entry
    return @($entry)
}

# Liste companionApps, quel que soit le format du fichier ; l'appelant enveloppe dans @() (un tableau vide se déroule au return)
function Get-LaunchCompanionApps($Config) {
    if ($null -ne $Config.companionApps) { return @($Config.companionApps | ForEach-Object { $_ } | Where-Object { $_ }) }
    return ConvertFrom-LegacyCompanionApp $Config.companionApp
}

function Read-LaunchConfig([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Fichier de configuration introuvable : $Path" }
    $config = Read-JsonFile $Path
    [object[]]$companionApps = @(Get-LaunchCompanionApps $config)
    $config | Add-Member -NotePropertyName companionApps -NotePropertyValue $companionApps -Force
    if ($null -ne $config.PSObject.Properties['companionApp']) { $config.PSObject.Properties.Remove('companionApp') }
    return $config
}

function Write-LaunchConfig($Config, [string]$Path) {
    Write-JsonFile $Config $Path
}

function Find-LaunchCompanion($Config, [string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    return @($Config.companionApps) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

# BUSINESS_RULE : une seule appli compagnon active pendant la partie — process de toutes les applis
# de config.json sauf celle demandée (toutes, si aucune n'est demandée)
function Get-OtherCompanionProcessNames($Config, [string]$KeepId) {
    $others = @($Config.companionApps | Where-Object { $_.id -ne $KeepId })
    return @($others | ForEach-Object { Get-LaunchCompanionProcessNames $_ } | Select-Object -Unique)
}

function ConvertTo-LaunchCompanionKey($Entry) {
    return "$($Entry.id)|$($Entry.path)|$($Entry.arguments)|$((Get-LaunchCompanionProcessNames $Entry) -join ',')"
}

# Deux listes companionApps décrivent la même chose si mêmes id, chemins, arguments et process dans le même ordre
function Test-LaunchCompanionAppsEqual([object[]]$Left, [object[]]$Right) {
    $left  = @($Left  | ForEach-Object { ConvertTo-LaunchCompanionKey $_ })
    $right = @($Right | ForEach-Object { ConvertTo-LaunchCompanionKey $_ })
    return (($left -join "`n") -eq ($right -join "`n"))
}
