<#
.SYNOPSIS
    Génère l'icône de base du jeu « logo-badges » : le logo HL seul (sans cadre ni fond), agrandi, fond transparent.

.DESCRIPTION
    Source : le logo vectoriel tools\logo\hex-launcher-logo.svg, dont le groupe `frame` est retiré. Le viewBox est
    resserré sur l'emprise du logo (mesurée sur un rendu 1024 px), en carré : le logo prend toute la largeur, centré
    en hauteur ou calé en bas (-Placement). Chaque taille du .ico est rendue par resvg depuis ce SVG, nette à 16 px.

    Le jeu logo-badges n'a pas de drapeau : create-shortcuts.ps1 pose sur cette icône la pastille pays et la pastille
    compagnon (icon-source.json, source « set-base »).

    L'installeur prend le même logo, centré et entouré d'une marge (-LogoFill 0.90) : tools\installer\installer-logo.ico
    (icône du .exe, images de l'assistant).

    Prérequis (outil de développement, hors release) : resvg dans le PATH — `scoop install resvg`.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-logo-icon.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-logo-icon.ps1 -Placement centered -PreviewDir tmp\preview
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-logo-icon.ps1 -Placement centered -LogoFill 0.90 -OutDir tools\installer -FileName installer-logo.ico
#>
param(
    # bottom (défaut, choix utilisateur) : calé en bas, la place libre en haut reçoit la pastille pays ; centered : centré
    [ValidateSet('centered', 'bottom')]
    [string]$Placement = 'bottom',

    # Part du côté occupée par le logo : 0.98 (défaut) = pleine largeur, marge anti-rognage de l'anticrénelage seule ;
    # 0.90 pour l'icône de l'installeur, qui paraissait trop grosse sur le .exe (retours utilisateur : 0.80 trop de marge)
    [ValidateRange(0.1, 1.0)]
    [double]$LogoFill = 0.98,

    # Dossier de sortie (défaut : app\ico\logo-badges)
    [string]$OutDir,

    # Nom du .ico écrit (défaut : hex-launcher.ico, l'icône de base du jeu)
    [string]$FileName = 'hex-launcher.ico',

    # Logo vectoriel (défaut : tools\logo\hex-launcher-logo.svg)
    [string]$LogoSvg,

    # Si fourni, écrit aussi un PNG 256 px pour contrôle visuel
    [string]$PreviewDir,

    # Exécutable resvg (défaut : cherché dans le PATH)
    [string]$Resvg = 'resvg'
)

Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot '..\app\lib\icon.lib.ps1')

$IconSizes          = @(256, 128, 64, 48, 32, 16)
$MeasureSize        = 1024   # rendu de mesure de l'emprise
$SvgSide            = 256    # côté du viewBox d'origine
$OpaqueAlphaMinimum = 8      # alpha au-dessous duquel un pixel ne compte pas dans l'emprise

# ---------------------------------------------------------------- SVG (fonctions pures)

# Le groupe `frame` (cadre or) contient un seul groupe imbriqué : on retire de son ouverture à sa fermeture
function Remove-SvgFrame([string]$Svg) {
    $withoutFrame = [regex]::Replace($Svg, '(?s)\s*<g id="frame">.*?</g>\s*</g>', '')
    if ($withoutFrame -eq $Svg) { throw 'Logo vectoriel : groupe « frame » introuvable' }
    return $withoutFrame
}

function Set-SvgViewBox([string]$Svg, $Box) {
    $viewBox = 'viewBox="{0} {1} {2} {3}"' -f (Format-SvgNumber $Box.X), (Format-SvgNumber $Box.Y), (Format-SvgNumber $Box.Side), (Format-SvgNumber $Box.Side)
    return [regex]::Replace($Svg, 'viewBox="[^"]*"', $viewBox, 1)
}

function Format-SvgNumber([double]$Value) {
    return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

<#
    ViewBox carré autour de l'emprise $Bounds = { X, Y, Width, Height } (unités SVG) : le logo en occupe $LogoFill
    dans sa plus grande dimension, centré horizontalement ; verticalement centré ou calé en bas.
#>
function Get-LogoViewBox($Bounds, [string]$Mode) {
    $side = [Math]::Max($Bounds.Width, $Bounds.Height) / $LogoFill
    $x = $Bounds.X - ($side - $Bounds.Width) / 2
    $y = if ($Mode -eq 'bottom') { $Bounds.Y + $Bounds.Height - $side + ($side - $Bounds.Width) / 2 }
         else { $Bounds.Y - ($side - $Bounds.Height) / 2 }
    return [pscustomobject]@{ X = $x; Y = $y; Side = $side }
}

# ---------------------------------------------------------------- Emprise

# Rectangle des pixels d'alpha ≥ $OpaqueAlphaMinimum, en pixels ; $null si l'image est vide
function Get-OpaqueBounds([System.Drawing.Bitmap]$Bitmap) {
    $area = New-Object System.Drawing.Rectangle(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits($area, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $bytes = New-Object byte[] ($data.Stride * $Bitmap.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        $stride = $data.Stride
    }
    finally { $Bitmap.UnlockBits($data) }
    $minX = $Bitmap.Width; $minY = $Bitmap.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($bytes[$y * $stride + $x * 4 + 3] -lt $OpaqueAlphaMinimum) { continue }
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
        }
    }
    if ($maxX -lt 0) { return $null }
    return [pscustomobject]@{ X = $minX; Y = $minY; Width = $maxX - $minX + 1; Height = $maxY - $minY + 1 }
}

# Emprise en pixels d'un rendu $RenderSize → unités du viewBox d'origine
function ConvertTo-SvgBounds($PixelBounds, [int]$RenderSize) {
    $unit = $SvgSide / $RenderSize
    return [pscustomobject]@{ X = $PixelBounds.X * $unit; Y = $PixelBounds.Y * $unit; Width = $PixelBounds.Width * $unit; Height = $PixelBounds.Height * $unit }
}

# ---------------------------------------------------------------- Rendu par resvg

function Test-ResvgAvailable {
    return [bool](Get-Command $Resvg -ErrorAction SilentlyContinue)
}

# Rend le SVG (texte) à une taille donnée et le charge en Bitmap détachée des fichiers temporaires
function ConvertFrom-SvgTextToBitmap([string]$Svg, [int]$Size) {
    $stem = Join-Path ([IO.Path]::GetTempPath()) ("hex-launcher-logo-only-{0}-{1}" -f $Size, [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText("$stem.svg", $Svg, (New-Object Text.UTF8Encoding($false)))
    try {
        & $Resvg -w $Size -h $Size "$stem.svg" "$stem.png" | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$stem.png")) { throw "resvg a échoué à $Size px" }
        $fromFile = New-Object System.Drawing.Bitmap("$stem.png")
        $bmp = New-Object System.Drawing.Bitmap($fromFile)
        $fromFile.Dispose()
        return $bmp
    }
    finally { Remove-Item "$stem.svg", "$stem.png" -ErrorAction SilentlyContinue }
}

# SVG du logo seul, viewBox resserré selon $Mode
function Get-LogoOnlySvg([string]$SvgPath, [string]$Mode) {
    if (-not (Test-Path $SvgPath)) { throw "Logo vectoriel introuvable : $SvgPath" }
    $frameless = Remove-SvgFrame (Get-Content -Path $SvgPath -Raw -Encoding UTF8)
    $measure = ConvertFrom-SvgTextToBitmap $frameless $MeasureSize
    try { $pixelBounds = Get-OpaqueBounds $measure }
    finally { $measure.Dispose() }
    if (-not $pixelBounds) { throw 'Logo vectoriel : rendu vide une fois le cadre retiré' }
    return Set-SvgViewBox $frameless (Get-LogoViewBox (ConvertTo-SvgBounds $pixelBounds $MeasureSize) $Mode)
}

# ---------------------------------------------------------------- Main

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-ResvgAvailable)) { throw "resvg introuvable ($Resvg) — outil requis pour rendre le logo : scoop install resvg" }
    $root = Split-Path $PSScriptRoot -Parent
    if (-not $LogoSvg) { $LogoSvg = Join-Path $PSScriptRoot 'logo\hex-launcher-logo.svg' }
    if (-not $OutDir) { $OutDir = Join-Path $root 'app\ico\logo-badges' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null

    $svg = Get-LogoOnlySvg $LogoSvg $Placement
    $entries = @($IconSizes | ForEach-Object { [pscustomobject]@{ Size = $_; Bitmap = (ConvertFrom-SvgTextToBitmap $svg $_) } })
    try {
        $target = Join-Path $OutDir $FileName
        Write-Ico $entries $target
        if ($PreviewDir) {
            New-Item -ItemType Directory -Force $PreviewDir | Out-Null
            $entries[0].Bitmap.Save((Join-Path $PreviewDir 'logo-badges-256.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        "OK : logo seul ($Placement) → $target"
    }
    finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
}
