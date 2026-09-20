<#
.SYNOPSIS
    Génère le jeu d'icônes « flat » dans app\ico\flat : hex-launcher.ico (base), hex-launcher-green.ico et hex-launcher-xx.ico
    (une par langue de app\locales.json), à partir du logo vectoriel tools\logo\hex-launcher-logo.svg.

.DESCRIPTION
    Le logo (cadre or + monogramme HL + gemme, fond transparent) est la source de vérité : tools\logo\hex-launcher-logo.svg
    (produit par tools\logo\make-logo-svg.py). Outil de développement, hors release : rien ici n'est nécessaire à l'usage.
    Il est rendu par resvg à chaque taille du .ico (256, 128, 64, 48, 32, 16), puis composé sur un fond dessiné
    nativement en GDI+ : un drapeau simplifié (ou une couleur unie pour la base), découpé au carré arrondi intérieur
    du cadre. Aucune image source raster.

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

# Icônes sans drapeau : fond uni (suffixe de fichier → couleur)
$BaseBackgrounds = [ordered]@{
    ''      = '#022DD2'   # hex-launcher.ico : bleu
    'green' = '#077A2F'   # hex-launcher-green.ico : vert
}

# ---------------------------------------------------------------- Primitives de dessin

function Get-Color([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

# Palette réduite partagée avec les pastilles compagnon (app\lib\palette.lib.ps1) : chaque couleur dessinée est ramenée
# à la teinte la plus proche — les dessins gardent leurs couleurs d'origine, seule la restitution change
function Get-FlagColor([string]$Hex) {
    return ConvertTo-PaletteColor $Hex
}

function Get-Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush((Get-FlagColor $Hex))
}

# Couleur intermédiaire entre deux teintes ($T = 0 → A, 1 → B)
function Get-BlendedColor([string]$HexA, [string]$HexB, [double]$T) {
    $a = Get-Color $HexA; $b = Get-Color $HexB
    return [System.Drawing.Color]::FromArgb(
        [int]($a.R + ($b.R - $a.R) * $T), [int]($a.G + ($b.G - $a.G) * $T), [int]($a.B + ($b.B - $a.B) * $T))
}

function New-PointArray([object[]]$Pairs) {
    return [System.Drawing.PointF[]]($Pairs | ForEach-Object { New-Object System.Drawing.PointF([float]$_[0], [float]$_[1]) })
}

# Bandes horizontales réparties dans la zone visible ; première et dernière prolongées aux bords
function Draw-HorizontalStripes($G, $R, [string[]]$Colors, [double[]]$Weights) {
    if (-not $Weights) { $Weights = @(1) * $Colors.Count }
    $total = ($Weights | Measure-Object -Sum).Sum
    $y = $R.Top
    for ($i = 0; $i -lt $Colors.Count; $i++) {
        $h  = $R.Height * $Weights[$i] / $total
        $y0 = if ($i -eq 0) { 0 } else { $y }
        $y1 = if ($i -eq $Colors.Count - 1) { $R.Size } else { $y + $h }
        $G.FillRectangle((Get-Brush $Colors[$i]), 0, [float]$y0, $R.Size, [float]($y1 - $y0))
        $y += $h
    }
}

function Draw-VerticalStripes($G, $R, [string[]]$Colors, [double[]]$Weights) {
    if (-not $Weights) { $Weights = @(1) * $Colors.Count }
    $total = ($Weights | Measure-Object -Sum).Sum
    $x = $R.Left
    for ($i = 0; $i -lt $Colors.Count; $i++) {
        $w  = $R.Width * $Weights[$i] / $total
        $x0 = if ($i -eq 0) { 0 } else { $x }
        $x1 = if ($i -eq $Colors.Count - 1) { $R.Size } else { $x + $w }
        $G.FillRectangle((Get-Brush $Colors[$i]), [float]$x0, 0, [float]($x1 - $x0), $R.Size)
        $x += $w
    }
}

function Draw-Disc($G, [string]$Color, [double]$Cx, [double]$Cy, [double]$Diameter) {
    $G.FillEllipse((Get-Brush $Color), [float]($Cx - $Diameter / 2), [float]($Cy - $Diameter / 2), [float]$Diameter, [float]$Diameter)
}

function Get-StarPoints([double]$Cx, [double]$Cy, [double]$Outer, [int]$Branches = 5) {
    $inner  = $Outer * 0.382
    $points = for ($i = 0; $i -lt $Branches * 2; $i++) {
        $radius = if ($i % 2 -eq 0) { $Outer } else { $inner }
        $angle  = -[Math]::PI / 2 + $i * [Math]::PI / $Branches
        New-Object System.Drawing.PointF([float]($Cx + $radius * [Math]::Cos($angle)), [float]($Cy + $radius * [Math]::Sin($angle)))
    }
    return [System.Drawing.PointF[]]$points
}

function Draw-Star($G, [string]$Color, [double]$Cx, [double]$Cy, [double]$Outer, [int]$Branches = 5) {
    $G.FillPolygon((Get-Brush $Color), (Get-StarPoints $Cx $Cy $Outer $Branches))
}

function Draw-Line($G, [string]$Color, [double]$Width, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2) {
    $pen = New-Object System.Drawing.Pen((Get-Color $Color), [float]$Width)
    $G.DrawLine($pen, [float]$X1, [float]$Y1, [float]$X2, [float]$Y2)
    $pen.Dispose()
}

# Union Jack simplifié (sans liseré) dans le rectangle donné ; le tracé est clippé au rectangle
function Draw-UnionJack($G, [double]$X, [double]$Y, [double]$W, [double]$H) {
    $G.SetClip((New-Object System.Drawing.RectangleF([float]$X, [float]$Y, [float]$W, [float]$H)))
    $G.FillRectangle((Get-Brush '#012169'), [float]$X, [float]$Y, [float]$W, [float]$H)
    $cx = $X + $W / 2; $cy = $Y + $H / 2; $t = [Math]::Min($W, $H) * 0.075
    Draw-Line $G '#FFFFFF' ($t * 1.4) $X $Y ($X + $W) ($Y + $H);  Draw-Line $G '#FFFFFF' ($t * 1.4) ($X + $W) $Y $X ($Y + $H)
    Draw-Line $G '#C8102E' ($t * 0.5) $X $Y ($X + $W) ($Y + $H);  Draw-Line $G '#C8102E' ($t * 0.5) ($X + $W) $Y $X ($Y + $H)
    Draw-Line $G '#FFFFFF' ($t * 2.2) $cx $Y $cx ($Y + $H);        Draw-Line $G '#FFFFFF' ($t * 2.2) $X $cy ($X + $W) $cy
    Draw-Line $G '#C8102E' ($t * 1.2) $cx $Y $cx ($Y + $H);        Draw-Line $G '#C8102E' ($t * 1.2) $X $cy ($X + $W) $cy
    $G.ResetClip()
}

# Trigramme du drapeau coréen : trois barres perpendiculaires à la diagonale ($AngleDeg = direction centre → trigramme),
# empilées le long de cette diagonale ; une barre brisée est coupée en deux par un jour égal à son épaisseur
function Draw-Trigram($G, [string]$Color, [double]$Cx, [double]$Cy, [double]$AngleDeg, [double]$Length, [double]$Thickness, [double]$Gap, [bool[]]$Broken) {
    $state = $G.Save()
    $G.TranslateTransform([float]$Cx, [float]$Cy)
    $G.RotateTransform([float]$AngleDeg)
    $brush = Get-Brush $Color
    $span = 3 * $Thickness + 2 * $Gap
    for ($i = 0; $i -lt 3; $i++) {
        $x = -$span / 2 + $i * ($Thickness + $Gap)     # axe local x = le long de la diagonale
        if ($Broken[$i]) {
            $half = ($Length - $Thickness) / 2
            $G.FillRectangle($brush, [float]$x, [float](-$Length / 2), [float]$Thickness, [float]$half)
            $G.FillRectangle($brush, [float]$x, [float]($Length / 2 - $half), [float]$Thickness, [float]$half)
        } else {
            $G.FillRectangle($brush, [float]$x, [float](-$Length / 2), [float]$Thickness, [float]$Length)
        }
    }
    $brush.Dispose()
    $G.Restore($state)
}

# Croissant : disque plein + disque de la couleur du fond décalé
function Draw-Crescent($G, [string]$Color, [string]$Background, [double]$Cx, [double]$Cy, [double]$Diameter, [double]$Offset) {
    Draw-Disc $G $Color $Cx $Cy $Diameter
    Draw-Disc $G $Background ($Cx + $Offset) $Cy ($Diameter * 0.8)
}

# ---------------------------------------------------------------- Drapeaux (simplifiés)
# Chaque scriptblock reçoit $G (Graphics) et $R (zone intérieure : Left/Right/Top/Bottom/Width/Height/Cx/Cy/Size).
# Le tracé déborde librement : il est ensuite découpé au carré arrondi intérieur du cadre.
# Couleurs : celles du drapeau, ramenées à $FlagPalette à la restitution (Get-FlagColor / Get-Brush).

# Emblème centré (disque japonais, taegeuk, étoile vietnamienne, croissant turc) : même diamètre, en fraction de la hauteur de la zone
$CenterEmblem = 0.5

$FlagDrawings = @{
    'ja_JP' = { param($G, $R)
        $G.Clear((Get-FlagColor '#FFFFFF'))
        Draw-Disc $G '#BC002D' $R.Cx $R.Cy ($R.Height * $CenterEmblem)
    }
    'fr_FR' = { param($G, $R) Draw-VerticalStripes $G $R @('#000091', '#FFFFFF', '#E1000F') }
    'en_US' = { param($G, $R)
        $stripes = @(); for ($i = 0; $i -lt 9; $i++) { $stripes += if ($i % 2 -eq 0) { '#B31942' } else { '#FFFFFF' } }
        Draw-HorizontalStripes $G $R $stripes
        $cantonW = $R.Width * 0.55; $cantonH = $R.Height * 4 / 9
        $G.FillRectangle((Get-Brush '#0A3161'), 0, 0, [float]($R.Left + $cantonW), [float]($R.Top + $cantonH))
        for ($row = 0; $row -lt 3; $row++) { for ($col = 0; $col -lt 3; $col++) {
            Draw-Disc $G '#FFFFFF' ($R.Left + $cantonW * (0.2 + 0.3 * $col)) ($R.Top + $cantonH * (0.2 + 0.3 * $row)) ($R.Size * 0.02)
        } }
    }
    'en_GB' = { param($G, $R)
        # Centré sur la zone intérieure, tracé sur toute l'image
        Draw-UnionJack $G ($R.Cx - $R.Size) ($R.Cy - $R.Size) ($R.Size * 2) ($R.Size * 2)
    }
    'en_AU' = { param($G, $R)
        $G.Clear((Get-FlagColor '#001B69'))
        $cantonW = $R.Width * 0.55; $cantonH = $R.Height * 0.4
        Draw-UnionJack $G 0 0 ($R.Left + $cantonW) ($R.Top + $cantonH)
        $star = $R.Width * 0.09
        Draw-Star $G '#FFFFFF' ($R.Left + $cantonW / 2) ($R.Top + $cantonH * 1.7) ($star * 1.3) 7   # étoile du Commonwealth
        foreach ($p in @(@(0.80, 0.22), @(0.95, 0.45), @(0.72, 0.62), @(0.86, 0.88))) {              # Croix du Sud
            Draw-Star $G '#FFFFFF' ($R.Left + $R.Width * $p[0]) ($R.Top + $R.Height * $p[1]) $star 7
        }
    }
    'en_SG' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#EE2536', '#FFFFFF')
        $cy = $R.Top + $R.Height * 0.25; $d = $R.Height * 0.32
        Draw-Crescent $G '#FFFFFF' '#EE2536' ($R.Left + $R.Width * 0.3) $cy $d ($d * 0.28)
        foreach ($p in @(@(0.62, -0.42), @(0.52, -0.12), @(0.72, -0.12), @(0.56, 0.22), @(0.68, 0.22))) {
            Draw-Star $G '#FFFFFF' ($R.Left + $R.Width * $p[0]) ($cy + $d * $p[1]) ($d * 0.11)
        }
    }
    'en_PH' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#0038A8', '#CE1126')
        $apex = $R.Left + $R.Width * 0.55
        $G.FillPolygon((Get-Brush '#FFFFFF'), (New-PointArray @(@(0, 0), @($apex, $R.Cy), @(0, $R.Size))))
        $sunCx = $R.Left + $R.Width * 0.18; $sunD = $R.Width * 0.24
        for ($i = 0; $i -lt 8; $i++) {
            $a = $i * [Math]::PI / 4
            Draw-Line $G '#FCD116' ($sunD * 0.15) $sunCx $R.Cy ($sunCx + $sunD * 0.85 * [Math]::Cos($a)) ($R.Cy + $sunD * 0.85 * [Math]::Sin($a))
        }
        Draw-Disc $G '#FCD116' $sunCx $R.Cy $sunD
    }
    'es_AR' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#74ACDF', '#FFFFFF', '#74ACDF')
        Draw-Disc $G '#F6B40E' $R.Cx $R.Cy ($R.Height * 0.22)
    }
    'id_ID' = { param($G, $R) Draw-HorizontalStripes $G $R @('#FF0000', '#FFFFFF') }
    'zh_MY' = { param($G, $R)
        $stripes = @(); for ($i = 0; $i -lt 7; $i++) { $stripes += if ($i % 2 -eq 0) { '#CC0000' } else { '#FFFFFF' } }
        Draw-HorizontalStripes $G $R $stripes
        $cantonRight = $R.Left + $R.Width * 0.55; $cantonBottom = $R.Top + $R.Height * 4 / 7
        $G.FillRectangle((Get-Brush '#000066'), 0, 0, [float]$cantonRight, [float]$cantonBottom)
        $cx = ($R.Left + $cantonRight) / 2; $cy = ($R.Top + $cantonBottom) / 2; $d = $R.Width * 0.3
        Draw-Crescent $G '#FFCC00' '#000066' ($cx - $d * 0.15) $cy $d ($d * 0.25)
        Draw-Star $G '#FFCC00' ($cx + $d * 0.42) $cy ($d * 0.3) 14
    }
    'ko_KR' = { param($G, $R)
        $G.Clear((Get-FlagColor '#FFFFFF'))
        $d = $R.Height * $CenterEmblem * 0.92
        Draw-Disc $G '#0047A0' $R.Cx $R.Cy $d
        $G.FillPie((Get-Brush '#CD2E3A'), [float]($R.Cx - $d / 2), [float]($R.Cy - $d / 2), [float]$d, [float]$d, 180, 180)
        Draw-Disc $G '#CD2E3A' ($R.Cx - $d / 4) $R.Cy ($d / 2)
        Draw-Disc $G '#0047A0' ($R.Cx + $d / 4) $R.Cy ($d / 2)
        # Quatre trigrammes sur les diagonales (proportions du drapeau : centres à ±0,75 d / ±0,5 d, barres d/2 × d/12)
        $trigrams = @(
            @{ X = -0.75; Y = -0.5; Broken = @($false, $false, $false) },   # geon ☰ haut gauche
            @{ X =  0.75; Y =  0.5; Broken = @($true,  $true,  $true)  },   # gon  ☷ bas droite
            @{ X =  0.75; Y = -0.5; Broken = @($true,  $false, $true)  },   # gam  ☵ haut droite
            @{ X = -0.75; Y =  0.5; Broken = @($false, $true,  $false) }    # ri   ☲ bas gauche
        )
        foreach ($t in $trigrams) {
            $angle = [Math]::Atan2($t.Y, $t.X) * 180 / [Math]::PI
            Draw-Trigram $G '#000000' ($R.Cx + $t.X * $d) ($R.Cy + $t.Y * $d) $angle ($d / 2) ($d / 12) ($d / 24) $t.Broken
        }
    }
    'de_DE' = { param($G, $R) Draw-HorizontalStripes $G $R @('#000000', '#D00000', '#FFCE00') }
    'es_ES' = { param($G, $R) Draw-HorizontalStripes $G $R @('#AD1519', '#FABD00', '#AD1519') @(1, 2, 1) }
    'es_MX' = { param($G, $R) Draw-VerticalStripes $G $R @('#006847', '#FFFFFF', '#CE1126') }
    'it_IT' = { param($G, $R) Draw-VerticalStripes $G $R @('#008C45', '#F4F5F0', '#CD212A') }
    'pl_PL' = { param($G, $R) Draw-HorizontalStripes $G $R @('#E9E8E7', '#D4213D') }
    'pt_BR' = { param($G, $R)
        $G.Clear((Get-FlagColor '#009440'))
        $rw = $R.Width * 0.85; $rh = $R.Height * 0.55
        $rhombus = New-PointArray @(@($R.Cx, ($R.Cy - $rh / 2)), @(($R.Cx + $rw / 2), $R.Cy), @($R.Cx, ($R.Cy + $rh / 2)), @(($R.Cx - $rw / 2), $R.Cy))
        $G.FillPolygon((Get-Brush '#FFCB00'), $rhombus)
        Draw-Disc $G '#302681' $R.Cx $R.Cy ($rh * 0.62)
    }
    'ru_RU' = { param($G, $R) Draw-HorizontalStripes $G $R @('#FFFFFF', '#0039A6', '#D52B1E') }
    'tr_TR' = { param($G, $R)
        $G.Clear((Get-FlagColor '#E30A17'))
        $d = $R.Height * $CenterEmblem; $cx = $R.Cx - $d * 0.2      # croissant + étoile centrés, même emprise que le disque japonais
        Draw-Disc $G '#FFFFFF' $cx $R.Cy $d
        Draw-Disc $G '#E30A17' ($cx + $d * 0.2) $R.Cy ($d * 0.8)
        Draw-Star $G '#FFFFFF' ($cx + $d * 0.62) $R.Cy ($d * 0.22)
    }
    'zh_TW' = { param($G, $R)
        $G.Clear((Get-FlagColor '#FE0000'))
        $cantonRight = $R.Left + $R.Width * 0.6; $cantonBottom = $R.Top + $R.Height * 0.5
        $G.FillRectangle((Get-Brush '#000095'), 0, 0, [float]$cantonRight, [float]$cantonBottom)
        $sunCx = ($R.Left + $cantonRight) / 2; $sunCy = ($R.Top + $cantonBottom) / 2; $sunD = $R.Width * 0.3
        for ($i = 0; $i -lt 12; $i++) {
            $a = $i * [Math]::PI / 6
            Draw-Line $G '#FFFFFF' ($sunD * 0.12) $sunCx $sunCy ($sunCx + $sunD * 0.85 * [Math]::Cos($a)) ($sunCy + $sunD * 0.85 * [Math]::Sin($a))
        }
        Draw-Disc $G '#FFFFFF' $sunCx $sunCy $sunD
    }
    'cs_CZ' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#FFFFFF', '#D7141A')
        $G.FillPolygon((Get-Brush '#11457E'), (New-PointArray @(@(0, 0), @(($R.Left + $R.Width * 0.5), $R.Cy), @(0, $R.Size))))
    }
    'el_GR' = { param($G, $R)
        $stripes = @(); for ($i = 0; $i -lt 9; $i++) { $stripes += if ($i % 2 -eq 0) { '#0D5EAF' } else { '#FFFFFF' } }
        Draw-HorizontalStripes $G $R $stripes
        $cantonRight = $R.Left + $R.Width * 0.5; $cantonBottom = $R.Top + $R.Height * 5 / 9
        $G.FillRectangle((Get-Brush '#0D5EAF'), 0, 0, [float]$cantonRight, [float]$cantonBottom)
        $t = $R.Height / 9
        Draw-Line $G '#FFFFFF' $t (($R.Left + $cantonRight) / 2) 0 (($R.Left + $cantonRight) / 2) $cantonBottom
        Draw-Line $G '#FFFFFF' $t 0 (($R.Top + $cantonBottom) / 2) $cantonRight (($R.Top + $cantonBottom) / 2)
    }
    'hu_HU' = { param($G, $R) Draw-HorizontalStripes $G $R @('#CE2939', '#FFFFFF', '#477050') }
    'ro_RO' = { param($G, $R) Draw-VerticalStripes $G $R @('#002B7F', '#FCD116', '#CE1126') }
    'th_TH' = { param($G, $R) Draw-HorizontalStripes $G $R @('#A51931', '#F4F5F8', '#2D2A4A', '#F4F5F8', '#A51931') @(1, 1, 2, 1, 1) }
    'vi_VN' = { param($G, $R)
        $G.Clear((Get-FlagColor '#DA251D'))
        Draw-Star $G '#FFFF00' $R.Cx $R.Cy ($R.Height * $CenterEmblem / 2)
    }
    'ar_AE' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#00843D', '#FFFFFF', '#000000')
        $G.FillRectangle((Get-Brush '#C8102E'), 0, 0, [float]($R.Left + $R.Width * 0.25), $R.Size)
    }
}

# ---------------------------------------------------------------- Fond : découpe au cadre

# Zone du fond : carré arrondi intérieur du cadre, débordant sous lui de $Frame.Overlap
function Get-BackgroundInset([int]$Size) {
    return [Math]::Max(1.0, $Size * ($Frame.Margin + $Frame.Thickness - $Frame.Overlap))
}

function New-InnerRegion([int]$Size, [double]$Inset) {
    return @{
        Left = $Inset; Right = $Size - $Inset; Top = $Inset; Bottom = $Size - $Inset
        Width = $Size - 2 * $Inset; Height = $Size - 2 * $Inset
        Cx = $Size / 2; Cy = $Size / 2
        Size = $Size
    }
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

function New-FlagBitmap([scriptblock]$Drawing, [int]$Size, $Region) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    & $Drawing $g $Region
    $g.Dispose()
    return $bmp
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
    $raw     = New-FlagBitmap $Drawing $Size (New-InnerRegion $Size $inset)
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
