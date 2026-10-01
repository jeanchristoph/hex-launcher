<#
.SYNOPSIS
    Génère les images de l'assistant d'installation depuis l'icône de l'installeur : tools\installer\wizard-corner.png
    et tools\installer\wizard-side.png, versionnées à côté de installer-logo.ico et lues par hex-launcher.iss.

.DESCRIPTION
    Source : tools\installer\installer-logo.ico (logo HL nu, centré, 90 % de la largeur — tools\make-logo-icon.ps1
    -Placement centered -LogoFill 0.90), dont la plus grande image est reprise.
      wizard-corner.png : coin haut-droit des pages intérieures (accord de licence…) ;
      wizard-side.png   : panneau gauche des pages d'accueil et de fin, à la place de l'image d'Inno Setup.
    À relancer après toute régénération de installer-logo.ico. Outil de développement, hors release.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-installer-images.ps1
#>
param(
    # Dossier de l'icône source et des images écrites (défaut : tools\installer)
    [string]$InstallerDir = (Join-Path $PSScriptRoot 'installer')
)

Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\lib\icon.lib.ps1')

# Part de la largeur de installer-logo.ico occupée par le logo (make-logo-icon -LogoFill 0.90, centré)
$InstallerIconLogoFill = 0.90

# Coin haut-droit : Inno étire l'image jusqu'au bord droit de la fenêtre, le logo s'en écarte donc davantage à droite
# qu'à gauche. Retours utilisateur : collé au bord à 100 %, trop petit à 50 %, puis « un poil plus grand, un peu plus
# de marge à droite » (84 % / 14 %), encore collé à droite (72 % / 26 %), puis L raccourci (retouche
# wizard-corner-short-l.png) → 70 % de la largeur, 28 % de marge à droite.
$InstallerWizardCorner = @{ LogoWidth = 0.70; RightMargin = 0.28 }

# Panneau gauche : 164 × 314 px d'Inno Setup (style modern) au double, pour rester net à 200 % ; fond bleu
# Panel du thème de l'assistant (app\lib\theme.lib.ps1), choisi par l'utilisateur à la place du noir ; logo HL sur 70 %
# de la largeur
$InstallerWizardSideSize       = @{ Width = 328; Height = 628 }
$InstallerWizardSideBackground = '#0F1620'
$InstallerWizardSideLogoWidth  = 0.70

# ---------------------------------------------------------------- Canevas (fonctions pures)

# Canevas carré de la taille de l'icône : logo à LogoWidth, calé à RightMargin du bord droit, centré en hauteur
function New-InstallerWizardCanvas([System.Drawing.Bitmap]$Logo) {
    $size    = $Logo.Width
    $scaled  = $size * $InstallerWizardCorner.LogoWidth / $InstallerIconLogoFill
    $iconGap = ($scaled - $size * $InstallerWizardCorner.LogoWidth) / 2
    $x       = $size * (1 - $InstallerWizardCorner.RightMargin) + $iconGap - $scaled
    $canvas  = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($Logo, [single]$x, [single](($size - $scaled) / 2), [single]$scaled, [single]$scaled)
    $g.Dispose()
    return $canvas
}

function New-InstallerWizardSideCanvas([System.Drawing.Bitmap]$Logo) {
    $width  = $InstallerWizardSideSize.Width
    $height = $InstallerWizardSideSize.Height
    $scaled = [int]($width * $InstallerWizardSideLogoWidth / $InstallerIconLogoFill)
    $canvas = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml($InstallerWizardSideBackground))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($Logo, [int](($width - $scaled) / 2), [int](($height - $scaled) / 2), $scaled, $scaled)
    $g.Dispose()
    return $canvas
}

# ---------------------------------------------------------------- Écriture

function Save-InstallerWizardImage([System.Drawing.Bitmap]$Canvas, [string]$Path) {
    $Canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $Canvas.Dispose()
    return $Path
}

# Écrit les deux images dans $Directory depuis la plus grande image de installer-logo.ico ; rend leurs chemins
function Export-InstallerWizardImages([string]$Directory) {
    $entries = @(Read-IcoEntries (Join-Path $Directory 'installer-logo.ico'))
    $largest = $entries | Sort-Object Size -Descending | Select-Object -First 1
    try {
        return [pscustomobject]@{
            Corner = Save-InstallerWizardImage (New-InstallerWizardCanvas $largest.Bitmap) (Join-Path $Directory 'wizard-corner.png')
            Side   = Save-InstallerWizardImage (New-InstallerWizardSideCanvas $largest.Bitmap) (Join-Path $Directory 'wizard-side.png')
        }
    }
    finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
}

# ---------------------------------------------------------------- Main

if ($MyInvocation.InvocationName -ne '.') {
    $images = Export-InstallerWizardImages $InstallerDir
    "OK : $($images.Corner)"
    "OK : $($images.Side)"
}
