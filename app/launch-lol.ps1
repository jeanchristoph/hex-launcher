<#
.SYNOPSIS
    Lance League of Legends dans la langue demandée, avec un splash animé.

.DESCRIPTION
    Chemin rapide : ferme le seul client de jeu, pose la langue par l'API locale du Riot Client (qui écrit alors
    le yaml lui-même) et lui demande le lancement — l'équivalent du bouton Play, sans fermer le Riot Client.
    Chemin historique, conservé en repli : ferme tous les process Riot, réécrit settings.locale dans
    league_of_legends.live.product_settings.yaml, relance avec --launch-product. Il sert dès que l'API locale ne
    répond pas, refuse, ou que le client de jeu n'apparaît pas — et sur demande avec -NoLocalApi.
    Chaque étape est tracée dans launch.log, une ligne horodatée par événement, appels d'API compris.
    Le résultat est retenu dans launch-state.json : après deux échecs consécutifs, le chemin rapide n'est plus
    tenté et l'attente disparaît, jusqu'à ce que le Riot Client change de version — une mise à jour pouvant
    aussi bien réparer son API que la casser.
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
. (Join-Path $PSScriptRoot 'lib\launch-state.lib.ps1')
. (Join-Path $PSScriptRoot 'lib\riot-window.lib.ps1')

# Client de jeu seul : ce que le chemin rapide ferme, en laissant la session du Riot Client vivante
$GameClientProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient')

# Tout Riot : ce que ferme le chemin historique, faute de pouvoir poser la langue autrement que dans le yaml
$RiotProcessNames = @('LeagueClientUxRender', 'LeagueClientUx', 'LeagueClient', 'RiotClientUxRender', 'RiotClientUx', 'RiotClientServices')

# Produit Riot lancé par ce lanceur, tel que le Riot Client le nomme
$LeagueProductId   = 'league_of_legends'
$LeaguePatchlineId = 'live'

# Budget total du chemin rapide : pose de la langue ET acceptation du lancement, dans une seule enveloppe.
# Un seul budget plutôt qu'un par étape — une machine lente peut consommer l'essentiel sur l'une ou sur l'autre
# sans que le total dérive. Les mesures de développement (3,4 s à chaud, 8,2 s à froid) viennent d'un poste
# rapide : elles ne servent pas de seuil, d'où la marge.
$LocalApiBudgetSeconds = 60

# Un lancement accepté ne prouve rien : le client de jeu doit apparaître. Large, car c'est l'étape qui souffre
# le plus d'un disque lent ou d'un Vanguard qui démarre.
$GameClientStartTimeoutSeconds = 30

# ---------------------------------------------------------------- Config

# Libellé affiché dans le splash, depuis locales.json ; repli sur le code si absent
function Get-LocaleLabel([string]$Code, [string]$CatalogPath) {
    if (-not (Test-Path $CatalogPath)) { return $Code }
    $entry = Read-JsonCatalog $CatalogPath | Where-Object { $_.code -eq $Code }
    if ($entry) { return $entry.label }
    return $Code
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

# Un endpoint déprécié chez Riot continue de répondre en ayant perdu son effet (/riotclient/new-args rend 204
# et ne lance plus rien depuis 2022) : seule l'apparition du client de jeu prouve que le lancement a eu lieu.
function Wait-GameClientStart([int]$TimeoutSeconds, [scriptblock]$OnTick) {
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    while ($chrono.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-GameClientRunning) { return $true }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }
    return (Test-GameClientRunning)
}

function Test-RiotClientRunning {
    return @(Get-Process -Name 'RiotClientServices' -ErrorAction SilentlyContinue).Count -gt 0
}

# Le Riot Client doit rester debout tant que le chemin rapide n'a pas abouti : son API est notre seul moyen d'agir
function Assert-RiotClientRunning([string]$Path) {
    if (Test-RiotClientRunning) { return $true }
    Write-LaunchLogLine 'RIOT' 'Riot Client absent — redémarrage' | Out-Null
    return (Start-RiotClient $Path)
}

# Chemin rapide : la session du Riot Client est réutilisée si elle existe, démarrée sinon — jamais fermée.
# La langue lui est posée (il écrit alors le yaml lui-même), puis le jeu est lancé comme par le bouton Play.
# Temps qu'il reste au chemin rapide, jamais moins d'une seconde pour laisser une dernière tentative aboutir
function Get-RemainingBudgetSeconds($Chrono, [int]$BudgetSeconds) {
    return [int][Math]::Max(1, $BudgetSeconds - $Chrono.Elapsed.TotalSeconds)
}

# Rend { Success; Failure } — Failure porte la cause, que la mémoire utilise pour décider combien de fois
# encore le chemin rapide mérite d'être tenté
function Start-LeagueClientByLocalApi([string]$Path, [string]$Value, [scriptblock]$OnTick, [scriptblock]$OnStatus) {
    if (-not (Test-RiotClientRunning)) { Write-LaunchStatus $OnStatus 'Démarrage du Riot Client…' }
    if (-not (Assert-RiotClientRunning $Path)) { return New-LocalApiAttempt $false (New-LocalApiFailure 'route' 0 'riot-client') }

    # Garde préventive : si le Riot Client venait à disparaître en cours de route, la boucle attendrait un
    # lockfile qui ne reviendrait jamais. Mesuré le 2026-09-20, il survit à la fermeture du client de jeu, quel
    # que soit son mode de démarrage — mais rien ne garantit qu'un patch de Riot ne changera pas cela.
    # Noms distincts, et pas de GetNewClosure : ce bloc est invoqué depuis Wait-RiotClientOperation, qui a son
    # propre $OnTick — s'y référer ici le ferait se rappeler lui-même jusqu'à saturer la pile. GetNewClosure
    # résoudrait la capture mais attacherait le bloc à un module dynamique, aveugle aux fonctions du script.
    $guardRiotPath = $Path
    $guardUserTick = $OnTick
    $guardedTick = { Assert-RiotClientRunning $guardRiotPath | Out-Null; if ($guardUserTick) { & $guardUserTick } else { Start-Sleep -Seconds 1 } }

    $chrono = [Diagnostics.Stopwatch]::StartNew()

    Write-LaunchStatus $OnStatus ('Application de la langue {0}…' -f $Value)
    $localeSet = Wait-RiotProductLocale -ProductId $LeagueProductId -PatchlineId $LeaguePatchlineId -Locale $Value `
        -TimeoutSeconds (Get-RemainingBudgetSeconds $chrono $LocalApiBudgetSeconds) -OnTick $guardedTick
    if (-not $localeSet.Success) { return New-LocalApiAttempt $false (New-LocalApiFailure $localeSet.Kind $localeSet.StatusCode 'locale') }

    Write-LaunchStatus $OnStatus 'Demande de lancement au Riot Client…'
    $launched = Wait-RiotProductLaunch -ProductId $LeagueProductId -PatchlineId $LeaguePatchlineId `
        -TimeoutSeconds (Get-RemainingBudgetSeconds $chrono $LocalApiBudgetSeconds) -OnTick $guardedTick
    if (-not $launched.Success) { return New-LocalApiAttempt $false (New-LocalApiFailure $launched.Kind $launched.StatusCode 'launch') }

    Write-LaunchStatus $OnStatus 'Le jeu se prépare…'
    $gameChrono = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Wait-GameClientStart $GameClientStartTimeoutSeconds $OnTick)) {
        Write-LaunchLogLine 'GAME' ('aucun client de jeu après {0} — lancement accepté sans effet' -f (Format-LaunchLogDuration $gameChrono)) | Out-Null
        return New-LocalApiAttempt $false (New-LocalApiFailure 'silent' $launched.StatusCode 'game-client')
    }

    Write-LaunchLogLine 'GAME' ('client de jeu détecté en {0}' -f (Format-LaunchLogDuration $gameChrono)) | Out-Null

    # Le jeu est lancé : la fenêtre du Riot Client n'a plus rien à montrer. On lui demande de se fermer — avec
    # une partie en cours il se replie sur son icône près de l'horloge au lieu de quitter, rend près de 600 Mo,
    # et son API continue de répondre. Jamais sur le chemin classique, où elle sert encore à cliquer sur Play.
    if (Close-RiotClientWindow) { Write-LaunchLogLine 'RIOT' 'fenêtre du Riot Client fermée (repli sur l''icône)' | Out-Null }

    return New-LocalApiAttempt $true $null
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
# Failure n'est renseigné que si le chemin rapide a échoué : c'est ce que la mémoire retient.
function Start-LeagueClient([string]$Path, [string]$YamlPath, [string]$Value, [switch]$NoLocalApi, [scriptblock]$OnTick, [scriptblock]$OnStatus) {
    $failure = $null

    if (-not $NoLocalApi) {
        Write-LaunchStatus $OnStatus 'Fermeture du client de jeu…'
        Stop-GameClientProcesses
        $attempt = Start-LeagueClientByLocalApi $Path $Value $OnTick $OnStatus
        if ($attempt.Success) { return New-LaunchOutcome 'api' $null }

        # Le client de jeu a pu apparaître juste après l'échéance : le chemin historique le tuerait pour le
        # relancer, et l'utilisateur verrait le jeu s'ouvrir, disparaître, puis s'ouvrir de nouveau
        if (Test-GameClientRunning) { return New-LaunchOutcome 'api' $null }

        $failure = $attempt.Failure
        Write-LaunchLogLine 'LEGACY' ('reprise du lancement classique — cause={0} code={1} étape={2}' -f $failure.Kind, $failure.StatusCode, $failure.Stage) | Out-Null
    }

    Write-LaunchStatus $OnStatus 'Lancement classique : fermeture de Riot puis redémarrage…'
    if (Start-LeagueClientByCommandLine $Path $YamlPath $Value) { return New-LaunchOutcome 'legacy' $failure }
    return New-LaunchOutcome 'failed' $failure
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

    $statePath    = Join-Path $PSScriptRoot $LaunchStateFileName
    $launchState  = Read-LaunchState $statePath
    $riotVersion  = Get-RiotClientVersion $config.riotClientPath
    # Trois voix peuvent écarter l'API : le raccourci (-NoLocalApi), le choix fait dans setup.bat, et la
    # mémoire des échecs. Il suffit d'une seule.
    $tryLocalApi  = (-not $NoLocalApi) -and (Get-LaunchUseLocalApi $config) -and (Test-LocalApiWorthTrying $launchState $riotVersion)
    $totalChrono  = [Diagnostics.Stopwatch]::StartNew()

    Write-LaunchLogLine 'START' ('locale={0} companion={1} noLocalApi={2} mémoire={3} riot={4}' -f `
        $Locale, $(if ($Companion) { $Companion } else { 'aucun' }), (-not (Get-LaunchUseLocalApi $config) -or $NoLocalApi), `
        $(if ($tryLocalApi) { 'tenter' } else { 'chemin classique' }), `
        $(if ($riotVersion) { $riotVersion } else { 'version inconnue' })) | Out-Null

    $splash = New-SplashWindow -Subtitle (Get-LocaleLabel $Locale (Join-Path $PSScriptRoot 'locales.json'))

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
            $onTick   = { Update-SplashStatus $splash (Format-WaitingStatus $script:CurrentStatus $stepChrono); Wait-WithAnimation 1 }

            $launch = Start-LeagueClient -Path $config.riotClientPath -YamlPath $YamlPath -Value $Locale -NoLocalApi:(-not $tryLocalApi) -OnTick $onTick -OnStatus $onStatus
            if ($launch.Outcome -eq 'legacy') { Update-SplashStatus $splash 'Riot Client : reprise par le lancement classique…' }
            if ($launch.Outcome -eq 'failed') { Update-SplashStatus $splash 'Riot Client introuvable — relancer setup.bat pour corriger config.json' }

            # On n'apprend que de ce qu'on a tenté : un lancement classé d'office ne dit rien de l'API
            if ($tryLocalApi) {
                $memory = Update-LocalApiOutcome $launchState ($launch.Outcome -eq 'api') $riotVersion $launch.Failure
                Write-LaunchState $memory $statePath | Out-Null
                Write-LaunchLogLine 'END' ('issue={0} durée={1} mémoire=échecs:{2}{3}' -f `
                    $launch.Outcome, (Format-LaunchLogDuration $totalChrono), $memory.localApi.failureCount, `
                    $(if ($memory.localApi.failureKind) { ' cause:' + $memory.localApi.failureKind } else { '' })) | Out-Null
            } else {
                Write-LaunchLogLine 'END' ('issue={0} durée={1} mémoire=inchangée (chemin rapide non tenté)' -f $launch.Outcome, (Format-LaunchLogDuration $totalChrono)) | Out-Null
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
    }
}
