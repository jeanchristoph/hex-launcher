<#
.SYNOPSIS
    Journal de lancement : une ligne horodatée par étape, pour savoir après coup ce que le lanceur a tenté.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\launch-log.lib.ps1')

    launch.log (à côté de config.json, gitignoré, hors release) :
        2026-09-20 02:45:11  START   locale=ja_JP companion=blitz memoire=tenter
        2026-09-20 02:45:13  API     PUT /riotclient/product-locales/... -> 201 en 1,7s
        2026-09-20 02:45:21  END     issue=api duree=10,4s

    Le splash ne montre qu'une étape à la fois et disparaît ; ce fichier reste. C'est la seule trace disponible
    quand quelqu'un signale « ça ne marche plus » sans pouvoir reproduire.

    INVARIANT : le mot de passe du lockfile n'est jamais écrit — seuls la méthode, le chemin et le code HTTP le sont.
    INVARIANT : aucune écriture de journal ne peut faire échouer un lancement. Un disque plein coûte la trace,
    jamais la partie.
#>

$LaunchLogFileName = 'launch.log'

# Au-delà, la moitié la plus ancienne est écartée : le fichier doit rester lisible et ne jamais grossir sans fin
$LaunchLogMaxBytes = 200KB

$script:LaunchLogPath = ''

function Set-LaunchLogPath([string]$Path) {
    $script:LaunchLogPath = $Path
    Limit-LaunchLogSize $Path
}

# Journal tronqué à la moitié la plus récente, sur une limite de lignes entières
function Limit-LaunchLogSize([string]$Path) {
    try {
        if (-not (Test-Path $Path)) { return $false }
        if ((Get-Item $Path).Length -le $LaunchLogMaxBytes) { return $false }
        $lines = @(Get-Content -Path $Path -Encoding UTF8)
        $kept  = @($lines | Select-Object -Last ([int]($lines.Count / 2)))
        [IO.File]::WriteAllLines($Path, $kept, (New-Object Text.UTF8Encoding($true)))
        return $true
    } catch {
        return $false
    }
}

function Format-LaunchLogLine([string]$Step, [string]$Detail) {
    return '{0}  {1,-7} {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Step, $Detail
}

# Écrit une ligne ; sans chemin défini (dot-sourcing des tests, mode script), le journal est simplement ignoré
function Write-LaunchLogLine([string]$Step, [string]$Detail) {
    if (-not $script:LaunchLogPath) { return $false }
    try {
        # UTF-8 AVEC BOM : un journal de support s'ouvre dans le Bloc-notes ou se lit par Get-Content sans
        # préciser d'encodage, et les accents doivent y apparaître correctement sans qu'on ait à y penser
        [IO.File]::AppendAllText($script:LaunchLogPath, (Format-LaunchLogLine $Step $Detail) + "`r`n", (New-Object Text.UTF8Encoding($true)))
        return $true
    } catch {
        return $false
    }
}

# Durées en secondes, une décimale : assez précis pour comparer deux lancements, assez court pour rester lisible
# Lancements journalisés depuis un instant donné : les lignes START d'un lancement réel, jamais celles d'un
# lancement refusé (« START refusé — … »). Lecture bornée aux dernières lignes — le journal peut peser 200 Ko.
# Rend 0 sur tout incident : un journal illisible ne doit rien changer au lancement.
$LaunchLogRecentTailLines = 400

function Get-RecentLaunchCount([string]$Path, [datetime]$Since) {
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $count = 0
        foreach ($line in @(Get-Content -Path $Path -Encoding UTF8 -Tail $LaunchLogRecentTailLines)) {
            if ($line -notmatch '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})  START   locale=') { continue }
            if ([datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) -ge $Since) { $count++ }
        }
        return $count
    } catch {
        return 0
    }
}

function Format-LaunchLogDuration($Chrono) {
    return '{0:N1}s' -f $Chrono.Elapsed.TotalSeconds
}
