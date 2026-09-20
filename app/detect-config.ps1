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
    powershell -NoProfile -ExecutionPolicy Bypass -File detect-config.ps1 -Language en
#>
param(
    [string]$OutputPath,
    [switch]$Force,

    # Langue des messages : fr, en ou ja (défaut : langue de Windows, sinon anglais)
    [string]$Language
)

$ProductSettings = Join-Path $env:ProgramData 'Riot Games\Metadata\league_of_legends.live\league_of_legends.live.product_settings.yaml'

. (Join-Path $PSScriptRoot 'lib\i18n.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\companion-app.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\riot-install.lib.ps1')   # Find-RiotClientPath : RiotClientInstalls.json, fichier officiel de Riot
$CompanionCatalogPath = Join-Path $PSScriptRoot 'companion-apps.json'

# Ajouter une appli : une entrée dans companion-apps.json (voir README.md).
# Une appli n'entre dans config.json que si son exécutable de lancement existe ; un catalogue absent ou
# invalide ne bloque pas la détection des chemins Riot (l'appli compagnon est optionnelle).
function Get-DetectedCompanionApps {
    try { $catalog = Read-CompanionCatalog $CompanionCatalogPath }
    catch { Write-Warning (Get-Text 'detect.companionIgnored' $_.Exception.Message); return @() }
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
        Get-Text 'detect.kept' $OutputPath
        Get-Text 'detect.keptHint'
        return
    }
    $config = New-LaunchConfig
    Write-LaunchConfig $config $OutputPath
    Get-Text 'detect.generated' $OutputPath
    (Get-Text 'detect.riotClientLine' $config.riotClientPath) + $(if (Test-Path $config.riotClientPath) { '' } else { Get-Text 'detect.missingMark' })
    (Get-Text 'detect.productSettingsLine' $config.productSettingsPath) + $(if (Test-Path $config.productSettingsPath) { '' } else { Get-Text 'detect.missingLolMark' })
    $companions = if ($config.companionApps.Count -gt 0) { ($config.companionApps | ForEach-Object { $_.name }) -join ', ' } else { Get-Text 'detect.noCompanion' }
    Get-Text 'detect.companionsLine' $companions
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-Translation (Resolve-UiLanguage $Language (Get-UICulture).Name) | Out-Null
    if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'config.json' }
    Invoke-ConfigDetection $OutputPath ([bool]$Force)
}
