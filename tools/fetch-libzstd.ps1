<#
.SYNOPSIS
    Récupère libzstd.dll (x64) depuis la release officielle facebook/zstd et la pose dans app\lib\native\.

.DESCRIPTION
    Seule dépendance binaire du projet : la décompression zstd des manifests et des chunks du CDN Riot (mode texte
    forcé). .NET Framework 4.x ne sait pas décompresser du zstd ; la bibliothèque officielle de Meta (licence BSD)
    est appelée par P/Invoke depuis app\lib\zstd.lib.ps1.

    Provenance vérifiable : le zip est téléchargé depuis la release GitHub officielle, son SHA-256 est comparé à
    $ZstdArchiveSha256, puis la DLL extraite est comparée à $ZstdLibrarySha256 (épinglé dans app\lib\zstd.lib.ps1,
    vérifié aussi à chaque chargement). La licence BSD est copiée à côté (redistribution binaire).

    Changer de version : modifier $ZstdVersion, relancer avec -Force, reporter les deux empreintes affichées.
    Le zip de la release ne publie ni empreinte ni signature : les empreintes épinglées ici ont été relevées le
    2026-09-27 sur zstd-v1.5.7-win64.zip.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\fetch-libzstd.ps1
#>
param([switch]$Force)

$ZstdVersion       = '1.5.7'
$ZstdArchiveUrl    = "https://github.com/facebook/zstd/releases/download/v$ZstdVersion/zstd-v$ZstdVersion-win64.zip"
$ZstdArchiveSha256 = 'ACB4E8111511749DC7A3EBEDCA9B04190E37A17AFEB73F55D4425DBF0B90FAD9'
$ZstdLicenseUrl    = "https://raw.githubusercontent.com/facebook/zstd/v$ZstdVersion/LICENSE"
$ZstdArchiveDllPath = "zstd-v$ZstdVersion-win64\dll\libzstd.dll"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $ProjectRoot 'app\lib\zstd.lib.ps1')

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Assert-FileSha256([string]$Path, [string]$Expected) {
    $actual = Get-FileSha256 $Path
    if ($actual -ne $Expected) { throw "Empreinte inattendue pour $Path : $actual (attendue : $Expected)" }
}

function Save-ZstdLibrary([string]$WorkFolder) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $archive = Join-Path $WorkFolder 'zstd.zip'
    Invoke-WebRequest -Uri $ZstdArchiveUrl -OutFile $archive -UseBasicParsing
    Assert-FileSha256 $archive $ZstdArchiveSha256
    Expand-Archive -Path $archive -DestinationPath $WorkFolder -Force
    $dll = Join-Path $WorkFolder $ZstdArchiveDllPath
    Assert-FileSha256 $dll $ZstdLibrarySha256
    New-Item -ItemType Directory -Path (Split-Path $ZstdLibraryPath -Parent) -Force | Out-Null
    Copy-Item -Path $dll -Destination $ZstdLibraryPath -Force
    Invoke-WebRequest -Uri $ZstdLicenseUrl -OutFile $ZstdLicensePath -UseBasicParsing
}

if ($MyInvocation.InvocationName -ne '.') {
    if ((Test-Path $ZstdLibraryPath) -and -not $Force) {
        Write-Host "Déjà présente : $ZstdLibraryPath (-Force pour la remplacer)"
        exit 0
    }
    $work = Join-Path ([IO.Path]::GetTempPath()) ('hex-launcher-zstd-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        Save-ZstdLibrary $work
        Write-Host "libzstd $ZstdVersion posée : $ZstdLibraryPath"
        Write-Host "SHA-256 : $(Get-FileSha256 $ZstdLibraryPath)"
    }
    finally { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue }
}
