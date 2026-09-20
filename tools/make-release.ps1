<#
.SYNOPSIS
    Construit l'archive de distribution hex-launcher-<version>.zip et, sur demande, publie la release GitHub.

.DESCRIPTION
    L'archive contient exactement ce qu'un joueur doit télécharger : setup.bat, LISEZMOI.txt, LICENSE,
    les README, un raccourci « Hex Launcher » vers setup.bat et le dossier app\ — sans config.json (propre à
    chaque machine), sans tests\, .forge\, .git*, tools\ ni dist\. La version est lue dans app\version.txt.

    Le raccourci est relatif : sa cible absolue (le staging) n'existe pas chez le joueur, l'Explorateur retombe
    alors sur le chemin relatif stocké dans le .lnk, résolu depuis l'emplacement du raccourci — l'archive se
    décompresse n'importe où (mesuré le 2026-09-20 : cible résolue et icône engrenage affichée après déplacement).
    Déplacé hors du dossier, il ne pointe plus sur rien : le raccourci du Bureau est celui que pose l'assistant.

    Sans -Publish : le zip est écrit dans dist\ (gitignoré). Avec -Publish : `gh release create v<version>`
    avec le zip en pièce jointe (nécessite gh authentifié et un tag non existant).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1 -Publish -Notes "Première version"
#>
param(
    [switch]$Publish,
    [string]$Notes = ''
)

$ReleaseRootFiles = @('setup.bat', 'LISEZMOI.txt', 'LICENSE', 'README.md', 'README.fr.md', 'README.ja.md')
$ReleaseShortcutName = 'Hex Launcher'
$ReleaseSetupIcon    = 'app\ico\hex-launcher-setup.ico'
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

# Raccourci portable vers setup.bat à la racine du staging. RelativePath reçoit le chemin du .lnk lui-même
# (IShellLink::SetRelativePath) : le shell en déduit « setup.bat » et pose le drapeau HasRelativePath.
# L'icône relative est résolue par le shell depuis le dossier du raccourci, pas depuis le répertoire courant.
function New-ReleaseSetupShortcut([string]$Staging) {
    $path     = Join-Path $Staging "$ReleaseShortcutName.lnk"
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath   = Join-Path $Staging 'setup.bat'
    $shortcut.RelativePath = $path
    $shortcut.IconLocation = "$ReleaseSetupIcon,0"
    $shortcut.WindowStyle  = 7   # Réduite : setup.bat n'a rien à montrer, la fenêtre de l'assistant suffit
    $shortcut.Description  = 'Hex Launcher — setup'
    $shortcut.Save()
    return $path
}

# Prépare un dossier hex-launcher-<version>\ avec la racine épurée, le raccourci et app\
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
    New-ReleaseSetupShortcut $staging | Out-Null
    return $staging
}

function New-ReleaseArchive([string]$Staging, [string]$Version, [string]$DistDir) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    $zip = Join-Path $DistDir "hex-launcher-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $Staging -DestinationPath $zip
    return $zip
}

function Publish-Release([string]$Version, [string]$Zip, [string]$ReleaseNotes) {
    $tag = "v$Version"
    & gh release create $tag $Zip --title "Hex Launcher $tag" --notes $ReleaseNotes
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
        if ($Publish) { "Release publiée : $(Publish-Release $version $zip $Notes)" }
    }
    finally { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
