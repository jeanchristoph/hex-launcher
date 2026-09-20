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

    Pastille pays : le drapeau de la langue (flag.lib.ps1) dessiné en haute résolution, réduit dans un carré, puis
    découpé au disque inscrit — toutes les couleurs restent visibles, seuls les coins sont perdus — sous le même
    anneau. Couleurs déclarées brutes : ni voile ni palette réduite, il n'y a aucun logo à détacher ici.

    Pastilles empilées (jeu « original-badges », sur l'icône du binaire de League of Legends) : pays en haut à
    droite, compagnon juste en dessous. Sous 32 px une seule pastille subsiste, le pays : c'est lui qui définit
    le raccourci, le compagnon est contextuel.
#>

. (Join-Path $PSScriptRoot 'icon.lib.ps1')
. (Join-Path $PSScriptRoot 'palette.lib.ps1')
. (Join-Path $PSScriptRoot 'flag.lib.ps1')

$BadgeShape = @{
    Diameter     = 0.34    # disque, en fraction du côté de l'icône
    CenterInset  = 0.58    # centre du disque à 0,58 × diamètre du coin haut-droit : la pastille déborde du cadre
    Ring         = 0.02    # anneau bleu nuit autour du disque, en fraction du côté (1 px minimum)
    StackGap     = 0.03    # jour entre deux pastilles empilées, en fraction du côté
    GlyphHeight  = 0.70    # hauteur de la lettre en fraction du diamètre
    GlyphStroke  = 0.02    # contour ajouté à la lettre, en fraction du diamètre : un cran plus gras que le Bold de la police
    GlyphMinSize = 32      # en dessous, disque de couleur seul
    StackMinSize = 32      # en dessous, pastille pays seule dans une pile
}

$FlagBadgeRender = @{
    Scale   = 4     # le drapeau est dessiné à 4 × le diamètre de la pastille avant réduction bicubique
    MinSize = 64    # et jamais sous 64 px, pour que les petits emblèmes restent tracés proprement
}

$BadgePalette = @{
    Ring       = '#0A0E14'   # Night, comme le liseré des icônes
    GlyphLight = '#FFFFFF'   # lettre sur pastille sombre
    GlyphDark  = '#0A0E14'   # lettre sur pastille claire (crème, jaune…)
}
$BadgeLightThreshold = 0.6   # luminance relative au-delà de laquelle la pastille est jugée claire
$BadgeDefaultStyle   = @{ NightVeil = $false; ReducedPalette = $false }

# ---------------------------------------------------------------- Métriques

# Emplacement $Slot : 0 = coin haut-droit, 1 = juste en dessous (pile verticale), chaque rang décalé d'une pastille
# avec son anneau et un jour
function Get-BadgeMetrics([int]$Size, [int]$Slot = 0) {
    $diameter = $Size * $BadgeShape.Diameter
    $ring     = [Math]::Max(1.0, $Size * $BadgeShape.Ring)
    $pitch    = $diameter + 2 * $ring + $Size * $BadgeShape.StackGap
    return @{
        Diameter    = $diameter
        Cx          = $Size - $diameter * $BadgeShape.CenterInset
        Cy          = $diameter * $BadgeShape.CenterInset + $Slot * $pitch
        Ring        = $ring
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

# Dessine la pastille en place sur le bitmap d'une entrée, à l'emplacement demandé
function Add-BadgeToBitmap([System.Drawing.Bitmap]$Bitmap, $Badge, $Style = $BadgeDefaultStyle, [int]$Slot = 0) {
    $metrics = Get-BadgeMetrics $Bitmap.Width $Slot
    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    $g.SmoothingMode = 'AntiAlias'
    Draw-BadgeDisc $g $metrics $Badge.color $Style
    if ($metrics.HasGlyph) { Draw-BadgeGlyph $g $metrics $Badge $Style }
    $g.Dispose()
}

# ---------------------------------------------------------------- Pastille pays (drapeau miniature)

# Drapeau de la langue réduit dans un carré du diamètre de la pastille : dessiné plus grand puis réduit en bicubique,
# pour que les emblèmes (disque, étoiles, croissant) gardent des bords propres même à quelques pixels
function New-FlagBadgeBitmap([string]$Code, [int]$Diameter) {
    $drawing = Get-FlagDrawing $Code
    if (-not $drawing) { throw "Pas de dessin de drapeau pour $Code" }
    $renderSize = [Math]::Max($FlagBadgeRender.MinSize, $Diameter * $FlagBadgeRender.Scale)
    $large = New-FlagBitmap $drawing $renderSize (New-FlagRegion $renderSize)
    try {
        $small = New-Object System.Drawing.Bitmap($Diameter, $Diameter, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($small)
        $g.InterpolationMode = 'HighQualityBicubic'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
        $g.DrawImage($large, 0, 0, $Diameter, $Diameter)
        $g.Dispose()
        return $small
    } finally { $large.Dispose() }
}

# Anneau, puis disque inscrit dans le carré du drapeau (remplissage par texture : bord anticrénelé, coins perdus)
function Draw-FlagBadgeDisc($G, $M, [System.Drawing.Bitmap]$Flag) {
    $outer = $M.Diameter / 2 + $M.Ring
    $left  = [float]($M.Cx - $Flag.Width / 2); $top = [float]($M.Cy - $Flag.Height / 2)
    $ring  = New-Object System.Drawing.SolidBrush((ConvertFrom-HexColor $BadgePalette.Ring))
    $G.FillEllipse($ring, [float]($M.Cx - $outer), [float]($M.Cy - $outer), [float](2 * $outer), [float](2 * $outer))
    $texture = New-Object System.Drawing.TextureBrush($Flag)
    $texture.WrapMode = 'Clamp'
    $texture.TranslateTransform($left, $top)
    $G.FillEllipse($texture, $left, $top, [float]$Flag.Width, [float]$Flag.Height)
    $ring.Dispose(); $texture.Dispose()
}

# Dessine la pastille pays en place sur le bitmap d'une entrée ; sans dessin pour la langue → throw, l'appelant replie
function Add-CountryBadgeToBitmap([System.Drawing.Bitmap]$Bitmap, [string]$Code, [int]$Slot = 0) {
    $metrics  = Get-BadgeMetrics $Bitmap.Width $Slot
    $diameter = [Math]::Max(1, [int][Math]::Round($metrics.Diameter))
    $flag = New-FlagBadgeBitmap $Code $diameter
    try {
        $g = [System.Drawing.Graphics]::FromImage($Bitmap)
        $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.CompositingQuality = 'HighQuality'
        Draw-FlagBadgeDisc $g $metrics $flag
        $g.Dispose()
    } finally { $flag.Dispose() }
}

# BUSINESS_RULE : pile verticale, pays en haut, compagnon en dessous ; sous StackMinSize le pays seul subsiste
function Add-StackedBadgesToBitmap([System.Drawing.Bitmap]$Bitmap, [string]$Code, $Badge, $Style = $BadgeDefaultStyle) {
    Add-CountryBadgeToBitmap $Bitmap $Code 0
    if ($Badge -and $Bitmap.Width -ge $BadgeShape.StackMinSize) { Add-BadgeToBitmap $Bitmap $Badge $Style 1 }
}

# ---------------------------------------------------------------- Empreinte

# 8 caractères hexadécimaux qui changent dès que le rendu change (pastille du catalogue, style, métriques de dessin) :
# nommer l'icône composée avec cette empreinte force Explorer à la relire au lieu de servir son cache d'icônes
function Get-BadgeSignature($Badge, $Style = $BadgeDefaultStyle) {
    $disc  = ConvertTo-HexColor (Get-BadgeColor $Badge.color $Style)
    $glyph = ConvertTo-HexColor (Get-BadgeColor (Get-BadgeGlyphColor $Badge $Style) $Style)
    return ConvertTo-RenderSignature "$($Badge.glyph)|$disc|$glyph|$(Get-BadgeShapeKey)"
}

# Empreinte d'une pile pays + compagnon : le texte du dessin du drapeau en fait partie, une retouche du drapeau
# change donc le nom du fichier composé — sans compagnon, la pile ne porte que le pays
function Get-StackedBadgeSignature([string]$Code, $Badge, $Style = $BadgeDefaultStyle) {
    $drawing   = if (Get-FlagDrawing $Code) { (Get-FlagDrawing $Code).ToString() } else { '' }
    $companion = if ($Badge) { Get-BadgeSignature $Badge $Style } else { 'none' }
    $render    = ($FlagBadgeRender.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
    return ConvertTo-RenderSignature "$Code|$drawing|$companion|$render|$(Get-BadgeShapeKey)"
}

function Get-BadgeShapeKey {
    return ($BadgeShape.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
}

# 8 caractères hexadécimaux (SHA-1 tronqué) d'une description de rendu, insensible à la casse
function ConvertTo-RenderSignature([string]$Source) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Source.ToLowerInvariant())) }
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

# Icône d'un binaire (lue en mémoire, jamais copiée) + pastille pays + pastille compagnon éventuelle → icône de
# destination : le seul fichier dérivé, local au poste (ico\<jeu>\companion, hors dépôt et hors release)
function Add-StackedBadgesToExecutableIcon([string]$ExecutablePath, [string]$Code, $Badge, [string]$DestinationIco, $Style = $BadgeDefaultStyle) {
    if ($Badge -and [string]::IsNullOrWhiteSpace($Badge.color)) { throw "Pastille compagnon invalide : couleur manquante" }
    $entries = Read-ExecutableIconEntries $ExecutablePath
    try {
        foreach ($entry in $entries) { Add-StackedBadgesToBitmap $entry.Bitmap $Code $Badge $Style }
        Write-Ico $entries $DestinationIco
    }
    finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
    return $DestinationIco
}
