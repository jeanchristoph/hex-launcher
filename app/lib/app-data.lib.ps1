<#
.SYNOPSIS
    Dossier des données de hex-launcher : tout ce que l'outil écrit à l'usage, hors du dossier du code.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\app-data.lib.ps1')

    Version installée (et dépôt de développement) : %LOCALAPPDATA%\hex-launcher\
    Version portable, reconnue au marqueur app\portable.json posé par make-release : data\, à côté de setup.bat,
    pour que tout voyage avec le dossier.

    Contenu : config.json, launch.log, icons\<jeu>\companion\ (icônes composées sur ce poste), update-state.json.
    Le cache et l'état du texte forcé restent dans %LOCALAPPDATA%\hex-launcher\ même en portable : ils décrivent les
    fichiers du jeu installé sur CE poste, pas l'outil.

    INVARIANT : le dossier du code (app\) n'est jamais écrit à l'usage — seul l'installeur ou la mise à jour y écrit.
    Une version antérieure y laissait config.json et launch.log : ils sont repris au premier lancement.
#>

$AppDataFolderName      = 'hex-launcher'
$PortableMarkerFileName = 'portable.json'
$PortableDataFolderName = 'data'
$LegacyAppDataFiles     = @('config.json', 'launch.log')

function Test-PortableInstall([string]$AppRoot) {
    return Test-Path -LiteralPath (Join-Path $AppRoot $PortableMarkerFileName)
}

# Désinstalleur qu'Inno Setup dépose à la racine d'une copie installée
$InstalledUninstallerFileName = 'unins000.exe'

# Nature de la copie : 'portable' (marqueur du zip), 'installed' (posée par l'installeur), 'source' (dépôt de
# développement, zip d'avant la 0.4.0) — une copie source ne sait pas se mettre à jour d'elle-même
function Get-DistributionKind([string]$AppRoot) {
    if (Test-PortableInstall $AppRoot) { return 'portable' }
    if (Test-Path -LiteralPath (Join-Path (Split-Path $AppRoot -Parent) $InstalledUninstallerFileName)) { return 'installed' }
    return 'source'
}

# Version de cette copie, lue dans app\version.txt ; '' si le fichier manque ou est illisible (rien à afficher)
function Get-InstalledVersion([string]$AppRoot) {
    try { return (Get-Content -LiteralPath (Join-Path $AppRoot 'version.txt') -Raw -ErrorAction Stop).Trim() }
    catch { return '' }
}

function Get-AppDataFolder([string]$AppRoot) {
    if (Test-PortableInstall $AppRoot) { return Join-Path (Split-Path $AppRoot -Parent) $PortableDataFolderName }
    return Join-Path $env:LOCALAPPDATA $AppDataFolderName
}

function Get-AppDataFilePath([string]$AppRoot, [string]$FileName) {
    return Join-Path (Get-AppDataFolder $AppRoot) $FileName
}

# Icônes drapeau + pastille composées sur ce poste pour un jeu d'icônes
function Get-CompanionIconFolder([string]$AppRoot, [string]$IconSetName) {
    return [IO.Path]::Combine((Get-AppDataFolder $AppRoot), 'icons', $IconSetName, 'companion')
}

# Crée le dossier des données et y reprend les fichiers d'une version antérieure ; rend le dossier
function Initialize-AppDataFolder([string]$AppRoot) {
    $folder = Get-AppDataFolder $AppRoot
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($name in $LegacyAppDataFiles) {
        Move-LegacyAppDataFile (Join-Path $AppRoot $name) (Join-Path $folder $name) | Out-Null
    }
    return $folder
}

# Jamais d'écrasement : une donnée déjà présente dans le dossier des données fait foi. Dossier du code en lecture
# seule → copie ; échec de la copie → avertissement, l'outil repart d'une détection neuve. Rend vrai si repris.
function Move-LegacyAppDataFile([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    if (Test-Path -LiteralPath $Destination) { return $false }
    try {
        Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
        return $true
    } catch {
        return Copy-LegacyAppDataFile $Source $Destination
    }
}

function Copy-LegacyAppDataFile([string]$Source, [string]$Destination) {
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Reprise impossible de $Source ($($_.Exception.Message))"
        return $false
    }
}
