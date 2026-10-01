<#
.SYNOPSIS
    Tests Pester 3.4 de tools\make-installer-images.ps1 — images de l'assistant d'installation (coin, panneau gauche).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\tools\make-installer-images.ps1')
$ProjectRoot = Split-Path $here -Parent

Describe 'Export-InstallerWizardImages' {
    It 'écrit les deux images de l''assistant en PNG à côté de l''icône de l''installeur' {
        Copy-Item (Join-Path $ProjectRoot 'tools\installer\installer-logo.ico') $TestDrive
        $images = Export-InstallerWizardImages $TestDrive
        $images.Corner | Should Be (Join-Path $TestDrive 'wizard-corner.png')
        $images.Side | Should Be (Join-Path $TestDrive 'wizard-side.png')
        $small = [System.Drawing.Image]::FromFile($images.Corner)
        try { $small.Width | Should Be 256 } finally { $small.Dispose() }
        $side = [System.Drawing.Image]::FromFile($images.Side)
        try { "$($side.Width)x$($side.Height)" | Should Be '328x628' } finally { $side.Dispose() }
    }

    It 'pose l''icône sur le fond bleu #0F1620 du panneau gauche, logo HL sur 70 % de la largeur' {
        $logo = New-Object System.Drawing.Bitmap(100, 100)
        $g = [System.Drawing.Graphics]::FromImage($logo); $g.Clear([System.Drawing.Color]::Gold); $g.Dispose()
        $canvas = New-InstallerWizardSideCanvas $logo
        try {
            $night = [System.Drawing.ColorTranslator]::FromHtml('#0F1620').ToArgb()
            foreach ($point in @(@(5, 5), @(15, 314), @(312, 314), @(164, 150), @(164, 478))) { $canvas.GetPixel($point[0], $point[1]).ToArgb() | Should Be $night }
            foreach ($point in @(@(45, 314), @(282, 314), @(164, 195), @(164, 432))) { $canvas.GetPixel($point[0], $point[1]).ToArgb() | Should Be ([System.Drawing.Color]::Gold.ToArgb()) }
        }
        finally { $canvas.Dispose(); $logo.Dispose() }
    }

    It 'pose le logo du coin haut-droit sur 70 %, bien plus loin du bord droit que du gauche' {
        # Icône de 100 px dont le logo (or) occupe 90 % centrés, comme installer-logo.ico
        $logo = New-Object System.Drawing.Bitmap(100, 100)
        $g = [System.Drawing.Graphics]::FromImage($logo); $g.FillRectangle([System.Drawing.Brushes]::Gold, 5, 5, 90, 90); $g.Dispose()
        $canvas = New-InstallerWizardCanvas $logo
        try {
            # Logo attendu de x = 2 à 72 (70 px), marge droite 28 px ; hauteur centrée de 15 à 85
            foreach ($point in @(@(4, 50), @(70, 50), @(50, 17), @(50, 83))) { $canvas.GetPixel($point[0], $point[1]).A | Should Be 255 }
            foreach ($point in @(@(74, 50), @(95, 50), @(50, 12), @(50, 88))) { $canvas.GetPixel($point[0], $point[1]).A | Should Be 0 }
        }
        finally { $canvas.Dispose(); $logo.Dispose() }
    }
}
