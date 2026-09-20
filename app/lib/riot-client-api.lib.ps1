<#
.SYNOPSIS
    API locale du Riot Client : lockfile, requêtes HTTPS sur 127.0.0.1, lancement d'un produit.

.DESCRIPTION
    Le Riot Client expose une API HTTP locale sur un port tiré au démarrage, protégée par le lockfile qu'il écrit
    à ce moment (Config\lockfile : « nom:pid:port:mot de passe:protocole »). Lancer un produit par cette API revient
    à cliquer sur Play : c'est le seul moyen fiable quand l'auto-lancement de --launch-product est annulé parce que
    la permission game:play est évaluée avant l'authentification RSO (journaux du Riot Client, 2026-09-19).

    Toutes les fonctions se dégradent en douceur — lockfile absent, API muette ou en erreur rendent $null ou $false
    avec un avertissement, jamais un throw : l'appelant garde son repli (ligne de commande, puis bouton Play).

    INVARIANT : le mot de passe du lockfile ne sort jamais dans un message, un avertissement ou une exception —
    ni dans le journal, qui ne reçoit que la méthode, le chemin et le code.

    Suppose lib\launch-log.lib.ps1 déjà dot-sourcé par l'appelant.
#>

# ---------------------------------------------------------------- Config

$RiotClientLockfilePath = Join-Path $env:LOCALAPPDATA 'Riot Games\Riot Client\Config\lockfile'

# Champs du lockfile, dans l'ordre : nom, pid, port, mot de passe, protocole
$LockfileFieldCount = 5

# Chemins de l'API locale, relevés sur swagger/v3/openapi.json du Riot Client — jamais supposés
$RiotClientProductLaunchPath = '/product-launcher/v1/products/{0}/patchlines/{1}'
$RiotClientProductLocalePath = '/riotclient/product-locales/products/{0}/patchlines/{1}'

# Route de lecture sans effet, présente dès que l'API du Riot Client est chargée : sert à savoir si elle répond
$RiotClientReadinessPath = '/riotclient/region-locale'

# ---------------------------------------------------------------- Lockfile

# Le Riot Client garde le lockfile ouvert : lecture en partage, sinon l'accès est refusé
function Read-LockedFileText([string]$Path) {
    $stream = $null
    $reader = $null
    try {
        # La résolution elle-même peut échouer (chemin vide quand %LOCALAPPDATA% n'est pas défini) : elle reste
        # dans le try, pour que la fonction rende $null en silence comme son contrat l'annonce
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $stream = New-Object IO.FileStream($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = New-Object IO.StreamReader($stream)
        return $reader.ReadToEnd()
    } catch {
        return $null
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Read-RiotClientLockfile([string]$Path = $RiotClientLockfilePath, [switch]$Quiet) {
    $content = Read-LockedFileText $Path
    if (-not $content) {
        if (-not $Quiet) { Write-Warning 'Riot Client : lockfile illisible ou absent — API locale indisponible.' }
        return $null
    }

    $fields = @($content.Trim() -split ':')
    if ($fields.Count -ne $LockfileFieldCount) {
        if (-not $Quiet) { Write-Warning 'Riot Client : lockfile au format inattendu — API locale ignorée.' }
        return $null
    }

    $port = 0
    if (-not [int]::TryParse($fields[2], [ref]$port)) {
        if (-not $Quiet) { Write-Warning 'Riot Client : port du lockfile illisible — API locale ignorée.' }
        return $null
    }

    return [pscustomobject]@{
        Name      = $fields[0]
        ProcessId = $fields[1]
        Port      = $port
        Password  = $fields[3]
        Protocol  = $fields[4]
    }
}

# ---------------------------------------------------------------- Transport

# WinHTTP, et non Invoke-WebRequest : après la requête, le Riot Client demande une renégociation TLS que
# HttpWebRequest refuse par conception (« la connexion sous-jacente a été fermée » sur chaque appel, toutes
# versions de TLS confondues — relevé du 2026-09-20). WinHTTP la gère, et son option SslErrorIgnoreFlags
# accepte le certificat auto-signé de la boucle locale sans toucher au réglage global de .NET.
$WinHttpSslErrorIgnoreOption = 4
$WinHttpIgnoreAllCertificateErrors = 13056

# En-tête Basic « riot:<mot de passe du lockfile> » — jamais affiché ni journalisé
function Get-RiotClientAuthorization($Lockfile) {
    return 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('riot:{0}' -f $Lockfile.Password)))
}

function New-RiotClientResult([bool]$Success, [int]$StatusCode) {
    return [pscustomobject]@{ Success = $Success; StatusCode = $StatusCode }
}

# Seul point de contact avec WinHTTP : rend le code HTTP, lève si la connexion n'aboutit pas
function Send-WinHttpRequest([string]$Method, [string]$Uri, [string]$Authorization, [string]$Body, [int]$TimeoutSeconds) {
    $milliseconds = $TimeoutSeconds * 1000
    $request = $null
    try {
        $request = New-Object -ComObject WinHttp.WinHttpRequest.5.1
        $request.SetTimeouts($milliseconds, $milliseconds, $milliseconds, $milliseconds)
        $request.Open($Method, $Uri, $false)
        $request.Option($WinHttpSslErrorIgnoreOption) = $WinHttpIgnoreAllCertificateErrors
        $request.SetRequestHeader('Authorization', $Authorization)
        if ($Body) {
            $request.SetRequestHeader('Content-Type', 'application/json')
            $request.Send($Body)
        } else {
            $request.Send()
        }
        return [int]$request.Status
    } finally {
        # Une requête par tentative, et la boucle en fait des dizaines : l'objet COM est rendu tout de suite
        if ($request) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($request) }
    }
}

function Invoke-RiotClientRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Lockfile,
        [string]$Body,
        [int]$TimeoutSeconds = 5
    )

    $uri = 'https://127.0.0.1:{0}{1}' -f $Lockfile.Port, $Path
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $status = Send-WinHttpRequest $Method $uri (Get-RiotClientAuthorization $Lockfile) $Body $TimeoutSeconds
        $result = New-RiotClientResult (Test-HttpSuccessStatus $status) $status
    } catch {
        $result = New-RiotClientResult $false 0
    }

    Write-LaunchLogLine 'API' ('{0} {1} -> {2} en {3}' -f $Method, $Path, $result.StatusCode, (Format-LaunchLogDuration $chrono)) | Out-Null
    return $result
}

# L'API est-elle chargée ? Vrai sur un 200 à une route de lecture ; un 404 ici ne dit pas « route disparue » mais
# « pas encore rechargée » — le Riot Client décharge toute son API quand le jeu se termine fenêtre fermée, et la
# recharge en quelques secondes quand on le relance sans argument (mesuré le 2026-09-20)
function Test-RiotClientReady($Lockfile) {
    return (Invoke-RiotClientRequest -Method GET -Path $RiotClientReadinessPath -Lockfile $Lockfile).Success
}

function Test-HttpSuccessStatus([int]$StatusCode) {
    return ($StatusCode -ge 200) -and ($StatusCode -lt 300)
}

# ---------------------------------------------------------------- Lancement d'un produit

# Codes qui signifient « pas encore », et eux seuls (relevés sur le Riot Client 139.0.5, le 2026-09-20) :
#   0   — la connexion n'est pas établie, le serveur local démarre encore
#   409 — conflit : vu une fois (2026-09-20) juste après le réveil d'un Riot Client replié, lancement demandé
#         3 s après le retour de son API ; un conflit décrit un état occupé, pas une route disparue
#   423 — session verrouillée : un client de jeu tourne toujours
#   424 — session en cours de libération : de 3 s si le jeu tournait depuis un moment à près d'une minute s'il
#         venait d'être lancé, le temps que son heartbeat expire
#   464 — session pas prête : authentification RSO en cours
# Tout autre échec — route disparue après une mise à jour de Riot, autorisation refusée — ne s'arrangera pas en
# insistant : on rend la main au repli.
$RiotClientRetryStatusCodes = @(0, 409, 423, 424, 464)

function Test-RiotClientRetryableStatus([int]$StatusCode) {
    return $RiotClientRetryStatusCodes -contains $StatusCode
}

# La langue du jeu se pose par l'API plutôt que dans le yaml : le Riot Client écrit alors le fichier lui-même,
# au lieu de réécrire par-dessus la valeur posée dans son dos (mesure du 2026-09-20 : fr_FR écrit à la main est
# revenu à ja_JP en quelques secondes, Riot Client allumé).
function Set-RiotProductLocale {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$PatchlineId,
        [Parameter(Mandatory)][string]$Locale,
        [Parameter(Mandatory)]$Lockfile
    )

    $path = $RiotClientProductLocalePath -f $ProductId, $PatchlineId
    return Invoke-RiotClientRequest -Method PUT -Path $path -Lockfile $Lockfile -Body ('"{0}"' -f $Locale)
}

function Start-RiotProduct {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$PatchlineId,
        [Parameter(Mandatory)]$Lockfile
    )

    return Invoke-RiotClientRequest -Method POST -Path ($RiotClientProductLaunchPath -f $ProductId, $PatchlineId) -Lockfile $Lockfile
}

# Le lancement est rejoué tant que la session n'est pas prête : aucune sonde ne prédit cet instant
# (relevé du 2026-09-20 à froid : 464 à 3,8 s, 200 à 8,2 s, alors que /riotclient/region-locale répond 200 dès 7 s).
# Rejoue une opération de l'API tant que le Riot Client répond « pas encore » : le lockfile est relu à chaque
# tour, puisqu'il peut n'apparaître qu'après le démarrage du client. L'opération reçoit le lockfile et rend un
# résultat { Success; StatusCode }. Un refus définitif sort immédiatement : insister n'y changerait rien.
#
# Rend { Success; Kind; StatusCode }. Kind distingue ce que l'appelant ne pourrait pas deviner d'un simple faux :
# 'route' quand l'API refuse (la situation ne s'arrangera pas), 'timeout' quand rien n'a été accepté dans le
# budget (une machine lente n'est pas une API cassée), 'cancelled' quand l'appelant a demandé d'arrêter
# (-ShouldStop, vérifié en tête de chaque tour : un clic pendant le tick prend effet avant toute nouvelle requête).
#
# L'écoulement est mesuré par un Stopwatch, jamais par l'heure système : une horloge qui recule (synchronisation
# NTP, changement d'heure) rendrait une échéance calculée sur (Get-Date) inatteignable pendant tout le décalage.
# Le budget est aussi vérifié après l'opération : une requête qui consomme son propre délai ne le fait pas déborder.
function Wait-RiotClientOperation {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][string]$FailureMessage,
        [string]$LockfilePath = $RiotClientLockfilePath,
        [int]$TimeoutSeconds = 30,
        [scriptblock]$OnTick,
        [scriptblock]$ShouldStop
    )

    $chrono = [Diagnostics.Stopwatch]::StartNew()
    $lastStatus = 0
    while ($chrono.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-StopRequested $ShouldStop) { return New-RiotClientOperationResult $false 'cancelled' $lastStatus }
        $lockfile = Read-RiotClientLockfile $LockfilePath -Quiet
        if (-not $lockfile) {
            # Sans cette trace, un budget épuisé sans aucune tentative reste inexplicable après coup
            Write-LaunchLogLine 'WAIT' 'lockfile du Riot Client illisible — rien à tenter ce tour' | Out-Null
        }
        if ($lockfile) {
            $result = & $Operation $lockfile
            $lastStatus = $result.StatusCode
            if ($result.Success) { return New-RiotClientOperationResult $true '' $result.StatusCode }
            if (-not (Test-RiotClientRetryableStatus $result.StatusCode)) {
                Write-Warning ('{0} (code {1}).' -f $FailureMessage, $result.StatusCode)
                return New-RiotClientOperationResult $false 'route' $result.StatusCode
            }
        }
        if ($chrono.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }

    Write-Warning ('{0} : rien accepté en {1} s.' -f $FailureMessage, $TimeoutSeconds)
    return New-RiotClientOperationResult $false 'timeout' $lastStatus
}

function Test-StopRequested([scriptblock]$ShouldStop) {
    if (-not $ShouldStop) { return $false }
    return [bool](& $ShouldStop)
}

function New-RiotClientOperationResult([bool]$Success, [string]$Kind, [int]$StatusCode) {
    return [pscustomobject]@{ Success = $Success; Kind = $Kind; StatusCode = $StatusCode }
}

function Wait-RiotProductLocale {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$PatchlineId,
        [Parameter(Mandatory)][string]$Locale,
        [string]$LockfilePath = $RiotClientLockfilePath,
        [int]$TimeoutSeconds = 30,
        [scriptblock]$OnTick,
        [scriptblock]$ShouldStop
    )

    $message = 'Riot Client : langue {0} refusée par l''API locale' -f $Locale
    return Wait-RiotClientOperation -Operation { param($Lockfile) Set-RiotProductLocale -ProductId $ProductId -PatchlineId $PatchlineId -Locale $Locale -Lockfile $Lockfile } `
        -FailureMessage $message -LockfilePath $LockfilePath -TimeoutSeconds $TimeoutSeconds -OnTick $OnTick -ShouldStop $ShouldStop
}

function Wait-RiotProductLaunch {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$PatchlineId,
        [string]$LockfilePath = $RiotClientLockfilePath,
        [int]$TimeoutSeconds = 30,
        [scriptblock]$OnTick,
        [scriptblock]$ShouldStop
    )

    $message = 'Riot Client : lancement de {0} refusé par l''API locale' -f $ProductId
    return Wait-RiotClientOperation -Operation { param($Lockfile) Start-RiotProduct -ProductId $ProductId -PatchlineId $PatchlineId -Lockfile $Lockfile } `
        -FailureMessage $message -LockfilePath $LockfilePath -TimeoutSeconds $TimeoutSeconds -OnTick $OnTick -ShouldStop $ShouldStop
}
