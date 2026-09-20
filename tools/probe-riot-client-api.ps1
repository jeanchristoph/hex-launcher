<#
.SYNOPSIS
    Sonde de l'API locale du Riot Client : état des process Riot, puis une requête par argument, code et durée.

.DESCRIPTION
    Outil de développement, hors release. Réutilise l'adapter du lanceur (lockfile, transport WinHTTP) pour
    mesurer ce que répond le Riot Client dans un état donné — fenêtre fermée, jeu fermé, session en cours de
    libération — sans rien lancer ni fermer. Le mot de passe du lockfile n'est jamais affiché.

    Chaque requête s'écrit MÉTHODE CHEMIN [CORPS] ; sans argument, la sonde envoie un jeu de routes de référence.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\probe-riot-client-api.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\probe-riot-client-api.ps1 "GET /riotclient/region-locale" "PUT /riotclient/product-locales/products/league_of_legends/patchlines/live ""fr_FR"""
#>
param([Parameter(ValueFromRemainingArguments)][string[]]$Requests)

$appRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'app'
. (Join-Path $appRoot 'lib\launch-log.lib.ps1')
. (Join-Path $appRoot 'lib\riot-client-api.lib.ps1')

# Routes de référence : lecture, langue, lancement (non envoyé par défaut : il démarre le jeu), interface
$DefaultRequests = @(
    'GET /riotclient/region-locale',
    'GET /riotclient/product-locales/products/league_of_legends/patchlines/live',
    'GET /product-session/v1/sessions',
    'GET /riotclient/ux-state',
    'GET /swagger/v3/openapi.json'
)

function Show-RiotProcesses {
    $names = @('RiotClientServices', 'RiotClientUx', 'RiotClientUxRender', 'Riot Client', 'LeagueClient', 'LeagueClientUx', 'LeagueClientUxRender')
    $running = @(Get-Process -Name $names -ErrorAction SilentlyContinue | Group-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count })
    if ($running.Count -eq 0) { return 'process Riot : aucun' }
    return 'process Riot : ' + ($running -join ', ')
}

function Split-ProbeRequest([string]$Request) {
    $parts = $Request.Trim() -split '\s+', 3
    return [pscustomobject]@{ Method = $parts[0].ToUpperInvariant(); Path = $parts[1]; Body = $(if ($parts.Count -gt 2) { $parts[2] } else { '' }) }
}

function Send-ProbeRequest($Lockfile, [string]$Request) {
    $probe = Split-ProbeRequest $Request
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-RiotClientRequest -Method $probe.Method -Path $probe.Path -Lockfile $Lockfile -Body $probe.Body
    return '{0,-6} {1,-75} -> {2,3} en {3}' -f $probe.Method, $probe.Path, $result.StatusCode, (Format-LaunchLogDuration $chrono)
}

Show-RiotProcesses
$lockfile = Read-RiotClientLockfile
if (-not $lockfile) { 'lockfile : absent ou illisible — aucune requête envoyée'; exit 1 }
'lockfile : pid={0} port={1}' -f $lockfile.ProcessId, $lockfile.Port
$toSend = if ($Requests -and $Requests.Count -gt 0) { $Requests } else { $DefaultRequests }
foreach ($request in $toSend) { Send-ProbeRequest $lockfile $request }
