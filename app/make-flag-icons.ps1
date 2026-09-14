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

    Le traitement du H est choisi par -Style parmi les presets de $MonogramStyles (proportions, empattements,
    finition or plat ou métallique, arêtes biseautées, profondeur d'ombre). L'octogone et le tracé
    géométrique en polygones sont communs à tous les styles.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Base
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Locales ja_JP,ko_KR -PreviewDir C:\tmp
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Style metal-serif
#>
param(
    # Codes à générer (défaut : tous ceux de locales.json ; aucun si -Base est donné seul)
    [string[]]$Locales,

    # Si fourni, écrit aussi un PNG 256 px par icône dans ce dossier (pour contrôle visuel)
    [string]$PreviewDir,

    # Génère l'icône de base hex-launcher.ico (implicite sans -Locales)
    [switch]$Base,

    # Preset de traitement du monogramme (voir $MonogramStyles)
    [ValidateSet('sobre', 'serif-marque', 'metal', 'metal-serif', 'elegant-etroit')]
    [string]$Style = 'sobre',

    # Dossier de sortie des .ico (défaut : ico\ à côté du script)
    [string]$OutDir
)

Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'lib\icon.lib.ps1')

$folder       = $PSScriptRoot
$icoFolder    = if ($OutDir) { $OutDir } else { Join-Path $folder 'ico' }
$IconSizes    = @(256, 128, 64, 48, 32, 16)
$BaseIconName = 'hex-launcher'

$Palette = @{
    Night     = '#0A0E14'
    NightTop  = '#0F1620'
    GoldShade = '#463714'   # arête inférieure des formes biseautées
    GoldDark  = '#785A28'
    Gold      = '#C8AA6E'
    GoldLight = '#F0E6D2'   # crème : haut du dégradé métallique et arête supérieure
}

# Géométrie de la base, en fraction du côté de l'icône
$Shape = @{
    Bevel        = 0.18    # coin coupé, mesuré le long du bord
    Border       = 0.04    # liseré or sombre
    InnerBorder  = 0.015   # fin liseré or, à l'intérieur du précédent
    SerifGapMin  = 0.08    # écart minimal entre les empattements des deux montants (sinon on réduit le débord)
    VeilAlpha    = 46      # voile bleu nuit sur le drapeau (0-255) pour garder le H lisible sur les fonds clairs
    ShadowAlpha  = 150     # opacité de l'ombre portée du H quand elle dépasse du liseré
}

# Presets du monogramme, du plus proche de l'original au plus travaillé. Cotes en fraction du côté de l'icône.
#   HHeight/HWidth : encombrement du H, empattements compris · Stem/Bar : montant et barre centrale
#   BarBelt : hauteur de la barre en son centre (« ceinture », = Bar pour une barre droite)
#   Flare/FlareHeight : débord et hauteur de l'empattement · SerifLip : lèvre verticale au bout de l'empattement, avant le biseau
#   IsMetallic : dégradé vertical crème → or → or sombre (deux tons à 32 et 16 px) au lieu d'un or plat
#   HasBevelEdges : arête claire sur les bords supérieurs, sombre sur les inférieurs (jamais à 32 et 16 px)
#   HasDropShadow : ombre portée visible au-delà du liseré bleu nuit (2 px à 256, 1 px en dessous)
$MonogramStyles = [ordered]@{
    'sobre' = @{            # rendu d'origine : H géométrique or plat, évasements discrets
        HHeight = 0.52; HWidth = 0.48; Stem = 0.105; Bar = 0.085; BarBelt = 0.085
        Flare = 0.03; FlareHeight = 0.045; SerifLip = 0
        IsMetallic = $false; HasBevelEdges = $false; HasDropShadow = $false
    }
    'serif-marque' = @{     # empattements larges à lèvre et biseau, barre ceinturée, or plat
        HHeight = 0.56; HWidth = 0.52; Stem = 0.095; Bar = 0.08; BarBelt = 0.10
        Flare = 0.06; FlareHeight = 0.06; SerifLip = 0.02
        IsMetallic = $false; HasBevelEdges = $false; HasDropShadow = $false
    }
    'metal' = @{            # proportions d'origine, or métallique biseauté et ombre profonde
        HHeight = 0.52; HWidth = 0.48; Stem = 0.105; Bar = 0.085; BarBelt = 0.085
        Flare = 0.03; FlareHeight = 0.045; SerifLip = 0
        IsMetallic = $true; HasBevelEdges = $true; HasDropShadow = $true
    }
    'metal-serif' = @{      # empattements marqués + or métallique biseauté + ombre profonde, lettre plus haute
        HHeight = 0.58; HWidth = 0.52; Stem = 0.095; Bar = 0.08; BarBelt = 0.10
        Flare = 0.06; FlareHeight = 0.06; SerifLip = 0.02
        IsMetallic = $true; HasBevelEdges = $true; HasDropShadow = $true
    }
    'elegant-etroit' = @{   # même traitement, lettre plus haute et plus étroite, fûts fins
        HHeight = 0.60; HWidth = 0.46; Stem = 0.085; Bar = 0.07; BarBelt = 0.09
        Flare = 0.055; FlareHeight = 0.06; SerifLip = 0.015
        IsMetallic = $true; HasBevelEdges = $true; HasDropShadow = $true
    }
}
$MonogramStyle = $MonogramStyles[$Style]

# ---------------------------------------------------------------- Primitives de dessin

function Get-Color([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function Get-Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush((Get-Color $Hex))
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
    $unit = [Math]::Max(1, [Math]::Round($Size / 128))   # 2 px à 256, 1 px en dessous
    return @{
        Bevel       = [Math]::Round($Size * $Shape.Bevel)
        Border      = $border
        InnerBorder = $innerBorder
        Inset       = $border + $innerBorder
        Outline     = $unit   # demi-largeur du liseré bleu nuit autour du H
        Shadow      = $unit   # profondeur de l'ombre portée visible au-delà du liseré
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

# Débord d'empattement en pixels, réduit tant que les empattements des deux montants ne laissent pas l'écart minimal
# (à 16 px il tombe à 0 : le H redevient un H droit, plus lisible)
function Get-FlareWidth([int]$Size, [int]$Width, [int]$Stem, [double]$Flare) {
    $pixels = [Math]::Round($Size * $Flare)
    $minGap = [Math]::Max(2, [Math]::Round($Size * $Shape.SerifGapMin))
    while ($pixels -gt 0 -and ($Width - 2 * $Stem - 4 * $pixels) -lt $minGap) { $pixels-- }
    return $pixels
}

# Dimensions du H, centrées sur l'icône et arrondies au pixel pour rester symétriques et nettes
function Get-MonogramMetrics([int]$Size, $Style) {
    $factor = Get-StrokeFactor $Size
    $center = $Size / 2
    $halfHeight  = [Math]::Round($Size * $Style.HHeight / 2)
    $halfWidth   = [Math]::Round($Size * $Style.HWidth / 2)
    $stem        = [Math]::Max(1, [Math]::Round($Size * $Style.Stem * $factor))
    $bar         = [Math]::Max(1, [Math]::Round($Size * $Style.Bar * $factor))
    $flare       = Get-FlareWidth $Size (2 * $halfWidth) $stem $Style.Flare
    $flareHeight = [Math]::Round($Size * $Style.FlareHeight)
    $leftStem    = $center - $halfWidth + $flare
    $rightStem   = $center + $halfWidth - $flare - $stem
    return @{
        Top         = $center - $halfHeight
        Height      = 2 * $halfHeight
        LeftStem    = $leftStem
        RightStem   = $rightStem
        Stem        = $stem
        BarTop      = $center - [Math]::Round($bar / 2)
        Bar         = $bar
        Belt        = [Math]::Round($Size * ($Style.BarBelt - $Style.Bar) / 2)   # surépaisseur de la barre au centre, par côté
        BeltRun     = [Math]::Round(($rightStem - $leftStem - $stem) * 0.3)      # longueur du biseau de la ceinture
        Flare       = $flare
        FlareHeight = $flareHeight
        SerifLip    = [Math]::Min([Math]::Round($Size * $Style.SerifLip), [Math]::Max(0, $flareHeight - 1))
    }
}

# Montant vertical à empattements haut et bas : lèvre verticale puis biseau droit vers le fût. Sens horaire.
function Get-StemPolygon([double]$Left, [double]$Top, $H) {
    $right = $Left + $H.Stem; $bottom = $Top + $H.Height
    $f = $H.Flare; $fh = $H.FlareHeight; $lip = $H.SerifLip
    return New-PointArray @(
        @(($Left - $f), $Top), @(($right + $f), $Top), @(($right + $f), ($Top + $lip)), @($right, ($Top + $fh)),
        @($right, ($bottom - $fh)), @(($right + $f), ($bottom - $lip)), @(($right + $f), $bottom),
        @(($Left - $f), $bottom), @(($Left - $f), ($bottom - $lip)), @($Left, ($bottom - $fh)),
        @($Left, ($Top + $fh)), @(($Left - $f), ($Top + $lip)))
}

# Barre centrale « ceinturée » : un peu plus épaisse au centre, transition en biseau droit. Sens horaire.
# $Overlap prolonge la barre sous les montants (remplissage sans couture) ; 0 pour ne garder que la partie visible.
function Get-BarPolygon($H, [int]$Offset, [int]$Overlap) {
    $innerLeft = $H.LeftStem + $H.Stem + $Offset; $innerRight = $H.RightStem + $Offset
    $top = $H.BarTop + $Offset; $bottom = $top + $H.Bar
    $d = $H.Belt; $k = $H.BeltRun
    return New-PointArray @(
        @(($innerLeft - $Overlap), $top), @($innerLeft, $top), @(($innerLeft + $k), ($top - $d)),
        @(($innerRight - $k), ($top - $d)), @($innerRight, $top), @(($innerRight + $Overlap), $top),
        @(($innerRight + $Overlap), $bottom), @($innerRight, $bottom), @(($innerRight - $k), ($bottom + $d)),
        @(($innerLeft + $k), ($bottom + $d)), @($innerLeft, $bottom), @(($innerLeft - $Overlap), $bottom))
}

# Les trois polygones du H ; la barre chevauche les montants sauf si $VisibleOnly (arêtes du biseau)
function Get-MonogramPolygons($H, [int]$Offset, [switch]$VisibleOnly) {
    $overlap = if ($VisibleOnly) { 0 } else { $H.Stem }
    return @(
        (Get-StemPolygon ($H.LeftStem + $Offset)  ($H.Top + $Offset) $H),
        (Get-StemPolygon ($H.RightStem + $Offset) ($H.Top + $Offset) $H),
        (Get-BarPolygon $H $Offset $overlap))
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

# Deux montants à empattements + barre centrale (la barre chevauche les montants : aucune couture d'anticrénelage)
function New-MonogramPath($H, [int]$Offset) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.FillMode = 'Winding'   # sinon le chevauchement barre/montants devient un trou
    foreach ($polygon in (Get-MonogramPolygons $H $Offset)) { $path.AddPolygon($polygon) }
    return $path
}

# Aux petites tailles le dégradé se réduit à deux tons pour que le H reste net
function Get-GoldGradientStops([int]$Size) {
    if ($Size -le 32) {
        return @{
            Colors    = @((Get-BlendedColor $Palette.GoldLight $Palette.Gold 0.5), (Get-BlendedColor $Palette.Gold $Palette.GoldDark 0.5))
            Positions = @(0.0, 1.0)
        }
    }
    return @{
        Colors    = @((Get-Color $Palette.GoldLight), (Get-Color $Palette.Gold), (Get-Color $Palette.GoldDark))
        Positions = @(0.0, 0.5, 1.0)
    }
}

# Or métallique : dégradé vertical sur la hauteur du H
function New-MetallicGoldBrush($H, [int]$Size) {
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, [float]$H.Top)), (New-Object System.Drawing.PointF(0, [float]($H.Top + $H.Height))),
        (Get-Color $Palette.GoldLight), (Get-Color $Palette.GoldDark))
    $brush.WrapMode = 'TileFlipXY'   # évite la ligne parasite aux extrémités du dégradé
    $stops = Get-GoldGradientStops $Size
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend
    $blend.Colors    = [System.Drawing.Color[]]$stops.Colors
    $blend.Positions = [float[]]$stops.Positions
    $brush.InterpolationColors = $blend
    return $brush
}

function New-GoldBrush($H, [int]$Size, $Style) {
    if ($Style.IsMetallic) { return New-MetallicGoldBrush $H $Size }
    return Get-Brush $Palette.Gold
}

# Épaisseur des arêtes du biseau : 2 px à 256, 1 px de 128 à 48, aucune à 32 et 16 (elles brouilleraient le H)
function Get-BevelWidth([int]$Size) {
    if ($Size -le 32) { return 0 }
    return [Math]::Max(1, [Math]::Round($Size / 128))
}

# Arêtes d'un polygone horaire (axe y vers le bas) : dx > 0 = bord qui regarde vers le haut, éclairé ;
# dx < 0 = bord qui regarde vers le bas, ombré ; les bords verticaux ne reçoivent rien
function Get-BevelEdges([System.Drawing.PointF[]]$Polygon) {
    for ($i = 0; $i -lt $Polygon.Count; $i++) {
        $a = $Polygon[$i]; $b = $Polygon[($i + 1) % $Polygon.Count]
        $dx = $b.X - $a.X
        if ([Math]::Abs($dx) -lt 0.5) { continue }
        @{ A = $a; B = $b; IsLit = ($dx -gt 0) }
    }
}

# Trait d'arête entièrement à l'intérieur de la forme : décalé d'une demi-épaisseur le long de la normale
# intérieure et raccourci d'autant à chaque bout (tous les angles du H sont ≥ 90°, le trait ne déborde pas)
function Draw-BevelEdge($G, $Edge, [int]$Width) {
    $dx = $Edge.B.X - $Edge.A.X; $dy = $Edge.B.Y - $Edge.A.Y
    $length = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $ux = $dx / $length * $Width / 2; $uy = $dy / $length * $Width / 2
    $nx = -$uy; $ny = $ux   # normale intérieure d'un polygone horaire
    $color = if ($Edge.IsLit) { $Palette.GoldLight } else { $Palette.GoldShade }
    Draw-Line $G $color $Width ($Edge.A.X + $nx + $ux) ($Edge.A.Y + $ny + $uy) ($Edge.B.X + $nx - $ux) ($Edge.B.Y + $ny - $uy)
}

function Draw-MonogramBevel($G, $H, [int]$Size) {
    $width = Get-BevelWidth $Size
    if ($width -eq 0) { return }
    foreach ($polygon in (Get-MonogramPolygons $H 0 -VisibleOnly)) {
        foreach ($edge in (Get-BevelEdges $polygon)) { Draw-BevelEdge $G $edge $width }
    }
}

# Ombre portée bleu nuit : cachée sous le liseré (décalage = Outline) ou visible au-delà (Outline + Shadow)
function Draw-MonogramShadow($G, $H, $M, $Style) {
    if (-not $Style.HasDropShadow) {
        $G.FillPath((Get-Brush $Palette.Night), (New-MonogramPath $H $M.Outline))
        return
    }
    $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($Shape.ShadowAlpha, (Get-Color $Palette.Night)))
    $G.FillPath($shadow, (New-MonogramPath $H ($M.Outline + $M.Shadow)))
    $shadow.Dispose()
}

# H or, ombre portée bleu nuit et fin liseré bleu nuit : relief sur le fond, contraste sur les drapeaux clairs.
# Le remplissage or recouvre la moitié intérieure du liseré ; les arêtes du biseau viennent en dernier.
function Draw-MonogramWithShadow($G, [int]$Size, $M, $Style) {
    $h = Get-MonogramMetrics $Size $Style
    Draw-MonogramShadow $G $h $M $Style
    $path = New-MonogramPath $h 0
    $pen  = New-Object System.Drawing.Pen((Get-Color $Palette.Night), [float](2 * $M.Outline))
    $G.DrawPath($pen, $path)
    $gold = New-GoldBrush $h $Size $Style
    $G.FillPath($gold, $path)
    if ($Style.HasBevelEdges) { Draw-MonogramBevel $G $h $Size }
    $pen.Dispose(); $gold.Dispose()
}

# Icône complète à la taille demandée ; $FlagDrawing $null = base seule
function New-BaseIconBitmap([int]$Size, $FlagDrawing, $Style = $MonogramStyle) {
    $metrics = Get-BaseMetrics $Size
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    Draw-BaseFrame $g $Size $metrics
    if ($FlagDrawing) { Draw-FlagLayer $g $Size $metrics $FlagDrawing }
    Draw-MonogramWithShadow $g $Size $metrics $Style
    $g.Dispose()
    return $bmp
}

# ---------------------------------------------------------------- Fichier .ico (écriture : lib\icon.lib.ps1)

# Une entrée par taille, chacune dessinée nativement
function New-IconEntries($FlagDrawing) {
    return @(foreach ($size in $IconSizes) {
        [PSCustomObject]@{ Size = $size; Bitmap = (New-BaseIconBitmap $size $FlagDrawing) }
    })
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
