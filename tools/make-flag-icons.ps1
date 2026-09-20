<#
.SYNOPSIS
    Génère le jeu d'icônes « flat » dans app\ico\flat : hex-launcher.ico (base), hex-launcher-green.ico et hex-launcher-xx.ico
    (une par langue de app\locales.json), à partir du logo vectoriel tools\logo\hex-launcher-logo.svg.

.DESCRIPTION
    Le logo (cadre or + monogramme HL + gemme, fond transparent) est la source de vérité : tools\logo\hex-launcher-logo.svg
    (produit par tools\logo\make-logo-svg.py). Outil de développement, hors release : rien ici n'est nécessaire à l'usage.
    Il est rendu par resvg à chaque taille du .ico (256, 128, 64, 48, 32, 16), puis composé sur un fond dessiné
    nativement en GDI+ : un drapeau simplifié (app\lib\flag.lib.ps1, partagé avec les pastilles pays) ou une couleur
    unie pour la base, découpé au carré arrondi intérieur du cadre. Aucune image source raster.

    Prérequis (outil de développement, hors release) : resvg dans le PATH — `scoop install resvg`.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-flag-icons.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-flag-icons.ps1 -Base
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-flag-icons.ps1 -Locales ja_JP,ko_KR -PreviewDir C:\tmp
#>
param(
    # Codes à générer (défaut : tous ceux de locales.json ; aucun si -Base est donné seul)
    [string[]]$Locales,

    # Si fourni, écrit aussi un PNG 256 px par icône dans ce dossier (pour contrôle visuel)
    [string]$PreviewDir,

    # Génère les icônes de base hex-launcher.ico et hex-launcher-green.ico (implicite sans -Locales)
    [switch]$Base,

    # Dossier de sortie des .ico (défaut : app\ico\flat, le jeu par défaut ; les autres jeux sont des dossiers frères)
    [string]$OutDir,

    # Logo vectoriel (défaut : tools\logo\hex-launcher-logo.svg)
    [string]$LogoSvg,

    # Exécutable resvg (défaut : cherché dans le PATH)
    [string]$Resvg = 'resvg'
)

Add-Type -AssemblyName System.Drawing
$appFolder = Join-Path $PSScriptRoot '..\app'
. (Join-Path $appFolder 'lib\icon.lib.ps1')
. (Join-Path $appFolder 'lib\palette.lib.ps1')
. (Join-Path $appFolder 'lib\flag.lib.ps1')

$folder       = $appFolder   # locales.json et ico\ vivent dans app\
$icoFolder    = if ($OutDir) { $OutDir } else { Join-Path $folder 'ico\flat' }
$logoSvgPath  = if ($LogoSvg) { $LogoSvg } else { Join-Path $PSScriptRoot 'logo\hex-launcher-logo.svg' }
$IconSizes    = @(256, 128, 64, 48, 32, 16)
$BaseIconName = 'hex-launcher'

# Géométrie du cadre du logo, en fraction du côté de l'icône (identique au SVG : marge 7, épaisseur 13, rayon 40 à 256 px).
# Le fond est découpé au carré arrondi intérieur du cadre, en débordant sous le cadre pour ne laisser aucun jour.
$Frame = @{
    Margin       = 7 / 256
    Thickness    = 13 / 256
    CornerRadius = 40 / 256
    Overlap      = 2 / 256
}

# Atténuation du drapeau : mêmes réglages que les pastilles compagnon ($PaletteMuting, app\lib\palette.lib.ps1)
$Background = $PaletteMuting

# Palette réduite partagée (app\lib\palette.lib.ps1) : chaque couleur de remplissage des drapeaux (app\lib\flag.lib.ps1)
# est ramenée à la teinte la plus proche à la restitution — les dessins gardent leurs couleurs d'origine, seules les
# icônes changent ; les pastilles pays, qui dessinent sans résolveur, les montrent brutes
$FlagPaletteResolver = { param([string]$Hex) ConvertTo-PaletteColor $Hex }

# Icônes sans drapeau : fond uni (suffixe de fichier → couleur)
$BaseBackgrounds = [ordered]@{
    ''      = '#022DD2'   # hex-launcher.ico : bleu
    'green' = '#077A2F'   # hex-launcher-green.ico : vert
}

# ---------------------------------------------------------------- Fond : découpe au cadre

# Zone du fond : carré arrondi intérieur du cadre, débordant sous lui de $Frame.Overlap
function Get-BackgroundInset([int]$Size) {
    return [Math]::Max(1.0, $Size * ($Frame.Margin + $Frame.Thickness - $Frame.Overlap))
}

function New-RoundedSquarePath([double]$Offset, [double]$Side, [double]$Radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = [Math]::Max(0.0, [Math]::Min($Radius, $Side / 2)); $d = 2 * $r
    if ($d -le 0) { $path.AddRectangle((New-Object System.Drawing.RectangleF($Offset, $Offset, $Side, $Side))); return $path }
    $right = $Offset + $Side - $d; $bottom = $Offset + $Side - $d
    $path.AddArc([float]$Offset, [float]$Offset, [float]$d, [float]$d, 180, 90)
    $path.AddArc([float]$right, [float]$Offset, [float]$d, [float]$d, 270, 90)
    $path.AddArc([float]$right, [float]$bottom, [float]$d, [float]$d, 0, 90)
    $path.AddArc([float]$Offset, [float]$bottom, [float]$d, [float]$d, 90, 90)
    $path.CloseFigure()
    return $path
}

# Matrice de saturation (luminance Rec. 601) : $S = 1 inchangé, 0 = gris
function New-SaturationMatrix([double]$S) {
    $lr = 0.299; $lg = 0.587; $lb = 0.114
    $rows = @(
        @(($lr * (1 - $S) + $S), ($lr * (1 - $S)), ($lr * (1 - $S)), 0, 0),
        @(($lg * (1 - $S)), ($lg * (1 - $S) + $S), ($lg * (1 - $S)), 0, 0),
        @(($lb * (1 - $S)), ($lb * (1 - $S)), ($lb * (1 - $S) + $S), 0, 0),
        @(0, 0, 0, 1, 0),
        @(0, 0, 0, 0, 1)
    )
    $matrix = New-Object System.Drawing.Imaging.ColorMatrix
    for ($i = 0; $i -lt 5; $i++) { for ($j = 0; $j -lt 5; $j++) { $matrix[$i, $j] = [float]$rows[$i][$j] } }
    return $matrix
}

# Copie du drapeau aux couleurs atténuées (saturation réduite)
function ConvertTo-MutedBitmap([System.Drawing.Bitmap]$Source) {
    $bmp = New-Object System.Drawing.Bitmap($Source.Width, $Source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $attributes.SetColorMatrix((New-SaturationMatrix $Background.Saturation))
    $rect = New-Object System.Drawing.Rectangle(0, 0, $Source.Width, $Source.Height)
    $g.DrawImage($Source, $rect, 0, 0, $Source.Width, $Source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
    $g.Dispose(); $attributes.Dispose()
    return $bmp
}

# Fond dessiné puis découpé au carré arrondi intérieur (remplissage par texture : bords anticrénelés)
function Draw-BackgroundLayer($G, [int]$Size, [scriptblock]$Drawing) {
    $inset   = Get-BackgroundInset $Size
    $raw     = New-FlagBitmap $Drawing $Size (New-FlagRegion $Size $inset) $FlagPaletteResolver
    $flag    = ConvertTo-MutedBitmap $raw
    $texture = New-Object System.Drawing.TextureBrush($flag)
    $texture.WrapMode = 'Clamp'
    $path = New-RoundedSquarePath $inset ($Size - 2 * $inset) ($Size * $Frame.CornerRadius - $inset)
    $G.FillPath($texture, $path)
    $veil = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($Background.VeilAlpha, (Get-Color $Background.VeilColor)))
    $G.FillPath($veil, $path)
    $veil.Dispose(); $path.Dispose(); $texture.Dispose(); $flag.Dispose(); $raw.Dispose()
}

# ---------------------------------------------------------------- Logo : rendu du SVG par resvg

function Test-ResvgAvailable {
    return [bool](Get-Command $Resvg -ErrorAction SilentlyContinue)
}

# Rend le SVG à une taille donnée dans un fichier temporaire et le charge en Bitmap (copie détachée du fichier)
function ConvertFrom-SvgToBitmap([string]$SvgPath, [int]$Size) {
    $png = Join-Path ([IO.Path]::GetTempPath()) ("hex-launcher-logo-{0}-{1}.png" -f $Size, [Guid]::NewGuid().ToString('N'))
    & $Resvg -w $Size -h $Size $SvgPath $png | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $png)) { throw "resvg a échoué pour $SvgPath à $Size px" }
    try {
        $fromFile = New-Object System.Drawing.Bitmap($png)
        $bmp = New-Object System.Drawing.Bitmap($fromFile)
        $fromFile.Dispose()
        return $bmp
    } finally { Remove-Item $png -ErrorAction SilentlyContinue }
}

# Une Bitmap du logo par taille, rendue une seule fois pour toutes les icônes
function Get-LogoLayers([string]$SvgPath) {
    if (-not (Test-Path $SvgPath)) { throw "Logo vectoriel introuvable : $SvgPath" }
    if (-not (Test-ResvgAvailable)) { throw "resvg introuvable ($Resvg) — outil requis pour rendre le logo : scoop install resvg" }
    $layers = @{}
    foreach ($size in $IconSizes) { $layers[$size] = ConvertFrom-SvgToBitmap $SvgPath $size }
    return $layers
}

# ---------------------------------------------------------------- Composition

function New-IconBitmap([int]$Size, [scriptblock]$BackgroundDrawing, [System.Drawing.Bitmap]$LogoLayer) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.CompositingQuality = 'HighQuality'
    Draw-BackgroundLayer $g $Size $BackgroundDrawing
    $g.DrawImage($LogoLayer, 0, 0, $Size, $Size)
    $g.Dispose()
    return $bmp
}

# Une entrée par taille, chacune dessinée nativement
function New-IconEntries([scriptblock]$BackgroundDrawing, [hashtable]$LogoLayers) {
    return @(foreach ($size in $IconSizes) {
        [PSCustomObject]@{ Size = $size; Bitmap = (New-IconBitmap $size $BackgroundDrawing $LogoLayers[$size]) }
    })
}

# ja_JP → hex-launcher-jp.ico (même convention que create-shortcuts.ps1)
function Get-IconFileName([string]$Code) {
    return "$BaseIconName-$($Code.Split('_')[1].ToLower()).ico"
}

function Get-BaseIconFileName([string]$Suffix) {
    if ($Suffix) { return "$BaseIconName-$Suffix.ico" }
    return "$BaseIconName.ico"
}

function New-SolidBackground([string]$Hex) {
    return { param($G, $R) $G.Clear((Get-FlagColor $Hex)) }.GetNewClosure()
}

function Export-Preview([object[]]$Entries, [string]$IconFileName) {
    $largest = $Entries | Sort-Object Size -Descending | Select-Object -First 1
    $largest.Bitmap.Save((Join-Path $PreviewDir ([IO.Path]::ChangeExtension($IconFileName, 'png'))), [System.Drawing.Imaging.ImageFormat]::Png)
}

function Export-Icon([scriptblock]$BackgroundDrawing, [hashtable]$LogoLayers, [string]$IconFileName) {
    $entries = New-IconEntries $BackgroundDrawing $LogoLayers
    $target  = Join-Path $icoFolder $IconFileName
    Write-Ico $entries $target
    if ($PreviewDir) { Export-Preview $entries $IconFileName }
    $entries | ForEach-Object { $_.Bitmap.Dispose() }
    return $target
}

function Read-LocaleCodes {
    # ForEach-Object déplie le tableau que ConvertFrom-Json (PS 5.1) renvoie comme un seul objet
    return @(Get-Content (Join-Path $folder 'locales.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { $_.code })
}

# ---------------------------------------------------------------- Main

if ($MyInvocation.InvocationName -ne '.') {
    $codes = if ($Locales) { @($Locales | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ }) }
             elseif ($Base) { @() }
             else { Read-LocaleCodes }

    $missing = @($codes | Where-Object { -not $FlagDrawings.ContainsKey($_) })
    if ($missing.Count -gt 0) { throw "Pas de dessin de drapeau pour : $($missing -join ', ') — ajouter une entrée dans `$FlagDrawings" }

    New-Item -ItemType Directory -Force $icoFolder | Out-Null
    if ($PreviewDir) { New-Item -ItemType Directory -Force $PreviewDir | Out-Null }

    $logoLayers = Get-LogoLayers $logoSvgPath
    try {
        if ($Base -or -not $Locales) {
            foreach ($suffix in $BaseBackgrounds.Keys) {
                "OK : base $(if ($suffix) { $suffix } else { 'bleue' }) → $(Export-Icon (New-SolidBackground $BaseBackgrounds[$suffix]) $logoLayers (Get-BaseIconFileName $suffix))"
            }
        }
        foreach ($code in $codes) {
            "OK : $code → $(Export-Icon $FlagDrawings[$code] $logoLayers (Get-IconFileName $code))"
        }
    } finally {
        $logoLayers.Values | ForEach-Object { $_.Dispose() }
    }
}
