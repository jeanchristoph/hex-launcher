<#
.SYNOPSIS
    Construit l'installeur hex-launcher-setup-<version>.exe (Inno Setup 6, tools\installer\hex-launcher.iss) et
    la version portable hex-launcher-portable-<version>.zip (marqueur app\portable.json : données dans data\, à côté
    de setup.bat) puis, sur demande, publie la release GitHub avec les deux.

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

    Les notes viennent de -Notes (texte) ou de -NotesFile (fichier Markdown, prioritaire). Elles sont toujours
    remises à gh par un fichier (dist\release-notes-v<version>.md, conservé à côté du zip) : passées en argument,
    PowerShell 5.1 les tronque au premier guillemet double — la release 0.2.0 est partie avec 558 caractères
    sur 5 900 (2026-09-20), réparée à la main par `gh release edit --notes-file`.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1 -Publish -Notes "Première version"
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1 -Publish -NotesFile .forge\branch\launcher\output\20260920-release-notes-0-2-0.md
#>
param(
    [switch]$Publish,
    [string]$Notes = '',
    [string]$NotesFile = ''
)

$ReleaseRootFiles = @('setup.bat', 'LISEZMOI.txt', 'LICENSE', 'README.md', 'README.fr.md', 'README.ja.md')
# Garde-fou : ces données vivent hors de app\ depuis la 0.4.0, mais un poste de développement plus ancien peut encore
# les y avoir — elles ne doivent jamais partir dans une release
$ReleaseExcluded     = @('config.json', 'launch.log')
$ReleaseExcludedDirs = @('ico\*\companion')   # icônes composées par une version antérieure à la 0.4.0

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

# ISCC.exe d'Inno Setup 6 : installation machine, par utilisateur (winget), sinon le PATH ; $null si absent
function Find-InnoSetupCompiler {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'))
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

# Arguments de ISCC : version, dossier préparé et dossier de sortie passés en définitions au .iss
function Get-InstallerCompilerArguments([string]$Staging, [string]$Version, [string]$DistDir) {
    $script = Join-Path $PSScriptRoot 'installer\hex-launcher.iss'
    return @('/Q', "/DAppVersion=$Version", "/DSourceDir=$Staging", "/DOutputDir=$DistDir", $script)
}

# hex-launcher-setup-<version>.exe, compilé depuis le dossier préparé (sans marqueur portable)
function New-ReleaseInstaller([string]$Staging, [string]$Version, [string]$DistDir) {
    $compiler = Find-InnoSetupCompiler
    if (-not $compiler) { throw 'Inno Setup 6 introuvable (ISCC.exe) — installer : winget install --id JRSoftware.InnoSetup --exact' }
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    & $compiler (Get-InstallerCompilerArguments $Staging $Version $DistDir)
    if ($LASTEXITCODE -ne 0) { throw "ISCC a échoué (code $LASTEXITCODE)" }
    return Join-Path $DistDir "hex-launcher-setup-$Version.exe"
}

# Marqueur de la version portable (app\portable.json) : ses données vivront dans data\, à côté de setup.bat.
# Posé après la compilation de l'installeur, qui ne doit jamais le contenir.
function Add-PortableMarker([string]$Staging) {
    $path = Join-Path $Staging 'app\portable.json'
    [IO.File]::WriteAllText($path, "{ `"portable`": true }`r`n", (New-Object Text.UTF8Encoding($false)))
    return $path
}

# hex-launcher-portable-<version>.zip : la version portable, à décompresser où l'on veut
function New-ReleaseArchive([string]$Staging, [string]$Version, [string]$DistDir) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    $zip = Join-Path $DistDir "hex-launcher-portable-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $Staging -DestinationPath $zip
    return $zip
}

# Empreinte SHA-256 d'un fichier livré, en minuscules — celle que rend Get-FileHash chez l'utilisateur
function Get-ReleaseChecksum([string]$Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Notes de release : le texte fourni, puis l'empreinte de chaque fichier livré et comment la vérifier
function Format-ReleaseNotes([string]$Notes, [string[]]$Assets) {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($Notes)) { $lines += $Notes.TrimEnd(); $lines += '' }
    foreach ($asset in $Assets) { $lines += "SHA-256 of ``$(Split-Path $asset -Leaf)``: ``$(Get-ReleaseChecksum $asset)``" }
    $lines += 'Verify in PowerShell: `Get-FileHash <the file> -Algorithm SHA256`'
    return ($lines -join "`n")
}

# Notes de la release : le texte de -Notes, ou le contenu de -NotesFile s'il est donné (lu en UTF-8)
function Read-ReleaseNotes([string]$Notes, [string]$NotesFile) {
    if ([string]::IsNullOrWhiteSpace($NotesFile)) { return $Notes }
    if (-not (Test-Path $NotesFile)) { throw "Fichier de notes introuvable : $NotesFile" }
    return (Get-Content -Path $NotesFile -Raw -Encoding UTF8)
}

# Les notes formatées, écrites à côté du zip : c'est ce fichier que gh publie, jamais un argument de ligne de
# commande (troncature au premier guillemet sous PowerShell 5.1). UTF-8 sans BOM, fins de ligne LF : GitHub les rend tels quels
function Write-ReleaseNotesFile([string]$ReleaseNotes, [string[]]$Assets, [string]$Version) {
    $path = Join-Path (Split-Path $Assets[0] -Parent) "release-notes-v$Version.md"
    [IO.File]::WriteAllText($path, (Format-ReleaseNotes $ReleaseNotes $Assets) + "`n", (New-Object Text.UTF8Encoding($false)))
    return $path
}

function Publish-Release([string]$Version, [string[]]$Assets, [string]$ReleaseNotes) {
    $tag = "v$Version"
    $notesFile = Write-ReleaseNotesFile $ReleaseNotes $Assets $Version
    & gh release create $tag @Assets --title "Hex Launcher $tag" --notes-file $notesFile
    if ($LASTEXITCODE -ne 0) { throw "gh release create a échoué (code $LASTEXITCODE)" }
    return $tag
}

# ---------------------------------------------------------------- Main (ignoré quand le script est dot-sourcé par les tests)

if ($MyInvocation.InvocationName -ne '.') {
    $root    = Get-ProjectRoot
    $version = Get-ReleaseVersion $root
    $staging = New-ReleaseStaging $root $version $env:TEMP
    try {
        $dist      = Join-Path $root 'dist'
        $installer = New-ReleaseInstaller $staging $version $dist
        Add-PortableMarker $staging | Out-Null
        $zip       = New-ReleaseArchive $staging $version $dist
        foreach ($asset in @($installer, $zip)) {
            "$(Split-Path $asset -Leaf) : $([math]::Round((Get-Item $asset).Length / 1KB)) Ko, SHA-256 $(Get-ReleaseChecksum $asset)"
        }
        if ($Publish) { "Release publiée : $(Publish-Release $version @($installer, $zip) (Read-ReleaseNotes $Notes $NotesFile))" }
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
