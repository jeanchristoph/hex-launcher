<#
.SYNOPSIS
    Détecte les emplacements de Riot et de l'application compagnon sur cette machine et génère config.json.

.DESCRIPTION
    - Riot Client : lu dans RiotClientInstalls.json (fichier officiel de Riot, à jour même après déplacement)
    - Fichier de langue : Metadata\league_of_legends.live\ sous ProgramData
    - Applications compagnon : toutes les applis de companion-apps.json présentes sur la machine (détection
      par les clés Uninstall du registre, en lecture seule, exécutable de lancement présent) → liste companionApps

    Un config.json existant n'est jamais écrasé sans -Force : les réglages faits à la main sont conservés.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File detect-config.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File detect-config.ps1 -Force
#>
param(
    [string]$OutputPath,
    [switch]$Force
)

$RiotInstallsPath  = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
$RiotClientDefault = 'C:\Riot Games\Riot Client\RiotClientServices.exe'
$ProductSettings   = Join-Path $env:ProgramData 'Riot Games\Metadata\league_of_legends.live\league_of_legends.live.product_settings.yaml'

. (Join-Path $PSScriptRoot 'lib\companion-app.lib.ps1')
$CompanionCatalogPath = Join-Path $PSScriptRoot 'companion-apps.json'

function Find-RiotClientPath {
    if (Test-Path $RiotInstallsPath) {
        $installs = Get-Content -Path $RiotInstallsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in 'rc_live', 'rc_default') {
            $candidate = $installs.$key
            if ($candidate -and (Test-Path $candidate)) { return ($candidate -replace '/', '\') }
        }
    }
    return $RiotClientDefault
}

# Ajouter une appli : une entrée dans companion-apps.json (voir README.md).
# Une appli n'entre dans config.json que si son exécutable de lancement existe ; un catalogue absent ou
# invalide ne bloque pas la détection des chemins Riot (l'appli compagnon est optionnelle).
function Get-DetectedCompanionApps {
    try { $catalog = Read-CompanionCatalog $CompanionCatalogPath }
    catch { Write-Warning "Applis compagnon ignorées : $($_.Exception.Message)"; return @() }
    $launchable = @(Get-InstalledCompanionApps $catalog | Where-Object { Test-Path (Expand-CompanionPath $_.App.launch.path) })
    return @($launchable | ForEach-Object { ConvertTo-LaunchCompanionEntry $_.App })
}

function New-LaunchConfig {
    return [ordered]@{
        riotClientPath      = Find-RiotClientPath
        productSettingsPath = $ProductSettings
        companionApps       = @(Get-DetectedCompanionApps)
    }
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par setup.ps1 ou les tests)

function Invoke-ConfigDetection([string]$OutputPath, [bool]$Force) {
    if ((Test-Path $OutputPath) -and -not $Force) {
        "config.json existant conservé : $OutputPath"
        "  (supprimer le fichier ou relancer avec -Force pour re-détecter)"
        return
    }
    $config = New-LaunchConfig
    Write-LaunchConfig $config $OutputPath
    "config.json généré : $OutputPath"
    "  Riot Client        : $($config.riotClientPath)" + $(if (Test-Path $config.riotClientPath) { '' } else { '  [INTROUVABLE]' })
    "  Fichier de langue  : $($config.productSettingsPath)" + $(if (Test-Path $config.productSettingsPath) { '' } else { '  [INTROUVABLE — LoL est-il installé ?]' })
    if ($config.companionApps.Count -gt 0) {
        "  Applis compagnon   : $(($config.companionApps | ForEach-Object { $_.name }) -join ', ')"
    } else {
        "  Applis compagnon   : aucune détectée — choix possible à l'étape suivante"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'config.json' }
    Invoke-ConfigDetection $OutputPath ([bool]$Force)
}
