<#
.SYNOPSIS
    Tests Pester 3.4 de lib\palette.lib.ps1 — palette réduite commune aux drapeaux et aux pastilles compagnon.
#>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\app\lib\palette.lib.ps1')

Describe 'ConvertTo-PaletteHex' {
    It 'rend une teinte de la palette inchangée' {
        foreach ($hex in $FlagPalette.Values) { ConvertTo-PaletteHex $hex | Should Be $hex }
    }

    It 'ramène les rouges des drapeaux et des pastilles au rouge de la palette' {
        foreach ($hex in '#EF4135', '#BC002D', '#E4103F', '#FE0000') { ConvertTo-PaletteHex $hex | Should Be $FlagPalette.Red }
    }

    It 'distingue bleu, marine et bleu ciel' {
        ConvertTo-PaletteHex '#0055A4' | Should Be $FlagPalette.Blue
        ConvertTo-PaletteHex '#3D3A69' | Should Be $FlagPalette.Navy
        ConvertTo-PaletteHex '#74ACDF' | Should Be $FlagPalette.SkyBlue
    }

    It 'ramène les clairs au blanc et les sombres au noir' {
        ConvertTo-PaletteHex '#ECEAE4' | Should Be $FlagPalette.White
        ConvertTo-PaletteHex '#0A0E14' | Should Be $FlagPalette.Black
    }

    It 'accepte une couleur en minuscules' {
        ConvertTo-PaletteHex '#ffce00' | Should Be $FlagPalette.Yellow
    }
}

Describe 'ConvertTo-MutedColor' {
    It 'ternit le blanc comme le voile GDI+ du générateur (mélange en lumière linéaire) : ni pur ni gris' {
        $muted = ConvertTo-MutedColor (ConvertFrom-HexColor '#FFFFFF')
        $muted.R | Should BeLessThan 240
        $muted.R | Should BeGreaterThan 215
        [Math]::Abs($muted.B - $muted.R) | Should BeLessThan 3
    }

    It 'désature un rouge pur sans le rendre gris' {
        $muted = ConvertTo-MutedColor (ConvertFrom-HexColor '#FF0000')
        ($muted.R - $muted.G) | Should BeGreaterThan 100
        $muted.R | Should BeLessThan 255
    }

    It 'rend une couleur opaque' {
        (ConvertTo-MutedColor (ConvertFrom-HexColor '#1F4E9C')).A | Should Be 255
    }
}

Describe 'ConvertTo-VeiledColor' {
    It 'voile sans désaturer : un rouge pur reste rouge, seulement assombri' {
        $veiled = ConvertTo-VeiledColor (ConvertFrom-HexColor '#FF0000')
        $veiled.R | Should BeLessThan 255
        $veiled.G | Should BeLessThan 30
        $veiled.B | Should BeLessThan 30
    }

    It 'donne à un blanc pur le même gris que le blanc d''un drapeau' {
        (ConvertTo-VeiledColor (ConvertFrom-HexColor '#FFFFFF')).ToArgb() | Should Be (ConvertTo-MutedPaletteColor '#FFFFFF').ToArgb()
    }
}

Describe 'ConvertTo-MutedPaletteColor' {
    It 'donne à une pastille blanche la même teinte qu''un drapeau blanc' {
        (ConvertTo-MutedPaletteColor '#ECEAE4').ToArgb() | Should Be (ConvertTo-MutedPaletteColor '#FFFFFF').ToArgb()
    }
}

Describe 'ConvertTo-PaletteColor' {
    It 'rend une couleur GDI+ opaque de la palette' {
        $color = ConvertTo-PaletteColor '#009246'
        $color.A | Should Be 255
        ConvertTo-HexColor $color | Should Be $FlagPalette.Green
    }
}
