<#
.SYNOPSIS
    Lance League of Legends dans la langue demandée, avec un splash animé.

.DESCRIPTION
    1. Ferme le Riot Client / client LoL s'ils tournent (sinon ils réécrivent le yaml à leur fermeture)
    2. Réécrit settings.locale dans league_of_legends.live.product_settings.yaml
    3. Lance le Riot Client, puis l'application compagnon (Porofessor, Blitz…) si activée dans config.json

    Les chemins machine (Riot, yaml, application compagnon) sont lus dans config.json, à côté de ce script.
    Voir README.md pour l'adapter à un autre poste.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP
#>
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z]{2}_[A-Z]{2}$')]
    [string]$Locale,

    # Par défaut : config.json à côté de ce script
    [string]$ConfigPath,

    # Ignore le chemin du yaml de config.json (utilisé pour tester sur une copie)
    [string]$YamlPath,

    # Ne ferme aucun process et ne lance rien : sert à tester le splash et la réécriture du yaml
    [switch]$DryRun
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$RiotProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient', 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices')

# ---------------------------------------------------------------- Config

function Read-LaunchConfig([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Fichier de configuration introuvable : $Path" }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Libellé affiché dans le splash, depuis locales.json ; repli sur le code si absent
function Get-LocaleLabel([string]$Code, [string]$CatalogPath) {
    if (-not (Test-Path $CatalogPath)) { return $Code }
    # ForEach-Object déplie le tableau que ConvertFrom-Json (PS 5.1) renvoie comme un seul objet
    $entry = Get-Content -Path $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.code -eq $Code }
    if ($entry) { return $entry.label }
    return $Code
}

function Test-CompanionAppEnabled($Config) {
    $app = $Config.companionApp
    return ($null -ne $app) -and [bool]$app.enabled -and -not [string]::IsNullOrWhiteSpace($app.path)
}

# ---------------------------------------------------------------- Splash

function New-SplashWindow([string]$LocaleLabel) {
    $gold = [System.Drawing.ColorTranslator]::FromHtml('#C8AA6E')
    $grey = [System.Drawing.ColorTranslator]::FromHtml('#A09B8C')

    $form                 = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition   = 'CenterScreen'
    $form.Size            = New-Object System.Drawing.Size(420, 170)
    $form.BackColor       = [System.Drawing.ColorTranslator]::FromHtml('#0A0E14')
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false

    $title           = New-Object System.Windows.Forms.Label
    $title.Text      = 'LEAGUE OF LEGENDS'
    $title.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $gold
    $title.AutoSize  = $false
    $title.TextAlign = 'MiddleCenter'
    $title.Dock      = 'Top'
    $title.Height    = 60

    $subtitle           = New-Object System.Windows.Forms.Label
    $subtitle.Text      = $LocaleLabel
    $subtitle.Font      = New-Object System.Drawing.Font('Segoe UI', 12)
    $subtitle.ForeColor = [System.Drawing.Color]::White
    $subtitle.AutoSize  = $false
    $subtitle.TextAlign = 'MiddleCenter'
    $subtitle.Dock      = 'Top'
    $subtitle.Height    = 30

    $progress                       = New-Object System.Windows.Forms.ProgressBar
    $progress.Style                 = 'Marquee'
    $progress.MarqueeAnimationSpeed = 25
    $progress.Dock                  = 'Top'
    $progress.Height                = 6

    $status           = New-Object System.Windows.Forms.Label
    $status.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
    $status.ForeColor = $grey
    $status.AutoSize  = $false
    $status.TextAlign = 'MiddleCenter'
    $status.Dock      = 'Fill'

    # Dock 'Top' empile dans l'ordre inverse d'ajout : on ajoute donc de bas en haut
    $form.Controls.AddRange(@($status, $progress, $subtitle, $title))
    $form.Tag = $status
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    return $form
}

function Update-SplashStatus([System.Windows.Forms.Form]$Splash, [string]$Text) {
    $Splash.Tag.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

# Un Start-Sleep bloquant figerait la barre : on pompe les messages Windows par petits pas
function Wait-WithAnimation([double]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
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

$splash = New-SplashWindow -LocaleLabel (Get-LocaleLabel $Locale (Join-Path $PSScriptRoot 'locales.json'))

try {
    Update-SplashStatus $splash 'Fermeture du client Riot…'
    if (-not $DryRun) { Stop-RiotProcesses } else { Wait-WithAnimation 1 }

    Update-SplashStatus $splash "Application de la langue $Locale…"
    Set-LeagueLocale -Path $YamlPath -Value $Locale
    Wait-WithAnimation 0.5

    Update-SplashStatus $splash 'Lancement de League of Legends…'
    if (-not $DryRun) { Start-LeagueClient -Path $config.riotClientPath -Value $Locale }
    Wait-WithAnimation 0.5

    if (Test-CompanionAppEnabled $config) {
        $appName = if ($config.companionApp.name) { $config.companionApp.name } else { 'application compagnon' }
        Update-SplashStatus $splash "Lancement de $appName…"
        $started = if ($DryRun) { Test-Path $config.companionApp.path } else { Start-CompanionApp $config.companionApp }
        if (-not $started) { Update-SplashStatus $splash "$appName introuvable — ignoré (vérifier config.json)" }
        Wait-WithAnimation 1.5
    } else {
        Wait-WithAnimation 1
    }
}
finally {
    $splash.Close()
    $splash.Dispose()
}
