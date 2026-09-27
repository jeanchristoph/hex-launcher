<#
.SYNOPSIS
    Journal de session du client LoL : savoir quand sa vérification d'installation est passée, pour poser le texte forcé après.

.DESCRIPTION
    Chargé par dot-sourcing, après lib\launch-log.lib.ps1 et lib\riot-client-api.lib.ps1 (Read-LockedFileText) :
        . (Join-Path $PSScriptRoot 'lib\league-client-log.lib.ps1')

    Le client LoL vérifie l'installation une seule fois par session, ~11 s après son démarrage (plugin
    rcp-be-lol-patch), après la connexion (~9 s), et répare tout fichier qui diffère du manifest ; aucune vérification
    au lancement d'une partie (journaux du 21 au 27/09/2026). Une pose faite avant cette vérification est annulée
    (essai réel du 2026-09-27 : réparée à +14 s, erreur de connexion). Ni l'API du client ni l'état du patcher ne
    prouvent que la vérification a eu lieu : seul son propre journal le dit.

    INVARIANT : le journal est lu seulement, en partage (le client le garde ouvert en écriture).
#>

$LeagueClientLogFolder = 'Logs\LeagueClient Logs'
$LeagueClientLogFilter = '*_LeagueClient.log'

# Fin de la vérification d'installation : installation conforme, ou réparation terminée
$LeagueClientVerifiedMarkers = @('Patcher Install is up to date', 'Patcher Game update successful')
$LeagueClientLoginMarker     = 'Login complete.'

# Au-delà, la vérification n'a pas été constatée (client lent, format du journal changé) : on renonce
$LeagueClientVerificationTimeoutSeconds = 180

# Journal de la session démarrée depuis $Since (celui du client lancé par ce lancement) ; $null s'il n'existe pas encore
function Find-LeagueClientSessionLog([string]$LeagueFolder, [datetime]$Since) {
    $folder = Join-Path $LeagueFolder $LeagueClientLogFolder
    if (-not (Test-Path -LiteralPath $folder)) { return $null }
    $latest = Get-ChildItem -LiteralPath $folder -Filter $LeagueClientLogFilter -File -ErrorAction SilentlyContinue |
              Where-Object { $_.CreationTime -ge $Since } |
              Sort-Object CreationTime -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    return $latest.FullName
}

# Vérification d'installation terminée et connexion faite : les fichiers ne seront plus contrôlés de la session
function Test-LeagueClientVerified([string]$Text) {
    if (-not $Text -or -not $Text.Contains($LeagueClientLoginMarker)) { return $false }
    foreach ($marker in $LeagueClientVerifiedMarkers) { if ($Text.Contains($marker)) { return $true } }
    return $false
}

function Test-LeagueClientSessionVerified([string]$LeagueFolder, [datetime]$Since) {
    $log = Find-LeagueClientSessionLog $LeagueFolder $Since
    if (-not $log) { return $false }
    return Test-LeagueClientVerified (Read-LockedFileText $log)
}

<#
    Attend la vérification de la session courante. $Wait = { LeagueFolder, Since, OnTick, ShouldStop }.
    Rend $true dès qu'elle est constatée, $false à l'échéance ou sur demande d'arrêt.
#>
function Wait-LeagueClientVerification($Wait) {
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    while ($chrono.Elapsed.TotalSeconds -lt $LeagueClientVerificationTimeoutSeconds) {
        if (Test-LeagueClientSessionVerified $Wait.LeagueFolder $Wait.Since) {
            Write-LaunchLogLine 'TEXT' ('vérification du client LoL constatée en {0}' -f (Format-LaunchLogDuration $chrono)) | Out-Null
            return $true
        }
        if ($Wait.ShouldStop -and (& $Wait.ShouldStop)) { return $false }
        if ($Wait.OnTick) { & $Wait.OnTick } else { Start-Sleep -Seconds 1 }
    }
    return (Test-LeagueClientSessionVerified $Wait.LeagueFolder $Wait.Since)
}
