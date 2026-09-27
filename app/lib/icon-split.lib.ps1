<#
.SYNOPSIS
    Icône coupée en diagonale : langue des voix en haut à gauche, langue du texte en bas à droite, trait noir entre les deux.

.DESCRIPTION
    Chargé par dot-sourcing (icon-badge.lib.ps1, create-shortcuts.ps1) :
        . (Join-Path $PSScriptRoot 'lib\icon-split.lib.ps1')

    La diagonale va du coin bas-gauche au coin haut-droit. Le trait est tracé puis ramené à l'alpha de l'image sur
    sa seule bande : il s'arrête net au bord du cadre, sans noircir les coins transparents, quel que soit le jeu
    d'icônes. Sert aux icônes .ico des jeux de fichiers (flat, classic) et à la pastille pays (original-badges).

    Logo et cadre au-dessus du trait (jeux de fichiers) : ils sont repérés en comparant les deux icônes de base du jeu,
    fond bleu et fond vert — ce qui ne change pas d'une couleur de fond à l'autre est le premier plan. Sur la bande du
    trait, ces pixels reprennent leur valeur d'avant le trait, avec un bord adouci entre les deux seuils de
    $DiagonalSplit (classic : les deux icônes de base ne sont pas identiques au pixel près).
#>

Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'icon.lib.ps1')

$DiagonalSplit = @{
    LineWidth    = 0.04   # trait, en fraction du côté
    MinLineWidth = 1.0    # px : le trait reste visible à 16 px
    LineColor    = '#000000'
    ForegroundTolerance = 40   # écart R+G+B entre les deux fonds sous lequel un pixel est tout premier plan
    BackgroundTolerance = 90   # écart au-dessus duquel il est tout fond ; entre les deux, fondu
}

$ArgbBytesPerPixel = 4
$ArgbAlphaOffset   = 3   # Format32bppArgb : B, G, R, A

# Triangle au-dessus de la diagonale bas-gauche → haut-droit
function New-UpperTrianglePath([int]$Width, [int]$Height) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon([System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(0, 0), [System.Drawing.PointF]::new($Width, 0), [System.Drawing.PointF]::new(0, $Height)))
    return $path
}

function Get-DiagonalLineWidth([int]$Size) {
    return [Math]::Max($DiagonalSplit.MinLineWidth, $Size * $DiagonalSplit.LineWidth)
}

function Read-ArgbPixels([System.Drawing.Bitmap]$Bitmap) {
    $area = New-Object System.Drawing.Rectangle(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits($area, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $pixels = New-Object byte[] ($data.Stride * $Bitmap.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        return [pscustomobject]@{ Bytes = $pixels; Stride = $data.Stride }
    }
    finally { $Bitmap.UnlockBits($data) }
}

function Write-ArgbPixels([System.Drawing.Bitmap]$Bitmap, [byte[]]$Pixels) {
    $area = New-Object System.Drawing.Rectangle(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits($area, 'WriteOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try { [Runtime.InteropServices.Marshal]::Copy($Pixels, 0, $data.Scan0, $Pixels.Length) }
    finally { $Bitmap.UnlockBits($data) }
}

# Part de premier plan d'un pixel (0 à 1) : écart R+G+B du même pixel entre les deux icônes de base
function Get-ForegroundWeight($Foreground, [int]$At) {
    $first = $Foreground.First.Bytes; $second = $Foreground.Second.Bytes
    if ($first[$At + $ArgbAlphaOffset] -eq 0 -and $second[$At + $ArgbAlphaOffset] -eq 0) { return 0.0 }
    $gap = [Math]::Abs($first[$At] - $second[$At]) + [Math]::Abs($first[$At + 1] - $second[$At + 1]) + [Math]::Abs($first[$At + 2] - $second[$At + 2])
    if ($gap -le $DiagonalSplit.ForegroundTolerance) { return 1.0 }
    if ($gap -ge $DiagonalSplit.BackgroundTolerance) { return 0.0 }
    return ($DiagonalSplit.BackgroundTolerance - $gap) / ($DiagonalSplit.BackgroundTolerance - $DiagonalSplit.ForegroundTolerance)
}

# Premier plan d'un pixel du trait : sa valeur d'avant le trait revient à proportion de son poids
function Restore-ForegroundPixel([byte[]]$After, [byte[]]$Before, [int]$At, [double]$Weight) {
    for ($channel = 0; $channel -lt $ArgbBytesPerPixel; $channel++) {
        $After[$At + $channel] = [byte][Math]::Round($After[$At + $channel] * (1 - $Weight) + $Before[$At + $channel] * $Weight)
    }
}

# Bande du trait, repassée pixel par pixel : l'alpha ne dépasse jamais celui d'avant le trait (pas de noir hors du
# cadre) et, si $Foreground est fourni, le premier plan reprend sa valeur d'avant le trait
function Complete-DiagonalBand([System.Drawing.Bitmap]$Bitmap, $Before, $Foreground) {
    $after = Read-ArgbPixels $Bitmap
    $width = $Bitmap.Width; $height = $Bitmap.Height
    $reach = [int][Math]::Ceiling((Get-DiagonalLineWidth $width) * [Math]::Sqrt(2)) + 2
    for ($y = 0; $y -lt $height; $y++) {
        $center = [int](($height - $y) * $width / $height) - 1
        for ($x = [Math]::Max(0, $center - $reach); $x -le [Math]::Min($width - 1, $center + $reach); $x++) {
            $at = $y * $after.Stride + $x * $ArgbBytesPerPixel
            $alpha = $at + $ArgbAlphaOffset
            if ($after.Bytes[$alpha] -gt $Before.Bytes[$alpha]) { $after.Bytes[$alpha] = $Before.Bytes[$alpha] }
            if (-not $Foreground) { continue }
            $weight = Get-ForegroundWeight $Foreground $at
            if ($weight -gt 0) { Restore-ForegroundPixel $after.Bytes $Before.Bytes $at $weight }
        }
    }
    Write-ArgbPixels $Bitmap $after.Bytes
}

function Draw-DiagonalLine([System.Drawing.Bitmap]$Bitmap) {
    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    $pen = New-Object System.Drawing.Pen((ConvertFrom-SplitLineColor), [float](Get-DiagonalLineWidth $Bitmap.Width))
    try {
        $g.SmoothingMode = 'AntiAlias'
        $g.DrawLine($pen, [float]0, [float]$Bitmap.Height, [float]$Bitmap.Width, [float]0)
    }
    finally { $pen.Dispose(); $g.Dispose() }
}

function ConvertFrom-SplitLineColor {
    return [System.Drawing.ColorTranslator]::FromHtml($DiagonalSplit.LineColor)
}

# Triangle haut-gauche de $Lower remplacé par celui de $Upper (mêmes tailles) ; $Upper est laissée intacte
function Join-DiagonalHalves([System.Drawing.Bitmap]$Lower, [System.Drawing.Bitmap]$Upper) {
    if ($Lower.Width -ne $Upper.Width -or $Lower.Height -ne $Upper.Height) { throw 'Icône coupée : tailles différentes' }
    $g = [System.Drawing.Graphics]::FromImage($Lower)
    $triangle = New-UpperTrianglePath $Lower.Width $Lower.Height
    try {
        $g.SetClip($triangle)
        $g.CompositingMode = 'SourceCopy'   # les pixels transparents de $Upper remplacent ceux de $Lower
        $g.DrawImage($Upper, 0, 0, $Lower.Width, $Lower.Height)
    }
    finally { $triangle.Dispose(); $g.Dispose() }
}

# Trait noir en diagonale ; $Foreground = { First, Second } (pixels des deux icônes de base, même taille) ou $null
function Add-DiagonalLine([System.Drawing.Bitmap]$Bitmap, $Foreground) {
    $before = Read-ArgbPixels $Bitmap
    Draw-DiagonalLine $Bitmap
    Complete-DiagonalBand $Bitmap $before $Foreground
}

<#
    Compose en place sur $Lower (langue du texte) : le triangle haut-gauche reçoit $Upper (langue des voix), puis le
    trait noir, par-dessus tout (pastille pays de original-badges).
#>
function Add-DiagonalSplitToBitmap([System.Drawing.Bitmap]$Lower, [System.Drawing.Bitmap]$Upper) {
    Join-DiagonalHalves $Lower $Upper
    Add-DiagonalLine $Lower $null
}

# Pixels des deux icônes de base, par taille : { <taille> = { First, Second } } ; vide sans paire (logo sous le trait)
function Read-ForegroundSources([string[]]$Paths) {
    $bySize = @{}
    if (@($Paths).Count -ne 2) { return $bySize }
    $first = Read-IcoEntries $Paths[0]
    $second = Read-IcoEntries $Paths[1]
    try {
        foreach ($entry in $first) {
            $match = @($second | Where-Object { $_.Size -eq $entry.Size })
            if ($match.Count -eq 0) { continue }
            $bySize[$entry.Size] = [pscustomobject]@{ First = (Read-ArgbPixels $entry.Bitmap); Second = (Read-ArgbPixels $match[0].Bitmap) }
        }
    }
    finally { @($first) + @($second) | ForEach-Object { $_.Bitmap.Dispose() } }
    return $bySize
}

<#
    Deux .ico → un .ico coupé, taille par taille (tailles communes aux deux). $Split = { Upper, Lower, Destination,
    Foreground } : Upper = icône de la langue des voix, Lower = celle du texte, Foreground = les deux icônes de base du
    jeu (fond bleu, fond vert) pour garder logo et cadre au-dessus du trait, ou $null. Rend le chemin écrit.
#>
function Merge-DiagonalSplitIco($Split) {
    $upper = Read-IcoEntries $Split.Upper
    $lower = Read-IcoEntries $Split.Lower
    try {
        $upperBySize = @{}
        foreach ($entry in $upper) { $upperBySize[$entry.Size] = $entry.Bitmap }
        $entries = @($lower | Where-Object { $upperBySize.ContainsKey($_.Size) })
        if ($entries.Count -eq 0) { throw 'Icône coupée : aucune taille commune aux deux icônes' }
        $foreground = Read-ForegroundSources $Split.Foreground
        foreach ($entry in $entries) {
            Join-DiagonalHalves $entry.Bitmap $upperBySize[$entry.Size]
            Add-DiagonalLine $entry.Bitmap $foreground[$entry.Size]
        }
        Write-Ico $entries $Split.Destination
    }
    finally { @($upper) + @($lower) | ForEach-Object { $_.Bitmap.Dispose() } }
    return $Split.Destination
}

# Réglages du trait, pour l'empreinte des icônes composées : un changement de rendu change leur nom de fichier
function Get-DiagonalSplitKey {
    return ($DiagonalSplit.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
}
