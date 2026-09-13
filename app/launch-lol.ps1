<#
.SYNOPSIS
    Lance League of Legends dans la langue demandée, avec un splash animé.

.DESCRIPTION
    1. Ferme le Riot Client / client LoL s'ils tournent (sinon ils réécrivent le yaml à leur fermeture)
    2. Réécrit settings.locale dans league_of_legends.live.product_settings.yaml
    3. Lance le Riot Client
    4. Ferme les autres applications compagnon de config.json (une seule active pendant la partie, sinon les
       overlays entrent en conflit), puis lance celle demandée par -Companion (Porofessor, Blitz…) si elle
       figure dans la liste companionApps

    Les chemins machine (Riot, yaml, applications compagnon) sont lus dans config.json, à côté de ce script.
    Voir README.md pour l'adapter à un autre poste.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP -Companion blitz
#>
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z]{2}_[A-Z]{2}$')]
    [string]$Locale,

    # Identifiant de l'appli compagnon à lancer après le jeu (companionApps de config.json). Absent → aucune.
    [string]$Companion,

    # Par défaut : config.json à côté de ce script
    [string]$ConfigPath,

    # Ignore le chemin du yaml de config.json (utilisé pour tester sur une copie)
    [string]$YamlPath,

    # Ne ferme aucun process et ne lance rien : sert à tester le splash et la réécriture du yaml
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'lib\splash.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\launch-config.lib.ps1')

$RiotProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient', 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices')

# ---------------------------------------------------------------- Config

# Libellé affiché dans le splash, depuis locales.json ; repli sur le code si absent
function Get-LocaleLabel([string]$Code, [string]$CatalogPath) {
    if (-not (Test-Path $CatalogPath)) { return $Code }
    $entry = Read-JsonCatalog $CatalogPath | Where-Object { $_.code -eq $Code }
    if ($entry) { return $entry.label }
    return $Code
}

# ---------------------------------------------------------------- Étapes

function Stop-RiotProcesses {
    $running = Get-Process -Name $RiotProcessNames -ErrorAction SilentlyContinue
    if (-not $running) { return }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-WithAnimation -Seconds 2
}

# Ne touche qu'à settings.locale — default_locale (repli géré par Riot) reste intact
function Set-LeagueLocale([string]$Path, [string]$Value) {
    $content = Get-Content -Path $Path -Raw
    $quote   = [char]34
    $updated = $content -replace '(?m)^(\s+locale:\s*).*$', ('${1}' + $quote + $Value + $quote)
    [System.IO.File]::WriteAllText($Path, $updated)
}

function Start-LeagueClient([string]$Path, [string]$Value) {
    Start-Process -FilePath $Path -ArgumentList "--launch-product=league_of_legends --launch-patchline=live --locale=$Value"
}

# Une seule appli compagnon active : celle du raccourci (laissée en place si elle tourne déjà), les autres sont fermées
function Stop-OtherCompanionApps($Config, [string]$KeepId) {
    $names = @(Get-OtherCompanionProcessNames $Config $KeepId)
    if ($names.Count -eq 0) { return }
    Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-CompanionApp($App) {
    if (-not (Test-Path $App.path)) { return $false }
    if ([string]::IsNullOrWhiteSpace($App.arguments)) {
        Start-Process -FilePath $App.path
    } else {
        Start-Process -FilePath $App.path -ArgumentList $App.arguments
    }
    return $true
}

# ---------------------------------------------------------------- Main

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
$config = Read-LaunchConfig $ConfigPath
if (-not $YamlPath) { $YamlPath = $config.productSettingsPath }

$splash = New-SplashWindow -Subtitle (Get-LocaleLabel $Locale (Join-Path $PSScriptRoot 'locales.json'))

try {
    Update-SplashStatus $splash 'Fermeture du client Riot…'
    if (-not $DryRun) { Stop-RiotProcesses } else { Wait-WithAnimation 1 }

    Update-SplashStatus $splash "Application de la langue $Locale…"
    Set-LeagueLocale -Path $YamlPath -Value $Locale
    Wait-WithAnimation 0.5

    Update-SplashStatus $splash 'Lancement de League of Legends…'
    if (-not $DryRun) { Start-LeagueClient -Path $config.riotClientPath -Value $Locale }
    Wait-WithAnimation 0.5

    $companionApp = Find-LaunchCompanion $config $Companion
    Update-SplashStatus $splash 'Fermeture des autres applis compagnon…'
    if (-not $DryRun) { Stop-OtherCompanionApps $config $Companion }
    Wait-WithAnimation 0.5

    if ($companionApp) {
        Update-SplashStatus $splash "Lancement de $($companionApp.name)…"
        $started = if ($DryRun) { Test-Path $companionApp.path } else { Start-CompanionApp $companionApp }
        if (-not $started) { Update-SplashStatus $splash "$($companionApp.name) introuvable — ignoré (vérifier config.json)" }
        Wait-WithAnimation 1.5
    } elseif ($Companion) {
        Update-SplashStatus $splash "Appli compagnon « $Companion » absente de config.json — ignorée (relancer install.bat)"
        Wait-WithAnimation 1.5
    } else {
        Wait-WithAnimation 1
    }
}
finally {
    Close-SplashWindow $splash
}
