<#
.SYNOPSIS
    Jeux d'icônes : chaque sous-dossier de ico\ qui contient hex-launcher.ico est un jeu, nommé par son dossier.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\icon-set.lib.ps1')

    Aucun manifeste : déposer un dossier ico\<nom>\ avec hex-launcher.ico (et les hex-launcher-xx.ico) suffit
    pour qu'il soit proposé dans setup.bat. Le jeu par défaut est ico\flat ; s'il manque, le premier dossier
    par ordre alphabétique. Un jeu = @{ Name; Path }.

    Option par jeu, fichier badge-style.json dans son dossier, pour les pastilles compagnon :
        { "nightVeil": true, "reducedPalette": false }
    nightVeil → voile bleu nuit des drapeaux ; reducedPalette → couleurs ramenées à la palette réduite des drapeaux
    (avant le voile). Fichier ou clé absents → couleurs brutes du catalogue.
#>

$DefaultIconSetName    = 'flat'
$IconSetBaseIcon       = 'hex-launcher.ico'
$IconSetBadgeStyleFile = 'badge-style.json'

# Jeux présents sous la racine, triés par nom ; l'appelant enveloppe dans @()
function Get-IconSets([string]$IcoRoot) {
    if (-not (Test-Path $IcoRoot)) { return @() }
    return @(Get-ChildItem -Path $IcoRoot -Directory | Sort-Object Name |
        Where-Object { Test-Path (Join-Path $_.FullName $IconSetBaseIcon) } |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

function Find-IconSet([object[]]$Sets, [string]$Name) {
    return @($Sets | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
}

# Jeu par défaut : ico\flat, sinon le premier ; $null sans aucun jeu
function Get-DefaultIconSet([object[]]$Sets) {
    $preferred = Find-IconSet $Sets $DefaultIconSetName
    if ($preferred) { return $preferred }
    return @($Sets) | Select-Object -First 1
}

# Jeu demandé, sinon le jeu par défaut avec avertissement (un nom inconnu ne bloque jamais l'installation)
function Resolve-IconSet([string]$IcoRoot, [string]$Name) {
    $sets = @(Get-IconSets $IcoRoot)
    if ($Name) {
        $wanted = Find-IconSet $sets $Name
        if ($wanted) { return $wanted }
        Write-Warning "Jeu d'icônes introuvable : $Name — repli sur le jeu par défaut"
    }
    return Get-DefaultIconSet $sets
}

function Get-IconSetFilePath($Set, [string]$FileName) {
    return Join-Path $Set.Path $FileName
}

# Style des pastilles du jeu : @{ NightVeil; ReducedPalette } ; fichier absent → brut ; illisible → brut avec avertissement
function Get-IconSetBadgeStyle($Set) {
    $style = @{ NightVeil = $false; ReducedPalette = $false }
    if (-not $Set) { return $style }
    $path = Get-IconSetFilePath $Set $IconSetBadgeStyleFile
    if (-not (Test-Path $path)) { return $style }
    try {
        $json = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $style.NightVeil      = [bool]$json.nightVeil
        $style.ReducedPalette = [bool]$json.reducedPalette
    } catch {
        Write-Warning "$IconSetBadgeStyleFile illisible dans le jeu $($Set.Name) ($($_.Exception.Message)) — pastilles aux couleurs brutes"
    }
    return $style
}

# Le jeu donné, ou à défaut le jeu par défaut « attendu » (dossier ico\flat, même absent) : jamais $null
function Get-IconSetFolderOrDefault($Set, [string]$IcoRoot) {
    if ($Set) { return $Set }
    return @{ Name = $DefaultIconSetName; Path = (Join-Path $IcoRoot $DefaultIconSetName) }
}
