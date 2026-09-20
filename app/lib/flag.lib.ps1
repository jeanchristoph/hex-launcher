<#
.SYNOPSIS
    Drapeaux dessinés en GDI+ : un scriptblock par langue du catalogue ($FlagDrawings), rendu dans un Bitmap carré.

.DESCRIPTION
    Chargé par dot-sourcing (tools\make-flag-icons.ps1 pour les fonds d'icônes, icon-badge.lib.ps1 pour les pastilles pays) :
        . (Join-Path $PSScriptRoot 'flag.lib.ps1')

    Une seule définition des drapeaux pour tout le projet : le générateur d'icônes et les pastilles pays suivent
    d'eux-mêmes toute retouche. Aucune dépendance : System.Drawing, natif à Windows.

    La lib est neutre : elle dessine les couleurs déclarées telles quelles. Un appelant peut fournir un résolveur
    à New-FlagBitmap (-ColorResolver { param($Hex) … } → System.Drawing.Color) pour transformer chaque couleur de
    remplissage à la restitution — le générateur y passe la palette réduite (ConvertTo-PaletteColor) ; les pastilles
    pays n'en passent aucun. Les pinceaux de trait (Draw-Line) restent bruts dans les deux cas.

    Chaque scriptblock reçoit $G (Graphics) et $R (zone de dessin : Left/Right/Top/Bottom/Width/Height/Cx/Cy/Size)
    et déborde librement : l'appelant découpe ensuite (carré arrondi du cadre, disque de la pastille).
#>

Add-Type -AssemblyName System.Drawing

# Résolveur de couleur actif, posé par New-FlagBitmap le temps du dessin ; $null → couleur brute
$script:FlagColorResolver = $null

# ---------------------------------------------------------------- Primitives de dessin

function Get-Color([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

# Couleur de remplissage restituée : brute, ou transformée par le résolveur de l'appelant
function Get-FlagColor([string]$Hex) {
    if ($script:FlagColorResolver) { return & $script:FlagColorResolver $Hex }
    return Get-Color $Hex
}

function Get-Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush((Get-FlagColor $Hex))
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
# Couleurs : celles du drapeau, brutes ou passées par le résolveur de l'appelant (Get-FlagColor / Get-Brush).

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

# ---------------------------------------------------------------- Rendu

function Get-FlagCodes {
    return @($FlagDrawings.Keys | Sort-Object)
}

# Dessin d'une langue (ja_JP → scriptblock), $null sans dessin
function Get-FlagDrawing([string]$Code) {
    if ($FlagDrawings.ContainsKey($Code)) { return $FlagDrawings[$Code] }
    return $null
}

# Zone de dessin d'un carré de $Size px, en retrait de $Inset de chaque bord (0 = tout le carré)
function New-FlagRegion([int]$Size, [double]$Inset = 0) {
    return @{
        Left = $Inset; Right = $Size - $Inset; Top = $Inset; Bottom = $Size - $Inset
        Width = $Size - 2 * $Inset; Height = $Size - 2 * $Inset
        Cx = $Size / 2; Cy = $Size / 2
        Size = $Size
    }
}

# Bitmap carré 32 bits du drapeau ; le résolveur, s'il est donné, ne vaut que le temps de ce dessin
function New-FlagBitmap([scriptblock]$Drawing, [int]$Size, $Region, [scriptblock]$ColorResolver = $null) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $previous = $script:FlagColorResolver
    $script:FlagColorResolver = $ColorResolver
    try { & $Drawing $g $Region }
    finally { $script:FlagColorResolver = $previous; $g.Dispose() }
    return $bmp
}
