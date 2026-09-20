<#
.SYNOPSIS
    Construit l'archive de distribution hex-launcher-<version>.zip et, sur demande, publie la release GitHub.

.DESCRIPTION
    L'archive contient exactement ce qu'un joueur doit télécharger : setup.bat, LISEZMOI.txt, LICENSE,
    les README et le dossier app\ — sans config.json (propre à chaque machine), sans tests\, .forge\,
    .git*, tools\ ni dist\. La version est lue dans app\version.txt.

    Pas de raccourci .lnk dans l'archive : la cible d'un .lnk peut être relative (RelativePath), son icône jamais —
    l'Explorateur la résout depuis son propre répertoire courant, pas depuis le raccourci (mesuré le 2026-09-20).
    Le raccourci « Hex Launcher » du Bureau est posé par l'assistant, en chemins absolus.

    Sans -Publish : le zip est écrit dans dist\ (gitignoré). Avec -Publish : `gh release create v<version>`
    avec le zip en pièce jointe (nécessite gh authentifié et un tag non existant). Les notes de release se
    terminent par l'empreinte SHA-256 du zip, pour que chacun puisse vérifier son téléchargement (Get-FileHash).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1 -Publish -Notes "Première version"
#>
param(
    [switch]$Publish,
    [string]$Notes = ''
)

$ReleaseRootFiles = @('setup.bat', 'LISEZMOI.txt', 'LICENSE', 'README.md', 'README.fr.md', 'README.ja.md')
$ReleaseExcluded     = @('config.json', 'launch.log')
$ReleaseExcludedDirs = @('ico\*\companion')   # icônes drapeau + pastille composées sur chaque poste par create-shortcuts.ps1, dans chaque jeu

function Get-ProjectRoot {
    return Split-Path $PSScriptRoot -Parent
}

function Get-ReleaseVersion([string]$Root) {
    $path = Join-Path $Root 'app\version.txt'
    if (-not (Test-Path $path)) { throw "app\version.txt introuvable : $path" }
    $version = (Get-Content -Path $path -Raw).Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Version invalide dans app\version.txt : « $version » (attendu : x.y.z)" }
    return $version
}

# app\ico\flat\companion\x.ico → vrai : le fichier est dans un dossier généré sur la machine (motifs -like, * = un dossier)
function Test-ReleaseExcludedDir([string]$AppRoot, [string]$FullName) {
    $relative = $FullName.Substring($AppRoot.Length).TrimStart('\')
    foreach ($dir in $ReleaseExcludedDirs) { if ($relative -like ($dir + '\*')) { return $true } }
    return $false
}

# Fichiers de app\ à livrer : tout sauf ceux propres à la machine
function Get-ReleaseAppFiles([string]$Root) {
    $app = Join-Path $Root 'app'
    return @(Get-ChildItem -Path $app -Recurse -File | Where-Object { $ReleaseExcluded -notcontains $_.Name -and -not (Test-ReleaseExcludedDir $app $_.FullName) })
}

# Prépare un dossier hex-launcher-<version>\ avec la racine épurée et app\
function New-ReleaseStaging([string]$Root, [string]$Version, [string]$StagingParent) {
    $staging = Join-Path $StagingParent "hex-launcher-$Version"
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    foreach ($name in $ReleaseRootFiles) { Copy-Item (Join-Path $Root $name) $staging }
    $app = Join-Path $Root 'app'
    foreach ($file in Get-ReleaseAppFiles $Root) {
        $relative = $file.FullName.Substring($app.Length).TrimStart('\')
        $target   = Join-Path (Join-Path $staging 'app') $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item $file.FullName $target
    }
    return $staging
}

function New-ReleaseArchive([string]$Staging, [string]$Version, [string]$DistDir) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    $zip = Join-Path $DistDir "hex-launcher-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $Staging -DestinationPath $zip
    return $zip
}

# Empreinte SHA-256 du zip, en minuscules — celle que rend Get-FileHash chez l'utilisateur
function Get-ReleaseChecksum([string]$Zip) {
    return (Get-FileHash -Path $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Notes de release : le texte fourni, puis l'empreinte du zip et comment la vérifier
function Format-ReleaseNotes([string]$Notes, [string]$Zip) {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($Notes)) { $lines += $Notes.TrimEnd(); $lines += '' }
    $lines += "SHA-256 of ``$(Split-Path $Zip -Leaf)``: ``$(Get-ReleaseChecksum $Zip)``"
    $lines += 'Verify in PowerShell: `Get-FileHash <the zip> -Algorithm SHA256`'
    return ($lines -join "`n")
}

function Publish-Release([string]$Version, [string]$Zip, [string]$ReleaseNotes) {
    $tag = "v$Version"
    & gh release create $tag $Zip --title "Hex Launcher $tag" --notes (Format-ReleaseNotes $ReleaseNotes $Zip)
    if ($LASTEXITCODE -ne 0) { throw "gh release create a échoué (code $LASTEXITCODE)" }
    return $tag
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    $root    = Get-ProjectRoot
    $version = Get-ReleaseVersion $root
    $staging = New-ReleaseStaging $root $version $env:TEMP
    try {
        $zip = New-ReleaseArchive $staging $version (Join-Path $root 'dist')
        "Archive : $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) Ko)"
        "SHA-256 : $(Get-ReleaseChecksum $zip)"
        if ($Publish) { "Release publiée : $(Publish-Release $version $zip $Notes)" }
    }
    finally { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
