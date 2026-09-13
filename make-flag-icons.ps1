<#
.SYNOPSIS
    Génère le jeu d'icônes original hex-launcher : ico\hex-launcher.ico (base) et ico\hex-launcher-xx.ico (une par langue de locales.json).

.DESCRIPTION
    Tout est dessiné par code GDI+, sans image source. La base est un carré aux quatre coins biseautés,
    fond bleu nuit en léger dégradé, liseré or sombre doublé d'un fin liseré or, et un H monogramme
    géométrique or au centre (montants évasés en biseaux droits). Les variantes langue composent un
    drapeau simplifié dans la zone intérieure (entre les liserés), sous le H.

    Chaque taille du .ico (256, 128, 64, 48, 32, 16) est dessinée nativement, avec des traits
    légèrement épaissis à 32 et 16 px pour rester lisibles.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Base
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Locales ja_JP,ko_KR -PreviewDir C:\tmp
#>
param(
    # Codes à générer (défaut : tous ceux de locales.json ; aucun si -Base est donné seul)
    [string[]]$Locales,

    # Si fourni, écrit aussi un PNG 256 px par icône dans ce dossier (pour contrôle visuel)
    [string]$PreviewDir,

    # Génère l'icône de base hex-launcher.ico (implicite sans -Locales)
    [switch]$Base
)

Add-Type -AssemblyName System.Drawing

$folder       = $PSScriptRoot
$icoFolder    = Join-Path $folder 'ico'
$IconSizes    = @(256, 128, 64, 48, 32, 16)
$BaseIconName = 'hex-launcher'

$Palette = @{
    Night     = '#0A0E14'
    NightTop  = '#0F1620'
    GoldDark  = '#785A28'
    Gold      = '#C8AA6E'
}

# Géométrie de la base, en fraction du côté de l'icône
$Shape = @{
    Bevel        = 0.18    # coin coupé, mesuré le long du bord
    Border       = 0.04    # liseré or sombre
    InnerBorder  = 0.015   # fin liseré or, à l'intérieur du précédent
    HHeight      = 0.52    # hauteur du H
    HWidth       = 0.48    # largeur du H, évasements compris
    Stem         = 0.105   # largeur d'un montant
    Bar          = 0.085   # hauteur de la barre centrale
    Flare        = 0.03    # débord de l'évasement de chaque côté du montant
    FlareHeight  = 0.045   # hauteur sur laquelle le montant s'évase
    VeilAlpha    = 46      # voile bleu nuit sur le drapeau (0-255) pour garder le H lisible sur les fonds clairs
}

# ---------------------------------------------------------------- Primitives de dessin

function Get-Color([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function Get-Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush((Get-Color $Hex))
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

# Croissant : disque plein + disque de la couleur du fond décalé
function Draw-Crescent($G, [string]$Color, [string]$Background, [double]$Cx, [double]$Cy, [double]$Diameter, [double]$Offset) {
    Draw-Disc $G $Color $Cx $Cy $Diameter
    Draw-Disc $G $Background ($Cx + $Offset) $Cy ($Diameter * 0.8)
}

# ---------------------------------------------------------------- Drapeaux (simplifiés)
# Chaque scriptblock reçoit $G (Graphics) et $R (zone intérieure : Left/Right/Top/Bottom/Width/Height/Cx/Cy/Size).
# Le tracé déborde librement : il est ensuite découpé à l'octogone intérieur de la base.

$FlagDrawings = @{
    'ja_JP' = { param($G, $R)
        $G.Clear([System.Drawing.Color]::White)
        Draw-Disc $G '#BC002D' $R.Cx $R.Cy ($R.Width * 0.75)
    }
    'fr_FR' = { param($G, $R) Draw-VerticalStripes $G $R @('#0055A4', '#FFFFFF', '#EF4135') }
    'en_US' = { param($G, $R)
        $stripes = @(); for ($i = 0; $i -lt 9; $i++) { $stripes += if ($i % 2 -eq 0) { '#B22234' } else { '#FFFFFF' } }
        Draw-HorizontalStripes $G $R $stripes
        $cantonW = $R.Width * 0.55; $cantonH = $R.Height * 4 / 9
        $G.FillRectangle((Get-Brush '#3C3B6E'), 0, 0, [float]($R.Left + $cantonW), [float]($R.Top + $cantonH))
        for ($row = 0; $row -lt 3; $row++) { for ($col = 0; $col -lt 3; $col++) {
            Draw-Disc $G '#FFFFFF' ($R.Left + $cantonW * (0.2 + 0.3 * $col)) ($R.Top + $cantonH * (0.2 + 0.3 * $row)) ($R.Size * 0.02)
        } }
    }
    'en_GB' = { param($G, $R)
        # Centré sur la zone intérieure, tracé sur toute l'image
        Draw-UnionJack $G ($R.Cx - $R.Size) ($R.Cy - $R.Size) ($R.Size * 2) ($R.Size * 2)
    }
    'en_AU' = { param($G, $R)
        $G.Clear((Get-Color '#012169'))
        $cantonW = $R.Width * 0.55; $cantonH = $R.Height * 0.4
        Draw-UnionJack $G 0 0 ($R.Left + $cantonW) ($R.Top + $cantonH)
        $star = $R.Width * 0.09
        Draw-Star $G '#FFFFFF' ($R.Left + $cantonW / 2) ($R.Top + $cantonH * 1.7) ($star * 1.3) 7   # étoile du Commonwealth
        foreach ($p in @(@(0.80, 0.22), @(0.95, 0.45), @(0.72, 0.62), @(0.86, 0.88))) {              # Croix du Sud
            Draw-Star $G '#FFFFFF' ($R.Left + $R.Width * $p[0]) ($R.Top + $R.Height * $p[1]) $star 7
        }
    }
    'en_SG' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#EF3340', '#FFFFFF')
        $cy = $R.Top + $R.Height * 0.25; $d = $R.Height * 0.32
        Draw-Crescent $G '#FFFFFF' '#EF3340' ($R.Left + $R.Width * 0.3) $cy $d ($d * 0.28)
        foreach ($p in @(@(0.62, -0.42), @(0.52, -0.12), @(0.72, -0.12), @(0.56, 0.22), @(0.68, 0.22))) {
            Draw-Star $G '#FFFFFF' ($R.Left + $R.Width * $p[0]) ($cy + $d * $p[1]) ($d * 0.11)
        }
    }
    'en_PH' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#0038A8', '#CE1126')
        $apex = $R.Left + $R.Width * 0.55
        $G.FillPolygon([System.Drawing.Brushes]::White, (New-PointArray @(@(0, 0), @($apex, $R.Cy), @(0, $R.Size))))
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
        $stripes = @(); for ($i = 0; $i -lt 7; $i++) { $stripes += if ($i % 2 -eq 0) { '#CC0001' } else { '#FFFFFF' } }
        Draw-HorizontalStripes $G $R $stripes
        $cantonRight = $R.Left + $R.Width * 0.55; $cantonBottom = $R.Top + $R.Height * 4 / 7
        $G.FillRectangle((Get-Brush '#010066'), 0, 0, [float]$cantonRight, [float]$cantonBottom)
        $cx = ($R.Left + $cantonRight) / 2; $cy = ($R.Top + $cantonBottom) / 2; $d = $R.Width * 0.3
        Draw-Crescent $G '#FFCC00' '#010066' ($cx - $d * 0.15) $cy $d ($d * 0.25)
        Draw-Star $G '#FFCC00' ($cx + $d * 0.42) $cy ($d * 0.3) 14
    }
    'ko_KR' = { param($G, $R)
        $G.Clear([System.Drawing.Color]::White)
        $d = $R.Width * 0.7
        Draw-Disc $G '#0047A0' $R.Cx $R.Cy $d
        $G.FillPie((Get-Brush '#CD2E3A'), [float]($R.Cx - $d / 2), [float]($R.Cy - $d / 2), [float]$d, [float]$d, 180, 180)
        Draw-Disc $G '#CD2E3A' ($R.Cx - $d / 4) $R.Cy ($d / 2)
        Draw-Disc $G '#0047A0' ($R.Cx + $d / 4) $R.Cy ($d / 2)
    }
    'de_DE' = { param($G, $R) Draw-HorizontalStripes $G $R @('#000000', '#DD0000', '#FFCE00') }
    'es_ES' = { param($G, $R) Draw-HorizontalStripes $G $R @('#AA151B', '#F1BF00', '#AA151B') @(1, 2, 1) }
    'es_MX' = { param($G, $R) Draw-VerticalStripes $G $R @('#006847', '#FFFFFF', '#CE1126') }
    'it_IT' = { param($G, $R) Draw-VerticalStripes $G $R @('#009246', '#FFFFFF', '#CE2B37') }
    'pl_PL' = { param($G, $R) Draw-HorizontalStripes $G $R @('#FFFFFF', '#DC143C') }
    'pt_BR' = { param($G, $R)
        $G.Clear((Get-Color '#009C3B'))
        $rw = $R.Width * 0.85; $rh = $R.Height * 0.55
        $rhombus = New-PointArray @(@($R.Cx, ($R.Cy - $rh / 2)), @(($R.Cx + $rw / 2), $R.Cy), @($R.Cx, ($R.Cy + $rh / 2)), @(($R.Cx - $rw / 2), $R.Cy))
        $G.FillPolygon((Get-Brush '#FFDF00'), $rhombus)
        Draw-Disc $G '#002776' $R.Cx $R.Cy ($rh * 0.62)
    }
    'ru_RU' = { param($G, $R) Draw-HorizontalStripes $G $R @('#FFFFFF', '#0039A6', '#D52B1E') }
    'tr_TR' = { param($G, $R)
        $G.Clear((Get-Color '#E30A17'))
        $d = $R.Width * 0.6; $cx = $R.Cx - $R.Width * 0.12
        Draw-Disc $G '#FFFFFF' $cx $R.Cy $d
        Draw-Disc $G '#E30A17' ($cx + $d * 0.2) $R.Cy ($d * 0.8)
        Draw-Star $G '#FFFFFF' ($cx + $d * 0.62) $R.Cy ($d * 0.22)
    }
    'zh_TW' = { param($G, $R)
        $G.Clear((Get-Color '#FE0000'))
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
    'th_TH' = { param($G, $R) Draw-HorizontalStripes $G $R @('#A51931', '#FFFFFF', '#2D2A4A', '#FFFFFF', '#A51931') @(1, 1, 2, 1, 1) }
    'vi_VN' = { param($G, $R)
        $G.Clear((Get-Color '#DA251D'))
        Draw-Star $G '#FFFF00' $R.Cx $R.Cy ($R.Width * 0.38)
    }
    'ar_AE' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#00732F', '#FFFFFF', '#000000')
        $G.FillRectangle((Get-Brush '#FF0000'), 0, 0, [float]($R.Left + $R.Width * 0.25), $R.Size)
    }
}

# ---------------------------------------------------------------- Base : géométrie

# Traits du H épaissis aux petites tailles, sinon ils disparaissent dans l'anticrénelage
function Get-StrokeFactor([int]$Size) {
    switch ($Size) {
        16      { return 1.4 }
        32      { return 1.15 }
        default { return 1.0 }
    }
}

# Épaisseurs en pixels entiers (bords nets) ; les liserés gardent au moins 1 px
function Get-BaseMetrics([int]$Size) {
    $border      = [Math]::Max(1, [Math]::Round($Size * $Shape.Border))
    $innerBorder = [Math]::Max(1, [Math]::Round($Size * $Shape.InnerBorder))
    return @{
        Bevel       = [Math]::Round($Size * $Shape.Bevel)
        Border      = $border
        InnerBorder = $innerBorder
        Inset       = $border + $innerBorder
        Shadow      = [Math]::Max(1, [Math]::Round($Size / 128))
    }
}

# Carré aux coins coupés, rétréci de $Inset par rapport au bord de l'icône (les diagonales reculent de Inset·√2)
function New-OctagonPath([int]$Size, [double]$Inset, [double]$Bevel) {
    $cut = $Bevel + $Inset * ([Math]::Sqrt(2) - 1)
    $a = $Inset; $b = $Size - $Inset
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon((New-PointArray @(
        @(($a + $cut), $a), @(($b - $cut), $a), @($b, ($a + $cut)), @($b, ($b - $cut)),
        @(($b - $cut), $b), @(($a + $cut), $b), @($a, ($b - $cut)), @($a, ($a + $cut)))))
    return $path
}

# Zone intérieure (entre les liserés) transmise aux dessins de drapeaux
function New-InnerRegion([int]$Size, [int]$Inset) {
    return @{
        Left = $Inset; Right = $Size - $Inset; Top = $Inset; Bottom = $Size - $Inset
        Width = $Size - 2 * $Inset; Height = $Size - 2 * $Inset
        Cx = $Size / 2; Cy = $Size / 2
        Size = $Size
    }
}

# Dimensions du H, centrées sur l'icône et arrondies au pixel pour rester symétriques et nettes
function Get-MonogramMetrics([int]$Size) {
    $factor = Get-StrokeFactor $Size
    $center = $Size / 2
    $halfHeight = [Math]::Round($Size * $Shape.HHeight / 2)
    $halfWidth  = [Math]::Round($Size * $Shape.HWidth / 2)
    $stem  = [Math]::Max(1, [Math]::Round($Size * $Shape.Stem * $factor))
    $bar   = [Math]::Max(1, [Math]::Round($Size * $Shape.Bar * $factor))
    $flare = [Math]::Round($Size * $Shape.Flare)
    return @{
        Top         = $center - $halfHeight
        Height      = 2 * $halfHeight
        LeftStem    = $center - $halfWidth + $flare
        RightStem   = $center + $halfWidth - $flare - $stem
        Stem        = $stem
        BarTop      = $center - [Math]::Round($bar / 2)
        Bar         = $bar
        Flare       = $flare
        FlareHeight = [Math]::Round($Size * $Shape.FlareHeight)
    }
}

# Montant vertical évasé en biseaux droits en haut et en bas
function Get-StemPoints([double]$Left, [double]$Top, [double]$Width, [double]$Height, [double]$Flare, [double]$FlareHeight) {
    $right = $Left + $Width; $bottom = $Top + $Height
    return New-PointArray @(
        @(($Left - $Flare), $Top), @(($right + $Flare), $Top), @($right, ($Top + $FlareHeight)),
        @($right, ($bottom - $FlareHeight)), @(($right + $Flare), $bottom), @(($Left - $Flare), $bottom),
        @($Left, ($bottom - $FlareHeight)), @($Left, ($Top + $FlareHeight)))
}

# ---------------------------------------------------------------- Base : dessin

function New-BackgroundBrush([int]$Size) {
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(0, $Size)),
        (Get-Color $Palette.NightTop), (Get-Color $Palette.Night))
    $brush.WrapMode = 'TileFlipXY'   # évite la ligne parasite de la dernière rangée
    return $brush
}

# Liseré or sombre, fin liseré or, puis fond nuit dégradé
function Draw-BaseFrame($G, [int]$Size, $M) {
    $G.FillPath((Get-Brush $Palette.GoldDark), (New-OctagonPath $Size 0 $M.Bevel))
    $G.FillPath((Get-Brush $Palette.Gold), (New-OctagonPath $Size $M.Border $M.Bevel))
    $G.FillPath((New-BackgroundBrush $Size), (New-OctagonPath $Size $M.Inset $M.Bevel))
}

function New-FlagBitmap([scriptblock]$Drawing, [int]$Size, $Region) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    & $Drawing $g $Region
    $g.Dispose()
    return $bmp
}

# Drapeau découpé à l'octogone intérieur (remplissage par texture : bords anticrénelés), puis voilé de bleu nuit
function Draw-FlagLayer($G, [int]$Size, $M, [scriptblock]$Drawing) {
    $flag    = New-FlagBitmap $Drawing $Size (New-InnerRegion $Size $M.Inset)
    $texture = New-Object System.Drawing.TextureBrush($flag)
    $texture.WrapMode = 'Clamp'
    $inner = New-OctagonPath $Size $M.Inset $M.Bevel
    $G.FillPath($texture, $inner)
    $veil = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($Shape.VeilAlpha, (Get-Color $Palette.Night)))
    $G.FillPath($veil, $inner)
    $texture.Dispose(); $flag.Dispose(); $veil.Dispose()
}

# Deux montants évasés + barre centrale (la barre chevauche les montants : aucune couture d'anticrénelage)
function New-MonogramPath($H, [int]$Offset) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.FillMode = 'Winding'   # sinon le chevauchement barre/montants devient un trou
    $path.AddPolygon((Get-StemPoints ($H.LeftStem + $Offset)  ($H.Top + $Offset) $H.Stem $H.Height $H.Flare $H.FlareHeight))
    $path.AddPolygon((Get-StemPoints ($H.RightStem + $Offset) ($H.Top + $Offset) $H.Stem $H.Height $H.Flare $H.FlareHeight))
    $path.AddRectangle((New-Object System.Drawing.RectangleF([float]($H.LeftStem + $Offset), [float]($H.BarTop + $Offset), [float]($H.RightStem + $H.Stem - $H.LeftStem), [float]$H.Bar)))
    return $path
}

# H or, ombre portée bleu nuit décalée d'un pixel (deux à 256 px) et fin liseré bleu nuit : relief sur le fond,
# contraste sur les drapeaux clairs. Le remplissage or final recouvre la moitié intérieure du liseré.
function Draw-MonogramWithShadow($G, [int]$Size, $M) {
    $h = Get-MonogramMetrics $Size
    $G.FillPath((Get-Brush $Palette.Night), (New-MonogramPath $h $M.Shadow))
    $path = New-MonogramPath $h 0
    $pen  = New-Object System.Drawing.Pen((Get-Color $Palette.Night), [float](2 * $M.Shadow))
    $G.DrawPath($pen, $path)
    $G.FillPath((Get-Brush $Palette.Gold), $path)
    $pen.Dispose()
}

# Icône complète à la taille demandée ; $FlagDrawing $null = base seule
function New-BaseIconBitmap([int]$Size, $FlagDrawing) {
    $metrics = Get-BaseMetrics $Size
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    Draw-BaseFrame $g $Size $metrics
    if ($FlagDrawing) { Draw-FlagLayer $g $Size $metrics $FlagDrawing }
    Draw-MonogramWithShadow $g $Size $metrics
    $g.Dispose()
    return $bmp
}

# ---------------------------------------------------------------- Fichier .ico

function ConvertTo-PngBytes([System.Drawing.Bitmap]$Bmp) {
    $ms = New-Object IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()   # la virgule évite que le pipeline déroule le byte[]
}

# Une entrée par taille, chacune dessinée nativement
function New-IconEntries($FlagDrawing) {
    return @(foreach ($size in $IconSizes) {
        [PSCustomObject]@{ Size = $size; Bitmap = (New-BaseIconBitmap $size $FlagDrawing) }
    })
}

# .ico à entrées PNG (supporté depuis Vista) : en-tête 6 o + 16 o par entrée, puis les données
function Write-Ico([object[]]$Entries, [string]$Path) {
    $pngs = @($Entries | ForEach-Object { [PSCustomObject]@{ Size = $_.Size; Bytes = (ConvertTo-PngBytes $_.Bitmap) } })
    $stream = [IO.File]::Create($Path)
    $w = New-Object IO.BinaryWriter($stream)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$pngs.Count)
    $dataOffset = 6 + 16 * $pngs.Count
    foreach ($p in $pngs) {
        $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$p.Bytes.Length); $w.Write([uint32]$dataOffset)
        $dataOffset += $p.Bytes.Length
    }
    foreach ($p in $pngs) { $w.Write($p.Bytes) }
    $w.Dispose(); $stream.Dispose()
}

# ja_JP → hex-launcher-jp.ico (même convention que create-shortcuts.ps1)
function Get-IconFileName([string]$Code) {
    return "$BaseIconName-$($Code.Split('_')[1].ToLower()).ico"
}

function Export-Preview([object[]]$Entries, [string]$IconFileName) {
    $largest = $Entries | Sort-Object Size -Descending | Select-Object -First 1
    $largest.Bitmap.Save((Join-Path $PreviewDir ([IO.Path]::ChangeExtension($IconFileName, 'png'))), [System.Drawing.Imaging.ImageFormat]::Png)
}

function Export-Icon($FlagDrawing, [string]$IconFileName) {
    $entries = New-IconEntries $FlagDrawing
    $target  = Join-Path $icoFolder $IconFileName
    Write-Ico $entries $target
    if ($PreviewDir) { Export-Preview $entries $IconFileName }
    $entries | ForEach-Object { $_.Bitmap.Dispose() }
    return $target
}

# ---------------------------------------------------------------- Main

function Read-LocaleCodes {
    # ForEach-Object déplie le tableau que ConvertFrom-Json (PS 5.1) renvoie comme un seul objet
    return @(Get-Content (Join-Path $folder 'locales.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { $_.code })
}

$codes = if ($Locales) { @($Locales | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ }) }
         elseif ($Base) { @() }
         else { Read-LocaleCodes }

$missing = @($codes | Where-Object { -not $FlagDrawings.ContainsKey($_) })
if ($missing.Count -gt 0) { throw "Pas de dessin de drapeau pour : $($missing -join ', ') — ajouter une entrée dans `$FlagDrawings" }

New-Item -ItemType Directory -Force $icoFolder | Out-Null
if ($PreviewDir) { New-Item -ItemType Directory -Force $PreviewDir | Out-Null }

if ($Base -or -not $Locales) {
    "OK : base → $(Export-Icon $null "$BaseIconName.ico")"
}
foreach ($code in $codes) {
    "OK : $code → $(Export-Icon $FlagDrawings[$code] (Get-IconFileName $code))"
}
