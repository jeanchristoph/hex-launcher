<#
.SYNOPSIS
    Vérification des mises à jour : dernière release GitHub, comparaison avec app\version.txt, version refusée.

.DESCRIPTION
    Chargé par dot-sourcing :
        . (Join-Path $PSScriptRoot 'lib\update.lib.ps1')

    Une seule requête, GET api.github.com/repos/<dépôt>/releases/latest, sans aucune donnée envoyée hormis
    l'en-tête User-Agent exigé par GitHub. Elle part sans attendre (Start-LatestReleaseRequest) et sa réponse est
    relevée plus tard (Receive-LatestRelease) : le lanceur avance pendant ce temps.

    INVARIANT : la vérification ne fait jamais échouer ni ne retarde de plus de $UpdateCheckTimeoutMs un lancement.
    Pas de réseau, GitHub lent, réponse illisible → aucune mise à jour proposée, rien d'affiché.

    update-state.json (dossier des données) : { "skippedVersion": "0.4.0" } — la version pour laquelle
    l'utilisateur a coché « Ne plus me demander jusqu'à la prochaine version ». Une version plus récente est
    proposée à nouveau.
#>

$UpdateRepository      = 'jeanchristoph/hex-launcher'
$UpdateLatestApiUrl    = "https://api.github.com/repos/$UpdateRepository/releases/latest"
$UpdateCheckTimeoutMs  = 2000
$UpdateStateFileName   = 'update-state.json'
$UpdateUserAgent       = 'hex-launcher'

# ---------------------------------------------------------------- Versions

function Get-InstalledVersion([string]$AppRoot) {
    return (Get-Content -Path (Join-Path $AppRoot 'version.txt') -Raw).Trim()
}

# 'v0.4.0' → '0.4.0' ; tag qui n'est pas une version x.y.z → ''
function ConvertTo-ReleaseVersion([string]$Tag) {
    $version = ([string]$Tag).Trim().TrimStart('v', 'V')
    if ($version -match '^\d+\.\d+\.\d+$') { return $version }
    return ''
}

function Test-NewerVersion([string]$Candidate, [string]$Current) {
    try { return ([version]$Candidate) -gt ([version]$Current) }
    catch { return $false }
}

# ---------------------------------------------------------------- Réponse de l'API GitHub

# Pièce jointe : nom, URL de téléchargement et empreinte SHA-256 publiée par GitHub (champ digest « sha256:… »)
function ConvertTo-ReleaseAsset($Asset) {
    $digest = [string]$Asset.digest
    return [pscustomobject]@{
        Name   = [string]$Asset.name
        Url    = [string]$Asset.browser_download_url
        Sha256 = $(if ($digest -match '^sha256:([0-9a-fA-F]{64})$') { $Matches[1].ToLowerInvariant() } else { '' })
    }
}

# Release utile au lanceur ; $null si son tag n'est pas une version
function ConvertTo-LatestRelease($Json) {
    if (-not $Json) { return $null }
    $version = ConvertTo-ReleaseVersion $Json.tag_name
    if (-not $version) { return $null }
    return [pscustomobject]@{
        Version = $version
        PageUrl = [string]$Json.html_url
        Assets  = @($Json.assets | Where-Object { $_ } | ForEach-Object { ConvertTo-ReleaseAsset $_ })
    }
}

# ---------------------------------------------------------------- Requête

# Démarre une opération asynchrone de WebClient hors de tout contexte de synchronisation. Sinon, dès qu'une fenêtre
# WinForms existe (splash, assistant), WebClient renvoie sa fin par la file de messages de ce thread : un
# Task.Wait qui ne la fait pas tourner attendrait jusqu'au délai, et rien ne serait jamais proposé.
function Start-DetachedWebTask([scriptblock]$Start) {
    $context = [Threading.SynchronizationContext]::Current
    [Threading.SynchronizationContext]::SetSynchronizationContext($null)
    try     { return & $Start }
    finally { [Threading.SynchronizationContext]::SetSynchronizationContext($context) }
}

function New-UpdateWebClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client          = New-Object System.Net.WebClient
    $client.Encoding = [Text.Encoding]::UTF8
    $client.Headers['User-Agent'] = $UpdateUserAgent
    return $client
}

# Requête partie sans attendre ; $null si elle n'a même pas pu partir
function Start-LatestReleaseRequest {
    try {
        $client = New-UpdateWebClient
        $client.Headers['Accept'] = 'application/vnd.github+json'
        $task = Start-DetachedWebTask { $client.DownloadStringTaskAsync($UpdateLatestApiUrl) }
        return @{ Client = $client; Task = $task; Chrono = [Diagnostics.Stopwatch]::StartNew() }
    } catch {
        return $null
    }
}

# Réponse arrivée dans le temps imparti, compté depuis le départ de la requête ; $null sinon, jamais d'exception
function Receive-LatestRelease($Request, [int]$TimeoutMs = $UpdateCheckTimeoutMs) {
    if (-not $Request) { return $null }
    $remaining = [int][math]::Max(0, $TimeoutMs - $Request.Chrono.ElapsedMilliseconds)
    try {
        if (-not $Request.Task.Wait($remaining)) { $Request.Client.CancelAsync(); return $null }
        return ConvertTo-LatestRelease ($Request.Task.Result | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------- Version refusée

function Read-SkippedVersion([string]$StatePath) {
    if (-not (Test-Path -LiteralPath $StatePath)) { return '' }
    try { return [string](Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json).skippedVersion }
    catch { return '' }
}

function Save-SkippedVersion([string]$StatePath, [string]$Version) {
    $json = [pscustomobject]@{ skippedVersion = $Version } | ConvertTo-Json
    [IO.File]::WriteAllText($StatePath, $json + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- Décision

# Proposée : plus récente que la version installée et différente de la version refusée
function Test-UpdateOffered($Release, [string]$InstalledVersion, [string]$SkippedVersion) {
    if (-not $Release) { return $false }
    if (-not (Test-NewerVersion $Release.Version $InstalledVersion)) { return $false }
    return $Release.Version -ne $SkippedVersion
}

# $Check : @{ Request ; InstalledVersion ; StatePath } — la release à proposer, ou $null
function Get-OfferedUpdate([hashtable]$Check) {
    $release = Receive-LatestRelease $Check.Request
    if (-not (Test-UpdateOffered $release $Check.InstalledVersion (Read-SkippedVersion $Check.StatePath))) { return $null }
    return $release
}
