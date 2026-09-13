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

function ConvertFrom-LegacyCompanionApp($Legacy) {
    if ($null -eq $Legacy -or -not [bool]$Legacy.enabled -or [string]::IsNullOrWhiteSpace($Legacy.path)) { return @() }
    return @([pscustomobject]@{ id = ConvertTo-CompanionId $Legacy.name; name = $Legacy.name; path = $Legacy.path; arguments = [string]$Legacy.arguments })
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

# Deux listes companionApps décrivent la même chose si mêmes id, chemins et arguments dans le même ordre
function Test-LaunchCompanionAppsEqual([object[]]$Left, [object[]]$Right) {
    $left  = @($Left  | ForEach-Object { "$($_.id)|$($_.path)|$($_.arguments)" })
    $right = @($Right | ForEach-Object { "$($_.id)|$($_.path)|$($_.arguments)" })
    return (($left -join "`n") -eq ($right -join "`n"))
}
