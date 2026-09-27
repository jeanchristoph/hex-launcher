<#
.SYNOPSIS
    Icône coupée en diagonale : langue des voix en haut à gauche, langue du texte en bas à droite, trait noir entre les deux.

.DESCRIPTION
    Chargé par dot-sourcing (icon-badge.lib.ps1, create-shortcuts.ps1) :
        . (Join-Path $PSScriptRoot 'lib\icon-split.lib.ps1')

    La diagonale va du coin bas-gauche au coin haut-droit. Le trait est tracé puis ramené à l'alpha de l'image sur
    sa seule bande : il s'arrête net au bord du cadre, sans noircir les coins transparents, quel que soit le jeu
    d'icônes. Sert aux icônes .ico des jeux de fichiers (flat, classic) et à la pastille pays (original-badges).
#>

Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'icon.lib.ps1')

$DiagonalSplit = @{
    LineWidth    = 0.04   # trait, en fraction du côté
    MinLineWidth = 1.0    # px : le trait reste visible à 16 px
    LineColor    = '#000000'
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

# Sur la bande du trait, l'alpha ne dépasse jamais celui d'avant le trait : pas de noir hors du cadre
function Limit-DiagonalBandAlpha([System.Drawing.Bitmap]$Bitmap, $Before) {
    $after = Read-ArgbPixels $Bitmap
    $width = $Bitmap.Width; $height = $Bitmap.Height
    $reach = [int][Math]::Ceiling((Get-DiagonalLineWidth $width) * [Math]::Sqrt(2)) + 2
    for ($y = 0; $y -lt $height; $y++) {
        $center = [int](($height - $y) * $width / $height) - 1
        for ($x = [Math]::Max(0, $center - $reach); $x -le [Math]::Min($width - 1, $center + $reach); $x++) {
            $at = $y * $after.Stride + $x * $ArgbBytesPerPixel + $ArgbAlphaOffset
            if ($after.Bytes[$at] -gt $Before.Bytes[$at]) { $after.Bytes[$at] = $Before.Bytes[$at] }
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

<#
    Compose en place sur $Lower (langue du texte) : le triangle haut-gauche reçoit $Upper (langue des voix), puis le
    trait noir. Les deux images ont la même taille ; $Upper est laissée intacte.
#>
function Add-DiagonalSplitToBitmap([System.Drawing.Bitmap]$Lower, [System.Drawing.Bitmap]$Upper) {
    if ($Lower.Width -ne $Upper.Width -or $Lower.Height -ne $Upper.Height) { throw 'Icône coupée : tailles différentes' }
    $g = [System.Drawing.Graphics]::FromImage($Lower)
    $triangle = New-UpperTrianglePath $Lower.Width $Lower.Height
    try {
        $g.SetClip($triangle)
        $g.CompositingMode = 'SourceCopy'   # les pixels transparents de $Upper remplacent ceux de $Lower
        $g.DrawImage($Upper, 0, 0, $Lower.Width, $Lower.Height)
    }
    finally { $triangle.Dispose(); $g.Dispose() }
    $before = Read-ArgbPixels $Lower
    Draw-DiagonalLine $Lower
    Limit-DiagonalBandAlpha $Lower $before
}

<#
    Deux .ico → un .ico coupé, taille par taille (tailles communes aux deux). $Split = { Upper, Lower, Destination } :
    Upper = icône de la langue des voix, Lower = celle du texte. Rend le chemin écrit.
#>
function Merge-DiagonalSplitIco($Split) {
    $upper = Read-IcoEntries $Split.Upper
    $lower = Read-IcoEntries $Split.Lower
    try {
        $upperBySize = @{}
        foreach ($entry in $upper) { $upperBySize[$entry.Size] = $entry.Bitmap }
        $entries = @($lower | Where-Object { $upperBySize.ContainsKey($_.Size) })
        if ($entries.Count -eq 0) { throw 'Icône coupée : aucune taille commune aux deux icônes' }
        foreach ($entry in $entries) { Add-DiagonalSplitToBitmap $entry.Bitmap $upperBySize[$entry.Size] }
        Write-Ico $entries $Split.Destination
    }
    finally { @($upper) + @($lower) | ForEach-Object { $_.Bitmap.Dispose() } }
    return $Split.Destination
}

# Réglages du trait, pour l'empreinte des icônes composées : un changement de rendu change leur nom de fichier
function Get-DiagonalSplitKey {
    return ($DiagonalSplit.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
}
