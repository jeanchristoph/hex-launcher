<#
.SYNOPSIS
    Texte forcé : pose les fichiers texte d'une locale à la place de ceux de la langue des voix, puis les restaure.

.DESCRIPTION
    Chargé par dot-sourcing, après lib\launch-log.lib.ps1, lib\zstd.lib.ps1, lib\riot-cdn.lib.ps1 et
    lib\riot-text-files.lib.ps1 :
        . (Join-Path $PSScriptRoot 'lib\forced-text.lib.ps1')

    Locale Riot = A (voix). Pose : Game\DATA\FINAL\Localized\Global.A.wad.client et Game\DATA\FINAL\UI.A.wad.client
    reçoivent le contenu de Global.B / UI.B (cache CDN). Les chemins internes d'un WAD ne portent pas la locale :
    le jeu lit le texte de B en croyant lire celui de A. Le client LoL (Plugins) reste en A.

    Sauvegarde : les fichiers de A tels qu'installés sont ceux du CDN pour ce manifest — ils amorcent le cache de A
    (%LOCALAPPDATA%\hex-launcher\text\<manifestId>\A\). Restauration = fichiers de A du cache, retéléchargés si un
    patch a changé le manifest entre-temps : jamais un fichier d'une version périmée remis dans le jeu.

    INVARIANT : le marqueur forced-text-state.json est écrit AVANT la première copie et effacé APRÈS la restauration
    complète — une pose interrompue est toujours restaurée au lancement suivant.
    INVARIANT : aucune pose tant qu'une restauration est en attente — la sauvegarde ne peut jamais être faite à
    partir de fichiers déjà forcés.
    INVARIANT : dans le dossier du jeu, seuls les deux fichiers texte de A sont écrits — rien n'y est créé ni supprimé.
#>

$ForcedTextStatePath = Join-Path $env:LOCALAPPDATA 'hex-launcher\forced-text-state.json'

# Fichiers texte d'une locale dans l'installation : chemin dans le jeu et format ({0} = locale) du fichier
function Get-ForcedTextTargets([string]$LeagueFolder, [string]$Locale) {
    return @($ForcedTextFileFormats | ForEach-Object {
        [PSCustomObject]@{ GamePath = Join-Path $LeagueFolder ('Game\' + (($_ -f $Locale) -replace '/', '\')); Format = $_ }
    })
}

# Nom d'une cible pour une locale donnée, tel que rangé dans le cache : Global.fr_FR.wad.client
function Get-ForcedTextFileName($Target, [string]$Locale) {
    return Split-Path ($Target.Format -f $Locale) -Leaf
}

function Read-ForcedTextState {
    if (-not (Test-Path -LiteralPath $ForcedTextStatePath)) { return $null }
    return Get-Content -LiteralPath $ForcedTextStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-ForcedTextState($State) {
    New-Item -ItemType Directory -Path (Split-Path $ForcedTextStatePath -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($ForcedTextStatePath, ($State | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

function Test-ForcedTextPending {
    return Test-Path -LiteralPath $ForcedTextStatePath
}

# Fichiers de $Source = { Folder, Locale } copiés sur les cibles du jeu, format pour format ; une cible absente
# (locale retirée par Riot) n'est jamais recréée
function Copy-ForcedTextFiles($Source, [object[]]$Targets) {
    foreach ($target in $Targets) {
        if (-not (Test-Path -LiteralPath $target.GamePath -PathType Leaf)) { continue }
        [IO.File]::Copy((Join-Path $Source.Folder (Get-ForcedTextFileName $target $Source.Locale)), $target.GamePath, $true)
    }
}

# Langue des voix installée : ses deux fichiers texte sont présents et sont des WAD
function Test-VoiceTextInstalled([object[]]$Targets) {
    foreach ($target in $Targets) { if (-not (Test-WadFile $target.GamePath)) { return $false } }
    return $true
}

# Amorce le cache de la langue des voix avec ses fichiers installés, s'il n'est pas déjà complet
function Backup-VoiceTextFiles([string]$ManifestIdHex, $Voice) {
    $folder = Get-ForcedTextCacheFolder $ManifestIdHex $Voice.Locale
    if (Test-ForcedTextCacheComplete $folder $Voice.Locale) { return }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($target in $Voice.Targets) {
        $destination = Join-Path $folder (Get-ForcedTextFileName $target $Voice.Locale)
        Copy-Item -LiteralPath $target.GamePath -Destination ($destination + '.part') -Force
        Move-Item -LiteralPath ($destination + '.part') -Destination $destination -Force
    }
}

<#
    Pose le texte de $Request.TextLocale dans le jeu de $Request.LeagueFolder, dont la locale Riot est
    $Request.VoiceLocale. $Request = { LeagueFolder, VoiceLocale, TextLocale }. Lève une exception sur tout échec.
#>
function Install-ForcedText($Request) {
    if (Test-ForcedTextPending) { throw 'Texte forcé : une restauration est en attente' }
    $release = Read-InstalledGameRelease $Request.LeagueFolder
    $voice   = [PSCustomObject]@{ Locale = $Request.VoiceLocale; Targets = (Get-ForcedTextTargets $Request.LeagueFolder $Request.VoiceLocale) }
    if (-not (Test-VoiceTextInstalled $voice.Targets)) { throw "Texte forcé : fichiers texte $($voice.Locale) absents du jeu" }
    $source = [PSCustomObject]@{ Folder = (Get-ForcedTextFiles $Request.LeagueFolder $Request.TextLocale); Locale = $Request.TextLocale }
    Backup-VoiceTextFiles $release.ManifestIdHex $voice
    Write-ForcedTextState ([PSCustomObject]@{ leagueFolder = $Request.LeagueFolder; manifestId = $release.ManifestIdHex; voiceLocale = $voice.Locale; textLocale = $Request.TextLocale })
    Copy-ForcedTextFiles $source $voice.Targets
    Write-LaunchLogLine 'TEXT' ('pose {0} sur {1}' -f $Request.TextLocale, $voice.Locale) | Out-Null
}

<#
    Remet les fichiers texte d'origine après une pose ; rend $true si une restauration a eu lieu, $false s'il n'y
    avait rien à restaurer. Lève une exception sur échec : le marqueur reste, la restauration sera retentée.
#>
function Restore-ForcedText {
    $state = Read-ForcedTextState
    if (-not $state) { return $false }
    if (Test-Path -LiteralPath (Join-Path $state.leagueFolder $GameOkFileName)) {
        $source = [PSCustomObject]@{ Folder = (Get-ForcedTextFiles $state.leagueFolder $state.voiceLocale); Locale = $state.voiceLocale }
        Copy-ForcedTextFiles $source (Get-ForcedTextTargets $state.leagueFolder $state.voiceLocale)
    }
    Remove-Item -LiteralPath $ForcedTextStatePath -Force
    Write-LaunchLogLine 'TEXT' ('restauration {0}' -f $state.voiceLocale) | Out-Null
    return $true
}
