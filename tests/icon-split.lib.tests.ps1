<#
.SYNOPSIS
    Tests Pester 3.4 de lib\icon-split.lib.ps1 — icône coupée en diagonale (voix en haut à gauche, texte en bas à droite).
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\icon-split.lib.ps1')

# Carré uni, coins bas-gauche et haut-droit transparents (comme le cadre arrondi des icônes du projet)
function New-TestSquare([int]$Size, [string]$Color) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml($Color))
    $g.Dispose()
    $corner = [int]($Size / 8)
    for ($i = 0; $i -lt $corner; $i++) {
        for ($j = 0; $j -lt $corner; $j++) {
            $bmp.SetPixel($i, $Size - 1 - $j, [System.Drawing.Color]::Transparent)
            $bmp.SetPixel($Size - 1 - $i, $j, [System.Drawing.Color]::Transparent)
        }
    }
    return $bmp
}

function Get-PixelHex([System.Drawing.Bitmap]$Bitmap, [int]$X, [int]$Y) {
    $c = $Bitmap.GetPixel($X, $Y)
    return '{0:X2}{1:X2}{2:X2}{3:X2}' -f $c.A, $c.R, $c.G, $c.B
}

function New-TestIco([string]$Name, [string]$Color, [int[]]$Sizes) {
    $path = Join-Path $TestDrive "$Name.ico"
    $entries = @($Sizes | ForEach-Object { [pscustomobject]@{ Size = $_; Bitmap = (New-TestSquare $_ $Color) } })
    Write-Ico $entries $path
    $entries | ForEach-Object { $_.Bitmap.Dispose() }
    return $path
}

Describe 'Add-DiagonalSplitToBitmap' {
    $upper = New-TestSquare 64 '#BC002D'   # voix : rouge
    $lower = New-TestSquare 64 '#002395'   # texte : bleu
    Add-DiagonalSplitToBitmap $lower $upper

    It 'place la langue des voix dans le triangle haut-gauche' {
        Get-PixelHex $lower 8 8 | Should Be 'FFBC002D'
    }

    It 'garde la langue du texte dans le triangle bas-droit' {
        Get-PixelHex $lower 56 56 | Should Be 'FF002395'
    }

    It 'trace un trait noir (anticrénelé) sur la diagonale bas-gauche → haut-droit' {
        $pixel = $lower.GetPixel(32, 31)
        $pixel.A | Should Be 255
        [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) | Should BeLessThan 64
    }

    It 'ne noircit pas les coins transparents traversés par la diagonale' {
        (Get-PixelHex $lower 1 62).Substring(0, 2) | Should Be '00'
        (Get-PixelHex $lower 62 1).Substring(0, 2) | Should Be '00'
    }

    It 'laisse intacte l''image de la langue des voix' {
        Get-PixelHex $upper 56 56 | Should Be 'FFBC002D'
    }

    It 'garde un trait visible à 16 px' {
        $small = New-TestSquare 16 '#002395'
        Add-DiagonalSplitToBitmap $small (New-TestSquare 16 '#BC002D')
        (Get-PixelHex $small 8 7).Substring(2) | Should Not Be '002395'
        (Get-PixelHex $small 8 7).Substring(2) | Should Not Be 'BC002D'
    }

    It 'refuse deux images de tailles différentes' {
        { Add-DiagonalSplitToBitmap (New-TestSquare 32 '#002395') (New-TestSquare 16 '#BC002D') } | Should Throw 'tailles différentes'
    }
}

Describe 'Merge-DiagonalSplitIco' {
    It 'compose chaque taille commune aux deux icônes' {
        $voice = New-TestIco 'voix' '#BC002D' @(64, 32, 16)
        $text  = New-TestIco 'texte' '#002395' @(64, 32)
        $destination = Join-Path $TestDrive 'coupee.ico'
        Merge-DiagonalSplitIco ([pscustomobject]@{ Upper = $voice; Lower = $text; Destination = $destination }) | Should Be $destination
        $entries = Read-IcoEntries $destination
        try {
            @($entries | ForEach-Object { $_.Size }) -join ',' | Should Be '64,32'
            Get-PixelHex $entries[0].Bitmap 8 8 | Should Be 'FFBC002D'
            Get-PixelHex $entries[0].Bitmap 56 56 | Should Be 'FF002395'
        }
        finally { $entries | ForEach-Object { $_.Bitmap.Dispose() } }
    }

    It 'refuse deux icônes sans taille commune' {
        $voice = New-TestIco 'voix-16' '#BC002D' @(16)
        $text  = New-TestIco 'texte-32' '#002395' @(32)
        { Merge-DiagonalSplitIco ([pscustomobject]@{ Upper = $voice; Lower = $text; Destination = (Join-Path $TestDrive 'x.ico') }) } | Should Throw 'aucune taille commune'
    }

    It 'échoue sur une icône absente' {
        { Merge-DiagonalSplitIco ([pscustomobject]@{ Upper = (Join-Path $TestDrive 'absente.ico'); Lower = (New-TestIco 't' '#002395' @(16)); Destination = (Join-Path $TestDrive 'y.ico') }) } | Should Throw
    }
}

Describe 'Get-DiagonalSplitKey' {
    It 'change dès qu''un réglage du trait change' {
        $before = Get-DiagonalSplitKey
        $DiagonalSplit = @{ LineWidth = 0.05; MinLineWidth = 1.0; LineColor = '#000000' }
        Get-DiagonalSplitKey | Should Not Be $before
    }
}
