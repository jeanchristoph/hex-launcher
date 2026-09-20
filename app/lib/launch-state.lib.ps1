<#
.SYNOPSIS
    Mémoire de lancement : ce que le lanceur a appris de l'API locale du Riot Client sur cette machine.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\launch-state.lib.ps1')

    launch-state.json (à côté de config.json, gitignoré, hors release) :
        localApi = { failureCount, riotClientVersion, lastOutcome, lastCheck }

    Séparé de config.json à dessein : config.json porte les intentions de l'utilisateur (langues, compagnons,
    jeu d'icônes) et n'est réécrit qu'à l'installation ; ce fichier porte des observations de la machine, mises à
    jour à chaque lancement.

    Trois champs décident, les autres ne servent qu'à la lecture humaine en cas de support :
      - failureCount     : échecs consécutifs de même cause ; au seuil de cette cause, on ne tente plus l'API
      - failureKind      : cause du dernier échec, qui fixe ce seuil (voir $LocalApiFailureThresholds)
      - riotClientVersion: version du Riot Client lors du dernier verdict ; si elle change, on retente

    INVARIANT : aucune écriture de ce fichier ne peut faire échouer un lancement. Un disque en lecture seule
    coûte la mémoire, jamais la partie.
#>

$LaunchStateFileName = 'launch-state.json'

# BUSINESS_RULE : la cause de l'échec décide combien de fois on réessaie, parce que tous les échecs ne disent
# pas la même chose.
#   route   — l'API a répondu qu'elle refuse (404, 401, 403) : une fois suffit, insister n'y changera rien
#   silent  — lancement accepté mais aucun client de jeu : l'endpoint est probablement vidé de son effet
#   timeout — jamais accepté dans le budget : machine lente, patch en cours, Vanguard qui démarre. Ce n'est pas
#             une panne de l'API, et deux mauvais jours ne doivent pas priver le poste du lancement direct.
$LocalApiFailureThresholds = @{ route = 1; silent = 2; timeout = 5 }
$LocalApiDefaultFailureThreshold = 2

function Get-LocalApiFailureThreshold([string]$Kind) {
    if ($LocalApiFailureThresholds.ContainsKey($Kind)) { return $LocalApiFailureThresholds[$Kind] }
    return $LocalApiDefaultFailureThreshold
}

# Cause d'un échec du chemin rapide : Kind décide, StatusCode et Stage sont là pour le support
function New-LocalApiFailure([string]$Kind, [int]$StatusCode, [string]$Stage) {
    return [pscustomobject]@{ Kind = $Kind; StatusCode = $StatusCode; Stage = $Stage }
}

function New-LaunchState {
    return [pscustomobject]@{
        localApi = [pscustomobject]@{
            failureCount      = 0
            failureKind       = ''
            failureStatusCode = 0
            failureStage      = ''
            riotClientVersion = ''
            lastOutcome       = ''
            lastCheck         = ''
        }
    }
}

# Un fichier absent, illisible ou tronqué rend un état neuf : la mémoire est un confort, jamais un prérequis
function Read-LaunchState([string]$Path) {
    if (-not (Test-Path $Path)) { return New-LaunchState }
    try {
        $state = Read-JsonFile $Path
        if ($null -eq $state.localApi) { return New-LaunchState }
        $fresh = New-LaunchState
        $fresh.localApi.failureCount      = [int]$state.localApi.failureCount
        $fresh.localApi.failureKind       = [string]$state.localApi.failureKind
        $fresh.localApi.failureStatusCode = [int]$state.localApi.failureStatusCode
        $fresh.localApi.failureStage      = [string]$state.localApi.failureStage
        $fresh.localApi.riotClientVersion = [string]$state.localApi.riotClientVersion
        $fresh.localApi.lastOutcome       = [string]$state.localApi.lastOutcome
        $fresh.localApi.lastCheck         = [string]$state.localApi.lastCheck
        return $fresh
    } catch {
        return New-LaunchState
    }
}

function Write-LaunchState($State, [string]$Path) {
    try {
        Write-JsonFile $State $Path
        return $true
    } catch {
        Write-Warning 'Mémoire de lancement non enregistrée (dossier en lecture seule ?) — sans effet sur le jeu.'
        return $false
    }
}

# Version du Riot Client sur le disque : lue sans API, pour savoir si Riot a bougé depuis le dernier verdict
function Get-RiotClientVersion([string]$Path) {
    try {
        return [string](Get-Item $Path -ErrorAction Stop).VersionInfo.ProductVersion
    } catch {
        return ''
    }
}

# Vaut-il la peine de tenter l'API locale ? Oui tant que les échecs de cette cause n'ont pas atteint son seuil,
# et de nouveau dès que le Riot Client change de version : une mise à jour est exactement ce qui peut réparer
# son API — ou la casser.
function Test-LocalApiWorthTrying($State, [string]$RiotClientVersion) {
    if ($State.localApi.riotClientVersion -ne $RiotClientVersion) { return $true }
    return ($State.localApi.failureCount -lt (Get-LocalApiFailureThreshold $State.localApi.failureKind))
}

# Nouveau verdict. Seuls s'additionnent les échecs de même cause sur la même version : un changement de l'une
# ou de l'autre repart de zéro, parce qu'il décrit une situation différente.
function Update-LocalApiOutcome($State, [bool]$Succeeded, [string]$RiotClientVersion, $Failure) {
    $updated = New-LaunchState
    $kind = if ($Succeeded -or $null -eq $Failure) { '' } else { [string]$Failure.Kind }
    $continues = ($State.localApi.riotClientVersion -eq $RiotClientVersion) -and ($State.localApi.failureKind -eq $kind)
    $previousFailures = if ($continues) { [int]$State.localApi.failureCount } else { 0 }

    $updated.localApi.failureCount      = if ($Succeeded) { 0 } else { $previousFailures + 1 }
    $updated.localApi.failureKind       = $kind
    $updated.localApi.failureStatusCode = if ($Succeeded -or $null -eq $Failure) { 0 } else { [int]$Failure.StatusCode }
    $updated.localApi.failureStage      = if ($Succeeded -or $null -eq $Failure) { '' } else { [string]$Failure.Stage }
    $updated.localApi.riotClientVersion = $RiotClientVersion
    $updated.localApi.lastOutcome       = if ($Succeeded) { 'success' } else { 'failure' }
    $updated.localApi.lastCheck         = (Get-Date).ToString('s')
    return $updated
}
