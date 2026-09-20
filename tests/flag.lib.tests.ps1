<#
.SYNOPSIS
    Tests Pester 3.4 de lib\flag.lib.ps1 — drapeaux dessinés en GDI+, couleurs brutes ou passées par un résolveur.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\flag.lib.ps1')
. (Join-Path $here '..\app\lib\launch-config.lib.ps1')

function Get-PixelHex([System.Drawing.Bitmap]$Bitmap, [int]$X, [int]$Y) {
    $c = $Bitmap.GetPixel($X, $Y)
    return ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
}

Describe 'Catalogue des dessins' {
    It 'dessine chaque langue de locales.json' {
        $codes   = @(Read-JsonCatalog (Join-Path $here '..\app\locales.json') | ForEach-Object { $_.code })
        $missing = @($codes | Where-Object { -not (Get-FlagDrawing $_) })
        $missing -join ',' | Should Be ''
    }

    It 'rend null pour une langue sans dessin' {
        Get-FlagDrawing 'xx_XX' | Should BeNullOrEmpty
    }

    It 'liste les codes triés' {
        $codes = @(Get-FlagCodes)
        $codes.Count | Should Be $FlagDrawings.Count
        ($codes -join ',') | Should Be (($codes | Sort-Object) -join ',')
    }
}

Describe 'New-FlagRegion' {
    It 'couvre tout le carré sans retrait' {
        $r = New-FlagRegion 64
        $r.Left | Should Be 0
        $r.Right | Should Be 64
        $r.Width | Should Be 64
        $r.Cx | Should Be 32
    }

    It 'rentre du retrait demandé de chaque côté' {
        $r = New-FlagRegion 64 10
        $r.Left | Should Be 10
        $r.Bottom | Should Be 54
        $r.Height | Should Be 44
        $r.Size | Should Be 64
    }
}

Describe 'New-FlagBitmap' {
    It 'dessine le Japon en couleurs brutes : disque rouge officiel sur blanc' {
        $bmp = New-FlagBitmap (Get-FlagDrawing 'ja_JP') 64 (New-FlagRegion 64)
        try {
            Get-PixelHex $bmp 32 32 | Should Be '#BC002D'
            Get-PixelHex $bmp 2 2   | Should Be '#FFFFFF'
        } finally { $bmp.Dispose() }
    }

    It 'dessine la France en trois bandes verticales aux couleurs déclarées' {
        $bmp = New-FlagBitmap (Get-FlagDrawing 'fr_FR') 90 (New-FlagRegion 90)
        try {
            Get-PixelHex $bmp 10 45 | Should Be '#000091'
            Get-PixelHex $bmp 45 45 | Should Be '#FFFFFF'
            Get-PixelHex $bmp 80 45 | Should Be '#E1000F'
        } finally { $bmp.Dispose() }
    }

    It 'passe chaque couleur de remplissage par le résolveur donné, le temps du dessin seulement' {
        $resolver = { param($Hex) [System.Drawing.Color]::FromArgb(0, 128, 0) }
        $bmp = New-FlagBitmap (Get-FlagDrawing 'ja_JP') 32 (New-FlagRegion 32) $resolver
        try { Get-PixelHex $bmp 16 16 | Should Be '#008000' } finally { $bmp.Dispose() }
        $raw = New-FlagBitmap (Get-FlagDrawing 'ja_JP') 32 (New-FlagRegion 32)
        try { Get-PixelHex $raw 16 16 | Should Be '#BC002D' } finally { $raw.Dispose() }
    }

    It 'rend un bitmap carré 32 bits de la taille demandée' {
        $bmp = New-FlagBitmap (Get-FlagDrawing 'de_DE') 48 (New-FlagRegion 48)
        try {
            $bmp.Width | Should Be 48
            $bmp.Height | Should Be 48
            $bmp.PixelFormat | Should Be ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        } finally { $bmp.Dispose() }
    }
}
