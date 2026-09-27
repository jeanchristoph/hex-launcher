<#
.SYNOPSIS
    Fichiers texte d'une locale (Global, UI) pour la version installée du jeu, obtenus du CDN Riot et mis en cache.

.DESCRIPTION
    Chargé par dot-sourcing, après lib\launch-log.lib.ps1, lib\zstd.lib.ps1 et lib\riot-cdn.lib.ps1 :
        . (Join-Path $PSScriptRoot 'lib\riot-text-files.lib.ps1')

    Riot n'installe que les fichiers de la locale active. Le mode texte forcé a besoin de ceux d'une autre locale :
      Game.ok       → URL (donc id) du manifest de la version installée, locale active ;
      Game.manifest → copie locale de ce manifest RMAN : chemins et chunks des fichiers de TOUTES les locales ;
      CDN public    → chunks des seuls fichiers texte (~4 Mo), jamais la locale Riot changée pour les obtenir.
    Cache : %LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\ ; un patch change l'id, l'ancien cache est purgé.

    INVARIANT : l'installation Riot est lue seulement (Game.ok, Game.manifest) — ce fichier n'y écrit jamais.
    INVARIANT : un Game.manifest dont l'id diffère de Game.ok (patch en cours) est refusé : les fichiers doivent
    correspondre exactement à la version installée. Toute erreur lève une exception — l'appelant lance le jeu
    normalement, dans la langue des voix.
#>

$ForcedTextCacheRoot = Join-Path $env:LOCALAPPDATA 'hex-launcher\text'

# Chemins dans le manifest (racine = dossier Game\ du jeu), {0} = locale ; relevé du 2026-09-27
$ForcedTextFileFormats = @('DATA/FINAL/Localized/Global.{0}.wad.client', 'DATA/FINAL/UI.{0}.wad.client')

$GameOkFileName       = 'Game.ok'
$GameManifestFileName = 'Game.manifest'
$WadMagic             = 'RW'
$RmanReaderSourcePath = Join-Path $PSScriptRoot 'rman-reader.cs'

# Compilé à la première lecture d'un manifest seulement : un lancement servi par le cache ne paie pas csc
function Initialize-RmanReader {
    if (-not ([Management.Automation.PSTypeName]'HexLauncher.RmanManifest').Type) { Add-Type -Path $RmanReaderSourcePath }
}

# Game.ok : ligne 1 = URL du manifest installé, ligne 2 = locale active
function Read-InstalledGameRelease([string]$LeagueFolder) {
    $path = Join-Path $LeagueFolder $GameOkFileName
    if (-not (Test-Path -LiteralPath $path)) { throw "Texte forcé : $GameOkFileName introuvable dans $LeagueFolder" }
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    if ($lines.Count -lt 2 -or $lines[0] -notmatch '/([0-9A-Fa-f]{16})\.manifest$') { throw "Texte forcé : $GameOkFileName illisible" }
    return [PSCustomObject]@{ ManifestUrl = $lines[0].Trim(); ManifestIdHex = $Matches[1].ToUpperInvariant(); Locale = $lines[1].Trim() }
}

function Read-InstalledGameManifest([string]$LeagueFolder, $Release) {
    Initialize-RmanReader
    $bytes  = [IO.File]::ReadAllBytes((Join-Path $LeagueFolder $GameManifestFileName))
    $header = [HexLauncher.RmanHeader]::Parse($bytes)
    if ($header.ManifestIdHex -ne $Release.ManifestIdHex) {
        throw ('Texte forcé : {0} ({1}) ne correspond pas à {2} ({3})' -f $GameManifestFileName, $header.ManifestIdHex, $GameOkFileName, $Release.ManifestIdHex)
    }
    $body = [HexLauncher.Zstd]::Decompress($bytes, $header.BodyOffset, $header.BodyCompressedLength, $header.BodyUncompressedLength)
    return [HexLauncher.RmanManifest]::Parse($body)
}

function Get-ForcedTextCacheFolder([string]$ManifestIdHex, [string]$Locale) {
    return Join-Path $ForcedTextCacheRoot (Join-Path $ManifestIdHex $Locale)
}

# Chemins du manifest d'une locale ; le nom seul (Global.fr_FR.wad.client) sert dans le cache
function Get-ForcedTextFilePaths([string]$Locale) {
    return @($ForcedTextFileFormats | ForEach-Object { $_ -f $Locale })
}

function Test-WadFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $magic = New-Object byte[] 2
        return $stream.Read($magic, 0, 2) -eq 2 -and [Text.Encoding]::ASCII.GetString($magic) -eq $WadMagic
    }
    finally { $stream.Dispose() }
}

# Cache complet : chaque fichier est présent et commence comme un WAD (écrits par renommage, jamais à moitié)
function Test-ForcedTextCacheComplete([string]$Folder, [string]$Locale) {
    foreach ($path in Get-ForcedTextFilePaths $Locale) {
        if (-not (Test-WadFile (Join-Path $Folder (Split-Path $path -Leaf)))) { return $false }
    }
    return $true
}

function Find-ForcedTextFile($Manifest, [string]$Path, [string]$Locale) {
    $file = $Manifest.FindFile($Path)
    if (-not $file -or -not $Manifest.HasLanguage($file, $Locale)) { throw "Texte forcé : $Path absent du manifest" }
    return $file
}

function Save-ForcedTextFile($Manifest, [string]$BaseUrl, $Target) {
    $file = Find-ForcedTextFile $Manifest $Target.Path $Target.Locale
    $destination = Join-Path $Target.Folder (Split-Path $Target.Path -Leaf)
    Save-RiotCdnFile ([PSCustomObject]@{ BaseUrl = $BaseUrl; Chunks = $Manifest.GetChunks($file); Size = $file.Size; Destination = $destination })
    if (-not (Test-WadFile $destination)) {
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        throw "Texte forcé : $destination n'est pas un fichier WAD"
    }
}

# Caches des versions précédentes : un patch rend inutiles les ~4 Mo par locale qu'ils contiennent
function Remove-StaleForcedTextCache([string]$ManifestIdHex) {
    if (-not (Test-Path -LiteralPath $ForcedTextCacheRoot)) { return }
    Get-ChildItem -LiteralPath $ForcedTextCacheRoot -Directory |
        Where-Object { $_.Name -ne $ManifestIdHex } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# $Request = { LeagueFolder, Release, Locale, Folder }
function Receive-ForcedTextFiles($Request) {
    Initialize-ZstdLibrary
    $manifest = Read-InstalledGameManifest $Request.LeagueFolder $Request.Release
    $baseUrl  = Get-RiotCdnBaseUrl $Request.Release.ManifestUrl
    New-Item -ItemType Directory -Path $Request.Folder -Force | Out-Null
    foreach ($path in Get-ForcedTextFilePaths $Request.Locale) {
        Save-ForcedTextFile $manifest $baseUrl ([PSCustomObject]@{ Path = $path; Locale = $Request.Locale; Folder = $Request.Folder })
    }
    Remove-StaleForcedTextCache $Request.Release.ManifestIdHex
}

<#
    Dossier de cache contenant les fichiers texte de $Locale pour la version installée dans $LeagueFolder
    (dossier de LeagueClient.exe), téléchargés au besoin. Lève une exception sur tout échec.
#>
function Get-ForcedTextFiles([string]$LeagueFolder, [string]$Locale) {
    $chrono  = [Diagnostics.Stopwatch]::StartNew()
    $release = Read-InstalledGameRelease $LeagueFolder
    $folder  = Get-ForcedTextCacheFolder $release.ManifestIdHex $Locale
    if (Test-ForcedTextCacheComplete $folder $Locale) {
        Write-LaunchLogLine 'TEXT' ('cache {0} {1}' -f $release.ManifestIdHex, $Locale) | Out-Null
        return $folder
    }
    Receive-ForcedTextFiles ([PSCustomObject]@{ LeagueFolder = $LeagueFolder; Release = $release; Locale = $Locale; Folder = $folder })
    Write-LaunchLogLine 'TEXT' ('téléchargé {0} {1} en {2}' -f $release.ManifestIdHex, $Locale, (Format-LaunchLogDuration $chrono)) | Out-Null
    return $folder
}
