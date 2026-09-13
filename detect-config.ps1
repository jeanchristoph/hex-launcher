<#
.SYNOPSIS
    Détecte les emplacements de Riot et de l'application compagnon sur cette machine et génère config.json.

.DESCRIPTION
    - Riot Client : lu dans RiotClientInstalls.json (fichier officiel de Riot, à jour même après déplacement)
    - Fichier de langue : Metadata\league_of_legends.live\ sous ProgramData
    - Application compagnon : première trouvée parmi Porofessor (Overwolf), Blitz, OP.GG — sinon désactivée

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

$OverwolfLauncher     = Join-Path ${env:ProgramFiles(x86)} 'Overwolf\OverwolfLauncher.exe'
$PorofessorExtension  = 'pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh'
$PorofessorExtensionDir = Join-Path $env:LOCALAPPDATA "Overwolf\Extensions\$PorofessorExtension"

# Ordre = priorité. Ajouter une entrée ici pour reconnaître une autre application.
$CompanionCandidates = @(
    @{
        Name      = 'Porofessor'
        Path      = $OverwolfLauncher
        Arguments = "-launchapp $PorofessorExtension -from-startmenu"
        Test      = { (Test-Path $OverwolfLauncher) -and (Test-Path $PorofessorExtensionDir) }
    }
    @{
        Name      = 'Blitz'
        Path      = Join-Path $env:LOCALAPPDATA 'Programs\Blitz\Blitz.exe'
        Arguments = ''
    }
    @{
        Name      = 'OP.GG'
        Path      = Join-Path $env:LOCALAPPDATA 'Programs\OP.GG\OP.GG.exe'
        Arguments = ''
    }
)

function Find-RiotClientPath {
    if (Test-Path $RiotInstallsPath) {
        $installs = Get-Content -Path $RiotInstallsPath -Raw | ConvertFrom-Json
        foreach ($key in 'rc_live', 'rc_default') {
            $candidate = $installs.$key
            if ($candidate -and (Test-Path $candidate)) { return ($candidate -replace '/', '\') }
        }
    }
    return $RiotClientDefault
}

function Test-CompanionCandidate([hashtable]$Candidate) {
    if ($Candidate.Test) { return & $Candidate.Test }
    return Test-Path $Candidate.Path
}

function Find-CompanionApp {
    foreach ($candidate in $CompanionCandidates) {
        if (Test-CompanionCandidate $candidate) {
            return [ordered]@{
                enabled   = $true
                name      = $candidate.Name
                path      = $candidate.Path
                arguments = $candidate.Arguments
            }
        }
    }
    return [ordered]@{ enabled = $false; name = ''; path = ''; arguments = '' }
}

function New-LaunchConfig {
    return [ordered]@{
        riotClientPath      = Find-RiotClientPath
        productSettingsPath = $ProductSettings
        companionApp        = Find-CompanionApp
    }
}

function Write-LaunchConfig([hashtable]$Config, [string]$Path) {
    $json = $Config | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($Path, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- Main

if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'config.json' }

if ((Test-Path $OutputPath) -and -not $Force) {
    "config.json existant conservé : $OutputPath"
    "  (supprimer le fichier ou relancer avec -Force pour re-détecter)"
    exit 0
}

$config = New-LaunchConfig
Write-LaunchConfig $config $OutputPath

"config.json généré : $OutputPath"
"  Riot Client        : $($config.riotClientPath)" + $(if (Test-Path $config.riotClientPath) { '' } else { '  [INTROUVABLE]' })
"  Fichier de langue  : $($config.productSettingsPath)" + $(if (Test-Path $config.productSettingsPath) { '' } else { '  [INTROUVABLE — LoL est-il installé ?]' })
if ($config.companionApp.enabled) {
    "  Appli compagnon    : $($config.companionApp.name) ($($config.companionApp.path))"
} else {
    "  Appli compagnon    : aucune détectée (Porofessor, Blitz, OP.GG) — désactivée, éditable dans config.json"
}
