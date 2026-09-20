<#
.SYNOPSIS
    Lecture/écriture de config.json et des catalogues JSON, partagées par le lanceur et les scripts d'installation.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\launch-config.lib.ps1')

    config.json :
        riotClientPath, productSettingsPath (détectés, corrigeables dans setup.bat),
        companionApps = [ { id, name, path, arguments }, … ],
        iconSet = nom du jeu d'icônes choisi dans setup.bat (dossier de app\ico ; absent → jeu par défaut),
        useLocalApi = chemin de lancement choisi dans setup.bat (absent → vrai : API locale du Riot Client)

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

# Nom du jeu d'icônes retenu ('' si jamais choisi)
# Chemin de lancement voulu par l'utilisateur (case de setup.bat) : vrai = API locale du Riot Client d'abord,
# faux = démarrage manuel directement. Absent d'un config.json antérieur → vrai, le comportement par défaut.
function Get-LaunchUseLocalApi($Config) {
    if ($null -ne $Config.useLocalApi) { return [bool]$Config.useLocalApi }
    return $true
}

function Set-LaunchUseLocalApi($Config, [bool]$UseLocalApi) {
    $Config | Add-Member -NotePropertyName useLocalApi -NotePropertyValue $UseLocalApi -Force
}

# N'écrit config.json que si le choix a changé ; rend vrai dans ce cas
function Save-LaunchUseLocalApi($Config, [string]$ConfigPath, [bool]$UseLocalApi) {
    if ((Get-LaunchUseLocalApi $Config) -eq $UseLocalApi) { return $false }
    Set-LaunchUseLocalApi $Config $UseLocalApi
    Write-LaunchConfig $Config $ConfigPath
    return $true
}

# Chemins Riot tels qu'ils seront lus par le lanceur : un chemin collé depuis l'Explorateur (« Copier en tant
# que chemin d'accès ») arrive entre guillemets, un chemin saisi peut traîner des espaces — ni l'un ni l'autre
# ne désigne un fichier
function ConvertTo-LaunchPathValue([string]$Path) {
    if ($null -eq $Path) { return '' }
    return $Path.Trim().Trim('"').Trim()
}

function Get-LaunchRiotPaths($Config) {
    return @{
        RiotClientPath      = [string]$Config.riotClientPath
        ProductSettingsPath = [string]$Config.productSettingsPath
    }
}

# $Paths : @{ RiotClientPath ; ProductSettingsPath } — mêmes clés que Get-LaunchRiotPaths
function Set-LaunchRiotPaths($Config, [hashtable]$Paths) {
    $Config | Add-Member -NotePropertyName riotClientPath      -NotePropertyValue (ConvertTo-LaunchPathValue $Paths.RiotClientPath) -Force
    $Config | Add-Member -NotePropertyName productSettingsPath -NotePropertyValue (ConvertTo-LaunchPathValue $Paths.ProductSettingsPath) -Force
}

function Test-LaunchRiotPathsEqual([hashtable]$Left, [hashtable]$Right) {
    return ((ConvertTo-LaunchPathValue $Left.RiotClientPath) -eq (ConvertTo-LaunchPathValue $Right.RiotClientPath) -and
            (ConvertTo-LaunchPathValue $Left.ProductSettingsPath) -eq (ConvertTo-LaunchPathValue $Right.ProductSettingsPath))
}

# N'écrit config.json que si un chemin a changé ; rend vrai dans ce cas
function Save-LaunchRiotPaths($Config, [string]$ConfigPath, [hashtable]$Paths) {
    if (Test-LaunchRiotPathsEqual (Get-LaunchRiotPaths $Config) $Paths) { return $false }
    Set-LaunchRiotPaths $Config $Paths
    Write-LaunchConfig $Config $ConfigPath
    return $true
}

function Get-LaunchIconSetName($Config) {
    if ($null -ne $Config.iconSet) { return [string]$Config.iconSet }
    return ''
}

function Set-LaunchIconSetName($Config, [string]$Name) {
    $Config | Add-Member -NotePropertyName iconSet -NotePropertyValue $Name -Force
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
