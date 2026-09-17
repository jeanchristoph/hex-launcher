<#
.SYNOPSIS
    Pastille compagnon sur une icône : disque de couleur et lettre en haut à droite, à toutes les tailles du .ico.

.DESCRIPTION
    Chargé par dot-sourcing depuis create-shortcuts.ps1 :
        . (Join-Path $PSScriptRoot 'lib\icon-badge.lib.ps1')

    La pastille est dessinée par code GDI+ (aucun visuel tiers) sur chaque entrée de l'icône drapeau, avec des
    métriques en fraction du côté, comme $Frame dans tools\make-flag-icons.ps1. Sous 32 px la lettre est omise :
    la couleur seule différencie l'appli compagnon. Les couleurs du catalogue (disque, lettre) sont gardées telles
    quelles ; le style (badge-style.json du jeu d'icônes) peut les ramener à la palette réduite des drapeaux
    (ReducedPalette) et/ou les passer sous leur voile bleu nuit (NightVeil) — palette.lib.ps1.
#>

. (Join-Path $PSScriptRoot 'icon.lib.ps1')
. (Join-Path $PSScriptRoot 'palette.lib.ps1')

$BadgeShape = @{
    Diameter     = 0.34    # disque, en fraction du côté de l'icône
    CenterInset  = 0.58    # centre du disque à 0,58 × diamètre du coin haut-droit : la pastille déborde du cadre
    Ring         = 0.02    # anneau bleu nuit autour du disque, en fraction du côté (1 px minimum)
    GlyphHeight  = 0.70    # hauteur de la lettre en fraction du diamètre
    GlyphStroke  = 0.02    # contour ajouté à la lettre, en fraction du diamètre : un cran plus gras que le Bold de la police
    GlyphMinSize = 32      # en dessous, disque de couleur seul
}

$BadgePalette = @{
    Ring       = '#0A0E14'   # Night, comme le liseré des icônes
    GlyphLight = '#FFFFFF'   # lettre sur pastille sombre
    GlyphDark  = '#0A0E14'   # lettre sur pastille claire (crème, jaune…)
}
$BadgeLightThreshold = 0.6   # luminance relative au-delà de laquelle la pastille est jugée claire
$BadgeDefaultStyle   = @{ NightVeil = $false; ReducedPalette = $false }

# ---------------------------------------------------------------- Métriques

function Get-BadgeMetrics([int]$Size) {
    $diameter = $Size * $BadgeShape.Diameter
    return @{
        Diameter    = $diameter
        Cx          = $Size - $diameter * $BadgeShape.CenterInset
        Cy          = $diameter * $BadgeShape.CenterInset
        Ring        = [Math]::Max(1.0, $Size * $BadgeShape.Ring)
        GlyphHeight = $diameter * $BadgeShape.GlyphHeight
        GlyphStroke = $diameter * $BadgeShape.GlyphStroke
        HasGlyph    = $Size -ge $BadgeShape.GlyphMinSize
    }
}

# Couleur restituée : celle du catalogue, ramenée à la palette réduite puis voilée selon le style
function Get-BadgeColor([string]$Hex, $Style = $BadgeDefaultStyle) {
    $color = if ($Style.ReducedPalette) { ConvertTo-PaletteColor $Hex } else { ConvertFrom-HexColor $Hex }
    if ($Style.NightVeil) { return ConvertTo-VeiledColor $color }
    return $color
}

# Luminance relative (0 = noir, 1 = blanc) de la couleur restituée, pondération Rec. 601
function Get-BadgeLuminance([string]$Hex, $Style = $BadgeDefaultStyle) {
    $c = Get-BadgeColor $Hex $Style
    return (0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) / 255
}

# Couleur de lettre du catalogue si donnée ; sinon sombre sur pastille claire, claire sur pastille sombre
function Get-BadgeGlyphColor($Badge, $Style = $BadgeDefaultStyle) {
    if (-not [string]::IsNullOrWhiteSpace($Badge.glyphColor)) { return $Badge.glyphColor }
    if ((Get-BadgeLuminance $Badge.color $Style) -gt $BadgeLightThreshold) { return $BadgePalette.GlyphDark }
    return $BadgePalette.GlyphLight
}

# ---------------------------------------------------------------- Dessin

function Draw-BadgeDisc($G, $M, [string]$Color, $Style) {
    $outer = $M.Diameter / 2 + $M.Ring
    $inner = $M.Diameter / 2
    $ring  = New-Object System.Drawing.SolidBrush((Get-BadgeColor $BadgePalette.Ring $Style))
    $disc  = New-Object System.Drawing.SolidBrush((Get-BadgeColor $Color $Style))
    $G.FillEllipse($ring, [float]($M.Cx - $outer), [float]($M.Cy - $outer), [float](2 * $outer), [float](2 * $outer))
    $G.FillEllipse($disc, [float]($M.Cx - $inner), [float]($M.Cy - $inner), [float](2 * $inner), [float](2 * $inner))
    $ring.Dispose(); $disc.Dispose()
}

# Tracé vectoriel de la lettre, centré sur ses propres bornes : DrawString centrerait la cellule, pas le dessin
function New-BadgeGlyphPath([string]$Glyph, $M) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString($Glyph, [System.Drawing.FontFamily]::GenericSansSerif, [int][System.Drawing.FontStyle]::Bold,
                    [float]$M.GlyphHeight, (New-Object System.Drawing.PointF(0, 0)), [System.Drawing.StringFormat]::GenericTypographic)
    $bounds = $path.GetBounds()
    $matrix = New-Object System.Drawing.Drawing2D.Matrix
    $matrix.Translate([float]($M.Cx - $bounds.X - $bounds.Width / 2), [float]($M.Cy - $bounds.Y - $bounds.Height / 2))
    $path.Transform($matrix)
    $matrix.Dispose()
    return $path
}

# Remplissage + contour de même couleur : le contour épaissit la lettre sans changer de police
function Draw-BadgeGlyph($G, $M, $Badge, $Style) {
    $path  = New-BadgeGlyphPath $Badge.glyph $M
    $color = Get-BadgeColor (Get-BadgeGlyphColor $Badge $Style) $Style
    $brush = New-Object System.Drawing.SolidBrush($color)
    $pen   = New-Object System.Drawing.Pen($color, [float]$M.GlyphStroke)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $G.FillPath($brush, $path)
    $G.DrawPath($pen, $path)
    $pen.Dispose(); $brush.Dispose(); $path.Dispose()
}

# Dessine la pastille en place sur le bitmap d'une entrée
function Add-BadgeToBitmap([System.Drawing.Bitmap]$Bitmap, $Badge, $Style = $BadgeDefaultStyle) {
    $metrics = Get-BadgeMetrics $Bitmap.Width
    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    $g.SmoothingMode = 'AntiAlias'
    Draw-BadgeDisc $g $metrics $Badge.color $Style
    if ($metrics.HasGlyph) { Draw-BadgeGlyph $g $metrics $Badge $Style }
    $g.Dispose()
}

# ---------------------------------------------------------------- Empreinte

# 8 caractères hexadécimaux qui changent dès que le rendu change (pastille du catalogue, style, métriques de dessin) :
# nommer l'icône composée avec cette empreinte force Explorer à la relire au lieu de servir son cache d'icônes
function Get-BadgeSignature($Badge, $Style = $BadgeDefaultStyle) {
    $shape = ($BadgeShape.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
    $disc  = ConvertTo-HexColor (Get-BadgeColor $Badge.color $Style)
    $glyph = ConvertTo-HexColor (Get-BadgeColor (Get-BadgeGlyphColor $Badge $Style) $Style)
    $source = "$($Badge.glyph)|$disc|$glyph|$shape"
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source.ToLowerInvariant())) }
    finally { $sha.Dispose() }
    return (($hash[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
}

# ---------------------------------------------------------------- Composition

# Icône source + pastille → icône de destination, toutes tailles conservées
function Add-CompanionBadge([string]$SourceIco, $Badge, [string]$DestinationIco, $Style = $BadgeDefaultStyle) {
    if (-not $Badge -or [string]::IsNullOrWhiteSpace($Badge.color)) { throw "Pastille compagnon invalide : couleur manquante" }
    $entries = Read-IcoEntries $SourceIco
    try {
        foreach ($entry in $entries) { Add-BadgeToBitmap $entry.Bitmap $Badge $Style }
        Write-Ico $entries $DestinationIco
    }
    finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
    return $DestinationIco
}
