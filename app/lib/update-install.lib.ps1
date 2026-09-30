<#
.SYNOPSIS
    Installation d'une mise à jour acceptée : téléchargement vérifié par SHA-256, puis installeur silencieux (copie
    installée) ou remplacement des fichiers sur place (copie portable).

.DESCRIPTION
    Chargé par dot-sourcing, après i18n.lib.ps1 et Initialize-Translation :
        . (Join-Path $PSScriptRoot 'lib\update-install.lib.ps1')

    INVARIANT : un fichier dont l'empreinte ne correspond pas au digest publié par GitHub n'est jamais exécuté ni
    décompressé. Pas de digest → pas de vérification possible → pas d'installation.
    INVARIANT : la mise à jour d'une copie portable ne touche jamais data\ ; seuls app\ et les fichiers livrés à la
    racine (setup.bat, README…) sont remplacés.
    Échec à n'importe quelle étape → exception ; l'appelant poursuit avec la version actuelle.
#>

. (Join-Path $PSScriptRoot 'app-data.lib.ps1')
. (Join-Path $PSScriptRoot 'update.lib.ps1')
. (Join-Path $PSScriptRoot 'splash.lib.ps1')

$UpdateDownloadTimeoutSeconds = 180
$UpdateInstallTimeoutSeconds  = 180
$UpdateInstallerArguments     = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCLOSEAPPLICATIONS')
$UpdateStatusSeconds          = 2
$UpdateReadOnlySeconds        = 8

# ---------------------------------------------------------------- Pièce jointe

function Get-UpdateAssetName([string]$Version, [string]$DistributionKind) {
    if ($DistributionKind -eq 'portable') { return "hex-launcher-portable-$Version.zip" }
    return "hex-launcher-setup-$Version.exe"
}

function Find-UpdateAsset($Release, [string]$DistributionKind) {
    $name  = Get-UpdateAssetName $Release.Version $DistributionKind
    $asset = @($Release.Assets | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
    if (-not $asset) { throw "$name absent de la release" }
    return $asset
}

# ---------------------------------------------------------------- Téléchargement

function Test-DownloadIntegrity([string]$Path, [string]$Sha256) {
    if ([string]::IsNullOrWhiteSpace($Sha256)) { return $false }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Sha256.ToUpperInvariant()
}

# Attend une tâche .NET en faisant tourner $Wait (animation du splash) ; lève son exception ou l'expiration
function Wait-UpdateTask([System.Threading.Tasks.Task]$Task, [scriptblock]$Wait, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $Task.IsCompleted) {
        if ((Get-Date) -gt $deadline) { throw "délai de $TimeoutSeconds s dépassé" }
        & $Wait
    }
    if ($Task.IsFaulted) { throw $Task.Exception.InnerException }
}

# Fichier téléchargé dans le dossier temporaire et vérifié ; supprimé et exception s'il est altéré
function Receive-UpdateFile($Asset, [scriptblock]$Wait) {
    $path = Join-Path $env:TEMP $Asset.Name
    $client = New-UpdateWebClient
    try     { Wait-UpdateTask (Start-DetachedWebTask { $client.DownloadFileTaskAsync($Asset.Url, $path) }) $Wait $UpdateDownloadTimeoutSeconds }
    finally { $client.Dispose() }
    if (Test-DownloadIntegrity $path $Asset.Sha256) { return $path }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    throw (Get-Text 'update.tampered')
}

# ---------------------------------------------------------------- Copie installée

function Install-InstallerUpdate([string]$InstallerPath, [scriptblock]$Wait) {
    $process  = Start-Process -FilePath $InstallerPath -ArgumentList $UpdateInstallerArguments -PassThru
    $deadline = (Get-Date).AddSeconds($UpdateInstallTimeoutSeconds)
    while (-not $process.HasExited) {
        if ((Get-Date) -gt $deadline) { throw "installeur : délai de $UpdateInstallTimeoutSeconds s dépassé" }
        & $Wait
    }
    if ($process.ExitCode -ne 0) { throw "installeur : code $($process.ExitCode)" }
}

# ---------------------------------------------------------------- Copie portable

# Sonde d'écriture : la seule écriture de l'outil dans app\ hors mise à jour, aussitôt effacée
function Test-FolderWritable([string]$Folder) {
    $probe = Join-Path $Folder ('.write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

# Dossier de la nouvelle version dans le zip décompressé : son unique sous-dossier (hex-launcher-<version>\)
function Get-ExtractedReleaseRoot([string]$Folder) {
    $children = @(Get-ChildItem -LiteralPath $Folder -Directory)
    if ($children.Count -ne 1) { throw 'archive inattendue' }
    return $children[0].FullName
}

function Get-RelativeFilePaths([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $Folder -Recurse -File | ForEach-Object { $_.FullName.Substring($Folder.Length).TrimStart('\') })
}

# Fichiers de app\ retirés par la nouvelle version : effacés, pour qu'aucun script périmé ne traîne
function Remove-ObsoleteAppFiles([string]$Source, [string]$Root) {
    $kept = Get-RelativeFilePaths (Join-Path $Source 'app')
    foreach ($relative in Get-RelativeFilePaths (Join-Path $Root 'app')) {
        if ($kept -notcontains $relative) { Remove-Item -LiteralPath (Join-Path $Root "app\$relative") -Force }
    }
}

# La nouvelle version par-dessus l'ancienne, fichier par fichier ; data\, absent de l'archive, reste intact
function Copy-ReleaseFiles([string]$Source, [string]$Root) {
    foreach ($relative in Get-RelativeFilePaths $Source) {
        $target = Join-Path $Root $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Source $relative) -Destination $target -Force
    }
}

function Install-PortableUpdate([string]$ZipPath, [string]$Root) {
    $extracted = Join-Path $env:TEMP ('hex-launcher-update-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extracted
        $source = Get-ExtractedReleaseRoot $extracted
        Remove-ObsoleteAppFiles $source $Root
        Copy-ReleaseFiles $source $Root
    } finally {
        Remove-Item -LiteralPath $extracted -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- Orchestration

# Le processus quitte le dossier du code : un répertoire courant à l'intérieur empêcherait de le remplacer
function Exit-CodeFolder {
    Set-Location -LiteralPath $env:TEMP
    [Environment]::CurrentDirectory = $env:TEMP
}

# $Update : @{ Release ; AppRoot ; Wait ; OnStatus } — rend 'installed' ou 'read_only' ; exception sur échec
function Install-Update([hashtable]$Update) {
    $kind = Get-DistributionKind $Update.AppRoot
    if ($kind -eq 'source') { throw 'copie non installée' }
    if ($kind -eq 'portable' -and -not (Test-FolderWritable $Update.AppRoot)) { return 'read_only' }
    $asset = Find-UpdateAsset $Update.Release $kind
    & $Update.OnStatus (Get-Text 'update.downloading' $Update.Release.Version)
    $file = Receive-UpdateFile $asset $Update.Wait
    try {
        & $Update.OnStatus (Get-Text 'update.installing' $Update.Release.Version)
        Exit-CodeFolder
        if ($kind -eq 'portable') { Install-PortableUpdate $file (Split-Path $Update.AppRoot -Parent) }
        else { Install-InstallerUpdate $file $Update.Wait }
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    return 'installed'
}

# Mise à jour menée dans le splash : rend 'installed', 'read_only' ou 'failed' — jamais d'exception, le lancement
# se poursuit toujours. $Update : @{ Release ; AppRoot ; Splash ; OnLog ; IsGameLaunchNext } — IsGameLaunchNext à
# faux (assistant) : pas d'annonce « lancement du jeu » une fois installée
function Invoke-SplashUpdate([hashtable]$Update) {
    $splash = $Update.Splash
    # Portée dynamique : ces blocs, appelés depuis Install-Update, voient encore $splash
    $update = $Update + @{ Wait = { Wait-WithAnimation 0.2 }; OnStatus = { param([string]$Text) Update-SplashStatus $splash $Text } }
    try {
        $outcome = Install-Update $update
    } catch {
        & $Update.OnLog "échec : $($_.Exception.Message)"
        Update-SplashStatus $splash (Get-Text 'update.failed' $_.Exception.Message)
        Wait-WithAnimation $UpdateStatusSeconds
        return 'failed'
    }
    & $Update.OnLog $outcome
    if ($outcome -eq 'read_only') { Show-UpdateReadOnly $splash $Update.Release }
    elseif ($Update.IsGameLaunchNext -ne $false) { Update-SplashStatus $splash (Get-Text 'update.installed'); Wait-WithAnimation $UpdateStatusSeconds }
    return $outcome
}

# Dossier portable non modifiable : message et bouton vers la page de la release, le temps de le lire
function Show-UpdateReadOnly($Splash, $Release) {
    $pageUrl = $Release.PageUrl
    Update-SplashStatus $Splash (Get-Text 'update.readOnly' $Release.Version)
    Add-SplashAction $Splash (Get-Text 'update.openPage') { Start-Process $pageUrl }.GetNewClosure() | Out-Null
    Show-SplashAction $Splash | Out-Null
    Wait-WithAnimation $UpdateReadOnlySeconds
    Remove-SplashAction $Splash | Out-Null
}
