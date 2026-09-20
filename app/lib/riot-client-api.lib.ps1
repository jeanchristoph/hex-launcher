<#
.SYNOPSIS
    API locale du Riot Client : lockfile, requêtes HTTPS sur 127.0.0.1, lancement et fermeture d'un produit.

.DESCRIPTION
    Le Riot Client expose une API HTTP locale sur un port tiré au démarrage, protégée par le lockfile qu'il écrit
    à ce moment (Config\lockfile : « nom:pid:port:mot de passe:protocole »). Lancer un produit par cette API revient
    à cliquer sur Play : c'est le seul moyen fiable quand l'auto-lancement de --launch-product est annulé parce que
    la permission game:play est évaluée avant l'authentification RSO (journaux du Riot Client, 2026-09-19).

    Toutes les fonctions se dégradent en douceur — lockfile absent, API muette ou en erreur rendent $null ou $false
    avec un avertissement, jamais un throw : l'appelant garde son repli (ligne de commande, puis bouton Play).

    INVARIANT : le mot de passe du lockfile ne sort jamais dans un message, un avertissement ou une exception —
    ni dans le journal, qui ne reçoit que la méthode, le chemin et le code. Même règle pour l'identifiant de
    session d'un produit, qui est le jeton de son client de jeu : jamais dans le journal.

    Suppose lib\launch-log.lib.ps1 déjà dot-sourcé par l'appelant.
#>

# ---------------------------------------------------------------- Config

$RiotClientLockfilePath = Join-Path $env:LOCALAPPDATA 'Riot Games\Riot Client\Config\lockfile'

# Champs du lockfile, dans l'ordre : nom, pid, port, mot de passe, protocole
$LockfileFieldCount = 5

# Chemins de l'API locale, relevés sur swagger/v3/openapi.json du Riot Client — jamais supposés
$RiotClientProductLaunchPath = '/product-launcher/v1/products/{0}/patchlines/{1}'
$RiotClientProductLocalePath = '/riotclient/product-locales/products/{0}/patchlines/{1}'
$RiotClientProductSessionsPath = '/product-session/v1/sessions'
$RiotClientProductSessionPath = '/product-session/v1/sessions/{0}'

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

function New-RiotClientResult([bool]$Success, [int]$StatusCode, [string]$WaitReason = '') {
    return [pscustomobject]@{ Success = $Success; StatusCode = $StatusCode; WaitReason = $WaitReason }
}

# Un 424 couvre deux attentes très différentes, que seul le corps distingue : 'updating' quand Riot patche le
# jeu (« Product 'league_of_legends' patchline 'live' not up to date », des minutes à des heures selon la
# connexion — relevé du 2026-09-20 17:14), 'releasing' sinon (session précédente à libérer, 3 s à 1 min).
# Vide pour tout autre code. Le corps est lu ici et oublié : jamais journalisé, jamais rendu.
$RiotClientWaitReasonUpdating  = 'updating'
$RiotClientWaitReasonReleasing = 'releasing'

function Get-RiotClientWaitReason([int]$StatusCode, [string]$Text) {
    if ($StatusCode -ne 424) { return '' }
    if ($Text -match 'not up to date') { return $RiotClientWaitReasonUpdating }
    return $RiotClientWaitReasonReleasing
}

# Seul point de contact avec WinHTTP : statut et corps de la réponse, lève si la connexion n'aboutit pas.
# Le lanceur ne lit jamais le corps ; les sondes de développement, si — en masquant le mot de passe du lockfile,
# que Riot renvoie dans les arguments de ses sessions (--remoting-auth-token).
function Invoke-WinHttpRequest([string]$Method, [string]$Uri, [string]$Authorization, [string]$Body, [int]$TimeoutSeconds) {
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
        return [pscustomobject]@{ Status = [int]$request.Status; Text = [string]$request.ResponseText }
    } finally {
        # Une requête par tentative, et la boucle en fait des dizaines : l'objet COM est rendu tout de suite
        if ($request) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($request) }
    }
}

# -LoggedPath : ce que le journal montre à la place du chemin, quand celui-ci porte un secret (identifiant de
# session d'un produit : c'est aussi le jeton d'authentification de son client de jeu)
function Invoke-RiotClientRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Lockfile,
        [string]$Body,
        [int]$TimeoutSeconds = 5,
        [string]$LoggedPath = $Path
    )

    $uri = 'https://127.0.0.1:{0}{1}' -f $Lockfile.Port, $Path
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WinHttpRequest $Method $uri (Get-RiotClientAuthorization $Lockfile) $Body $TimeoutSeconds
        $result = New-RiotClientResult (Test-HttpSuccessStatus $response.Status) $response.Status (Get-RiotClientWaitReason $response.Status $response.Text)
    } catch {
        $result = New-RiotClientResult $false 0
    }

    Write-LaunchLogLine 'API' ('{0} {1} -> {2} en {3}' -f $Method, $LoggedPath, $result.StatusCode, (Format-LaunchLogDuration $chrono)) | Out-Null
    return $result
}

# Seule lecture d'un corps de réponse dans le lanceur : rend { Success; StatusCode; Text }. Le texte ne va jamais
# au journal — les sessions d'un produit portent son jeton et le mot de passe du lockfile en clair
function Read-RiotClientResource {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Lockfile,
        [int]$TimeoutSeconds = 5
    )

    $uri = 'https://127.0.0.1:{0}{1}' -f $Lockfile.Port, $Path
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WinHttpRequest 'GET' $uri (Get-RiotClientAuthorization $Lockfile) '' $TimeoutSeconds
        $result = [pscustomobject]@{ Success = (Test-HttpSuccessStatus $response.Status); StatusCode = $response.Status; Text = $response.Text }
    } catch {
        $result = [pscustomobject]@{ Success = $false; StatusCode = 0; Text = '' }
    }

    Write-LaunchLogLine 'API' ('GET {0} -> {1} en {2}' -f $Path, $result.StatusCode, (Format-LaunchLogDuration $chrono)) | Out-Null
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

# ---------------------------------------------------------------- Fermeture d'un produit

# La session d'un produit en marche, telle que le Riot Client la décrit : { Id; Body }, Body étant l'objet JSON
# à lui renvoyer tel quel. $null si l'API ne répond pas, si le produit n'a pas de session ou si la réponse est
# illisible. L'identifiant est aussi le jeton d'authentification du client de jeu : jamais journalisé.
function Find-RiotProductSession {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)]$Lockfile
    )

    $sessions = Read-RiotClientResource -Path $RiotClientProductSessionsPath -Lockfile $Lockfile
    if (-not $sessions.Success) { return $null }
    try {
        $catalog = $sessions.Text | ConvertFrom-Json
    } catch {
        return $null
    }
    $entry = $catalog.PSObject.Properties | Where-Object { $_.Value.productId -eq $ProductId } | Select-Object -First 1
    if (-not $entry) { return $null }
    return [pscustomobject]@{ Id = $entry.Name; Body = ($entry.Value | ConvertTo-Json -Depth 10 -Compress) }
}

# DELETE sur la session, l'objet de la session en corps : sans lui, le Riot Client répond 400 « A value for
# 'session' is required » et ne fait rien (relevé du 2026-09-20). Réservé aux lanceurs de produit d'après le
# swagger — ce que nous sommes. Mesuré : 204 immédiat, client de jeu parti en 0,5 s, et le Riot Client quitte
# à son tour dans la seconde au lieu de rester replié — l'appelant le redémarre s'il en a encore besoin.
function Remove-RiotProductSession {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Lockfile
    )

    return Invoke-RiotClientRequest -Method DELETE -Path ($RiotClientProductSessionPath -f $Session.Id) -Lockfile $Lockfile `
        -Body $Session.Body -LoggedPath ($RiotClientProductSessionPath -f '<session>')
}

# Ferme un produit comme le Riot Client le ferait lui-même, au lieu de tuer son process pendant que Vanguard y
# est attaché (VAN 216 après des kills rapprochés, 2026-09-20). Vrai quand la fermeture est acceptée ; faux
# sinon — l'appelant garde le kill en dernier recours.
function Stop-RiotProduct {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)]$Lockfile
    )

    $session = Find-RiotProductSession -ProductId $ProductId -Lockfile $Lockfile
    if (-not $session) { return $false }
    return (Remove-RiotProductSession -Session $session -Lockfile $Lockfile).Success
}

# ---------------------------------------------------------------- Attente d'une opération

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
#
# -OnWait : appelé avec le motif d'attente ('updating', 'releasing') quand Riot répond 424 et que le motif change —
# une fois par changement, jamais à chaque tour : l'appelant s'en sert pour dire au joueur pourquoi ça dure.
#
# -SuccessProbe : sonde évaluée avant chaque tentative ; vraie → l'opération est acquise (Kind 'probe'), quel que
# soit le dernier code. Mesuré le 2026-09-20 : une demande de lancement peut expirer côté client (code 0 après 7 s)
# alors que Riot l'a exécutée — les tentatives suivantes répondent 423 « un client de jeu tourne » jusqu'au bout du
# budget, et c'est le nôtre. Seule une preuve extérieure (le client de jeu présent) lève l'ambiguïté.
function Wait-RiotClientOperation {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][string]$FailureMessage,
        [string]$LockfilePath = $RiotClientLockfilePath,
        [int]$TimeoutSeconds = 30,
        [scriptblock]$OnTick,
        [scriptblock]$ShouldStop,
        [scriptblock]$SuccessProbe,
        [scriptblock]$OnWait
    )

    $chrono = [Diagnostics.Stopwatch]::StartNew()
    $lastStatus = 0
    $lastWaitReason = ''
    while (-not (Test-WaitBudgetExhausted $chrono $TimeoutSeconds)) {
        if (Test-StopRequested $ShouldStop) { return New-RiotClientOperationResult $false 'cancelled' $lastStatus }
        if (Test-SuccessProbed $SuccessProbe) { return New-RiotClientOperationResult $true 'probe' $lastStatus }
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
            if ($OnWait -and $result.WaitReason -and $result.WaitReason -ne $lastWaitReason) {
                $lastWaitReason = $result.WaitReason
                & $OnWait $result.WaitReason
            }
        }
        if (Test-WaitBudgetExhausted $chrono $TimeoutSeconds) { break }
        if ($OnTick) { & $OnTick } else { Start-Sleep -Seconds 1 }
    }

    # Dernière chance : la preuve a pu arriver pendant la tentative qui a consommé le budget
    if (Test-SuccessProbed $SuccessProbe) { return New-RiotClientOperationResult $true 'probe' $lastStatus }
    Write-Warning ('{0} : rien accepté en {1} s.' -f $FailureMessage, $TimeoutSeconds)
    return New-RiotClientOperationResult $false 'timeout' $lastStatus
}

# -TimeoutSeconds 0 : aucune limite — la boucle ne rend la main que sur succès, refus définitif ou demande d'arrêt.
# Un patch du jeu sur une connexion lente peut durer des heures ; c'est le bouton du splash qui décide, pas un compteur
$NoTimeLimitSeconds = 0

function Test-WaitBudgetExhausted($Chrono, [int]$TimeoutSeconds) {
    if ($TimeoutSeconds -eq $NoTimeLimitSeconds) { return $false }
    return $Chrono.Elapsed.TotalSeconds -ge $TimeoutSeconds
}

function Test-StopRequested([scriptblock]$ShouldStop) {
    if (-not $ShouldStop) { return $false }
    return [bool](& $ShouldStop)
}

function Test-SuccessProbed([scriptblock]$SuccessProbe) {
    if (-not $SuccessProbe) { return $false }
    return [bool](& $SuccessProbe)
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

# -SuccessProbe : l'appelant sait reconnaître le produit lancé (son client de jeu en marche) — la lib, elle, ne
# connaît que des codes HTTP
function Wait-RiotProductLaunch {
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$PatchlineId,
        [string]$LockfilePath = $RiotClientLockfilePath,
        [int]$TimeoutSeconds = 30,
        [scriptblock]$OnTick,
        [scriptblock]$ShouldStop,
        [scriptblock]$SuccessProbe,
        [scriptblock]$OnWait
    )

    $message = 'Riot Client : lancement de {0} refusé par l''API locale' -f $ProductId
    return Wait-RiotClientOperation -Operation { param($Lockfile) Start-RiotProduct -ProductId $ProductId -PatchlineId $PatchlineId -Lockfile $Lockfile } `
        -FailureMessage $message -LockfilePath $LockfilePath -TimeoutSeconds $TimeoutSeconds -OnTick $OnTick -ShouldStop $ShouldStop -SuccessProbe $SuccessProbe -OnWait $OnWait
}
