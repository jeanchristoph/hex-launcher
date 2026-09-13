<#
.SYNOPSIS
    Génère ico\league-of-legends-xx.ico pour chaque langue de locales.json : icône LoL avec le drapeau en fond.

.DESCRIPTION
    Part de l'icône officielle Riot (256 px), remplace les pixels à dominante bleue du fond par un
    drapeau simplifié (lisible à 32 px), garde le L et l'anneau dorés, puis écrit un .ico multi-tailles.

    Le drapeau est composé dans la zone du fond réellement visible (entre le bord droit du L et le
    bord droit du cercle intérieur) ; les couleurs de bord sont prolongées jusqu'aux bords de l'image.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Locales ja_JP,ko_KR -PreviewDir C:\tmp
#>
param(
    # Codes à générer (défaut : tous ceux de locales.json)
    [string[]]$Locales,

    # Si fourni, écrit aussi un PNG 256 px par drapeau dans ce dossier (pour contrôle visuel)
    [string]$PreviewDir,

    [string]$SourceIco = (Join-Path $env:ProgramData 'Riot Games\Metadata\league_of_legends.live\league_of_legends.live.ico')
)

Add-Type -AssemblyName System.Drawing

$folder     = $PSScriptRoot
$icoFolder  = Join-Path $folder 'ico'
$IconSizes  = @(256, 128, 64, 48, 32, 16)

# Zone du fond visible, en fraction de la taille (mesurée sur l'icône Riot)
$Visible = @{ Left = 0.453; Right = 0.844; Top = 0.18; Bottom = 0.80 }

# ---------------------------------------------------------------- Primitives de dessin

function Get-Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($Hex))
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
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($Color), [float]$Width)
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
# Chaque scriptblock reçoit $G (Graphics) et $R (zone visible : Left/Right/Top/Bottom/Width/Height/Cx/Cy/Size)

$FlagDrawings = @{
    'ja_JP' = { param($G, $R)
        $G.Clear([System.Drawing.Color]::White)
        Draw-Disc $G '#BC002D' $R.Cx $R.Cy ($R.Width * 0.75)
    }
    'fr_FR' = { param($G, $R)
        # Bleu réduit : le biseau du L le fait paraître plus large
        Draw-VerticalStripes $G $R @('#0055A4', '#FFFFFF', '#EF4135') @(0.75, 1.125, 1.125)
    }
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
        # Centré sur la zone visible, tracé sur toute l'image
        Draw-UnionJack $G ($R.Cx - $R.Size) ($R.Cy - $R.Size) ($R.Size * 2) ($R.Size * 2)
    }
    'en_AU' = { param($G, $R)
        $G.Clear([System.Drawing.ColorTranslator]::FromHtml('#012169'))
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
        $triangle = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(0, 0)),
            (New-Object System.Drawing.PointF([float]$apex, [float]$R.Cy)),
            (New-Object System.Drawing.PointF(0, [float]$R.Size)))
        $G.FillPolygon([System.Drawing.Brushes]::White, $triangle)
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
        $G.Clear([System.Drawing.ColorTranslator]::FromHtml('#009C3B'))
        $rw = $R.Width * 0.85; $rh = $R.Height * 0.55
        $rhombus = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF([float]$R.Cx, [float]($R.Cy - $rh / 2))),
            (New-Object System.Drawing.PointF([float]($R.Cx + $rw / 2), [float]$R.Cy)),
            (New-Object System.Drawing.PointF([float]$R.Cx, [float]($R.Cy + $rh / 2))),
            (New-Object System.Drawing.PointF([float]($R.Cx - $rw / 2), [float]$R.Cy)))
        $G.FillPolygon((Get-Brush '#FFDF00'), $rhombus)
        Draw-Disc $G '#002776' $R.Cx $R.Cy ($rh * 0.62)
    }
    'ru_RU' = { param($G, $R) Draw-HorizontalStripes $G $R @('#FFFFFF', '#0039A6', '#D52B1E') }
    'tr_TR' = { param($G, $R)
        $G.Clear([System.Drawing.ColorTranslator]::FromHtml('#E30A17'))
        $d = $R.Width * 0.6; $cx = $R.Cx - $R.Width * 0.12
        Draw-Disc $G '#FFFFFF' $cx $R.Cy $d
        Draw-Disc $G '#E30A17' ($cx + $d * 0.2) $R.Cy ($d * 0.8)
        Draw-Star $G '#FFFFFF' ($cx + $d * 0.62) $R.Cy ($d * 0.22)
    }
    'zh_TW' = { param($G, $R)
        $G.Clear([System.Drawing.ColorTranslator]::FromHtml('#FE0000'))
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
        $triangle = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(0, 0)),
            (New-Object System.Drawing.PointF([float]($R.Left + $R.Width * 0.5), [float]$R.Cy)),
            (New-Object System.Drawing.PointF(0, [float]$R.Size)))
        $G.FillPolygon((Get-Brush '#11457E'), $triangle)
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
        $G.Clear([System.Drawing.ColorTranslator]::FromHtml('#DA251D'))
        Draw-Star $G '#FFFF00' $R.Cx $R.Cy ($R.Width * 0.38)
    }
    'ar_AE' = { param($G, $R)
        Draw-HorizontalStripes $G $R @('#00732F', '#FFFFFF', '#000000')
        $G.FillRectangle((Get-Brush '#FF0000'), 0, 0, [float]($R.Left + $R.Width * 0.25), $R.Size)
    }
}

# ---------------------------------------------------------------- Composition

# Lecture de l'entrée 256px du .ico (DIB 32bpp, lignes du bas vers le haut) — GDI+ plafonne à 128px sinon
function Read-IcoEntry256([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + $i * 16
        if ($bytes[$entry] -ne 0) { continue }   # 0 = 256px
        $offset = [BitConverter]::ToUInt32($bytes, $entry + 12)
        $width  = [BitConverter]::ToInt32($bytes, $offset + 4)
        $height = [BitConverter]::ToInt32($bytes, $offset + 8) / 2
        $bmp    = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $rect   = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
        $data   = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
        $stride = $width * 4
        for ($y = 0; $y -lt $height; $y++) {
            $srcRow = $offset + 40 + ($height - 1 - $y) * $stride
            [System.Runtime.InteropServices.Marshal]::Copy($bytes, $srcRow, [IntPtr]::Add($data.Scan0, $y * $data.Stride), $stride)
        }
        $bmp.UnlockBits($data)
        return $bmp
    }
    throw "Pas d'entrée 256px dans $Path"
}

function New-VisibleRegion([int]$Size) {
    $left = $Size * $Visible.Left; $right = $Size * $Visible.Right
    $top  = $Size * $Visible.Top;  $bottom = $Size * $Visible.Bottom
    return @{
        Left = $left; Right = $right; Top = $top; Bottom = $bottom
        Width = $right - $left; Height = $bottom - $top
        Cx = ($left + $right) / 2; Cy = ($top + $bottom) / 2
        Size = $Size
    }
}

function New-FlagBitmap([scriptblock]$Drawing, [int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    & $Drawing $g (New-VisibleRegion $Size)
    $g.Dispose()
    return $bmp
}

function Get-Pixels([System.Drawing.Bitmap]$Bmp) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $Bmp.Width, $Bmp.Height)
    $data = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buffer = New-Object byte[] ($data.Stride * $Bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buffer, 0, $buffer.Length)
    $Bmp.UnlockBits($data)
    return $buffer
}

function Set-Pixels([System.Drawing.Bitmap]$Bmp, [byte[]]$Buffer) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $Bmp.Width, $Bmp.Height)
    $data = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [System.Runtime.InteropServices.Marshal]::Copy($Buffer, 0, $data.Scan0, $Buffer.Length)
    $Bmp.UnlockBits($data)
}

# Le fond LoL est bleu-turquoise (B > R), le L et l'anneau sont dorés (R > B).
# On remplace les pixels à dominante bleue par le drapeau, avec un fondu sur la frontière
# et un peu du relief d'origine pour ne pas avoir un aplat mort.
function Merge-FlagIntoBackground([System.Drawing.Bitmap]$Base, [System.Drawing.Bitmap]$FlagBmp) {
    $src  = Get-Pixels $Base
    $flag = Get-Pixels $FlagBmp
    $out  = New-Object byte[] $src.Length
    for ($i = 0; $i -lt $src.Length; $i += 4) {
        $b = $src[$i]; $gr = $src[$i + 1]; $r = $src[$i + 2]; $a = $src[$i + 3]
        if ($a -eq 0) { continue }
        $t = ($b - $r - 5) / 30.0
        if ($t -lt 0) { $t = 0 } elseif ($t -gt 1) { $t = 1 }
        $lum   = (0.299 * $r + 0.587 * $gr + 0.114 * $b) / 255.0
        $shade = [Math]::Min(1.05, 0.8 + 0.35 * $lum)
        $out[$i]     = [byte][Math]::Min(255, $b  * (1 - $t) + $flag[$i]     * $shade * $t)
        $out[$i + 1] = [byte][Math]::Min(255, $gr * (1 - $t) + $flag[$i + 1] * $shade * $t)
        $out[$i + 2] = [byte][Math]::Min(255, $r  * (1 - $t) + $flag[$i + 2] * $shade * $t)
        $out[$i + 3] = $a
    }
    $result = New-Object System.Drawing.Bitmap($Base.Width, $Base.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    Set-Pixels $result $out
    return $result
}

function Resize-Bitmap([System.Drawing.Bitmap]$Bmp, [int]$Size) {
    $r = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($r)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.SmoothingMode     = 'HighQuality'
    $g.PixelOffsetMode   = 'HighQuality'
    $g.DrawImage($Bmp, 0, 0, $Size, $Size)
    $g.Dispose()
    return $r
}

# .ico à entrées PNG (supporté depuis Vista) : en-tête 6 o + 16 o par entrée, puis les données
function Write-Ico([System.Drawing.Bitmap]$Master, [int[]]$Sizes, [string]$Path) {
    $pngs = foreach ($s in $Sizes) {
        $ms = New-Object IO.MemoryStream
        $resized = Resize-Bitmap $Master $s
        $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $resized.Dispose()
        [PSCustomObject]@{ Size = $s; Bytes = $ms.ToArray() }
    }
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

# ja_JP → league-of-legends-jp.ico (même convention que create-shortcuts.ps1)
function Get-IconFileName([string]$Code) {
    return "league-of-legends-$($Code.Split('_')[1].ToLower()).ico"
}

# ---------------------------------------------------------------- Main

if (-not $Locales) {
    # ForEach-Object déplie le tableau que ConvertFrom-Json (PS 5.1) renvoie comme un seul objet
    $Locales = @(Get-Content (Join-Path $folder 'locales.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { $_.code })
}
$Locales = @($Locales | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })

$missing = @($Locales | Where-Object { -not $FlagDrawings.ContainsKey($_) })
if ($missing.Count -gt 0) { throw "Pas de dessin de drapeau pour : $($missing -join ', ') — ajouter une entrée dans `$FlagDrawings" }

New-Item -ItemType Directory -Force $icoFolder | Out-Null
if ($PreviewDir) { New-Item -ItemType Directory -Force $PreviewDir | Out-Null }

$base = Read-IcoEntry256 $SourceIco
foreach ($code in $Locales) {
    $flagBmp = New-FlagBitmap $FlagDrawings[$code] $base.Width
    $merged  = Merge-FlagIntoBackground $base $flagBmp
    $target  = Join-Path $icoFolder (Get-IconFileName $code)
    Write-Ico $merged $IconSizes $target
    if ($PreviewDir) { $merged.Save((Join-Path $PreviewDir "$code.png"), [System.Drawing.Imaging.ImageFormat]::Png) }
    $flagBmp.Dispose(); $merged.Dispose()
    "OK : $code → $target"
}
$base.Dispose()
