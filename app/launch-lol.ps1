<#
.SYNOPSIS
    Lance League of Legends dans la langue demandée, avec un splash animé.

.DESCRIPTION
    Chemin rapide : ferme le seul client de jeu — par l'API locale du Riot Client, qui clôt la session de jeu
    proprement là où un kill vaut une manipulation pour Vanguard (VAN 216), le kill restant le dernier recours —,
    pose la langue par cette même API (le Riot Client écrit alors le yaml lui-même) et lui demande le lancement,
    l'équivalent du bouton Play. Le Riot Client quitte après une fermeture par l'API : il est redémarré à froid.
    Chemin historique, conservé en repli : ferme tous les process Riot, réécrit settings.locale dans
    league_of_legends.live.product_settings.yaml, relance avec --launch-product. Il sert dès que l'API locale ne
    répond pas, refuse, ou que le client de jeu n'apparaît pas — et sur demande avec -NoLocalApi.
    Un Riot Client replié sur son icône dont la partie s'est terminée n'a plus ni fenêtre ni API (toutes ses
    routes répondent 404, son serveur a changé de port) : le chemin rapide le relance sans argument — la même
    instance rouvre sa fenêtre et recharge son API en deux secondes, sans kill ni session serveur abandonnée.
    Passé 2 min d'attente, le splash montre « Forcer en démarrage manuel » : un clic abandonne le chemin rapide et
    passe en démarrage manuel (Riot relancé, Jouer à cliquer) pour ce lancement seulement — rien n'est mémorisé.
    La croix en haut à droite du splash arrête le lanceur sans rien faire d'autre : rien n'est tué, Riot et le jeu
    restent en l'état, pour réessayer plus tard.
    Chaque étape est tracée dans launch.log, une ligne horodatée par événement, appels d'API compris.
    Le lanceur n'a pas de mémoire : l'API est tentée à chaque lancement, sauf -NoLocalApi ou la case
    « Démarrage manuel » de setup.bat. Une mémoire des échecs a existé (0.2.0, retirée) : elle transformait un
    refus ponctuel en démarrage manuel permanent, sans rien montrer à l'utilisateur.
    En dernier ressort, le bouton Play du Riot Client reste actif : le lanceur n'échoue jamais durement.
    Arbre de décision complet : .forge/branch/launcher/output/20260920-launch-decision-tree.md

    Dans tous les cas, ferme ensuite les autres applications compagnon de config.json (une seule active pendant
    la partie, sinon les overlays entrent en conflit), puis lance celle demandée par -Companion (Porofessor,
    Blitz…) si elle figure dans la liste companionApps.

    Les chemins machine (Riot, yaml, applications compagnon) sont lus dans config.json, à côté de ce script.
    Voir README.md pour l'adapter à un autre poste.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP -Companion blitz
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File launch-lol.ps1 -Locale ja_JP -NoLocalApi
#>
param(
    # Code de langue Riot à appliquer (ex. ja_JP) : requis à l'exécution, facultatif au dot-sourcing des tests
    [ValidatePattern('^[a-z]{2}_[A-Z]{2}$')]
    [string]$Locale,

    # Identifiant de l'appli compagnon à lancer après le jeu (companionApps de config.json). Absent → aucune.
    [string]$Companion,

    # Par défaut : config.json à côté de ce script
    [string]$ConfigPath,

    # Ignore le chemin du yaml de config.json (utilisé pour tester sur une copie)
    [string]$YamlPath,

    # Ignore l'API locale du Riot Client et prend directement le chemin historique (dépannage)
    [switch]$NoLocalApi,

    # Ne ferme aucun process et ne lance rien : sert à tester le splash et la réécriture du yaml
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'lib\splash.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\launch-config.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\launch-log.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\riot-client-api.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\riot-window.lib.ps1')

# Client de jeu seul : ce que le chemin rapide ferme, en laissant la session du Riot Client vivante
$GameClientProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient')

# Tout Riot : ce que ferme le chemin historique, faute de pouvoir poser la langue autrement que dans le yaml
$RiotProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient', 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices')

# Produit Riot lancé par ce lanceur, tel que le Riot Client le nomme
$LeagueProductId   = 'league_of_legends'
$LeaguePatchlineId = 'live'

# Chemin rapide sans limite de temps (0 = aucune, voir $NoTimeLimitSeconds) : tant que Riot répond « pas encore »
# — patch du jeu en cours, qui peut durer des heures sur une connexion lente, session à libérer — le lanceur
# attend. Seuls un refus franc de l'API ou le bouton « Forcer en démarrage manuel » du splash font basculer.
# Un budget de 60 s, puis 6 min, a existé : sur un poste lent il basculait en démarrage manuel au milieu d'un patch
# (décision de l'utilisateur, 2026-09-20).
$LocalApiBudgetSeconds = $NoTimeLimitSeconds

# Un lancement accepté ne prouve rien : le client de jeu doit apparaître. Sans limite (0, voir $NoTimeLimitSeconds) :
# c'est l'étape qui souffre le plus d'un disque lent ou d'un Vanguard qui démarre, et basculer en démarrage manuel
# tuerait un client peut-être en train de venir. Le bouton « Forcer » du splash reste la sortie (utilisateur, 2026-09-20).
$GameClientStartTimeoutSeconds = $NoTimeLimitSeconds

# Temps laissé au client de jeu pour disparaître après une fermeture acceptée par l'API (mesuré : 0,5 s) ; au-delà,
# le kill reprend la main
$GameClientStopTimeoutSeconds = 5

# Délai avant de proposer « Forcer en démarrage manuel » : un lancement normal tient en 8 à 13 s sur un poste rapide,
# près d'une minute sur un poste ordinaire — le bouton ne doit tenter personne quand tout va bien, il n'a de sens
# que sur une attente qui s'éternise (session à libérer, API muette)
$ForceStartButtonDelaySeconds = 120

# Réveil du Riot Client (relance sans argument pour rouvrir sa fenêtre et recharger son API, mesuré : 2 à 4 s) :
# sans échéance. Une échéance de 15 puis 30 s a existé — passée, la première requête partait vers une API absente,
# 404, démarrage manuel par erreur (17:00 le 2026-09-20). La relance est rejouée : à 5 s d'abord, car tombée
# pendant la bascule de Riot en arrière-plan (le joueur vient de fermer le jeu, Riot démonte ses plugins ~2 s)
# la première est perdue — la nouvelle instance dit « Client already running, exiting » à une instance qui
# n'écoute plus — puis toutes les 30 s, jusqu'à la fenêtre ou au clic de l'utilisateur (« Forcer », croix).
$RiotClientInterfaceRetrySeconds   = 5
$RiotClientRelaunchIntervalSeconds = 30

# Process de l'interface du Riot Client (avec une espace) : présent tant que sa fenêtre existe, réduite ou non
$RiotClientInterfaceProcessName = 'Riot Client'

# Un seul lanceur à la fois : deux raccourcis cliqués à 3 s d'écart ont donné deux boucles en parallèle, puis deux
# démarrages manuels qui se tuaient l'un l'autre (journal du 2026-09-20 17:14). Mutex et non sémaphore : un lanceur
# tué par le Gestionnaire des tâches le libère (abandonné), un sémaphore resterait pris jusqu'au redémarrage.
$LaunchMutexName = 'Local\HexLauncher.Launch'

# Temps d'affichage du splash « lancement déjà en cours » avant de s'effacer
$LaunchRefusedSplashSeconds = 3

# Temps d'affichage de « Lancement interrompu » après un clic sur la croix
$LaunchAbortedSplashSeconds = 1

# BUSINESS_RULE : Vanguard refuse le client de jeu (VAN 216, redémarrage de Windows requis) à partir du 4ᵉ
# démarrage en moins de 5 min, que la fermeture soit un kill ou un arrêt propre par l'API — mesuré trois fois le
# 2026-09-20 (~15 cycles, 4 en 3 min, 5 en 5 min). Le lanceur ne peut pas l'empêcher : il prévient au 3ᵉ, et continue.
$LaunchBurstWindowMinutes    = 5
$LaunchBurstWarningThreshold = 3
$LaunchBurstWarningSeconds   = 3
$LaunchBurstWarningMessage   = 'Trop de lancements rapprochés : risque d''erreur Vanguard VAN 216 (redémarrage de Windows requis)'

# ---------------------------------------------------------------- Config

# Libellé affiché dans le splash, depuis locales.json ; repli sur le code si absent
function Get-LocaleLabel([string]$Code, [string]$CatalogPath) {
    if (-not (Test-Path $CatalogPath)) { return $Code }
    $entry = Read-JsonCatalog $CatalogPath | Where-Object { $_.code -eq $Code }
    if ($entry) { return $entry.label }
    return $Code
}

# ---------------------------------------------------------------- Verrou

# Rend le mutex pris, ou $null si un autre lanceur le tient. Un mutex abandonné (lanceur précédent tué) est repris
function Enter-LaunchLock([string]$Name = $LaunchMutexName) {
    $mutex = New-Object Threading.Mutex($false, $Name)
    try {
        if ($mutex.WaitOne(0)) { return $mutex }
    } catch [Threading.AbandonedMutexException] {
        return $mutex
    }
    $mutex.Dispose()
    return $null
}

function Exit-LaunchLock($Mutex) {
    if (-not $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

# Vrai à partir du 3ᵉ lancement journalisé dans la fenêtre — celui-ci compris, son START étant déjà écrit
function Test-LaunchBurst([string]$LogPath) {
    $count = Get-RecentLaunchCount $LogPath (Get-Date).AddMinutes(-$LaunchBurstWindowMinutes)
    if ($count -lt $LaunchBurstWarningThreshold) { return $false }
    Write-LaunchLogLine 'WARN' ('{0} lancements en {1} min — avertissement Vanguard affiché' -f $count, $LaunchBurstWindowMinutes) | Out-Null
    return $true
}

# ---------------------------------------------------------------- Étapes

function Stop-RiotProcesses {
    $running = @(Get-Process -Name $RiotProcessNames -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }
    Write-LaunchLogLine 'KILL' ('tout Riot fermé ({0} process)' -f $running.Count) | Out-Null
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

# Un chemin de config.json périmé (Riot déplacé, réinstallé) ne doit pas faire tomber le lanceur en exception
function Start-RiotClient([string]$Path) {
    try {
        Start-Process -FilePath $Path
        Write-LaunchLogLine 'RIOT' 'Riot Client démarré (sans argument de produit)' | Out-Null
        return $true
    } catch {
        Write-LaunchLogLine 'RIOT' ('Riot Client introuvable : {0}' -f $Path) | Out-Null
        Write-Warning ('Riot Client introuvable ({0}) — relancer setup.bat pour corriger config.json.' -f $Path)
        return $false
    }
}

# Version du Riot Client sur le disque, pour le journal : un « ça ne marche plus » se lit avec la version en face
function Get-RiotClientVersion([string]$Path) {
    try {
        return [string](Get-Item $Path -ErrorAction Stop).VersionInfo.ProductVersion
    } catch {
        return ''
    }
}

# Dernier recours : Vanguard attaché au client de jeu prend un kill pour une manipulation (VAN 216 après des
# fermetures brutales rapprochées, 2026-09-20). La fermeture par l'API passe d'abord (Stop-GameClient).
function Stop-GameClientProcesses {
    $running = @(Get-Process -Name $GameClientProcessNames -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }
    Write-LaunchLogLine 'KILL' ('client de jeu fermé ({0} process)' -f $running.Count) | Out-Null
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-WithAnimation 2
}

function Test-GameClientRunning {
    return @(Get-Process -Name $GameClientProcessNames -ErrorAction SilentlyContinue).Count -gt 0
}

# Demande au Riot Client de fermer sa session de jeu — ce qu'il fait lui-même en 0,5 s (mesuré le 2026-09-20).
# Faux si son API ne répond pas ou ne connaît pas de session : le kill reste alors le seul moyen
function Stop-GameClientByLocalApi {
    $lockfile = Read-RiotClientLockfile -Quiet
    if (-not $lockfile) { return $false }
    return (Stop-RiotProduct -ProductId $LeagueProductId -Lockfile $lockfile)
}

function Wait-GameClientExit([int]$TimeoutSeconds, [scriptblock]$OnTick) {
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    while ($chrono.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (-not (Test-GameClientRunning)) { return $true }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }
    return (-not (Test-GameClientRunning))
}

# Ferme le client de jeu proprement quand l'API le permet, le tue sinon. Le Riot Client quitte lui aussi après
# une fermeture par l'API au lieu de rester replié : le chemin rapide le redémarre à froid, sans session à libérer
function Stop-GameClient([scriptblock]$OnTick) {
    if (-not (Test-GameClientRunning)) { return }
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    if ((Stop-GameClientByLocalApi) -and (Wait-GameClientExit $GameClientStopTimeoutSeconds $OnTick)) {
        Write-LaunchLogLine 'GAME' ('client de jeu fermé par l''API en {0}' -f (Format-LaunchLogDuration $chrono)) | Out-Null
        return
    }
    Stop-GameClientProcesses
}

# Un endpoint déprécié chez Riot continue de répondre en ayant perdu son effet (/riotclient/new-args rend 204
# et ne lance plus rien depuis 2022) : seule l'apparition du client de jeu prouve que le lancement a eu lieu.
# S'arrête aussi sur demande de l'appelant (-ShouldStop) : c'est lui qui distingue ensuite l'abandon de l'échéance
function Wait-GameClientStart([int]$TimeoutSeconds, [scriptblock]$OnTick, [scriptblock]$ShouldStop) {
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-WaitBudgetExhausted $chrono $TimeoutSeconds)) {
        if (Test-GameClientRunning) { return $true }
        if (Test-StopRequested $ShouldStop) { return $false }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }
    return (Test-GameClientRunning)
}

function Test-RiotClientRunning {
    return @(Get-Process -Name 'RiotClientServices' -ErrorAction SilentlyContinue).Count -gt 0
}

function Test-RiotClientInterfaceRunning {
    return @(Get-Process -Name $RiotClientInterfaceProcessName -ErrorAction SilentlyContinue).Count -gt 0
}

# Attend que l'interface soit là ET que l'API réponde : l'une sans l'autre ne suffit pas, le serveur redémarre
# sur un nouveau port et le lockfile est relu à chaque tour. Rend faux à l'échéance ou sur demande d'arrêt.
function Wait-RiotClientInterface([int]$TimeoutSeconds, [scriptblock]$OnTick, [scriptblock]$ShouldStop) {
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    while ($chrono.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-StopRequested $ShouldStop) { return $false }
        if (Test-RiotClientInterfaceRunning) {
            $lockfile = Read-RiotClientLockfile -Quiet
            if ($lockfile -and (Test-RiotClientReady $lockfile)) { return $true }
        }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }
    return $false
}

# BUSINESS_RULE : un Riot Client vivant mais sans interface n'est pas utilisable par l'API — replié sur son icône
# (croix réglée sur « réduire », ou fermée par ce lanceur une fois le jeu parti), il décharge toute son API dès
# que la partie se termine : 404 partout, port changé (mesuré le 2026-09-20, quatre fois). Le relancer sans
# argument réveille la même instance : fenêtre rouverte, API rechargée en 2 s. Jamais de kill — il laisserait
# une session serveur à expirer, jusqu'à 57 s de 424 au démarrage suivant. Rend vrai quand l'API répond, faux
# sinon — l'appelant tente alors l'API quand même, le repli restant là pour le pire cas.
# Rend vrai quand fenêtre et API sont là ; faux seulement si l'exécutable est introuvable ou si l'utilisateur a
# demandé l'arrêt — jamais sur une échéance
function Restore-RiotClientInterface([string]$Path, [scriptblock]$OnTick, [scriptblock]$ShouldStop) {
    if (Test-RiotClientInterfaceRunning) { return $true }
    Write-LaunchLogLine 'RIOT' 'Riot Client sans interface (replié après une partie) — relance pour rouvrir sa fenêtre et son API' | Out-Null
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    $relaunches = 0
    $waitSeconds = $RiotClientInterfaceRetrySeconds
    do {
        $relaunches++
        if (-not (Start-RiotClient $Path)) { return $false }
        if (Wait-RiotClientInterface $waitSeconds $OnTick $ShouldStop) {
            Write-LaunchLogLine 'RIOT' ('interface et API revenues en {0}' -f (Format-LaunchLogDuration $chrono)) | Out-Null
            return $true
        }
        if (Test-StopRequested $ShouldStop) { break }
        Write-LaunchLogLine 'RIOT' (Format-RiotRelaunchReason ($relaunches + 1) $chrono) | Out-Null
        $waitSeconds = $RiotClientRelaunchIntervalSeconds
    } while ($true)
    Write-LaunchLogLine 'RIOT' ('réveil interrompu par l''utilisateur après {0}' -f (Format-LaunchLogDuration $chrono)) | Out-Null
    return $false
}

function Format-RiotRelaunchReason([int]$Number, $Chrono) {
    if ($Number -eq 2) { return 'relance n° 2 après {0} — la première a pu tomber pendant la bascule en arrière-plan' -f (Format-LaunchLogDuration $Chrono) }
    return 'relance n° {0} après {1} — fenêtre et API toujours absentes' -f $Number, (Format-LaunchLogDuration $Chrono)
}

# Le Riot Client doit rester debout tant que le chemin rapide n'a pas abouti : son API est notre seul moyen d'agir
function Assert-RiotClientRunning([string]$Path) {
    if (Test-RiotClientRunning) { return $true }
    Write-LaunchLogLine 'RIOT' 'Riot Client absent — redémarrage' | Out-Null
    return (Start-RiotClient $Path)
}

# Une fenêtre Riot refermée pendant l'attente (croix → repli en arrière-plan, API déchargée) laisserait la boucle
# sur des codes 0 jusqu'au budget (journal du 2026-09-20 17:14 : fermée à 28 s, 3 min de code 0). Vue puis
# disparue → réveil, une fois par disparition ; jamais vue (Riot en train de démarrer) → rien, son interface arrive
function Watch-RiotClientInterface([string]$Path, [scriptblock]$OnTick, [scriptblock]$ShouldStop) {
    if (Test-RiotClientInterfaceRunning) { $script:RiotInterfaceSeen = $true; return }
    if (-not $script:RiotInterfaceSeen) { return }
    $script:RiotInterfaceSeen = $false
    Write-LaunchLogLine 'RIOT' 'interface disparue pendant l''attente — réveil' | Out-Null
    Restore-RiotClientInterface $Path $OnTick $ShouldStop | Out-Null
}

# Chemin rapide : la session du Riot Client est réutilisée si elle existe, démarrée sinon — jamais fermée.
# La langue lui est posée (il écrit alors le yaml lui-même), puis le jeu est lancé comme par le bouton Play.
# Temps qu'il reste au chemin rapide, jamais moins d'une seconde pour laisser une dernière tentative aboutir ;
# un budget sans limite le reste
function Get-RemainingBudgetSeconds($Chrono, [int]$BudgetSeconds) {
    if ($BudgetSeconds -eq $NoTimeLimitSeconds) { return $NoTimeLimitSeconds }
    return [int][Math]::Max(1, $BudgetSeconds - $Chrono.Elapsed.TotalSeconds)
}

# Cause d'un échec du chemin rapide, pour le journal : Kind ('route' — l'API refuse, 'timeout' — rien accepté dans
# le budget, 'silent' — lancement accepté sans client de jeu, 'cancelled' — l'utilisateur a forcé le démarrage),
# code HTTP et étape
function New-LocalApiFailure([string]$Kind, [int]$StatusCode, [string]$Stage) {
    return [pscustomobject]@{ Kind = $Kind; StatusCode = $StatusCode; Stage = $Stage }
}

# Rend { Success; Failure } — Failure porte la cause de l'échec, journalisée pour le support
function Start-LeagueClientByLocalApi([string]$Path, [string]$Value, [scriptblock]$OnTick, [scriptblock]$OnStatus, [scriptblock]$ShouldStop) {
    # Seul un Riot Client qui tournait déjà peut être replié sans interface ; celui qu'on démarre à froid a la
    # sienne en route, le relancer une seconde fois n'aurait aucun sens
    $wasRunning = Test-RiotClientRunning
    if (-not $wasRunning) { Write-LaunchStatus $OnStatus 'Démarrage du Riot Client…' }
    if (-not (Assert-RiotClientRunning $Path)) { return New-LocalApiAttempt $false (New-LocalApiFailure 'route' 0 'riot-client') }
    if ($wasRunning -and -not (Test-RiotClientInterfaceRunning)) {
        Write-LaunchStatus $OnStatus 'Réveil du Riot Client…'
        Restore-RiotClientInterface $Path $OnTick $ShouldStop | Out-Null
        if (Test-StopRequested $ShouldStop) { return New-LocalApiAttempt $false (New-LocalApiFailure 'cancelled' 0 'riot-client') }
    }

    # Garde préventive : si le Riot Client venait à disparaître en cours de route, la boucle attendrait un
    # lockfile qui ne reviendrait jamais. Mesuré le 2026-09-20, il survit à la fermeture du client de jeu, quel
    # que soit son mode de démarrage — mais rien ne garantit qu'un patch de Riot ne changera pas cela.
    # Noms distincts, et pas de GetNewClosure : ce bloc est invoqué depuis Wait-RiotClientOperation, qui a son
    # propre $OnTick — s'y référer ici le ferait se rappeler lui-même jusqu'à saturer la pile. GetNewClosure
    # résoudrait la capture mais attacherait le bloc à un module dynamique, aveugle aux fonctions du script.
    $guardRiotPath   = $Path
    $guardUserTick   = $OnTick
    $guardShouldStop = $ShouldStop
    # Même règle de nommage pour le motif d'attente : invoqué depuis la lib, il ne doit capturer que des noms à lui
    $waitStatusSink = $OnStatus
    $onWait = {
        param($Reason)
        $status = Get-WaitReasonStatus $Reason
        if ($status) { Write-LaunchLogLine 'WAIT' ('424 : {0}' -f $status) | Out-Null; Write-LaunchStatus $waitStatusSink $status }
    }
    $script:RiotInterfaceSeen = $false
    $guardedTick = {
        Assert-RiotClientRunning $guardRiotPath | Out-Null
        Watch-RiotClientInterface $guardRiotPath $guardUserTick $guardShouldStop
        if ($guardUserTick) { & $guardUserTick } else { Start-Sleep -Seconds 1 }
    }

    $chrono = [Diagnostics.Stopwatch]::StartNew()

    Write-LaunchStatus $OnStatus ('Application de la langue {0}…' -f $Value)
    $localeSet = Wait-RiotProductLocale -ProductId $LeagueProductId -PatchlineId $LeaguePatchlineId -Locale $Value `
        -TimeoutSeconds (Get-RemainingBudgetSeconds $chrono $LocalApiBudgetSeconds) -OnTick $guardedTick -ShouldStop $ShouldStop
    if (-not $localeSet.Success) { return New-LocalApiAttempt $false (New-LocalApiFailure $localeSet.Kind $localeSet.StatusCode 'locale') }

    # Le client de jeu en marche vaut acceptation : une demande expirée côté client (code 0) a pu être exécutée
    # par Riot, qui répond ensuite 423 « un client de jeu tourne » — le nôtre (mesuré le 2026-09-20, 55 s perdues)
    Write-LaunchStatus $OnStatus 'Demande de lancement au Riot Client…'
    $launched = Wait-RiotProductLaunch -ProductId $LeagueProductId -PatchlineId $LeaguePatchlineId `
        -TimeoutSeconds (Get-RemainingBudgetSeconds $chrono $LocalApiBudgetSeconds) -OnTick $guardedTick -ShouldStop $ShouldStop `
        -SuccessProbe { Test-GameClientRunning } -OnWait $onWait
    if (-not $launched.Success) { return New-LocalApiAttempt $false (New-LocalApiFailure $launched.Kind $launched.StatusCode 'launch') }
    if ($launched.Kind -eq 'probe') { Write-LaunchLogLine 'GAME' ('client de jeu déjà en marche pendant la demande de lancement (dernier code {0})' -f $launched.StatusCode) | Out-Null }

    Write-LaunchStatus $OnStatus 'Le jeu se prépare…'
    $gameChrono = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Wait-GameClientStart $GameClientStartTimeoutSeconds $OnTick $ShouldStop)) {
        if (Test-StopRequested $ShouldStop) { return New-LocalApiAttempt $false (New-LocalApiFailure 'cancelled' $launched.StatusCode 'game-client') }
        Write-LaunchLogLine 'GAME' ('aucun client de jeu après {0} — lancement accepté sans effet' -f (Format-LaunchLogDuration $gameChrono)) | Out-Null
        return New-LocalApiAttempt $false (New-LocalApiFailure 'silent' $launched.StatusCode 'game-client')
    }

    Write-LaunchLogLine 'GAME' ('client de jeu détecté en {0}' -f (Format-LaunchLogDuration $gameChrono)) | Out-Null
    Complete-LocalApiLaunch
    return New-LocalApiAttempt $true $null
}

# Le jeu est lancé : la fenêtre du Riot Client n'a plus rien à montrer. On lui demande de se fermer — avec
# une partie en cours il se replie sur son icône près de l'horloge au lieu de quitter, rend près de 600 Mo,
# et son API continue de répondre. Jamais en démarrage manuel, où elle sert encore à cliquer sur Jouer.
function Complete-LocalApiLaunch {
    if (Close-RiotClientWindow) { Write-LaunchLogLine 'RIOT' 'fenêtre du Riot Client fermée (repli sur l''icône)' | Out-Null }
}

# Ce que le splash dit quand Riot fait attendre le lancement (424) — textes validés par l'utilisateur le 2026-09-20
$WaitReasonStatuses = @{
    updating  = 'Mise à jour de League of Legends par Riot en cours…'
    releasing = 'Riot libère la session de jeu précédente…'
}

function Get-WaitReasonStatus([string]$Reason) {
    if ($WaitReasonStatuses.ContainsKey($Reason)) { return $WaitReasonStatuses[$Reason] }
    return ''
}

function New-LocalApiAttempt([bool]$Success, $Failure) {
    return [pscustomobject]@{ Success = $Success; Failure = $Failure }
}

# Le splash ne sait rien du lanceur et le lanceur ne sait rien du splash : ils se parlent par ce bloc
function Write-LaunchStatus([scriptblock]$OnStatus, [string]$Message) {
    if ($OnStatus) { & $OnStatus $Message }
}

# Une attente peut durer une minute, le temps que le Riot Client libère la session précédente : afficher les
# secondes écoulées montre que quelque chose se passe encore
function Format-WaitingStatus([string]$Message, $Chrono) {
    return '{0} ({1:N0} s)' -f $Message.TrimEnd([char]0x2026), $Chrono.Elapsed.TotalSeconds
}

# Chemin historique : tout Riot est fermé, la langue écrite dans le yaml, le jeu demandé en ligne de commande.
# Le Riot Client annule parfois cet auto-lancement (permission game:play arbitrée avant l'authentification RSO) :
# sa page produit reste alors ouverte, bouton Play actif — dernier repli, jamais un échec dur.
function Start-LeagueClientByCommandLine([string]$Path, [string]$YamlPath, [string]$Value) {
    Stop-RiotProcesses

    # Le yaml peut avoir bougé (LoL réinstallé ailleurs, config.json périmé). Tout Riot vient d'être fermé :
    # échouer ici laisserait l'utilisateur sans jeu et sans bouton Play. On prévient, et on lance quand même —
    # --locale est passé en argument, et Riot retombe sinon sur default_locale.
    try {
        Set-LeagueLocale -Path $YamlPath -Value $Value
    } catch {
        Write-Warning ('Fichier de langue inaccessible ({0}) : la langue du jeu ne change pas, le lancement continue.' -f $YamlPath)
    }

    try {
        Start-Process -FilePath $Path -ArgumentList "--launch-product=$LeagueProductId --launch-patchline=$LeaguePatchlineId --locale=$Value"
        Write-LaunchLogLine 'RIOT' ('Riot Client relancé avec --launch-product --locale={0}' -f $Value) | Out-Null
        return $true
    } catch {
        Write-Warning ('Riot Client introuvable ({0}) — relancer setup.bat pour corriger config.json.' -f $Path)
        return $false
    }
}

# Rend { Outcome; Failure } — Outcome vaut 'api' quand l'API locale a fait le travail, 'legacy' quand le chemin
# historique a pris le relais, 'failed' quand même lui n'a pas pu démarrer le Riot Client (chemin périmé).
# Failure n'est renseigné que si le chemin rapide a échoué : il dit pourquoi, pour le journal.
# -ShouldStop : « Forcer en démarrage manuel » — le chemin rapide rend la main, le démarrage manuel prend le relais.
# -ShouldAbort : la croix du splash — le chemin rapide rend la main et rien d'autre ne se passe (issue 'cancelled') :
# rien n'est tué, Riot et le jeu restent en l'état, l'utilisateur réessaiera plus tard.
function Start-LeagueClient([string]$Path, [string]$YamlPath, [string]$Value, [switch]$NoLocalApi, [scriptblock]$OnTick, [scriptblock]$OnStatus, [scriptblock]$ShouldStop, [scriptblock]$ShouldAbort) {
    $failure = $null

    if (-not $NoLocalApi) {
        Write-LaunchStatus $OnStatus 'Fermeture du client de jeu…'
        Stop-GameClient $OnTick
        # Un seul drapeau pour les boucles, quelle que soit la sortie choisie. Noms propres à cette fonction : le bloc
        # est invoqué depuis la lib, il retrouve ces variables parce que Start-LeagueClient est encore sur la pile
        $stopOnForce = $ShouldStop
        $stopOnAbort = $ShouldAbort
        $stopOnEither = { (Test-StopRequested $stopOnForce) -or (Test-StopRequested $stopOnAbort) }
        $attempt = Start-LeagueClientByLocalApi $Path $Value $OnTick $OnStatus $stopOnEither
        if ($attempt.Success) { return New-LaunchOutcome 'api' $null }
        if (Test-StopRequested $ShouldAbort) {
            Write-LaunchLogLine 'ABORT' 'lancement interrompu par l''utilisateur (croix du splash) — rien n''est touché' | Out-Null
            return New-LaunchOutcome 'cancelled' $attempt.Failure
        }

        # Le client de jeu a pu apparaître juste après l'échéance : le chemin historique le tuerait pour le
        # relancer, et l'utilisateur verrait le jeu s'ouvrir, disparaître, puis s'ouvrir de nouveau. Fin du chemin
        # rapide comme après un succès franc : fenêtre Riot repliée (oubliée jusqu'au 2026-09-20)
        if (Test-GameClientRunning) {
            Write-LaunchLogLine 'GAME' 'client de jeu apparu après l''échéance — lancement retenu' | Out-Null
            Complete-LocalApiLaunch
            return New-LaunchOutcome 'api' $null
        }

        $failure = $attempt.Failure
        Write-LaunchLogLine 'LEGACY' ('reprise en démarrage manuel — cause={0} code={1} étape={2}' -f $failure.Kind, $failure.StatusCode, $failure.Stage) | Out-Null
    }

    Write-LaunchStatus $OnStatus (Get-FallbackStatusMessage $failure)
    if (Start-LeagueClientByCommandLine $Path $YamlPath $Value) { return New-LaunchOutcome 'legacy' $failure }
    return New-LaunchOutcome 'failed' $failure
}

# Le statut dit à l'utilisateur pourquoi Riot se ferme : parce qu'il l'a demandé, ou parce que l'API n'a pas suivi
function Get-FallbackStatusMessage($Failure) {
    if ($Failure -and $Failure.Kind -eq 'cancelled') { return 'Démarrage manuel forcé : fermeture de Riot puis redémarrage — appuyez sur Jouer…' }
    return 'Démarrage manuel : fermeture de Riot puis redémarrage — appuyez sur Jouer…'
}

function New-LaunchOutcome([string]$Outcome, $Failure) {
    return [pscustomobject]@{ Outcome = $Outcome; Failure = $Failure }
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

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Locale) { throw "-Locale est requis (ex. ja_JP)." }

    if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
    $config = Read-LaunchConfig $ConfigPath
    if (-not $YamlPath) { $YamlPath = $config.productSettingsPath }

    # Le journal est ouvert après tous les dot-sourcings : recharger une lib remettrait son chemin à vide
    Set-LaunchLogPath (Join-Path $PSScriptRoot $LaunchLogFileName)

    $launchLock = Enter-LaunchLock
    if (-not $launchLock) {
        Write-LaunchLogLine 'START' ('refusé — lancement déjà en cours (locale={0} demandée)' -f $Locale) | Out-Null
        $splash = New-SplashWindow -Subtitle (Get-LocaleLabel $Locale (Join-Path $PSScriptRoot 'locales.json'))
        try {
            Update-SplashStatus $splash 'Un lancement est déjà en cours — patientez qu''il se termine'
            Wait-WithAnimation $LaunchRefusedSplashSeconds
        }
        finally { Close-SplashWindow $splash }
        return
    }

    $riotVersion  = Get-RiotClientVersion $config.riotClientPath
    # Deux voix peuvent écarter l'API : la ligne de commande (-NoLocalApi) et la case cochée dans setup.bat.
    # Il suffit d'une seule.
    $tryLocalApi  = (-not $NoLocalApi) -and (Get-LaunchUseLocalApi $config)
    $totalChrono  = [Diagnostics.Stopwatch]::StartNew()

    Write-LaunchLogLine 'START' ('locale={0} companion={1} chemin={2} riot={3}' -f `
        $Locale, $(if ($Companion) { $Companion } else { 'aucun' }), `
        $(if ($tryLocalApi) { 'rapide' } elseif ($NoLocalApi) { 'manuel (-NoLocalApi)' } else { 'manuel (case de setup.bat)' }), `
        $(if ($riotVersion) { $riotVersion } else { 'version inconnue' })) | Out-Null

    $splash = New-SplashWindow -Subtitle (Get-LocaleLabel $Locale (Join-Path $PSScriptRoot 'locales.json'))
    if (Test-LaunchBurst (Join-Path $PSScriptRoot $LaunchLogFileName)) {
        Update-SplashStatus $splash $LaunchBurstWarningMessage
        Wait-WithAnimation $LaunchBurstWarningSeconds
    }

    # « Forcer en démarrage manuel » : le clic, pompé par le tick de l'attente en cours, ne fait que lever un drapeau ;
    # les boucles le lisent à leur tour suivant (ShouldStop) et rendent la main. Rien n'est mémorisé.
    $script:ForceStartRequested = $false
    $shouldStop = { $script:ForceStartRequested }
    Add-SplashAction $splash 'Forcer en démarrage manuel' { $script:ForceStartRequested = $true; Hide-SplashAction $splash | Out-Null } | Out-Null
    # La croix : même mécanique, autre issue — le lanceur s'arrête sans démarrage manuel ni compagnon
    $script:AbortRequested = $false
    $shouldAbort = { $script:AbortRequested }
    Add-SplashCloseButton $splash { $script:AbortRequested = $true; Hide-SplashAction $splash | Out-Null } | Out-Null

    try {
        if ($DryRun) {
            Update-SplashStatus $splash 'Fermeture du client de jeu…'
            Wait-WithAnimation 1
            Update-SplashStatus $splash "Application de la langue $Locale…"
            Set-LeagueLocale -Path $YamlPath -Value $Locale
            Wait-WithAnimation 0.5
        }

        if (-not $DryRun) {
            # Le statut courant est retenu pour que le tick puisse y accoler les secondes écoulées
            $script:CurrentStatus = 'Lancement de League of Legends…'
            $stepChrono = [Diagnostics.Stopwatch]::StartNew()
            $onStatus = { param($Message) $script:CurrentStatus = $Message; $stepChrono.Restart(); Update-SplashStatus $splash $Message }
            $onTick   = {
                if ($totalChrono.Elapsed.TotalSeconds -ge $ForceStartButtonDelaySeconds) { Show-SplashAction $splash | Out-Null }
                Update-SplashStatus $splash (Format-WaitingStatus $script:CurrentStatus $stepChrono)
                Wait-WithAnimation 1
            }

            $launch = Start-LeagueClient -Path $config.riotClientPath -YamlPath $YamlPath -Value $Locale -NoLocalApi:(-not $tryLocalApi) -OnTick $onTick -OnStatus $onStatus -ShouldStop $shouldStop -ShouldAbort $shouldAbort
            Hide-SplashAction $splash | Out-Null
            if ($launch.Outcome -eq 'legacy') { Update-SplashStatus $splash (Get-FallbackStatusMessage $launch.Failure) }
            if ($launch.Outcome -eq 'failed') { Update-SplashStatus $splash 'Riot Client introuvable — relancer setup.bat pour corriger config.json' }

            Write-LaunchLogLine 'END' ('issue={0} durée={1}' -f $launch.Outcome, (Format-LaunchLogDuration $totalChrono)) | Out-Null
            if ($launch.Outcome -eq 'cancelled') {
                Update-SplashStatus $splash 'Lancement interrompu'
                Wait-WithAnimation $LaunchAbortedSplashSeconds
                return
            }
        }
        Wait-WithAnimation 0.5

        $companionApp = Find-LaunchCompanion $config $Companion
        Update-SplashStatus $splash 'Fermeture des autres applis compagnon…'
        if (-not $DryRun) { Stop-OtherCompanionApps $config $Companion }
        Wait-WithAnimation 0.5

        if ($companionApp) {
            Update-SplashStatus $splash "Lancement de $($companionApp.name)…"
            $started = if ($DryRun) { Test-Path $companionApp.path } else { Start-CompanionApp $companionApp }
            if (-not $started) { Update-SplashStatus $splash "$($companionApp.name) introuvable — ignoré (vérifier config.json)" }
            Write-LaunchLogLine 'COMPAN' ('{0} : {1}' -f $companionApp.name, $(if ($started) { 'lancée' } else { 'introuvable, ignorée' })) | Out-Null
            Wait-WithAnimation 1.5
        } elseif ($Companion) {
            Update-SplashStatus $splash "Appli compagnon « $Companion » absente de config.json — ignorée (relancer setup.bat)"
            Wait-WithAnimation 1.5
        } else {
            Wait-WithAnimation 1
        }
    }
    finally {
        Close-SplashWindow $splash
        Exit-LaunchLock $launchLock
    }
}
