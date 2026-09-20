<#
.SYNOPSIS
    Emplacements déclarés par Riot sur cette machine : Riot Client et dossier de League of Legends, lus dans RiotClientInstalls.json.

.DESCRIPTION
    Chargé par dot-sourcing (detect-config.ps1, create-shortcuts.ps1) :
        . (Join-Path $PSScriptRoot 'lib\riot-install.lib.ps1')

    %ProgramData%\Riot Games\RiotClientInstalls.json est le fichier officiel de Riot, à jour même après un déplacement
    du jeu : rc_live / rc_default donnent le Riot Client, associated_client associe chaque dossier de jeu installé
    (« C:/Riot Games/League of Legends/ ») à son Riot Client. Lecture seule ; rien n'est mémorisé ici — le chemin du
    Riot Client entre dans config.json par detect-config.ps1, celui de LeagueClient.exe est relu à chaque installation
    de raccourcis (un config.json existant n'est jamais réécrit).
#>

$RiotInstallsPath      = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
$RiotClientDefault     = 'C:\Riot Games\Riot Client\RiotClientServices.exe'
$LeagueClientExeName   = 'LeagueClient.exe'

# Contenu du fichier officiel, $null s'il manque ou ne se lit pas (Riot absent de la machine)
function Read-RiotClientInstalls {
    if (-not (Test-Path $RiotInstallsPath)) { return $null }
    try { return Get-Content -Path $RiotInstallsPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json }
    catch { return $null }
}

function ConvertTo-WindowsPath([string]$Path) {
    return ($Path -replace '/', '\')
}

# Riot Client déclaré (rc_live puis rc_default, s'il existe sur le disque), sinon le chemin d'installation par défaut
function Find-RiotClientPath {
    $installs = Read-RiotClientInstalls
    if ($installs) {
        foreach ($key in 'rc_live', 'rc_default') {
            $candidate = $installs.$key
            if ($candidate -and (Test-Path $candidate)) { return ConvertTo-WindowsPath $candidate }
        }
    }
    return $RiotClientDefault
}

# Dossiers de jeu déclarés dans associated_client (clés de l'objet), en chemins Windows
function Get-RiotGameFolders($Installs) {
    if (-not $Installs -or $null -eq $Installs.associated_client) { return @() }
    return @($Installs.associated_client.PSObject.Properties | ForEach-Object { ConvertTo-WindowsPath $_.Name })
}

# LeagueClient.exe du premier dossier de jeu qui le contient ; $null si League of Legends n'est pas installé
function Find-LeagueClientPath {
    foreach ($folder in Get-RiotGameFolders (Read-RiotClientInstalls)) {
        $candidate = Join-Path $folder $LeagueClientExeName
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}
